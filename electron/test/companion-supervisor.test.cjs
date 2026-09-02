"use strict";

const assert = require("node:assert/strict");
const { EventEmitter } = require("node:events");
const test = require("node:test");

const {
  CompanionSupervisor,
  HEALTH_FAILURES_BEFORE_RESTART,
  HEALTH_INTERVAL_MS,
} = require("../lib/companion-supervisor.cjs");

const BOOTSTRAP = `${JSON.stringify({ deviceKey: "d", requestToken: "t" })}\n`;

class FakeChild extends EventEmitter {
  constructor() {
    super();
    this.exitCode = null;
    this.signals = [];
    this.bootstrap = null;
    this.stdout = new EventEmitter();
    this.stderr = new EventEmitter();
    this.stdin = Object.assign(new EventEmitter(), {
      end: (line, callback) => {
        this.bootstrap = line;
        callback();
      },
    });
  }

  kill(signal) {
    this.signals.push(signal);
    this.exit(null, signal);
  }

  exit(code, signal = null) {
    if (this.exitCode !== null) return;
    this.exitCode = code ?? 0;
    this.emit("exit", code, signal);
  }
}

function fakeLog() {
  return {
    attached: [],
    entries: [],
    attach(stream, label) {
      this.attached.push(label);
    },
    write(label, text) {
      this.entries.push(`${label}: ${text}`);
    },
  };
}

// Builds a supervisor over fake process, port, and health primitives. Ports
// are handed out in order; a restart that asks for a port still in the list
// gets it back, which is how the renderer origin usually survives.
function build(t, { ports = [43123], overrides = {} } = {}) {
  const spawned = [];
  const restarted = [];
  const failures = [];
  const available = [...ports];
  const log = fakeLog();
  const supervisor = new CompanionSupervisor({
    executable: "/Resources/companion/clawnsole_companion",
    argumentsFor: (port) => ["--port", String(port), "--secure-bootstrap"],
    cwd: "/Resources/renderer",
    env: { CLAWNSOLE: "1" },
    bootstrapLine: BOOTSTRAP,
    log,
    onRestarted: (info) => restarted.push(info),
    onFailed: (reason) => failures.push(reason),
    spawn: (executable, args, options) => {
      const child = new FakeChild();
      spawned.push({ child, executable, args, options });
      return child;
    },
    findOpenPort: async (host, { preferred = null } = {}) => {
      assert.equal(host, "127.0.0.1");
      const index = preferred === null ? -1 : available.indexOf(preferred);
      if (index !== -1) return available[index];
      const next = available.find((port) => port !== preferred);
      if (next === undefined) throw new Error("no port available");
      return next;
    },
    waitForServer: async (url, { isProcessAlive }) => {
      if (!isProcessAlive()) throw new Error(`${url} never came up`);
    },
    fetchImpl: async () => ({ ok: true, status: 200 }),
    healthIntervalMs: 0,
    restartDelayMs: 1,
    ...overrides,
  });
  t.after(() => supervisor.stop());
  return { failures, log, restarted, spawned, supervisor };
}

function settle(times = 6) {
  return new Promise((resolve) => {
    let remaining = times;
    const step = () => {
      remaining -= 1;
      if (remaining <= 0) resolve();
      else setTimeout(step, 2);
    };
    setTimeout(step, 2);
  });
}

test("the supervisor rejects an unusable configuration", () => {
  const valid = {
    executable: "/companion",
    argumentsFor: () => [],
    bootstrapLine: BOOTSTRAP,
  };
  assert.throws(
    () => new CompanionSupervisor({ ...valid, executable: "" }),
    /executable/,
  );
  assert.throws(
    () => new CompanionSupervisor({ ...valid, argumentsFor: null }),
    /arguments/,
  );
  assert.throws(
    () => new CompanionSupervisor({ ...valid, bootstrapLine: "{}" }),
    /bootstrap/,
  );
});

test("starting the companion bootstraps it on an allocated port", async (t) => {
  const { log, spawned, supervisor } = build(t);
  const url = await supervisor.start();

  assert.equal(url, "http://127.0.0.1:43123");
  assert.equal(supervisor.url, url);
  assert.equal(supervisor.running, true);
  assert.equal(spawned.length, 1);
  assert.equal(spawned[0].executable, "/Resources/companion/clawnsole_companion");
  assert.deepEqual(spawned[0].args, ["--port", "43123", "--secure-bootstrap"]);
  assert.deepEqual(spawned[0].options, {
    cwd: "/Resources/renderer",
    env: { CLAWNSOLE: "1" },
    stdio: ["pipe", "pipe", "pipe"],
  });
  assert.equal(spawned[0].child.bootstrap, BOOTSTRAP);
  assert.deepEqual(log.attached, ["out", "error"]);
});

