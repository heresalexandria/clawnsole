"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");

const {
  INSTALL_LOCATION_FILE,
  INSTALL_LOCATION_HELP,
  applicationsMoveDeclined,
  describeInstallFailure,
  isTranslocated,
  rememberApplicationsMoveDeclined,
} = require("../lib/install-location.cjs");

function temporaryDirectory(t) {
  const directory = fs.mkdtempSync(
    path.join(os.tmpdir(), "clawnsole-install-location-"),
  );
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  return directory;
}

test("a Gatekeeper translocated bundle is recognized", () => {
  assert.equal(
    isTranslocated(
      "/private/var/folders/z9/AppTranslocation/1B2C/d/Clawnsole.app",
    ),
    true,
  );
  assert.equal(isTranslocated("/Applications/Clawnsole.app"), false);
  assert.equal(isTranslocated(null), false);
});

test("permission and translocation failures become one actionable line", () => {
  for (const code of ["EACCES", "EPERM", "EROFS"]) {
    const error = Object.assign(new Error("rename failed"), { code });
    assert.equal(
      describeInstallFailure(error, "/Applications/Clawnsole.app"),
      INSTALL_LOCATION_HELP,
    );
  }
  assert.equal(
    describeInstallFailure(
      new Error("rename failed"),
      "/private/var/folders/z9/AppTranslocation/1B2C/d/Clawnsole.app",
    ),
    INSTALL_LOCATION_HELP,
  );
  assert.match(INSTALL_LOCATION_HELP, /Applications folder/);
});

test("an unrelated failure keeps its own message", () => {
  const error = Object.assign(new Error("ditto ran out of space"), {
    code: "ENOSPC",
  });
  assert.equal(
    describeInstallFailure(error, "/Applications/Clawnsole.app"),
    "ditto ran out of space",
  );
  assert.equal(describeInstallFailure("plain string"), "plain string");
});

test("a declined move to Applications is remembered once and for all", (t) => {
  const userData = temporaryDirectory(t);
  assert.equal(applicationsMoveDeclined(userData), false);

  rememberApplicationsMoveDeclined(
    userData,
    () => new Date("2026-09-01T12:00:00.000Z"),
  );
  assert.equal(applicationsMoveDeclined(userData), true);

  const stored = JSON.parse(
    fs.readFileSync(path.join(userData, INSTALL_LOCATION_FILE), "utf8"),
  );
  assert.equal(stored.applicationsMoveDeclinedAt, "2026-09-01T12:00:00.000Z");
  // The record is rewritten atomically, so no temporary file survives.
  assert.deepEqual(fs.readdirSync(userData), [INSTALL_LOCATION_FILE]);

  rememberApplicationsMoveDeclined(userData);
  assert.equal(applicationsMoveDeclined(userData), true);
  assert.deepEqual(fs.readdirSync(userData), [INSTALL_LOCATION_FILE]);
});

test("a missing or malformed record reads as never declined", (t) => {
  const userData = temporaryDirectory(t);
  const file = path.join(userData, INSTALL_LOCATION_FILE);

  fs.writeFileSync(file, "not json");
  assert.equal(applicationsMoveDeclined(userData), false);

  fs.writeFileSync(file, JSON.stringify({ applicationsMoveDeclinedAt: 17 }));
  assert.equal(applicationsMoveDeclined(userData), false);
});
