"use strict";

let electronApp = null;
try {
  const electron = require("electron");
  if (electron && typeof electron === "object") electronApp = electron.app;
} catch (error) {
  if (error.code !== "MODULE_NOT_FOUND") throw error;
}

const { execFile, spawn } = require("node:child_process");
const crypto = require("node:crypto");
const fs = require("node:fs");
const https = require("node:https");
const path = require("node:path");

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

function app() {
  if (!electronApp) throw new Error("The updater is only available inside Electron.");
  return electronApp;
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

function stateFile() {
  return path.join(app().getPath("userData"), "update-state.json");
}

function readState() {
  try {
    const value = JSON.parse(fs.readFileSync(stateFile(), "utf8"));
    return value && typeof value === "object" ? value : {};
  } catch {
    return {};
  }
}

function writeState(patch) {
  const file = stateFile();
  const next = { ...readState(), ...patch };
  try {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, `${JSON.stringify(next, null, 2)}\n`, { mode: 0o600 });
    fs.chmodSync(file, 0o600);
  } catch {
    // Losing an update timestamp only causes another harmless check.
  }
  return next;
}

function userAgent() {
  return `Clawnsole/${app().getVersion()} (+https://github.com/${REPO})`;
}

function request(url, { headers = {}, redirects = 5 } = {}) {
  return new Promise((resolve, reject) => {
    if (!allowedUrl(url)) {
      reject(new Error(`Refusing to fetch ${url}.`));
      return;
    }
    const outgoing = https.get(url, {
      headers: { "User-Agent": userAgent(), ...headers },
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
        resolve(request(target, { headers, redirects: redirects - 1 }));
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

async function getText(url, headers = {}) {
  const response = await request(url, { headers });
  const chunks = [];
  let bytes = 0;
  for await (const chunk of response) {
    bytes += chunk.length;
    if (bytes > 8 * 1024 * 1024) throw new Error("The update response was too large.");
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString("utf8");
}

async function latestRelease() {
  const raw = await getText(RELEASE_API, {
    Accept: "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
  });
  const release = JSON.parse(raw);
  if (!release || typeof release !== "object" || release.draft || release.prerelease) {
    throw new Error("GitHub did not return a stable Clawnsole release.");
  }
  return release;
}

let lastResult = null;

async function check({ force = false } = {}) {
  const current = app().getVersion();
  const state = readState();
  const stale = !state.lastCheckAt || Date.now() - state.lastCheckAt >= CHECK_INTERVAL_MS;
  if (!force && !stale) {
    return lastResult || { ok: true, current, available: false, skipped: true };
  }

  try {
    const release = await latestRelease();
    const latest = String(release.tag_name || "").replace(/^v/, "");
    const asset = assetFor(release.assets);
    const result = {
      ok: true,
      current,
      latest,
      available: isNewer(latest, current),
      installable: Boolean(asset) && app().isPackaged,
      asset,
      release,
      htmlUrl: allowedUrl(release.html_url) ? release.html_url : RELEASE_PAGE,
      checkedAt: Date.now(),
    };
    writeState({
      lastCheckAt: result.checkedAt,
      latestSeen: latest,
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
    writeState({ lastCheckAt: result.checkedAt, lastError: result.error });
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

async function expectedChecksum(release, assetName) {
  const sums = (Array.isArray(release.assets) ? release.assets : []).find(
    (asset) => asset?.name === "SHA256SUMS.txt",
  );
  if (!sums || !allowedUrl(sums.browser_download_url)) {
    throw new Error("This release has no trusted SHA256SUMS.txt asset.");
  }
  const expected = checksumFor(await getText(sums.browser_download_url), assetName);
  if (!expected) throw new Error(`SHA256SUMS.txt does not cover ${assetName}.`);
  return expected;
}

function downloadDirectory() {
  return path.join(app().getPath("temp"), "clawnsole-update");
}

async function download(result, onProgress = () => {}) {
  if (!result?.available || !result.asset || !result.release) {
    throw new Error("There is no Clawnsole update ready to download.");
  }
  if (!app().isPackaged) throw new Error("Development builds update with git, not in place.");
  if (!allowedUrl(result.asset.browser_download_url)) {
    throw new Error("GitHub returned an untrusted update URL.");
  }

  const expected = await expectedChecksum(result.release, result.asset.name);
  const directory = downloadDirectory();
  fs.rmSync(directory, { recursive: true, force: true });
  fs.mkdirSync(directory, { recursive: true });
  const destination = path.join(directory, path.basename(result.asset.name));
  const response = await request(result.asset.browser_download_url);
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
  writeState({ staged });
  return staged;
}

function run(command, arguments_) {
  return new Promise((resolve, reject) => {
    execFile(command, arguments_, { maxBuffer: 8 << 20 }, (error, stdout, stderr) => {
      if (error) {
        reject(new Error(`${command} failed: ${String(stderr || error.message).slice(-400)}`));
      } else {
        resolve(stdout);
      }
    });
  });
}

function installedBundle() {
  return path.resolve(process.execPath, "..", "..", "..");
}

async function install(staged) {
  if (!app().isPackaged) throw new Error("Development builds update with git, not in place.");
  if (!staged?.file || !fs.existsSync(staged.file)) {
    throw new Error("The verified update download is missing.");
  }
  const bundle = installedBundle();
  if (!bundle.endsWith(".app")) throw new Error(`Cannot locate the installed app at ${bundle}.`);
  fs.accessSync(path.dirname(bundle), fs.constants.W_OK);

  const directory = downloadDirectory();
  const unpacked = path.join(directory, "unpacked");
  fs.rmSync(unpacked, { recursive: true, force: true });
  fs.mkdirSync(unpacked, { recursive: true });
  await run("/usr/bin/ditto", ["-x", "-k", staged.file, unpacked]);
  const freshName = fs.readdirSync(unpacked).find((name) => name === "Clawnsole.app");
  if (!freshName) throw new Error("The update archive did not contain Clawnsole.app.");
  const fresh = path.join(unpacked, freshName);
  if (!fs.existsSync(path.join(fresh, "Contents", "Info.plist"))) {
    throw new Error("The downloaded Clawnsole app is incomplete.");
  }

  const script = path.join(directory, "swap.sh");
  fs.writeFileSync(script, `#!/bin/sh
set -u
pid="$1"; fresh="$2"; dest="$3"
for _ in $(seq 1 150); do
  kill -0 "$pid" 2>/dev/null || break
  sleep 0.2
done
rm -rf "$dest.old"
mv "$dest" "$dest.old" || exit 1
if ! /usr/bin/ditto "$fresh" "$dest"; then
  rm -rf "$dest"
  mv "$dest.old" "$dest"
  open "$dest"
  exit 1
fi
rm -rf "$dest.old"
xattr -dr com.apple.quarantine "$dest" 2>/dev/null
open "$dest"
`, { mode: 0o700 });
  const helper = spawn("/bin/sh", [script, String(process.pid), fresh, bundle], {
    detached: true,
    stdio: "ignore",
  });
  helper.unref();
  writeState({ staged: null, lastCheckAt: 0 });
  setTimeout(() => app().quit(), 400);
}

module.exports = {
  ALLOWED_HOSTS,
  CHECK_INTERVAL_MS,
  RELEASE_PAGE,
  allowedUrl,
  assetFor,
  check,
  checksumFor,
  compareVersions,
  download,
  install,
  isNewer,
  parseVersion,
};
