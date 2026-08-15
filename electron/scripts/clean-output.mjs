#!/usr/bin/env node

import { rm } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const electronDirectory = path.resolve(scriptDirectory, "..");
const releaseDirectory = path.join(electronDirectory, "dist", "release");
if (!releaseDirectory.startsWith(`${electronDirectory}${path.sep}`)) {
  throw new Error("Refusing to clean output outside the Electron directory.");
}
await rm(releaseDirectory, { recursive: true, force: true });
