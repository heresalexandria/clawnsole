export type ProviderId = "bfl";

export type VideoMode = "t2v" | "i2v" | "v2v" | "draft_enhance";

export type Flux3AspectRatio =
  | "auto"
  | "21:9"
  | "2:1"
  | "16:9"
  | "4:3"
  | "1:1"
  | "3:4"
  | "9:16";

export type Flux3Duration = "auto" | number;
export type Flux3Resolution = "hd" | "fhd";
export type Flux3Keyframe = string | [seconds: number, image: string];

export interface Flux3CommonInput {
  prompt: string;
  aspect_ratio: Flux3AspectRatio;
  duration: Flux3Duration;
  resolution: Flux3Resolution;
  version: "latest";
  generate_audio: boolean;
  safety_tolerance: number;
  draft: boolean;
}

export interface Flux3TextToVideoInput extends Flux3CommonInput {
  mode: "t2v";
}

export interface Flux3ImageToVideoInput extends Flux3CommonInput {
  mode: "i2v";
  keyframes: Flux3Keyframe[];
}

export interface Flux3VideoToVideoInput extends Flux3CommonInput {
  mode: "v2v";
  start_video: string;
}

export interface Flux3DraftEnhanceInput {
  mode: "draft_enhance";
  draft_cache: string;
  resolution: Flux3Resolution;
  safety_tolerance: number;
}

export type Flux3VideoInput =
  | Flux3TextToVideoInput
  | Flux3ImageToVideoInput
  | Flux3VideoToVideoInput
  | Flux3DraftEnhanceInput;

export interface SubmitGenerationRequest {
  provider: ProviderId;
  input: Flux3VideoInput;
}

export interface PollGenerationRequest {
  provider: ProviderId;
  pollingUrl: string;
  localId: string;
}

export interface AsyncGenerationResponse {
  id: string;
  polling_url: string;
  cost?: number | null;
}

export interface GenerationResultPayload {
  id: string;
  status:
    | "Task not found"
    | "Pending"
    | "Request Moderated"
    | "Content Moderated"
    | "Ready"
    | "Error"
    | "Failed";
  result?: Record<string, unknown> | null;
  progress?: number | null;
  details?: Record<string, unknown>;
  preview?: Record<string, unknown>;
}
