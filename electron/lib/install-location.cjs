"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const INSTALL_LOCATION_FILE = "install-location.json";
const INSTALL_LOCATION_HELP =
  "Move Clawnsole to your Applications folder, then check for updates again.";
const LOCATION_ERROR_CODES = new Set(["EACCES", "EPERM", "EROFS"]);

// Gatekeeper runs a quarantined app from a read-only, randomized path. Such
// a bundle can never be replaced in place, no matter its permissions.
function isTranslocated(bundlePath) {
  return /\/AppTranslocation\//.test(String(bundlePath || ""));
}

// Turns the raw filesystem failures of an in-place update into the one
// action that fixes all of them. Other errors keep their own message.
function describeInstallFailure(error, bundlePath = "") {
  const code = error && typeof error === "object" ? error.code : null;
  if (LOCATION_ERROR_CODES.has(code) || isTranslocated(bundlePath)) {
    return INSTALL_LOCATION_HELP;
  }
  return error instanceof Error ? error.message : String(error);
}

function installLocationFile(userData) {
  return path.join(userData, INSTALL_LOCATION_FILE);
}

function applicationsMoveDeclined(userData) {
  try {
    const parsed = JSON.parse(
      fs.readFileSync(installLocationFile(userData), "utf8"),
    );
    return typeof parsed?.applicationsMoveDeclinedAt === "string";
  } catch {
    return false;
  }
}

function rememberApplicationsMoveDeclined(userData, now = () => new Date()) {
  fs.mkdirSync(userData, { recursive: true });
  const file = installLocationFile(userData);
  const temporary = `${file}.${process.pid}.${crypto.randomUUID()}.tmp`;
  try {
    fs.writeFileSync(
      temporary,
      `${JSON.stringify({ applicationsMoveDeclinedAt: now().toISOString() })}\n`,
      { encoding: "utf8", flag: "wx", flush: true },
    );
    fs.renameSync(temporary, file);
  } finally {
    fs.rmSync(temporary, { force: true });
  }
}

module.exports = {
  INSTALL_LOCATION_FILE,
  INSTALL_LOCATION_HELP,
  applicationsMoveDeclined,
  describeInstallFailure,
  isTranslocated,
  rememberApplicationsMoveDeclined,
};
