"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const { rendererIpcGuard, guardedRendererHandler } = require("../lib/renderer-ipc.cjs");

test("only the active window's main frame may invoke privileged handlers", () => {
  let origin = "http://127.0.0.1:7357";
  const frame = { url: `${origin}/studio` };
  const contents = { mainFrame: frame, isDestroyed: () => false };
  let window = { webContents: contents, isDestroyed: () => false };
  const trusted = rendererIpcGuard({
    getWindow: () => window,
    getRendererUrl: () => origin,
  });
  let handler;
  let invocations = 0;
  guardedRendererHandler({ handle: (_channel, callback) => { handler = callback; } }, trusted)(
    "clawnsole:drive:authorize", (_event, argument) => {
      invocations += 1;
      return argument;
    },
  );
  const valid = { sender: contents, senderFrame: frame };
  const rejected = (event) => assert.throws(() => handler(event), /request was rejected/);
  assert.equal(handler(valid, "access"), "access");
  rejected({ sender: {}, senderFrame: frame });
  rejected({ sender: contents, senderFrame: { url: frame.url } });
  rejected({ sender: contents, senderFrame: null });
  rejected(undefined);
  frame.url = "https://untrusted.example";
  rejected(valid);
  frame.url = "http://127.0.0.1:7357/studio";
  origin = "http://127.0.0.1:7358";
  rejected(valid);
  frame.url = `${origin}/studio`;
  assert.equal(handler(valid, "refreshed"), "refreshed");
  window = { webContents: { mainFrame: frame, isDestroyed: () => false }, isDestroyed: () => false };
  rejected(valid);
  window = { webContents: contents, isDestroyed: () => true };
  rejected(valid);
  window = null;
  rejected(valid);
  assert.equal(invocations, 2);
});
