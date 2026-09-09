"use strict";

const crypto = require("node:crypto");

const DIAGNOSTIC_CHANNEL = "clawnsole:diagnostic";
const RENDERER_EVENTS = new Set([
  "flutter-error", "flutter-platform-error", "flutter-ready", "flutter-health",
  "flutter-engine-stalled", "flutter-motion-constrained", "flutter-lifecycle",
  "web-error", "web-unhandled-rejection", "webgl-context-lost",
  "webgl-context-restored", "bootstrap-error",
]);
const METRIC_FIELDS = [
  "frameCount", "lastFrameAgeMs", "cacheBytes", "cacheImages", "liveImages", "pendingImages",
  "canvasKitHeapBytes", "canvasKitDecodeCacheBytes", "canvasKitDecodeCacheLimitBytes",
  "appActive",
  "flutterErrorsSuppressed",
  "lifecycleState", "documentHidden", "framesSinceLastHealth", "motionConstrained", "heapPressure",
];
// Numeric fields kept for the Flutter app's own self-reports. The Dart side
// reports a stall or a latched motion brake with codes and byte counts only.
const EVENT_FIELDS = {
  "flutter-health": METRIC_FIELDS,
  "flutter-engine-stalled": ["lastFrameAgeMs", "errorsInWindow"],
  "flutter-motion-constrained": ["heapBytes"],
  "flutter-lifecycle": ["lifecycleState"],
};
const INTERNAL_EVENTS = new Set([
  "renderer-console-error", "renderer-console-warning", "renderer-preload-error",
  "renderer-load-failed", "renderer-process-metrics",
  "renderer-engine-stalled", "renderer-heap-growth", "renderer-error-storm",
]);
// Events whose per-minute totals decide whether a frozen engine is dead or
// merely idle. Preload "suppressed" summaries count toward the same totals.
const ERROR_RATE_EVENTS = new Set([
  "flutter-error", "web-error", "web-unhandled-rejection", "renderer-console-error",
]);
const PROCESS_TYPES = new Set(["Browser", "Tab", "Renderer", "GPU", "Utility", "Zygote", "Sandbox helper"]);
const WINDOW_MS = 60_000;
const MAX_PER_EVENT = 3;

// Derived-alert thresholds. The wasm heap cannot grow past 2 GiB; an engine
// that stops completing frames while errors keep arriving is dead, whereas a
// static screen with no frames and no errors is simply idle.
const MiB = 1024 * 1024;
const STALLED_RECORDS = 2;
const ERROR_STORM_PER_MINUTE = 1000;
const HEAP_GROWTH_STEP_BYTES = 64 * MiB;
const HEAP_GROWTH_WINDOW_BYTES = 256 * MiB;
const HEAP_GROWTH_WINDOW_DELTAS = 5;
const HEAP_CRITICAL_BYTES = 1.5 * 1024 * MiB;

// Flutter's instrumented engine prints object counters at most every 2 s.
// Only lines of this exact shape are parsed; the rest of console text is
// never retained.
const ENGINE_COUNTERS_PREFIX = "Engine counters:";
const ENGINE_COUNTER_LINE = /^\s*([A-Za-z][A-Za-z0-9. ]{0,40}) (Created|Deleted|Leaked): (\d{1,12})$/;
const MAX_COUNTER_LABELS = 64;

function identifier(value) {
  return typeof value === "string" && /^[A-Za-z_$][\w$]{0,63}$/.test(value)
    ? value : "UnknownError";
}

