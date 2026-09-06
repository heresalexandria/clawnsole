"use strict";

const assert = require("node:assert/strict");
const { EventEmitter } = require("node:events");
const test = require("node:test");

const {
  STABLE_AFTER_MS,
  installRendererRecovery,
} = require("../lib/renderer-recovery.cjs");

// A stand-in for the BrowserWindow the shell installs recovery on: only its
// webContents events, reloads, and the dialogs it triggers are observable.
function harness({ answers = [], now = () => 0, ...options } = {}) {
  const events = new EventEmitter();
  const prompts = [];
  const actions = [];
  const window = {
    webContents: {
      on: (name, listener) => events.on(name, listener),
      reload: () => actions.push("reload"),
    },
  };
  const queue = [...answers];
  installRendererRecovery({
    window,
    now,
    showMessage: async (message) => {
      prompts.push(message);
      const next = queue.shift();
      if (typeof next === "function") return next(message);
      return { response: next ?? 0 };
    },
    relaunch: () => actions.push("relaunch"),
    quit: () => actions.push("quit"),
    ...options,
  });
  return { actions, events, prompts };
}

const flush = () => new Promise((resolve) => setImmediate(() => setImmediate(resolve)));

test("a clean renderer exit is not a crash", async () => {
  const { actions, events, prompts } = harness();
  events.emit("render-process-gone", {}, { reason: "clean-exit" });
  await flush();
  assert.deepEqual(actions, []);
  assert.deepEqual(prompts, []);
});

test("the first renderer crash reloads the window silently", async () => {
  const { actions, events, prompts } = harness();
  events.emit("render-process-gone", {}, { reason: "crashed" });
  await flush();
  assert.deepEqual(actions, ["reload"]);
  assert.deepEqual(prompts, []);
});

test("a crash loop asks the user to reload or quit", async () => {
  const { actions, events, prompts } = harness({ answers: [1] });
  events.emit("render-process-gone", {}, { reason: "crashed" });
  await flush();
  events.emit("render-process-gone", {}, { reason: "oom" });
  await flush();

  assert.equal(prompts.length, 1);
  assert.deepEqual(prompts[0].buttons, ["Reload", "Quit"]);
  assert.match(prompts[0].detail, /oom/);
  assert.deepEqual(actions, ["reload", "quit"]);
});

test("choosing Reload restores the crash budget", async () => {
  const { actions, events } = harness({ answers: [0] });
  events.emit("render-process-gone", {}, { reason: "crashed" });
  await flush();
  events.emit("render-process-gone", {}, { reason: "crashed" });
  await flush();
  assert.deepEqual(actions, ["reload", "reload"]);

  // The window is healthy again, so the next crash is a first crash.
  events.emit("render-process-gone", {}, { reason: "crashed" });
  await flush();
  assert.deepEqual(actions, ["reload", "reload", "reload"]);
});

test("a crash long after the last one is not a loop", async () => {
  let clock = 0;
  const { actions, events, prompts } = harness({ now: () => clock });
  events.emit("render-process-gone", {}, { reason: "crashed" });
  await flush();

  clock = STABLE_AFTER_MS + 1;
  events.emit("render-process-gone", {}, { reason: "crashed" });
  await flush();

  assert.deepEqual(prompts, []);
  assert.deepEqual(actions, ["reload", "reload"]);
});

test("an unresponsive window offers waiting or relaunching", async () => {
  const { actions, events, prompts } = harness({ answers: [1] });
  events.emit("unresponsive");
  await flush();

  assert.equal(prompts.length, 1);
  assert.deepEqual(prompts[0].buttons, ["Wait", "Relaunch"]);
  assert.equal(prompts[0].defaultId, 0);
  assert.ok(prompts[0].signal, "the prompt must be cancellable");
  assert.deepEqual(actions, ["relaunch"]);
});

test("waiting leaves the window alone and only one prompt appears", async () => {
  const { actions, events, prompts } = harness({ answers: [0, 0] });
  events.emit("unresponsive");
  events.emit("unresponsive");
  await flush();

  assert.equal(prompts.length, 1);
  assert.deepEqual(actions, []);
});

