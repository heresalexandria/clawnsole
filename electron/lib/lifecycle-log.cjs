"use strict";

const PROCESS_REASONS = new Set([
  "clean-exit", "abnormal-exit", "killed", "crashed", "oom", "launch-failed",
  "integrity-failure", "memory-eviction",
]);
// Reasons a live renderer process is treated as dead even though Chromium
// never reported render-process-gone: the Flutter engine aborted inside
// WebAssembly, stopped producing frames while throwing, or its wasm heap is
// about to hit the 2 GiB cap.
const ENGINE_REASONS = new Set(["engine-abort", "frames-frozen", "heap-critical"]);
const PROCESS_TYPES = new Set([
  "GPU", "Utility", "Zygote", "Sandbox helper", "Pepper Plugin",
  "Pepper Plugin Broker", "Browser", "Renderer",
]);

// Lifecycle records contain fixed event names and process metadata only. Never
// copy exception messages, URLs, service names, or renderer content into them.
function processDetails(details = {}) {
  return {
    reason: PROCESS_REASONS.has(details.reason) || ENGINE_REASONS.has(details.reason)
      ? details.reason : "unknown",
    exitCode: Number.isSafeInteger(details.exitCode) ? details.exitCode : null,
    type: PROCESS_TYPES.has(details.type) ? details.type : "unknown",
  };
}

function writeLifecycle(log, event, details = null) {
  try {
    log?.write("shell", `${event}${details ? ` ${JSON.stringify(processDetails(details))}` : ""}`);
  } catch {
    // Diagnostics must not become another failure path.
  }
}

// Event listeners do not consume returned promises. Catch both synchronous
// throws and asynchronous failures at each intentionally detached boundary.
function runShellTask(log, event, action) {
  try {
    return Promise.resolve(action()).catch(() => writeLifecycle(log, event));
  } catch {
    writeLifecycle(log, event);
    return Promise.resolve();
  }
}

function writeStartup(log, appVersion, electronVersion) {
  const version = (value) => typeof value === "string" && /^\d+\.\d+\.\d+(?:[-.][a-zA-Z0-9.]+)?$/.test(value)
    && value.length <= 40 ? value : "unknown";
  writeLifecycle(log, `shell-started app=${version(appVersion)} electron=${version(electronVersion)}`);
}

module.exports = { ENGINE_REASONS, processDetails, runShellTask, writeLifecycle, writeStartup };
