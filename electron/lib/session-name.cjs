"use strict";

const { spawn } = require("node:child_process");

const MAXIMUM_SOURCE_CHARACTERS = 2_048;
const MAXIMUM_INPUT_BYTES = 16_384;
const MAXIMUM_OUTPUT_BYTES = 4_096;
// The first on-device Foundation Models request can include model warm-up.
// This never blocks generation submission, so allow it enough time to finish
// while still guaranteeing that an unhealthy helper is reaped.
const DEFAULT_TIMEOUT_MS = 20_000;
const SESSION_NAME_CHANNEL = "clawnsole:session-name:generate";

function boundedSource(source) {
  if (typeof source !== "string") return "";
  return Array.from(source.trim()).slice(0, MAXIMUM_SOURCE_CHARACTERS).join("");
}

function generateSessionName(
  source,
  {
    executable,
    spawnImpl = spawn,
    timeoutMs = DEFAULT_TIMEOUT_MS,
  } = {},
) {
  const bounded = boundedSource(source);
  if (!bounded || typeof executable !== "string" || !executable) {
    return Promise.resolve(null);
  }
  const request = Buffer.from(`${JSON.stringify({ source: bounded })}\n`, "utf8");
  if (request.length > MAXIMUM_INPUT_BYTES) return Promise.resolve(null);

  return new Promise((resolve) => {
    let child;
    try {
      child = spawnImpl(executable, [], {
        env: {},
        stdio: ["pipe", "pipe", "pipe"],
        windowsHide: true,
      });
    } catch {
      resolve(null);
      return;
    }

    const output = [];
    let outputBytes = 0;
    let settled = false;
    let timer;
    const finish = (value, terminate = false) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (terminate && child.exitCode === null) child.kill("SIGKILL");
      resolve(value);
    };

    child.once("error", () => finish(null));
    child.stdout.on("data", (chunk) => {
      outputBytes += chunk.length;
      if (outputBytes > MAXIMUM_OUTPUT_BYTES) {
        finish(null, true);
        return;
      }
      output.push(chunk);
    });
    // The helper intentionally emits no diagnostics. Always drain stderr so a
    // framework-level message cannot block it, but never retain or log content.
    child.stderr.resume();
    child.stdin.on("error", () => {});
    child.once("close", (code) => {
      if (settled || code !== 0) {
        finish(null);
        return;
      }
      try {
        const decoded = JSON.parse(Buffer.concat(output).toString("utf8"));
        if (typeof decoded.name !== "string") {
          finish(null);
          return;
        }
        const name = Array.from(decoded.name.trim())
          .slice(0, 128)
          .join("");
        finish(name || null);
      } catch {
        finish(null);
      }
    });

    timer = setTimeout(() => finish(null, true), Math.max(1, timeoutMs));
    child.stdin.end(request);
  });
}

function installSessionNameHandler({
  ipcMain,
  isAllowedAppUrl,
  rendererUrl,
  executable,
  generate = generateSessionName,
}) {
  ipcMain.handle(SESSION_NAME_CHANNEL, (event, source) => {
    const allowedRendererUrl = typeof rendererUrl === "function"
      ? rendererUrl()
      : rendererUrl;
    if (!isAllowedAppUrl(event.senderFrame?.url, allowedRendererUrl)) {
      return null;
    }
    const helperExecutable = typeof executable === "function"
      ? executable()
      : executable;
    return generate(source, { executable: helperExecutable });
  });
}

module.exports = {
  DEFAULT_TIMEOUT_MS,
  MAXIMUM_INPUT_BYTES,
  MAXIMUM_OUTPUT_BYTES,
  MAXIMUM_SOURCE_CHARACTERS,
  SESSION_NAME_CHANNEL,
  boundedSource,
  generateSessionName,
  installSessionNameHandler,
};
