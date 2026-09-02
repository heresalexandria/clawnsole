"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const { EventEmitter } = require("node:events");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { Readable } = require("node:stream");
const test = require("node:test");
const updater = require("../lib/updater.cjs");
const {
  INSTALL_LOCATION_HELP,
} = require("../lib/install-location.cjs");

const VERSION = "1.2.3";
const ASSET_NAME = `Clawnsole-${VERSION}-mac-arm64.zip`;
const DOWNLOAD_BASE =
  `https://github.com/heresalexandria/clawnsole/releases/download/v${VERSION}`;
const ASSET_URL = `${DOWNLOAD_BASE}/${ASSET_NAME}`;
const SUMS_URL = `${DOWNLOAD_BASE}/SHA256SUMS.txt`;
const ARCHIVE = "a signed Clawnsole archive";
const ARCHIVE_SHA256 = crypto.createHash("sha256").update(ARCHIVE).digest("hex");

// Electron's app, HTTPS, the child-process runner, and the running
// executable are all injected, so the download, verification, and install
// paths run under plain Node.
function electronStub(t, { bundleDirectory } = {}) {
  const directories = [];
  const make = (label) => {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), label));
    directories.push(directory);
    return directory;
  };
  const temp = make("clawnsole-updater-temp-");
  const userData = make("clawnsole-updater-data-");
  const applications = bundleDirectory ?? make("clawnsole-updater-apps-");
  t.after(() => {
    for (const directory of directories) {
      fs.rmSync(directory, { recursive: true, force: true });
    }
  });
  const quits = [];
  return {
    applications,
    quits,
    temp,
    userData,
    app: {
      isPackaged: true,
      getVersion: () => "1.0.0",
      getPath: (name) => (name === "temp" ? temp : userData),
      quit: () => quits.push("quit"),
    },
    execPath: path.join(
      applications,
      "Clawnsole.app",
      "Contents",
      "MacOS",
      "Clawnsole",
    ),
  };
}

function httpsStub(bodies) {
  return {
    get(url, _options, callback) {
      const outgoing = new EventEmitter();
      outgoing.destroy = () => {};
      const body = bodies[String(url)];
      queueMicrotask(() => {
        const payload = Buffer.from(body ?? "");
        const response = Readable.from([payload]);
        response.statusCode = body === undefined ? 404 : 200;
        response.headers = { "content-length": String(payload.length) };
        callback(response);
      });
      return outgoing;
    },
  };
}

function downloadResult() {
  return {
    available: true,
    latest: VERSION,
    asset: {
      name: ASSET_NAME,
      browser_download_url: ASSET_URL,
      size: Buffer.byteLength(ARCHIVE),
    },
    release: {
      assets: [
        { name: "SHA256SUMS.txt", browser_download_url: SUMS_URL },
        { name: ASSET_NAME, browser_download_url: ASSET_URL },
      ],
    },
  };
}

// Stands in for ditto and codesign. ditto materializes the unpacked bundle;
// codesign reports verification and the Team ID the way the real tool does,
// on stderr.
function toolStub({ signatureValid = true, teamIdentifier = "KMZ785G889" } = {}) {
  const calls = [];
  return {
    calls,
    execFile(command, args, _options, callback) {
      calls.push([path.basename(command), ...args]);
      if (command.endsWith("ditto")) {
        const contents = path.join(args.at(-1), "Clawnsole.app", "Contents");
        fs.mkdirSync(contents, { recursive: true });
        fs.writeFileSync(path.join(contents, "Info.plist"), "<plist/>");
        callback(null, "", "");
        return;
      }
      if (args[0] === "--verify") {
        if (signatureValid) callback(null, "", "");
        else {
          callback(
            new Error("exited with code 1"),
            "",
            "code object is not signed at all",
          );
        }
        return;
      }
      callback(
        null,
        "",
        `Identifier=ai.clawnsole.desktop\nTeamIdentifier=${teamIdentifier}\n`
          + "Sealed Resources version=2\n",
      );
    },
  };
}

function spawnStub() {
  const calls = [];
  return {
    calls,
    spawn(command, args, options) {
      calls.push({ command, args, options });
      return { unref() {} };
    },
  };
}

