"use strict";

// Run with ./node_modules/.bin/electron scripts/smoke-diagnostics.cjs.
// A synthetic local page and temporary profile never access the user's app.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const http = require("node:http");
const path = require("node:path");
const { once } = require("node:events");
const { app, BrowserWindow, ipcMain, Menu } = require("electron");
const { configureSmokeProfile } = require("../lib/smoke-profile.cjs");
const { buildApplicationMenuTemplate } = require("../lib/application-menu.cjs");
const { rendererIpcGuard } = require("../lib/renderer-ipc.cjs");
const { DIAGNOSTIC_CHANNEL, RendererDiagnostics, installDiagnosticIpc } = require("../lib/renderer-diagnostics.cjs");

app.setName("Clawnsole Diagnostics Smoke");
const profile = configureSmokeProfile(app, { smoke: true });
const windows = [];
let server;
let done = false;
const deadline = setTimeout(() => finish(new Error("Diagnostics smoke timed out")), 45_000);
function finish(error = null) {
  if (done) return;
  done = true;
  clearTimeout(deadline);
  for (const window of windows) if (!window.isDestroyed()) window.destroy();
  server?.close();
  if (error) console.error(error);
  else console.log("Diagnostics smoke passed: isolated browser errors, sanitized WASM stacks, bounded IPC, sender guards, engine counters, engine-abort alert, native recovery menus, and disposal.");
  try { fs.rmSync(profile, { recursive: true, force: true }); } catch { /* Teardown may still hold a file. */ }
  app.exit(error ? 1 : 0);
}