// Keep executable locations and function identifiers, never the exception's
// first line, full source URLs, queries, arguments, or filesystem directories.
function sanitizeStack(value) {
  if (typeof value !== "string") return [];
  const frames = [];
  for (const raw of value.slice(0, 32768).split(/\r?\n/).slice(0, 80)) {
    const line = raw.trim();
    if (line.length > 2048) continue;
    if (!/^(?:at\s|#\d+\s|[A-Za-z_$][\w.$<>]*@)/.test(line)) continue;
    const wasm = /(?:([A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*\.wasm)|wasm:\/\/wasm\/[^\s():]{1,200}):wasm-function\[(\d{1,9})\]:(0x[\da-fA-F]{1,16})\)?$/.exec(line);
    if (wasm) {
      frames.push({ source: wasm[1]?.slice(0, 100) ?? "wasm", functionIndex: Number(wasm[2]), offset: wasm[3].toLowerCase() });
      if (frames.length === 12) break;
      continue;
    }
    const location = /(?:^|[\s(/\\])([A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*\.(?:js|dart|wasm)):(\d{1,9})(?::(\d{1,9}))?(?:\)?\s*$)/.exec(line);
    if (!location) continue;
    const prefix = line.slice(0, location.index).replace(/^(?:at\s+|#\d+\s+)/, "");
    const functionMatch = /^([A-Za-z_$][\w.$<>]{0,95})(?:\s*\(|@)/.exec(prefix);
    frames.push({
      source: location[1].slice(0, 100),
      line: Number(location[2]),
      column: location[3] === undefined ? null : Number(location[3]),
      ...(functionMatch ? { function: functionMatch[1] } : {}),
    });
    if (frames.length === 12) break;
  }
  return frames;
}

function finiteNumber(value, maximum = 1e15) {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 && value <= maximum
    ? Math.round(value * 100) / 100 : null;
}

function suppressionCount(value) {
  return Number.isSafeInteger(value) && value > 0 && value <= 1e9 ? value : null;
}

function sanitizeDiagnostic(payload) {
  if (!payload || typeof payload !== "object" || !RENDERER_EVENTS.has(payload.event)) return null;
  const result = { event: payload.event };
  if (suppressionCount(payload.suppressed) !== null) result.suppressed = payload.suppressed;
  if (payload.errorType !== undefined) result.errorType = identifier(payload.errorType);
  const frames = sanitizeStack(payload.stack);
  if (frames.length) result.frames = frames;
  const fields = EVENT_FIELDS[payload.event];
  if (fields) {
    for (const key of fields) {
      const value = finiteNumber(payload[key]);
      if (value !== null) result[key] = value;
    }
  }
  return result;
}

function consoleCategory(message) {
  const text = typeof message === "string" ? message.slice(0, 4096) : "";
  if (/\bAborted\(|Cannot enlarge memory|RuntimeError: Aborted/i.test(text)) return "engine-abort";
  if (/context[_ -]?lost|CONTEXT_LOST_WEBGL/i.test(text)) return "graphics-context-lost";
  if (/out of memory|allocation failed|memory access out of bounds/i.test(text)) return "memory-failure";
  if (/CanvasKit|WebGL|skwasm/i.test(text)) return "graphics-error";
  if (/maximum call stack|stack overflow/i.test(text)) return "stack-overflow";
  return "unclassified";
}

// Parses one "Engine counters:" console message into {label: {created,
// deleted, leaked}}. Unknown lines are dropped; the label charset is fixed.
function parseEngineCounters(message) {
  const counters = new Map();
  if (typeof message !== "string" || !message.startsWith(ENGINE_COUNTERS_PREFIX)) return counters;
  for (const line of message.slice(0, 16384).split(/\r?\n/).slice(1, 400)) {
    const match = ENGINE_COUNTER_LINE.exec(line);
    if (!match) continue;
    const label = match[1].trim();
    let entry = counters.get(label);
    if (!entry) {
      if (counters.size >= MAX_COUNTER_LABELS) continue;
      entry = { created: 0, deleted: 0, leaked: 0 };
      counters.set(label, entry);
    }
    entry[match[2].toLowerCase()] = Number(match[3]);
  }
  return counters;
}

// The process allowlist shared by the minute sample and the diagnostics
// report: types, pids, CPU and working sets only, never names or commands.
function sanitizeAppMetrics(metrics) {
  return (Array.isArray(metrics) ? metrics : []).slice(0, 12).map((metric) => ({
    type: PROCESS_TYPES.has(metric?.type) ? metric.type : "other",
    pid: Number.isSafeInteger(metric?.pid) ? metric.pid : null,
    cpuPercent: finiteNumber(metric?.cpu?.percentCPUUsage, 1e5),
    workingSetKiB: finiteNumber(metric?.memory?.workingSetSize),
    peakWorkingSetKiB: finiteNumber(metric?.memory?.peakWorkingSetSize),
  }));
}

function perMinute(count, intervalMs) {
  return intervalMs > 0 ? Math.round(count * WINDOW_MS / intervalMs) : null;
}

class RendererDiagnostics {
  constructor({ contents, log, getAppMetrics = () => [], onAlert = () => {}, now = Date.now,
    setIntervalImpl = setInterval, clearIntervalImpl = clearInterval }) {
    this.contents = contents;
    this.log = log;
    this.getAppMetrics = getAppMetrics;
    this.onAlert = onAlert;
    this.now = now;
    this.clearInterval = clearIntervalImpl;
    this.events = new Map();
    this.disposed = false;
    this.listeners = [];
    this.lastHealthAt = null;
    this.errorMinute = { startedAt: null, counts: new Map(), stormed: new Set() };
    this.engineCounters = new Map();
    this.previousEngineCounters = new Map();
    this.resetEngineState();
    const listen = (name, listener) => {
      contents.on(name, listener);
      this.listeners.push([name, listener]);
    };
    listen("console-message", (details, ...legacy) => {
      const [legacyLevel, legacyMessage, legacyLine, legacySource] = legacy;
      const level = details?.level ?? ({ 1: "info", 2: "warning", 3: "error" }[legacyLevel]);
      const message = details?.message ?? legacyMessage;
      if (level === "info" || level === "log") {
        if (typeof message === "string" && message.startsWith(ENGINE_COUNTERS_PREFIX)) {
          this.adoptEngineCounters(parseEngineCounters(message));
        }
        return;
      }
      if (level !== "warning" && level !== "error") return;
      const event = `renderer-console-${level}`;
      const category = consoleCategory(message);
      if (level === "error") this.countError(event, 1);
      if (category === "engine-abort") this.alertEngineDead("engine-abort", {});
      if (this.suppressFlood(event)) return;
      const source = details?.sourceId ?? legacySource;
      const line = details?.lineNumber ?? legacyLine;
      this.record({
        event,
        category,
        frames: sanitizeStack(`${typeof message === "string" ? message.slice(0, 32768) : ""}\nat console (${typeof source === "string" ? source.slice(0, 2048) : ""}:${line}:0)`),
      });
    });
    listen("preload-error", (_event, _path, error) => this.record({
      event: "renderer-preload-error", errorType: identifier(error?.name), frames: sanitizeStack(error?.stack),
    }));
    listen("did-fail-load", (_event, code, _description, _url, mainFrame) => {
      if (mainFrame !== true) return;
      this.record({ event: "renderer-load-failed", code: Number.isSafeInteger(code) ? code : null });
    });
    // A new document is a new Flutter instance: derived state from the old
    // one must not fire alerts against it.
    listen("did-finish-load", () => this.resetEngineState());
    listen("destroyed", () => this.dispose());
    this.timer = setIntervalImpl(() => this.sample(), WINDOW_MS);
    this.timer?.unref?.();
  }

  resetEngineState() {
    this.previousHealth = null;
    this.stalledRecords = 0;
    this.heapDeltas = [];
    this.errorsSinceHealth = 0;
    this.engineDeadReported = false;
    this.heapCriticalReported = false;
    this.lastFramesPerMinute = null;
    this.lastHeapBytes = null;
    this.engineCounters = new Map();
    this.previousEngineCounters = new Map();
  }

  report(payload) {
    try {
      if (!payload || !RENDERER_EVENTS.has(payload.event)) return;
      this.countError(payload.event, suppressionCount(payload.suppressed) ?? 1);
      if (this.suppressFlood(payload.event, suppressionCount(payload.suppressed) ?? 1)) return;
      const clean = sanitizeDiagnostic(payload);
      if (clean) {
        if (clean.event === "flutter-health") this.observeHealth(clean);
        // Flutter's own stall verdict (flutter-engine-stalled) is recorded as
        // corroboration only. Page content cannot earn a reload by sending an
        // event: recovery follows the shell's rule over the health records it
        // received itself (observeHealth).
        this.record(clean);
      }
    } catch { /* Invalid IPC diagnostics must not affect the application. */ }
  }

  // Per-minute error totals across every source, counted before any flood
  // suppression so a storm is measured rather than hidden by the caps.
  countError(event, count) {
    if (this.disposed || !ERROR_RATE_EVENTS.has(event)) return;
    const at = this.now();
    const minute = this.errorMinute;
    if (minute.startedAt === null || at - minute.startedAt >= WINDOW_MS) {
      minute.startedAt = at;
      minute.counts.clear();
      minute.stormed.clear();
    }
    const total = Math.min(1e9, (minute.counts.get(event) ?? 0) + count);
    minute.counts.set(event, total);
    this.errorsSinceHealth = Math.min(1e9, this.errorsSinceHealth + count);
    if (total >= ERROR_STORM_PER_MINUTE && !minute.stormed.has(event)) {
      minute.stormed.add(event);
      const details = { sourceEvent: event, perMinute: total };
      this.record({ event: "renderer-error-storm", ...details });
      this.alert("error-storm", details);
    }
  }

  // Derives frame, heap and error deltas from consecutive health records.
  // A negative frame delta means Flutter restarted, which resets everything.
  observeHealth(health) {
    const at = this.now();
    const previous = this.previousHealth;
    const previousAt = this.lastHealthAt;
    const errors = this.errorsSinceHealth;
    this.lastHealthAt = at;
    this.previousHealth = health;
    this.errorsSinceHealth = 0;
    if (typeof health.canvasKitHeapBytes === "number") this.lastHeapBytes = health.canvasKitHeapBytes;
    if (!previous || previousAt === null) return;
    const intervalMs = Math.max(0, at - previousAt);
    const framesDelta = typeof health.frameCount === "number" && typeof previous.frameCount === "number"
      ? health.frameCount - previous.frameCount : null;
    if (framesDelta !== null && framesDelta < 0) {
      const heap = this.lastHeapBytes;
      this.resetEngineState();
      this.previousHealth = health;
      this.lastHeapBytes = heap;
      return;
    }
    const flutterErrorsDelta = typeof health.flutterErrorsSuppressed === "number"
      && typeof previous.flutterErrorsSuppressed === "number"
      ? Math.max(0, health.flutterErrorsSuppressed - previous.flutterErrorsSuppressed) : 0;
    const errorsPerMinute = perMinute(errors, intervalMs) ?? errors;
    const framesPerMinute = framesDelta === null ? null : perMinute(framesDelta, intervalMs);
    if (framesPerMinute !== null) this.lastFramesPerMinute = framesPerMinute;
    if (framesDelta === 0) this.stalledRecords += 1;
    else if (framesDelta !== null) {
      this.stalledRecords = 0;
      this.engineDeadReported = false;
    }
    const stalled = framesDelta === 0 && this.stalledRecords >= STALLED_RECORDS
      && health.appActive === 1 && (flutterErrorsDelta > 0 || errorsPerMinute >= ERROR_STORM_PER_MINUTE);
    if (stalled) {
      const details = {
        framesDelta, intervalMs, lastFrameAgeMs: health.lastFrameAgeMs ?? null, appActive: 1,
        flutterErrorsDelta, errorsPerMinute, consecutiveMinutes: this.stalledRecords,
      };
      this.record({ event: "renderer-engine-stalled", ...details });
      this.alertEngineDead("frames-frozen", details);
    }
    this.observeHeap(health, previous, { framesDelta, intervalMs, framesPerMinute });
  }

  observeHeap(health, previous, { framesDelta, intervalMs, framesPerMinute }) {
    const heapBytes = health.canvasKitHeapBytes;
    if (typeof heapBytes !== "number") return;
    const heapDeltaBytes = typeof previous.canvasKitHeapBytes === "number"
      ? heapBytes - previous.canvasKitHeapBytes : null;
    if (heapDeltaBytes !== null) {
      this.heapDeltas.push(heapDeltaBytes);
      if (this.heapDeltas.length > HEAP_GROWTH_WINDOW_DELTAS) this.heapDeltas.shift();
    }
    // Growth summed over the last five deltas catches a leak that stays
    // just under the single-interval step.
    const windowGrowth = this.heapDeltas.length === HEAP_GROWTH_WINDOW_DELTAS
      ? this.heapDeltas.reduce((total, delta) => total + delta, 0) : 0;
    const critical = heapBytes >= HEAP_CRITICAL_BYTES;
    const growing = (heapDeltaBytes !== null && heapDeltaBytes >= HEAP_GROWTH_STEP_BYTES)
      || windowGrowth >= HEAP_GROWTH_WINDOW_BYTES;
    if (!critical) this.heapCriticalReported = false;
    if (!critical && !growing) return;
    const details = {
      heapBytes, heapDeltaBytes, framesDelta, intervalMs, framesPerMinute, critical: critical ? 1 : 0,
    };
    this.record({ event: "renderer-heap-growth", ...details });
    if (growing) this.alert("heap-growth", details);
    if (critical && !this.heapCriticalReported) {
      this.heapCriticalReported = true;
      this.alert("heap-critical", { reason: "heap-critical", ...details });
    }
  }

  // One engine-dead alert per episode: a reload (new document or a positive
  // frame delta) re-arms it, so a pending prompt is not re-triggered every
  // minute while the user decides.
  alertEngineDead(reason, details) {
    if (this.engineDeadReported) return;
    this.engineDeadReported = true;
    this.alert("engine-dead", { reason, ...details });
  }

  alert(kind, details) {
    if (this.disposed) return;
    try { this.onAlert(kind, details); } catch { /* Alerts are advisory. */ }
  }

  adoptEngineCounters(counters) {
    if (this.disposed || counters.size === 0) return;
    this.engineCounters = counters;
  }

  engineCounterSummary() {
    const summary = {};
    for (const [label, entry] of this.engineCounters) {
      const live = entry.created - entry.deleted - entry.leaked;
      const previous = this.previousEngineCounters.get(label);
      summary[label] = {
        created: entry.created, deleted: entry.deleted, leaked: entry.leaked, live,
        ...(previous ? {
          createdDelta: entry.created - previous.created,
          deletedDelta: entry.deleted - previous.deleted,
          leakedDelta: entry.leaked - previous.leaked,
          liveDelta: live - (previous.created - previous.deleted - previous.leaked),
        } : {}),
      };
    }
    this.previousEngineCounters = this.engineCounters;
    return summary;
  }

  suppressFlood(event, count = 1) {
    if (this.disposed) return true;
    const bucket = this.events.get(event);
    if (!bucket || this.now() - bucket.startedAt >= WINDOW_MS || bucket.received < 32) return false;
    bucket.suppressed = Math.min(1e9, bucket.suppressed + count);
    return true;
  }

  record(payload) {
    if (this.disposed || !RENDERER_EVENTS.has(payload.event) && !INTERNAL_EVENTS.has(payload.event)) return;
    const at = this.now();
    let bucket = this.events.get(payload.event);
    if (!bucket || at - bucket.startedAt >= WINDOW_MS) {
      if (bucket) this.flushBucket(payload.event, bucket);
      bucket = { startedAt: at, signatures: new Set(), suppressed: 0, received: 0 };
      this.events.set(payload.event, bucket);
    }
    bucket.received += 1;
    const json = JSON.stringify(payload);
    const signature = crypto.createHash("sha256").update(json).digest("hex").slice(0, 16);
    if (bucket.signatures.has(signature) || bucket.signatures.size >= MAX_PER_EVENT) {
      bucket.suppressed = Math.min(1e9, bucket.suppressed + (suppressionCount(payload.suppressed) ?? 1));
      return;
    }
    bucket.signatures.add(signature);
    this.write(json);
  }

  flushBucket(event, bucket) {
    if (bucket.suppressed) this.write(JSON.stringify({ event: "renderer-diagnostic-summary", sourceEvent: event, suppressed: bucket.suppressed }));
  }

  sample() {
    if (this.disposed) return;
    for (const [event, bucket] of this.events) {
      this.flushBucket(event, bucket);
    }
    this.events.clear();
    try {
      const processes = sanitizeAppMetrics(this.getAppMetrics());
      const metrics = { event: "renderer-process-metrics", flutterHealthAgeMs: this.lastHealthAt === null ? null : Math.max(0, this.now() - this.lastHealthAt) };
      if (this.lastFramesPerMinute !== null) metrics.framesPerMinute = this.lastFramesPerMinute;
      if (this.lastHeapBytes !== null) metrics.heapBytes = this.lastHeapBytes;
      metrics.processes = processes;
      if (this.engineCounters.size) metrics.engineCounters = this.engineCounterSummary();
      this.record(metrics);
    } catch { /* Process sampling is optional and never probes renderer JS. */ }
  }

  write(entry) {
    try { this.log?.write("renderer", entry); } catch { /* Best effort. */ }
  }

  dispose() {
    if (this.disposed) return;
    this.disposed = true;
    this.clearInterval(this.timer);
    for (const [name, listener] of this.listeners) this.contents.removeListener(name, listener);
    for (const [event, bucket] of this.events) this.flushBucket(event, bucket);
    this.events.clear();
  }
}

function installDiagnosticIpc(ipcMain, isTrustedEvent, getDiagnostics) {
  const listener = (event, payload) => {
    if (isTrustedEvent(event)) getDiagnostics()?.report(payload);
  };
  ipcMain.on(DIAGNOSTIC_CHANNEL, listener);
  return () => ipcMain.removeListener(DIAGNOSTIC_CHANNEL, listener);
}

module.exports = {
  DIAGNOSTIC_CHANNEL,
  ENGINE_COUNTERS_PREFIX,
  HEAP_CRITICAL_BYTES,
  HEAP_GROWTH_STEP_BYTES,
  HEAP_GROWTH_WINDOW_BYTES,
  RendererDiagnostics,
  consoleCategory,
  installDiagnosticIpc,
  parseEngineCounters,
  sanitizeAppMetrics,
  sanitizeDiagnostic,
  sanitizeStack,
};
