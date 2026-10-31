import 'bfl_api.dart';
import 'models.dart';
import 'provider_catalog.dart';

/// The narrowly supported fal families, audited against their public OpenAPI.
enum FalModelFamily { fluxMax, flux, h3, kling, wan, ltx }

/// One exact fal endpoint and its provider-neutral capabilities.
///
/// These are intentionally explicit: arbitrary catalog routes must never become
/// create-ready through guessed endpoint names or silently dropped controls.
class FalRouteSpec extends VideoModelDefinition {
  const FalRouteSpec({
    required super.id,
    required super.canonicalModelId,
    required super.label,
    required super.description,
    required super.modes,
    required super.aspectRatios,
    required super.resolutions,
    required super.minDuration,
    required super.maxDuration,
    required super.durationStep,
    required super.maxKeyframes,
    required super.usdPerSecond,
    required super.supportsAudio,
    required this.family,
    required this.listUsdPerSecond,
    super.referenceUsdPerSecond,
    super.supportsStartFrame,
    super.supportsEndFrame,
    super.supportsSeed,
    super.supportsAutoDuration,
    super.maxPromptCharacters,
    super.maxInputImageBytes,
    super.maxDurationByResolution,
    super.promptOptionalModes,
  });

  final FalModelFamily family;
  final Map<String, double> listUsdPerSecond;
  String get endpoint => id;

  Map<String, Object?> buildPayload(Map<String, Object?> input) {
    final imageRoute = modes.single == VideoMode.i2v;
    final mode = input['mode']?.toString();
    if (mode != null && mode != modes.single.wireValue) {
      _invalid('This fal route does not support $mode.');
    }
    for (final key in const <String>[
      'reference_images',
      'reference_videos',
      'reference_audios',
      'start_video',
      'input_video',
    ]) {
      final value = input[key];
      if (value is List && value.isNotEmpty ||
          value is String && value.isNotEmpty) {
        _invalid('This fal route does not support $key.');
      }
    }
    final frames = <String>[];
    final rawFrames = input['keyframes'];
    if (rawFrames != null && rawFrames is! List) {
      _invalid('Pinned frames must be a list of image sources.');
    }
    if (rawFrames is List) {
      for (final frame in rawFrames) {
        final value = frame is List && frame.length == 2 ? frame[1] : frame;
        if (value is! String || value.trim().isEmpty) {
          _invalid('Pinned frames must contain an image source.');
        }
        frames.add(value);
      }
    }
    if (frames.length > maxKeyframes || imageRoute && frames.isEmpty) {
      _invalid(
        imageRoute
            ? 'This fal route requires 1–$maxKeyframes pinned images.'
            : 'This fal text route does not accept pinned images.',
      );
    }
    final prompt = input['prompt']?.toString().trim() ?? '';
    if (prompt.isEmpty && !promptOptionalModes.contains(modes.single)) {
      _invalid('A prompt is required for this fal route.');
    }
    if (maxPromptCharacters != null && prompt.length > maxPromptCharacters!) {
      _invalid('The prompt exceeds this fal route’s character limit.');
    }
    final resolution = input['resolution']?.toString() ?? resolutions.first.id;
    if (!listUsdPerSecond.containsKey(resolution)) {
      _invalid('This fal route does not support resolution $resolution.');
    }
    final ratio = input['aspect_ratio']?.toString() ?? aspectRatios.first;
    if (!aspectRatios.contains(ratio)) {
      _invalid('This fal route does not support aspect ratio $ratio.');
    }
    final duration = input['duration'] ?? minDuration;
    if (duration == 'auto') {
      if (!supportsAutoDuration) {
        _invalid('This fal route requires a fixed duration.');
      }
    } else if (duration is! num ||
        !duration.isFinite ||
        duration != duration.roundToDouble() ||
        duration < minDuration ||
        duration > maxDurationFor(resolution) ||
        (duration - minDuration) % durationStep != 0) {
      _invalid(
        'The duration is not supported by this fal route and resolution.',
      );
    }
    final seed = input['seed'];
    if (seed != null && supportsSeed) {
      if (seed is! int ||
          family == FalModelFamily.wan && (seed < 0 || seed > 2147483647)) {
        _invalid('The seed is outside this fal route’s supported range.');
      }
    }
    final wireResolution = family == FalModelFamily.h3
        ? const <String, String>{
            'sd': '480P',
            'hd': '768P',
            'fhd': '1080P',
          }[resolution]
        : const <String, String>{
            'sd': '480p',
            'hd': '720p',
            'fhd': '1080p',
            'qhd': '1440p',
            '4k': '2160p',
          }[resolution];
    final payload = <String, Object?>{
      if (prompt.isNotEmpty) 'prompt': prompt,
      'duration': family == FalModelFamily.wan && duration == 'auto'
          ? null
          : duration,
      'resolution': wireResolution,
      if (!(imageRoute &&
          (family == FalModelFamily.h3 || family == FalModelFamily.kling)))
        'aspect_ratio': family == FalModelFamily.wan && ratio == 'auto'
            ? 'adaptive'
            : ratio,
      if (supportsAudio)
        (family == FalModelFamily.wan ? 'audio' : 'generate_audio'):
            input['generate_audio'] != false,
      if (supportsSeed && seed != null) 'seed': seed,
      if (family == FalModelFamily.h3) 'prompt_expansion_mode': 'balanced',
      // Fixing fps to 25 preserves the full advertised Fast duration range.
      if (family == FalModelFamily.ltx) 'fps': 25,
    };
    if (frames.isNotEmpty) {
      payload[family == FalModelFamily.kling || family == FalModelFamily.wan
              ? 'start_image_url'
              : 'image_url'] =
          frames.first;
      if (frames.length > 1) payload['end_image_url'] = frames.last;
      if (frames.length > 2) {
        payload['middle_image_urls'] = frames.sublist(1, frames.length - 1);
      }
    }
    return payload;
  }

