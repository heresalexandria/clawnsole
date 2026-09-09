"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { sanitizeAppMetrics } = require("./renderer-diagnostics.cjs");

const CRASH_REPORT_NAME = /^clawnsole(?:[ _-]|$)/i;
const MAX_CRASH_REPORTS = 12;
const FILE_CAP_BYTES = 5 * 1024 * 1024;
const TOTAL_CAP_BYTES = 40 * 1024 * 1024;
const LOG_FILES = ["companion.log", "companion.log.1"];
const RUNTIME_VERSION_KEYS = ["electron", "chrome", "node", "v8"];
const RENDERER_VERSION_KEYS = ["app_name", "version", "build_number", "package_name"];
// Shown in the save dialog and written at the top of the bundle. Log lines
// are sanitized, but macOS crash reports and file listings are copied as-is.
const PRIVACY_NOTICE = "This report may contain your computer's name and file paths. "
  + "Review it before sharing.";

function reportFileName(now) {
  const stamp = now.toISOString().replace(/\.\d{3}Z$/, "Z").replace(/:/g, "-");
  return `Clawnsole-Diagnostics-${stamp}.txt`;
}

function pick(source, keys, maxLength = 64) {
  const result = {};
  if (!source || typeof source !== "object") return result;
  for (const key of keys) {
    const value = source[key];
    if (typeof value === "string" && value.length <= maxLength) result[key] = value;
    else if (typeof value === "number" && Number.isFinite(value)) result[key] = value;
  }
  return result;
}

// Flutter writes version.json beside the renderer bundle. Anything but the
// expected small object of short strings is reported as unavailable.
function readRendererVersion(rendererDirectory, fsImpl) {
  if (typeof rendererDirectory !== "string") return null;
  try {
    const raw = fsImpl.readFileSync(path.join(rendererDirectory, "version.json"), "utf8");
    if (raw.length > 4096) return null;
    return pick(JSON.parse(raw), RENDERER_VERSION_KEYS);
  } catch {
    return null;
  }
}

// Crash reports named for Clawnsole, newest first. Regular files only:
// aliases, symlinks and directories inside DiagnosticReports are skipped.
function crashReportEntries(directories, { fsImpl = fs, limit = MAX_CRASH_REPORTS } = {}) {
  const entries = [];
  for (const directory of directories) {
    let names = [];
    try {
      names = fsImpl.readdirSync(directory);
    } catch {
      continue;
    }
    for (const name of names) {
      if (!CRASH_REPORT_NAME.test(name)) continue;
      const file = path.join(directory, name);
      try {
        const stat = fsImpl.lstatSync(file);
        if (!stat.isFile()) continue;
        entries.push({ file, mtimeMs: stat.mtimeMs, size: stat.size });
      } catch {
        // A report that vanished or cannot be read is simply absent.
      }
    }
  }
  entries.sort((a, b) => b.mtimeMs - a.mtimeMs || a.file.localeCompare(b.file));
  return entries.slice(0, limit);
}

function readCapped(file, capBytes, fsImpl) {
  const descriptor = fsImpl.openSync(file, "r");
  try {
    const size = fsImpl.fstatSync(descriptor).size;
    const length = Math.min(size, capBytes);
    const buffer = Buffer.alloc(length);
    let offset = 0;
    while (offset < length) {
      const read = fsImpl.readSync(descriptor, buffer, offset, length - offset, offset);
      if (read <= 0) break;
      offset += read;
    }
    return { text: buffer.subarray(0, offset).toString("utf8"), bytes: offset, truncated: size > length };
  } finally {
    fsImpl.closeSync(descriptor);
  }
}

function header(title) {
  return `\n==================== ${title} ====================\n`;
}

// Produces one UTF-8 text bundle: environment, renderer version, process
// metrics, both companion logs and the newest Clawnsole crash reports, each
// under its own header, with per-file and total size caps.
function buildDiagnosticsReport({
  fsImpl = fs,
  now = () => new Date(),
  logDirectory,
  reportDirectories = [],
  rendererDirectory = null,
  versions = {},
  platform = process.platform,
  arch = process.arch,
  systemVersion = null,
  appMetrics = [],
  fileCapBytes = FILE_CAP_BYTES,
  totalCapBytes = TOTAL_CAP_BYTES,
} = {}) {
  const generatedAt = now();
  const parts = [
    `Clawnsole diagnostics report\nGenerated: ${generatedAt.toISOString()}\n${PRIVACY_NOTICE}\n`,
  ];
  const environment = {
    platform: typeof platform === "string" ? platform.slice(0, 32) : null,
    arch: typeof arch === "string" ? arch.slice(0, 32) : null,
    systemVersion: typeof systemVersion === "string" ? systemVersion.slice(0, 64) : null,
    versions: pick(versions, RUNTIME_VERSION_KEYS),
    renderer: readRendererVersion(rendererDirectory, fsImpl),
  };
  parts.push(header("Environment"), `${JSON.stringify(environment, null, 2)}\n`);
  let processes = [];
  try {
    processes = sanitizeAppMetrics(typeof appMetrics === "function" ? appMetrics() : appMetrics);
  } catch {
    processes = [];
  }
  parts.push(header("Process metrics"), `${JSON.stringify(processes, null, 2)}\n`);

  const candidates = [
    ...(typeof logDirectory === "string"
      ? LOG_FILES.map((name) => ({ file: path.join(logDirectory, name), kind: "log" })) : []),
    ...crashReportEntries(reportDirectories, { fsImpl })
      .map((entry) => ({ ...entry, kind: "crash-report" })),
  ];
  const files = [];
  let remaining = totalCapBytes;
  for (const candidate of candidates) {
    const title = `${candidate.kind === "log" ? "Log" : "Crash report"}: ${candidate.file}`;
    if (remaining <= 0) {
      parts.push(header(title), "[omitted: the report reached its 40 MiB total size cap]\n");
      files.push({ file: candidate.file, bytes: 0, truncated: true, omitted: true });
      continue;
    }
    let content;
    try {
      content = readCapped(candidate.file, Math.min(fileCapBytes, remaining), fsImpl);
    } catch {
      parts.push(header(title), "[unavailable]\n");
      files.push({ file: candidate.file, bytes: 0, truncated: false, omitted: true });
      continue;
    }
    remaining -= content.bytes;
    parts.push(header(title), content.text.endsWith("\n") || !content.text ? content.text : `${content.text}\n`);
    if (content.truncated) parts.push("[truncated: only the first part of this file is included]\n");
    files.push({ file: candidate.file, bytes: content.bytes, truncated: content.truncated, omitted: false });
  }
  return { text: parts.join(""), files, fileName: reportFileName(generatedAt) };
}

module.exports = {
  FILE_CAP_BYTES,
  MAX_CRASH_REPORTS,
  PRIVACY_NOTICE,
  TOTAL_CAP_BYTES,
  buildDiagnosticsReport,
  crashReportEntries,
  reportFileName,
};
