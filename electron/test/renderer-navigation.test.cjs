"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const { protectRendererNavigation } = require("../lib/renderer-navigation.cjs");
const { isAllowedAppUrl, isAllowedRendererPermission } = require("../lib/runtime.cjs");
const { rendererIpcGuard } = require("../lib/renderer-ipc.cjs");

const origin = "http://127.0.0.1:7357";
const untrusted = [
  "/media?url=https%3A%2F%2Fexample.com%2Fvideo.mp4", "/assets?id=123",
  "/asset-cache?id=123", "/state", "/health", "/generations/status",
  "/vault/unlock", "/index.html/../media", "/%6dedia", "/icons/Icon-192.png",
  "/flutter_bootstrap.js", "/index.html%2f..%2fassets", "/studio",
];

test("media and API documents never acquire IPC or renderer permissions", () => {
  const frame = { url: origin };
  const contents = { mainFrame: frame, isDestroyed: () => false };
  const window = { webContents: contents, isDestroyed: () => false };
  const trusted = rendererIpcGuard({ getWindow: () => window, getRendererUrl: () => origin });
  for (const path of untrusted) {
    frame.url = origin + path;
    assert.equal(isAllowedAppUrl(frame.url, origin), false, path);
    assert.equal(trusted({ sender: contents, senderFrame: frame }), false, path);
    assert.equal(isAllowedRendererPermission("clipboard-sanitized-write", frame.url, origin), false, path);
  }
  for (const path of ["/", "/?session=launch", "/#/library", "/index.html#/settings"]) {
    frame.url = origin + path;
    assert.equal(trusted({ sender: contents, senderFrame: frame }), true, path);
  }
});

test("navigation and redirects reject media documents while entry reloads and hash routes work", () => {
  const handlers = new Map();
  const external = [];
  let currentOrigin = origin;
  const contents = {
    on: (name, handler) => handlers.set(name, handler),
    setWindowOpenHandler: (handler) => handlers.set("new-window", handler),
  };
  protectRendererNavigation({ contents, getRendererUrl: () => currentOrigin, openExternal: (url) => external.push(url) });
  const prevented = (name, url, legacy = false) => {
    let blocked = false;
    const event = { preventDefault: () => { blocked = true; }, ...(legacy ? {} : { url }) };
    handlers.get(name)(event, url);
    return blocked;
  };
  for (const name of ["will-navigate", "will-redirect"]) {
    for (const path of untrusted) assert.equal(prevented(name, origin + path), true, `${name} ${path}`);
    assert.equal(prevented(name, `${origin}/index.html#/library`), false);
    assert.equal(prevented(name, `${origin}/`, true), false);
  }
  assert.equal(prevented("will-navigate", "https://bfl.ai/docs"), true);
  assert.deepEqual(external, ["https://bfl.ai/docs"]);
  assert.equal(prevented("will-redirect", "https://bfl.ai/redirect"), true);
  assert.deepEqual(external, ["https://bfl.ai/docs"]);
  currentOrigin = "http://127.0.0.1:7358";
  assert.equal(prevented("will-navigate", origin), true);
  assert.equal(prevented("will-navigate", currentOrigin), false);
  assert.deepEqual(handlers.get("new-window")({ url: `${currentOrigin}/media` }), { action: "deny" });
  assert.equal(prevented("will-attach-webview", currentOrigin), true);
});
