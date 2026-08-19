const { spawn } = require("node:child_process");
const path = require("node:path");
const {
  app,
  BrowserWindow,
  dialog,
  ipcMain,
  Menu,
  nativeTheme,
  session,
  shell,
} = require("electron");
const {
  findOpenPort,
  isAllowedAppUrl,
  isAllowedExternalUrl,
  waitForServer,
} = require("./lib/runtime.cjs");
const updater = require("./lib/updater.cjs");

const APP_NAME = "Clawnsole";
const DEVELOPMENT_URL = process.env.CLAWNSOLE_RENDERER_URL || "http://127.0.0.1:7357";
const IS_SMOKE_TEST = process.argv.includes("--smoke");

let mainWindow = null;
let rendererProcess = null;
let rendererUrl = null;
let isQuitting = false;
let updateBusy = false;

app.setName(APP_NAME);

function logServerOutput(stream, label) {
  stream?.setEncoding("utf8");
  stream?.on("data", (chunk) => {
    for (const line of chunk.trimEnd().split("\n")) {
      if (line) process.stderr.write(`[renderer:${label}] ${line}\n`);
    }
  });
}

async function startBundledRenderer() {
  const rendererDirectory = path.join(process.resourcesPath, "renderer");
  const companionExecutable = path.join(
    process.resourcesPath,
    "companion",
    "clawnsole_companion",
  );
  const port = await findOpenPort();
  const localUrl = `http://127.0.0.1:${port}`;

  const companionArguments = [
    "--port",
    String(port),
    "--data-file",
    path.join(app.getPath("userData"), "clawnsole.json"),
    "--web-root",
    rendererDirectory,
  ];
  rendererProcess = spawn(companionExecutable, companionArguments, {
    cwd: rendererDirectory,
    env: process.env,
    stdio: ["ignore", "pipe", "pipe"],
  });

  logServerOutput(rendererProcess.stdout, "out");
  logServerOutput(rendererProcess.stderr, "error");

  rendererProcess.once("exit", (code, signal) => {
    const stoppedUnexpectedly = !isQuitting;
    rendererProcess = null;
    if (stoppedUnexpectedly) {
      console.error(`Clawnsole's renderer stopped unexpectedly (${signal || code}).`);
      app.quit();
    }
  });

  await waitForServer(`${localUrl}/health`, {
    isProcessAlive: () => Boolean(rendererProcess && rendererProcess.exitCode === null),
  });
  return localUrl;
}

function stopBundledRenderer() {
  if (!rendererProcess || rendererProcess.exitCode !== null) return;
  rendererProcess.kill("SIGTERM");
  rendererProcess = null;
}

