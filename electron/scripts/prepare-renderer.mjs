#!/usr/bin/env node

import { access, chmod, cp, mkdir, rm } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const electronDirectory = path.resolve(scriptDirectory, "..");
const repositoryRoot = path.resolve(electronDirectory, "..");
const flutterBuild = path.join(repositoryRoot, "flutter", "build");
const webSource = path.join(flutterBuild, "web");
const companionSource = path.join(flutterBuild, "clawnsole_companion");
const appleLocalSource = path.join(
  repositoryRoot,
  "apple_local",
  "build",
  "Clawnsole Apple Local.app",
);
const destination = path.join(electronDirectory, "dist", "renderer");
const companionDestination = path.join(electronDirectory, "dist", "companion");

await access(path.join(webSource, "index.html")).catch(() => {
  throw new Error("Missing Flutter web output. Run `flutter/scripts/build_web` first.");
});
await access(companionSource).catch(() => {
  throw new Error("Missing compiled companion. Run `flutter/scripts/build_web` first.");
});

if (!destination.startsWith(`${electronDirectory}${path.sep}`)) {
  throw new Error("Refusing to prepare a renderer outside the Electron directory.");
}

await rm(destination, { recursive: true, force: true });
await rm(companionDestination, { recursive: true, force: true });
await cp(webSource, destination, { recursive: true });
await mkdir(companionDestination, { recursive: true });
const companionExecutable = path.join(companionDestination, "clawnsole_companion");
await cp(companionSource, companionExecutable);
await chmod(companionExecutable, 0o755);
try {
  if (process.env.CLAWNSOLE_INCLUDE_APPLE_LOCAL === "false") {
    throw new Error("Apple Local was disabled for this build architecture.");
  }
  await access(appleLocalSource);
  const appleLocalApplication = path.join(
    companionDestination,
    "Clawnsole Apple Local.app",
  );
  await cp(appleLocalSource, appleLocalApplication, { recursive: true });
  await chmod(
    path.join(
      appleLocalApplication,
      "Contents",
      "MacOS",
      "clawnsole_apple_generator",
    ),
    0o755,
  );
  console.log(`Prepared the Apple Local helper at ${appleLocalApplication}.`);
} catch {
  console.log("Apple Local helper is unavailable for this build architecture.");
}

console.log(`Prepared the Flutter renderer at ${destination}.`);
console.log(`Prepared the local companion at ${companionExecutable}.`);
