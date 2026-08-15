"use client";

import {
  AlertTriangle,
  ArrowDownToLine,
  AudioLines,
  Check,
  ChevronDown,
  CircleDot,
  Clock3,
  Coins,
  ExternalLink,
  Eye,
  EyeOff,
  FileVideo,
  Film,
  FolderDown,
  HardDrive,
  ImagePlus,
  Images,
  KeyRound,
  LibraryBig,
  Link2,
  LoaderCircle,
  PawPrint,
  Play,
  Plus,
  RefreshCw,
  RotateCcw,
  Settings2,
  ShieldCheck,
  SlidersHorizontal,
  Sparkles,
  Trash2,
  UploadCloud,
  Volume2,
  WandSparkles,
  X,
} from "lucide-react";
import {
  type ChangeEvent,
  type FormEvent,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import {
  DEFAULT_PROVIDER,
  VIDEO_PROVIDERS,
} from "../lib/providers/catalog";
import type {
  AsyncGenerationResponse,
  Flux3AspectRatio,
  Flux3Duration,
  Flux3Keyframe,
  Flux3Resolution,
  Flux3VideoInput,
  GenerationResultPayload,
  VideoMode,
} from "../lib/providers/contracts";
import {
  type LocalDataStats,
  type PublicLocalState,
  type StoredAssetReference,
  type StoredGeneration,
  type StoredGenerationConfig,
} from "../lib/generations";
import {
  creditsToUsd,
  estimateGenerationCredits,
} from "../lib/providers/pricing";

type AppSection = "create" | "library" | "settings";
type LibraryFilter = "all" | "working" | "ready" | "failed";

interface KeyframeDraft {
  id: string;
  label: string;
  source: string;
  seconds: number;
  kind: "file" | "url" | "local";
  storedSource?: StoredAssetReference;
}

interface SourceDraft {
  file?: File;
  url: string;
  previewUrl?: string;
  storedSource?: StoredAssetReference;
}

interface GenerationForm {
  mode: VideoMode;
  prompt: string;
  aspectRatio: Flux3AspectRatio;
  duration: Flux3Duration;
  durationSeconds: number;
  resolution: Flux3Resolution;
  generateAudio: boolean;
  safetyTolerance: number;
  draft: boolean;
  exactTiming: boolean;
}

interface FilePickerWindow extends Window {
  showSaveFilePicker?: (options: {
    suggestedName: string;
    types: Array<{ description: string; accept: Record<string, string[]> }>;
  }) => Promise<{
    createWritable(): Promise<WritableStream>;
  }>;
}

interface ProviderCreditState {
  credits: number | null;
  loading: boolean;
  error?: string;
  updatedAt?: string;
}

const INITIAL_FORM: GenerationForm = {
  mode: "t2v",
  prompt: "",
  aspectRatio: "16:9",
  duration: "auto",
  durationSeconds: 8,
  resolution: "hd",
  generateAudio: true,
  safetyTolerance: 2,
  draft: false,
  exactTiming: false,
};

const EMPTY_STORAGE: LocalDataStats = {
  path: "",
  bytes: 0,
  assetBytes: 0,
  assets: 0,
  records: 0,
  lastUpdated: null,
};

const STATUS_FAILURES = new Set(["Error", "Failed", "Request Moderated", "Content Moderated"]);

function uid() {
  return typeof crypto !== "undefined" && "randomUUID" in crypto
    ? crypto.randomUUID()
    : `${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

function fileToDataUrl(file: Blob) {
  return new Promise<string>((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result));
    reader.onerror = () => reject(reader.error ?? new Error("The file could not be read."));
    reader.readAsDataURL(file);
  });
}

function formatBytes(bytes: number) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(bytes > 10 * 1024 ? 0 : 1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
}

function formatRelativeTime(value: string) {
  const seconds = Math.max(0, Math.round((Date.now() - new Date(value).getTime()) / 1000));
  if (seconds < 60) return "Just now";
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`;
  return new Intl.DateTimeFormat("en", { month: "short", day: "numeric" }).format(new Date(value));
}

function formatCredits(value: number) {
  return new Intl.NumberFormat("en", { maximumFractionDigits: 1 }).format(value);
}

function formatUsdFromCredits(value: number) {
  return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(creditsToUsd(DEFAULT_PROVIDER.id, value));
}

function formatCreditRange(minimum: number, maximum: number) {
  return minimum === maximum
    ? formatCredits(minimum)
    : `${formatCredits(minimum)}–${formatCredits(maximum)}`;
}

function formatUsdRange(minimum: number, maximum: number) {
  return minimum === maximum
    ? formatUsdFromCredits(minimum)
    : `${formatUsdFromCredits(minimum)}–${formatUsdFromCredits(maximum)}`;
}

function storedCreditRange(item: StoredGeneration) {
  if (typeof item.cost === "number") return { minimum: item.cost, maximum: item.cost, actual: true };
  if (typeof item.estimatedCreditsMin === "number" && typeof item.estimatedCreditsMax === "number") {
    return { minimum: item.estimatedCreditsMin, maximum: item.estimatedCreditsMax, actual: false };
  }
  return null;
}

function modeLabel(mode: VideoMode) {
  return DEFAULT_PROVIDER.modes.find((item) => item.id === mode)?.label ?? mode;
}

function getErrorMessage(payload: unknown, fallback: string) {
  if (typeof payload === "object" && payload !== null && "error" in payload) {
    return String((payload as { error: unknown }).error);
  }
  return fallback;
}

function mediaProxyUrl(url: string) {
  return `/api/media?url=${encodeURIComponent(url)}`;
}

function assetUrl(reference: StoredAssetReference) {
  return reference.kind === "local"
    ? `/api/assets?id=${encodeURIComponent(reference.value)}`
    : reference.value;
}

function generationMediaUrl(item: StoredGeneration) {
  if (item.resultAsset) return assetUrl(item.resultAsset);
  return item.resultUrl ? mediaProxyUrl(item.resultUrl) : "";
}

function generationInputPreview(item: StoredGeneration) {
  const firstFrame = item.config.keyframes?.find((frame) => frame.source)?.source;
  if (firstFrame) return assetUrl(firstFrame);
  if (item.config.source?.contentType?.startsWith("image/")) return assetUrl(item.config.source);
  return "";
}

async function requestSource(source: string, stored?: StoredAssetReference) {
  if (stored?.kind !== "local") return source.trim();
  const response = await fetch(assetUrl(stored), { cache: "no-store" });
  if (!response.ok) throw new Error(`The retained input “${stored.label}” is missing.`);
  return fileToDataUrl(await response.blob());
}

function isWorking(item: StoredGeneration) {
  return item.status === "submitting" || item.status === "Pending";
}

function filenameFor(item: StoredGeneration) {
  const date = item.createdAt.slice(0, 10);
  return `clawnsole-${date}-${item.localId.slice(0, 6)}.mp4`;
}

export function ClawnsoleApp() {
  const [section, setSection] = useState<AppSection>("create");
  const [libraryFilter, setLibraryFilter] = useState<LibraryFilter>("all");
  const [history, setHistory] = useState<StoredGeneration[]>([]);
  const [form, setForm] = useState<GenerationForm>(INITIAL_FORM);
  const [keyframes, setKeyframes] = useState<KeyframeDraft[]>([]);
  const [videoSource, setVideoSource] = useState<SourceDraft>({ url: "" });
  const [draftSource, setDraftSource] = useState<SourceDraft>({ url: "" });
  const [advancedOpen, setAdvancedOpen] = useState(false);
  const [modelMenuOpen, setModelMenuOpen] = useState(false);
  const [hasApiKey, setHasApiKey] = useState(false);
  const [keyDraft, setKeyDraft] = useState("");
  const [showKey, setShowKey] = useState(false);
  const [keyCheck, setKeyCheck] = useState<{ state: "idle" | "checking" | "valid" | "error"; credits?: number; message?: string }>({ state: "idle" });
  const [providerCredit, setProviderCredit] = useState<ProviderCreditState>({ credits: null, loading: false });
  const [storage, setStorage] = useState<LocalDataStats>(EMPTY_STORAGE);
  const [search, setSearch] = useState("");
  const [toast, setToast] = useState("");
  const historyRef = useRef(history);
  const pollingRef = useRef(new Set<string>());
  const retentionAttemptsRef = useRef(new Set<string>());
  const toastTimerRef = useRef<number | null>(null);

  useEffect(() => {
    historyRef.current = history;
  }, [history]);

  useEffect(() => () => {
    if (toastTimerRef.current) window.clearTimeout(toastTimerRef.current);
    if (videoSource.previewUrl) URL.revokeObjectURL(videoSource.previewUrl);
  }, [videoSource.previewUrl]);

  const showToastMessage = useCallback((message: string) => {
    setToast(message);
    if (toastTimerRef.current) window.clearTimeout(toastTimerRef.current);
    toastTimerRef.current = window.setTimeout(() => setToast(""), 3600);
  }, []);

  const applyLocalState = useCallback((state: PublicLocalState) => {
    setHistory(state.generations);
    historyRef.current = state.generations;
    setSection(state.preferences.activeSection);
    setLibraryFilter(state.preferences.libraryFilter);
    setHasApiKey(state.hasBflApiKey);
    setStorage(state.storage);
  }, []);

  const refreshLocalState = useCallback(async () => {
    const response = await fetch("/api/local-state", { cache: "no-store" });
    const payload = (await response.json()) as PublicLocalState & { error?: string };
    if (!response.ok) throw new Error(payload.error || "Local data could not be read.");
    applyLocalState(payload);
    return payload;
  }, [applyLocalState]);

  const mutateLocalState = useCallback(async (action: string, value?: unknown) => {
    const response = await fetch("/api/local-state", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action, value }),
    });
    const payload = (await response.json()) as PublicLocalState & { error?: string };
    if (!response.ok) throw new Error(payload.error || "Local data could not be updated.");
    applyLocalState(payload);
    return payload;
  }, [applyLocalState]);

  useEffect(() => {
    const timer = window.setTimeout(() => {
      void refreshLocalState().catch((error) => {
        showToastMessage(error instanceof Error ? error.message : "Local data could not be read.");
      });
    }, 0);
    return () => window.clearTimeout(timer);
  }, [refreshLocalState, showToastMessage]);

  const updateHistory = useCallback((updater: (items: StoredGeneration[]) => StoredGeneration[]) => {
    setHistory((current) => {
      const next = updater(current);
      historyRef.current = next;
      return next;
    });
  }, []);

  const refreshProviderCredits = useCallback(async () => {
    if (!hasApiKey) {
      setProviderCredit({ credits: null, loading: false });
      return;
    }
    setProviderCredit((current) => ({ ...current, loading: true, error: undefined }));
    try {
      const response = await fetch("/api/providers/bfl/credits", { cache: "no-store" });
      const payload = (await response.json()) as { credits?: number; error?: string };
      if (!response.ok || typeof payload.credits !== "number") {
        throw new Error(payload.error || "BFL credit balance is unavailable.");
      }
      setProviderCredit({ credits: payload.credits, loading: false, updatedAt: new Date().toISOString() });
    } catch (error) {
      setProviderCredit((current) => ({
        ...current,
        loading: false,
        error: error instanceof Error ? error.message : "BFL credit balance is unavailable.",
      }));
    }
  }, [hasApiKey]);

  useEffect(() => {
    if (!hasApiKey) {
      setProviderCredit({ credits: null, loading: false });
      return;
    }
    const refreshWhenVisible = () => {
      if (document.visibilityState === "visible") void refreshProviderCredits();
    };
    const first = window.setTimeout(refreshWhenVisible, 150);
    const interval = window.setInterval(refreshWhenVisible, 60_000);
    document.addEventListener("visibilitychange", refreshWhenVisible);
    return () => {
      window.clearTimeout(first);
      window.clearInterval(interval);
      document.removeEventListener("visibilitychange", refreshWhenVisible);
    };
  }, [hasApiKey, refreshProviderCredits]);

  const pollGeneration = useCallback(async (item: StoredGeneration) => {
    if (!hasApiKey || !item.pollingUrl || pollingRef.current.has(item.localId)) return;
    pollingRef.current.add(item.localId);
    try {
      const response = await fetch("/api/generations/status", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ provider: item.provider, localId: item.localId, pollingUrl: item.pollingUrl }),
      });
      const payload = (await response.json()) as GenerationResultPayload & { error?: string; generation?: StoredGeneration };
      if (!response.ok) throw new Error(getErrorMessage(payload, "Status could not be checked."));
      if (payload.generation) {
        updateHistory((items) => items.map((entry) => entry.localId === item.localId ? payload.generation! : entry));
        if (payload.generation.status === "Ready") showToastMessage("Your film is ready to watch and save.");
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : "Status could not be checked.";
      if (!/429|active request/i.test(message)) {
        updateHistory((items) => items.map((entry) => entry.localId === item.localId
          ? { ...entry, error: message, updatedAt: new Date().toISOString() }
          : entry));
      }
    } finally {
      pollingRef.current.delete(item.localId);
    }
  }, [hasApiKey, showToastMessage, updateHistory]);

  useEffect(() => {
    if (!hasApiKey) return;
    const run = () => {
      for (const item of historyRef.current.filter(isWorking)) void pollGeneration(item);
    };
    const first = window.setTimeout(run, 900);
    const interval = window.setInterval(run, 4000);
    return () => {
      window.clearTimeout(first);
      window.clearInterval(interval);
    };
  }, [hasApiKey, pollGeneration]);

  useEffect(() => {
    for (const item of history) {
      if (item.status !== "Ready" || item.resultAsset
        || retentionAttemptsRef.current.has(item.localId)) continue;
      retentionAttemptsRef.current.add(item.localId);
      if (item.resultUrl) {
        void fetch("/api/assets", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ localId: item.localId }),
        }).then(async (response) => {
          const payload = (await response.json()) as { generation?: StoredGeneration };
          if (response.ok && payload.generation) {
            updateHistory((items) => items.map((entry) => entry.localId === item.localId
              ? payload.generation!
              : entry));
          }
        }).catch(() => undefined);
      } else if (hasApiKey && item.pollingUrl) {
        void pollGeneration(item);
      }
    }
  }, [hasApiKey, history, pollGeneration, updateHistory]);

  const navigate = (next: AppSection) => {
    setSection(next);
    void fetch("/api/local-state", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: "setPreferences", value: { activeSection: next, libraryFilter } }),
    });
  };

  const setFilter = (filter: LibraryFilter) => {
    setLibraryFilter(filter);
    void fetch("/api/local-state", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: "setPreferences", value: { activeSection: section, libraryFilter: filter } }),
    });
  };

  const setMode = (mode: VideoMode) => {
    setForm((current) => ({ ...current, mode }));
  };

  const addFrameFiles = async (event: ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(event.target.files ?? []);
    event.target.value = "";
    if (!files.length) return;
    const available = DEFAULT_PROVIDER.maxKeyframes - keyframes.length;
    const selected = files.slice(0, available);
    const frames = await Promise.all(selected.map(async (file, index) => ({
      id: uid(),
      label: file.name,
      source: await fileToDataUrl(file),
      seconds: keyframes.length + index === 0 ? 0 : Math.min(20, (keyframes.length + index) * 3),
      kind: "file" as const,
    })));
    setKeyframes((current) => [...current, ...frames]);
    if (files.length > available) showToastMessage("FLUX 3 accepts up to ten keyframes.");
  };

  const addUrlFrame = () => {
    if (keyframes.length >= DEFAULT_PROVIDER.maxKeyframes) return;
    setKeyframes((current) => [...current, {
      id: uid(),
      label: "Reference URL",
      source: "",
      seconds: current.length === 0 ? 0 : Math.min(20, current.length * 3),
      kind: "url",
    }]);
  };

  const updateFrame = (id: string, patch: Partial<KeyframeDraft>) => {
    setKeyframes((current) => current.map((frame) => frame.id === id
      ? { ...frame, ...patch, storedSource: patch.source === undefined ? frame.storedSource : undefined }
      : frame));
  };

  const removeFrame = (id: string) => {
    setKeyframes((current) => current.filter((frame) => frame.id !== id));
  };

  const onVideoFile = (event: ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    event.target.value = "";
    if (!file) return;
    if (videoSource.previewUrl) URL.revokeObjectURL(videoSource.previewUrl);
    setVideoSource({ file, url: "", previewUrl: URL.createObjectURL(file) });
  };

  const onDraftFile = (event: ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    event.target.value = "";
    if (!file) return;
    setDraftSource({ file, url: "" });
  };

  const validateForm = () => {
    if (!hasApiKey) return "Add your BFL API key before generating.";
    if (form.mode !== "draft_enhance" && !form.prompt.trim()) return "Describe the video you want to make.";
    if (form.mode === "i2v") {
      if (!keyframes.length) return "Add at least one image frame.";
      if (keyframes.some((frame) => !frame.source.trim())) return "Every keyframe needs an image or URL.";
      if (!form.exactTiming && keyframes.length > 2 && form.duration === "auto") {
        return "Choose a duration when using three or more evenly spaced frames.";
      }
      if (form.exactTiming) {
        const ordered = [...keyframes].sort((a, b) => a.seconds - b.seconds);
        if (ordered.some((frame) => frame.seconds < 0 || frame.seconds > 20)) return "Keyframe timing must stay between 0 and 20 seconds.";
        if (new Set(ordered.map((frame) => frame.seconds)).size !== ordered.length) return "Each timed keyframe needs a unique time.";
      }
    }
    if (form.mode === "v2v" && !videoSource.file && !videoSource.url.trim()) return "Add the video you want FLUX 3 to continue.";
    if (form.mode === "draft_enhance" && !draftSource.file && !draftSource.url.trim()) return "Add a draft cache bundle or URL.";
    return "";
  };

  const buildInput = async (): Promise<Flux3VideoInput> => {
    if (form.mode === "draft_enhance") {
      return {
        mode: "draft_enhance",
        draft_cache: draftSource.file
          ? await fileToDataUrl(draftSource.file)
          : await requestSource(draftSource.url, draftSource.storedSource),
        resolution: form.resolution,
        safety_tolerance: form.safetyTolerance,
      };
    }

    const common = {
      prompt: form.prompt.trim(),
      aspect_ratio: form.aspectRatio,
      duration: form.duration === "auto" ? "auto" as const : form.durationSeconds,
      resolution: form.resolution,
      version: "latest" as const,
      generate_audio: form.generateAudio,
      safety_tolerance: form.safetyTolerance,
      draft: form.draft,
    };
    if (form.mode === "i2v") {
      const ordered = form.exactTiming
        ? [...keyframes].sort((a, b) => a.seconds - b.seconds)
        : keyframes;
      const frames = await Promise.all(ordered.map(async (frame) => {
        const source = await requestSource(frame.source, frame.storedSource);
        return form.exactTiming ? [frame.seconds, source] as Flux3Keyframe : source;
      }));
      return { ...common, mode: "i2v", keyframes: frames };
    }
    if (form.mode === "v2v") {
      return {
        ...common,
        mode: "v2v",
        start_video: videoSource.file
          ? await fileToDataUrl(videoSource.file)
          : await requestSource(videoSource.url, videoSource.storedSource),
      };
    }
    return { ...common, mode: "t2v" };
  };

  const compactConfig = (): StoredGenerationConfig => {
    const orderedFrames = form.exactTiming
      ? [...keyframes].sort((a, b) => a.seconds - b.seconds)
      : keyframes;
    return {
      aspectRatio: form.aspectRatio,
      duration: form.duration === "auto" ? "auto" : form.durationSeconds,
      resolution: form.resolution,
      generateAudio: form.generateAudio,
      safetyTolerance: form.safetyTolerance,
      draft: form.draft,
      exactTiming: form.exactTiming,
      keyframes: form.mode === "i2v"
        ? orderedFrames.map((frame) => ({
            label: frame.label,
            seconds: form.exactTiming ? frame.seconds : undefined,
            source: frame.storedSource,
          }))
        : undefined,
      sourceLabel: form.mode === "v2v"
        ? videoSource.file?.name || videoSource.url || undefined
        : form.mode === "draft_enhance"
          ? draftSource.file?.name || draftSource.url || undefined
          : undefined,
      source: form.mode === "v2v"
        ? videoSource.storedSource
        : form.mode === "draft_enhance"
          ? draftSource.storedSource
          : undefined,
    };
  };

  const submitGeneration = async (event: FormEvent) => {
    event.preventDefault();
    const problem = validateForm();
    if (problem) {
      if (!hasApiKey) navigate("settings");
      showToastMessage(problem);
      return;
    }

    const localId = uid();
    const now = new Date().toISOString();
    const config = compactConfig();
    const estimate = estimateGenerationCredits(DEFAULT_PROVIDER.id, { mode: form.mode, config }, historyRef.current);
    const prompt = form.mode === "draft_enhance" ? "Enhance saved FLUX 3 draft" : form.prompt.trim();
    const pending: StoredGeneration = {
      localId,
      provider: "bfl",
      model: "flux-3-video",
      status: "submitting",
      progress: 0,
      prompt,
      mode: form.mode,
      config,
      createdAt: now,
      updatedAt: now,
      estimatedCreditsMin: estimate.minimum,
      estimatedCreditsMax: estimate.maximum,
      estimateBasis: estimate.basis,
    };
    updateHistory((items) => [pending, ...items]);
    showToastMessage("Generation sent. Clawnsole will keep an eye on it.");

    try {
      const input = await buildInput();
      const response = await fetch("/api/generations", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          provider: "bfl",
          input,
          record: { localId, prompt, mode: form.mode, config, createdAt: now },
        }),
      });
      const payload = (await response.json()) as AsyncGenerationResponse & { error?: string; generation?: StoredGeneration };
      if (payload.generation) {
        updateHistory((items) => items.map((item) => item.localId === localId ? payload.generation! : item));
        if (typeof payload.generation.creditsAfter === "number") {
          setProviderCredit({
            credits: payload.generation.creditsAfter,
            loading: false,
            updatedAt: new Date().toISOString(),
          });
        } else {
          void refreshProviderCredits();
        }
      }
      if (!response.ok) throw new Error(getErrorMessage(payload, "Generation could not be submitted."));
    } catch (error) {
      const message = error instanceof Error ? error.message : "Generation could not be submitted.";
      updateHistory((items) => items.map((item) => item.localId === localId
        ? { ...item, status: "Error", error: message, updatedAt: new Date().toISOString() }
        : item));
      showToastMessage(message);
    }
  };

  const saveKey = async () => {
    const clean = keyDraft.trim();
    if (!clean) {
      showToastMessage("Paste a BFL API key first.");
      return;
    }
    try {
      await mutateLocalState("setApiKey", clean);
      setKeyDraft("");
      setKeyCheck({ state: "idle" });
      showToastMessage("API key saved to Clawnsole’s local data file.");
    } catch (error) {
      showToastMessage(error instanceof Error ? error.message : "The API key could not be saved.");
    }
  };

  const verifyKey = async () => {
    const clean = keyDraft.trim();
    if (!clean && !hasApiKey) return;
    setKeyCheck({ state: "checking" });
    try {
      const response = await fetch("/api/providers/bfl/credits", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(clean ? { apiKey: clean } : {}),
      });
      const payload = (await response.json()) as { credits?: number; error?: string };
      if (!response.ok) throw new Error(payload.error || "BFL rejected this key.");
      setKeyCheck({ state: "valid", credits: payload.credits });
      if (!clean && typeof payload.credits === "number") {
        setProviderCredit({ credits: payload.credits, loading: false, updatedAt: new Date().toISOString() });
      }
    } catch (error) {
      setKeyCheck({ state: "error", message: error instanceof Error ? error.message : "The key could not be checked." });
    }
  };

  const removeKey = async () => {
    try {
      await mutateLocalState("clearApiKey");
      setKeyDraft("");
      setKeyCheck({ state: "idle" });
      showToastMessage("API key removed from the local data file.");
    } catch (error) {
      showToastMessage(error instanceof Error ? error.message : "The API key could not be removed.");
    }
  };

  const saveMedia = async (item: StoredGeneration) => {
    const mediaUrl = generationMediaUrl(item);
    if (!mediaUrl) return;
    const filename = filenameFor(item);
    const picker = (window as FilePickerWindow).showSaveFilePicker;
    if (picker) {
      try {
        const handle = await picker({
          suggestedName: filename,
          types: [{ description: "MP4 video", accept: { "video/mp4": [".mp4"] } }],
        });
        const response = await fetch(mediaUrl);
        if (!response.ok || !response.body) throw new Error("The retained video is unavailable.");
        const writable = await handle.createWritable();
        await response.body.pipeTo(writable);
        showToastMessage("Saved. Finder knows exactly where it lives.");
        return;
      } catch (error) {
        if (error instanceof DOMException && error.name === "AbortError") return;
        showToastMessage(error instanceof Error ? error.message : "The video could not be saved.");
        return;
      }
    }
    const anchor = document.createElement("a");
    anchor.href = item.resultAsset
      ? `${assetUrl(item.resultAsset)}&download=1`
      : `${mediaUrl}&download=1&filename=${encodeURIComponent(filename)}`;
    anchor.download = filename;
    anchor.click();
    showToastMessage("Download started. Use your browser’s downloads to show it in Finder.");
  };

  const removeGeneration = async (localId: string) => {
    try {
      const response = await fetch(`/api/local-state/generations?id=${encodeURIComponent(localId)}`, { method: "DELETE" });
      const payload = (await response.json()) as PublicLocalState & { error?: string };
      if (!response.ok) throw new Error(payload.error || "The generation could not be removed.");
      applyLocalState(payload);
    } catch (error) {
      showToastMessage(error instanceof Error ? error.message : "The generation could not be removed.");
    }
  };

  const reuseGeneration = (item: StoredGeneration) => {
    setForm((current) => ({
      ...current,
      mode: item.mode === "draft_enhance" ? "t2v" : item.mode,
      prompt: item.mode === "draft_enhance" ? "" : item.prompt,
      aspectRatio: item.config.aspectRatio,
      duration: item.config.duration,
      durationSeconds: typeof item.config.duration === "number" ? item.config.duration : current.durationSeconds,
      resolution: item.config.resolution,
      generateAudio: item.config.generateAudio,
      safetyTolerance: item.config.safetyTolerance,
      draft: item.config.draft,
      exactTiming: Boolean(item.config.exactTiming),
    }));
    setKeyframes((item.config.keyframes ?? []).map((frame) => ({
      id: uid(),
      label: frame.label,
      source: frame.source ? assetUrl(frame.source) : "",
      seconds: frame.seconds ?? 0,
      kind: frame.source?.kind === "local" ? "local" : "url",
      storedSource: frame.source,
    })));
    const retainedSource = item.config.source;
    setVideoSource(item.mode === "v2v" && retainedSource
      ? {
          url: assetUrl(retainedSource),
          previewUrl: retainedSource.contentType?.startsWith("video/") ? assetUrl(retainedSource) : undefined,
          storedSource: retainedSource,
        }
      : { url: "" });
    setDraftSource({ url: "" });
    navigate("create");
    showToastMessage("Prompt, settings, and retained references copied.");
  };

  const enhanceDraft = (item: StoredGeneration) => {
    if (!item.draftCacheUrl) return;
    setForm((current) => ({
      ...current,
      mode: "draft_enhance",
      duration: item.config.duration,
      durationSeconds: typeof item.config.duration === "number" ? item.config.duration : current.durationSeconds,
      resolution: "fhd",
      generateAudio: item.config.generateAudio,
      draft: false,
    }));
    setDraftSource({ url: item.draftCacheUrl });
    navigate("create");
  };

  const clearHistoryAction = async () => {
    try {
      await mutateLocalState("clearHistory");
      showToastMessage("Generation history cleared from the data file.");
    } catch (error) {
      showToastMessage(error instanceof Error ? error.message : "History could not be cleared.");
    }
  };

  const clearPreferencesAction = async () => {
    try {
      await mutateLocalState("clearPreferences");
      showToastMessage("Saved preferences reset.");
    } catch (error) {
      showToastMessage(error instanceof Error ? error.message : "Preferences could not be reset.");
    }
  };

  const clearEverything = async () => {
    try {
      await mutateLocalState("clearAll");
      setKeyDraft("");
      setKeyCheck({ state: "idle" });
      showToastMessage("Clawnsole’s local data file was removed.");
    } catch (error) {
      showToastMessage(error instanceof Error ? error.message : "The local data file could not be removed.");
    }
  };

  const filteredHistory = useMemo(() => history.filter((item) => {
    const matchesSearch = !search.trim() || item.prompt.toLowerCase().includes(search.trim().toLowerCase());
    if (!matchesSearch) return false;
    if (libraryFilter === "working") return isWorking(item);
    if (libraryFilter === "ready") return item.status === "Ready";
    if (libraryFilter === "failed") return STATUS_FAILURES.has(item.status);
    return true;
  }), [history, libraryFilter, search]);

  const workingCount = history.filter(isWorking).length;
  const readyCount = history.filter((item) => item.status === "Ready").length;
  const spentCredits = history.reduce((total, item) => total + (typeof item.cost === "number" ? item.cost : 0), 0);
  const currentConfig = compactConfig();
  const currentEstimate = estimateGenerationCredits(DEFAULT_PROVIDER.id, { mode: form.mode, config: currentConfig }, history);
  const estimatedBalanceAfter = providerCredit.credits === null
    ? null
    : {
        minimum: Math.max(0, providerCredit.credits - currentEstimate.maximum),
        maximum: Math.max(0, providerCredit.credits - currentEstimate.minimum),
      };

  return (
    <div className="app-shell">
      <aside className="rail">
        <button className="brand-mark" onClick={() => navigate("create")} aria-label="Clawnsole home">
          <span>C</span>
        </button>
        <nav className="rail-nav" aria-label="Primary navigation">
          <button className={section === "create" ? "active" : ""} onClick={() => navigate("create")}>
            <WandSparkles size={20} />
            <span>Create</span>
          </button>
          <button className={section === "library" ? "active" : ""} onClick={() => navigate("library")}>
            <LibraryBig size={20} />
            <span>Library</span>
            {workingCount > 0 && <b>{workingCount}</b>}
          </button>
        </nav>
        <div className="rail-bottom">
          <div className="slow-badge" title="Take it slow. Make it good."><PawPrint size={17} /></div>
          <button className={section === "settings" ? "active" : ""} onClick={() => navigate("settings")}>
            <Settings2 size={20} />
            <span>Settings</span>
          </button>
        </div>
      </aside>

      <main className="workspace">
        <header className="topbar">
          <button className="wordmark" onClick={() => navigate("create")}>Clawnsole<span>®</span></button>
          <div className="topbar-actions">
            <div className="model-switcher-wrap">
              <button className="model-switcher" onClick={() => setModelMenuOpen((open) => !open)} aria-expanded={modelMenuOpen}>
                <CircleDot size={15} />
                <span>{DEFAULT_PROVIDER.modelLabel}</span>
                <ChevronDown size={15} />
              </button>
              {modelMenuOpen && (
                <div className="model-menu">
                  <button onClick={() => setModelMenuOpen(false)}>
                    <span className="provider-monogram">BFL</span>
                    <span><strong>FLUX 3</strong><small>Black Forest Labs · active</small></span>
                    <Check size={16} />
                  </button>
                  <p>New providers will appear here without changing your library.</p>
                </div>
              )}
            </div>
            <button
              className={`credit-status ${providerCredit.error ? "error" : ""}`}
              onClick={() => void refreshProviderCredits()}
              disabled={!hasApiKey || providerCredit.loading}
              title={providerCredit.error || "Refresh Black Forest Labs credits"}
            >
              <Coins size={16} />
              <span>
                <strong>{providerCredit.credits === null ? (hasApiKey ? "—" : "No key") : formatCredits(providerCredit.credits)}</strong>
                <small>{DEFAULT_PROVIDER.billing.creditLabel}</small>
              </span>
              <RefreshCw className={providerCredit.loading ? "spinning" : ""} size={13} />
            </button>
            <button className={`key-status ${hasApiKey ? "connected" : ""}`} onClick={() => navigate("settings")}>
              <KeyRound size={16} />
              <span>{hasApiKey ? "API key set" : "Add API key"}</span>
            </button>
          </div>
        </header>

        {section === "create" && (
          <div className="create-view">
            <section className="composer-column">
              <div className="view-heading">
                <div>
                  <p className="eyebrow"><Sparkles size={14} /> FLUX 3 studio</p>
                  <h1>Make it move<span>.</span></h1>
                  <p>Direct one continuous moment, pin the important frames, and let Clawnsole mind the render.</p>
                </div>
                <div className="claw-ornament" aria-hidden="true"><i /><i /><i /></div>
              </div>

              <form className="composer" onSubmit={submitGeneration}>
                <div className="mode-tabs" role="tablist" aria-label="Generation mode">
                  {DEFAULT_PROVIDER.modes.map((mode) => (
                    <button
                      key={mode.id}
                      type="button"
                      role="tab"
                      aria-selected={form.mode === mode.id}
                      className={form.mode === mode.id ? "active" : ""}
                      onClick={() => setMode(mode.id)}
                    >
                      {mode.shortLabel}
                    </button>
                  ))}
                </div>

                {form.mode !== "draft_enhance" && (
                  <div className="prompt-field">
                    <label htmlFor="prompt">Direction</label>
                    <textarea
                      id="prompt"
                      value={form.prompt}
                      onChange={(event) => setForm((current) => ({ ...current, prompt: event.target.value }))}
                      placeholder="A single continuous shot of a sleepy sloth crossing a sunlit hotel lobby, walnut paneling, amber afternoon light, slow dolly in…"
                      rows={6}
                    />
                    <div className="prompt-footer">
                      <span>{form.prompt.length.toLocaleString()} characters</span>
                      <button type="button" onClick={() => setForm((current) => ({ ...current, prompt: "One single continuous shot. No cuts, edits, or transitions. " + current.prompt }))}>
                        <Link2 size={13} /> One-shot prefix
                      </button>
                    </div>
                  </div>
                )}

                {form.mode === "i2v" && (
                  <KeyframeEditor
                    frames={keyframes}
                    exactTiming={form.exactTiming}
                    onExactTiming={(exactTiming) => setForm((current) => ({ ...current, exactTiming }))}
                    onFiles={addFrameFiles}
                    onAddUrl={addUrlFrame}
                    onUpdate={updateFrame}
                    onRemove={removeFrame}
                  />
                )}

                {form.mode === "v2v" && (
                  <SourceEditor
                    title="Source clip"
                    description="FLUX 3 continues naturally from the final frames of this clip."
                    accept="video/mp4,video/quicktime"
                    icon={<FileVideo size={22} />}
                    source={videoSource}
                    onFile={onVideoFile}
                    onUrl={(url) => setVideoSource({ url })}
                    onClear={() => setVideoSource({ url: "" })}
                  />
                )}

                {form.mode === "draft_enhance" && (
                  <SourceEditor
                    title="Draft cache"
                    description="Use the .bin bundle from a prior draft for the same generation at full quality."
                    accept=".bin,application/octet-stream"
                    icon={<ArrowDownToLine size={22} />}
                    source={draftSource}
                    onFile={onDraftFile}
                    onUrl={(url) => setDraftSource({ url })}
                    onClear={() => setDraftSource({ url: "" })}
                  />
                )}

                {form.mode !== "draft_enhance" && (
                  <div className="control-section">
                    <div className="section-label"><span>Frame</span><small>Output shape</small></div>
                    <div className="aspect-grid" aria-label="Aspect ratio">
                      {DEFAULT_PROVIDER.aspectRatios.map((ratio) => (
                        <button
                          type="button"
                          key={ratio}
                          className={form.aspectRatio === ratio ? "active" : ""}
                          onClick={() => setForm((current) => ({ ...current, aspectRatio: ratio }))}
                        >
                          <span className={`ratio-shape ratio-${ratio.replace(":", "-")}`} />
                          {ratio === "auto" ? "Auto" : ratio}
                        </button>
                      ))}
                    </div>
                  </div>
                )}

                <div className="paired-controls">
                  {form.mode !== "draft_enhance" && (
                    <div className="control-block duration-control">
                      <div className="control-heading"><span><Clock3 size={16} /> Duration</span><b>{form.duration === "auto" ? "Auto" : `${form.durationSeconds}s`}</b></div>
                      <div className="duration-row">
                        <button type="button" className={form.duration === "auto" ? "active" : ""} onClick={() => setForm((current) => ({ ...current, duration: "auto" }))}>Auto</button>
                        <button type="button" className={form.duration !== "auto" ? "active" : ""} onClick={() => setForm((current) => ({ ...current, duration: current.durationSeconds }))}>{form.durationSeconds} sec</button>
                      </div>
                      <input
                        aria-label="Duration in seconds"
                        type="range"
                        min={DEFAULT_PROVIDER.duration.min}
                        max={DEFAULT_PROVIDER.duration.max}
                        value={form.durationSeconds}
                        disabled={form.duration === "auto"}
                        onChange={(event) => setForm((current) => ({ ...current, durationSeconds: Number(event.target.value), duration: Number(event.target.value) }))}
                      />
                      <div className="range-labels"><span>5 sec</span><span>20 sec</span></div>
                    </div>
                  )}

                  <div className="control-block resolution-control">
                    <div className="control-heading"><span><Film size={16} /> Finish</span></div>
                    <div className="resolution-options">
                      {DEFAULT_PROVIDER.resolutions.map((resolution) => (
                        <button
                          type="button"
                          key={resolution.id}
                          className={form.resolution === resolution.id ? "active" : ""}
                          disabled={form.draft && resolution.id === "fhd"}
                          onClick={() => setForm((current) => ({ ...current, resolution: resolution.id }))}
                        >
                          <span>{resolution.label}</span><small>{resolution.detail}</small>
                        </button>
                      ))}
                    </div>
                  </div>
                </div>

                {form.mode !== "draft_enhance" && (
                  <div className="switch-row">
                    <button type="button" className={`switch-card ${form.generateAudio ? "on" : ""}`} onClick={() => setForm((current) => ({ ...current, generateAudio: !current.generateAudio }))} aria-pressed={form.generateAudio}>
                      <span className="switch-icon"><Volume2 size={18} /></span>
                      <span><strong>Synchronized audio</strong><small>Dialogue, ambience, and sound</small></span>
                      <i><b /></i>
                    </button>
                    <button
                      type="button"
                      className={`switch-card ${form.draft ? "on" : ""}`}
                      onClick={() => setForm((current) => ({
                        ...current,
                        draft: !current.draft,
                        resolution: current.draft ? current.resolution : "hd",
                      }))}
                      aria-pressed={form.draft}
                    >
                      <span className="switch-icon"><Sparkles size={18} /></span>
                      <span><strong>Fast draft</strong><small>Preview now, enhance later</small></span>
                      <i><b /></i>
                    </button>
                  </div>
                )}

                <div className={`advanced-panel ${advancedOpen ? "open" : ""}`}>
                  <button type="button" className="advanced-toggle" onClick={() => setAdvancedOpen((open) => !open)} aria-expanded={advancedOpen}>
                    <span><SlidersHorizontal size={16} /> Advanced controls</span>
                    <ChevronDown size={16} />
                  </button>
                  {advancedOpen && (
                    <div className="advanced-content">
                      <div className="safety-control">
                        <div className="control-heading">
                          <span><ShieldCheck size={16} /> Safety tolerance</span>
                          <b>{form.safetyTolerance} / 4</b>
                        </div>
                        <input
                          type="range"
                          aria-label="Safety tolerance"
                          min={DEFAULT_PROVIDER.safety.min}
                          max={DEFAULT_PROVIDER.safety.max}
                          value={form.safetyTolerance}
                          onChange={(event) => setForm((current) => ({ ...current, safetyTolerance: Number(event.target.value) }))}
                        />
                        <div className="range-labels"><span>Strictest</span><span>More permissive</span></div>
                      </div>
                      <div className="version-note">
                        <span>Model version</span><strong>latest</strong><small>Dated releases will appear here when BFL publishes them.</small>
                      </div>
                    </div>
                  )}
                </div>

                <div className="cost-preview">
                  <div className="cost-preview-main">
                    <span className="cost-preview-icon"><Coins size={19} /></span>
                    <span><small>Estimated BFL charge</small><strong>{formatCreditRange(currentEstimate.minimum, currentEstimate.maximum)} credits</strong></span>
                    <b>{formatUsdRange(currentEstimate.minimum, currentEstimate.maximum)}</b>
                  </div>
                  <div className="cost-preview-balance">
                    <span><small>Available now</small><strong>{providerCredit.credits === null ? (providerCredit.error ? "Unavailable" : hasApiKey ? "Checking…" : "Add API key") : `${formatCredits(providerCredit.credits)} credits`}</strong></span>
                    <span><small>Estimated after</small><strong>{estimatedBalanceAfter ? `${formatCreditRange(estimatedBalanceAfter.minimum, estimatedBalanceAfter.maximum)} credits` : "—"}</strong></span>
                  </div>
                  <p>{form.draft && form.mode !== "draft_enhance" ? "Drafts use BFL’s HD draft tier. " : ""}{currentEstimate.basis === "provider-history" ? "Calibrated from BFL charges in your history." : "Based on BFL’s published per-second rate."} BFL’s exact charge replaces the estimate on submit. <a href={DEFAULT_PROVIDER.billing.pricingUrl} target="_blank" rel="noreferrer">Rate card ↗</a></p>
                </div>

                <div className="submit-row">
                  <div className="submit-note">
                    <PawPrint size={18} />
                    <span>{hasApiKey ? "Ready when you are" : "API key needed"}<small>{form.draft ? "Fast draft enabled" : `${form.resolution.toUpperCase()} · ${form.duration === "auto" ? "auto length" : `${form.durationSeconds} seconds`}`}</small></span>
                  </div>
                  <button className="generate-button" type="submit">
                    <Play size={17} fill="currentColor" /> Generate video
                  </button>
                </div>
              </form>
            </section>

            <aside className="activity-column">
              <div className="activity-heading">
                <div><p className="eyebrow">On the branch</p><h2>Recent work</h2></div>
                <button onClick={() => navigate("library")}>View library <ChevronDown size={14} /></button>
              </div>
              <div className="activity-list">
                {history.length === 0 ? (
                  <div className="empty-activity">
                    <div className="empty-film"><Film size={30} /><i /></div>
                    <h3>A quiet branch.</h3>
                    <p>Your generations will gather here with live progress and playback.</p>
                  </div>
                ) : history.slice(0, 5).map((item) => (
                  <ActivityCard
                    key={item.localId}
                    item={item}
                    onSave={() => void saveMedia(item)}
                    onReuse={() => reuseGeneration(item)}
                    onEnhance={() => enhanceDraft(item)}
                  />
                ))}
              </div>
              <div className="activity-summary">
                <span><b>{history.length}</b> kept locally</span>
                <span><b>{readyCount}</b> complete</span>
                <span><b>{workingCount}</b> moving</span>
                <span><b>{formatCredits(spentCredits)}</b> credits spent</span>
              </div>
            </aside>
          </div>
        )}

        {section === "library" && (
          <LibraryView
            history={filteredHistory}
            total={history.length}
            filter={libraryFilter}
            search={search}
            onSearch={setSearch}
            onFilter={setFilter}
            onCreate={() => navigate("create")}
            onSave={(item) => void saveMedia(item)}
            onReuse={reuseGeneration}
            onEnhance={enhanceDraft}
            onRemove={removeGeneration}
          />
        )}

        {section === "settings" && (
          <SettingsView
            keyDraft={keyDraft}
            keySet={hasApiKey}
            showKey={showKey}
            check={keyCheck}
            storage={storage}
            onKeyDraft={setKeyDraft}
            onShowKey={() => setShowKey((show) => !show)}
            onSave={() => void saveKey()}
            onVerify={() => void verifyKey()}
            onRemoveKey={() => void removeKey()}
            onClearHistory={() => void clearHistoryAction()}
            onClearPreferences={() => void clearPreferencesAction()}
            onClearAll={() => void clearEverything()}
          />
        )}
      </main>

      {toast && <div className="toast" role="status"><PawPrint size={17} /> {toast}</div>}
    </div>
  );
}

