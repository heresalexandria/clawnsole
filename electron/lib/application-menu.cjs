"use strict";

const SETTINGS_ACCELERATOR = "CmdOrCtrl+,";
const NAVIGATE_CHANNEL = "clawnsole:navigate";
const HELP_LINKS = Object.freeze([
  { label: "Clawnsole Privacy Policy", url: "https://clawnsole.app/privacy/" },
  { label: "Terms of Use", url: "https://clawnsole.app/tos/" },
  {
    label: "Report an Issue…",
    url: "https://github.com/heresalexandria/clawnsole/issues",
  },
]);

// Developer tools remain separate from the native recovery action, which must
// also be reachable when a packaged Flutter renderer is blank.
function developmentViewItems(isPackaged) {
  if (isPackaged) return [];
  return [
    { role: "forceReload" },
    { role: "toggleDevTools" },
    { type: "separator" },
  ];
}

function buildApplicationMenuTemplate({
  appName,
  isPackaged,
  checkForUpdates,
  openSettings,
  openExternalUrl,
  reloadStudio,
  showLogs,
  saveDiagnosticsReport = () => {},
}) {
  return [
    {
      label: appName,
      submenu: [
        { role: "about" },
        { label: "Check for Updates…", click: () => checkForUpdates() },
        { type: "separator" },
        {
          label: "Settings…",
          accelerator: SETTINGS_ACCELERATOR,
          click: () => openSettings(),
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
    {
      label: "View",
      submenu: [
        ...developmentViewItems(isPackaged),
        { label: "Reload Studio", accelerator: "CmdOrCtrl+R", click: () => reloadStudio() },
        { type: "separator" },
        { role: "resetZoom" },
        { role: "zoomIn" },
        { role: "zoomOut" },
        { type: "separator" },
        { role: "togglefullscreen" },
      ],
    },
    { role: "windowMenu" },
    {
      role: "help",
      submenu: [
        ...HELP_LINKS.map(({ label, url }) => ({
          label,
          click: () => openExternalUrl(url),
        })),
        { type: "separator" },
        { label: "Show Logs", click: () => showLogs() },
        { label: "Save Diagnostics Report…", click: () => saveDiagnosticsReport() },
      ],
    },
  ];
}

module.exports = {
  HELP_LINKS,
  NAVIGATE_CHANNEL,
  SETTINGS_ACCELERATOR,
  buildApplicationMenuTemplate,
};