  Never _invalid(String message) =>
      throw ProviderException(message, status: 400);
}

const _falModel0 = FalRouteSpec(
  id: "blackforestlabs/flux-3-max/text-to-video",
  canonicalModelId: "flux-3-max",
  label: "FLUX 3 Max · Text",
  description: "Fal’s post-trained FLUX 3 video model with synchronized audio.",
  family: FalModelFamily.fluxMax,
  modes: <VideoMode>[VideoMode.t2v],
  aspectRatios: <String>[
    "auto",
    "21:9",
    "2:1",
    "16:9",
    "4:3",
    "1:1",
    "3:4",
    "9:16",
  ],
  resolutions: <VideoResolutionDefinition>[
    VideoResolutionDefinition("hd", "HD", "1280 × 720"),
    VideoResolutionDefinition("fhd", "Full HD", "1920 × 1080"),
  ],
  minDuration: 5,
  maxDuration: 20,
  durationStep: 1,
  maxKeyframes: 0,
  usdPerSecond: 0.17,
  supportsAudio: true,
  listUsdPerSecond: <String, double>{"hd": 0.17, "fhd": 0.29},
  supportsSeed: true,
);

const _falModel1 = FalRouteSpec(
  id: "blackforestlabs/flux-3-max/image-to-video",
  canonicalModelId: "flux-3-max",
  label: "FLUX 3 Max · Frames",
  description: "Fal’s post-trained FLUX 3 video model with synchronized audio.",
  family: FalModelFamily.fluxMax,
  modes: <VideoMode>[VideoMode.i2v],
  aspectRatios: <String>[
    "auto",
    "21:9",
    "2:1",
    "16:9",
    "4:3",
    "1:1",
    "3:4",
    "9:16",
  ],
  resolutions: <VideoResolutionDefinition>[
    VideoResolutionDefinition("hd", "HD", "1280 × 720"),
    VideoResolutionDefinition("fhd", "Full HD", "1920 × 1080"),
  ],
  minDuration: 5,
  maxDuration: 20,
  durationStep: 1,
  maxKeyframes: 2,
  usdPerSecond: 0.17,
  supportsAudio: true,
  listUsdPerSecond: <String, double>{"hd": 0.17, "fhd": 0.29},
  referenceUsdPerSecond: 0.17,
  supportsStartFrame: true,
  supportsEndFrame: true,
  supportsSeed: true,
);