function stageDownload(electron, sum = ARCHIVE_SHA256) {
  return updater.download(downloadResult(), () => {}, {
    app: electron.app,
    https: httpsStub({
      [SUMS_URL]: `${sum}  ${ASSET_NAME}\n`,
      [ASSET_URL]: ARCHIVE,
    }),
  });
}

test("check results summarize into a compact renderer payload", () => {
  const summary = updater.summarize({
    ok: true,
    current: "0.4.0",
    latest: "0.5.0",
    available: true,
    installable: true,
    htmlUrl: "https://github.com/heresalexandria/clawnsole/releases/tag/v0.5.0",
    asset: { name: "Clawnsole-0.5.0-mac-arm64.zip", secret: "not for renderers" },
    release: { body: "notes" },
  });
  assert.deepEqual(summary, {
    ok: true,
    current: "0.4.0",
    latest: "0.5.0",
    available: true,
    installable: true,
    error: null,
    htmlUrl: "https://github.com/heresalexandria/clawnsole/releases/tag/v0.5.0",
  });
  assert.equal(updater.summarize(null).ok, false);
  assert.equal(updater.summarize(undefined).htmlUrl, updater.RELEASE_PAGE);
});

test("a throttled startup restores the last persisted update", () => {
  const cached = updater.cachedResult("0.10.1", {
    latestSeen: "0.11.0",
    latestUrl: "https://github.com/heresalexandria/clawnsole/releases/tag/v0.11.0",
  }, { isPackaged: true });
  assert.deepEqual(cached, {
    ok: true,
    current: "0.10.1",
    latest: "0.11.0",
    available: true,
    installable: true,
    htmlUrl: "https://github.com/heresalexandria/clawnsole/releases/tag/v0.11.0",
    skipped: true,
  });

  assert.equal(updater.cachedResult("0.11.0", {
    latestSeen: "0.11.0",
    latestHasAsset: true,
  }, { isPackaged: true }).available, false);
});

test("semantic versions compare numerically", () => {
  assert.deepEqual(updater.parseVersion("v1.2.3"), [1, 2, 3]);
  assert.equal(updater.compareVersions("0.10.0", "0.9.0"), 1);
  assert.equal(updater.compareVersions("0.9.0", "0.10.0"), -1);
  assert.equal(updater.compareVersions("invalid", "0.10.0"), null);
  assert.equal(updater.isNewer("1.0.0", "0.99.0"), true);
});

test("the updater selects only this Mac architecture's zip", () => {
  const assets = [
    { name: "Clawnsole-1.2.3-mac-arm64.dmg" },
    { name: "Clawnsole-1.2.3-mac-arm64.zip" },
    { name: "Clawnsole-1.2.3-mac-x64.zip" },
    { name: "Clawnsole-1.2.3-ios.ipa" },
  ];
  assert.equal(
    updater.assetFor(assets, "darwin", "arm64").name,
    "Clawnsole-1.2.3-mac-arm64.zip",
  );
  assert.equal(
    updater.assetFor(assets, "darwin", "x64").name,
    "Clawnsole-1.2.3-mac-x64.zip",
  );
  assert.equal(updater.assetFor(assets, "linux", "arm64"), null);
});

test("update URLs are limited to GitHub TLS hosts", () => {
  assert.equal(updater.allowedUrl(
    "https://api.github.com/repos/heresalexandria/clawnsole/releases/latest",
  ), true);
  assert.equal(updater.allowedUrl(
    "https://release-assets.githubusercontent.com/github-production-release-asset/x",
  ), true);
  for (const value of [
    "http://github.com/heresalexandria/clawnsole",
    "https://github.com.evil.example/update.zip",
    "file:///tmp/update.zip",
    "javascript:alert(1)",
  ]) {
    assert.equal(updater.allowedUrl(value), false, value);
  }
});

test("checksum lookup is exact by release asset basename", () => {
  const wanted = "a".repeat(64);
  const other = "b".repeat(64);
  const sums = `${other}  Clawnsole-1.2.3-mac-x64.zip\n${wanted} *Clawnsole-1.2.3-mac-arm64.zip\n`;
  assert.equal(
    updater.checksumFor(sums, "Clawnsole-1.2.3-mac-arm64.zip"),
    wanted,
  );
  assert.equal(updater.checksumFor(sums, "Clawnsole-1.2.4-mac-arm64.zip"), null);
});

