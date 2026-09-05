"use strict";

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

// Run before the single-instance lock or any session/credential/data reads.
// Every smoke invocation gets its own empty profile, even beside a live app.
function configureSmokeProfile(app, { smoke, temporaryDirectory = os.tmpdir() }) {
  if (!smoke) return null;
  const root = fs.mkdtempSync(path.join(temporaryDirectory, "clawnsole-smoke-"));
  const locations = {
    userData: path.join(root, "profile"),
    sessionData: path.join(root, "session"),
    logs: path.join(root, "logs"),
  };
  for (const [name, directory] of Object.entries(locations)) {
    fs.mkdirSync(directory);
    app.setPath(name, directory);
  }
  return root;
}

module.exports = { configureSmokeProfile };
