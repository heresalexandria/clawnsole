#!/usr/bin/env node

import { access, cp, mkdir, rename, rm } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const electronDirectory = path.resolve(scriptDirectory, "..");
const repositoryRoot = path.resolve(electronDirectory, "..");
const standaloneSource = path.join(repositoryRoot, ".next", "standalone");
const staticSource = path.join(repositoryRoot, ".next", "static");
const publicSource = path.join(repositoryRoot, "public");
const destination = path.join(electronDirectory, "dist", "renderer");

await access(path.join(standaloneSource, "server.js")).catch(() => {
  throw new Error("Missing .next/standalone/server.js. Run `npm run build` first.");
});

if (!destination.startsWith(`${electronDirectory}${path.sep}`)) {
  throw new Error("Refusing to prepare a renderer outside the Electron directory.");
}

await rm(destination, { recursive: true, force: true });
await mkdir(destination, { recursive: true });
await cp(standaloneSource, destination, { recursive: true });
// Next's output tracer can include the current local data file because the server
// reads it. Packaged apps must always begin with their own Application Support file.
await rm(path.join(destination, ".clawnsole"), { recursive: true, force: true });

// electron-builder excludes directories named node_modules from extraResources.
// NODE_PATH points the bundled Node runtime at this equivalent traced dependency tree.
await rename(
  path.join(destination, "node_modules"),
  path.join(destination, "vendor_modules"),
);
await cp(publicSource, path.join(destination, "public"), { recursive: true });
await mkdir(path.join(destination, ".next"), { recursive: true });
await cp(staticSource, path.join(destination, ".next", "static"), { recursive: true });

console.log(`Prepared the standalone renderer at ${destination}.`);
