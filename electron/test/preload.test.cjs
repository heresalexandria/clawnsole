"use strict";

const assert = require("node:assert/strict");
const Module = require("node:module");
const path = require("node:path");
const test = require("node:test");

// The preload runs inside Electron, so the real module is swapped for a
// recorder that captures the renderer contract it publishes.
function loadPreload({ invokeResult, now = Date.now } = {}) {
  const exposed = {};
  const invoked = [];
  const listeners = new Map();
  const rendererListeners = new Map();
  const sent = [];
  const rendererWindow = {
    document: { activeElement: null },
    addEventListener: (name, listener, capture) => {
      assert.equal(capture, true);
      rendererListeners.set(name, listener);
    },
    setTimeout: (callback) => callback(),
  };
  const electron = {
    contextBridge: {
      exposeInMainWorld: (key, value) => {
        exposed[key] = value;
        rendererWindow[key] = value;
      },
      executeInMainWorld: ({ func }) => func(),
    },
    ipcRenderer: {
      send: (channel, payload) => sent.push({ channel, payload }),
      invoke: async (channel, ...args) => {
        invoked.push({ channel, args });
        return invokeResult === undefined ? { channel } : invokeResult;
      },
      on: (channel, listener) => {
        listeners.set(channel, listener);
      },
      removeListener: (channel, listener) => {
        if (listeners.get(channel) === listener) listeners.delete(channel);
      },
    },
  };

  const load = Module._load;
  const previousWindow = global.window;
  const previousNow = Date.now;
  Date.now = now;
  global.window = rendererWindow;
  Module._load = function (request, ...rest) {
    if (request === "electron") return electron;
    return load.call(this, request, ...rest);
  };
  try {
    const preloadPath = path.join(__dirname, "..", "preload.cjs");
    delete require.cache[require.resolve(preloadPath)];
    require(preloadPath);
  } finally {
    Module._load = load;
    Date.now = previousNow;
    if (previousWindow === undefined) delete global.window;
    else global.window = previousWindow;
  }
  return {
    exposed,
    invoked,
    listeners,
    rendererListeners,
    rendererWindow,
    sent,
  };
}

function textElement(overrides = {}) {
  return {
    tagName: "TEXTAREA",
    type: "textarea",
    value: "Clawnsole",
    selectionStart: 0,
    selectionEnd: 0,
    ...overrides,
  };
}

test("diagnostics bridge bounds stack payloads and excludes arbitrary content before IPC", () => {
  const { exposed, sent } = loadPreload();
  exposed.clawnsole.reportDiagnostic({ event: "flutter-error", errorType: "StateError", stack: "x".repeat(40000), message: "secret", url: "secret" });
  exposed.clawnsole.reportDiagnostic({ event: "private-event", stack: "secret" });
  exposed.clawnsole.reportDiagnostic({ event: "flutter-health", frameCount: 10, cacheBytes: Infinity, privateMetric: 42, canvasKitHeapBytes: 2147483648, flutterErrorsSuppressed: 253000 });
  assert.equal(sent.length, 2);
  assert.equal(sent[0].channel, "clawnsole:diagnostic");
  assert.deepEqual(Object.keys(sent[0].payload).sort(), ["errorType", "event", "stack"]);
  assert.equal(sent[0].payload.stack.length, 32768);
  assert.deepEqual(sent[1].payload, { event: "flutter-health", frameCount: 10, canvasKitHeapBytes: 2147483648, flutterErrorsSuppressed: 253000 });
});

test("browser errors and graphics context events forward diagnostics without suppressing normal handling", () => {
  const { rendererListeners, sent } = loadPreload();
  const event = { error: { name: "TypeError", stack: " at run (main.js:1:2)", message: "secret" },
    reason: "secret rejection", preventDefault() { assert.fail("must preserve browser behavior"); } };
  rendererListeners.get("error")(event);
  rendererListeners.get("unhandledrejection")(event);
  rendererListeners.get("webglcontextlost")(event);
  rendererListeners.get("webglcontextrestored")(event);
  assert.deepEqual(sent.map((call) => call.payload), [
    { event: "web-error", errorType: "TypeError", stack: " at run (main.js:1:2)" },
    { event: "web-unhandled-rejection" }, { event: "webgl-context-lost" }, { event: "webgl-context-restored" },
  ]);
  assert.doesNotMatch(JSON.stringify(sent), /secret/);
});

test("an error storm is bounded before IPC and the next health event carries its suppressed total", () => {
  let clock = 0;
  const { exposed, sent, rendererListeners } = loadPreload({ now: () => clock });
  for (let i = 0; i < 10_000; i += 1) exposed.clawnsole.reportDiagnostic({ event: "flutter-error", stack: "x".repeat(100) });
  assert.equal(sent.length, 31);
  clock = 60_000;
  exposed.clawnsole.reportDiagnostic({ event: "flutter-health", frameCount: 50 });
  assert.deepEqual(sent.at(-2).payload, { event: "flutter-error", suppressed: 9969 });
  assert.deepEqual(sent.at(-1).payload, { event: "flutter-health", frameCount: 50 });
  assert.doesNotThrow(() => rendererListeners.get("error")({ get error() { throw new Error("hostile getter"); } }));
});

