"use strict";
const assert = require("node:assert/strict");
const test = require("node:test");
const { ENGINE_REASONS, processDetails, runShellTask, writeLifecycle } = require("../lib/lifecycle-log.cjs");

test("process breadcrumbs keep only allowlisted metadata", () => {
  assert.deepEqual(processDetails({
    reason: "oom", type: "GPU", exitCode: 137,
    serviceName: "private service", url: "https://secret.example/token",
  }), { reason: "oom", type: "GPU", exitCode: 137 });
  assert.deepEqual(processDetails({ reason: "secret", type: "private", exitCode: "secret" }),
    { reason: "unknown", type: "unknown", exitCode: null });
});

test("engine-dead reasons are fixed names that survive the process allowlist", () => {
  assert.deepEqual([...ENGINE_REASONS], ["engine-abort", "frames-frozen", "heap-critical"]);
  for (const reason of ENGINE_REASONS) {
    assert.deepEqual(processDetails({ reason, type: "Renderer" }),
      { reason, type: "Renderer", exitCode: null });
  }
  assert.equal(processDetails({ reason: "engine-dead" }).reason, "unknown");
});

test("detached shell actions contain synchronous throws and rejected promises", async () => {
  const entries = [];
  const log = { write: (label, message) => entries.push([label, message]) };
  await runShellTask(log, "load-failed", () => { throw new Error("private URL"); });
  await runShellTask(log, "load-failed", async () => { throw new Error("private token"); });
  assert.deepEqual(entries, [["shell", "load-failed"], ["shell", "load-failed"]]);
  assert.doesNotThrow(() => writeLifecycle({ write: () => { throw new Error(); } }, "load-failed"));
});

test("startup versions are useful without accepting arbitrary diagnostic text", () => {
  const { writeStartup } = require("../lib/lifecycle-log.cjs");
  const entries = [];
  const log = { write: (_label, message) => entries.push(message) };
  writeStartup(log, "0.52.2", "43.4.0");
  writeStartup(log, "secret\nvalue", "https://signed.example");
  assert.deepEqual(entries, [
    "shell-started app=0.52.2 electron=43.4.0",
    "shell-started app=unknown electron=unknown",
  ]);
});