function KeyframeEditor({
  frames,
  exactTiming,
  onExactTiming,
  onFiles,
  onAddUrl,
  onUpdate,
  onRemove,
}: {
  frames: KeyframeDraft[];
  exactTiming: boolean;
  onExactTiming(value: boolean): void;
  onFiles(event: ChangeEvent<HTMLInputElement>): void;
  onAddUrl(): void;
  onUpdate(id: string, patch: Partial<KeyframeDraft>): void;
  onRemove(id: string): void;
}) {
  return (
    <div className="keyframe-editor">
      <div className="keyframe-heading">
        <div><span>Keyframes</span><small>1–10 images · first and last frames are pinned</small></div>
        <label className="timing-check">
          <input type="checkbox" checked={exactTiming} onChange={(event) => onExactTiming(event.target.checked)} />
          Exact timing
        </label>
      </div>
      <div className="keyframe-strip">
        {frames.map((frame, index) => (
          <div className="keyframe-card" key={frame.id}>
            {frame.source ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={frame.source} alt="" />
            ) : (
              <div className="url-frame"><Link2 size={20} /></div>
            )}
            <span className="frame-position">{index === 0 ? "Start" : index === frames.length - 1 ? "Last" : `Frame ${index + 1}`}</span>
            <button type="button" className="remove-frame" onClick={() => onRemove(frame.id)} aria-label={`Remove ${frame.label}`}><X size={14} /></button>
            {frame.kind === "url" && (
              <input
                aria-label={`Frame ${index + 1} URL`}
                type="url"
                value={frame.source}
                placeholder="https://…"
                onChange={(event) => onUpdate(frame.id, { source: event.target.value, label: event.target.value || "Reference URL" })}
              />
            )}
            {exactTiming && (
              <label className="frame-time"><input type="number" min="0" max="20" step="0.1" value={frame.seconds} onChange={(event) => onUpdate(frame.id, { seconds: Number(event.target.value) })} /> sec</label>
            )}
          </div>
        ))}
        {frames.length < DEFAULT_PROVIDER.maxKeyframes && (
          <label className="add-frame-card">
            <ImagePlus size={22} />
            <span>Add images</span>
            <small>PNG, JPG, WEBP</small>
            <input type="file" accept="image/png,image/jpeg,image/webp" multiple onChange={onFiles} />
          </label>
        )}
      </div>
      <button className="add-url-button" type="button" onClick={onAddUrl} disabled={frames.length >= DEFAULT_PROVIDER.maxKeyframes}><Plus size={14} /> Add image URL</button>
    </div>
  );
}

