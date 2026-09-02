"use strict";

const STABLE_AFTER_MS = 5 * 60 * 1000;

// The Flutter renderer is a single page with no unsaved state outside the
// companion, so the first crash simply reloads it. A second crash inside
// STABLE_AFTER_MS is a loop, and the user gets to choose. A hung renderer
// is offered a wait or a full relaunch; the prompt closes itself when the
// renderer recovers on its own.
function installRendererRecovery({
  window,
  showMessage,
  relaunch,
  quit,
  reloadLimit = 1,
  stableAfterMs = STABLE_AFTER_MS,
  now = Date.now,
}) {
  let reloads = 0;
  let lastCrashAt = null;
  let unresponsivePrompt = null;

  window.webContents.on("render-process-gone", (_event, details = {}) => {
    if (details.reason === "clean-exit") return;
    const at = now();
    if (lastCrashAt !== null && at - lastCrashAt >= stableAfterMs) reloads = 0;
    lastCrashAt = at;
    if (reloads < reloadLimit) {
      reloads += 1;
      window.webContents.reload();
      return;
    }
    void showMessage({
      type: "error",
      title: "Clawnsole Window Stopped",
      message: "Clawnsole's window stopped unexpectedly.",
      detail: `The renderer reported "${details.reason || "unknown"}" after it `
        + "was already reloaded once.",
      buttons: ["Reload", "Quit"],
      defaultId: 0,
      cancelId: 1,
    }).then((choice) => {
      if (choice.response === 0) {
        reloads = 0;
        window.webContents.reload();
      } else {
        quit();
      }
    });
  });

  window.webContents.on("unresponsive", () => {
    if (unresponsivePrompt) return;
    const controller = new AbortController();
    unresponsivePrompt = controller;
    void showMessage({
      type: "warning",
      title: "Clawnsole Is Not Responding",
      message: "Clawnsole's window is not responding.",
      detail: "You can give it more time or relaunch Clawnsole. Generations "
        + "already in progress continue in the local companion.",
      buttons: ["Wait", "Relaunch"],
      defaultId: 0,
      cancelId: 0,
      signal: controller.signal,
    }).then((choice) => {
      if (unresponsivePrompt === controller) unresponsivePrompt = null;
      if (choice.response === 1) relaunch();
    });
  });

  window.webContents.on("responsive", () => {
    unresponsivePrompt?.abort();
    unresponsivePrompt = null;
  });
}

module.exports = {
  STABLE_AFTER_MS,
  installRendererRecovery,
};
