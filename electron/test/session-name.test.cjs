"use strict";

const assert = require("node:assert/strict");
const { EventEmitter } = require("node:events");
const fs = require("node:fs");
const path = require("node:path");
const { PassThrough } = require("node:stream");
const test = require("node:test");
const {
  DEFAULT_TIMEOUT_MS,
  MAXIMUM_OUTPUT_BYTES,
  MAXIMUM_SOURCE_CHARACTERS,
  boundedSource,
  generateSessionName,
  installSessionNameHandler,
} = require("../lib/session-name.cjs");

test("allows enough time for first-run on-device model warm-up", () => {
  assert.equal(DEFAULT_TIMEOUT_MS, 20_000);
});

function fakeProcess({ output = '{"name":"Red Fox Study"}\n', code = 0 } = {}) {
  const child = new EventEmitter();
  child.stdin = new PassThrough();
  child.stdout = new PassThrough();
  child.stderr = new PassThrough();
  child.exitCode = null;
  child.killedWith = null;
  child.kill = (signal) => {
    child.killedWith = signal;
    child.exitCode = 1;
    return true;
  };
  process.nextTick(() => {
    child.stdout.end(output);
    child.exitCode = code;
    child.emit("close", code);
  });
  return child;
}

test("runs the helper with a bounded stdin request and empty environment", async () => {
  let invocation;
  let request = "";
  const name = await generateSessionName("  snowy red fox  ", {
    executable: "/Applications/Clawnsole.app/session-title",
    spawnImpl: (executable, arguments_, options) => {
      const child = fakeProcess();
      child.stdin.on("data", (chunk) => (request += chunk.toString("utf8")));
      invocation = { executable, arguments_, options };
      return child;
    },
  });

  assert.equal(name, "Red Fox Study");
  assert.equal(invocation.executable, "/Applications/Clawnsole.app/session-title");
  assert.deepEqual(invocation.arguments_, []);
  assert.deepEqual(invocation.options.env, {});
  assert.deepEqual(invocation.options.stdio, ["pipe", "pipe", "pipe"]);
  assert.deepEqual(JSON.parse(request), { source: "snowy red fox" });
});

test("bounds source locally and refuses empty or invalid input", async () => {
  let spawned = 0;
  const spawnImpl = () => {
    spawned += 1;
    return fakeProcess();
  };
  assert.equal(boundedSource("x".repeat(4_000)).length, MAXIMUM_SOURCE_CHARACTERS);
  assert.equal(await generateSessionName(" ", { executable: "/helper", spawnImpl }), null);
  assert.equal(await generateSessionName(null, { executable: "/helper", spawnImpl }), null);
  assert.equal(await generateSessionName("fox", { executable: "", spawnImpl }), null);
  assert.equal(spawned, 0);
});

test("rejects malformed, failed, oversized, and timed-out helper output", async () => {
  assert.equal(
    await generateSessionName("fox", {
      executable: "/helper",
      spawnImpl: () => fakeProcess({ output: "not-json" }),
    }),
    null,
  );
  assert.equal(
    await generateSessionName("fox", {
      executable: "/helper",
      spawnImpl: () => fakeProcess({ code: 1 }),
    }),
    null,
  );

  const oversized = fakeProcess({ output: "x".repeat(MAXIMUM_OUTPUT_BYTES + 1) });
  assert.equal(
    await generateSessionName("fox", {
      executable: "/helper",
      spawnImpl: () => oversized,
    }),
    null,
  );
  assert.equal(oversized.killedWith, "SIGKILL");

  const stalled = new EventEmitter();
  stalled.stdin = new PassThrough();
  stalled.stdout = new PassThrough();
  stalled.stderr = new PassThrough();
  stalled.exitCode = null;
  stalled.kill = (signal) => {
    stalled.killedWith = signal;
    stalled.exitCode = 1;
  };
  assert.equal(
    await generateSessionName("fox", {
      executable: "/helper",
      spawnImpl: () => stalled,
      timeoutMs: 1,
    }),
    null,
  );
  assert.equal(stalled.killedWith, "SIGKILL");
});

test("IPC accepts only the active renderer and forwards no prompt metadata", async () => {
  let registration;
  const generated = [];
  installSessionNameHandler({
    ipcMain: {
      handle: (channel, handler) => (registration = { channel, handler }),
    },
    isAllowedAppUrl: (candidate, expected) => candidate === expected,
    rendererUrl: () => "http://127.0.0.1:7357",
    executable: () => "/resources/session-title/session_title_helper",
    generate: async (source, options) => {
      generated.push({ source, options });
      return "Fox in Snow";
    },
  });

  assert.equal(registration.channel, "clawnsole:session-name:generate");
  assert.equal(
    await registration.handler(
      { senderFrame: { url: "https://attacker.example/" } },
      "private prompt",
    ),
    null,
  );
  assert.equal(generated.length, 0);
  assert.equal(
    await registration.handler(
      { senderFrame: { url: "http://127.0.0.1:7357" } },
      "private prompt",
    ),
    "Fox in Snow",
  );
  assert.deepEqual(generated, [{
    source: "private prompt",
    options: {
      executable: "/resources/session-title/session_title_helper",
    },
  }]);
});

test("the signed helper is part of the Electron package contract", () => {
  const electronDirectory = path.join(__dirname, "..");
  const metadata = JSON.parse(
    fs.readFileSync(path.join(electronDirectory, "package.json"), "utf8"),
  );
  assert.ok(metadata.build.extraResources.some(
    ({ from, to }) => from === "dist/session-title" && to === "session-title",
  ));
  assert.deepEqual(metadata.build.mac.binaries, [
    "Contents/Resources/session-title/session_title_helper",
  ]);
  assert.equal(
    fs.statSync(path.join(electronDirectory, "scripts", "prepare-session-title-helper"))
      .mode & 0o111,
    0o111,
  );
  assert.equal(
    fs.existsSync(path.join(electronDirectory, "native", "session_title_helper.swift")),
    true,
  );
});