function installApplicationMenu() {
  const template = [
    {
      label: APP_NAME,
      submenu: [
        { role: "about" },
        {
          label: "Check for Updates…",
          click: () => void checkForUpdates({ manual: true }),
        },
        { type: "separator" },
        { role: "services" },
        { type: "separator" },
        { role: "hide" },
        { role: "hideOthers" },
        { role: "unhide" },
        { type: "separator" },
        { role: "quit" },
      ],
    },
    { role: "editMenu" },
    { role: "viewMenu" },
    { role: "windowMenu" },
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

function showMessage(options) {
  return mainWindow
    ? dialog.showMessageBox(mainWindow, options)
    : dialog.showMessageBox(options);
}

function emitUpdateEvent(payload) {
  mainWindow?.webContents.send("clawnsole:update:event", payload);
}

// Downloads and installs a checked update while streaming progress to both
// the dock icon and the renderer, which shows its own progress modal.
async function downloadAndInstall(result) {
  mainWindow?.setProgressBar(2);
  emitUpdateEvent({
    phase: "downloading",
    version: result.latest,
    received: 0,
    total: result.asset?.size ?? null,
    fraction: null,
  });
  try {
    const staged = await updater.download(result, ({ received, total, fraction }) => {
      mainWindow?.setProgressBar(fraction ?? 2);
      emitUpdateEvent({
        phase: "downloading",
        version: result.latest,
        received,
        total,
        fraction,
      });
    });
    emitUpdateEvent({ phase: "installing", version: result.latest });
    mainWindow?.setProgressBar(-1);
    await updater.install(staged);
  } catch (error) {
    mainWindow?.setProgressBar(-1);
    emitUpdateEvent({
      phase: "error",
      version: result.latest,
      message: error instanceof Error ? error.message : String(error),
    });
    throw error;
  }
}

async function checkForUpdates({ manual = false } = {}) {
  if (updateBusy) return;
  updateBusy = true;
  try {
    const result = await updater.check({ force: manual });
    if (result.skipped) return;
    if (!result.ok) {
      if (manual) {
        await showMessage({
          type: "warning",
          title: "Clawnsole Updates",
          message: "Clawnsole could not check for updates.",
          detail: result.error,
        });
      }
      return;
    }
    if (!result.available) {
      if (manual) {
        await showMessage({
          type: "info",
          title: "Clawnsole Updates",
          message: `Clawnsole ${result.current} is up to date.`,
        });
      }
      return;
    }

    const buttons = result.installable
      ? ["Download and Install", "Later", "View Release"]
      : ["View Release", "Later"];
    const choice = await showMessage({
      type: "info",
      title: "Clawnsole Update Available",
      message: `Clawnsole ${result.latest} is available.`,
      detail: result.installable
        ? `You are running ${result.current}. The update will be verified, installed in place, and Clawnsole will reopen.`
        : `You are running ${result.current}. Development builds update from source.`,
      buttons,
      defaultId: 0,
      cancelId: 1,
    });
    if ((!result.installable && choice.response === 0)
      || (result.installable && choice.response === 2)) {
      await shell.openExternal(result.htmlUrl || updater.RELEASE_PAGE);
      return;
    }
    if (!result.installable || choice.response !== 0) return;

    await downloadAndInstall(result);
  } catch (error) {
    mainWindow?.setProgressBar(-1);
    await showMessage({
      type: "error",
      title: "Clawnsole Update Failed",
      message: "Clawnsole could not install the update.",
      detail: error instanceof Error ? error.message : String(error),
    });
  } finally {
    updateBusy = false;
  }
}

// The renderer's version dialog already carries the user's consent, so this
// flow skips the native prompt and reports through update events instead.
async function startUpdateFromRenderer() {
  if (updateBusy) {
    return { ok: false, error: "An update is already in progress." };
  }
  updateBusy = true;
  try {
    const result = await updater.check({ force: true });
    const summary = updater.summarize(result);
    if (!result.ok) return summary;
    if (!result.available) {
      return { ...summary, error: `Clawnsole ${result.current} is already up to date.` };
    }
    if (!result.installable) {
      return {
        ...summary,
        error: "This build updates from source with git rather than replacing itself.",
      };
    }
    await downloadAndInstall(result);
    return { ...summary, started: true };
  } catch (error) {
    return {
      ok: false,
      error: error instanceof Error ? error.message : String(error),
    };
  } finally {
    updateBusy = false;
  }
}

// The in-app update dialog only appears when the preload reaches the renderer
// and the Flutter app binds to it, so the smoke test treats either half being
// absent as a packaging failure. Flutter boots asynchronously, so poll.
async function verifyRendererBridge(timeoutMs = 40_000) {
  const deadline = Date.now() + timeoutMs;
  let shape = "unavailable";
  while (Date.now() < deadline) {
    shape = await mainWindow?.webContents.executeJavaScript(
      "[typeof window.clawnsole?.checkForUpdate,"
      + " typeof window.clawnsole?.startUpdate,"
      + " typeof window.clawnsole?.onUpdateEvent,"
      + " window.clawnsoleShellReady === true].join(',')",
    );
    if (shape === "function,function,function,true") return;
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw new Error(`The renderer update bridge is missing (saw ${shape}).`);
}

function installRendererBridge() {
  ipcMain.handle("clawnsole:update:check", async () =>
    updater.summarize(await updater.check({ force: true })));
  ipcMain.handle("clawnsole:update:start", () => startUpdateFromRenderer());
}

function protectNavigation(window, localRendererUrl) {
  window.webContents.setWindowOpenHandler(({ url }) => {
    if (isAllowedExternalUrl(url)) void shell.openExternal(url);
    return { action: "deny" };
  });

  window.webContents.on("will-navigate", (event, url) => {
    if (isAllowedAppUrl(url, localRendererUrl)) return;
    event.preventDefault();
    if (isAllowedExternalUrl(url)) void shell.openExternal(url);
  });

  window.webContents.on("will-attach-webview", (event) => event.preventDefault());
}

async function createMainWindow(localRendererUrl) {
  const window = new BrowserWindow({
    title: APP_NAME,
    width: 1480,
    height: 980,
    minWidth: 1040,
    minHeight: 700,
    backgroundColor: nativeTheme.shouldUseDarkColors ? "#0D0E18" : "#F3F4FA",
    show: false,
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      preload: path.join(__dirname, "preload.cjs"),
      sandbox: true,
      webSecurity: true,
    },
  });

  protectNavigation(window, localRendererUrl);
  window.once("ready-to-show", () => window.show());
  window.on("closed", () => {
    if (mainWindow === window) mainWindow = null;
  });
  await window.loadURL(localRendererUrl);
  mainWindow = window;
}

async function startApplication() {
  installApplicationMenu();
  installRendererBridge();

  session.defaultSession.on("will-download", (_event, item) => {
    item.setSaveDialogOptions({
      title: "Save Clawnsole video",
      defaultPath: item.getFilename(),
    });
  });
  session.defaultSession.setPermissionCheckHandler(() => false);
  session.defaultSession.setPermissionRequestHandler((_webContents, _permission, callback) => {
    callback(false);
  });

  rendererUrl = app.isPackaged ? await startBundledRenderer() : DEVELOPMENT_URL;
  if (!app.isPackaged) await waitForServer(rendererUrl, { timeoutMs: 60_000 });
  await createMainWindow(rendererUrl);
  if (IS_SMOKE_TEST) {
    await verifyRendererBridge();
    console.log("Clawnsole packaged smoke test passed.");
    setTimeout(() => app.quit(), 250).unref();
  } else if (app.isPackaged) {
    setTimeout(() => void checkForUpdates(), 3_000).unref();
  }
}

const hasSingleInstanceLock = app.requestSingleInstanceLock();

if (!hasSingleInstanceLock) {
  app.quit();
} else {
  app.on("second-instance", () => {
    if (!mainWindow) return;
    if (mainWindow.isMinimized()) mainWindow.restore();
    mainWindow.show();
    mainWindow.focus();
  });

  app.on("activate", () => {
    if (!mainWindow && rendererUrl) void createMainWindow(rendererUrl);
  });

  app.on("before-quit", () => {
    isQuitting = true;
    stopBundledRenderer();
  });

  app.on("window-all-closed", () => app.quit());

  app.whenReady().then(startApplication).catch((error) => {
    console.error(error);
    app.quit();
  });
}
