"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const { STORAGES, clearRendererOriginStorage } = require("../lib/renderer-storage.cjs");

test("service workers and cache storage are cleared for the renderer origin only", async () => {
  const calls = [];
  const session = { clearStorageData: async (options) => { calls.push(options); } };
  assert.equal(await clearRendererOriginStorage(session, "http://127.0.0.1:50691/index.html?x=1"), true);
  assert.deepEqual(calls, [{ origin: "http://127.0.0.1:50691", storages: [...STORAGES] }]);
  assert.deepEqual(STORAGES, ["serviceworkers", "cachestorage"]);
});

test("an invalid URL, a missing session, or a failing clear never throws", async () => {
  assert.equal(await clearRendererOriginStorage({ clearStorageData: async () => {} }, "not a url"), false);
  assert.equal(await clearRendererOriginStorage(null, "http://127.0.0.1:1/"), false);
  const failing = { clearStorageData: async () => { throw new Error("busy"); } };
  assert.equal(await clearRendererOriginStorage(failing, "http://127.0.0.1:1/"), false);
});
