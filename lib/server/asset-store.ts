import { randomUUID } from "node:crypto";
import { createReadStream, createWriteStream } from "node:fs";
import {
  access,
  mkdir,
  readdir,
  rename,
  rm,
  stat,
  unlink,
  writeFile,
} from "node:fs/promises";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";
import path from "node:path";
import type {
  StoredAssetReference,
  StoredGeneration,
  StoredGenerationConfig,
} from "../generations";
import type { Flux3VideoInput } from "../providers/contracts";

const configuredAssetDirectory = process.env.CLAWNSOLE_ASSET_DIR;
const configuredDataFile = process.env.CLAWNSOLE_DATA_FILE;
const dataFile = configuredDataFile
  ? path.resolve(/*turbopackIgnore: true*/ configuredDataFile)
  : path.join(process.cwd(), ".clawnsole", "clawnsole.json");

export const LOCAL_ASSET_DIRECTORY = configuredAssetDirectory
  ? path.resolve(/*turbopackIgnore: true*/ configuredAssetDirectory)
  : path.join(path.dirname(dataFile), "assets");

const ASSET_ID = /^[a-f0-9-]{36}$/;
const MAX_REMOTE_BYTES = 4 * 1024 * 1024 * 1024;

function assetPath(id: string) {
  if (!ASSET_ID.test(id)) throw new Error("The local asset id is invalid.");
  return path.join(LOCAL_ASSET_DIRECTORY, `${id}.asset`);
}

function cleanLabel(value: string) {
  return value.slice(0, 240) || "Clawnsole asset";
}

function cleanContentType(value: string | undefined, fallback = "application/octet-stream") {
  const candidate = value?.split(";")[0].trim().toLowerCase();
  return candidate && /^[a-z0-9.+-]+\/[a-z0-9.+-]+$/.test(candidate)
    ? candidate
    : fallback;
}

function decodeDataUrl(source: string) {
  if (!source.startsWith("data:")) return null;
  const separator = source.indexOf(",");
  if (separator < 0) throw new Error("A selected local asset is malformed.");
  const metadata = source.slice(5, separator);
  const encoded = source.slice(separator + 1);
  const pieces = metadata.split(";");
  const contentType = cleanContentType(pieces[0]);
  const bytes = pieces.includes("base64")
    ? Buffer.from(encoded, "base64")
    : Buffer.from(decodeURIComponent(encoded));
  return { bytes, contentType };
}

async function existingLocalReference(
  reference: StoredAssetReference | undefined,
  label: string,
) {
  if (reference?.kind !== "local" || !ASSET_ID.test(reference.value)) return null;
  try {
    const file = await stat(assetPath(reference.value));
    return {
      kind: "local" as const,
      value: reference.value,
      label: cleanLabel(label || reference.label),
      contentType: cleanContentType(reference.contentType),
      bytes: file.size,
    };
  } catch {
    return null;
  }
}

async function storeBuffer(bytes: Buffer, label: string, contentType: string) {
  const id = randomUUID();
  await mkdir(LOCAL_ASSET_DIRECTORY, { recursive: true, mode: 0o700 });
  await writeFile(assetPath(id), bytes, { mode: 0o600, flag: "wx" });
  return {
    kind: "local" as const,
    value: id,
    label: cleanLabel(label),
    contentType: cleanContentType(contentType),
    bytes: bytes.byteLength,
  };
}

async function persistInputSource(
  source: string,
  label: string,
  retained?: StoredAssetReference,
): Promise<StoredAssetReference | undefined> {
  const existing = await existingLocalReference(retained, label);
  if (existing) return existing;

  const local = decodeDataUrl(source);
  if (local) return storeBuffer(local.bytes, label, local.contentType);

  try {
    const remote = new URL(source);
    if (remote.protocol !== "https:") return undefined;
    return {
      kind: "remote",
      value: remote.toString().slice(0, 8_000),
      label: cleanLabel(label),
    };
  } catch {
    return undefined;
  }
}

function keyframeSource(value: unknown) {
  if (typeof value === "string") return value;
  if (Array.isArray(value) && typeof value[1] === "string") return value[1];
  return "";
}

