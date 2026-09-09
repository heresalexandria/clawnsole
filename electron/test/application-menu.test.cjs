"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  HELP_LINKS,
  NAVIGATE_CHANNEL,
  SETTINGS_ACCELERATOR,
  buildApplicationMenuTemplate,
} = require("../lib/application-menu.cjs");
const { isAllowedExternalUrl } = require("../lib/runtime.cjs");

function buildTemplate(overrides = {}) {
  const calls = { updates: 0, settings: 0, opened: [], reloads: 0, logs: 0, reports: 0 };
  const template = buildApplicationMenuTemplate({
    appName: "Clawnsole",
    isPackaged: true,
    checkForUpdates: () => {
      calls.updates += 1;
    },
    openSettings: () => {
      calls.settings += 1;
    },
    openExternalUrl: (url) => calls.opened.push(url),
    reloadStudio: () => calls.reloads += 1,
    showLogs: () => calls.logs += 1,
    saveDiagnosticsReport: () => calls.reports += 1,
    ...overrides,
  });
  return { calls, template };
}

function submenuOf(template, label) {
  const entry = template.find(
    (item) => item.label === label || item.role === label,
  );
  assert.ok(entry, `the ${label} menu must exist`);
  return entry.submenu;
}

function labelsOf(submenu) {
  return submenu.map((item) => item.label || item.role || item.type);
}

test("the navigate channel and Settings shortcut are stable", () => {
  assert.equal(NAVIGATE_CHANNEL, "clawnsole:navigate");
  assert.equal(SETTINGS_ACCELERATOR, "CmdOrCtrl+,");
});

test("Settings… sits in the app menu on the standard shortcut", () => {
  const { calls, template } = buildTemplate();
  const appMenu = submenuOf(template, "Clawnsole");
  const settings = appMenu.find((item) => item.label === "Settings…");

  assert.ok(settings, "the app menu must offer Settings…");
  assert.equal(settings.accelerator, SETTINGS_ACCELERATOR);
  settings.click();
  assert.equal(calls.settings, 1);

  const updates = appMenu.find((item) => item.label === "Check for Updates…");
  updates.click();
  assert.equal(calls.updates, 1);
  assert.ok(appMenu.some((item) => item.role === "quit"));
});

test("the View menu is explicit and hides developer tools when packaged", () => {
  const packaged = labelsOf(submenuOf(buildTemplate().template, "View"));
  assert.deepEqual(packaged, [
    "Reload Studio",
    "separator",
    "resetZoom",
    "zoomIn",
    "zoomOut",
    "separator",
    "togglefullscreen",
  ]);

  const development = labelsOf(
    submenuOf(buildTemplate({ isPackaged: false }).template, "View"),
  );
  assert.deepEqual(development.slice(0, 2), [
    "forceReload",
    "toggleDevTools",
  ]);
  assert.ok(development.includes("togglefullscreen"));
});

test("no menu keeps Electron's catch-all view role", () => {
  const { template } = buildTemplate();
  assert.equal(template.some((item) => item.role === "viewMenu"), false);
  assert.deepEqual(
    template.map((item) => item.label || item.role),
    ["Clawnsole", "editMenu", "View", "windowMenu", "help"],
  );
});

test("Help links open through the shell's external allowlist", () => {
  const { calls, template } = buildTemplate();
  const help = submenuOf(template, "help");

  assert.deepEqual(labelsOf(help), [
    "Clawnsole Privacy Policy",
    "Terms of Use",
    "Report an Issue…",
    "separator",
    "Show Logs",
    "Save Diagnostics Report…",
  ]);
  for (const item of help.filter((item) => HELP_LINKS.some((link) => link.label === item.label))) item.click();
  assert.deepEqual(calls.opened, [
    "https://clawnsole.app/privacy/",
    "https://clawnsole.app/tos/",
    "https://github.com/heresalexandria/clawnsole/issues",
  ]);
  for (const { url } of HELP_LINKS) {
    assert.equal(isAllowedExternalUrl(url), true, `${url} must be allowlisted`);
  }
});

test("packaged recovery and logs work through native callbacks without the Flutter renderer", () => {
  const { calls, template } = buildTemplate();
  const reload = submenuOf(template, "View").find((item) => item.label === "Reload Studio");
  assert.equal(reload.accelerator, "CmdOrCtrl+R");
  reload.click();
  submenuOf(template, "help").find((item) => item.label === "Show Logs").click();
  submenuOf(template, "help").find((item) => item.label === "Save Diagnostics Report…").click();
  assert.equal(calls.reloads, 1);
  assert.equal(calls.logs, 1);
  assert.equal(calls.reports, 1);
  assert.deepEqual(calls.opened, []);
});
