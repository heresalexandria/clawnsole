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
  Notification,
  safeStorage,
  session,
  shell,
} = require("electron");
const {
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
const { bundledCompanionArguments } = require("./lib/companion-launch.cjs");
const { CompanionLog } = require("./lib/companion-log.cjs");
const { CompanionSupervisor } = require("./lib/companion-supervisor.cjs");
const {
  NAVIGATE_CHANNEL,
  buildApplicationMenuTemplate,
} = require("./lib/application-menu.cjs");
const { installRendererRecovery } = require("./lib/renderer-recovery.cjs");
const {
  NOTIFY_CHANNEL,
  sanitizeNotification,
  shouldShowNotification,
} = require("./lib/notifications.cjs");
const {
  INSTALL_LOCATION_HELP,
  applicationsMoveDeclined,
  rememberApplicationsMoveDeclined,
} = require("./lib/install-location.cjs");

const APP_NAME = "Clawnsole";
const DEVELOPMENT_URL = process.env.CLAWNSOLE_RENDERER_URL || "http://127.0.0.1:7357";
const IS_SMOKE_TEST = process.argv.includes("--smoke");
// Every member the Flutter app binds to, plus the flag it raises once it has.
const BRIDGE_MEMBERS = [
  "checkForUpdate",
  "startUpdate",
  "onUpdateEvent",
  "onNavigate",
  "notify",
  "authorizeGoogleDrive",
  "disconnectGoogleDrive",
  "settingsVault",
  "openExternalUrl",
  "revealDataFolder",
  "chooseDataDirectory",
];

let mainWindow = null;
let companion = null;
let companionLog = null;
let companionSession = null;
let companionFailurePending = false;
let rendererUrl = null;
let isQuitting = false;
let updateBusy = false;
let googleDriveAuth = null;
let companionToken = "";

app.setName(APP_NAME);

function companionLogger() {
  if (!companionLog) {
    companionLog = new CompanionLog({
      directory: app.getPath("logs"),
      // Development keeps the familiar terminal stream; a packaged app has
      // nowhere to echo to and relies on the file alone.
      echo: app.isPackaged ? null : (entry) => process.stderr.write(entry),
    });
  }
  return companionLog;
}

// The supervisor owns the bundled companion for the life of the shell: it
// restarts one unexpected exit or health-check failure by itself, and asks
// here only when a second failure makes it a crash loop.
async function startBundledRenderer({ deviceKey, requestToken }) {
  const rendererDirectory = path.join(process.resourcesPath, "renderer");
  const companionEnvironment = { ...process.env };
  delete companionEnvironment.CLAWNSOLE_COMPANION_TOKEN;
  companion = new CompanionSupervisor({
    executable: path.join(process.resourcesPath, "companion", "clawnsole_companion"),
    argumentsFor: (port) => bundledCompanionArguments({
      port,
      dataFile: dataLocation.dataFile(app.getPath("userData")),
      rendererDirectory,
      resourcesPath: process.resourcesPath,
    }),
    cwd: rendererDirectory,
    env: companionEnvironment,
    bootstrapLine: companionBootstrapLine(deviceKey, requestToken),
    log: companionLogger(),
    onRestarted: (restart) => adoptCompanionUrl(restart),
    onFailed: (reason) => void reportCompanionFailure(reason),
  });
  return companion.start();
}

function stopBundledRenderer() {
  companion?.stop();
  companion = null;
  companionLog?.close();
}

// A restart usually reclaims the same port. When it cannot, the renderer
// origin moves, so the session header follows it and the window reloads from
// the new origin rather than the dead one.
function adoptCompanionUrl({ url, changedUrl }) {
  rendererUrl = url;
  companionSession?.rebind(url);
  if (!mainWindow || mainWindow.isDestroyed()) return;
  if (changedUrl) void mainWindow.loadURL(url);
  else mainWindow.webContents.reload();
}

async function reportCompanionFailure(reason) {
  if (isQuitting || companionFailurePending) return;
  companionFailurePending = true;
  try {
    for (;;) {
      const choice = await showMessage({
        type: "error",
        title: "Clawnsole Stopped Working",
        message: "Clawnsole's local companion stopped and could not be restarted.",
        detail: `${reason}\n\nReopening Clawnsole starts a fresh companion. Your `
          + "library and settings stay where they are.",
        buttons: ["Reopen", "Show Logs", "Quit"],
        defaultId: 0,
        cancelId: 2,
      });
      if (choice.response === 1) {
        shell.showItemInFolder(companionLogger().file);
        continue;
      }
      if (choice.response === 0) {
        isQuitting = true;
        app.relaunch();
      }
      app.quit();
      return;
    }
  } finally {
    companionFailurePending = false;
  }
}

// Settings… and any later section shortcut reach Flutter through the
// preload's onNavigate bridge. On macOS the window may already be closed, so
// reopen it first and navigate once it has loaded.
function openSection(section) {
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.show();
    mainWindow.webContents.send(NAVIGATE_CHANNEL, { section });
    return;
  }
  if (!rendererUrl) return;
  void createMainWindow().then(() => {
    mainWindow?.webContents.send(NAVIGATE_CHANNEL, { section });
  });
}

