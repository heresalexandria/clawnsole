"use strict";

// Run with ./node_modules/.bin/electron scripts/smoke-recovery.cjs.
// Uses a fresh profile and synthetic page; never opens a user's library.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const { once } = require("node:events");
const { app, BrowserWindow } = require("electron");
const { configureSmokeProfile } = require("../lib/smoke-profile.cjs");
const { installRendererRecovery } = require("../lib/renderer-recovery.cjs");

app.setName("Clawnsole Recovery Smoke");
const profile = configureSmokeProfile(app, { smoke: true });
let window;
let done = false;
const deadline = setTimeout(() => finish(new Error("Recovery smoke timed out")), 45_000);
function finish(error = null) {
  if (done) return;
  done = true;
  clearTimeout(deadline);
  window?.destroy();
  if (error) console.error(error);
  else console.log("Recovery smoke passed: 6 real renderer crashes and 1 dead-engine reload recovered; shell stayed alive.");
  try { fs.rmSync(profile, { recursive: true, force: true }); } catch { /* App teardown may still hold a file. */ }
  app.exit(error ? 1 : 0);
}

app.whenReady().then(async () => {
  window = new BrowserWindow({
    show: false,
    webPreferences: { sandbox: true, contextIsolation: true, nodeIntegration: false },
  });
  let prompts = 0;
  const records = [];
  const recovery = installRendererRecovery({
    window,
    // Exercise both the initial automatic recovery and the explicit crash-loop
    // reload path without displaying interactive dialogs in automation.
    showMessage: async () => { prompts += 1; return { response: 0 }; },
    relaunch: () => { throw new Error("Unexpected relaunch"); },
    quit: () => { throw new Error("Unexpected quit"); },
    log: { write: (_, entry) => records.push(entry) },
  });
  await window.loadURL("data:text/html,<title>Recovery fixture</title><p id='ready'>Ready</p>");
  for (let cycle = 0; cycle < 6; cycle += 1) {
    const loaded = once(window.webContents, "did-finish-load");
    window.webContents.forcefullyCrashRenderer();
    await loaded;
    assert.equal(await window.webContents.executeJavaScript("document.getElementById('ready').textContent"), "Ready");
  }
  assert.equal(prompts, 3);
  assert.equal(records.filter((entry) => entry.startsWith("renderer-gone ")).length, 6);
  // A dead Flutter engine inside a live process arrives through recoverFrom
  // and reuses the same budget: the last dialog answer restored it, so this
  // reload is silent, and the duplicate trigger is ignored.
  const reloaded = once(window.webContents, "did-finish-load");
  assert.equal(recovery.recoverFrom("engine-abort"), true);
  assert.equal(recovery.recoverFrom("frames-frozen"), true);
  await reloaded;
  assert.equal(await window.webContents.executeJavaScript("document.getElementById('ready').textContent"), "Ready");
  assert.equal(prompts, 3);
  assert.equal(records.filter((entry) => entry.startsWith("renderer-engine-dead ")).length, 2);
  assert.equal(records.filter((entry) => entry === "renderer-reload").length, 7);
  assert.equal(recovery.recoverFrom("unknown"), false);
  finish();
}).catch(finish);
