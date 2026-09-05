"use strict";

const { isAllowedAppUrl } = require("./runtime.cjs");

// Resolve the active window and origin for every call: companion restarts and
// window recreation must invalidate the previous renderer's authority.
function rendererIpcGuard({ getWindow, getRendererUrl }) {
  return (event) => {
    const window = getWindow();
    if (!window || window.isDestroyed()) return false;
    const contents = window.webContents;
    return Boolean(
      contents && !contents.isDestroyed()
      && event?.sender === contents
      && event.senderFrame
      && event.senderFrame === contents.mainFrame
      && isAllowedAppUrl(event.senderFrame.url, getRendererUrl()),
    );
  };
}

function guardedRendererHandler(ipcMain, isTrustedEvent) {
  return (channel, handler) => ipcMain.handle(channel, (event, ...args) => {
    if (!isTrustedEvent(event)) {
      throw new Error("The renderer request was rejected.");
    }
    return handler(event, ...args);
  });
}

module.exports = { rendererIpcGuard, guardedRendererHandler };
