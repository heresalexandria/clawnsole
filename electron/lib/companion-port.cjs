"use strict";

const fs = require("node:fs");
const path = require("node:path");

const PORT_FILE = "companion-port.json";

function validPort(value) {
  return Number.isInteger(value) && value > 0 && value < 65_536 ? value : null;
}

// The port the packaged companion bound last time. Keeping the loopback
// origin stable across launches lets Chromium reuse its per-origin HTTP cache
// for the media the companion marks cacheable, instead of writing a fresh
// copy under a new origin on every start (the bundle itself is served
// no-store). A missing, unreadable or malformed file simply means a random
// port, exactly as before.
function readPreferredPort(userData, { fsImpl = fs } = {}) {
  try {
    const parsed = JSON.parse(fsImpl.readFileSync(path.join(userData, PORT_FILE), "utf8"));
    return validPort(parsed?.port);
  } catch {
    return null;
  }
}

function rememberPort(userData, port, { fsImpl = fs } = {}) {
  const valid = validPort(port);
  if (valid === null) return false;
  try {
    if (readPreferredPort(userData, { fsImpl }) === valid) return true;
    fsImpl.mkdirSync(userData, { recursive: true });
    fsImpl.writeFileSync(path.join(userData, PORT_FILE), `${JSON.stringify({ port: valid })}\n`);
    return true;
  } catch {
    return false;
  }
}

function portOfUrl(url) {
  try {
    return validPort(Number(new URL(url).port));
  } catch {
    return null;
  }
}

module.exports = { PORT_FILE, portOfUrl, readPreferredPort, rememberPort };
