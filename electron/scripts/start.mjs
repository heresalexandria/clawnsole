#!/usr/bin/env node

import { spawn } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const electronDirectory = path.resolve(scriptDirectory, "..");
const repositoryRoot = path.resolve(electronDirectory, "..");
const port = Number(process.env.CLAWNSOLE_WEB_PORT || "3000");
if (!Number.isInteger(port) || port < 1 || port > 65_535) {
  throw new Error("CLAWNSOLE_WEB_PORT must be an integer between 1 and 65535.");
}
const rendererUrl = `http://127.0.0.1:${port}`;
const executableSuffix = process.platform === "win32" ? ".cmd" : "";
const electronExecutable = path.join(electronDirectory, "node_modules", ".bin", `electron${executableSuffix}`);

let nextProcess = null;
let electronProcess = null;
let isStopping = false;

async function isReady() {
  try {
    const response = await fetch(`${rendererUrl}/api/local-state`, {
      signal: AbortSignal.timeout(1_500),
    });
    if (!response.ok) return false;
    const state = await response.json();
    return Array.isArray(state.generations) && typeof state.storage === "object";
  } catch {
    return false;
  }
}

async function waitUntilReady() {
  for (let attempt = 0; attempt < 120; attempt += 1) {
    if (await isReady()) return;
    if (nextProcess?.exitCode !== null) {
      throw new Error("The Next.js development server stopped before it became ready.");
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw new Error(`The Next.js development server did not become ready at ${rendererUrl}.`);
}

function stopOwnedNextServer() {
  if (!nextProcess || nextProcess.exitCode !== null) return;
  try {
    process.kill(-nextProcess.pid, "SIGTERM");
  } catch {
    nextProcess.kill("SIGTERM");
  }
  nextProcess = null;
}

function stopElectron() {
  if (!electronProcess || electronProcess.exitCode !== null) return;
  electronProcess.kill("SIGTERM");
  electronProcess = null;
}

async function run() {
  if (await isReady()) {
    console.log(`Using the Clawnsole server already running at ${rendererUrl}.`);
  } else {
    console.log(`Starting the Clawnsole server at ${rendererUrl}…`);
    nextProcess = spawn(
      "npm",
      ["run", "dev", "--", "--hostname", "127.0.0.1", "--port", String(port)],
      {
        cwd: repositoryRoot,
        detached: process.platform !== "win32",
        env: process.env,
        stdio: "inherit",
      },
    );
    await waitUntilReady();
  }

  console.log("Opening Clawnsole for macOS…");
  electronProcess = spawn(electronExecutable, [electronDirectory, ...process.argv.slice(2)], {
    cwd: electronDirectory,
    env: { ...process.env, CLAWNSOLE_RENDERER_URL: rendererUrl },
    stdio: "inherit",
  });

  const exitCode = await new Promise((resolve) => {
    electronProcess.once("exit", (code, signal) => resolve(signal ? 1 : (code ?? 0)));
  });
  isStopping = true;
  stopOwnedNextServer();
  process.exitCode = exitCode;
}

for (const signal of ["SIGINT", "SIGTERM"]) {
  process.on(signal, () => {
    if (isStopping) return;
    isStopping = true;
    stopElectron();
    stopOwnedNextServer();
    process.exit(0);
  });
}

run().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  stopElectron();
  stopOwnedNextServer();
  process.exitCode = 1;
});
