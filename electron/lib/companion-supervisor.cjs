"use strict";

const { spawn: spawnProcess } = require("node:child_process");
const {
  findOpenPort: allocatePort,
  waitForServer: awaitServer,
} = require("./runtime.cjs");

const HEALTH_INTERVAL_MS = 30_000;
const HEALTH_TIMEOUT_MS = 5_000;
const HEALTH_FAILURES_BEFORE_RESTART = 3;
const RESTART_DELAY_MS = 1_500;
const STABLE_AFTER_MS = 10 * 60 * 1000;

// Runs the bundled companion for the life of the shell. An unexpected exit,
// or a run of failed /health pings, triggers one automatic restart after a
// short backoff. The restart prefers the previous port so the renderer origin
// usually survives, and always replays the same bootstrap line so the
// companion reopens the same secure store with the same session token. A
// second failure before the companion has stayed up for STABLE_AFTER_MS is
// reported through onFailed so the shell can ask the user what to do.
class CompanionSupervisor {
  #child = null;
  #port = null;
  #stopping = false;
  #launching = false;
  #restarts = 0;
  #startedAt = null;
  #healthFailures = 0;
  #healthTimer = null;
  #restartTimer = null;

  constructor({
    executable,
    argumentsFor,
    cwd,
    env,
    bootstrapLine,
    log = null,
    onRestarted = () => {},
    onFailed = () => {},
    spawn = spawnProcess,
    findOpenPort = allocatePort,
    waitForServer = awaitServer,
    fetchImpl = globalThis.fetch,
    now = Date.now,
    healthIntervalMs = HEALTH_INTERVAL_MS,
    healthTimeoutMs = HEALTH_TIMEOUT_MS,
    healthFailuresBeforeRestart = HEALTH_FAILURES_BEFORE_RESTART,
    restartDelayMs = RESTART_DELAY_MS,
    maxRestarts = 1,
    stableAfterMs = STABLE_AFTER_MS,
  }) {
    if (typeof executable !== "string" || !executable) {
      throw new TypeError("A companion executable is required.");
    }
    if (typeof argumentsFor !== "function") {
      throw new TypeError("Companion arguments must be derived from the port.");
    }
    if (typeof bootstrapLine !== "string" || !bootstrapLine.endsWith("\n")) {
      throw new TypeError("A companion bootstrap line is required.");
    }
    this.executable = executable;
    this.argumentsFor = argumentsFor;
    this.cwd = cwd;
    this.env = env;
    this.bootstrapLine = bootstrapLine;
    this.log = log;
    this.onRestarted = onRestarted;
    this.onFailed = onFailed;
    this.spawn = spawn;
    this.findOpenPort = findOpenPort;
    this.waitForServer = waitForServer;
    this.fetch = fetchImpl;
    this.now = now;
    this.healthIntervalMs = healthIntervalMs;
    this.healthTimeoutMs = healthTimeoutMs;
    this.healthFailuresBeforeRestart = healthFailuresBeforeRestart;
    this.restartDelayMs = restartDelayMs;
    this.maxRestarts = maxRestarts;
    this.stableAfterMs = stableAfterMs;
    this.url = null;
  }

