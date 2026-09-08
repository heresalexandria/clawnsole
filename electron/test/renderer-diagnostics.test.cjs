"use strict";

const assert = require("node:assert/strict");
const { EventEmitter } = require("node:events");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");
const { CompanionLog } = require("../lib/companion-log.cjs");
const { rendererIpcGuard } = require("../lib/renderer-ipc.cjs");
const { DIAGNOSTIC_CHANNEL, RendererDiagnostics, installDiagnosticIpc,
  sanitizeDiagnostic, sanitizeStack } = require("../lib/renderer-diagnostics.cjs");

function fixture(overrides = {}) {
  const contents = new EventEmitter();
  const entries = [];
  let clock = 0;
  let interval;
  let cleared = 0;
  const timer = { unref() {} };
  const diagnostics = new RendererDiagnostics({
    contents, log: { write: (label, entry) => { assert.equal(label, "renderer"); entries.push(JSON.parse(entry)); } },
    now: () => clock,
    setIntervalImpl: (callback, delay) => { assert.equal(delay, 60_000); interval = callback; return timer; },
    clearIntervalImpl: (value) => { assert.equal(value, timer); cleared += 1; },
    ...overrides,
  });
  return { contents, entries, diagnostics, advance: (time) => clock += time, sample: () => interval(), cleared: () => cleared };
}

test("diagnostic stacks preserve executable JS/Dart/WASM locations while excluding exception text and URLs", () => {
  const stack = `Error: secret prompt bearer-token\n`
    + ` at Object._cullRect (https://private.example/account/main.dart.js:124:56)\n`
    + ` at https://www.gstatic.com/flutter-canvaskit/private-hash/chromium/canvaskit.wasm:wasm-function[9661]:0x45cde5\n`
    + ` at wasm://wasm/private-hash:wasm-function[7764]:0x2134\n`
    + `#0 Widget.build (package:private/path/widget.dart:82:9)\n`
    + `run@file:///Users/private/name/app.js:10:2\n`
    + ` at secret (https://private.example/asset.js?token=secret:20:3)\n`;
  const result = sanitizeDiagnostic({ event: "flutter-error", errorType: "StateError", stack,
    message: "secret", url: "https://private.example", nested: { token: "secret" } });
  assert.deepEqual(result, { event: "flutter-error", errorType: "StateError", frames: [
    { source: "main.dart.js", line: 124, column: 56, function: "Object._cullRect" },
    { source: "canvaskit.wasm", functionIndex: 9661, offset: "0x45cde5" },
    { source: "wasm", functionIndex: 7764, offset: "0x2134" },
    { source: "widget.dart", line: 82, column: 9, function: "Widget.build" },
    { source: "app.js", line: 10, column: 2, function: "run" },
  ] });
  assert.doesNotMatch(JSON.stringify(result), /secret|private|https|file:|package:|Users|bearer/);
  assert.equal(sanitizeStack(" at a (http://localhost/main.js:1:2)\n".repeat(200)).length, 12);
  assert.deepEqual(sanitizeStack({ toString() { throw new Error("must not stringify"); } }), []);
});

test("only fixed event names, identifier types, and finite nonnegative health metrics are accepted", () => {
  assert.equal(sanitizeDiagnostic({ event: "arbitrary-secret", stack: "x" }), null);
  assert.deepEqual(sanitizeDiagnostic({ event: "flutter-health", errorType: "Error with secret",
    frameCount: 12, cacheBytes: Infinity, liveImages: -1, pendingImages: "123", lastFrameAgeMs: 1.234,
    canvasKitHeapBytes: 2147483648, canvasKitDecodeCacheBytes: 1024,
    canvasKitDecodeCacheLimitBytes: 33554432, flutterErrorsSuppressed: 253000, privateCount: 1,
  }), { event: "flutter-health", errorType: "UnknownError", frameCount: 12, lastFrameAgeMs: 1.23,
    canvasKitHeapBytes: 2147483648, canvasKitDecodeCacheBytes: 1024, canvasKitDecodeCacheLimitBytes: 33554432, flutterErrorsSuppressed: 253000 });
  assert.deepEqual(sanitizeDiagnostic({ event: "flutter-ready", cacheBytes: 12 }), { event: "flutter-ready" });
});

test("duplicate and changing error floods produce bounded records and exact suppressed totals", () => {
  const f = fixture();
  for (let i = 0; i < 10_000; i += 1) f.diagnostics.report({ event: "flutter-error", errorType: "Error",
    stack: `Error: secret\n at paint (http://localhost/main.dart.js:${i + 1}:2)` });
  for (let i = 0; i < 100; i += 1) f.diagnostics.report({ event: "web-error", errorType: "Error" });
  assert.equal(f.entries.length, 4);
  f.advance(60_000);
  f.sample();
  assert.deepEqual(f.entries.filter((entry) => entry.event === "renderer-diagnostic-summary"), [
    { event: "renderer-diagnostic-summary", sourceEvent: "flutter-error", suppressed: 9997 },
    { event: "renderer-diagnostic-summary", sourceEvent: "web-error", suppressed: 99 },
  ]);
  f.diagnostics.report({ event: "flutter-error", errorType: "Error" });
  assert.equal(f.entries.at(-1).event, "flutter-error");
  f.diagnostics.dispose();
});

