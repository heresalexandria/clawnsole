"use strict";

const assert = require("node:assert/strict");
const { EventEmitter } = require("node:events");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");
const { CompanionLog } = require("../lib/companion-log.cjs");
const { rendererIpcGuard } = require("../lib/renderer-ipc.cjs");
const { DIAGNOSTIC_CHANNEL, HEAP_CRITICAL_BYTES, HEAP_GROWTH_STEP_BYTES, RendererDiagnostics,
  consoleCategory, installDiagnosticIpc, parseEngineCounters, sanitizeAppMetrics, sanitizeDiagnostic,
  sanitizeStack } = require("../lib/renderer-diagnostics.cjs");

const MiB = 1024 * 1024;

function fixture(overrides = {}) {
  const contents = new EventEmitter();
  const entries = [];
  const alerts = [];
  let clock = 0;
  let interval;
  let cleared = 0;
  const timer = { unref() {} };
  const diagnostics = new RendererDiagnostics({
    contents, log: { write: (label, entry) => { assert.equal(label, "renderer"); entries.push(JSON.parse(entry)); } },
    onAlert: (kind, details) => alerts.push({ kind, ...details }),
    now: () => clock,
    setIntervalImpl: (callback, delay) => { assert.equal(delay, 60_000); interval = callback; return timer; },
    clearIntervalImpl: (value) => { assert.equal(value, timer); cleared += 1; },
    ...overrides,
  });
  const health = (fields) => diagnostics.report({ event: "flutter-health", appActive: 1, ...fields });
  return { contents, entries, alerts, diagnostics, health, advance: (time) => clock += time,
    sample: () => interval(), cleared: () => cleared };
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
  assert.equal(f.entries.length, 5);
  assert.deepEqual(f.entries[3], { event: "renderer-error-storm", sourceEvent: "flutter-error", perMinute: 1000 });
  assert.deepEqual(f.alerts, [{ kind: "error-storm", sourceEvent: "flutter-error", perMinute: 1000 }]);
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

test("console classification recognizes an Emscripten abort without keeping its text", () => {
  assert.equal(consoleCategory("Aborted(). Build with -sASSERTIONS for more info."), "engine-abort");
  assert.equal(consoleCategory("Aborted(native code called abort())"), "engine-abort");
  assert.equal(consoleCategory("RuntimeError: Aborted(OOM)"), "engine-abort");
  assert.equal(consoleCategory("Cannot enlarge memory arrays to size 2147483648"), "engine-abort");
  assert.equal(consoleCategory("Operation aborted by user"), "unclassified");
  assert.equal(consoleCategory("WebGL: CONTEXT_LOST_WEBGL"), "graphics-context-lost");
});

test("the Flutter app's own self-reports keep numeric fields and never trigger recovery", () => {
  const f = fixture();
  f.health({ frameCount: 40, lifecycleState: 2, documentHidden: 0, framesSinceLastHealth: 12,
    motionConstrained: 1, heapPressure: 2, privateMetric: 7 });
  f.diagnostics.report({ event: "flutter-motion-constrained", heapBytes: 1073741824, note: "secret" });
  f.diagnostics.report({ event: "flutter-lifecycle", lifecycleState: 3, url: "http://secret" });
  f.diagnostics.report({ event: "flutter-engine-stalled", lastFrameAgeMs: 130000, errorsInWindow: 7000, stack: "at secret" });
  f.diagnostics.report({ event: "flutter-engine-stalled", lastFrameAgeMs: 190000, errorsInWindow: 7100 });
  assert.deepEqual(f.entries[0], { event: "flutter-health", frameCount: 40, appActive: 1, lifecycleState: 2,
    documentHidden: 0, framesSinceLastHealth: 12, motionConstrained: 1, heapPressure: 2 });
  assert.deepEqual(f.entries[1], { event: "flutter-motion-constrained", heapBytes: 1073741824 });
  assert.deepEqual(f.entries[2], { event: "flutter-lifecycle", lifecycleState: 3 });
  assert.deepEqual(f.entries[3], { event: "flutter-engine-stalled", lastFrameAgeMs: 130000, errorsInWindow: 7000 });
  // The page's own verdict is evidence, never a trigger: no alert, no reload.
  assert.deepEqual(f.alerts, []);
  assert.doesNotMatch(JSON.stringify([f.entries, f.alerts]), /secret|privateMetric|http/);
  f.diagnostics.dispose();
});

test("an engine abort on the console raises one engine-dead alert per document", () => {
  const f = fixture();
  const abort = { level: "error", message: "Aborted(DO_NOT_LOG). Build with -sASSERTIONS", sourceId: "http://x/canvaskit.js", lineNumber: 1 };
  f.contents.emit("console-message", abort);
  f.contents.emit("console-message", abort);
  f.contents.emit("console-message", { level: "error", message: "RuntimeError: Aborted(DO_NOT_LOG)" });
  assert.deepEqual(f.alerts, [{ kind: "engine-dead", reason: "engine-abort" }]);
  assert.equal(f.entries[0].category, "engine-abort");
  f.contents.emit("did-finish-load");
  f.contents.emit("console-message", abort);
  assert.equal(f.alerts.length, 2);
  assert.doesNotMatch(JSON.stringify([f.entries, f.alerts]), /DO_NOT_LOG|http/);
  f.diagnostics.dispose();
});

test("a frozen frame count with an error storm is a dead engine; an idle screen is not", () => {
  const f = fixture();
  f.health({ frameCount: 100, lastFrameAgeMs: 10, flutterErrorsSuppressed: 0 });
  // Idle: no frames for many minutes and no errors never triggers anything.
  for (let minute = 0; minute < 5; minute += 1) {
    f.advance(60_000);
    f.health({ frameCount: 100, lastFrameAgeMs: 60_000 * (minute + 1), flutterErrorsSuppressed: 0 });
  }
  assert.deepEqual(f.alerts, []);
  assert.equal(f.entries.some((entry) => entry.event === "renderer-engine-stalled"), false);
  // Errors arrive while frames stay frozen: the second stalled record fires.
  for (let i = 0; i < 1500; i += 1) f.diagnostics.report({ event: "web-error", errorType: "TypeError" });
  f.advance(60_000);
  f.health({ frameCount: 100, lastFrameAgeMs: 360_000, flutterErrorsSuppressed: 0 });
  const stalled = f.entries.find((entry) => entry.event === "renderer-engine-stalled");
  assert.deepEqual(stalled, { event: "renderer-engine-stalled", framesDelta: 0, intervalMs: 60_000,
    lastFrameAgeMs: 360_000, appActive: 1, flutterErrorsDelta: 0, errorsPerMinute: 1500, consecutiveMinutes: 6 });
  assert.deepEqual(f.alerts.filter((alert) => alert.kind === "engine-dead"),
    [{ kind: "engine-dead", reason: "frames-frozen", ...stalled, event: undefined }].map(({ event, ...rest }) => rest));
  // The alert is not repeated every minute while the shell decides.
  for (let i = 0; i < 1500; i += 1) f.diagnostics.report({ event: "renderer-console-error" });
  f.contents.emit("console-message", { level: "error", message: "x" });
  f.advance(60_000);
  f.health({ frameCount: 100, lastFrameAgeMs: 420_000, flutterErrorsSuppressed: 0 });
  assert.equal(f.alerts.filter((alert) => alert.kind === "engine-dead").length, 1);
  // A new Flutter instance starts counting again from a lower frame count.
  f.advance(60_000);
  f.health({ frameCount: 3, flutterErrorsSuppressed: 0 });
  f.advance(60_000);
  f.health({ frameCount: 3, flutterErrorsSuppressed: 5 });
  f.advance(60_000);
  f.health({ frameCount: 3, flutterErrorsSuppressed: 9 });
  assert.equal(f.alerts.filter((alert) => alert.kind === "engine-dead").length, 2);
  assert.equal(f.alerts.at(-1).flutterErrorsDelta, 4);
  assert.equal(f.alerts.at(-1).consecutiveMinutes, 2);
  f.diagnostics.dispose();
});

test("a frozen engine in the background, or one that only just stopped, is left alone", () => {
  const f = fixture();
  f.health({ frameCount: 10, appActive: 0 });
  for (let minute = 0; minute < 3; minute += 1) {
    for (let i = 0; i < 2000; i += 1) f.diagnostics.report({ event: "flutter-error" });
    f.advance(60_000);
    f.health({ frameCount: 10, appActive: 0, flutterErrorsSuppressed: 10 * (minute + 1) });
  }
  assert.deepEqual(f.alerts.filter((alert) => alert.kind === "engine-dead"), []);
  const g = fixture();
  g.health({ frameCount: 10 });
  g.advance(60_000);
  g.diagnostics.report({ event: "flutter-error", suppressed: 5000 });
  g.health({ frameCount: 10, flutterErrorsSuppressed: 5000 });
  assert.deepEqual(g.alerts.filter((alert) => alert.kind === "engine-dead"), [], "one stalled record is not enough");
  g.advance(60_000);
  g.health({ frameCount: 40, flutterErrorsSuppressed: 5000 });
  g.advance(60_000);
  g.health({ frameCount: 40, flutterErrorsSuppressed: 5001 });
  assert.deepEqual(g.alerts.filter((alert) => alert.kind === "engine-dead"), [], "the count restarts after frames");
  f.diagnostics.dispose();
  g.diagnostics.dispose();
});

test("wasm heap growth and the 1.5 GiB critical line produce numeric records and alerts", () => {
  const f = fixture();
  f.health({ frameCount: 0, canvasKitHeapBytes: 256 * MiB });
  f.advance(60_000);
  f.health({ frameCount: 5820, canvasKitHeapBytes: 256 * MiB + HEAP_GROWTH_STEP_BYTES });
  assert.deepEqual(f.entries.at(-2), { event: "renderer-heap-growth", heapBytes: 320 * MiB, heapDeltaBytes: 64 * MiB,
    framesDelta: 5820, intervalMs: 60_000, framesPerMinute: 5820, critical: 0 });
  assert.deepEqual(f.alerts, [{ kind: "heap-growth", heapBytes: 320 * MiB, heapDeltaBytes: 64 * MiB,
    framesDelta: 5820, intervalMs: 60_000, framesPerMinute: 5820, critical: 0 }]);
  // Slow growth: 60 MiB per minute never trips the step but does trip the
  // five-delta window once five deltas (64 + 4 x 60 MiB) have accumulated.
  let heap = 320 * MiB;
  let frames = 5820;
  for (let minute = 0; minute < 3; minute += 1) {
    heap += 60 * MiB;
    frames += 100;
    f.advance(60_000);
    f.health({ frameCount: frames, canvasKitHeapBytes: heap });
  }
  assert.equal(f.alerts.filter((alert) => alert.kind === "heap-growth").length, 1, "four deltas are not yet a window");
  heap += 60 * MiB;
  f.advance(60_000);
  f.health({ frameCount: frames, canvasKitHeapBytes: heap });
  assert.equal(f.alerts.filter((alert) => alert.kind === "heap-growth").length, 2);
  // Critical fires once, then re-arms only after the heap shrinks.
  f.advance(60_000);
  f.health({ frameCount: frames, canvasKitHeapBytes: HEAP_CRITICAL_BYTES });
  f.advance(60_000);
  f.health({ frameCount: frames, canvasKitHeapBytes: HEAP_CRITICAL_BYTES + MiB });
  const critical = f.alerts.filter((alert) => alert.kind === "heap-critical");
  assert.equal(critical.length, 1);
  assert.equal(critical[0].reason, "heap-critical");
  assert.equal(critical[0].heapBytes, HEAP_CRITICAL_BYTES);
  assert.equal(f.entries.filter((entry) => entry.event === "renderer-heap-growth" && entry.critical === 1).length, 2);
  f.advance(60_000);
  f.health({ frameCount: 1, canvasKitHeapBytes: 128 * MiB });
  f.advance(60_000);
  f.health({ frameCount: 2, canvasKitHeapBytes: HEAP_CRITICAL_BYTES });
  assert.equal(f.alerts.filter((alert) => alert.kind === "heap-critical").length, 2);
  f.sample();
  const metrics = f.entries.at(-1);
  assert.equal(metrics.event, "renderer-process-metrics");
  assert.equal(metrics.heapBytes, HEAP_CRITICAL_BYTES);
  assert.equal(metrics.framesPerMinute, 1);
  assert.doesNotMatch(JSON.stringify([f.entries, f.alerts]), /[^\w"]-?\d+\.\d+e/);
  f.diagnostics.dispose();
});

test("engine counters are parsed only from the instrumented engine's own message", () => {
  const message = "Engine counters:\n  Picture Created: 1200\n  Picture Deleted: 1100\n  Picture Leaked: 40\n"
    + "  Paint Created: 50\n  Paint Deleted: 50\n  secret_token Created: 1\n  Nope: 3\n  https://x Created: 1\n"
    + "  Picture Created: notanumber\n" + Array.from({ length: 80 }, (_, i) => `  Label${i} Created: ${i}`).join("\n");
  const parsed = parseEngineCounters(message);
  assert.deepEqual(parsed.get("Picture"), { created: 1200, deleted: 1100, leaked: 40 });
  assert.deepEqual(parsed.get("Paint"), { created: 50, deleted: 50, leaked: 0 });
  assert.equal(parsed.has("secret_token"), false);
  assert.equal(parsed.size, 64, "labels are capped");
  assert.equal(parseEngineCounters("Not engine counters:\n  Picture Created: 1").size, 0);
  assert.equal(parseEngineCounters(null).size, 0);
});

test("minute samples carry engine counters with live objects and per-minute deltas, never other console text", () => {
  const f = fixture();
  f.contents.emit("console-message", { level: "info", message: "secret plain log https://private.example" });
  f.contents.emit("console-message", { level: "info", message: "Engine counters:\n  Picture Created: 100\n  Picture Deleted: 90\n  Picture Leaked: 2" });
  f.contents.emit("console-message", {}, 1, "Engine counters:\n  Picture Created: 110\n  Picture Deleted: 95\n  Picture Leaked: 3\n  Path Created: 4");
  f.advance(60_000);
  f.sample();
  assert.deepEqual(f.entries.at(-1).engineCounters, {
    Picture: { created: 110, deleted: 95, leaked: 3, live: 12 },
    Path: { created: 4, deleted: 0, leaked: 0, live: 4 },
  });
  f.contents.emit("console-message", { level: "info", message: "Engine counters:\n  Picture Created: 160\n  Picture Deleted: 120\n  Picture Leaked: 5\n  Path Created: 4" });
  f.advance(60_000);
  f.sample();
  assert.deepEqual(f.entries.at(-1).engineCounters, {
    Picture: { created: 160, deleted: 120, leaked: 5, live: 35, createdDelta: 50, deletedDelta: 25, leakedDelta: 2, liveDelta: 23 },
    Path: { created: 4, deleted: 0, leaked: 0, live: 4, createdDelta: 0, deletedDelta: 0, leakedDelta: 0, liveDelta: 0 },
  });
  f.contents.emit("did-finish-load");
  f.advance(60_000);
  f.sample();
  assert.equal("engineCounters" in f.entries.at(-1), false, "a new document starts without counters");
  assert.doesNotMatch(JSON.stringify(f.entries), /secret|private|https/);
  f.diagnostics.dispose();
});

test("the process allowlist mapper is shared with the diagnostics report", () => {
  assert.deepEqual(sanitizeAppMetrics([{ type: "Tab", pid: 4, name: "secret", cpu: { percentCPUUsage: 3 },
    memory: { workingSetSize: 10, peakWorkingSetSize: 20 } }, { type: "Mystery" }]), [
    { type: "Tab", pid: 4, cpuPercent: 3, workingSetKiB: 10, peakWorkingSetKiB: 20 },
    { type: "other", pid: null, cpuPercent: null, workingSetKiB: null, peakWorkingSetKiB: null },
  ]);
  assert.deepEqual(sanitizeAppMetrics(null), []);
  assert.equal(sanitizeAppMetrics(Array.from({ length: 20 }, () => ({ type: "Utility" }))).length, 12);
});