// Help-menu destinations go through the same allowlist as every other link
// the shell hands to macOS.
function openMenuUrl(url) {
  if (!isAllowedExternalUrl(url)) return false;
  void shell.openExternal(url);
  return true;
}

function installApplicationMenu() {
  Menu.setApplicationMenu(Menu.buildFromTemplate(buildApplicationMenuTemplate({
    appName: APP_NAME,
    isPackaged: app.isPackaged,
    checkForUpdates: () => void checkForUpdates({ manual: true }),
    openSettings: () => openSection("settings"),
    openExternalUrl: (url) => openMenuUrl(url),
  })));
}

function showMessage(options) {
  return mainWindow && !mainWindow.isDestroyed()
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

// A bundle outside /Applications can never replace itself: Gatekeeper runs a
// freshly downloaded copy from a read-only randomized path, and everywhere
// else the swap trips over permissions. Offer the move once and remember a
// decline so the prompt never becomes nagging.
async function offerApplicationsMove() {
  if (!app.isPackaged || IS_SMOKE_TEST) return;
  if (typeof app.isInApplicationsFolder !== "function") return;
  if (app.isInApplicationsFolder()) return;
  const userData = app.getPath("userData");
  if (applicationsMoveDeclined(userData)) return;
  const choice = await showMessage({
    type: "question",
    title: "Move Clawnsole to Applications?",
    message: "Clawnsole is not in your Applications folder.",
    detail: "Clawnsole can only install its own updates from the Applications "
      + "folder. Moving it now takes a moment and reopens Clawnsole.",
    buttons: ["Move to Applications", "Not Now"],
    defaultId: 0,
    cancelId: 1,
  });
  if (choice.response !== 0) {
    try {
      rememberApplicationsMoveDeclined(userData);
    } catch {
      // A prompt shown twice is better than a failed launch.
    }
    return;
  }
  try {
    // A successful move relaunches Clawnsole from its new home.
    app.moveToApplicationsFolder();
  } catch (error) {
    await showMessage({
      type: "warning",
      title: "Clawnsole Was Not Moved",
      message: "Clawnsole could not move itself to the Applications folder.",
      detail: `${error instanceof Error ? error.message : String(error)}\n\n`
        + INSTALL_LOCATION_HELP,
    });
  }
}

// The post-quit swap helper leaves its report beside the staged update. This
// is the launch that consumes it, so a failed in-place update is never silent.
async function reportPreviousUpdate() {
  if (!app.isPackaged) return;
  let result = null;
  try {
    result = updater.consumeSwapResult();
  } catch {
    result = null;
  }
  if (!result) return;
  await showMessage({
    type: result.ok ? "info" : "warning",
    title: "Clawnsole Updates",
    message: result.message,
  });
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
  const probe = `[${
    BRIDGE_MEMBERS.map((name) => `typeof window.clawnsole?.${name}`).join(",")
  }, window.clawnsoleShellReady === true].join(',')`;
  const expected = `${BRIDGE_MEMBERS.map(() => "function").join(",")},true`;
  const deadline = Date.now() + timeoutMs;
  let shape = "unavailable";
  while (Date.now() < deadline) {
    shape = await mainWindow?.webContents.executeJavaScript(probe);
    if (shape === expected) return;
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
  // Resolves to true only when a banner was actually posted, which is what
  // the Flutter side awaits before deciding whether to show its own toast.
  ipcMain.handle(NOTIFY_CHANNEL, (event, payload) => {
    if (!isAllowedAppUrl(event.senderFrame?.url, rendererUrl)) return false;
    const notification = sanitizeNotification(payload);
    if (!notification) return false;
    if (!shouldShowNotification({
      supported: Notification.isSupported(),
      windowFocused: mainWindow?.isDestroyed() === false && mainWindow.isFocused(),
    })) {
      return false;
    }
    const banner = new Notification(notification);
    banner.on("click", () => {
      if (!mainWindow || mainWindow.isDestroyed()) return;
      if (mainWindow.isMinimized()) mainWindow.restore();
      mainWindow.show();
      mainWindow.focus();
    });
    banner.show();
    return true;
  });
}

// The renderer origin can move when the companion restarts on a new port, so
// every guard reads the live value rather than the one captured at startup.
function protectNavigation(window) {
  window.webContents.setWindowOpenHandler(({ url }) => {
    if (isAllowedExternalUrl(url)) void shell.openExternal(url);
    return { action: "deny" };
  });

  window.webContents.on("will-navigate", (event, url) => {
    if (isAllowedAppUrl(url, rendererUrl)) return;
    event.preventDefault();
    if (isAllowedExternalUrl(url)) void shell.openExternal(url);
  });

  window.webContents.on("will-attach-webview", (event) => event.preventDefault());
}

async function createMainWindow() {
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

  protectNavigation(window);
  installRendererRecovery({
    window,
    showMessage,
    relaunch: () => {
      isQuitting = true;
      app.relaunch();
      app.quit();
    },
    quit: () => app.quit(),
  });
  window.once("ready-to-show", () => window.show());
  window.on("closed", () => {
    if (mainWindow === window) mainWindow = null;
  });
  mainWindow = window;
  await window.loadURL(rendererUrl);
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
  companionSession = installCompanionSessionHeader(
    session.defaultSession.webRequest,
    rendererUrl,
    companionToken,
  );
  // /health is the companion's only unauthenticated route: every other path,
  // the app shell included, answers 403 without the session header this
  // process only ever adds inside Electron's own session.
  if (!app.isPackaged) {
    await waitForServer(`${rendererUrl}/health`, { timeoutMs: 60_000 });
  }
  await createMainWindow();
  if (IS_SMOKE_TEST) {
    await verifyRendererBridge();
    console.log("Clawnsole packaged smoke test passed.");
    setTimeout(() => app.quit(), 250).unref();
    return;
  }
  await reportPreviousUpdate();
  await offerApplicationsMove();
}

const hasSingleInstanceLock = app.requestSingleInstanceLock();

if (!hasSingleInstanceLock) {
  app.quit();
} else {
  // Reopening a windowless Clawnsole from the Dock or Finder arrives here as
  // well as through activate, so both rebuild the window.
  app.on("second-instance", () => {
    if (!mainWindow) {
      if (rendererUrl) void createMainWindow();
      return;
    }
    if (mainWindow.isMinimized()) mainWindow.restore();
    mainWindow.show();
    mainWindow.focus();
  });

  app.on("activate", () => {
    if (!mainWindow && rendererUrl) void createMainWindow();
  });

  app.on("before-quit", () => {
    isQuitting = true;
    stopBundledRenderer();
  });

  // macOS keeps an app running without windows: ⌘W closes the window, the
  // companion keeps serving, and Dock activation reopens it. Only ⌘Q, or a
  // non-darwin host closing its last window, ends the session.
  app.on("window-all-closed", () => {
    if (process.platform !== "darwin") app.quit();
  });

  app.whenReady().then(startApplication).catch((error) => {
    console.error(error);
    app.quit();
  });
}
