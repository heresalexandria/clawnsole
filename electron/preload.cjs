"use strict";

const { contextBridge, ipcRenderer } = require("electron");
const rendererWindow = window;

const DIAGNOSTIC_EVENTS = new Set([
  "flutter-error", "flutter-platform-error", "flutter-ready", "flutter-health",
  "flutter-engine-stalled", "flutter-motion-constrained", "flutter-lifecycle",
  "web-error", "web-unhandled-rejection", "webgl-context-lost",
  "webgl-context-restored", "bootstrap-error",
]);
const HEALTH_FIELDS = [
  "frameCount", "lastFrameAgeMs", "cacheBytes", "cacheImages", "liveImages", "pendingImages",
  "canvasKitHeapBytes", "canvasKitDecodeCacheBytes", "canvasKitDecodeCacheLimitBytes",
  "appActive",
  "flutterErrorsSuppressed",
  "lifecycleState", "documentHidden", "framesSinceLastHealth", "motionConstrained", "heapPressure",
];
// Numeric fields each Flutter-originated event may carry across the bridge.
const EVENT_FIELDS = {
  "flutter-health": HEALTH_FIELDS,
  "flutter-engine-stalled": ["lastFrameAgeMs", "errorsInWindow"],
  "flutter-motion-constrained": ["heapBytes"],
  "flutter-lifecycle": ["lifecycleState"],
};
const diagnosticNow = Date.now;
const diagnosticWindows = new Map();

// Only fixed fields cross the bridge. The main process independently validates
// and redacts stacks before writing its bounded log. Bound IPC traffic too: an
// error storm must not fill the shell's message queue with repeated stacks.
function reportDiagnostic(payload) {
  try {
    if (!payload || !DIAGNOSTIC_EVENTS.has(payload.event)) return;
    const at = diagnosticNow();
    for (const [event, bucket] of diagnosticWindows) {
      if (at - bucket.startedAt < 60_000) continue;
      if (bucket.suppressed) ipcRenderer.send("clawnsole:diagnostic", { event, suppressed: bucket.suppressed });
      diagnosticWindows.delete(event);
    }
    let bucket = diagnosticWindows.get(payload.event);
    if (!bucket) {
      bucket = { startedAt: at, sent: 0, suppressed: 0 };
      diagnosticWindows.set(payload.event, bucket);
    }
    // At most 31 detailed events plus one delayed summary per type/minute.
    if (bucket.sent >= 31) {
      bucket.suppressed = Math.min(1e9, bucket.suppressed + 1);
      return;
    }
    bucket.sent += 1;
    const clean = { event: payload.event };
    if (typeof payload.errorType === "string") clean.errorType = payload.errorType.slice(0, 64);
    if (typeof payload.stack === "string") clean.stack = payload.stack.slice(0, 32768);
    const fields = EVENT_FIELDS[payload.event];
    if (fields) {
      for (const key of fields) {
        if (typeof payload[key] === "number" && Number.isFinite(payload[key])) clean[key] = payload[key];
      }
    }
    ipcRenderer.send("clawnsole:diagnostic", clean);
  } catch { /* Diagnostics must preserve the original error handling. */ }
}

const TEXT_CONTEXT_MENU_CHANNEL = "clawnsole:text-context-menu";
const TEXT_INPUT_TYPES = new Set([
  "email",
  "number",
  "password",
  "search",
  "tel",
  "text",
  "url",
]);

function isTextEditingElement(element) {
  if (!element || typeof element !== "object") return false;
  const tagName = String(element.tagName || "").toUpperCase();
  if (tagName === "TEXTAREA") return true;
  if (tagName === "INPUT") {
    return TEXT_INPUT_TYPES.has(String(element.type || "text").toLowerCase());
  }
  return element.isContentEditable === true;
}

function textEditingElementFromEvent(event) {
  const path = typeof event.composedPath === "function"
    ? event.composedPath()
    : [event.target];
  return path.find(isTextEditingElement) || null;
}

function activeTextEditingElement() {
  let element = rendererWindow.document?.activeElement;
  const visited = new Set();
  while (element && !visited.has(element)) {
    if (isTextEditingElement(element)) return element;
    visited.add(element);
    element = element.shadowRoot?.activeElement || null;
  }
  return null;
}

function textInputState(element) {
  if (!isTextEditingElement(element)) return null;
  const value = "value" in element
    ? String(element.value || "")
    : String(element.textContent || "");
  const selectionStart = Number.isInteger(element.selectionStart)
    ? element.selectionStart
    : null;
  const selectionEnd = Number.isInteger(element.selectionEnd)
    ? element.selectionEnd
    : null;
  return {
    hasSelection: selectionStart !== null
      && selectionEnd !== null
      && selectionStart !== selectionEnd,
    hasText: value.length > 0,
    obscured: String(element.type || "").toLowerCase() === "password",
    readOnly: element.readOnly === true || element.disabled === true,
  };
}

