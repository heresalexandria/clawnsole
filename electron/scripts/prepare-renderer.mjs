#!/usr/bin/env node

import { access, chmod, cp, mkdir, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const electronDirectory = path.resolve(scriptDirectory, "..");
const repositoryRoot = path.resolve(electronDirectory, "..");
const flutterBuild = path.join(repositoryRoot, "flutter", "build");
const webSource = path.join(flutterBuild, "web");
const companionSource = path.join(flutterBuild, "clawnsole_companion");
const destination = path.join(electronDirectory, "dist", "renderer");
const companionDestination = path.join(electronDirectory, "dist", "companion");
const configDestination = path.join(electronDirectory, "dist", "config");

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
await rm(configDestination, { recursive: true, force: true });
await cp(webSource, destination, { recursive: true });
await mkdir(companionDestination, { recursive: true });
const companionExecutable = path.join(companionDestination, "clawnsole_companion");
await cp(companionSource, companionExecutable);
await chmod(companionExecutable, 0o755);
await mkdir(configDestination, { recursive: true });
await writeFile(
  path.join(configDestination, "google-oauth.json"),
  `${JSON.stringify({
    googleOAuthClientId: process.env.CLAWNSOLE_GOOGLE_DESKTOP_CLIENT_ID || "",
    googleOAuthClientSecret: process.env.CLAWNSOLE_GOOGLE_DESKTOP_CLIENT_SECRET || "",
  })}\n`,
  { encoding: "utf8", mode: 0o600 },
);

console.log(`Prepared the Flutter renderer at ${destination}.`);
console.log(`Prepared the local companion at ${companionExecutable}.`);
console.log("Prepared optional desktop Google OAuth configuration.");