export async function persistGenerationInputs(
  input: Flux3VideoInput,
  config: StoredGenerationConfig,
): Promise<StoredGenerationConfig> {
  if (input.mode === "i2v") {
    const keyframes = await Promise.all((config.keyframes ?? []).map(async (frame, index) => ({
      ...frame,
      source: await persistInputSource(
        keyframeSource(input.keyframes[index]),
        frame.label,
        frame.source,
      ),
    })));
    return { ...config, keyframes };
  }

  if (input.mode === "v2v") {
    return {
      ...config,
      source: await persistInputSource(
        input.start_video,
        config.sourceLabel || "Starting video",
        config.source,
      ),
    };
  }

  if (input.mode === "draft_enhance") {
    return {
      ...config,
      source: await persistInputSource(
        input.draft_cache,
        config.sourceLabel || "FLUX 3 draft cache",
        config.source,
      ),
    };
  }

  return config;
}

export async function storeRemoteResult(source: string, label: string) {
  const url = new URL(source);
  if (url.protocol !== "https:" || (url.hostname !== "bfl.ai" && !url.hostname.endsWith(".bfl.ai"))) {
    throw new Error("The generated video URL is not a trusted BFL delivery URL.");
  }

  const response = await fetch(url, { cache: "no-store" });
  if (!response.ok || !response.body) {
    throw new Error("The generated video could not be copied into local history.");
  }
  const reportedLength = Number(response.headers.get("content-length"));
  if (Number.isFinite(reportedLength) && reportedLength > MAX_REMOTE_BYTES) {
    throw new Error("The generated video is too large for Clawnsole's local asset store.");
  }

  const id = randomUUID();
  await mkdir(LOCAL_ASSET_DIRECTORY, { recursive: true, mode: 0o700 });
  const destination = assetPath(id);
  const temporary = `${destination}.${process.pid}.tmp`;
  try {
    await pipeline(
      Readable.fromWeb(response.body as import("node:stream/web").ReadableStream),
      createWriteStream(temporary, { mode: 0o600, flags: "wx" }),
    );
    const file = await stat(temporary);
    if (file.size > MAX_REMOTE_BYTES) throw new Error("The generated video is too large for local history.");
    await rename(temporary, destination);
    return {
      kind: "local" as const,
      value: id,
      label: cleanLabel(label),
      contentType: cleanContentType(response.headers.get("content-type") ?? undefined, "video/mp4"),
      bytes: file.size,
    };
  } catch (error) {
    await unlink(temporary).catch(() => undefined);
    throw error;
  }
}

export function localAssetIds(generations: StoredGeneration[]) {
  const ids = new Set<string>();
  const add = (reference?: StoredAssetReference) => {
    if (reference?.kind === "local" && ASSET_ID.test(reference.value)) ids.add(reference.value);
  };
  for (const generation of generations) {
    add(generation.resultAsset);
    add(generation.config.source);
    for (const frame of generation.config.keyframes ?? []) add(frame.source);
  }
  return ids;
}

export function findLocalAsset(generations: StoredGeneration[], id: string) {
  if (!ASSET_ID.test(id)) return null;
  const references: StoredAssetReference[] = [];
  for (const generation of generations) {
    if (generation.resultAsset) references.push(generation.resultAsset);
    if (generation.config.source) references.push(generation.config.source);
    for (const frame of generation.config.keyframes ?? []) {
      if (frame.source) references.push(frame.source);
    }
  }
  return references.find((reference) => reference.kind === "local" && reference.value === id) ?? null;
}

export async function openLocalAsset(id: string) {
  const filePath = assetPath(id);
  const file = await stat(filePath);
  return { filePath, file, createReadStream };
}

export async function pruneLocalAssets(generations: StoredGeneration[]) {
  const retained = localAssetIds(generations);
  let files: string[];
  try {
    files = await readdir(LOCAL_ASSET_DIRECTORY);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return;
    throw error;
  }
  await Promise.all(files.map(async (file) => {
    const id = file.endsWith(".asset") ? file.slice(0, -6) : "";
    if (!retained.has(id)) await unlink(path.join(LOCAL_ASSET_DIRECTORY, file)).catch(() => undefined);
  }));
}

export async function clearLocalAssets() {
  await rm(LOCAL_ASSET_DIRECTORY, { recursive: true, force: true });
}

export async function localAssetStats() {
  let files: string[];
  try {
    files = await readdir(LOCAL_ASSET_DIRECTORY);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return { assets: 0, bytes: 0 };
    throw error;
  }
  const sizes = await Promise.all(files.filter((file) => file.endsWith(".asset")).map(async (file) => {
    try {
      return (await stat(path.join(LOCAL_ASSET_DIRECTORY, file))).size;
    } catch {
      return 0;
    }
  }));
  return { assets: sizes.length, bytes: sizes.reduce((total, size) => total + size, 0) };
}

export async function assertLocalAssetExists(reference: StoredAssetReference) {
  if (reference.kind !== "local") return;
  await access(assetPath(reference.value));
}
