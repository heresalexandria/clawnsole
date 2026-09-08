"use strict";

// Development-only renderer soak. Loads one URL in a hidden, unthrottled
// window inside an isolated temporary profile and prints one JSON line per
// sample: CanvasKit wasm heap size, requestAnimationFrame rate, Tab/GPU
// working sets and the latest "Engine counters:" from an instrumented
// Flutter engine. It never opens the user's real profile.
//
//   CLAWNSOLE_COMPANION_TOKEN=<session token> ./node_modules/.bin/electron \
//     scripts/soak-renderer.cjs --url=http://127.0.0.1:7357/ \
//     [--seconds=600] [--interval=5] [--offscreen] [--width=1480] [--height=980]
//
// The session token, read from CLAWNSOLE_COMPANION_TOKEN (or the first line
// of standard input), is added as the X-Clawnsole-Session header for that
// origin only, so the packaged or development companion serves the real app.
// It is never accepted on the command line: argv is visible to every local
// process and kept in shell history, and the token unlocks the whole
// companion. --offscreen renders
// without a compositor surface at 120 frames per second. A taller window
// keeps content such as the Create screen's Recent work row on screen; a
// placeholder scrolled out of view pauses itself and would measure nothing.
// Pages that publish window.__soakFrames (tool/renderer_soak.dart) also
// report Flutter frames per second, which is what a paced animation limits;
// the requestAnimationFrame rate stays at the display rate regardless.
const fs = require("node:fs");
const { app, BrowserWindow } = require("electron");
const { configureSmokeProfile } = require("../lib/smoke-profile.cjs");
const { installCompanionSessionHeader } = require("../lib/companion-session.cjs");
const { parseEngineCounters, sanitizeAppMetrics } = require("../lib/renderer-diagnostics.cjs");

// The tool is meant to be piped. A reader that closes early (head, a parser
// that has seen enough) must end the run quietly: an uncaught EPIPE in the
// main process would otherwise surface as Electron's error dialog on every
// sample.
process.stdout.on("error", () => app.exit(0));
process.on("uncaughtException", (error) => {
  if (error && error.code === "EPIPE") {
    app.exit(0);
    return;
  }
  process.stderr.write(`${error && error.stack ? error.stack : error}\n`);
  app.exit(1);
});

const options = parseArguments(process.argv.slice(2));
let profile = null;
let window = null;
let engineCounters = {};
let engineCounterUpdates = 0;

function parseArguments(argv) {
  const parsed = {
    url: null, token: null, seconds: 120, interval: 5, offscreen: false, help: false,
    width: 1480, height: 980,
  };
  for (const argument of argv) {
    const [flag, ...rest] = argument.split("=");
    const value = rest.join("=");
    if (flag === "--help") parsed.help = true;
    else if (flag === "--offscreen") parsed.offscreen = true;
    else if (flag === "--url") parsed.url = /^https?:\/\//.test(value) ? value : null;
    else if (flag === "--token") parsed.tokenOnArgv = true;
    else if (flag === "--seconds") parsed.seconds = Math.max(1, Number(value) || 0);
    else if (flag === "--interval") parsed.interval = Math.max(1, Number(value) || 0);
    else if (flag === "--width") parsed.width = Math.min(8192, Math.max(320, Number(value) || 0));
    else if (flag === "--height") parsed.height = Math.min(8192, Math.max(320, Number(value) || 0));
  }
  return parsed;
}

const SAMPLE_SCRIPT = `(async () => {
  const heapBytes = globalThis.flutterCanvasKit?.HEAPU8?.byteLength ?? null;
  const flutterFrames = Number.isSafeInteger(globalThis.__soakFrames) ? globalThis.__soakFrames : null;
  const frames = await new Promise((resolve) => {
    let count = 0;
    const startedAt = performance.now();
    const tick = () => {
      count += 1;
      if (performance.now() - startedAt < 1000) requestAnimationFrame(tick);
      else resolve(count);
    };
    requestAnimationFrame(tick);
    setTimeout(() => resolve(count), 1500);
  });
  return { heapBytes, fps: frames, flutterFrames };
})()`;