const _falModel2 = FalRouteSpec(
  id: "blackforestlabs/flux-3/text-to-video",
  canonicalModelId: "flux-3",
  label: "FLUX 3 · Text",
  description:
      "FLUX 3 video with synchronized audio and upsampled output above 720p.",
  family: FalModelFamily.flux,
  modes: <VideoMode>[VideoMode.t2v],
  aspectRatios: <String>[
    "auto",
    "21:9",
    "2:1",
    "16:9",
    "4:3",
    "1:1",
    "3:4",
    "9:16",
  ],
  resolutions: <VideoResolutionDefinition>[
    VideoResolutionDefinition("hd", "HD", "1280 × 720"),
    VideoResolutionDefinition("fhd", "Full HD", "1920 × 1080"),
    VideoResolutionDefinition("qhd", "1440p", "2560 × 1440"),
    VideoResolutionDefinition("4k", "4K", "3840 × 2160"),
  ],
  minDuration: 5,
  maxDuration: 20,
  durationStep: 1,
  maxKeyframes: 0,
  usdPerSecond: 0.17,
  supportsAudio: true,
  listUsdPerSecond: <String, double>{
    "hd": 0.17,
    "fhd": 0.29,
    "qhd": 0.32,
    "4k": 0.47,
  },
  supportsAutoDuration: true,
);

const _falModel3 = FalRouteSpec(
  id: "blackforestlabs/flux-3/image-to-video",
  canonicalModelId: "flux-3",
  label: "FLUX 3 · Frames",
  description:
      "FLUX 3 video with synchronized audio and upsampled output above 720p.",
  family: FalModelFamily.flux,
  modes: <VideoMode>[VideoMode.i2v],
  aspectRatios: <String>[
    "auto",
    "21:9",
    "2:1",
    "16:9",
    "4:3",
    "1:1",
    "3:4",
    "9:16",
  ],
  resolutions: <VideoResolutionDefinition>[
    VideoResolutionDefinition("hd", "HD", "1280 × 720"),
    VideoResolutionDefinition("fhd", "Full HD", "1920 × 1080"),
    VideoResolutionDefinition("qhd", "1440p", "2560 × 1440"),
    VideoResolutionDefinition("4k", "4K", "3840 × 2160"),
  ],
  minDuration: 5,
  maxDuration: 20,
  durationStep: 1,
  maxKeyframes: 1,
  usdPerSecond: 0.17,
  supportsAudio: true,
  listUsdPerSecond: <String, double>{
    "hd": 0.17,
    "fhd": 0.29,
    "qhd": 0.32,
    "4k": 0.47,
  },
  referenceUsdPerSecond: 0.17,
  supportsStartFrame: true,
  supportsEndFrame: false,
  supportsAutoDuration: true,
);

const _falModel4 = FalRouteSpec(
  id: "minimax/h3-max/text-to-video",
  canonicalModelId: "minimax-h3-max",
  label: "MiniMax H3 Max · Text",
  description:
      "Fal’s post-trained MiniMax H3. Native audio is always enabled; output can exceed the requested duration by about 0.7 seconds.",
  family: FalModelFamily.h3,
  modes: <VideoMode>[VideoMode.t2v],
  aspectRatios: <String>["16:9", "21:9", "4:3", "1:1", "3:4", "9:16"],
  resolutions: <VideoResolutionDefinition>[
    VideoResolutionDefinition("hd", "768p", "Native 768 px short edge"),
    VideoResolutionDefinition("sd", "480p", "480 px short edge"),
    VideoResolutionDefinition("fhd", "Full HD", "1920 × 1080"),
  ],
  minDuration: 1,
  maxDuration: 15,
  durationStep: 1,
  maxKeyframes: 0,
  usdPerSecond: 0.08,
  supportsAudio: false,
  listUsdPerSecond: <String, double>{"hd": 0.08, "sd": 0.05, "fhd": 0.16},
  supportsSeed: true,
  maxPromptCharacters: 50000,
);

