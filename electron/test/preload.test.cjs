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
  const electron = {
    contextBridge: {
      exposeInMainWorld: (key, value) => {
        exposed[key] = value;
      },
    },
    ipcRenderer: {
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
  }
  return { exposed, invoked, listeners };
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

  await bridge.checkForUpdate();
  await bridge.checkForUpdate(true);
  await bridge.startUpdate();
  await bridge.authorizeGoogleDrive();
  await bridge.disconnectGoogleDrive();
  assert.deepEqual(
    invoked.map((call) => call.channel),
    [
      "clawnsole:update:check",
      "clawnsole:update:check",
      "clawnsole:update:start",
      "clawnsole:drive:authorize",
      "clawnsole:drive:disconnect",
    ],
  );
  assert.deepEqual(invoked[0].args, [false]);
  assert.deepEqual(invoked[1].args, [true]);
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
