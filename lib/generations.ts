import type {
  Flux3AspectRatio,
  Flux3Duration,
  Flux3Resolution,
  VideoMode,
} from "./providers/contracts";

export type StoredGenerationStatus =
  | "submitting"
  | "Pending"
  | "Ready"
  | "Error"
  | "Failed"
  | "Request Moderated"
  | "Content Moderated";

export interface StoredGenerationConfig {
  aspectRatio: Flux3AspectRatio;
  duration: Flux3Duration;
  resolution: Flux3Resolution;
  generateAudio: boolean;
  safetyTolerance: number;
  draft: boolean;
  keyframes?: Array<{ label: string; seconds?: number }>;
  sourceLabel?: string;
}

export interface StoredGeneration {
  localId: string;
  provider: "bfl";
  model: "flux-3-video";
  requestId?: string;
  pollingUrl?: string;
  status: StoredGenerationStatus;
  progress?: number;
  prompt: string;
  mode: VideoMode;
  config: StoredGenerationConfig;
  createdAt: string;
  updatedAt: string;
  resultUrl?: string;
  draftCacheUrl?: string;
  deliveryExpiresAt?: string;
  deliveryExpired?: boolean;
  estimatedCreditsMin?: number;
  estimatedCreditsMax?: number;
  estimateBasis?: "bfl-rate" | "provider-history";
  creditsBefore?: number;
  creditsAfter?: number;
  cost?: number | null;
  error?: string;
}

export interface LocalPreferences {
  activeSection: "create" | "library" | "settings";
  libraryFilter: "all" | "working" | "ready" | "failed";
}

export interface LocalDataStats {
  path: string;
  bytes: number;
  records: number;
  lastUpdated: string | null;
}

export interface PublicLocalState {
  generations: StoredGeneration[];
  preferences: LocalPreferences;
  hasBflApiKey: boolean;
  storage: LocalDataStats;
}
