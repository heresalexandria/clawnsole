"use strict";

const TEXT_CONTEXT_MENU_CHANNEL = "clawnsole:text-context-menu";

function buildNativeTextMenuTemplate(state = {}, clipboardHasText = true) {
  const canCopy = state.hasSelection === true && state.obscured !== true;
  const canEdit = state.readOnly !== true;
  return [
    { role: "undo" },
    { role: "redo" },
    { type: "separator" },
    { role: "cut", enabled: canEdit && canCopy },
    { role: "copy", enabled: canCopy },
    { role: "paste", enabled: canEdit && clipboardHasText },
    { role: "delete", enabled: canEdit && state.hasSelection === true },
    { type: "separator" },
    { role: "selectAll", enabled: state.hasText === true },
  ];
}

function clipboardContainsText(clipboard) {
  return clipboard.availableFormats().some((format) => {
    const normalized = format.toLowerCase();
    return normalized.includes("text")
      || normalized.includes("plain")
      || normalized.includes("utf8");
  });
}

function installNativeTextContextMenu({ BrowserWindow, Menu, clipboard, ipcMain }) {
  ipcMain.on(TEXT_CONTEXT_MENU_CHANNEL, (event, state = {}) => {
    const window = BrowserWindow.fromWebContents(event.sender);
    if (!window) return;
    const menu = Menu.buildFromTemplate(
      buildNativeTextMenuTemplate(state, clipboardContainsText(clipboard)),
    );
    menu.popup({ window });
  });
}

module.exports = {
  TEXT_CONTEXT_MENU_CHANNEL,
  buildNativeTextMenuTemplate,
  clipboardContainsText,
  installNativeTextContextMenu,
};