const _falModel5 = FalRouteSpec(
  id: "minimax/h3-max/image-to-video",
  canonicalModelId: "minimax-h3-max",
  label: "MiniMax H3 Max · Frames",
  description:
      "Fal’s post-trained MiniMax H3. Native audio is always enabled; output can exceed the requested duration by about 0.7 seconds.",
  family: FalModelFamily.h3,
  modes: <VideoMode>[VideoMode.i2v],
  aspectRatios: <String>["auto"],
  resolutions: <VideoResolutionDefinition>[
    VideoResolutionDefinition("hd", "768p", "Native 768 px short edge"),
    VideoResolutionDefinition("sd", "480p", "480 px short edge"),
    VideoResolutionDefinition("fhd", "Full HD", "1920 × 1080"),
  ],
  minDuration: 1,
  maxDuration: 15,
  durationStep: 1,
  maxKeyframes: 2,
  usdPerSecond: 0.08,
  supportsAudio: false,
  listUsdPerSecond: <String, double>{"hd": 0.08, "sd": 0.05, "fhd": 0.16},
  referenceUsdPerSecond: 0.08,
  supportsStartFrame: true,
  supportsEndFrame: true,
  supportsSeed: true,
  maxPromptCharacters: 50000,
);

const _falModel6 = FalRouteSpec(
  id: "minimax/h3-max-turbo/text-to-video",
  canonicalModelId: "minimax-h3-max-turbo",
  label: "MiniMax H3 Max Turbo · Text",
  description:
      "Faster fal-post-trained MiniMax H3. Native audio is always enabled; output can exceed the requested duration by about 0.7 seconds.",
  family: FalModelFamily.h3,
  modes: <VideoMode>[VideoMode.t2v],
  aspectRatios: <String>["16:9", "21:9", "4:3", "1:1", "3:4", "9:16"],
  resolutions: <VideoResolutionDefinition>[
    VideoResolutionDefinition("hd", "768p", "Native 768 px short edge"),
    VideoResolutionDefinition("sd", "480p", "480 px short edge"),
    VideoResolutionDefinition("fhd", "Full HD", "1920 × 1080"),
  ],
  minDuration: 1,
  maxDuration: 15,
  durationStep: 1,
  maxKeyframes: 0,
  usdPerSecond: 0.04,
  supportsAudio: false,
  listUsdPerSecond: <String, double>{"hd": 0.04, "sd": 0.025, "fhd": 0.08},
  supportsSeed: true,
  maxPromptCharacters: 50000,
);

const _falModel7 = FalRouteSpec(
  id: "minimax/h3-max-turbo/image-to-video",
  canonicalModelId: "minimax-h3-max-turbo",
  label: "MiniMax H3 Max Turbo · Frames",
  description:
      "Faster fal-post-trained MiniMax H3. Native audio is always enabled; output can exceed the requested duration by about 0.7 seconds.",
  family: FalModelFamily.h3,
  modes: <VideoMode>[VideoMode.i2v],
  aspectRatios: <String>["auto"],
  resolutions: <VideoResolutionDefinition>[
    VideoResolutionDefinition("hd", "768p", "Native 768 px short edge"),
    VideoResolutionDefinition("sd", "480p", "480 px short edge"),
    VideoResolutionDefinition("fhd", "Full HD", "1920 × 1080"),
  ],
  minDuration: 1,
  maxDuration: 15,
  durationStep: 1,
  maxKeyframes: 2,
  usdPerSecond: 0.04,
  supportsAudio: false,
  listUsdPerSecond: <String, double>{"hd": 0.04, "sd": 0.025, "fhd": 0.08},
  referenceUsdPerSecond: 0.04,
  supportsStartFrame: true,
  supportsEndFrame: true,
  supportsSeed: true,
  maxPromptCharacters: 50000,
);