let lastTextMenuRequestAt = 0;
function requestNativeTextMenu(element) {
  const state = textInputState(element);
  if (!state) return false;
  const now = Date.now();
  if (now - lastTextMenuRequestAt < 250) return true;
  lastTextMenuRequestAt = now;
  ipcRenderer.send(TEXT_CONTEXT_MENU_CHANNEL, state);
  return true;
}

rendererWindow.addEventListener("contextmenu", (event) => {
  const element = textEditingElementFromEvent(event)
    || activeTextEditingElement();
  if (requestNativeTextMenu(element)) event.preventDefault();
}, true);

// Flutter consumes the browser contextmenu event for its canvas. A secondary
// pointer press still focuses the engine's real input/textarea, so defer until
// Flutter has moved DOM focus and then ask the main process for an OS menu.
rendererWindow.addEventListener("pointerdown", (event) => {
  if (event.button !== 2) return;
  rendererWindow.setTimeout(() => {
    requestNativeTextMenu(activeTextEditingElement());
  }, 0);
}, true);

// Main-process events reach the renderer through per-channel subscriptions
// that hand back their own unsubscribe function.
function subscribe(channel, callback) {
  if (typeof callback !== "function") return () => {};
  const listener = (_event, payload) => callback(payload);
  ipcRenderer.on(channel, listener);
  return () => ipcRenderer.removeListener(channel, listener);
}

// The renderer-facing shell surface. The Flutter app feature-detects
// `window.clawnsole` to offer in-place updates with download progress.
contextBridge.exposeInMainWorld("clawnsole", {
  shell: "electron",
  reportDiagnostic,
  checkForUpdate: (force = false) =>
    ipcRenderer.invoke("clawnsole:update:check", force === true),
  startUpdate: () => ipcRenderer.invoke("clawnsole:update:start"),
  authorizeGoogleDrive: () =>
    ipcRenderer.invoke("clawnsole:drive:authorize"),
  authorizeGoogleDriveSilently: () =>
    ipcRenderer.invoke("clawnsole:drive:authorizeSilent"),
  disconnectGoogleDrive: () =>
    ipcRenderer.invoke("clawnsole:drive:disconnect"),
  settingsVault: (action, value = "") =>
    ipcRenderer.invoke("clawnsole:vault:settings", action, value),
  openExternalUrl: (url, purpose) =>
    ipcRenderer.invoke("clawnsole:external:open", url, purpose),
  revealDataFolder: () => ipcRenderer.invoke("clawnsole:data:reveal"),
  chooseDataDirectory: () => ipcRenderer.invoke("clawnsole:data:choose"),
  // notify({ title, body }) resolves to true when a system notification was
  // actually posted. The shell posts one only while its window is not
  // focused, so a false result means the in-app UI should say it instead.
  notify: (options) => ipcRenderer.invoke("clawnsole:notify", {
    title: options?.title,
    body: options?.body,
  }).then((shown) => shown === true),
  onUpdateEvent: (callback) => subscribe("clawnsole:update:event", callback),
  // onNavigate receives { section } when a menu item or shortcut such as
  // Settings… (⌘,) asks the app to show a section.
  onNavigate: (callback) => subscribe("clawnsole:navigate", callback),
});

// Error and promise rejection events belong to the world that threw them.
// Register in the page's world, then cross back through the narrow, rate-limited
// bridge. An isolated-world listener alone misses Flutter's JavaScript errors.
try {
  contextBridge.executeInMainWorld({ func: () => {
    const report = window.clawnsole.reportDiagnostic;
    const reportError = (event, property, type) => {
      try {
        const error = event[property];
        report({ event: type, errorType: error?.name, stack: error?.stack });
      } catch {
        report({ event: type });
      }
    };
    window.addEventListener("error", (event) => reportError(event, "error", "web-error"), true);
    window.addEventListener("unhandledrejection", (event) => reportError(event, "reason", "web-unhandled-rejection"), true);
    window.addEventListener("webglcontextlost", () => report({ event: "webgl-context-lost" }), true);
    window.addEventListener("webglcontextrestored", () => report({ event: "webgl-context-restored" }), true);
  } });
} catch (error) {
  reportDiagnostic({ event: "bootstrap-error", errorType: error?.name, stack: error?.stack });
}
