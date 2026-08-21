"use strict";

const assert = require("node:assert/strict");
const Module = require("node:module");
const path = require("node:path");
const test = require("node:test");

// The preload runs inside Electron, so the real module is swapped for a
// recorder that captures the renderer contract it publishes.
function loadPreload() {
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
      },
    },
    ipcRenderer: {
      send: (channel, payload) => sent.push({ channel, payload }),
      invoke: async (channel, ...args) => {
        invoked.push({ channel, args });
        return { channel };
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