test("a download that matches SHA256SUMS.txt is staged", async (t) => {
  const electron = electronStub(t);
  const progress = [];
  const staged = await updater.download(downloadResult(), (event) => {
    progress.push(event);
  }, {
    app: electron.app,
    https: httpsStub({
      [SUMS_URL]: `${ARCHIVE_SHA256}  ${ASSET_NAME}\n`,
      [ASSET_URL]: ARCHIVE,
    }),
  });

  assert.equal(staged.version, VERSION);
  assert.equal(staged.sha256, ARCHIVE_SHA256);
  assert.equal(fs.readFileSync(staged.file, "utf8"), ARCHIVE);
  assert.equal(progress.at(-1).fraction, 1);
  const state = JSON.parse(
    fs.readFileSync(path.join(electron.userData, "update-state.json"), "utf8"),
  );
  assert.equal(state.staged.sha256, ARCHIVE_SHA256);
});

test("a mismatched checksum is refused and the download discarded", async (t) => {
  const electron = electronStub(t);
  await assert.rejects(
    () => stageDownload(electron, "c".repeat(64)),
    /failed checksum verification/,
  );
  assert.equal(
    fs.existsSync(path.join(electron.temp, "clawnsole-update")),
    false,
  );
});

test("a release without SHA256SUMS.txt is never downloaded", async (t) => {
  const electron = electronStub(t);
  const result = downloadResult();
  result.release.assets = [
    { name: ASSET_NAME, browser_download_url: ASSET_URL },
  ];
  await assert.rejects(
    () => updater.download(result, () => {}, {
      app: electron.app,
      https: httpsStub({ [ASSET_URL]: ARCHIVE }),
    }),
    /no trusted SHA256SUMS\.txt/,
  );
});

test("the Team ID is read from codesign's description", () => {
  assert.equal(updater.EXPECTED_TEAM_ID, "KMZ785G889");
  assert.equal(
    updater.teamIdentifierFrom(
      "Identifier=ai.clawnsole.desktop\nTeamIdentifier=KMZ785G889\nSealed=2\n",
    ),
    "KMZ785G889",
  );
  assert.equal(updater.teamIdentifierFrom("TeamIdentifier=not set"), "not set");
  assert.equal(updater.teamIdentifierFrom("Identifier=x"), null);
  assert.equal(updater.teamIdentifierFrom(""), null);
});

test("a bundle signed by Clawnsole's Apple team verifies", async () => {
  const tools = toolStub();
  assert.deepEqual(
    await updater.verifyBundleSignature("/tmp/Clawnsole.app", {
      execFile: tools.execFile,
    }),
    { teamIdentifier: "KMZ785G889" },
  );
  assert.deepEqual(tools.calls, [
    ["codesign", "--verify", "--deep", "--strict", "/tmp/Clawnsole.app"],
    ["codesign", "-d", "--verbose=2", "/tmp/Clawnsole.app"],
  ]);
});

test("a broken signature stops verification before the Team ID", async () => {
  const tools = toolStub({ signatureValid: false });
  await assert.rejects(
    () => updater.verifyBundleSignature("/tmp/Clawnsole.app", {
      execFile: tools.execFile,
    }),
    /failed signature verification/,
  );
  assert.equal(tools.calls.length, 1);
});

