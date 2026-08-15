import type { StoredGeneration } from "../../../../lib/generations";
import type {
  GenerationResultPayload,
  PollGenerationRequest,
} from "../../../../lib/providers/contracts";
import { getBflApiKey, updateGeneration } from "../../../../lib/server/data-store";
import { getServerProvider } from "../../../../lib/server/providers";
import { ProviderRequestError } from "../../../../lib/server/providers/errors";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

function normalizeProgress(progress: number | null | undefined) {
  if (progress == null || !Number.isFinite(progress)) return undefined;
  const normalized = progress <= 1 ? progress * 100 : progress;
  return Math.max(0, Math.min(100, Math.round(normalized)));
}

function findUrl(value: unknown, wanted: "media" | "draft", key = ""): string | undefined {
  if (typeof value === "string" && /^https:\/\//.test(value)) {
    const isDraft = /draft|cache|\.bin(?:\?|$)/i.test(`${key} ${value}`);
    if ((wanted === "draft" && isDraft) || (wanted === "media" && !isDraft)) return value;
  }
  if (Array.isArray(value)) {
    for (const item of value) {
      const found = findUrl(item, wanted, key);
      if (found) return found;
    }
  } else if (typeof value === "object" && value !== null) {
    for (const [childKey, child] of Object.entries(value)) {
      const found = findUrl(child, wanted, childKey);
      if (found) return found;
    }
  }
  return undefined;
}

function storedStatus(payload: GenerationResultPayload): StoredGeneration["status"] {
  if (payload.status === "Ready") return "Ready";
  if (payload.status === "Error"
    || payload.status === "Failed"
    || payload.status === "Request Moderated"
    || payload.status === "Content Moderated") return payload.status;
  return "Pending";
}

export async function POST(request: Request) {
  try {
    const body = (await request.json()) as Partial<PollGenerationRequest>;
    if (!body.pollingUrl || !body.localId || body.provider !== "bfl") {
      return Response.json({ error: "A provider, generation id, and polling URL are required." }, { status: 400 });
    }
    const apiKey = await getBflApiKey();
    if (!apiKey) return Response.json({ error: "The saved BFL API key is missing." }, { status: 400 });

    const payload = await getServerProvider(body.provider).poll(apiKey, body.pollingUrl);
    const status = storedStatus(payload);
    const resultUrl = status === "Ready" ? findUrl(payload.result, "media") : undefined;
    const draftCacheUrl = status === "Ready" ? findUrl(payload.result, "draft") : undefined;
    const generation = await updateGeneration(body.localId, (current) => ({
      ...current,
      status,
      progress: status === "Ready" ? 100 : normalizeProgress(payload.progress),
      updatedAt: new Date().toISOString(),
      resultUrl: resultUrl ?? current.resultUrl,
      draftCacheUrl: draftCacheUrl ?? current.draftCacheUrl,
      deliveryExpiresAt: status === "Ready"
        ? new Date(Date.now() + 10 * 60 * 1000).toISOString()
        : current.deliveryExpiresAt,
      error: status === "Error" || status === "Failed"
        || status === "Request Moderated" || status === "Content Moderated"
        ? JSON.stringify(payload.details ?? payload.result ?? status).slice(0, 2000)
        : undefined,
    }));
    return Response.json({ ...payload, generation });
  } catch (error) {
    if (error instanceof ProviderRequestError) {
      return Response.json(
        { error: error.message, details: error.details },
        { status: error.status },
      );
    }
    return Response.json(
      { error: error instanceof Error ? error.message : "Generation status is unavailable." },
      { status: 500 },
    );
  }
}