test("preload suppression totals survive full main-process buckets and flood limits", () => {
  const f = fixture();
  for (let i = 0; i < 31; i += 1) f.diagnostics.report({ event: "flutter-error", stack: ` at paint (main.js:${i + 1}:2)` });
  f.diagnostics.report({ event: "flutter-error", suppressed: 9969 });
  f.diagnostics.report({ event: "flutter-error", suppressed: 200 });
  f.advance(60_000);
  f.sample();
  assert.deepEqual(f.entries.find((entry) => entry.event === "renderer-diagnostic-summary"), {
    event: "renderer-diagnostic-summary", sourceEvent: "flutter-error", suppressed: 10197,
  });
  f.diagnostics.dispose();
});

test("console, preload and load failures keep useful categories and frames without messages", () => {
  const f = fixture();
  f.contents.emit("console-message", { level: "error", message: "CanvasKit secret URL https://private.example", sourceId: "http://localhost/main.dart.js", lineNumber: 72 });
  f.contents.emit("console-message", {}, 2, "out of memory secret", 9, "file:///private/engine.js");
  f.contents.emit("console-message", { level: "info", message: "secret" });
  f.contents.emit("preload-error", {}, "/private/preload.cjs", { name: "TypeError", message: "secret", stack: "TypeError: secret\n at boot (file:///private/boot.js:2:3)" });
  f.contents.emit("did-fail-load", {}, -2, "secret", "https://secret", false);
  f.contents.emit("did-fail-load", {}, -7, "secret", "https://secret", true);
  assert.deepEqual(f.entries.map((entry) => entry.event), ["renderer-console-error", "renderer-console-warning", "renderer-preload-error", "renderer-load-failed"]);
  assert.equal(f.entries[0].category, "graphics-error");
  assert.equal(f.entries[0].frames[0].line, 72);
  assert.equal(f.entries[1].category, "memory-failure");
  assert.equal(f.entries[3].code, -7);
  assert.doesNotMatch(JSON.stringify(f.entries), /secret|private|https|file:/);
  f.diagnostics.dispose();
});

test("minute samples use allowlisted process numbers and report the last Flutter heartbeat age", () => {
  const f = fixture({ getAppMetrics: () => [{ type: "Renderer", pid: 123, name: "secret", serviceName: "secret",
    cpu: { percentCPUUsage: 12.234 }, memory: { workingSetSize: 2250000, peakWorkingSetSize: 2300000, secret: 1 } }] });
  f.diagnostics.report({ event: "flutter-health", frameCount: 50 });
  f.advance(120_000);
  f.sample();
  assert.deepEqual(f.entries.at(-1), { event: "renderer-process-metrics", flutterHealthAgeMs: 120000, processes: [
    { type: "Renderer", pid: 123, cpuPercent: 12.23, workingSetKiB: 2250000, peakWorkingSetKiB: 2300000 },
  ] });
  f.diagnostics.dispose();
});

test("destroying a renderer removes all owned listeners and timers; late callbacks cannot log", () => {
  const f = fixture();
  f.contents.emit("destroyed");
  f.diagnostics.dispose();
  assert.equal(f.cleared(), 1);
  assert.deepEqual(f.contents.eventNames(), []);
  f.sample();
  f.diagnostics.report({ event: "flutter-error" });
  assert.deepEqual(f.entries, []);
});

test("diagnostic IPC rejects cross-window, subframe and wrong-origin senders and can be disposed", () => {
  const ipc = new EventEmitter();
  const frame = { url: "http://127.0.0.1:7357/" };
  const contents = { mainFrame: frame, isDestroyed: () => false };
  const window = { webContents: contents, isDestroyed: () => false };
  const received = [];
  const guard = rendererIpcGuard({ getWindow: () => window, getRendererUrl: () => "http://127.0.0.1:7357" });
  const dispose = installDiagnosticIpc(ipc, guard, () => ({ report: (payload) => received.push(payload) }));
  const payload = { event: "flutter-ready" };
  ipc.emit(DIAGNOSTIC_CHANNEL, { sender: {}, senderFrame: frame }, payload);
  ipc.emit(DIAGNOSTIC_CHANNEL, { sender: contents, senderFrame: { ...frame } }, payload);
  frame.url = "https://private.example";
  ipc.emit(DIAGNOSTIC_CHANNEL, { sender: contents, senderFrame: frame }, payload);
  frame.url = "http://127.0.0.1:7357/";
  ipc.emit(DIAGNOSTIC_CHANNEL, { sender: contents, senderFrame: frame }, payload);
  assert.deepEqual(received, [payload]);
  dispose();
  assert.equal(ipc.listenerCount(DIAGNOSTIC_CHANNEL), 0);
});

test("persistent diagnostics reuse the capped two-file log and tolerate an unwritable logger", () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "clawnsole-diagnostics-"));
  const log = new CompanionLog({ directory, maxBytes: 1024 });
  const f = fixture({ log });
  try {
    for (let i = 0; i < 40; i += 1) {
      f.diagnostics.report({ event: "flutter-error", errorType: "Error", stack: " at paint (http://localhost/main.dart.js:12:34)" });
      f.advance(60_000);
      f.sample();
    }
    f.diagnostics.dispose();
    log.close();
    assert.deepEqual(fs.readdirSync(directory).sort(), ["companion.log", "companion.log.1"]);
    for (const file of fs.readdirSync(directory)) assert.ok(fs.statSync(path.join(directory, file)).size <= 1024);
  } finally { f.diagnostics.dispose(); log.close(); fs.rmSync(directory, { recursive: true, force: true }); }
  const broken = fixture({ log: { write() { throw new Error("closed log"); } } });
  assert.doesNotThrow(() => broken.diagnostics.report({ event: "flutter-error" }));
  broken.diagnostics.dispose();
});