test("a bundle from another Apple team is refused", async () => {
  for (const teamIdentifier of ["9Z9Z9Z9Z9Z", "not set"]) {
    await assert.rejects(
      () => updater.verifyBundleSignature("/tmp/Clawnsole.app", {
        execFile: toolStub({ teamIdentifier }).execFile,
      }),
      (error) => {
        assert.match(error.message, /not signed by Clawnsole's Apple team/);
        assert.match(error.message, /KMZ785G889/);
        return true;
      },
    );
  }
});

test("a verified update is handed to the post-quit swap helper", async (t) => {
  const electron = electronStub(t);
  const staged = await stageDownload(electron);
  const tools = toolStub();
  const spawner = spawnStub();

  await updater.install(staged, {
    app: electron.app,
    execFile: tools.execFile,
    spawn: spawner.spawn,
    execPath: electron.execPath,
  });

  const commands = tools.calls.map((call) => call.join(" "));
  assert.equal(commands.length, 3);
  assert.match(commands[0], /^ditto -x -k /);
  assert.match(commands[1], /^codesign --verify --deep --strict /);
  assert.match(commands[2], /^codesign -d --verbose=2 /);

  assert.equal(spawner.calls.length, 1);
  const [script, pid, fresh, destination, resultFile, version] =
    spawner.calls[0].args;
  assert.equal(spawner.calls[0].command, "/bin/sh");
  assert.equal(spawner.calls[0].options.detached, true);
  assert.equal(pid, String(process.pid));
  assert.equal(destination, path.join(electron.applications, "Clawnsole.app"));
  assert.equal(fresh.endsWith(path.join("unpacked", "Clawnsole.app")), true);
  assert.equal(version, VERSION);
  assert.equal(path.basename(resultFile), "update-result.json");
  assert.equal(fs.statSync(script).mode & 0o777, 0o700);

  const state = JSON.parse(
    fs.readFileSync(path.join(electron.userData, "update-state.json"), "utf8"),
  );
  assert.equal(state.staged, null);
});

// Sparkle's order: nothing is released from quarantine until the copy of a
// verified bundle has succeeded.
test("the swap helper only clears quarantine after a successful copy", () => {
  const script = updater.SWAP_SCRIPT;
  assert.ok(script.indexOf("/usr/bin/ditto") < script.indexOf("xattr -dr"));
  assert.ok(script.indexOf("xattr -dr") < script.indexOf("report true"));
  assert.match(script, /com\.apple\.quarantine/);
  assert.match(script, /mv "\$dest\.old" "\$dest"/);
});

test("an unverifiable download never reaches the swap helper", async (t) => {
  const electron = electronStub(t);
  const staged = await stageDownload(electron);

  for (const [options, expected] of [
    [{ signatureValid: false }, /failed signature verification/],
    [{ teamIdentifier: "9Z9Z9Z9Z9Z" }, /not signed by Clawnsole's Apple team/],
  ]) {
    const spawner = spawnStub();
    await assert.rejects(
      () => updater.install(staged, {
        app: electron.app,
        execFile: toolStub(options).execFile,
        spawn: spawner.spawn,
        execPath: electron.execPath,
      }),
      expected,
    );
    assert.deepEqual(spawner.calls, []);
  }
});

test("a translocated bundle is told where to move instead", async (t) => {
  const electron = electronStub(t);
  const staged = await stageDownload(electron);
  const spawner = spawnStub();

  await assert.rejects(
    () => updater.install(staged, {
      app: electron.app,
      execFile: toolStub().execFile,
      spawn: spawner.spawn,
      execPath: path.join(
        "/private/var/folders/z9/AppTranslocation/1B2C/d",
        "Clawnsole.app",
        "Contents",
        "MacOS",
        "Clawnsole",
      ),
    }),
    new RegExp(INSTALL_LOCATION_HELP),
  );
  assert.deepEqual(spawner.calls, []);
});

test("the swap helper's report is surfaced once and then cleared", (t) => {
  const electron = electronStub(t);
  const directory = path.join(electron.temp, "clawnsole-update");
  const file = path.join(directory, "update-result.json");
  fs.mkdirSync(directory, { recursive: true });
  const dependencies = { app: electron.app, execPath: electron.execPath };

  fs.writeFileSync(
    file,
    JSON.stringify({ ok: true, version: VERSION, stage: "installed" }),
  );
  assert.deepEqual(updater.consumeSwapResult(dependencies), {
    ok: true,
    version: VERSION,
    stage: "installed",
    message: `Clawnsole was updated to ${VERSION}.`,
  });
  assert.equal(fs.existsSync(file), false);
  assert.equal(updater.consumeSwapResult(dependencies), null);

  fs.writeFileSync(
    file,
    JSON.stringify({ ok: false, version: VERSION, stage: "move-aside" }),
  );
  const blocked = updater.consumeSwapResult(dependencies);
  assert.equal(blocked.ok, false);
  assert.match(blocked.message, new RegExp(INSTALL_LOCATION_HELP));

  fs.writeFileSync(file, "not json");
  assert.equal(updater.consumeSwapResult(dependencies), null);
});
