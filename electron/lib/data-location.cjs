"use strict";

const fs = require("node:fs");
const path = require("node:path");

// The companion reads --data-file once at startup, so the shell owns the
// pointer file that records a user-chosen data directory and relaunches the
// app after a move. Product semantics stay in the Flutter companion.
const DATA_LOCATION_FILE = "data-location.json";
const DATA_FILE = "clawnsole.json";
const SECURE_FILE = "clawnsole.json.secure";
const ASSETS_DIRECTORY = "assets";

// Only an existing directory is honored, so an unplugged portable drive
// falls back to the default location instead of failing startup.
function storedDataDirectory(userData) {
  try {
    const source = fs.readFileSync(
      path.join(userData, DATA_LOCATION_FILE),
      "utf8",
    );
    const parsed = JSON.parse(source);
    const directory = typeof parsed?.dataDirectory === "string"
      ? parsed.dataDirectory.trim()
      : "";
    if (directory && fs.statSync(directory).isDirectory()) return directory;
  } catch {
    // An unreadable pointer must never block startup.
  }
  return null;
}

function dataDirectory(userData) {
  return storedDataDirectory(userData) || userData;
}

function dataFile(userData) {
  return path.join(dataDirectory(userData), DATA_FILE);
}

function rememberDataDirectory(userData, directory) {
  fs.mkdirSync(userData, { recursive: true });
  fs.writeFileSync(
    path.join(userData, DATA_LOCATION_FILE),
    `${JSON.stringify({ dataDirectory: directory })}\n`,
  );
}

// Validates a picked target before anything is copied. Returns
// { ok, error?, hasExistingLibrary? }.
function inspectRelocationTarget(currentDirectory, targetDirectory) {
  const current = path.resolve(currentDirectory);
  const target = path.resolve(targetDirectory);
  if (target === current) {
    return {
      ok: false,
      error: "Clawnsole already stores its data in that folder.",
    };
  }
  const assets = path.join(current, ASSETS_DIRECTORY);
  if (target === assets || target.startsWith(assets + path.sep)) {
    return {
      ok: false,
      error: "Choose a folder outside the current assets folder.",
    };
  }
  return {
    ok: true,
    hasExistingLibrary: fs.existsSync(path.join(target, DATA_FILE)),
  };
}

// Copies the data file, the encrypted key sibling, and the assets folder.
// The previous copy intentionally stays in place as a safety net.
function copyLibrary(currentDirectory, targetDirectory) {
  fs.mkdirSync(targetDirectory, { recursive: true });
  for (const name of [DATA_FILE, SECURE_FILE]) {
    const source = path.join(currentDirectory, name);
    if (fs.existsSync(source)) {
      fs.copyFileSync(source, path.join(targetDirectory, name));
    }
  }
  const assets = path.join(currentDirectory, ASSETS_DIRECTORY);
  if (fs.existsSync(assets)) {
    fs.cpSync(assets, path.join(targetDirectory, ASSETS_DIRECTORY), {
      recursive: true,
    });
  }
}

module.exports = {
  DATA_LOCATION_FILE,
  copyLibrary,
  dataDirectory,
  dataFile,
  inspectRelocationTarget,
  rememberDataDirectory,
  storedDataDirectory,
};
