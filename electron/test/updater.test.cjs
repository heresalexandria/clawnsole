"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const updater = require("../lib/updater.cjs");

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