function SourceEditor({
  title,
  description,
  accept,
  icon,
  source,
  onFile,
  onUrl,
  onClear,
}: {
  title: string;
  description: string;
  accept: string;
  icon: React.ReactNode;
  source: SourceDraft;
  onFile(event: ChangeEvent<HTMLInputElement>): void;
  onUrl(value: string): void;
  onClear(): void;
}) {
  const selected = source.file || source.storedSource;
  return (
    <div className="source-editor">
      <div className="source-copy"><span>{icon}</span><div><strong>{title}</strong><small>{description}</small></div></div>
      {selected ? (
        <div className="source-selected">
          {source.previewUrl ? <video src={source.previewUrl} muted playsInline /> : <div className="source-file-icon"><HardDrive size={22} /></div>}
          <div><strong>{source.file?.name || source.storedSource?.label || "Linked source"}</strong><small>{source.file ? formatBytes(source.file.size) : source.storedSource?.bytes ? `${formatBytes(source.storedSource.bytes)} · retained locally` : source.url}</small></div>
          <button type="button" onClick={onClear} aria-label="Remove source"><X size={16} /></button>
        </div>
      ) : (
        <div className="source-inputs">
          <label><UploadCloud size={18} /> Choose file<input type="file" accept={accept} onChange={onFile} /></label>
          <span>or</span>
          <div><Link2 size={16} /><input type="url" value={source.url} placeholder="Paste a hosted URL" onChange={(event) => onUrl(event.target.value)} /></div>
        </div>
      )}
    </div>
  );
}