const _falModel8 = FalRouteSpec(
  id: "kling/v4/text-to-video",
  canonicalModelId: "kling-4.0",
  label: "Kling 4.0 · Text",
  description: "Kling 4.0 video with native audio always enabled.",
  family: FalModelFamily.kling,
  modes: <VideoMode>[VideoMode.t2v],
  aspectRatios: <String>["16:9", "9:16", "1:1", "21:9"],
  resolutions: <VideoResolutionDefinition>[
    VideoResolutionDefinition("hd", "HD", "1280 × 720"),
    VideoResolutionDefinition("fhd", "Full HD", "1920 × 1080"),
  ],
  minDuration: 3,
  maxDuration: 30,
  durationStep: 1,
  maxKeyframes: 0,
  usdPerSecond: 0.157,
  supportsAudio: false,
  listUsdPerSecond: <String, double>{"hd": 0.157, "fhd": 0.235},
  maxPromptCharacters: 26000,
);

const _falModel9 = FalRouteSpec(
  id: "kling/v4/image-to-video",
  canonicalModelId: "kling-4.0",
  label: "Kling 4.0 · Frames",
  description: "Kling 4.0 video with native audio always enabled.",
  family: FalModelFamily.kling,
  modes: <VideoMode>[VideoMode.i2v],
  aspectRatios: <String>["auto"],
  resolutions: <VideoResolutionDefinition>[
    VideoResolutionDefinition("hd", "HD", "1280 × 720"),
    VideoResolutionDefinition("fhd", "Full HD", "1920 × 1080"),
  ],
  minDuration: 3,
  maxDuration: 30,
  durationStep: 1,
  maxKeyframes: 10,
  usdPerSecond: 0.157,
  supportsAudio: false,
  listUsdPerSecond: <String, double>{"hd": 0.157, "fhd": 0.235},
  referenceUsdPerSecond: 0.157,
  supportsStartFrame: true,
  supportsEndFrame: true,
  maxPromptCharacters: 26000,
  maxInputImageBytes: 30000000,
  promptOptionalModes: <VideoMode>[VideoMode.i2v],
);

const _falModel10 = FalRouteSpec(
  id: "alibaba/wan-3.0/text-to-video",
  canonicalModelId: "wan-3.0",
  label: "Wan 3.0 · Text",
  description:
      "Wan 3.0 video with generated audio and optional automatic duration.",
  family: FalModelFamily.wan,
  modes: <VideoMode>[VideoMode.t2v],
  aspectRatios: <String>["auto", "16:9", "4:3", "1:1", "3:4", "9:16"],
  resolutions: <VideoResolutionDefinition>[
    VideoResolutionDefinition("hd", "HD", "1280 × 720"),
    VideoResolutionDefinition("sd", "480p", "480 px short edge"),
    VideoResolutionDefinition("fhd", "Full HD", "1920 × 1080"),
  ],
  minDuration: 2,
  maxDuration: 30,
  durationStep: 1,
  maxKeyframes: 0,
  usdPerSecond: 0.1,
  supportsAudio: true,
  listUsdPerSecond: <String, double>{"hd": 0.1, "sd": 0.05, "fhd": 0.2},
  supportsSeed: true,
  supportsAutoDuration: true,
  maxPromptCharacters: 20000,
);

