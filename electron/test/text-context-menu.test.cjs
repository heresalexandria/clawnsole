"use strict";

const assert = require("node:assert/strict");
const { EventEmitter } = require("node:events");
const test = require("node:test");

const {
  TEXT_CONTEXT_MENU_CHANNEL,
  buildNativeTextMenuTemplate,
  installNativeTextContextMenu,
} = require("../lib/text-context-menu.cjs");

test("the native menu follows editor and system clipboard capabilities", () => {
  const template = buildNativeTextMenuTemplate({
    hasSelection: true,
    hasText: true,
    obscured: false,
    readOnly: false,
  }, true);
  const items = template.filter((item) => item.role);

  assert.deepEqual(
    items.map((item) => item.role),
    ["undo", "redo", "cut", "copy", "paste", "delete", "selectAll"],
  );
  assert.deepEqual(
    Object.fromEntries(items.map((item) => [item.role, item.enabled])),
    {
      undo: undefined,
      redo: undefined,
      cut: true,
      copy: true,
      paste: true,
      delete: true,
      selectAll: true,
    },
  );
});

test("password fields can paste but cannot copy or cut", () => {
  const template = buildNativeTextMenuTemplate({
    hasSelection: true,
    hasText: true,
    obscured: true,
    readOnly: false,
  }, true);
  const enabled = Object.fromEntries(
    template.filter((item) => item.role).map((item) => [item.role, item.enabled]),
  );
  assert.equal(enabled.copy, false);
  assert.equal(enabled.cut, false);
  assert.equal(enabled.paste, true);
});

test("an IPC request opens a native menu for its BrowserWindow", () => {
  const ipcMain = new EventEmitter();
  const window = {};
  const sender = {};
  const seen = { template: null, popup: null };
  const BrowserWindow = {
    fromWebContents: (candidate) => candidate === sender ? window : null,
  };
  const Menu = {
    buildFromTemplate: (template) => {
      seen.template = template;
      return { popup: (options) => (seen.popup = options) };
    },
  };
  const clipboard = { availableFormats: () => ["text/plain"] };
  installNativeTextContextMenu({ BrowserWindow, Menu, clipboard, ipcMain });

  ipcMain.emit(TEXT_CONTEXT_MENU_CHANNEL, { sender }, {
    hasSelection: false,
    hasText: false,
    obscured: false,
    readOnly: false,
  });

  assert.equal(
    seen.template.find((item) => item.role === "paste").enabled,
    true,
  );
  assert.deepEqual(seen.popup, { window });
});
