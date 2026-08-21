const { spawn } = require("node:child_process");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const {
  app,
  BrowserWindow,
  clipboard,
  dialog,
  ipcMain,
  Menu,
  nativeTheme,
  safeStorage,
  session,
  shell,
} = require("electron");
const {
  findOpenPort,
  isAllowedAppUrl,
  isAllowedExplicitExternalUrl,
  isAllowedExternalUrl,
  isAllowedRendererPermission,
  waitForServer,
} = require("./lib/runtime.cjs");
const { installNativeTextContextMenu } = require("./lib/text-context-menu.cjs");
const {
  companionBootstrapLine,
  installCompanionSessionHeader,
  is32ByteBase64Url,
  proxySettingsVault,
} = require("./lib/companion-session.cjs");
const updater = require("./lib/updater.cjs");
const dataLocation = require("./lib/data-location.cjs");
const packageMetadata = require("./package.json");
const { GoogleDriveAuth, configuredOAuth } = require("./lib/google-drive-auth.cjs");
const { VaultKeyCache } = require("./lib/vault-key-cache.cjs");

const APP_NAME = "Clawnsole";
const DEVELOPMENT_URL = process.env.CLAWNSOLE_RENDERER_URL || "http://127.0.0.1:7357";
const IS_SMOKE_TEST = process.argv.includes("--smoke");

let mainWindow = null;
let rendererProcess = null;
let rendererUrl = null;
let isQuitting = false;
let updateBusy = false;
let googleDriveAuth = null;
let companionToken = "";

app.setName(APP_NAME);

function logServerOutput(stream, label) {
  stream?.setEncoding("utf8");
  stream?.on("data", (chunk) => {
    for (const line of chunk.trimEnd().split("\n")) {
      if (line) process.stderr.write(`[renderer:${label}] ${line}\n`);
    }
  });
}

