import type { Flux3AspectRatio, ProviderId, VideoMode } from "./contracts";

export interface VideoProviderDefinition {
  id: ProviderId;
  name: string;
  model: string;
  modelLabel: string;
  description: string;
  modes: Array<{ id: VideoMode; label: string; shortLabel: string }>;
  aspectRatios: Flux3AspectRatio[];
  duration: { min: number; max: number; supportsAuto: boolean };
  resolutions: Array<{ id: "hd" | "fhd"; label: string; detail: string }>;
  safety: { min: number; max: number; default: number };
  maxKeyframes: number;
  supportsAudio: boolean;
  supportsDrafts: boolean;
  billing: { creditLabel: string; pricingUrl: string };
  docsUrl: string;
}

export const VIDEO_PROVIDERS: Record<ProviderId, VideoProviderDefinition> = {
  bfl: {
    id: "bfl",
    name: "Black Forest Labs",
    model: "flux-3-video",
    modelLabel: "FLUX 3",
    description: "Multimodal video with synchronized audio and keyframe control.",
    modes: [
      { id: "t2v", label: "Text to video", shortLabel: "Text" },
      { id: "i2v", label: "Image to video", shortLabel: "Frames" },
      { id: "v2v", label: "Video continuation", shortLabel: "Continue" },
      { id: "draft_enhance", label: "Draft enhance", shortLabel: "Enhance" },
    ],
    aspectRatios: ["auto", "21:9", "2:1", "16:9", "4:3", "1:1", "3:4", "9:16"],
    duration: { min: 5, max: 20, supportsAuto: true },
    resolutions: [
      { id: "hd", label: "HD", detail: "Fast native render" },
      { id: "fhd", label: "Full HD", detail: "Upsampled finish" },
    ],
    safety: { min: 0, max: 4, default: 2 },
    maxKeyframes: 10,
    supportsAudio: true,
    supportsDrafts: true,
    billing: { creditLabel: "BFL credits", pricingUrl: "https://bfl.ai/pricing" },
    docsUrl: "https://docs.bfl.ai/flux_3/flux3_video",
  },
};

export const DEFAULT_PROVIDER = VIDEO_PROVIDERS.bfl;
