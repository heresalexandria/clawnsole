import type {
  Flux3VideoInput,
  GenerationResultPayload,
} from "../../providers/contracts";
import { ProviderRequestError, readProviderResponse } from "./errors";

const BFL_BASE_URL = "https://api.bfl.ai";

function apiHeaders(apiKey: string, json = false) {
  const headers: Record<string, string> = {
    Accept: "application/json",
    "x-key": apiKey,
  };
  if (json) headers["Content-Type"] = "application/json";
  return headers;
}

export function assertBflPollingUrl(value: string) {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw new ProviderRequestError("The polling URL is invalid.", 400);
  }
  if (url.protocol !== "https:" || (!url.hostname.endsWith(".bfl.ai") && url.hostname !== "bfl.ai")) {
    throw new ProviderRequestError("The polling URL is not a BFL endpoint.", 400);
  }
  return url;
}

export async function submitBflGeneration(apiKey: string, input: Flux3VideoInput) {
  const response = await fetch(`${BFL_BASE_URL}/v1/flux-3-video`, {
    method: "POST",
    headers: apiHeaders(apiKey, true),
    body: JSON.stringify(input),
  });
  return readProviderResponse(response);
}

export async function pollBflGeneration(
  apiKey: string,
  pollingUrl: string,
): Promise<GenerationResultPayload> {
  const url = assertBflPollingUrl(pollingUrl);
  const response = await fetch(url, {
    headers: apiHeaders(apiKey),
    cache: "no-store",
  });
  return (await readProviderResponse(response)) as GenerationResultPayload;
}

export async function getBflCredits(apiKey: string) {
  const response = await fetch(`${BFL_BASE_URL}/v1/credits`, {
    headers: apiHeaders(apiKey),
    cache: "no-store",
  });
  const payload = (await readProviderResponse(response)) as { credits?: unknown };
  if (typeof payload.credits !== "number" || !Number.isFinite(payload.credits)) {
    throw new ProviderRequestError("BFL returned an invalid credit balance.", 502, payload);
  }
  return { credits: payload.credits };
}
