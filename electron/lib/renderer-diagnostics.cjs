"use strict";

const crypto = require("node:crypto");

const DIAGNOSTIC_CHANNEL = "clawnsole:diagnostic";
const RENDERER_EVENTS = new Set([
  "flutter-error", "flutter-platform-error", "flutter-ready", "flutter-health",
  "web-error", "web-unhandled-rejection", "webgl-context-lost",
  "webgl-context-restored", "bootstrap-error",
]);
const METRIC_FIELDS = [
  "frameCount", "lastFrameAgeMs", "cacheBytes", "cacheImages", "liveImages", "pendingImages",
  "canvasKitHeapBytes", "canvasKitDecodeCacheBytes", "canvasKitDecodeCacheLimitBytes",
  "appActive",
  "flutterErrorsSuppressed",
];
const INTERNAL_EVENTS = new Set([
  "renderer-console-error", "renderer-console-warning", "renderer-preload-error",
  "renderer-load-failed", "renderer-process-metrics",
]);
const PROCESS_TYPES = new Set(["Browser", "Tab", "Renderer", "GPU", "Utility", "Zygote", "Sandbox helper"]);
const WINDOW_MS = 60_000;
const MAX_PER_EVENT = 3;

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
  if (payload.event === "flutter-health") {
    for (const key of METRIC_FIELDS) {
      const value = finiteNumber(payload[key]);
      if (value !== null) result[key] = value;
    }
  }
  return result;
}

function consoleCategory(message) {
  const text = typeof message === "string" ? message.slice(0, 4096) : "";
  if (/context[_ -]?lost|CONTEXT_LOST_WEBGL/i.test(text)) return "graphics-context-lost";
  if (/out of memory|allocation failed|memory access out of bounds/i.test(text)) return "memory-failure";
  if (/CanvasKit|WebGL|skwasm/i.test(text)) return "graphics-error";
  if (/maximum call stack|stack overflow/i.test(text)) return "stack-overflow";
  return "unclassified";
}

class RendererDiagnostics {
  constructor({ contents, log, getAppMetrics = () => [], now = Date.now,
    setIntervalImpl = setInterval, clearIntervalImpl = clearInterval }) {
    this.contents = contents;
    this.log = log;
    this.getAppMetrics = getAppMetrics;
    this.now = now;
    this.clearInterval = clearIntervalImpl;
    this.events = new Map();
    this.disposed = false;
    this.listeners = [];
    this.lastHealthAt = null;
    const listen = (name, listener) => {
      contents.on(name, listener);
      this.listeners.push([name, listener]);
    };
    listen("console-message", (details, ...legacy) => {
      const [legacyLevel, legacyMessage, legacyLine, legacySource] = legacy;
      const level = details?.level ?? ({ 2: "warning", 3: "error" }[legacyLevel]);
      if (level !== "warning" && level !== "error") return;
      const event = `renderer-console-${level}`;
      if (this.suppressFlood(event)) return;
      const message = details?.message ?? legacyMessage;
      const source = details?.sourceId ?? legacySource;
      const line = details?.lineNumber ?? legacyLine;
      this.record({
        event,
        category: consoleCategory(message),
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
    listen("destroyed", () => this.dispose());
    this.timer = setIntervalImpl(() => this.sample(), WINDOW_MS);
    this.timer?.unref?.();
  }

  report(payload) {
    try {
      if (!payload || !RENDERER_EVENTS.has(payload.event) || this.suppressFlood(payload.event, suppressionCount(payload.suppressed) ?? 1)) return;
      const clean = sanitizeDiagnostic(payload);
      if (clean) {
        if (clean.event === "flutter-health") this.lastHealthAt = this.now();
        this.record(clean);
      }
    } catch { /* Invalid IPC diagnostics must not affect the application. */ }
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
      const processes = this.getAppMetrics().slice(0, 12).map((metric) => ({
        type: PROCESS_TYPES.has(metric.type) ? metric.type : "other",
        pid: Number.isSafeInteger(metric.pid) ? metric.pid : null,
        cpuPercent: finiteNumber(metric.cpu?.percentCPUUsage, 1e5),
        workingSetKiB: finiteNumber(metric.memory?.workingSetSize),
        peakWorkingSetKiB: finiteNumber(metric.memory?.peakWorkingSetSize),
      }));
      this.record({ event: "renderer-process-metrics", flutterHealthAgeMs: this.lastHealthAt === null ? null : Math.max(0, this.now() - this.lastHealthAt), processes });
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

module.exports = { DIAGNOSTIC_CHANNEL, RendererDiagnostics, sanitizeDiagnostic, sanitizeStack, installDiagnosticIpc };
