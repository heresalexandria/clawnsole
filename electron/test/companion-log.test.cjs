"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { Readable } = require("node:stream");
const test = require("node:test");

const {
  CompanionLog,
  LOG_FILE,
  MAX_LOG_BYTES,
  PREVIOUS_LOG_FILE,
} = require("../lib/companion-log.cjs");

const STAMP = "2026-09-01T12:00:00.000Z";

function temporaryDirectory(t) {
  const directory = fs.mkdtempSync(
    path.join(os.tmpdir(), "clawnsole-companion-log-"),
  );
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  return directory;
}

function openLog(t, directory, options = {}) {
  const log = new CompanionLog({
    directory,
    now: () => new Date(STAMP),
    ...options,
  });
  t.after(() => log.close());
  return log;
}

test("a log directory is required", () => {
  assert.throws(() => new CompanionLog({}), /log directory/);
  assert.throws(() => new CompanionLog({ directory: "  " }), /log directory/);
});

test("companion output is stamped, labelled, and split into lines", (t) => {
  const directory = path.join(temporaryDirectory(t), "Logs");
  const log = openLog(t, directory);

  log.write("out", "companion ready\nlistening on 127.0.0.1:43123\n");
  log.write("error", "a warning");

  assert.equal(log.file, path.join(directory, LOG_FILE));
  assert.deepEqual(fs.readFileSync(log.file, "utf8").split("\n"), [
    `${STAMP} [out] companion ready`,
    `${STAMP} [out] listening on 127.0.0.1:43123`,
    `${STAMP} [error] a warning`,
    "",
  ]);
});

test("attached streams are captured and optionally echoed", async (t) => {
  const directory = temporaryDirectory(t);
  const echoed = [];
  const log = openLog(t, directory, { echo: (entry) => echoed.push(entry) });

  const stream = Readable.from(["first line\n", "second line\n"]);
  log.attach(stream, "out");
  log.attach(null, "out");
  await new Promise((resolve) => stream.once("end", resolve));

  assert.deepEqual(echoed, [
    `${STAMP} [out] first line\n`,
    `${STAMP} [out] second line\n`,
  ]);
  assert.equal(fs.readFileSync(log.file, "utf8"), echoed.join(""));
});

test("the log is size capped and keeps exactly one previous file", (t) => {
  const directory = temporaryDirectory(t);
  const log = openLog(t, directory, { maxBytes: 200 });

  for (let index = 0; index < 12; index += 1) {
    log.write("out", `line ${index} ${"x".repeat(40)}`);
  }

  assert.deepEqual(fs.readdirSync(directory).sort(), [
    LOG_FILE,
    PREVIOUS_LOG_FILE,
  ]);
  for (const name of [LOG_FILE, PREVIOUS_LOG_FILE]) {
    const size = fs.statSync(path.join(directory, name)).size;
    assert.ok(size <= 200, `${name} must stay under the cap (saw ${size})`);
  }
  // The newest lines survive; the oldest were dropped with the rotation.
  assert.match(fs.readFileSync(log.file, "utf8"), /line 11/);
  assert.equal(MAX_LOG_BYTES, 5 * 1024 * 1024);
});

test("an unwritable log disables itself instead of taking the shell down", (t) => {
  const directory = path.join(temporaryDirectory(t), "blocked");
  fs.writeFileSync(directory, "not a directory");
  const log = openLog(t, directory);

  assert.doesNotThrow(() => log.write("out", "companion ready"));
  assert.doesNotThrow(() => log.write("out", "still running"));
  assert.doesNotThrow(() => log.close());
});

test("a single huge line cannot exceed either rotated log cap", (t) => {
  const directory = temporaryDirectory(t);
  const log = openLog(t, directory, { maxBytes: 200 });
  log.write("error", "x".repeat(10_000));
  log.write("error", "y".repeat(10_000));
  for (const name of [LOG_FILE, PREVIOUS_LOG_FILE]) {
    assert.ok(fs.statSync(path.join(directory, name)).size <= 200);
    assert.match(fs.readFileSync(path.join(directory, name), "utf8"), /truncated/);
  }
});

test("a broken terminal echo and output stream cannot crash logging", (t) => {
  const log = openLog(t, temporaryDirectory(t), {
    echo: () => { throw new Error("terminal closed"); },
  });
  const stream = new Readable({ read() {} });
  log.attach(stream, "out");
  assert.doesNotThrow(() => log.write("out", "still saved"));
  assert.doesNotThrow(() => stream.emit("error", new Error("pipe closed")));
  assert.match(fs.readFileSync(log.file, "utf8"), /still saved/);
  assert.match(fs.readFileSync(log.file, "utf8"), /output-stream-error/);
});
