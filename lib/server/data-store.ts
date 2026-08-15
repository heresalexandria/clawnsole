import { mkdir, readFile, rename, stat, unlink, writeFile } from "node:fs/promises";
import path from "node:path";
import type {
  LocalPreferences,
  PublicLocalState,
  StoredGeneration,
} from "../generations";
import {
  clearLocalAssets,
  localAssetStats,
  pruneLocalAssets,
} from "./asset-store.ts";

interface LocalDataFile {
  schemaVersion: 2;
  apiKeys: { bfl?: string };
  preferences: LocalPreferences;
  generations: StoredGeneration[];
}

const DEFAULT_PREFERENCES: LocalPreferences = {
  activeSection: "create",
  libraryFilter: "all",
};

const DEFAULT_DATA: LocalDataFile = {
  schemaVersion: 2,
  apiKeys: {},
  preferences: DEFAULT_PREFERENCES,
  generations: [],
};

const configuredDataFile = process.env.CLAWNSOLE_DATA_FILE;
export const LOCAL_DATA_FILE = configuredDataFile
  ? path.resolve(/*turbopackIgnore: true*/ configuredDataFile)
  : path.join(process.cwd(), ".clawnsole", "clawnsole.json");

let mutationQueue: Promise<unknown> = Promise.resolve();

function cleanData(value: unknown): LocalDataFile {
  if (typeof value !== "object" || value === null) return structuredClone(DEFAULT_DATA);
  const data = value as Partial<LocalDataFile>;
  return {
    schemaVersion: 2,
    apiKeys: typeof data.apiKeys === "object" && data.apiKeys !== null
      ? { bfl: typeof data.apiKeys.bfl === "string" ? data.apiKeys.bfl : undefined }
      : {},
    preferences: {
      activeSection: data.preferences?.activeSection === "library"
        || data.preferences?.activeSection === "settings"
        ? data.preferences.activeSection
        : "create",
      libraryFilter: data.preferences?.libraryFilter === "working"
        || data.preferences?.libraryFilter === "ready"
        || data.preferences?.libraryFilter === "failed"
        ? data.preferences.libraryFilter
        : "all",
    },
    generations: Array.isArray(data.generations) ? data.generations : [],
  };
}

function expireDeliveryUrls(data: LocalDataFile) {
  const now = Date.now();
  let changed = false;
  const generations = data.generations.map((item) => {
    if (!item.deliveryExpiresAt || new Date(item.deliveryExpiresAt).getTime() > now) return item;
    if (!item.resultUrl && !item.draftCacheUrl) return item;
    changed = true;
    return {
      ...item,
      resultUrl: undefined,
      draftCacheUrl: undefined,
      deliveryExpired: Boolean(!item.resultAsset || item.draftCacheUrl),
    };
  });
  return { data: changed ? { ...data, generations } : data, changed };
}

async function readRawData() {
  try {
    const raw = await readFile(LOCAL_DATA_FILE, "utf8");
    return cleanData(JSON.parse(raw));
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return structuredClone(DEFAULT_DATA);
    if (error instanceof SyntaxError) {
      throw new Error(`Clawnsole could not read ${LOCAL_DATA_FILE}. The JSON file is malformed.`);
    }
    throw error;
  }
}

async function writeRawData(data: LocalDataFile) {
  await mkdir(path.dirname(LOCAL_DATA_FILE), { recursive: true });
  const tempPath = `${LOCAL_DATA_FILE}.${process.pid}.${Date.now()}.tmp`;
  await writeFile(tempPath, `${JSON.stringify(data, null, 2)}\n`, { encoding: "utf8", mode: 0o600 });
  await rename(tempPath, LOCAL_DATA_FILE);
}

async function mutate<T>(mutator: (data: LocalDataFile) => T | Promise<T>) {
  const task = mutationQueue.then(async () => {
    const data = await readRawData();
    const result = await mutator(data);
    await writeRawData(data);
    return result;
  });
  mutationQueue = task.catch(() => undefined);
  return task;
}

export async function readLocalData() {
  const { data, changed } = expireDeliveryUrls(await readRawData());
  if (!changed) return data;
  return mutate((current) => {
    const expired = expireDeliveryUrls(current).data;
    current.generations = expired.generations;
    return structuredClone(current);
  });
}

export async function getBflApiKey() {
  return (await readRawData()).apiKeys.bfl?.trim() || "";
}

export async function setBflApiKey(value: string) {
  return mutate((data) => {
    const clean = value.trim();
    if (clean.length > 2_000) throw new Error("The BFL API key is unexpectedly long.");
    if (clean) data.apiKeys.bfl = clean;
    else delete data.apiKeys.bfl;
  });
}

export async function setPreferences(preferences: Partial<LocalPreferences>) {
  return mutate((data) => {
    if (preferences.activeSection === "create"
      || preferences.activeSection === "library"
      || preferences.activeSection === "settings") {
      data.preferences.activeSection = preferences.activeSection;
    }
    if (preferences.libraryFilter === "all"
      || preferences.libraryFilter === "working"
      || preferences.libraryFilter === "ready"
      || preferences.libraryFilter === "failed") {
      data.preferences.libraryFilter = preferences.libraryFilter;
    }
  });
}

export async function upsertGeneration(generation: StoredGeneration) {
  return mutate((data) => {
    const index = data.generations.findIndex((item) => item.localId === generation.localId);
    if (index >= 0) data.generations[index] = generation;
    else data.generations.unshift(generation);
    return generation;
  });
}

export async function updateGeneration(
  localId: string,
  updater: (generation: StoredGeneration) => StoredGeneration,
) {
  return mutate((data) => {
    const index = data.generations.findIndex((item) => item.localId === localId);
    if (index < 0) return null;
    const generation = updater(data.generations[index]);
    data.generations[index] = generation;
    return generation;
  });
}

export async function deleteGeneration(localId: string) {
  const generations = await mutate((data) => {
    data.generations = data.generations.filter((item) => item.localId !== localId);
    return structuredClone(data.generations);
  });
  await pruneLocalAssets(generations);
}

export async function clearGenerationHistory() {
  await mutate((data) => {
    data.generations = [];
  });
  await clearLocalAssets();
}

export async function resetPreferences() {
  return mutate((data) => {
    data.preferences = { ...DEFAULT_PREFERENCES };
  });
}

export async function deleteLocalDataFile() {
  const task = mutationQueue.then(async () => {
    try {
      await unlink(LOCAL_DATA_FILE);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
    }
    await clearLocalAssets();
  });
  mutationQueue = task.catch(() => undefined);
  return task;
}

export async function toPublicLocalState(input?: LocalDataFile): Promise<PublicLocalState> {
  const data = input ?? await readLocalData();
  let fileStats: { size: number; mtime: Date } | null = null;
  try {
    const current = await stat(LOCAL_DATA_FILE);
    fileStats = { size: current.size, mtime: current.mtime };
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
  }
  const assetStats = await localAssetStats();
  return {
    generations: data.generations,
    preferences: data.preferences,
    hasBflApiKey: Boolean(data.apiKeys.bfl),
    storage: {
      path: LOCAL_DATA_FILE,
      bytes: fileStats?.size ?? 0,
      assetBytes: assetStats.bytes,
      assets: assetStats.assets,
      records: data.generations.length,
      lastUpdated: fileStats?.mtime.toISOString() ?? null,
    },
  };
}