function ActivityCard({ item, onSave, onReuse, onEnhance }: { item: StoredGeneration; onSave(): void; onReuse(): void; onEnhance(): void }) {
  const working = isWorking(item);
  const failed = STATUS_FAILURES.has(item.status);
  const mediaUrl = generationMediaUrl(item);
  const inputPreview = generationInputPreview(item);
  const creditRange = storedCreditRange(item);
  return (
    <article className={`activity-card ${working ? "working" : ""} ${failed ? "failed" : ""}`}>
      <div className="activity-preview">
        {mediaUrl ? (
          // Generated media does not include a provider-supplied caption track.
          // eslint-disable-next-line jsx-a11y/media-has-caption
          <video aria-label="Generated video" src={mediaUrl} controls playsInline preload="metadata" />
        ) : inputPreview ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={inputPreview} alt="Retained generation input" />
        ) : (
          <div className="preview-placeholder"><Film size={23} /><span>{item.config.aspectRatio}</span></div>
        )}
        <span className={`status-badge ${working ? "working" : failed ? "failed" : "ready"}`}>
          {working && <LoaderCircle size={11} />}
          {failed ? "Needs attention" : item.status === "Ready" ? "Ready" : item.status === "submitting" ? "Sending" : "Rendering"}
        </span>
      </div>
      <div className="activity-copy">
        <div className="activity-meta"><span>{modeLabel(item.mode)}</span><time>{formatRelativeTime(item.createdAt)}</time></div>
        <h3>{item.prompt}</h3>
        {creditRange && (
          <div className={`activity-cost ${creditRange.actual ? "actual" : "estimated"}`}>
            <Coins size={12} />
            <span>{creditRange.actual ? "BFL charge" : "Estimated"}</span>
            <strong>{formatCreditRange(creditRange.minimum, creditRange.maximum)} cr · {formatUsdRange(creditRange.minimum, creditRange.maximum)}</strong>
          </div>
        )}
        {working && (
          <div className="progress-wrap">
            <div className={`progress-track ${item.progress == null ? "indeterminate" : ""}`}><i style={item.progress != null ? { width: `${Math.max(4, item.progress)}%` } : undefined} /></div>
            <span>{item.progress != null ? `${item.progress}%` : "In motion"}</span>
          </div>
        )}
        {failed && <p className="compact-error"><AlertTriangle size={13} /> {item.error || item.status}</p>}
        <div className="activity-actions">
          {mediaUrl && <button onClick={onSave}><FolderDown size={14} /> Save</button>}
          {item.draftCacheUrl && <button onClick={onEnhance}><Sparkles size={14} /> Enhance</button>}
          <button onClick={onReuse}><RotateCcw size={14} /> Reuse inputs</button>
        </div>
      </div>
    </article>
  );
}