const _falModel11 = FalRouteSpec(
  id: "alibaba/wan-3.0/image-to-video",
  canonicalModelId: "wan-3.0",
  label: "Wan 3.0 · Frames",
  description:
      "Wan 3.0 video with generated audio and optional automatic duration.",
  family: FalModelFamily.wan,
  modes: <VideoMode>[VideoMode.i2v],
  aspectRatios: <String>["auto", "16:9", "4:3", "1:1", "3:4", "9:16"],
  resolutions: <VideoResolutionDefinition>[
    VideoResolutionDefinition("hd", "HD", "1280 × 720"),
    VideoResolutionDefinition("sd", "480p", "480 px short edge"),
    VideoResolutionDefinition("fhd", "Full HD", "1920 × 1080"),
  ],
  minDuration: 2,
  maxDuration: 30,
  durationStep: 1,
  maxKeyframes: 2,
  usdPerSecond: 0.1,
  supportsAudio: true,
  listUsdPerSecond: <String, double>{"hd": 0.1, "sd": 0.05, "fhd": 0.2},
  referenceUsdPerSecond: 0.1,
  supportsStartFrame: true,
  supportsEndFrame: true,
  supportsSeed: true,
  supportsAutoDuration: true,
  maxPromptCharacters: 20000,
  promptOptionalModes: <VideoMode>[VideoMode.i2v],
);

const _falModel12 = FalRouteSpec(
  id: "lightricks/ltx-2.5/text-to-video/fast",
  canonicalModelId: "ltx-2.5-fast",
  label: "LTX 2.5 Fast · Text",
  description:
      "LTX 2.5 Fast with native audio at 25 fps; output above 1080p is limited to 10 seconds.",
  family: FalModelFamily.ltx,
  modes: <VideoMode>[VideoMode.t2v],
  aspectRatios: <String>["16:9", "9:16"],
  resolutions: <VideoResolutionDefinition>[
    VideoResolutionDefinition("hd", "HD", "1280 × 720"),
    VideoResolutionDefinition("fhd", "Full HD", "1920 × 1080"),
    VideoResolutionDefinition("qhd", "1440p", "2560 × 1440"),
    VideoResolutionDefinition("4k", "4K", "3840 × 2160"),
  ],
  minDuration: 6,
  maxDuration: 20,
  durationStep: 2,
  maxKeyframes: 0,
  usdPerSecond: 0.09,
  supportsAudio: true,
  listUsdPerSecond: <String, double>{
    "hd": 0.09,
    "fhd": 0.13,
    "qhd": 0.19,
    "4k": 0.3,
  },
  supportsAutoDuration: true,
  maxPromptCharacters: 5000,
  maxDurationByResolution: <String, int>{"qhd": 10, "4k": 10},
);

const _falModel13 = FalRouteSpec(
  id: "lightricks/ltx-2.5/image-to-video/fast",
  canonicalModelId: "ltx-2.5-fast",
  label: "LTX 2.5 Fast · Frames",
  description:
      "LTX 2.5 Fast with native audio at 25 fps; output above 1080p is limited to 10 seconds.",
  family: FalModelFamily.ltx,
  modes: <VideoMode>[VideoMode.i2v],
  aspectRatios: <String>["auto", "16:9", "9:16"],
  resolutions: <VideoResolutionDefinition>[
    VideoResolutionDefinition("hd", "HD", "1280 × 720"),
    VideoResolutionDefinition("fhd", "Full HD", "1920 × 1080"),
    VideoResolutionDefinition("qhd", "1440p", "2560 × 1440"),
    VideoResolutionDefinition("4k", "4K", "3840 × 2160"),
  ],
  minDuration: 6,
  maxDuration: 20,
  durationStep: 2,
  maxKeyframes: 2,
  usdPerSecond: 0.09,
  supportsAudio: true,
  listUsdPerSecond: <String, double>{
    "hd": 0.09,
    "fhd": 0.13,
    "qhd": 0.19,
    "4k": 0.3,
  },
  referenceUsdPerSecond: 0.09,
  supportsStartFrame: true,
  supportsEndFrame: true,
  supportsAutoDuration: true,
  maxPromptCharacters: 5000,
  maxDurationByResolution: <String, int>{"qhd": 10, "4k": 10},
);

