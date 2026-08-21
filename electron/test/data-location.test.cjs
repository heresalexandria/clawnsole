"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");

const dataLocation = require("../lib/data-location.cjs");

function temporaryDirectory(t, label) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), label));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  return directory;
}

test("the default data directory is userData until a move is recorded", (t) => {
  const userData = temporaryDirectory(t, "clawnsole-data-location-");
  const target = temporaryDirectory(t, "clawnsole-data-target-");

  assert.equal(dataLocation.storedDataDirectory(userData), null);
  assert.equal(dataLocation.dataDirectory(userData), userData);
  assert.equal(
    dataLocation.dataFile(userData),
    path.join(userData, "clawnsole.json"),
  );

  dataLocation.rememberDataDirectory(userData, target);
  assert.equal(dataLocation.storedDataDirectory(userData), target);
  assert.equal(
    dataLocation.dataFile(userData),
    path.join(target, "clawnsole.json"),
  );
});

test("a missing or malformed pointer falls back to userData", (t) => {
  const userData = temporaryDirectory(t, "clawnsole-data-location-");
  const pointer = path.join(userData, dataLocation.DATA_LOCATION_FILE);

  fs.writeFileSync(pointer, "not json");
  assert.equal(dataLocation.dataDirectory(userData), userData);

  fs.writeFileSync(
    pointer,
    JSON.stringify({ dataDirectory: path.join(userData, "unplugged-drive") }),
  );
  assert.equal(dataLocation.dataDirectory(userData), userData);
});

test("relocation targets are validated before any copy", (t) => {
  const current = temporaryDirectory(t, "clawnsole-data-current-");
  const target = temporaryDirectory(t, "clawnsole-data-target-");

  const same = dataLocation.inspectRelocationTarget(current, current);
  assert.equal(same.ok, false);
  assert.match(same.error, /already stores/);

  const insideAssets = dataLocation.inspectRelocationTarget(
    current,
    path.join(current, "assets", "nested"),
  );
  assert.equal(insideAssets.ok, false);
  assert.match(insideAssets.error, /assets folder/);

  const empty = dataLocation.inspectRelocationTarget(current, target);
  assert.deepEqual(empty, { ok: true, hasExistingLibrary: false });

  fs.writeFileSync(path.join(target, "clawnsole.json"), "{}");
  const occupied = dataLocation.inspectRelocationTarget(current, target);
  assert.deepEqual(occupied, { ok: true, hasExistingLibrary: true });
});

test("copyLibrary moves the data file, key sibling, and assets", (t) => {
  const current = temporaryDirectory(t, "clawnsole-data-current-");
  const target = path.join(
    temporaryDirectory(t, "clawnsole-data-target-"),
    "portable",
  );
  fs.writeFileSync(path.join(current, "clawnsole.json"), '{"records":[]}');
  fs.writeFileSync(path.join(current, "clawnsole.json.secure"), "sealed");
  fs.mkdirSync(path.join(current, "assets"));
  fs.writeFileSync(path.join(current, "assets", "one.asset"), "video");

  dataLocation.copyLibrary(current, target);

  assert.equal(
    fs.readFileSync(path.join(target, "clawnsole.json"), "utf8"),
    '{"records":[]}',
  );
  assert.equal(
    fs.readFileSync(path.join(target, "clawnsole.json.secure"), "utf8"),
    "sealed",
  );
  assert.equal(
    fs.readFileSync(path.join(target, "assets", "one.asset"), "utf8"),
    "video",
  );
  // The previous copy stays in place as a safety net.
  assert.ok(fs.existsSync(path.join(current, "clawnsole.json")));
  assert.ok(fs.existsSync(path.join(current, "assets", "one.asset")));
});