test("the preload publishes the renderer update bridge", async () => {
  const { exposed, invoked } = loadPreload();
  const bridge = exposed.clawnsole;

  assert.ok(bridge, "window.clawnsole must be exposed");
  assert.equal(bridge.shell, "electron");
  assert.equal(typeof bridge.checkForUpdate, "function");
  assert.equal(typeof bridge.startUpdate, "function");
  assert.equal(typeof bridge.onUpdateEvent, "function");
  assert.equal(typeof bridge.authorizeGoogleDrive, "function");
  assert.equal(typeof bridge.disconnectGoogleDrive, "function");
  assert.equal(typeof bridge.settingsVault, "function");
  assert.equal(typeof bridge.openExternalUrl, "function");
  assert.equal(typeof bridge.revealDataFolder, "function");
  assert.equal(typeof bridge.chooseDataDirectory, "function");
  assert.equal(typeof bridge.notify, "function");
  assert.equal(typeof bridge.onNavigate, "function");
  assert.equal(typeof bridge.reportDiagnostic, "function");

  await bridge.checkForUpdate();
  await bridge.checkForUpdate(true);
  await bridge.startUpdate();
  await bridge.authorizeGoogleDrive();
  await bridge.disconnectGoogleDrive();
  await bridge.settingsVault("unlock", "passphrase");
  await bridge.settingsVault("sync");
  await bridge.openExternalUrl("https://cdn.example/video.mp4", "media");
  await bridge.revealDataFolder();
  await bridge.chooseDataDirectory();
  await bridge.notify({ title: "Clawnsole", body: "Your video is ready." });
  assert.deepEqual(
    invoked.map((call) => call.channel),
    [
      "clawnsole:update:check",
      "clawnsole:update:check",
      "clawnsole:update:start",
      "clawnsole:drive:authorize",
      "clawnsole:drive:disconnect",
      "clawnsole:vault:settings",
      "clawnsole:vault:settings",
      "clawnsole:external:open",
      "clawnsole:data:reveal",
      "clawnsole:data:choose",
      "clawnsole:notify",
    ],
  );
  assert.deepEqual(invoked[0].args, [false]);
  assert.deepEqual(invoked[1].args, [true]);
  assert.deepEqual(invoked[5].args, ["unlock", "passphrase"]);
  assert.deepEqual(invoked[6].args, ["sync", ""]);
  assert.deepEqual(invoked[7].args, [
    "https://cdn.example/video.mp4",
    "media",
  ]);
});

test("notify passes only a title and body and resolves to a boolean", async () => {
  const shown = loadPreload({ invokeResult: true });
  assert.equal(
    await shown.exposed.clawnsole.notify({
      title: "Clawnsole",
      body: "Your video is ready.",
      icon: "/etc/passwd",
    }),
    true,
  );
  assert.deepEqual(shown.invoked[0].args, [
    { title: "Clawnsole", body: "Your video is ready." },
  ]);

  const suppressed = loadPreload({ invokeResult: false });
  assert.equal(await suppressed.exposed.clawnsole.notify({ title: "x" }), false);

  // A main process that answers with anything but true never reads as shown.
  const malformed = loadPreload({ invokeResult: { ok: true, shown: true } });
  assert.equal(await malformed.exposed.clawnsole.notify(), false);
  assert.deepEqual(malformed.invoked[0].args, [
    { title: undefined, body: undefined },
  ]);
});

test("menu navigation reaches the renderer as a section payload", () => {
  const { exposed, listeners } = loadPreload();
  const seen = [];
  const unsubscribe = exposed.clawnsole.onNavigate((payload) => seen.push(payload));

  const listener = listeners.get("clawnsole:navigate");
  assert.ok(listener, "the bridge must subscribe to the navigate channel");
  listener({}, { section: "settings" });
  assert.deepEqual(seen, [{ section: "settings" }]);

  unsubscribe();
  assert.equal(listeners.has("clawnsole:navigate"), false);
});

test("update events reach the renderer and unsubscribe cleanly", () => {
  const { exposed, listeners } = loadPreload();
  const seen = [];
  const unsubscribe = exposed.clawnsole.onUpdateEvent((payload) => seen.push(payload));

  const listener = listeners.get("clawnsole:update:event");
  assert.ok(listener, "the bridge must subscribe to the update channel");
  listener({}, { phase: "downloading", received: 10, total: 100 });
  assert.deepEqual(seen, [{ phase: "downloading", received: 10, total: 100 }]);

  unsubscribe();
  assert.equal(listeners.has("clawnsole:update:event"), false);
});

test("a non-function subscriber is ignored rather than thrown at", () => {
  const { exposed, listeners } = loadPreload();
  const unsubscribe = exposed.clawnsole.onUpdateEvent("not a function");
  assert.equal(typeof unsubscribe, "function");
  assert.equal(listeners.has("clawnsole:update:event"), false);
  unsubscribe();
});

test("the preload requests a native menu for a renderer text control", () => {
  const { rendererListeners, sent } = loadPreload();
  let prevented = false;
  rendererListeners.get("contextmenu")({
    target: textElement({ selectionStart: 1, selectionEnd: 3 }),
    preventDefault: () => (prevented = true),
  });

  assert.equal(prevented, true);
  assert.deepEqual(sent, [{
    channel: "clawnsole:text-context-menu",
    payload: {
      hasSelection: true,
      hasText: true,
      obscured: false,
      readOnly: false,
    },
  }]);
});

test("the preload falls back to Flutter's focused DOM editor", () => {
  const { rendererListeners, rendererWindow, sent } = loadPreload();
  rendererWindow.document.activeElement = textElement({
    tagName: "INPUT",
    type: "password",
    value: "secret",
  });
  rendererListeners.get("pointerdown")({ button: 2 });

  assert.deepEqual(sent, [{
    channel: "clawnsole:text-context-menu",
    payload: {
      hasSelection: false,
      hasText: true,
      obscured: true,
      readOnly: false,
    },
  }]);
  assert.equal(JSON.stringify(sent).includes("secret"), false);
});
