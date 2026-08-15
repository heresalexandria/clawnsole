const { spawn } = require("node:child_process");
const path = require("node:path");
const {
  app,
  BrowserWindow,
  Menu,
  session,
  shell,
} = require("electron");
const {
  findOpenPort,
  isAllowedAppUrl,
  isAllowedExternalUrl,
  waitForServer,
} = require("./lib/runtime.cjs");

const APP_NAME = "Clawnsole";
const DEVELOPMENT_URL = process.env.CLAWNSOLE_RENDERER_URL || "http://127.0.0.1:3000";

let mainWindow = null;
let rendererProcess = null;
let rendererUrl = null;
let isQuitting = false;

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
  const serverFile = path.join(rendererDirectory, "server.js");
  const port = await findOpenPort();
  const localUrl = `http://127.0.0.1:${port}`;

  rendererProcess = spawn(process.execPath, [serverFile], {
    cwd: rendererDirectory,
    env: {
      ...process.env,
      CLAWNSOLE_DATA_FILE: path.join(app.getPath("userData"), "clawnsole.json"),
      ELECTRON_RUN_AS_NODE: "1",
      HOSTNAME: "127.0.0.1",
      NEXT_TELEMETRY_DISABLED: "1",
      NODE_PATH: path.join(rendererDirectory, "vendor_modules"),
      PORT: String(port),
    },
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

  await waitForServer(localUrl, {
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
    backgroundColor: "#efe7d8",
    show: false,
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
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

  session.defaultSession.setPermissionCheckHandler(() => false);
  session.defaultSession.setPermissionRequestHandler((_webContents, _permission, callback) => {
    callback(false);
  });

  rendererUrl = app.isPackaged ? await startBundledRenderer() : DEVELOPMENT_URL;
  if (!app.isPackaged) await waitForServer(rendererUrl, { timeoutMs: 60_000 });
  await createMainWindow(rendererUrl);
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
