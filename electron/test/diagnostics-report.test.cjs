"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");
const {
  MAX_CRASH_REPORTS,
  PRIVACY_NOTICE,
  buildDiagnosticsReport,
  crashReportEntries,
  reportFileName,
} = require("../lib/diagnostics-report.cjs");

function scratch(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "clawnsole-report-"));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const logs = path.join(root, "logs");
  const reports = path.join(root, "DiagnosticReports");
  const systemReports = path.join(root, "SystemReports");
  const renderer = path.join(root, "renderer");
  for (const directory of [logs, reports, systemReports, renderer]) fs.mkdirSync(directory);
  return { root, logs, reports, systemReports, renderer };
}

const NOW = () => new Date("2026-09-08T12:34:56.789Z");
const section = (title) => `\n==================== ${title} ====================\n`;
const jsonSection = (text, title) => JSON.parse(text.split(section(title))[1].split("\n\n====")[0]);

test("the report bundles logs, matching crash reports, versions and process metrics under headers", (t) => {
  const s = scratch(t);
  fs.writeFileSync(path.join(s.logs, "companion.log"), "2026 [shell] shell-ready\n");
  fs.writeFileSync(path.join(s.logs, "companion.log.1"), "older line");
  fs.writeFileSync(path.join(s.reports, "Clawnsole-2026-09-07-101010.ips"), "{\"crash\":1}\n");
  fs.writeFileSync(path.join(s.reports, "Clawnsole Helper (GPU)_2026-09-07-101011_mac.ips"), "gpu\n");
  fs.writeFileSync(path.join(s.reports, "clawnsole"), "bare\n");
  fs.writeFileSync(path.join(s.reports, "clawnsole.ips"), "must not match\n");
  fs.writeFileSync(path.join(s.reports, "Clawnsoleish-2026.ips"), "must not match\n");
  fs.writeFileSync(path.join(s.reports, "Safari-2026.ips"), "must not match\n");
  fs.writeFileSync(path.join(s.systemReports, "Clawnsole_2026-09-06.crash"), "system\n");
  fs.mkdirSync(path.join(s.reports, "Clawnsole-directory"));
  fs.symlinkSync(path.join(s.reports, "clawnsole"), path.join(s.reports, "Clawnsole-link.ips"));
  fs.writeFileSync(path.join(s.renderer, "version.json"),
    JSON.stringify({ app_name: "clawnsole", version: "0.59.4", build_number: "1", package_name: "clawnsole", secret: "x" }));

  const report = buildDiagnosticsReport({
    now: NOW,
    logDirectory: s.logs,
    reportDirectories: [s.reports, s.systemReports, path.join(s.root, "missing")],
    rendererDirectory: s.renderer,
    versions: { electron: "43.4.0", chrome: "142.0.0.0", node: "22.20.0", v8: "14.2", openssl: "3", uv: "1" },
    platform: "darwin",
    arch: "arm64",
    systemVersion: "26.0",
    appMetrics: () => [{ type: "GPU", pid: 9, name: "secret-helper", cpu: { percentCPUUsage: 1.5 },
      memory: { workingSetSize: 100, peakWorkingSetSize: 120 } }],
  });

  assert.equal(report.fileName, "Clawnsole-Diagnostics-2026-09-08T12-34-56Z.txt");
  assert.match(report.text, /^Clawnsole diagnostics report\nGenerated: 2026-09-08T12:34:56.789Z\n/);
  assert.ok(report.text.includes(PRIVACY_NOTICE));
  const environment = jsonSection(report.text, "Environment");
  assert.deepEqual(environment, {
    platform: "darwin", arch: "arm64", systemVersion: "26.0",
    versions: { electron: "43.4.0", chrome: "142.0.0.0", node: "22.20.0", v8: "14.2" },
    renderer: { app_name: "clawnsole", version: "0.59.4", build_number: "1", package_name: "clawnsole" },
  });
  const processes = jsonSection(report.text, "Process metrics");
  assert.deepEqual(processes, [{ type: "GPU", pid: 9, cpuPercent: 1.5, workingSetKiB: 100, peakWorkingSetKiB: 120 }]);
  assert.doesNotMatch(report.text, /secret|openssl|must not match|Safari|Clawnsoleish/);
  assert.ok(report.text.includes(section(`Log: ${path.join(s.logs, "companion.log")}`) + "2026 [shell] shell-ready\n"));
  assert.ok(report.text.includes(section(`Log: ${path.join(s.logs, "companion.log.1")}`) + "older line\n"));
  assert.ok(report.text.includes(section(`Crash report: ${path.join(s.reports, "Clawnsole-2026-09-07-101010.ips")}`) + "{\"crash\":1}\n"));
  assert.ok(report.text.includes("Clawnsole Helper (GPU)_2026-09-07-101011_mac.ips"));
  assert.ok(report.text.includes(section(`Crash report: ${path.join(s.reports, "clawnsole")}`) + "bare\n"));
  assert.ok(report.text.includes(section(`Crash report: ${path.join(s.systemReports, "Clawnsole_2026-09-06.crash")}`) + "system\n"));
  assert.equal(report.text.includes("Clawnsole-link.ips"), false, "symlinks are not regular files");
  assert.equal(report.text.includes("Clawnsole-directory"), false);
  assert.deepEqual(report.files.map((file) => path.basename(file.file)).slice(0, 2), ["companion.log", "companion.log.1"]);
  assert.equal(report.files.length, 6);
});