test("a window that recovers on its own closes its own prompt", async () => {
  let aborted = false;
  const { actions, events, prompts } = harness({
    answers: [
      (message) => new Promise((resolve) => {
        message.signal.addEventListener("abort", () => {
          aborted = true;
          resolve({ response: message.cancelId });
        });
      }),
    ],
  });
  events.emit("unresponsive");
  await flush();
  assert.equal(prompts.length, 1);

  events.emit("responsive");
  await flush();
  assert.equal(aborted, true);
  assert.deepEqual(actions, []);

  // With the prompt gone, a later hang prompts again.
  events.emit("unresponsive");
  await flush();
  assert.equal(prompts.length, 2);
});

test("dialog rejection is contained and allows a later recovery prompt", async () => {
  const { actions, events, prompts } = harness({
    answers: [() => Promise.reject(new Error("native dialog closed")), 0],
  });
  events.emit("unresponsive");
  await flush();
  events.emit("unresponsive");
  await flush();
  assert.equal(prompts.length, 2);
  assert.deepEqual(actions, []);
});

test("a stale hang answer cannot relaunch a recovered window", async () => {
  let answer;
  const { actions, events } = harness({
    answers: [() => new Promise((resolve) => { answer = resolve; })],
  });
  events.emit("unresponsive");
  events.emit("responsive");
  answer({ response: 1 });
  await flush();
  assert.deepEqual(actions, []);
});

test("a crash invalidates the hang prompt before reloading", async () => {
  let answer;
  const { actions, events, prompts } = harness({
    answers: [() => new Promise((resolve) => { answer = resolve; })],
  });
  events.emit("unresponsive");
  events.emit("render-process-gone", {}, { reason: "crashed" });
  assert.equal(prompts[0].signal.aborted, true);
  answer({ response: 1 });
  await flush();
  assert.deepEqual(actions, ["reload"]);
});

test("duplicate crash events share one prompt and closed windows ignore its answer", async () => {
  let answer;
  const { actions, events, prompts } = harness({
    answers: [() => new Promise((resolve) => { answer = resolve; })],
  });
  events.emit("render-process-gone", {}, { reason: "crashed" });
  await flush();
  events.emit("render-process-gone", {}, { reason: "crashed" });
  events.emit("render-process-gone", {}, { reason: "oom" });
  assert.equal(prompts.length, 1);
  events.emit("destroyed");
  assert.equal(prompts[0].signal.aborted, true);
  answer({ response: 1 });
  await flush();
  assert.deepEqual(actions, ["reload"]);
});

test("crash dialog rejection and logging failure do not escape recovery", async () => {
  const { actions, events } = harness({
    log: { write: () => { throw new Error("disk unavailable"); } },
    answers: [() => Promise.reject(new Error("dialog unavailable"))],
  });
  events.emit("render-process-gone", {}, { reason: "crashed" });
  await flush();
  events.emit("render-process-gone", {}, { reason: "crashed" });
  await flush();
  assert.deepEqual(actions, ["reload"]);
});


test("renderer navigation waits until native crash teardown returns", async () => {
  const { actions, events } = harness();
  events.emit("render-process-gone", {}, { reason: "crashed" });
  assert.deepEqual(actions, [], "navigation must not re-enter native teardown");
  await flush();
  assert.deepEqual(actions, ["reload"]);
});

test("closing a window cancels an already queued automatic reload", async () => {
  const { actions, events } = harness();
  events.emit("render-process-gone", {}, { reason: "crashed" });
  events.emit("destroyed");
  await flush();
  assert.deepEqual(actions, []);
});

test("a companion reload invalidates a pending crash answer without resetting the budget", async () => {
  let answer;
  const { actions, events, prompts } = harness({
    answers: [() => new Promise((resolve) => { answer = resolve; }), 0],
  });
  events.emit("render-process-gone", {}, { reason: "crashed" });
  await flush();
  events.emit("did-finish-load");
  events.emit("render-process-gone", {}, { reason: "crashed" });
  assert.equal(prompts.length, 1);

  // The companion restarts and independently navigates the same window to
  // its live URL. A late answer from the old crash dialog is now irrelevant.
  events.emit("did-finish-load");
  assert.equal(prompts[0].signal.aborted, true);
  answer({ response: 1 });
  await flush();
  assert.deepEqual(actions, ["reload"]);

  events.emit("render-process-gone", {}, { reason: "crashed" });
  await flush();
  assert.equal(prompts.length, 2, "loading alone must not reset the crash-loop budget");
  assert.deepEqual(actions, ["reload", "reload"]);
});
