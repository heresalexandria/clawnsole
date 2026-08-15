import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

test("stores uncapped compact history in one owner-only local file", async () => {
  const tempDirectory = await mkdtemp(path.join(tmpdir(), "clawnsole-test-"));
  const dataFile = path.join(tempDirectory, "nested", "clawnsole.json");
  process.env.CLAWNSOLE_DATA_FILE = dataFile;

  try {
    const store = await import(`../lib/server/data-store.ts?test=${Date.now()}`);
    await store.setBflApiKey("bfl_local-test-secret");

    for (let index = 0; index < 55; index += 1) {
      const createdAt = new Date(Date.now() - index * 1000).toISOString();
      await store.upsertGeneration({
        localId: `generation-${index}`,
        provider: "bfl",
        model: "flux-3-video",
        status: index === 0 ? "Ready" : "Pending",
        prompt: `A compact prompt ${index}`,
        mode: "t2v",
        config: {
          aspectRatio: "16:9",
          duration: 8,
          resolution: "hd",
          generateAudio: true,
          safetyTolerance: 2,
          draft: false,
        },
        createdAt,
        updatedAt: createdAt,
        ...(index === 0
          ? {
              estimatedCreditsMin: 136,
              estimatedCreditsMax: 136,
              estimateBasis: "bfl-rate",
              creditsBefore: 500,
              creditsAfter: 364,
              cost: 136,
              resultUrl: "https://delivery.bfl.ai/video.mp4",
              deliveryExpiresAt: new Date(Date.now() - 1000).toISOString(),
            }
          : {}),
      });
    }

    const publicState = await store.toPublicLocalState();
    assert.equal(publicState.generations.length, 55);
    assert.equal(publicState.storage.records, 55);
    assert.equal(publicState.hasBflApiKey, true);
    assert.equal("apiKeys" in publicState, false);
    assert.equal(publicState.generations.at(-1)?.localId, "generation-0");
    assert.equal(publicState.generations.at(-1)?.resultUrl, undefined);
    assert.equal(publicState.generations.at(-1)?.deliveryExpired, true);
    assert.equal(publicState.generations.at(-1)?.cost, 136);
    assert.equal(publicState.generations.at(-1)?.creditsBefore, 500);
    assert.equal(publicState.generations.at(-1)?.creditsAfter, 364);

    const raw = await readFile(dataFile, "utf8");
    assert.match(raw, /bfl_local-test-secret/);
    assert.doesNotMatch(JSON.stringify(publicState), /bfl_local-test-secret/);
    assert.equal((await stat(dataFile)).mode & 0o777, 0o600);
  } finally {
    await rm(tempDirectory, { recursive: true, force: true });
    delete process.env.CLAWNSOLE_DATA_FILE;
  }
});

test("keeps browser storage and media payloads out of persistence", async () => {
  const [app, store, readme, packageJson] = await Promise.all([
    readFile(new URL("../app/clawnsole-app.tsx", import.meta.url), "utf8"),
    readFile(new URL("../lib/server/data-store.ts", import.meta.url), "utf8"),
    readFile(new URL("../README.md", import.meta.url), "utf8"),
    readFile(new URL("../package.json", import.meta.url), "utf8"),
  ]);

  assert.doesNotMatch(`${app}\n${store}`, /localStorage|sessionStorage|indexedDB|HISTORY_LIMIT|HISTORY_BUDGET/);
  assert.match(app, /record: \{ localId, prompt, mode: form\.mode, config, createdAt: now \}/);
  assert.doesNotMatch(store, /slice\(0,\s*40\)|220_000/);
  assert.match(readme, /\.clawnsole\/clawnsole\.json/);

  const scripts = JSON.parse(packageJson).scripts;
  assert.equal(scripts.dev, "next dev");
  assert.equal(scripts.start, "next start");
});

test("estimates FLUX 3 video spend from BFL's published rate card", async () => {
  const { creditsToUsd, estimateGenerationCredits } = await import("../lib/providers/pricing.ts");
  const baseConfig = {
    aspectRatio: "16:9",
    duration: 8,
    resolution: "hd",
    generateAudio: true,
    safetyTolerance: 2,
    draft: false,
  };

  assert.deepEqual(
    estimateGenerationCredits("bfl", { mode: "t2v", config: baseConfig }),
    { minimum: 136, maximum: 136, basis: "bfl-rate" },
  );
  assert.deepEqual(
    estimateGenerationCredits("bfl", { mode: "i2v", config: { ...baseConfig, resolution: "fhd" } }),
    { minimum: 232, maximum: 232, basis: "bfl-rate" },
  );
  assert.deepEqual(
    estimateGenerationCredits("bfl", { mode: "v2v", config: { ...baseConfig, duration: 5 } }),
    { minimum: 205, maximum: 205, basis: "bfl-rate" },
  );
  assert.deepEqual(
    estimateGenerationCredits("bfl", { mode: "v2v", config: { ...baseConfig, duration: "auto", resolution: "fhd" } }),
    { minimum: 265, maximum: 1060, basis: "bfl-rate" },
  );
  assert.deepEqual(
    estimateGenerationCredits("bfl", { mode: "t2v", config: { ...baseConfig, duration: 10, draft: true } }),
    { minimum: 60, maximum: 60, basis: "bfl-rate" },
  );
  assert.equal(creditsToUsd("bfl", 136), 1.36);
});

test("reconciles estimates with exact provider charges in local history", async () => {
  const { estimateGenerationCredits } = await import("../lib/providers/pricing.ts");
  const config = {
    aspectRatio: "16:9",
    duration: 8,
    resolution: "hd",
    generateAudio: true,
    safetyTolerance: 2,
    draft: false,
  };
  const history = [{
    localId: "priced-generation",
    provider: "bfl",
    model: "flux-3-video",
    status: "Ready",
    prompt: "A priced generation",
    mode: "t2v",
    config,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    cost: 130,
  }];

  assert.deepEqual(
    estimateGenerationCredits("bfl", { mode: "t2v", config }, history),
    { minimum: 130, maximum: 130, basis: "provider-history" },
  );
});