// The companion session token from the environment, or from the first line
// of a piped standard input, trimmed; null when neither offers one.
function readToken() {
  const fromEnvironment = process.env.CLAWNSOLE_COMPANION_TOKEN?.trim();
  if (fromEnvironment) return fromEnvironment;
  if (process.stdin.isTTY) return null;
  try {
    const line = fs.readFileSync(0, "utf8").split(/\r?\n/)[0]?.trim();
    return line || null;
  } catch {
    return null;
  }
}

function finish(error = null, code = error ? 1 : 0) {
  if (error) console.error(error);
  if (window && !window.isDestroyed()) window.destroy();
  if (profile) {
    try { fs.rmSync(profile, { recursive: true, force: true }); } catch { /* Best effort. */ }
  }
  app.exit(code);
}

async function sample(startedAt) {
  let page = { heapBytes: null, fps: null, flutterFrames: null };
  try {
    page = await window.webContents.executeJavaScript(SAMPLE_SCRIPT, true);
  } catch {
    page = { heapBytes: null, fps: null, flutterFrames: null, error: "sample-failed" };
  }
  const processes = sanitizeAppMetrics(app.getAppMetrics())
    .filter((metric) => metric.type === "Tab" || metric.type === "GPU")
    .map(({ type, pid, workingSetKiB, peakWorkingSetKiB }) =>
      ({ type, pid, workingSetKiB, peakWorkingSetKiB }));
  console.log(JSON.stringify({
    at: new Date().toISOString(),
    elapsedMs: Date.now() - startedAt,
    heapBytes: page.heapBytes,
    fps: page.fps,
    flutterFrames: page.flutterFrames ?? null,
    ...(page.error ? { error: page.error } : {}),
    processes,
    engineCounterUpdates,
    engineCounters,
  }));
}

function run() {
  if (options.help || !options.url) {
    console.log([
      "Usage: CLAWNSOLE_COMPANION_TOKEN=<session token> electron scripts/soak-renderer.cjs --url=<http(s) URL>",
      "         [--seconds=<total, default 120>] [--interval=<seconds, default 5>] [--offscreen]",
      "         [--width=<px, default 1480>] [--height=<px, default 980>]",
      "",
      "Prints one JSON line per sample. Uses a throwaway profile; never the installed app's.",
    ].join("\n"));
    app.exit(options.help ? 0 : 2);
    return;
  }
  if (options.tokenOnArgv) {
    process.stderr.write("Pass the session token in CLAWNSOLE_COMPANION_TOKEN (or on stdin), not on the command line.\n");
    app.exit(2);
    return;
  }
  options.token = readToken();
  app.setName("Clawnsole Renderer Soak");
  app.commandLine.appendSwitch("disable-renderer-backgrounding");
  app.commandLine.appendSwitch("disable-background-timer-throttling");
  profile = configureSmokeProfile(app, { smoke: true });
  app.whenReady().then(soak).catch(finish);
}

async function soak() {
  window = new BrowserWindow({
    show: false,
    width: options.width,
    height: options.height,
    webPreferences: {
      backgroundThrottling: false,
      offscreen: options.offscreen,
      sandbox: true,
      contextIsolation: true,
      nodeIntegration: false,
    },
  });
  if (options.offscreen) window.webContents.setFrameRate(120);
  if (options.token) {
    installCompanionSessionHeader(window.webContents.session.webRequest, options.url, options.token);
  }
  window.webContents.on("console-message", (details, ...legacy) => {
    const message = details?.message ?? legacy[1];
    if (typeof message !== "string" || !message.startsWith("Engine counters:")) return;
    const parsed = parseEngineCounters(message);
    if (parsed.size === 0) return;
    engineCounterUpdates += 1;
    engineCounters = Object.fromEntries([...parsed].map(([label, entry]) => [label, {
      ...entry, live: entry.created - entry.deleted - entry.leaked,
    }]));
  });
  window.webContents.on("render-process-gone", (_event, details) => {
    console.log(JSON.stringify({ at: new Date().toISOString(), rendererGone: details?.reason ?? "unknown" }));
    finish(null, 3);
  });
  await window.loadURL(options.url);
  const startedAt = Date.now();
  const deadline = startedAt + options.seconds * 1000;
  while (Date.now() < deadline) {
    await sample(startedAt);
    await new Promise((resolve) => setTimeout(resolve, options.interval * 1000));
  }
  await sample(startedAt);
  finish();
}

run();
