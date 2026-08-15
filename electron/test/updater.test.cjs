"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const updater = require("../lib/updater.cjs");

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