function LibraryView({
  history,
  total,
  filter,
  search,
  onSearch,
  onFilter,
  onCreate,
  onSave,
  onReuse,
  onEnhance,
  onRemove,
}: {
  history: StoredGeneration[];
  total: number;
  filter: LibraryFilter;
  search: string;
  onSearch(value: string): void;
  onFilter(value: LibraryFilter): void;
  onCreate(): void;
  onSave(item: StoredGeneration): void;
  onReuse(item: StoredGeneration): void;
  onEnhance(item: StoredGeneration): void;
  onRemove(id: string): void;
}) {
  const filters: Array<{ id: LibraryFilter; label: string }> = [
    { id: "all", label: "All" },
    { id: "working", label: "In progress" },
    { id: "ready", label: "Ready" },
    { id: "failed", label: "Needs attention" },
  ];
  return (
    <section className="library-view">
      <div className="page-heading">
        <div><p className="eyebrow"><LibraryBig size={14} /> Local history</p><h1>Your films<span>.</span></h1><p>Generation metadata, reference inputs, and completed videos stay together on this machine.</p></div>
        <button className="primary-action" onClick={onCreate}><Plus size={17} /> New generation</button>
      </div>
      <div className="library-toolbar">
        <div className="filter-tabs">
          {filters.map((item) => <button key={item.id} className={filter === item.id ? "active" : ""} onClick={() => onFilter(item.id)}>{item.label}</button>)}
        </div>
        <label className="search-field"><span className="sr-only">Search prompts</span><input value={search} onChange={(event) => onSearch(event.target.value)} placeholder="Search prompts" /></label>
      </div>
      {history.length ? (
        <div className="generation-grid">
          {history.map((item) => <GenerationCard key={item.localId} item={item} onSave={() => onSave(item)} onReuse={() => onReuse(item)} onEnhance={() => onEnhance(item)} onRemove={() => onRemove(item.localId)} />)}
        </div>
      ) : (
        <div className="library-empty">
          <div><Images size={35} /><i /><i /></div>
          <h2>{total ? "Nothing matches that view." : "No films just yet."}</h2>
          <p>{total ? "Try another filter or a broader prompt search." : "Your first generation will arrive here with its settings and live status."}</p>
          {!total && <button onClick={onCreate}><WandSparkles size={16} /> Create your first</button>}
        </div>
      )}
    </section>
  );
}

