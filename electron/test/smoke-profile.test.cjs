"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");
const { configureSmokeProfile } = require("../lib/smoke-profile.cjs");

test("normal launches retain their configured profile", () => {
  assert.equal(configureSmokeProfile({
    setPath: () => assert.fail("normal launch must not redirect profile"),
  }, { smoke: false }), null);
});

test("smoke runs isolate profile, browser session and logs before any data access", (t) => {
  const temporaryDirectory = fs.mkdtempSync(path.join(os.tmpdir(), "clawnsole-smoke-profile-test-"));
  t.after(() => fs.rmSync(temporaryDirectory, { recursive: true, force: true }));
  const existing = path.join(temporaryDirectory, "existing-profile");
  fs.mkdirSync(existing);
  fs.writeFileSync(path.join(existing, "history.json"), "FAKE_EXISTING_HISTORY");
  const locations = {};
  const app = {
    getPath: () => assert.fail("must not read the user's profile"),
    setPath: (name, directory) => {
      assert.ok(fs.statSync(directory).isDirectory());
      locations[name] = directory;
    },
  };
  const first = configureSmokeProfile(app, { smoke: true, temporaryDirectory });
  assert.deepEqual(Object.keys(locations), ["userData", "sessionData", "logs"]);
  for (const directory of Object.values(locations)) {
    assert.equal(path.dirname(directory), first);
    assert.deepEqual(fs.readdirSync(directory), []);
  }
  const second = configureSmokeProfile(app, { smoke: true, temporaryDirectory });
  assert.notEqual(first, second);
  assert.equal(fs.readFileSync(path.join(existing, "history.json"), "utf8"), "FAKE_EXISTING_HISTORY");
});

test("entry point isolates smoke state before lock, session and native integration startup", () => {
  const source = fs.readFileSync(path.join(__dirname, "..", "main.cjs"), "utf8");
  const configure = source.indexOf("const smokeProfile = configureSmokeProfile");
  assert.ok(configure > 0);
  assert.ok(configure < source.indexOf('app.getPath("userData")'));
  assert.ok(configure < source.indexOf("session.defaultSession"));
  assert.ok(configure < source.indexOf("app.requestSingleInstanceLock()"));
});
