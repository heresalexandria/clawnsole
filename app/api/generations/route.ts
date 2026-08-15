import type { StoredGeneration, StoredGenerationConfig } from "../../../lib/generations";
import type {
  AsyncGenerationResponse,
  ProviderId,
  SubmitGenerationRequest,
  VideoMode,
} from "../../../lib/providers/contracts";
import { estimateGenerationCredits } from "../../../lib/providers/pricing";
import { persistGenerationInputs } from "../../../lib/server/asset-store";
import { getBflApiKey, readLocalData, upsertGeneration } from "../../../lib/server/data-store";
import { getServerProvider } from "../../../lib/server/providers";
import { ProviderRequestError } from "../../../lib/server/providers/errors";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

interface SubmitRecord {
  localId: string;
  prompt: string;
  mode: VideoMode;
  config: StoredGenerationConfig;
  createdAt: string;
}

function shortText(value: unknown, maxLength: number) {
  return typeof value === "string" ? value.slice(0, maxLength) : "";
}

function compactStoredConfig(config: StoredGenerationConfig): StoredGenerationConfig {
  const sourceLabel = shortText(config.sourceLabel, 500);
  return {
    aspectRatio: config.aspectRatio,
    duration: config.duration,
    resolution: config.resolution,
    generateAudio: Boolean(config.generateAudio),
    safetyTolerance: config.safetyTolerance,
    draft: Boolean(config.draft),
    exactTiming: Boolean(config.exactTiming),
    keyframes: Array.isArray(config.keyframes)
      ? config.keyframes.slice(0, 10).map((frame) => ({
          label: shortText(frame?.label, 240),
          seconds: typeof frame?.seconds === "number" ? frame.seconds : undefined,
          source: frame?.source?.kind === "local"
            ? {
                kind: "local" as const,
                value: shortText(frame.source.value, 80),
                label: shortText(frame.source.label, 240),
                contentType: shortText(frame.source.contentType, 120),
                bytes: typeof frame.source.bytes === "number" ? frame.source.bytes : undefined,
              }
            : undefined,
        }))
      : undefined,
    sourceLabel: /^data:/i.test(sourceLabel) ? "Embedded source (not stored)" : sourceLabel || undefined,
    source: config.source?.kind === "local"
      ? {
          kind: "local",
          value: shortText(config.source.value, 80),
          label: shortText(config.source.label, 240),
          contentType: shortText(config.source.contentType, 120),
          bytes: typeof config.source.bytes === "number" ? config.source.bytes : undefined,
        }
      : undefined,
  };
}

async function readCreditsSafely(provider: ProviderId, apiKey: string) {
  try {
    return (await getServerProvider(provider).credits(apiKey)).credits;
  } catch {
    return undefined;
  }
}

export async function POST(request: Request) {
  let generation: StoredGeneration | null = null;
  try {
    const body = (await request.json()) as Partial<SubmitGenerationRequest> & { record?: SubmitRecord };
    if (body.provider !== "bfl" || !body.input || !body.record?.localId || !body.record.config) {
      return Response.json({ error: "The generation request is incomplete." }, { status: 400 });
    }
    const apiKey = await getBflApiKey();
    if (!apiKey) {
      return Response.json({ error: "Add a BFL API key in Settings before generating." }, { status: 400 });
    }

    const now = new Date().toISOString();
    const config = await persistGenerationInputs(
      body.input,
      compactStoredConfig(body.record.config),
    );
    const existingHistory = (await readLocalData()).generations;
    const estimate = estimateGenerationCredits(body.provider, { mode: body.record.mode, config }, existingHistory);
    generation = {
      localId: body.record.localId,
      provider: "bfl",
      model: "flux-3-video",
      status: "submitting",
      progress: 0,
      prompt: shortText(body.record.prompt, 50_000),
      mode: body.record.mode,
      config,
      createdAt: body.record.createdAt || now,
      updatedAt: now,
      estimatedCreditsMin: estimate.minimum,
      estimatedCreditsMax: estimate.maximum,
      estimateBasis: estimate.basis,
    };
    await upsertGeneration(generation);

    const creditsBefore = await readCreditsSafely(body.provider, apiKey);
    if (creditsBefore !== undefined) {
      generation = { ...generation, creditsBefore };
      await upsertGeneration(generation);
    }

    const data = await getServerProvider(body.provider).submit(apiKey, body.input) as AsyncGenerationResponse;
    const cost = typeof data.cost === "number" && Number.isFinite(data.cost) ? data.cost : null;
    const liveCreditsAfter = await readCreditsSafely(body.provider, apiKey);
    const creditsAfter = liveCreditsAfter ?? (creditsBefore !== undefined && typeof cost === "number"
      ? Math.max(0, creditsBefore - cost)
      : undefined);
    generation = {
      ...generation,
      requestId: data.id,
      pollingUrl: data.polling_url,
      status: "Pending",
      progress: undefined,
      cost,
      creditsBefore,
      creditsAfter,
      updatedAt: new Date().toISOString(),
    };
    await upsertGeneration(generation);
    return Response.json({ ...data, generation }, { status: 201 });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Generation could not be submitted.";
    if (generation) {
      generation = {
        ...generation,
        status: "Error",
        error: message,
        updatedAt: new Date().toISOString(),
      };
      await upsertGeneration(generation).catch(() => undefined);
    }
    if (error instanceof ProviderRequestError) {
      return Response.json(
        { error: error.message, details: error.details, generation },
        { status: error.status },
      );
    }
    return Response.json({ error: message, generation }, { status: 500 });
  }
}
