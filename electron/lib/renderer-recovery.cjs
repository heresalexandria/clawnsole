"use strict";

const {
  ENGINE_REASONS,
  processDetails,
  runShellTask,
  writeLifecycle,
} = require("./lifecycle-log.cjs");
const STABLE_AFTER_MS = 5 * 60 * 1000;

// Dialog copy for the two ways a window can need recovery. Chromium reports a
// dead process itself; a dead Flutter engine inside a live process is inferred
// by renderer diagnostics and arrives through recoverFrom(reason).
const CRASH_COPY = {
  event: "renderer-crash-dialog-failed",
  title: "Clawnsole Window Stopped",
  message: "Clawnsole's window stopped unexpectedly.",
  detail: (details) => `The renderer reported "${processDetails(details).reason}" and `
    + "could not recover automatically. Saved drafts and library data "
    + "will be restored when the window reloads.",
};
const ENGINE_COPY = {
  event: "renderer-engine-dialog-failed",
  title: "Clawnsole Stopped Drawing",
  message: "Clawnsole's studio stopped drawing.",
  detail: () => "Clawnsole already reloaded the window once and the studio stopped "
    + "drawing again. Reloading it again restores saved drafts and library data; "
    + "edits that were never saved cannot be recovered.",
};

// Reload one failed renderer before prompting on a crash loop. Saved drafts
// and library state are restored by Flutter; renderer-only transient state
// cannot survive a crashed process. A recovered or closed window invalidates
// its pending prompts so late answers cannot close a healthy application.
function installRendererRecovery({
  window,
  showMessage,
  relaunch,
  quit,
  log = null,
  reloadLimit = 1,
  stableAfterMs = STABLE_AFTER_MS,
  now = Date.now,
}) {
  let reloads = 0;
  let lastCrashAt = null;
  let unresponsivePrompt = null;
  let crashPrompt = null;
  let disposed = false;
  let pendingReload = null;
  const contents = window.webContents;
  const alive = () => !disposed && !window.isDestroyed?.() && !contents.isDestroyed?.();
  const closeHangPrompt = () => {
    const prompt = unresponsivePrompt;
    unresponsivePrompt = null;
    prompt?.abort();
  };
  const reload = () => {
    if (!alive()) return false;
    if (pendingReload !== null) return true;
    // Chromium can still be tearing down RenderFrameHost inside the gone
    // callback. Never navigate synchronously through that native stack.
    pendingReload = setImmediate(() => {
      pendingReload = null;
      if (!alive()) return;
      try {
        contents.reload();
        writeLifecycle(log, "renderer-reload");
      } catch {
        writeLifecycle(log, "renderer-reload-failed");
        reloads = reloadLimit;
        recover({ reason: "launch-failed" }, CRASH_COPY);
      }
    });
    return true;
  };

  // The shared budget: one silent reload, then a dialog, reset once the
  // window has stayed up for stableAfterMs. Repeated triggers while a reload
  // or prompt is pending are ignored.
  const recover = (details, copy) => {
    closeHangPrompt();
    if (crashPrompt || pendingReload !== null) return;
    const at = now();
    if (lastCrashAt !== null && at - lastCrashAt >= stableAfterMs) reloads = 0;
    lastCrashAt = at;
    if (reloads < reloadLimit) {
      reloads += 1;
      if (reload()) return;
    }
    const controller = new AbortController();
    crashPrompt = controller;
    void runShellTask(log, copy.event, async () => {
      try {
        const choice = await showMessage({
          type: "error",
          title: copy.title,
          message: copy.message,
          detail: copy.detail(details),
          buttons: ["Reload", "Quit"],
          defaultId: 0,
          cancelId: 1,
          signal: controller.signal,
        });
        if (!alive() || crashPrompt !== controller || controller.signal.aborted) return;
        if (choice.response === 0) {
          reloads = 0;
          reload();
        } else {
          quit();
        }
      } finally {
        if (crashPrompt === controller) crashPrompt = null;
      }
    });
  };

  const onGone = (_event, details = {}) => {
    if (!alive() || details.reason === "clean-exit") return;
    writeLifecycle(log, "renderer-gone", details);
    recover(details, CRASH_COPY);
  };

  // A live process whose engine no longer draws: reload it exactly like a
  // crash. The reason must be one of the fixed engine reasons; anything else
  // is refused rather than logged as "unknown".
  const recoverFrom = (reason) => {
    if (!alive() || !ENGINE_REASONS.has(reason)) return false;
    const details = { reason, type: "Renderer" };
    writeLifecycle(log, "renderer-engine-dead", details);
    recover(details, ENGINE_COPY);
    return true;
  };

  const onUnresponsive = () => {
    if (!alive() || unresponsivePrompt || crashPrompt) return;
    writeLifecycle(log, "renderer-unresponsive");
    const controller = new AbortController();
    unresponsivePrompt = controller;
    void runShellTask(log, "renderer-hang-dialog-failed", async () => {
      try {
        const choice = await showMessage({
          type: "warning",
          title: "Clawnsole Is Not Responding",
          message: "Clawnsole's window is not responding.",
          detail: "You can give it more time or relaunch Clawnsole. Submitted "
            + "generations remain in your library and are checked again after relaunch.",
          buttons: ["Wait", "Relaunch"],
          defaultId: 0,
          cancelId: 0,
          signal: controller.signal,
        });
        if (!alive() || unresponsivePrompt !== controller || controller.signal.aborted) return;
        if (choice.response === 1) relaunch();
      } finally {
        if (unresponsivePrompt === controller) unresponsivePrompt = null;
      }
    });
  };
  const onResponsive = () => {
    if (unresponsivePrompt) writeLifecycle(log, "renderer-responsive");
    closeHangPrompt();
  };
  const onLoaded = () => {
    // Another recovery path, such as a restarted companion adopting its URL,
    // can load a new document while the crash-loop dialog is still open.
    // Its old answer must not quit or reload the newly restored window. Keep
    // the retry budget: a successful load alone does not prove stability.
    const prompt = crashPrompt;
    crashPrompt = null;
    if (prompt) {
      prompt.abort();
      writeLifecycle(log, "renderer-loaded-during-recovery");
    }
  };
  const dispose = () => {
    if (disposed) return;
    disposed = true;
    if (pendingReload !== null) clearImmediate(pendingReload);
    pendingReload = null;
    closeHangPrompt();
    crashPrompt?.abort();
    crashPrompt = null;
    contents.removeListener?.("render-process-gone", onGone);
    contents.removeListener?.("unresponsive", onUnresponsive);
    contents.removeListener?.("responsive", onResponsive);
    contents.removeListener?.("did-finish-load", onLoaded);
    contents.removeListener?.("destroyed", dispose);
    window.removeListener?.("closed", dispose);
  };
  contents.on("render-process-gone", onGone);
  contents.on("unresponsive", onUnresponsive);
  contents.on("responsive", onResponsive);
  contents.on("did-finish-load", onLoaded);
  contents.on("destroyed", dispose);
  window.once?.("closed", dispose);
  return { dispose, recoverFrom };
}

module.exports = { STABLE_AFTER_MS, installRendererRecovery };