test("an unexpected exit is restarted once on the same port", async (t) => {
  const { log, restarted, spawned, supervisor } = build(t);
  await supervisor.start();

  spawned[0].child.exit(1);
  await settle();

  assert.equal(spawned.length, 2);
  assert.equal(spawned[1].child.bootstrap, BOOTSTRAP);
  assert.deepEqual(restarted, [
    { url: "http://127.0.0.1:43123", changedUrl: false },
  ]);
  assert.equal(supervisor.url, "http://127.0.0.1:43123");
  assert.ok(log.entries.some((entry) => entry.includes("Restarting in")));
});

test("a restart onto a new port reports the moved renderer origin", async (t) => {
  const handed = [];
  const { restarted, spawned, supervisor } = build(t, {
    overrides: {
      // The previous port has been taken in the meantime, so the companion
      // comes back somewhere else and the renderer origin moves with it.
      findOpenPort: async (_host, { preferred = null } = {}) => {
        handed.push(preferred);
        return handed.length === 1 ? 43123 : 43124;
      },
    },
  });
  await supervisor.start();

  spawned[0].child.exit(1);
  await settle();

  assert.deepEqual(handed, [null, 43123]);
  assert.deepEqual(restarted, [
    { url: "http://127.0.0.1:43124", changedUrl: true },
  ]);
  assert.equal(supervisor.url, "http://127.0.0.1:43124");
  assert.deepEqual(spawned[1].args, [
    "--port",
    "43124",
    "--secure-bootstrap",
  ]);
});

test("a second failure reaches the shell instead of looping", async (t) => {
  const { failures, restarted, spawned, supervisor } = build(t);
  await supervisor.start();

  spawned[0].child.exit(1);
  await settle();
  assert.equal(restarted.length, 1);

  spawned[1].child.exit(2);
  await settle();

  assert.equal(spawned.length, 2, "a crash loop must not respawn again");
  assert.equal(failures.length, 1);
  assert.match(failures[0], /The companion exited \(2\)\./);
});

test("a companion that stayed up earns a fresh restart budget", async (t) => {
  let clock = 0;
  const { failures, restarted, spawned, supervisor } = build(t, {
    overrides: {
      now: () => clock,
      stableAfterMs: 1_000,
    },
  });
  await supervisor.start();

  spawned[0].child.exit(1);
  await settle();
  assert.equal(restarted.length, 1);

  clock = 5_000;
  spawned[1].child.exit(1);
  await settle();

  assert.equal(restarted.length, 2);
  assert.deepEqual(failures, []);
});

test("repeated health failures are treated as an exit", async (t) => {
  let healthy = true;
  const { restarted, spawned, supervisor } = build(t, {
    overrides: {
      healthIntervalMs: 2,
      healthFailuresBeforeRestart: 2,
      fetchImpl: async () => {
        if (!healthy) throw new Error("connection refused");
        return { ok: true, status: 200 };
      },
    },
  });
  await supervisor.start();
  healthy = false;

  const deadline = Date.now() + 2_000;
  while (restarted.length === 0 && Date.now() < deadline) await settle(2);

  assert.deepEqual(restarted, [
    { url: "http://127.0.0.1:43123", changedUrl: false },
  ]);
  assert.equal(spawned.length, 2);
  assert.deepEqual(spawned[0].child.signals, ["SIGKILL"]);
});

test("a single health failure is forgiven", async (t) => {
  let failNext = true;
  const { failures, restarted, supervisor } = build(t, {
    overrides: {
      healthIntervalMs: 2,
      healthFailuresBeforeRestart: 3,
      fetchImpl: async () => {
        if (failNext) {
          failNext = false;
          throw new Error("one blip");
        }
        return { ok: true, status: 200 };
      },
    },
  });
  await supervisor.start();
  await settle(10);

  assert.deepEqual(restarted, []);
  assert.deepEqual(failures, []);
  assert.equal(supervisor.running, true);
});

test("stopping the companion is deliberate and never restarts it", async (t) => {
  const { failures, restarted, spawned, supervisor } = build(t);
  await supervisor.start();

  supervisor.stop();
  await settle();

  assert.deepEqual(spawned[0].child.signals, ["SIGTERM"]);
  assert.equal(spawned.length, 1);
  assert.deepEqual(restarted, []);
  assert.deepEqual(failures, []);
  assert.equal(supervisor.running, false);
});

test("the health cadence matches the documented contract", () => {
  assert.equal(HEALTH_INTERVAL_MS, 30_000);
  assert.equal(HEALTH_FAILURES_BEFORE_RESTART, 3);
});