  get running() {
    return Boolean(this.#child && this.#child.exitCode === null);
  }

  async start() {
    this.url = await this.#launch(null);
    return this.url;
  }

  stop() {
    this.#stopping = true;
    this.#clearTimers();
    const child = this.#child;
    this.#child = null;
    if (child && child.exitCode === null) child.kill("SIGTERM");
  }

  async #launch(preferredPort) {
    this.#launching = true;
    try {
      const port = await this.findOpenPort("127.0.0.1", { preferred: preferredPort });
      const url = `http://127.0.0.1:${port}`;
      const child = this.spawn(this.executable, this.argumentsFor(port), {
        cwd: this.cwd,
        env: this.env,
        stdio: ["pipe", "pipe", "pipe"],
      });
      this.#child = child;
      this.#port = port;
      this.log?.attach(child.stdout, "out");
      this.log?.attach(child.stderr, "error");
      child.once("exit", (code, signal) => {
        if (this.#child !== child) return;
        this.#child = null;
        this.log?.write("shell", `The companion exited (${signal || code}).`);
        if (!this.#stopping && !this.#launching) {
          this.#recover(`The companion exited (${signal || code}).`);
        }
      });

      await new Promise((resolve, reject) => {
        const failed = () => reject(
          new Error("Clawnsole could not initialize its local secure storage."),
        );
        child.stdin.once("error", failed);
        child.stdin.end(this.bootstrapLine, () => {
          child.stdin.removeListener("error", failed);
          resolve();
        });
      });

      await this.waitForServer(`${url}/health`, {
        isProcessAlive: () => this.#child === child && child.exitCode === null,
      });
      this.#startedAt = this.now();
      this.#healthFailures = 0;
      this.#scheduleHealth();
      return url;
    } finally {
      this.#launching = false;
    }
  }

  #recover(reason) {
    this.#clearTimers();
    if (this.#stopping) return;
    // A companion that ran cleanly for a while has earned a fresh restart
    // budget; only a crash loop reaches the user.
    if (
      this.#startedAt !== null
      && this.now() - this.#startedAt >= this.stableAfterMs
    ) {
      this.#restarts = 0;
    }
    if (this.#restarts >= this.maxRestarts) {
      this.onFailed(reason);
      return;
    }
    this.#restarts += 1;
    this.log?.write(
      "shell",
      `${reason} Restarting in ${this.restartDelayMs}ms `
        + `(attempt ${this.#restarts} of ${this.maxRestarts}).`,
    );
    this.#restartTimer = setTimeout(() => {
      this.#restartTimer = null;
      void this.#restart(reason);
    }, this.restartDelayMs);
  }

  async #restart(reason) {
    if (this.#stopping) return;
    const previousUrl = this.url;
    try {
      this.url = await this.#launch(this.#port);
    } catch (error) {
      if (this.#stopping) return;
      this.onFailed(`${reason} ${error.message}`);
      return;
    }
    this.log?.write("shell", `The companion restarted at ${this.url}.`);
    this.onRestarted({ url: this.url, changedUrl: this.url !== previousUrl });
  }

  #scheduleHealth() {
    this.#clearHealthTimer();
    if (!(this.healthIntervalMs > 0)) return;
    this.#healthTimer = setInterval(
      () => void this.#pingHealth(),
      this.healthIntervalMs,
    );
    this.#healthTimer.unref?.();
  }

  async #pingHealth() {
    if (this.#stopping || this.#launching || !this.#child) return;
    const child = this.#child;
    try {
      const response = await this.fetch(`${this.url}/health`, {
        signal: AbortSignal.timeout(this.healthTimeoutMs),
      });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      this.#healthFailures = 0;
      return;
    } catch (error) {
      if (this.#child !== child || this.#stopping) return;
      this.#healthFailures += 1;
      this.log?.write(
        "shell",
        `Health check failed (${this.#healthFailures} of `
          + `${this.healthFailuresBeforeRestart}): ${error.message}`,
      );
      if (this.#healthFailures < this.healthFailuresBeforeRestart) return;
    }
    // The process is alive but no longer answering, so treat it as an exit.
    this.#healthFailures = 0;
    this.#child = null;
    if (child.exitCode === null) child.kill("SIGKILL");
    this.#recover("The companion stopped answering health checks.");
  }

  #clearHealthTimer() {
    if (this.#healthTimer !== null) {
      clearInterval(this.#healthTimer);
      this.#healthTimer = null;
    }
  }

  #clearTimers() {
    this.#clearHealthTimer();
    if (this.#restartTimer !== null) {
      clearTimeout(this.#restartTimer);
      this.#restartTimer = null;
    }
  }
}

module.exports = {
  CompanionSupervisor,
  HEALTH_FAILURES_BEFORE_RESTART,
  HEALTH_INTERVAL_MS,
  RESTART_DELAY_MS,
  STABLE_AFTER_MS,
};