const _falModel14 = FalRouteSpec(
  id: "lightricks/ltx-2.5/text-to-video/pro",
  canonicalModelId: "ltx-2.5-pro",
  label: "LTX 2.5 Pro · Text",
  description: "LTX 2.5 Pro with native audio at 25 fps, up to 1080p.",
  family: FalModelFamily.ltx,
  modes: <VideoMode>[VideoMode.t2v],
  aspectRatios: <String>["16:9", "9:16"],
  resolutions: <VideoResolutionDefinition>[
    VideoResolutionDefinition("hd", "HD", "1280 × 720"),
    VideoResolutionDefinition("fhd", "Full HD", "1920 × 1080"),
  ],
  minDuration: 6,
  maxDuration: 10,
  durationStep: 2,
  maxKeyframes: 0,
  usdPerSecond: 0.12,
  supportsAudio: true,
  listUsdPerSecond: <String, double>{"hd": 0.12, "fhd": 0.17},
  supportsAutoDuration: true,
  maxPromptCharacters: 5000,
);

const _falModel15 = FalRouteSpec(
  id: "lightricks/ltx-2.5/image-to-video/pro",
  canonicalModelId: "ltx-2.5-pro",
  label: "LTX 2.5 Pro · Frames",
  description: "LTX 2.5 Pro with native audio at 25 fps, up to 1080p.",
  family: FalModelFamily.ltx,
  modes: <VideoMode>[VideoMode.i2v],
  aspectRatios: <String>["auto", "16:9", "9:16"],
  resolutions: <VideoResolutionDefinition>[
    VideoResolutionDefinition("hd", "HD", "1280 × 720"),
    VideoResolutionDefinition("fhd", "Full HD", "1920 × 1080"),
  ],
  minDuration: 6,
  maxDuration: 10,
  durationStep: 2,
  maxKeyframes: 2,
  usdPerSecond: 0.12,
  supportsAudio: true,
  listUsdPerSecond: <String, double>{"hd": 0.12, "fhd": 0.17},
  referenceUsdPerSecond: 0.12,
  supportsStartFrame: true,
  supportsEndFrame: true,
  supportsAutoDuration: true,
  maxPromptCharacters: 5000,
);

const falModelDefinitions = <VideoModelDefinition>[
  _falModel0,
  _falModel1,
  _falModel2,
  _falModel3,
  _falModel4,
  _falModel5,
  _falModel6,
  _falModel7,
  _falModel8,
  _falModel9,
  _falModel10,
  _falModel11,
  _falModel12,
  _falModel13,
  _falModel14,
  _falModel15,
];

const falRouteSpecs = <String, FalRouteSpec>{
  "blackforestlabs/flux-3-max/text-to-video": _falModel0,
  "blackforestlabs/flux-3-max/image-to-video": _falModel1,
  "blackforestlabs/flux-3/text-to-video": _falModel2,
  "blackforestlabs/flux-3/image-to-video": _falModel3,
  "minimax/h3-max/text-to-video": _falModel4,
  "minimax/h3-max/image-to-video": _falModel5,
  "minimax/h3-max-turbo/text-to-video": _falModel6,
  "minimax/h3-max-turbo/image-to-video": _falModel7,
  "kling/v4/text-to-video": _falModel8,
  "kling/v4/image-to-video": _falModel9,
  "alibaba/wan-3.0/text-to-video": _falModel10,
  "alibaba/wan-3.0/image-to-video": _falModel11,
  "lightricks/ltx-2.5/text-to-video/fast": _falModel12,
  "lightricks/ltx-2.5/image-to-video/fast": _falModel13,
  "lightricks/ltx-2.5/text-to-video/pro": _falModel14,
  "lightricks/ltx-2.5/image-to-video/pro": _falModel15,
};

FalRouteSpec? falRouteByModel(String model) => falRouteSpecs[model];