function GenerationCard({ item, onSave, onReuse, onEnhance, onRemove }: { item: StoredGeneration; onSave(): void; onReuse(): void; onEnhance(): void; onRemove(): void }) {
  const working = isWorking(item);
  const failed = STATUS_FAILURES.has(item.status);
  const creditRange = storedCreditRange(item);
  const mediaUrl = generationMediaUrl(item);
  const inputPreview = generationInputPreview(item);
  return (
    <article className="generation-card">
      <div className="generation-media">
        {mediaUrl ? (
          // Generated media does not include a provider-supplied caption track.
          // eslint-disable-next-line jsx-a11y/media-has-caption
          <video aria-label="Generated video" controls playsInline preload="metadata" src={mediaUrl} />
        ) : inputPreview ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={inputPreview} alt="Retained generation input" />
        ) : (
          <div className="generation-placeholder">
            {working ? <LoaderCircle size={32} /> : failed ? <AlertTriangle size={30} /> : <Film size={31} />}
            <span>{item.deliveryExpired ? "Delivery expired" : working ? "Rendering" : failed ? "No output" : "Saved metadata"}</span>
          </div>
        )}
        <span className={`status-badge ${working ? "working" : failed ? "failed" : "ready"}`}>{working ? "In progress" : failed ? "Needs attention" : "Ready"}</span>
        {working && <div className="card-progress"><i style={item.progress != null ? { width: `${Math.max(4, item.progress)}%` } : undefined} /></div>}
      </div>
      <div className="generation-body">
        <div className="generation-kicker"><span>{modeLabel(item.mode)}</span><time>{formatRelativeTime(item.createdAt)}</time></div>
        <h2>{item.prompt}</h2>
        <div className="config-line">
          <span>{item.config.aspectRatio}</span><span>{item.config.duration === "auto" ? "Auto" : `${item.config.duration}s`}</span><span>{item.config.resolution.toUpperCase()}</span>{item.config.generateAudio && <span><AudioLines size={12} /> Audio</span>}
        </div>
        {creditRange && (
          <div className={`generation-cost ${creditRange.actual ? "actual" : "estimated"}`}>
            <div><Coins size={15} /><span><small>{creditRange.actual ? "BFL charge" : "Estimated charge"}</small><strong>{formatCreditRange(creditRange.minimum, creditRange.maximum)} credits</strong></span></div>
            <b>{formatUsdRange(creditRange.minimum, creditRange.maximum)}</b>
            {typeof item.creditsBefore === "number" && typeof item.creditsAfter === "number" && (
              <p>{formatCredits(item.creditsBefore)} → {formatCredits(item.creditsAfter)} credits available</p>
            )}
          </div>
        )}
        {item.error && <p className="card-error"><AlertTriangle size={14} /> {item.error}</p>}
        {item.deliveryExpired && <p className="expiry-note"><Clock3 size={13} /> {item.resultAsset ? "BFL’s source link expired; your local video remains." : "BFL’s delivery link expired; the generation record remains."}</p>}
        <div className="generation-actions">
          {mediaUrl && <button className="save-button" onClick={onSave}><FolderDown size={15} /> Save to Finder</button>}
          {item.draftCacheUrl && <button onClick={onEnhance}><Sparkles size={15} /> Enhance</button>}
          <button onClick={onReuse}><RotateCcw size={15} /> Reuse</button>
          <button className="icon-danger" onClick={onRemove} aria-label="Delete history record"><Trash2 size={15} /></button>
        </div>
      </div>
    </article>
  );
}

