"use strict";

let electronApp = null;
try {
  const electron = require("electron");
  if (electron && typeof electron === "object") electronApp = electron.app;
} catch (error) {
  if (error.code !== "MODULE_NOT_FOUND") throw error;
}

const {
  execFile: executeFile,
  spawn: spawnProcess,
} = require("node:child_process");
const crypto = require("node:crypto");
const fs = require("node:fs");
const defaultHttps = require("node:https");
const path = require("node:path");
const {
  INSTALL_LOCATION_HELP,
  describeInstallFailure,
  isTranslocated,
} = require("./install-location.cjs");

const REPO = "heresalexandria/clawnsole";
const RELEASE_API = `https://api.github.com/repos/${REPO}/releases/latest`;
const RELEASE_PAGE = `https://github.com/${REPO}/releases/latest`;
const CHECK_INTERVAL_MS = 24 * 60 * 60 * 1000;
const ALLOWED_HOSTS = new Set([
  "api.github.com",
  "github.com",
  "objects.githubusercontent.com",
  "release-assets.githubusercontent.com",
]);
// The Apple team that signs every published Clawnsole bundle. CI refuses to
// publish a release signed by anyone else, and the updater refuses to
// install one.
const EXPECTED_TEAM_ID = "KMZ785G889";
const SWAP_RESULT_FILE = "update-result.json";
const CODESIGN = "/usr/bin/codesign";
const DITTO = "/usr/bin/ditto";

// The post-quit helper writes update-result.json beside the staged update so
// the next launch can report what happened. The previous bundle is reopened
// whenever it could not be replaced.
//
// Sparkle-style order: the fresh bundle's signature and Team ID were verified
// before this helper was spawned, so releasing it from quarantine is the very
// last step and only ever happens to a bundle that passed verification.
const SWAP_SCRIPT = `#!/bin/sh
set -u
pid="$1"; fresh="$2"; dest="$3"; result="$4"; version="$5"
report() {
  printf '{"ok":%s,"version":"%s","stage":"%s"}\\n' "$1" "$version" "$2" > "$result.tmp" \\
    && mv "$result.tmp" "$result"
}
for _ in $(seq 1 150); do
  kill -0 "$pid" 2>/dev/null || break
  sleep 0.2
done
rm -rf "$dest.old"
if ! mv "$dest" "$dest.old"; then
  report false move-aside
  open "$dest"
  exit 1
fi
if ! /usr/bin/ditto "$fresh" "$dest"; then
  rm -rf "$dest"
  mv "$dest.old" "$dest"
  report false copy
  open "$dest"
  exit 1
fi
rm -rf "$dest.old"
xattr -dr com.apple.quarantine "$dest" 2>/dev/null
report true installed
open "$dest"
`;

function app() {
  if (!electronApp) throw new Error("The updater is only available inside Electron.");
  return electronApp;
}

// Electron, the child-process runner, HTTPS, and the executable path are
// injectable so the download, verification, and install paths can run under
// plain Node tests.
function resolveDependencies(overrides = {}) {
  return {
    app: overrides.app ?? app(),
    execFile: overrides.execFile ?? executeFile,
    spawn: overrides.spawn ?? spawnProcess,
    https: overrides.https ?? defaultHttps,
    execPath: overrides.execPath ?? process.execPath,
  };
}

function allowedUrl(value) {
  try {
    const candidate = new URL(value);
    return candidate.protocol === "https:" && ALLOWED_HOSTS.has(candidate.hostname);
  } catch {
    return false;
  }
}

function parseVersion(value) {
  const match = /^v?(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$/.exec(String(value || "").trim());
  return match ? match.slice(1).map(Number) : null;
}

function compareVersions(left, right) {
  const a = parseVersion(left);
  const b = parseVersion(right);
  if (!a || !b) return null;
  for (let index = 0; index < 3; index += 1) {
    if (a[index] !== b[index]) return a[index] > b[index] ? 1 : -1;
  }
  return 0;
}

function isNewer(candidate, current) {
  return compareVersions(candidate, current) === 1;
}

function assetFor(assets, platform = process.platform, arch = process.arch) {
  if (platform !== "darwin") return null;
  const suffix = `-mac-${arch}.zip`;
  return (Array.isArray(assets) ? assets : []).find(
    (asset) => asset && typeof asset.name === "string" && asset.name.endsWith(suffix),
  ) || null;
}

function stateFile(electron) {
  return path.join(electron.getPath("userData"), "update-state.json");
}

function readState(electron) {
  try {
    const value = JSON.parse(fs.readFileSync(stateFile(electron), "utf8"));
    return value && typeof value === "object" ? value : {};
  } catch {
    return {};
  }
}

function writeState(electron, patch) {
  const file = stateFile(electron);
  const next = { ...readState(electron), ...patch };
  try {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, `${JSON.stringify(next, null, 2)}\n`, { mode: 0o600 });
    fs.chmodSync(file, 0o600);
  } catch {
    // Losing an update timestamp only causes another harmless check.
  }
  return next;
}