test("missing logs, an unreadable renderer version and a broken metrics source do not stop the report", (t) => {
  const s = scratch(t);
  fs.writeFileSync(path.join(s.renderer, "version.json"), "{not json");
  const report = buildDiagnosticsReport({
    now: NOW, logDirectory: s.logs, reportDirectories: [], rendererDirectory: s.renderer,
    versions: null, platform: "darwin", arch: "arm64",
    appMetrics: () => { throw new Error("metrics unavailable"); },
  });
  assert.ok(report.text.includes(section(`Log: ${path.join(s.logs, "companion.log")}`) + "[unavailable]\n"));
  assert.equal(jsonSection(report.text, "Environment").renderer, null);
  assert.deepEqual(jsonSection(report.text, "Process metrics"), []);
  assert.deepEqual(report.files.map((file) => file.omitted), [true, true]);
  const bare = buildDiagnosticsReport({ now: NOW });
  assert.equal(bare.files.length, 0);
  assert.match(bare.text, /Clawnsole diagnostics report/);
});

test("crash reports are the newest twelve regular files and each file and the bundle are capped", (t) => {
  const s = scratch(t);
  for (let index = 0; index < 15; index += 1) {
    const file = path.join(s.reports, `Clawnsole-${String(index).padStart(2, "0")}.ips`);
    fs.writeFileSync(file, `report ${index} `.padEnd(200, "r"));
    fs.utimesSync(file, new Date(index * 1000), new Date(index * 1000));
  }
  const entries = crashReportEntries([s.reports]);
  assert.equal(entries.length, MAX_CRASH_REPORTS);
  assert.equal(path.basename(entries[0].file), "Clawnsole-14.ips");
  assert.equal(path.basename(entries.at(-1).file), "Clawnsole-03.ips");

  fs.writeFileSync(path.join(s.logs, "companion.log"), "x".repeat(300));
  fs.writeFileSync(path.join(s.logs, "companion.log.1"), "y".repeat(300));
  const report = buildDiagnosticsReport({
    now: NOW, logDirectory: s.logs, reportDirectories: [s.reports],
    fileCapBytes: 100, totalCapBytes: 250,
  });
  assert.equal(report.files[0].bytes, 100);
  assert.equal(report.files[0].truncated, true);
  assert.ok(report.text.includes("x".repeat(100) + "\n[truncated: only the first part of this file is included]\n"));
  assert.equal(report.files[1].bytes, 100);
  assert.equal(report.files[2].bytes, 50, "the last file only gets what remains of the total cap");
  assert.equal(report.files[3].omitted, true);
  assert.ok(report.text.includes("[omitted: the report reached its 40 MiB total size cap]"));
  assert.equal(report.files.filter((file) => !file.omitted).length, 3);
});

test("report names carry a UTC stamp that is safe for macOS file names", () => {
  assert.equal(reportFileName(new Date("2026-01-02T03:04:05.006Z")), "Clawnsole-Diagnostics-2026-01-02T03-04-05Z.txt");
  assert.doesNotMatch(reportFileName(new Date()), /[:/\\]/);
});
