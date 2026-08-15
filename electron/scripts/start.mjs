#!/usr/bin/env node

import { spawn } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import runtime from "../lib/runtime.cjs";

const { findOpenPort, waitForServer } = runtime;
const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const electronDirectory = path.resolve(scriptDirectory, "..");
const repositoryRoot = path.resolve(electronDirectory, "..");
const flutterDirectory = path.join(repositoryRoot, "flutter");
const webRoot = path.join(flutterDirectory, "build", "web");
const requestedPort = process.env.CLAWNSOLE_WEB_PORT?.trim();
const port = requestedPort ? Number(requestedPort) : await findOpenPort();
if (!Number.isInteger(port) || port < 1 || port > 65_535) {
  throw new Error("CLAWNSOLE_WEB_PORT must be an integer between 1 and 65535.");
}

const rendererUrl = `http://127.0.0.1:${port}`;
const dataFile = process.env.CLAWNSOLE_FLUTTER_DATA_FILE
  || path.join(repositoryRoot, ".clawnsole", "clawnsole.json");
const executableSuffix = process.platform === "win32" ? ".cmd" : "";
const electronExecutable = path.join(
  electronDirectory,
  "node_modules",
  ".bin",
  `electron${executableSuffix}`,
);

let companionProcess = null;
let electronProcess = null;
let isStopping = false;

function stopProcess(child, signal = "SIGTERM") {
  if (!child || child.exitCode !== null) return;
  try {
    if (process.platform !== "win32") process.kill(-child.pid, signal);
    else child.kill(signal);
  } catch {
    child.kill(signal);
  }
}

async function run() {
  companionProcess = spawn(
    "dart",
    [
      "run",
      "tool/clawnsole_companion.dart",
      "--port",
      String(port),
      "--data-file",
      dataFile,
      "--web-root",
      webRoot,
    ],
    {
      cwd: flutterDirectory,
      detached: process.platform !== "win32",
      env: process.env,
      stdio: "inherit",
    },
  );

  await waitForServer(`${rendererUrl}/health`, {
    timeoutMs: 60_000,
    isProcessAlive: () => Boolean(
      companionProcess && companionProcess.exitCode === null,
    ),
  });

  console.log(`Opening Clawnsole for macOS at ${rendererUrl}…`);
  electronProcess = spawn(
    electronExecutable,
    [electronDirectory, ...process.argv.slice(2)],
    {
      cwd: electronDirectory,
      env: { ...process.env, CLAWNSOLE_RENDERER_URL: rendererUrl },
      stdio: "inherit",
    },
  );

  const exitCode = await new Promise((resolve) => {
    electronProcess.once("exit", (code, signal) => resolve(signal ? 1 : (code ?? 0)));
  });
  isStopping = true;
  stopProcess(companionProcess);
  process.exitCode = exitCode;
}

for (const signal of ["SIGINT", "SIGTERM"]) {
  process.on(signal, () => {
    if (isStopping) return;
    isStopping = true;
    stopProcess(electronProcess);
    stopProcess(companionProcess);
    process.exit(0);
  });
}

run().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  stopProcess(electronProcess);
  stopProcess(companionProcess);
  process.exitCode = 1;
});
