"use strict";

const fs = require("node:fs");
const path = require("node:path");

const LOG_FILE = "companion.log";
const PREVIOUS_LOG_FILE = "companion.log.1";
const MAX_LOG_BYTES = 5 * 1024 * 1024;

// Captures the bundled companion's stdout and stderr in a size-capped file
// under the app's log directory. When the current file would grow past the
// cap it becomes companion.log.1, replacing the previous one, and a fresh
// companion.log starts, so support only ever needs the two newest files.
class CompanionLog {
  #descriptor = null;
  #size = 0;
  #disabled = false;

  constructor({
    directory,
    maxBytes = MAX_LOG_BYTES,
    now = () => new Date(),
    echo = null,
  }) {
    if (typeof directory !== "string" || !directory.trim()) {
      throw new TypeError("A log directory is required.");
    }
    this.directory = directory;
    this.file = path.join(directory, LOG_FILE);
    this.previousFile = path.join(directory, PREVIOUS_LOG_FILE);
    this.maxBytes = maxBytes;
    this.now = now;
    this.echo = typeof echo === "function" ? echo : null;
  }

  attach(stream, label) {
    if (!stream) return;
    stream.setEncoding("utf8");
    stream.on("data", (chunk) => this.write(label, chunk));
    stream.on("error", () => this.write("shell", "companion-output-stream-error"));
  }

  write(label, text) {
    try {
      const stamp = this.now().toISOString();
      for (const line of String(text ?? "").trimEnd().split("\n")) {
        if (!line) continue;
        let entry = Buffer.from(`${stamp} [${label}] ${line}\n`);
        // An unusually long native error must not bypass rotation's cap.
        const limit = Math.min(this.maxBytes, 64 * 1024);
        if (entry.length > limit) {
          const suffix = Buffer.from("... [truncated]\n");
          entry = limit > suffix.length
            ? Buffer.concat([entry.subarray(0, limit - suffix.length), suffix])
            : entry.subarray(0, limit);
        }
        try { this.echo?.(entry.toString("utf8")); } catch { /* Terminal may be closed. */ }
        this.#append(entry);
      }
    } catch {
      this.#disabled = true;
      this.close();
    }
  }

  close() {
    if (this.#descriptor === null) return;
    try {
      fs.closeSync(this.#descriptor);
    } catch {
      // The descriptor is gone either way.
    }
    this.#descriptor = null;
  }

  #append(entry) {
    if (this.#disabled) return;
    try {
      const bytes = Buffer.byteLength(entry, "utf8");
      if (this.#descriptor === null) this.#open();
      if (this.#size > 0 && this.#size + bytes > this.maxBytes) this.#rotate();
      fs.writeSync(this.#descriptor, entry);
      this.#size += bytes;
    } catch {
      // A log that cannot be written must never take the shell down with it.
      this.#disabled = true;
      this.close();
      // Do not fall back to another potentially closed output stream here.
    }
  }

  #open() {
    fs.mkdirSync(this.directory, { recursive: true });
    this.#descriptor = fs.openSync(this.file, "a");
    this.#size = fs.fstatSync(this.#descriptor).size;
  }

  #rotate() {
    this.close();
    fs.renameSync(this.file, this.previousFile);
    this.#open();
  }
}

module.exports = {
  CompanionLog,
  LOG_FILE,
  MAX_LOG_BYTES,
  PREVIOUS_LOG_FILE,
};