function userAgent(electron) {
  return `Clawnsole/${electron.getVersion()} (+https://github.com/${REPO})`;
}

function request(url, { headers = {}, redirects = 5, dependencies }) {
  return new Promise((resolve, reject) => {
    if (!allowedUrl(url)) {
      reject(new Error(`Refusing to fetch ${url}.`));
      return;
    }
    const outgoing = dependencies.https.get(url, {
      headers: { "User-Agent": userAgent(dependencies.app), ...headers },
      timeout: 30_000,
    }, (response) => {
      const status = response.statusCode || 0;
      if (status >= 300 && status < 400 && response.headers.location) {
        response.resume();
        if (redirects <= 0) {
          reject(new Error("The update download redirected too many times."));
          return;
        }
        const target = new URL(response.headers.location, url).toString();
        resolve(request(target, { headers, redirects: redirects - 1, dependencies }));
        return;
      }
      if (status !== 200) {
        response.resume();
        reject(new Error(`GitHub returned HTTP ${status}.`));
        return;
      }
      resolve(response);
    });
    outgoing.on("timeout", () => outgoing.destroy(new Error("The update request timed out.")));
    outgoing.on("error", reject);
  });
}

async function getText(url, headers, dependencies) {
  const response = await request(url, { headers, dependencies });
  const chunks = [];
  let bytes = 0;
  for await (const chunk of response) {
    bytes += chunk.length;
    if (bytes > 8 * 1024 * 1024) throw new Error("The update response was too large.");
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString("utf8");
}

async function latestRelease(dependencies) {
  const raw = await getText(RELEASE_API, {
    Accept: "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
  }, dependencies);
  const release = JSON.parse(raw);
  if (!release || typeof release !== "object" || release.draft || release.prerelease) {
    throw new Error("GitHub did not return a stable Clawnsole release.");
  }
  return release;
}

let lastResult = null;

function cachedResult(current, state, { isPackaged = app().isPackaged } = {}) {
  if (state.lastError) {
    return {
      ok: false,
      current,
      available: false,
      error: state.lastError,
      htmlUrl: RELEASE_PAGE,
      skipped: true,
    };
  }
  const latest = typeof state.latestSeen === "string" ? state.latestSeen : null;
  const available = latest ? isNewer(latest, current) : false;
  return {
    ok: true,
    current,
    latest,
    available,
    // Older updater state predates this field. A packaged macOS build may
    // still advertise its cached release; starting the update re-checks and
    // validates the architecture-specific asset before downloading anything.
    installable: state.latestHasAsset == null
      ? Boolean(available && isPackaged)
      : Boolean(available && isPackaged && state.latestHasAsset === true),
    htmlUrl: allowedUrl(state.latestUrl) ? state.latestUrl : RELEASE_PAGE,
    skipped: true,
  };
}

async function check({ force = false, dependencies: overrides } = {}) {
  const dependencies = resolveDependencies(overrides);
  const electron = dependencies.app;
  const current = electron.getVersion();
  const state = readState(electron);
  const stale = !state.lastCheckAt || Date.now() - state.lastCheckAt >= CHECK_INTERVAL_MS;
  if (!force && !stale) {
    return lastResult || cachedResult(current, state, { isPackaged: electron.isPackaged });
  }

  try {
    const release = await latestRelease(dependencies);
    const latest = String(release.tag_name || "").replace(/^v/, "");
    const asset = assetFor(release.assets);
    const result = {
      ok: true,
      current,
      latest,
      available: isNewer(latest, current),
      installable: Boolean(asset) && electron.isPackaged,
      asset,
      release,
      htmlUrl: allowedUrl(release.html_url) ? release.html_url : RELEASE_PAGE,
      checkedAt: Date.now(),
    };
    writeState(electron, {
      lastCheckAt: result.checkedAt,
      latestSeen: latest,
      latestHasAsset: Boolean(asset),
      latestUrl: result.htmlUrl,
      lastError: null,
    });
    lastResult = result;
    return result;
  } catch (error) {
    const result = {
      ok: false,
      current,
      available: false,
      error: error instanceof Error ? error.message : String(error),
      checkedAt: Date.now(),
      htmlUrl: RELEASE_PAGE,
    };
    writeState(electron, { lastCheckAt: result.checkedAt, lastError: result.error });
    lastResult = result;
    return result;
  }
}

function checksumFor(text, assetName) {
  for (const line of String(text || "").split("\n")) {
    const match = /^([0-9a-f]{64})\s+\*?(.+?)\s*$/i.exec(line.trim());
    if (match && path.basename(match[2]) === assetName) return match[1].toLowerCase();
  }
  return null;
}

async function expectedChecksum(release, assetName, dependencies) {
  const sums = (Array.isArray(release.assets) ? release.assets : []).find(
    (asset) => asset?.name === "SHA256SUMS.txt",
  );
  if (!sums || !allowedUrl(sums.browser_download_url)) {
    throw new Error("This release has no trusted SHA256SUMS.txt asset.");
  }
  const expected = checksumFor(
    await getText(sums.browser_download_url, {}, dependencies),
    assetName,
  );
  if (!expected) throw new Error(`SHA256SUMS.txt does not cover ${assetName}.`);
  return expected;
}

function downloadDirectory(electron) {
  return path.join(electron.getPath("temp"), "clawnsole-update");
}

async function download(result, onProgress = () => {}, overrides = {}) {
  const dependencies = resolveDependencies(overrides);
  const electron = dependencies.app;
  if (!result?.available || !result.asset || !result.release) {
    throw new Error("There is no Clawnsole update ready to download.");
  }
  if (!electron.isPackaged) throw new Error("Development builds update with git, not in place.");
  if (!allowedUrl(result.asset.browser_download_url)) {
    throw new Error("GitHub returned an untrusted update URL.");
  }

  const expected = await expectedChecksum(result.release, result.asset.name, dependencies);
  const directory = downloadDirectory(electron);
  fs.rmSync(directory, { recursive: true, force: true });
  fs.mkdirSync(directory, { recursive: true });
  const destination = path.join(directory, path.basename(result.asset.name));
  const response = await request(result.asset.browser_download_url, { dependencies });
  const total = Number(response.headers["content-length"]) || Number(result.asset.size) || 0;
  const hash = crypto.createHash("sha256");
  let received = 0;
  let lastProgress = 0;

  await new Promise((resolve, reject) => {
    const output = fs.createWriteStream(destination, { mode: 0o600 });
    response.on("data", (chunk) => {
      received += chunk.length;
      hash.update(chunk);
      const now = Date.now();
      if (now - lastProgress >= 200) {
        lastProgress = now;
        onProgress({ received, total, fraction: total ? received / total : null });
      }
    });
    response.on("error", reject);
    output.on("error", reject);
    output.on("finish", resolve);
    response.pipe(output);
  });

  const actual = hash.digest("hex");
  if (actual !== expected) {
    fs.rmSync(directory, { recursive: true, force: true });
    throw new Error("The downloaded update failed checksum verification.");
  }
  onProgress({ received, total, fraction: 1 });
  const staged = { file: destination, version: result.latest, sha256: actual };
  writeState(electron, { staged });
  return staged;
}

function run(execFile, command, arguments_) {
  return new Promise((resolve, reject) => {
    execFile(command, arguments_, { maxBuffer: 8 << 20 }, (error, stdout, stderr) => {
      if (error) {
        reject(new Error(`${command} failed: ${String(stderr || error.message).slice(-400)}`));
      } else {
        resolve({ stdout: String(stdout || ""), stderr: String(stderr || "") });
      }
    });
  });
}

function installedBundle(execPath = process.execPath) {
  return path.resolve(execPath, "..", "..", "..");
}

function teamIdentifierFrom(output) {
  const match = /^TeamIdentifier=(.*)$/m.exec(String(output || ""));
  return match ? match[1].trim() : null;
}

// The checksum proves the archive is the one CI published; the signature and
// Team ID prove the app inside it was built and signed by Clawnsole's Apple
// team. codesign prints its description on stderr, so both streams are read.
async function verifyBundleSignature(bundle, { execFile = executeFile } = {}) {
  try {
    await run(execFile, CODESIGN, ["--verify", "--deep", "--strict", bundle]);
  } catch (error) {
    throw new Error(
      `The downloaded update failed signature verification: ${error.message}`,
    );
  }
  const { stdout, stderr } = await run(execFile, CODESIGN, ["-d", "--verbose=2", bundle]);
  const teamIdentifier = teamIdentifierFrom(`${stderr}\n${stdout}`);
  if (teamIdentifier !== EXPECTED_TEAM_ID) {
    throw new Error(
      "The downloaded update was not signed by Clawnsole's Apple team "
        + `(expected ${EXPECTED_TEAM_ID}, found ${teamIdentifier || "no team"}).`,
    );
  }
  return { teamIdentifier };
}

async function install(staged, overrides = {}) {
  const dependencies = resolveDependencies(overrides);
  const { app: electron, execFile, spawn } = dependencies;
  if (!electron.isPackaged) throw new Error("Development builds update with git, not in place.");
  if (!staged?.file || !fs.existsSync(staged.file)) {
    throw new Error("The verified update download is missing.");
  }
  const bundle = installedBundle(dependencies.execPath);
  if (!bundle.endsWith(".app")) throw new Error(`Cannot locate the installed app at ${bundle}.`);
  if (isTranslocated(bundle)) throw new Error(INSTALL_LOCATION_HELP);
  try {
    fs.accessSync(path.dirname(bundle), fs.constants.W_OK);
  } catch (error) {
    throw new Error(describeInstallFailure(error, bundle));
  }

  const directory = downloadDirectory(electron);
  const unpacked = path.join(directory, "unpacked");
  fs.rmSync(unpacked, { recursive: true, force: true });
  fs.mkdirSync(unpacked, { recursive: true });
  await run(execFile, DITTO, ["-x", "-k", staged.file, unpacked]);
  const freshName = fs.readdirSync(unpacked).find((name) => name === "Clawnsole.app");
  if (!freshName) throw new Error("The update archive did not contain Clawnsole.app.");
  const fresh = path.join(unpacked, freshName);
  if (!fs.existsSync(path.join(fresh, "Contents", "Info.plist"))) {
    throw new Error("The downloaded Clawnsole app is incomplete.");
  }
  // Nothing moves into place, and nothing leaves quarantine, until the fresh
  // bundle's signature and Team ID both check out.
  await verifyBundleSignature(fresh, { execFile });

  const script = path.join(directory, "swap.sh");
  fs.writeFileSync(script, SWAP_SCRIPT, { mode: 0o700 });
  const resultFile = path.join(directory, SWAP_RESULT_FILE);
  fs.rmSync(resultFile, { force: true });
  const version = String(staged.version || "").replace(/[^0-9A-Za-z.+-]/g, "");
  const helper = spawn(
    "/bin/sh",
    [script, String(process.pid), fresh, bundle, resultFile, version],
    { detached: true, stdio: "ignore" },
  );
  helper.unref();
  writeState(electron, { staged: null, lastCheckAt: 0 });
  setTimeout(() => electron.quit(), 400);
}

function swapResultMessage({ ok, version, stage, bundle }) {
  if (ok) return `Clawnsole was updated to ${version}.`;
  if (stage === "move-aside") {
    return `Clawnsole could not replace itself in ${path.dirname(bundle)}, so `
      + `${version} was not installed. ${INSTALL_LOCATION_HELP}`;
  }
  return `Clawnsole could not finish installing ${version}, so the previous `
    + "version was kept. Check for updates to try again.";
}

// Reads and removes the helper's report from the last install attempt, if
// there is one, so a launch can surface it exactly once.
function consumeSwapResult(overrides = {}) {
  const dependencies = resolveDependencies(overrides);
  const file = path.join(downloadDirectory(dependencies.app), SWAP_RESULT_FILE);
  let source;
  try {
    source = fs.readFileSync(file, "utf8");
  } catch {
    return null;
  }
  fs.rmSync(file, { force: true });
  let payload;
  try {
    payload = JSON.parse(source);
  } catch {
    return null;
  }
  if (!payload || typeof payload !== "object") return null;
  const result = {
    ok: payload.ok === true,
    version: typeof payload.version === "string" && payload.version
      ? payload.version
      : "the update",
    stage: typeof payload.stage === "string" ? payload.stage : "unknown",
  };
  return {
    ...result,
    message: swapResultMessage({
      ...result,
      bundle: installedBundle(dependencies.execPath),
    }),
  };
}

// The renderer only needs a compact, serializable summary of a check.
function summarize(result) {
  return {
    ok: Boolean(result?.ok),
    current: result?.current ?? null,
    latest: result?.latest ?? null,
    available: Boolean(result?.available),
    installable: Boolean(result?.installable),
    error: result?.error ?? null,
    htmlUrl: result?.htmlUrl ?? RELEASE_PAGE,
  };
}

module.exports = {
  ALLOWED_HOSTS,
  CHECK_INTERVAL_MS,
  EXPECTED_TEAM_ID,
  RELEASE_PAGE,
  SWAP_RESULT_FILE,
  SWAP_SCRIPT,
  allowedUrl,
  assetFor,
  cachedResult,
  check,
  checksumFor,
  compareVersions,
  consumeSwapResult,
  download,
  install,
  installedBundle,
  isNewer,
  parseVersion,
  summarize,
  teamIdentifierFrom,
  verifyBundleSignature,
};