async function startBundledRenderer({ deviceKey, requestToken }) {
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
    dataLocation.dataFile(app.getPath("userData")),
    "--web-root",
    rendererDirectory,
    "--secure-bootstrap",
  ];
  const companionEnvironment = { ...process.env };
  delete companionEnvironment.CLAWNSOLE_COMPANION_TOKEN;
  const child = spawn(companionExecutable, companionArguments, {
    cwd: rendererDirectory,
    env: companionEnvironment,
    stdio: ["pipe", "pipe", "pipe"],
  });
  rendererProcess = child;

  logServerOutput(child.stdout, "out");
  logServerOutput(child.stderr, "error");

  child.once("exit", (code, signal) => {
    const stoppedUnexpectedly = !isQuitting;
    if (rendererProcess === child) rendererProcess = null;
    if (stoppedUnexpectedly) {
      console.error(`Clawnsole's renderer stopped unexpectedly (${signal || code}).`);
      app.quit();
    }
  });

  await new Promise((resolve, reject) => {
    const failed = () => reject(
      new Error("Clawnsole could not initialize its local secure storage."),
    );
    child.stdin.once("error", failed);
    child.stdin.end(
      companionBootstrapLine(deviceKey, requestToken),
      () => {
        child.stdin.removeListener("error", failed);
        resolve();
      },
    );
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

// Moving the companion's data directory must happen here: the companion
// reads --data-file once at startup, so after the files are migrated the app
// records the choice and relaunches against the new location. Confirmation
// dialogs are native so the flow survives even a wedged renderer.
async function chooseDataDirectory() {
  const userData = app.getPath("userData");
  const current = dataLocation.dataDirectory(userData);
  const openOptions = {
    title: "Choose a Clawnsole Data Folder",
    buttonLabel: "Use This Folder",
    defaultPath: current,
    properties: ["openDirectory", "createDirectory"],
  };
  const selection = mainWindow
    ? await dialog.showOpenDialog(mainWindow, openOptions)
    : await dialog.showOpenDialog(openOptions);
  const target = selection.canceled ? null : selection.filePaths[0];
  if (!target) return { ok: true, canceled: true };
  const inspection = dataLocation.inspectRelocationTarget(current, target);
  if (!inspection.ok) return { ok: false, error: inspection.error };
  if (inspection.hasExistingLibrary) {
    const choice = await showMessage({
      type: "question",
      title: "Use the Existing Library?",
      message: "That folder already contains a Clawnsole library.",
      detail: "Clawnsole can reopen using the library in that folder. "
        + "The library currently in use stays where it is.",
      buttons: ["Use Existing Library", "Cancel"],
      defaultId: 0,
      cancelId: 1,
    });
    if (choice.response !== 0) return { ok: true, canceled: true };
  } else {
    const choice = await showMessage({
      type: "question",
      title: "Move Clawnsole Data?",
      message: "Move Clawnsole's data to the selected folder?",
      detail: `Clawnsole will copy its library and assets to ${target}, then `
        + `reopen from there. The current copy stays in ${current} until you `
        + "delete it.",
      buttons: ["Move and Reopen", "Cancel"],
      defaultId: 0,
      cancelId: 1,
    });
    if (choice.response !== 0) return { ok: true, canceled: true };
    try {
      dataLocation.copyLibrary(current, target);
    } catch (error) {
      return {
        ok: false,
        error: error instanceof Error ? error.message : String(error),
      };
    }
  }
  try {
    dataLocation.rememberDataDirectory(userData, target);
  } catch (error) {
    return {
      ok: false,
      error: error instanceof Error ? error.message : String(error),
    };
  }
  isQuitting = true;
  app.relaunch();
  // Let the reply reach the renderer before the app exits.
  setTimeout(() => app.quit(), 150).unref();
  return { ok: true, moved: true };
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
      + " typeof window.clawnsole?.authorizeGoogleDrive,"
      + " typeof window.clawnsole?.disconnectGoogleDrive,"
      + " typeof window.clawnsole?.settingsVault,"
      + " typeof window.clawnsole?.openExternalUrl,"
      + " typeof window.clawnsole?.revealDataFolder,"
      + " typeof window.clawnsole?.chooseDataDirectory,"
      + " window.clawnsoleShellReady === true].join(',')",
    );
    if (
      shape
      === "function,function,function,function,function,function,function,"
        + "function,function,true"
    ) {
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw new Error(`The renderer update bridge is missing (saw ${shape}).`);
}

function installRendererBridge() {
  installNativeTextContextMenu({ BrowserWindow, Menu, clipboard, ipcMain });
  ipcMain.handle("clawnsole:update:check", async (_event, force = false) =>
    updater.summarize(await updater.check({ force: force === true })));
  ipcMain.handle("clawnsole:update:start", () => startUpdateFromRenderer());
  ipcMain.handle("clawnsole:drive:authorize", () => googleDriveAuth.authorize());
  ipcMain.handle("clawnsole:drive:authorizeSilent", () => googleDriveAuth.authorizeSilently());
  ipcMain.handle("clawnsole:drive:disconnect", () => googleDriveAuth.disconnect());
  ipcMain.handle(
    "clawnsole:vault:settings",
    (event, action, value) => {
      if (!isAllowedAppUrl(event.senderFrame?.url, rendererUrl)) {
        return { ok: false, error: "The settings-vault request was rejected." };
      }
      return proxySettingsVault({
        action,
        value,
        rendererUrl,
        requestToken: companionToken,
      });
    },
  );
  ipcMain.handle("clawnsole:external:open", async (event, url, purpose) => {
    if (!isAllowedAppUrl(event.senderFrame?.url, rendererUrl)) return false;
    if (!isAllowedExplicitExternalUrl(url, purpose)) return false;
    await shell.openExternal(url);
    return true;
  });
  ipcMain.handle("clawnsole:data:reveal", async (event) => {
    if (!isAllowedAppUrl(event.senderFrame?.url, rendererUrl)) {
      return { ok: false, error: "The data-folder request was rejected." };
    }
    const failure = await shell.openPath(
      dataLocation.dataDirectory(app.getPath("userData")),
    );
    return failure ? { ok: false, error: failure } : { ok: true };
  });
  ipcMain.handle("clawnsole:data:choose", (event) => {
    if (!isAllowedAppUrl(event.senderFrame?.url, rendererUrl)) {
      return { ok: false, error: "The data-folder request was rejected." };
    }
    return chooseDataDirectory();
  });
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
  let packagedOAuth = {};
  if (app.isPackaged) {
    try {
      packagedOAuth = JSON.parse(
        fs.readFileSync(
          path.join(process.resourcesPath, "config", "google-oauth.json"),
          "utf8",
        ),
      );
    } catch {
      packagedOAuth = {};
    }
  }
  const oauth = configuredOAuth({ ...packageMetadata, ...packagedOAuth });
  googleDriveAuth = new GoogleDriveAuth({
    ...oauth,
    userData: app.getPath("userData"),
    safeStorage,
    openExternal: (url) => shell.openExternal(url),
  });
  installApplicationMenu();
  installRendererBridge();

  session.defaultSession.on("will-download", (_event, item) => {
    item.setSaveDialogOptions({
      title: "Save Clawnsole video",
      defaultPath: item.getFilename(),
    });
  });
  session.defaultSession.setPermissionCheckHandler(
    (_webContents, permission, requestingOrigin) =>
      isAllowedRendererPermission(permission, requestingOrigin, rendererUrl),
  );
  session.defaultSession.setPermissionRequestHandler(
    (_webContents, permission, callback, details) => {
      callback(
        isAllowedRendererPermission(
          permission,
          details.requestingUrl,
          rendererUrl,
        ),
      );
    },
  );

  if (app.isPackaged) {
    companionToken = crypto.randomBytes(32).toString("base64url");
    const vaultKeyCache = new VaultKeyCache({
      userData: app.getPath("userData"),
      safeStorage,
    });
    let deviceKey = await vaultKeyCache.load("device");
    if (!deviceKey) {
      deviceKey = crypto.randomBytes(32).toString("base64url");
      await vaultKeyCache.save("device", deviceKey);
    }
    rendererUrl = await startBundledRenderer({
      deviceKey,
      requestToken: companionToken,
    });
  } else {
    companionToken = process.env.CLAWNSOLE_COMPANION_TOKEN?.trim() || "";
    if (!is32ByteBase64Url(companionToken)) {
      throw new Error(
        "Development must be started through electron/scripts/start_macos.",
      );
    }
    rendererUrl = DEVELOPMENT_URL;
  }
  installCompanionSessionHeader(
    session.defaultSession.webRequest,
    rendererUrl,
    companionToken,
  );
  if (!app.isPackaged) await waitForServer(rendererUrl, { timeoutMs: 60_000 });
  await createMainWindow(rendererUrl);
  if (IS_SMOKE_TEST) {
    await verifyRendererBridge();
    console.log("Clawnsole packaged smoke test passed.");
    setTimeout(() => app.quit(), 250).unref();
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
