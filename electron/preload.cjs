"use strict";

const { contextBridge, ipcRenderer } = require("electron");

// The renderer-facing shell surface. The Flutter app feature-detects
// `window.clawnsole` to offer in-place updates with download progress.
contextBridge.exposeInMainWorld("clawnsole", {
  shell: "electron",
  checkForUpdate: (force = false) =>
    ipcRenderer.invoke("clawnsole:update:check", force === true),
  startUpdate: () => ipcRenderer.invoke("clawnsole:update:start"),
  onUpdateEvent: (callback) => {
    if (typeof callback !== "function") return () => {};
    const listener = (_event, payload) => callback(payload);
    ipcRenderer.on("clawnsole:update:event", listener);
    return () => ipcRenderer.removeListener("clawnsole:update:event", listener);
  },
});
