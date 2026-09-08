"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");
const { PORT_FILE, portOfUrl, readPreferredPort, rememberPort } = require("../lib/companion-port.cjs");

function temporaryUserData(t) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "clawnsole-port-"));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  return directory;
}

test("the last bound port round-trips through a small JSON file", (t) => {
  const userData = path.join(temporaryUserData(t), "profile");
  assert.equal(readPreferredPort(userData), null);
  assert.equal(rememberPort(userData, 43123), true);
  assert.equal(readPreferredPort(userData), 43123);
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(userData, PORT_FILE), "utf8")), { port: 43123 });
});

test("an unchanged port is not rewritten and a changed one replaces it", (t) => {
  const userData = temporaryUserData(t);
  rememberPort(userData, 43123);
  const before = fs.statSync(path.join(userData, PORT_FILE));
  fs.utimesSync(path.join(userData, PORT_FILE), new Date(0), new Date(0));
  rememberPort(userData, 43123);
  assert.equal(fs.statSync(path.join(userData, PORT_FILE)).mtimeMs, 0, "identical port must not rewrite");
  assert.ok(before);
  rememberPort(userData, 50000);
  assert.equal(readPreferredPort(userData), 50000);
});

test("only integers between 1 and 65535 are accepted or persisted", (t) => {
  const userData = temporaryUserData(t);
  for (const invalid of [0, -1, 65_536, 1.5, "43123", null, undefined, NaN]) {
    assert.equal(rememberPort(userData, invalid), false, String(invalid));
  }
  assert.equal(fs.existsSync(path.join(userData, PORT_FILE)), false);
  for (const contents of ["", "{", "[]", "{\"port\":\"43123\"}", "{\"port\":70000}", "null"]) {
    fs.writeFileSync(path.join(userData, PORT_FILE), contents);
    assert.equal(readPreferredPort(userData), null, JSON.stringify(contents));
  }
});

test("filesystem failures fall back to a random port instead of throwing", () => {
  const failing = { readFileSync() { throw new Error("EACCES"); }, mkdirSync() { throw new Error("EROFS"); },
    writeFileSync() { throw new Error("EROFS"); } };
  assert.equal(readPreferredPort("/nowhere", { fsImpl: failing }), null);
  assert.equal(rememberPort("/nowhere", 43123, { fsImpl: failing }), false);
});

test("the port of the renderer origin is extracted for persistence", () => {
  assert.equal(portOfUrl("http://127.0.0.1:43123"), 43123);
  assert.equal(portOfUrl("http://127.0.0.1"), null);
  assert.equal(portOfUrl("not a url"), null);
});