function SettingsView({
  keyDraft,
  keySet,
  showKey,
  check,
  storage,
  onKeyDraft,
  onShowKey,
  onSave,
  onVerify,
  onRemoveKey,
  onClearHistory,
  onClearPreferences,
  onClearAll,
}: {
  keyDraft: string;
  keySet: boolean;
  showKey: boolean;
  check: { state: "idle" | "checking" | "valid" | "error"; credits?: number; message?: string };
  storage: LocalDataStats;
  onKeyDraft(value: string): void;
  onShowKey(): void;
  onSave(): void;
  onVerify(): void;
  onRemoveKey(): void;
  onClearHistory(): void;
  onClearPreferences(): void;
  onClearAll(): void;
}) {
  const totalBytes = storage.bytes + storage.assetBytes;
  return (
    <section className="settings-view">
      <div className="page-heading">
        <div><p className="eyebrow"><Settings2 size={14} /> Personal setup</p><h1>Settings<span>.</span></h1><p>Connect your provider and keep a close eye on Clawnsole’s local data file.</p></div>
      </div>
      <div className="settings-layout">
        <div className="settings-main">
          <section className="settings-section">
            <div className="settings-section-heading"><span className="settings-icon"><KeyRound size={20} /></span><div><h2>Black Forest Labs</h2><p>Your key stays on this machine and is never returned to the browser.</p></div>{keySet && <span className="connected-label"><Check size={13} /> Connected</span>}</div>
            <div className="api-key-field">
              <label htmlFor="api-key">BFL API key</label>
              <div><input id="api-key" type={showKey ? "text" : "password"} autoComplete="off" value={keyDraft} onChange={(event) => onKeyDraft(event.target.value)} placeholder={keySet ? "Saved — paste a replacement" : "bfl_••••••••••••••••"} /><button onClick={onShowKey} type="button" aria-label={showKey ? "Hide API key" : "Show API key"}>{showKey ? <EyeOff size={17} /> : <Eye size={17} />}</button></div>
              <small>Create a project key in the BFL dashboard. Clawnsole writes it to the local data file with owner-only permissions.</small>
            </div>
            <div className="remember-row"><HardDrive size={18} /><span><strong>Stored locally, server-side</strong><small>The browser receives only whether a key exists, never the secret itself.</small></span></div>
            {check.state !== "idle" && (
              <div className={`key-check-result ${check.state}`}>
                {check.state === "checking" && <><LoaderCircle size={15} /> Checking with BFL…</>}
                {check.state === "valid" && <><Check size={15} /> Key verified · {check.credits?.toLocaleString()} credits available</>}
                {check.state === "error" && <><AlertTriangle size={15} /> {check.message}</>}
              </div>
            )}
            <div className="settings-actions"><button className="primary-action" onClick={onSave}><KeyRound size={16} /> {keySet ? "Replace key" : "Save key"}</button><button onClick={onVerify} disabled={(!keyDraft && !keySet) || check.state === "checking"}><RefreshCw size={15} /> Verify & check credits</button>{keySet && <button className="text-danger" onClick={onRemoveKey}>Remove</button>}</div>
          </section>

          <section className="settings-section storage-section">
            <div className="settings-section-heading"><span className="settings-icon clay"><HardDrive size={20} /></span><div><h2>Local project data</h2><p>Compact JSON plus retained reference inputs and finished videos.</p></div><span className="storage-total">{formatBytes(totalBytes)}</span></div>
            <div className="file-stats-grid">
              <div><strong>{formatBytes(storage.bytes)}</strong><span>Metadata</span></div>
              <div><strong>{formatBytes(storage.assetBytes)}</strong><span>{storage.assets.toLocaleString()} retained assets</span></div>
              <div><strong>{storage.records.toLocaleString()}</strong><span>Generations</span></div>
              <div><strong>{storage.lastUpdated ? formatRelativeTime(storage.lastUpdated) : "Not yet"}</strong><span>Last write</span></div>
            </div>
            <div className="data-path"><span>Data file</span><code>{storage.path || ".clawnsole/clawnsole.json"}</code></div>
          </section>
        </div>
        <aside className="settings-side">
          <section>
            <PawPrint size={25} />
            <h3>Room to stretch.</h3>
            <p>History is uncapped. Completed videos and uploaded references stay local until their records are removed.</p>
          </section>
          <section className="clear-section">
            <h3>Clear local data</h3>
            <p>These actions update only Clawnsole data on this machine.</p>
            <button onClick={onClearHistory}><Trash2 size={15} /><span><strong>Clear history</strong><small>Records, retained inputs, and videos</small></span></button>
            <button onClick={onClearPreferences}><RefreshCw size={15} /><span><strong>Reset preferences</strong><small>Navigation and filter state</small></span></button>
            <button className="danger-row" onClick={onClearAll}><AlertTriangle size={15} /><span><strong>Delete all local data</strong><small>History, assets, settings, and API key</small></span></button>
          </section>
          <a className="docs-link" href={VIDEO_PROVIDERS.bfl.docsUrl} target="_blank" rel="noreferrer"><span><ExternalLink size={16} /><strong>FLUX 3 documentation</strong></span><ChevronDown size={15} /></a>
        </aside>
      </div>
    </section>
  );
}