async function waitFor(predicate, label) {
  const deadline = Date.now() + 5000;
  while (!predicate()) {
    if (Date.now() > deadline) throw new Error(`Missing smoke signal: ${label}`);
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
}

app.whenReady().then(async () => {
  server = http.createServer((request, response) => {
    if (request.url === "/fixture.js") {
      response.setHeader("Content-Type", "text/javascript");
      response.end(`window.runSmokeHooks = () => {
        console.warn('CanvasKit DO_NOT_LOG_SECRET');
        console.log('Engine counters:\\n  Picture Created: 120\\n  Picture Deleted: 100\\n  Picture Leaked: 4\\n  DO_NOT_LOG_SECRET Created: 1\\n  Path Created: 7');
        console.log('DO_NOT_LOG_SECRET plain log line');
        console.error('Aborted(DO_NOT_LOG_SECRET). Build with -sASSERTIONS for more info.');
        setTimeout(function fixtureError(){throw new TypeError('DO_NOT_LOG_SECRET')}, 0);
        Promise.reject(new RangeError('DO_NOT_LOG_SECRET'));
        document.getElementById('surface').dispatchEvent(new Event('webglcontextlost'));
        document.getElementById('surface').dispatchEvent(new Event('webglcontextrestored'));
      };`);
      return;
    }
    response.setHeader("Content-Type", "text/html");
    response.end("<!doctype html><title>Diagnostics fixture</title><canvas id='surface'></canvas><script src='/fixture.js'></script>");
  });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const url = `http://127.0.0.1:${server.address().port}`;
  const createWindow = () => {
    const window = new BrowserWindow({ show: false, webPreferences: {
      sandbox: true, contextIsolation: true, nodeIntegration: false,
      preload: path.join(__dirname, "..", "preload.cjs"),
    } });
    windows.push(window);
    return window;
  };
  const window = createWindow();
  const entries = [];
  const alerts = [];
  const diagnostics = new RendererDiagnostics({ contents: window.webContents,
    log: { write: (_label, entry) => entries.push(JSON.parse(entry)) }, getAppMetrics: () => app.getAppMetrics(),
    onAlert: (kind, details) => alerts.push({ kind, ...details }) });
  const guard = rendererIpcGuard({ getWindow: () => window, getRendererUrl: () => url });
  const disposeIpc = installDiagnosticIpc(ipcMain, guard, () => diagnostics);
  let rejected = 0;
  let stormMessages = 0;
  const observe = (event, payload) => {
    if (!guard(event)) rejected += 1;
    if (payload?.event === "flutter-error") stormMessages += 1;
  };
  ipcMain.on(DIAGNOSTIC_CHANNEL, observe);
  await window.loadURL(url);
  assert.deepEqual(await window.webContents.executeJavaScript("[typeof window.clawnsole.reportDiagnostic, typeof require, typeof process]"), ["function", "undefined", "undefined"]);
  await window.webContents.executeJavaScript(`
    window.clawnsole.reportDiagnostic({event:'flutter-ready'});
    window.runSmokeHooks();
    true;
  `);
  const expected = ["flutter-ready", "renderer-console-warning", "web-error", "web-unhandled-rejection", "webgl-context-lost", "webgl-context-restored"];
  try {
    await waitFor(() => expected.every((event) => entries.some((entry) => entry.event === event)), "browser hooks");
  } catch (error) {
    console.error("Received diagnostic events:", entries.map((entry) => entry.event));
    throw error;
  }
  await waitFor(() => alerts.length >= 1, "engine-abort alert");
  assert.deepEqual(alerts, [{ kind: "engine-dead", reason: "engine-abort" }]);
  assert.equal(entries.find((entry) => entry.event === "renderer-console-error").category, "engine-abort");
  assert.equal(entries.find((entry) => entry.event === "web-error").errorType, "TypeError");
  assert.ok(entries.find((entry) => entry.event === "web-error").frames.some((frame) => frame.source === "fixture.js" && frame.function === "fixtureError"));
  assert.equal(entries.find((entry) => entry.event === "web-unhandled-rejection").errorType, "RangeError");
  await window.webContents.executeJavaScript(`
    for(let i=0;i<10000;i++) window.clawnsole.reportDiagnostic({
      event:'flutter-error', errorType:'Error', message:'DO_NOT_LOG_SECRET',
      stack:'Error: DO_NOT_LOG_SECRET\\n at https://example.invalid/private/canvaskit.wasm:wasm-function[9661]:0x45cde5\\n at paint (https://example.invalid/private/main.dart.js:12:34)'
    });
    true;
  `);
  await waitFor(() => stormMessages >= 31, "bounded IPC delivery");
  assert.equal(stormMessages, 31);
  assert.deepEqual(entries.find((entry) => entry.event === "flutter-error").frames, [
    { source: "canvaskit.wasm", functionIndex: 9661, offset: "0x45cde5" },
    { source: "main.dart.js", line: 12, column: 34, function: "paint" },
  ]);
  const other = createWindow();
  await other.loadURL(url);
  await other.webContents.executeJavaScript("window.clawnsole.reportDiagnostic({event:'bootstrap-error'}); true");
  await waitFor(() => rejected === 1, "other-window IPC rejection");
  await window.loadURL(`${url}/untrusted`);
  await window.webContents.executeJavaScript("window.clawnsole.reportDiagnostic({event:'bootstrap-error'}); true");
  await waitFor(() => rejected === 2, "wrong-entry IPC rejection");
  assert.equal(entries.some((entry) => entry.event === "bootstrap-error"), false);
  await window.loadURL(url);
  let logsOpened = 0;
  let reportsSaved = 0;
  const menu = Menu.buildFromTemplate(buildApplicationMenuTemplate({
    appName: "Diagnostics Smoke", isPackaged: true, checkForUpdates() {}, openSettings() {}, openExternalUrl() {},
    reloadStudio: () => window.webContents.reload(), showLogs: () => logsOpened += 1,
    saveDiagnosticsReport: () => reportsSaved += 1,
  }));
  Menu.setApplicationMenu(menu);
  const view = menu.items.find((item) => item.label === "View").submenu;
  const loaded = once(window.webContents, "did-finish-load");
  view.items.find((item) => item.label === "Reload Studio").click();
  await loaded;
  const help = menu.items.find((item) => item.role === "help").submenu.items;
  help.find((item) => item.label === "Show Logs").click();
  help.find((item) => item.label === "Save Diagnostics Report…").click();
  assert.equal(logsOpened, 1);
  assert.equal(reportsSaved, 1);
  // The reload above started a new document, so replay the instrumented
  // engine's counter message and confirm only its numbers reach the sample.
  await window.webContents.executeJavaScript("window.runSmokeHooks(); true");
  await waitFor(() => diagnostics.engineCounters.size === 2, "engine counters");
  diagnostics.sample();
  const metrics = entries.find((entry) => entry.event === "renderer-process-metrics");
  assert.ok(metrics.processes.some((process) => process.type === "Tab"));
  assert.deepEqual(metrics.engineCounters, {
    Picture: { created: 120, deleted: 100, leaked: 4, live: 16 },
    Path: { created: 7, deleted: 0, leaked: 0, live: 7 },
  });
  assert.doesNotMatch(JSON.stringify(entries), /DO_NOT_LOG_SECRET|example\.invalid|https?:|private\//);
  const destroyed = once(window.webContents, "destroyed");
  window.destroy();
  await destroyed;
  assert.equal(diagnostics.disposed, true);
  disposeIpc();
  ipcMain.removeListener(DIAGNOSTIC_CHANNEL, observe);
  finish();
}).catch(finish);
