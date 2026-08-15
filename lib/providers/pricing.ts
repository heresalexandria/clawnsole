import type { StoredGeneration, StoredGenerationConfig } from "../generations";
import type { ProviderId, VideoMode } from "./contracts";

export const BFL_USD_PER_CREDIT = 0.01;

export interface CreditEstimate {
  minimum: number;
  maximum: number;
  basis: "bfl-rate" | "provider-history";
}

interface EstimateInput {
  mode: VideoMode;
  config: StoredGenerationConfig;
}

// Published by Black Forest Labs at https://bfl.ai/pricing. BFL prices in USD
// per second; one BFL credit is $0.01, so $0.17/second is 17 credits/second.
const BFL_CREDITS_PER_SECOND = {
  textOrImage: { draft: 6, hd: 17, fhd: 29 },
  video: { draft: 12, hd: 41, fhd: 53 },
} as const;

function actualCredits(item: StoredGeneration) {
  return typeof item.cost === "number" && Number.isFinite(item.cost) && item.cost >= 0
    ? item.cost
    : null;
}

function median(values: number[]) {
  const ordered = [...values].sort((a, b) => a - b);
  const middle = Math.floor(ordered.length / 2);
  return ordered.length % 2
    ? ordered[middle]
    : (ordered[middle - 1] + ordered[middle]) / 2;
}

function samePricingSignature(item: StoredGeneration, input: EstimateInput) {
  return item.mode === input.mode
    && item.config.resolution === input.config.resolution
    && item.config.duration === input.config.duration
    && item.config.generateAudio === input.config.generateAudio
    && item.config.draft === input.config.draft;
}

function roundCredits(value: number) {
  return Math.max(0, Math.round(value * 10) / 10);
}

function estimateBflGenerationCredits(
  input: EstimateInput,
  history: StoredGeneration[] = [],
): CreditEstimate {
  const exactQuotes = history
    .filter((item) => samePricingSignature(item, input))
    .map(actualCredits)
    .filter((value): value is number => value !== null);

  if (exactQuotes.length) {
    const quote = roundCredits(median(exactQuotes));
    return { minimum: quote, maximum: quote, basis: "provider-history" };
  }

  const sameTierRates = history.flatMap((item) => {
    const credits = actualCredits(item);
    const duration = item.config.duration;
    if (credits === null
      || typeof duration !== "number"
      || duration <= 0
      || item.mode !== input.mode
      || item.config.resolution !== input.config.resolution
      || item.config.generateAudio !== input.config.generateAudio
      || item.config.draft !== input.config.draft) return [];
    return [credits / duration];
  });

  const rateTable = input.mode === "v2v" ? BFL_CREDITS_PER_SECOND.video : BFL_CREDITS_PER_SECOND.textOrImage;
  const publishedRate = input.config.draft && input.mode !== "draft_enhance"
    ? rateTable.draft
    : rateTable[input.config.resolution];
  const rate = sameTierRates.length ? median(sameTierRates) : publishedRate;
  const basis = sameTierRates.length ? "provider-history" : "bfl-rate";
  const duration = input.config.duration;
  const minimumSeconds = typeof duration === "number" ? duration : 5;
  const maximumSeconds = typeof duration === "number" ? duration : 20;

  return {
    minimum: roundCredits(rate * minimumSeconds),
    maximum: roundCredits(rate * maximumSeconds),
    basis,
  };
}

export function estimateGenerationCredits(
  provider: ProviderId,
  input: EstimateInput,
  history: StoredGeneration[] = [],
) {
  if (provider === "bfl") return estimateBflGenerationCredits(input, history);
  const unsupportedProvider: never = provider;
  throw new Error(`No cost estimator is registered for ${unsupportedProvider}.`);
}

export function creditsToUsd(provider: ProviderId, credits: number) {
  if (provider === "bfl") return credits * BFL_USD_PER_CREDIT;
  const unsupportedProvider: never = provider;
  throw new Error(`No credit conversion is registered for ${unsupportedProvider}.`);
}
