import 'models.dart';

const clawnsoleMobileTestBuild = bool.fromEnvironment(
  'CLAWNSOLE_MOBILE_TEST_BUILD',
);
const mobileTestProviderId = 'artcraft';
const mobileTestModelId = 'seedance_1p5_pro';
const mobileTestResolutionId = 'sd';
const mobileTestDurationSeconds = 5;

const _appleLocalRatios = <String>['16:9', '4:3', '1:1', '3:4', '9:16'];
const _appleLocalStandard = VideoResolutionDefinition(
  'hd',
  'Standard',
  '512 px long edge',
);
const _appleLocalLarge = VideoResolutionDefinition(
  'fhd',
  'Large',
  '768 px long edge',
);

enum ReferenceVideoCompatibilityProfile { generic, seedance }

/// Whether a provider/model route supplies a meaningful completion percentage.
///
/// Unknown routes deliberately default to [none]. A progress-shaped response
/// field is not enough to opt in: some aggregators report 0 for the entire run
/// and jump directly to 100 when the result is ready.
enum ProviderProgressReporting { none, reported }

class VideoResolutionDefinition {
  const VideoResolutionDefinition(this.id, this.label, this.detail);

  final String id;
  final String label;
  final String detail;
}

class VideoDurationRange {
  const VideoDurationRange({
    required this.minimumSeconds,
    required this.maximumSeconds,
    required this.stepSeconds,
  }) : assert(minimumSeconds > 0),
       assert(maximumSeconds >= minimumSeconds),
       assert(stepSeconds > 0),
       assert((maximumSeconds - minimumSeconds) % stepSeconds == 0);

  final int minimumSeconds;
  final int maximumSeconds;
  final int stepSeconds;

  int get divisions => (maximumSeconds - minimumSeconds) ~/ stepSeconds;

  int normalize(int value) {
    final clamped = value.clamp(minimumSeconds, maximumSeconds);
    final offset = clamped - minimumSeconds;
    return minimumSeconds + (offset ~/ stepSeconds) * stepSeconds;
  }
}

class VideoModelDefinition {
  const VideoModelDefinition({
    required this.id,
    this.canonicalModelId,
    required this.label,
    required this.description,
    required this.modes,
    required this.aspectRatios,
    required this.resolutions,
    required this.minDuration,
    required this.maxDuration,
    required this.durationStep,
    required this.maxKeyframes,
    this.maxKeyframesByMode = const <VideoMode, int>{},
    required this.usdPerSecond,
    this.referenceUsdPerSecond,
    this.supportsStartFrame = false,
    this.supportsEndFrame = false,
    this.maxImageReferences = 0,
    this.maxVideoReferences = 0,
    this.maxAudioReferences = 0,
    this.maxTotalReferences,
    this.maxReferencesByMode =
        const <VideoMode, Map<MediaReferenceKind, int>>{},
    this.framesExclusiveWithReferences = false,
    this.maxReferenceVideoSeconds,
    this.maxReferenceAudioSeconds,
    this.minReferenceAudioSeconds,
    this.maxReferenceVideoSecondsByResolution = const <String, int>{},
    this.maxReferenceAudioSecondsByResolution = const <String, int>{},
    this.requiresVisualReferenceForAudio = false,
    this.maxDurationWithImageGuidance,
    this.maxDurationByResolution = const <String, int>{},
    this.aspectRatiosByResolution = const <String, List<String>>{},
    this.aspectRatiosByMode = const <VideoMode, List<String>>{},
    this.aspectRatiosWithFrames,
    this.resolutionsByReferenceKind =
        const <MediaReferenceKind, List<String>>{},
    this.referencePromptHint,
    this.referenceTasks = const <MediaReferenceTask>[
      MediaReferenceTask.reference,
    ],
    this.supportsAutoDuration = false,
    this.supportsAudio = true,
    this.supportsDraft = false,
    this.supportsTimedKeyframes = false,
    this.supportsFrameRate = false,
    this.supportsSeed = false,
    this.maxPromptCharacters,
    this.promptOptionalModes = const <VideoMode>[],
    this.promptOptionalWithFramesOnly = false,
    this.minSourceVideoSeconds,
    this.maxSourceVideoSeconds,
    this.durationFromSourceModes = const <VideoMode>[],
    this.sourceInputLabel,
    this.sourceInputHint,
    this.supportsGuidanceWithSource = false,
    this.sourceGuidanceRequiresTimestamps = false,
    this.upscaleUsesResolutionTargets = false,
    this.outputKind = GenerationOutputKind.video,
    this.progressReporting,
  });

  final String id;
  final String? canonicalModelId;
  final String label;
  final String description;
  final List<VideoMode> modes;
  final List<String> aspectRatios;
  final List<VideoResolutionDefinition> resolutions;
  final int minDuration;
  final int maxDuration;
  final int durationStep;
  final int maxKeyframes;
  final Map<VideoMode, int> maxKeyframesByMode;
  final double usdPerSecond;
  final double? referenceUsdPerSecond;
  final bool supportsStartFrame;
  final bool supportsEndFrame;
  final int maxImageReferences;
  final int maxVideoReferences;
  final int maxAudioReferences;
  final int? maxTotalReferences;
  final Map<VideoMode, Map<MediaReferenceKind, int>> maxReferencesByMode;

  /// The provider exposes pinned-keyframe and creative-reference modes as
  /// separate request shapes, so a generation cannot combine both.
  final bool framesExclusiveWithReferences;

  final int? maxReferenceVideoSeconds;
  final int? maxReferenceAudioSeconds;
  final int? minReferenceAudioSeconds;
  final Map<String, int> maxReferenceVideoSecondsByResolution;
  final Map<String, int> maxReferenceAudioSecondsByResolution;
  final bool requiresVisualReferenceForAudio;
  final int? maxDurationWithImageGuidance;
  final Map<String, int> maxDurationByResolution;
  final Map<String, List<String>> aspectRatiosByResolution;
  final Map<VideoMode, List<String>> aspectRatiosByMode;
  final List<String>? aspectRatiosWithFrames;
  final Map<MediaReferenceKind, List<String>> resolutionsByReferenceKind;
  final String? referencePromptHint;
  final List<MediaReferenceTask> referenceTasks;
  final bool supportsAutoDuration;
  final bool supportsAudio;
  final bool supportsDraft;
  final bool supportsTimedKeyframes;
  final bool supportsFrameRate;

  /// The wire API accepts a reproducible random seed for this model.
  final bool supportsSeed;

  /// Provider-published prompt ceiling, measured in Dart/UTF-16 code units.
  /// Null means the provider does not publish a dependable route limit.
  final int? maxPromptCharacters;

  /// Modes whose wire contract permits an empty prompt.
  final List<VideoMode> promptOptionalModes;
  final bool promptOptionalWithFramesOnly;

  /// Provider-published limits for the dedicated source-video input.
  final int? minSourceVideoSeconds;
  final int? maxSourceVideoSeconds;

  /// Modes whose output length follows the attached source instead of the
  /// duration control.
  final List<VideoMode> durationFromSourceModes;
  final String? sourceInputLabel;
  final String? sourceInputHint;
  final bool supportsGuidanceWithSource;
  final bool sourceGuidanceRequiresTimestamps;
  final bool upscaleUsesResolutionTargets;
  final GenerationOutputKind outputKind;

  /// Overrides the provider-wide progress contract for this model route.
  final ProviderProgressReporting? progressReporting;

  /// Produces the fixed, low-cost capability surface used by mobile review.
  ///
  /// All request semantics stay attached to the manifest-defined model, while
  /// the selectable output and duration are narrowed to one exact choice.
  VideoModelDefinition constrainedForMobileTest(
    VideoResolutionDefinition resolution,
  ) => VideoModelDefinition(
    id: id,
    canonicalModelId: canonicalModelId,
    label: label,
    description: description,
    modes: modes,
    aspectRatios: aspectRatios,
    resolutions: <VideoResolutionDefinition>[resolution],
    minDuration: mobileTestDurationSeconds,
    maxDuration: mobileTestDurationSeconds,
    durationStep: 1,
    maxKeyframes: maxKeyframes,
    maxKeyframesByMode: maxKeyframesByMode,
    usdPerSecond: usdPerSecond,
    referenceUsdPerSecond: referenceUsdPerSecond,
    supportsStartFrame: supportsStartFrame,
    supportsEndFrame: supportsEndFrame,
    maxImageReferences: maxImageReferences,
    maxVideoReferences: maxVideoReferences,
    maxAudioReferences: maxAudioReferences,
    maxTotalReferences: maxTotalReferences,
    maxReferencesByMode: maxReferencesByMode,
    framesExclusiveWithReferences: framesExclusiveWithReferences,
    maxReferenceVideoSeconds: maxReferenceVideoSeconds,
    maxReferenceAudioSeconds: maxReferenceAudioSeconds,
    minReferenceAudioSeconds: minReferenceAudioSeconds,
    maxReferenceVideoSecondsByResolution: maxReferenceVideoSecondsByResolution,
    maxReferenceAudioSecondsByResolution: maxReferenceAudioSecondsByResolution,
    requiresVisualReferenceForAudio: requiresVisualReferenceForAudio,
    maxDurationWithImageGuidance: mobileTestDurationSeconds,
    maxDurationByResolution: const <String, int>{
      mobileTestResolutionId: mobileTestDurationSeconds,
    },
    aspectRatiosByResolution: aspectRatiosByResolution,
    aspectRatiosByMode: aspectRatiosByMode,
    aspectRatiosWithFrames: aspectRatiosWithFrames,
    resolutionsByReferenceKind: resolutionsByReferenceKind,
    referencePromptHint: referencePromptHint,
    referenceTasks: referenceTasks,
    supportsAutoDuration: false,
    supportsAudio: supportsAudio,
    supportsDraft: supportsDraft,
    supportsTimedKeyframes: supportsTimedKeyframes,
    supportsFrameRate: supportsFrameRate,
    supportsSeed: supportsSeed,
    maxPromptCharacters: maxPromptCharacters,
    promptOptionalModes: promptOptionalModes,
    promptOptionalWithFramesOnly: promptOptionalWithFramesOnly,
    minSourceVideoSeconds: minSourceVideoSeconds,
    maxSourceVideoSeconds: maxSourceVideoSeconds,
    durationFromSourceModes: durationFromSourceModes,
    sourceInputLabel: sourceInputLabel,
    sourceInputHint: sourceInputHint,
    supportsGuidanceWithSource: supportsGuidanceWithSource,
    sourceGuidanceRequiresTimestamps: sourceGuidanceRequiresTimestamps,
    upscaleUsesResolutionTargets: upscaleUsesResolutionTargets,
    outputKind: outputKind,
    progressReporting: progressReporting,
  );

  String get canonicalId => canonicalModelId ?? id;

  int maxReferences(MediaReferenceKind kind, [VideoMode? mode]) =>
      (mode == null ? null : maxReferencesByMode[mode]?[kind]) ??
      switch (kind) {
        MediaReferenceKind.image => maxImageReferences,
        MediaReferenceKind.video => maxVideoReferences,
        MediaReferenceKind.audio => maxAudioReferences,
      };

  int maxKeyframesFor(VideoMode mode) =>
      maxKeyframesByMode[mode] ?? maxKeyframes;

  bool get supportsMediaReferences =>
      maxImageReferences > 0 ||
      maxVideoReferences > 0 ||
      maxAudioReferences > 0;

  ReferenceVideoCompatibilityProfile? get referenceVideoCompatibilityProfile =>
      maxVideoReferences <= 0
      ? null
      : canonicalId.startsWith('seedance-') || id.startsWith('seedance_')
      ? ReferenceVideoCompatibilityProfile.seedance
      : ReferenceVideoCompatibilityProfile.generic;

  bool get isUpscaler => modes.length == 1 && modes.single == VideoMode.upscale;

  bool promptIsOptional(VideoMode mode, {bool hasFrames = false}) =>
      promptOptionalModes.contains(mode) &&
      (!promptOptionalWithFramesOnly || mode != VideoMode.i2v || hasFrames);

  bool durationComesFromSource(VideoMode mode) =>
      durationFromSourceModes.contains(mode);

  int maxDurationFor(String resolution, {bool withImageGuidance = false}) {
    final resolutionMaximum =
        maxDurationByResolution[resolution] ?? maxDuration;
    final guidanceMaximum = withImageGuidance
        ? maxDurationWithImageGuidance
        : null;
    return guidanceMaximum == null || resolutionMaximum < guidanceMaximum
        ? resolutionMaximum
        : guidanceMaximum;
  }

  VideoDurationRange durationRangeFor(
    String resolution, {
    bool withImageGuidance = false,
  }) => VideoDurationRange(
    minimumSeconds: minDuration,
    maximumSeconds: maxDurationFor(
      resolution,
      withImageGuidance: withImageGuidance,
    ),
    stepSeconds: durationStep,
  );

  int? maxReferenceSeconds(MediaReferenceKind kind, String resolution) =>
      switch (kind) {
        MediaReferenceKind.image => null,
        MediaReferenceKind.video =>
          maxReferenceVideoSecondsByResolution[resolution] ??
              maxReferenceVideoSeconds,
        MediaReferenceKind.audio =>
          maxReferenceAudioSecondsByResolution[resolution] ??
              maxReferenceAudioSeconds,
      };

  List<String> aspectRatiosFor(
    String resolution, {
    bool withFrames = false,
    VideoMode? mode,
  }) => withFrames && aspectRatiosWithFrames != null
      ? aspectRatiosWithFrames!
      : (mode == null ? null : aspectRatiosByMode[mode]) ??
            aspectRatiosByResolution[resolution] ??
            aspectRatios;

  bool supportsResolutionForReferences(
    String resolution,
    Iterable<MediaReferenceKind> kinds,
  ) => kinds.every(
    (kind) => resolutionsByReferenceKind[kind]?.contains(resolution) ?? true,
  );

  ProviderModelPrice price(String provider) => ProviderModelPrice(
    provider: provider,
    model: id,
    canonicalModelId: canonicalId,
    label: label,
    usdPerSecond: usdPerSecond,
    referenceUsdPerSecond: referenceUsdPerSecond,
    modes: modes,
    minDuration: minDuration,
    maxDuration: maxDuration,
    durationStep: durationStep,
    source: switch (provider) {
      'atlas' => 'published · starting rate',
      'artcraft' => 'published · default configuration',
      _ => 'published',
    },
  );
}

class VideoProviderDefinition {
  const VideoProviderDefinition({
    required this.id,
    String? adapter,
    required this.name,
    required this.description,
    required this.consoleUrl,
    required this.docsUrl,
    required this.pricingUrl,
    required this.models,
    this.pricingSource = 'Published rate card',
    this.requiresApiKey = true,
    this.isLocal = false,
    this.resultDelivery = const ProviderResultDelivery(),
    this.progressReporting = ProviderProgressReporting.none,
  }) : adapter = adapter ?? id;

  final String id;
  final String adapter;
  final String name;
  final String description;
  final String consoleUrl;
  final String docsUrl;
  final String pricingUrl;
  final String pricingSource;
  final List<VideoModelDefinition> models;
  final bool requiresApiKey;
  final bool isLocal;
  final ProviderResultDelivery resultDelivery;
  final ProviderProgressReporting progressReporting;

  VideoModelDefinition get defaultModel => models.first;
  String get model => defaultModel.id;
  String get modelLabel => defaultModel.label;
  List<VideoMode> get modes => defaultModel.modes;
  List<String> get aspectRatios => defaultModel.aspectRatios;
  int get minDuration => defaultModel.minDuration;
  int get maxDuration => defaultModel.maxDuration;
  int get maxKeyframes => defaultModel.maxKeyframes;
}

/// Provider-side availability after a generation reaches a terminal state.
///
/// Clawnsole always tries to retain completed media immediately. A null
/// [availability] means the provider does not publish a dependable window, so
/// the app must keep retrying instead of inventing an expiry.
class ProviderResultDelivery {
  const ProviderResultDelivery({
    this.availability,
    this.keepOpenRecommended = false,
  });

  final Duration? availability;
  final bool keepOpenRecommended;
}

class _ArtCraftModel extends VideoModelDefinition {
  const _ArtCraftModel({
    required super.id,
    super.canonicalModelId,
    required super.label,
    required super.description,
    required super.aspectRatios,
    required super.resolutions,
    required super.minDuration,
    required super.maxDuration,
    required super.maxKeyframes,
    required super.usdPerSecond,
    super.supportsStartFrame = true,
    super.supportsEndFrame = true,
    super.maxImageReferences,
    super.maxVideoReferences,
    super.maxAudioReferences,
    super.maxTotalReferences,
    super.framesExclusiveWithReferences,
    super.maxReferenceVideoSeconds,
    super.maxReferenceAudioSeconds,
    super.requiresVisualReferenceForAudio,
    super.maxDurationWithImageGuidance,
    super.aspectRatiosWithFrames,
    super.durationStep = 1,
    bool supportsText = true,
    super.supportsAudio = false,
  }) : super(
         modes: supportsText
             ? maxKeyframes > 0
                   ? const <VideoMode>[VideoMode.t2v, VideoMode.i2v]
                   : const <VideoMode>[VideoMode.t2v]
             : const <VideoMode>[VideoMode.i2v],
         referenceUsdPerSecond:
             maxKeyframes > 0 ||
                 maxImageReferences > 0 ||
                 maxVideoReferences > 0 ||
                 maxAudioReferences > 0
             ? usdPerSecond
             : null,
       );
}

const _sd = VideoResolutionDefinition('sd', '480p', '854 × 480');
const _hd = VideoResolutionDefinition('hd', 'HD', '1280 × 720');
const _fhd = VideoResolutionDefinition('fhd', 'Full HD', '1920 × 1080');
const _qhd = VideoResolutionDefinition('qhd', '1440p', '2560 × 1440');
const _twoK = VideoResolutionDefinition('qhd', '2K', '2048 px');
const _uhd = VideoResolutionDefinition('4k', '4K', '3840 × 2160');
const _wideRatios = <String>[
  'auto',
  '21:9',
  '2:1',
  '16:9',
  '4:3',
  '1:1',
  '3:4',
  '9:16',
];
const _ltxRatios = <String>['16:9', '9:16'];
const _artCraftRatios = <String>['21:9', '16:9', '4:3', '1:1', '3:4', '9:16'];
const _artCraftAutoRatios = <String>[
  'auto',
  '21:9',
  '16:9',
  '4:3',
  '1:1',
  '3:4',
  '9:16',
];
const _artCraftCommonRatios = <String>['16:9', '4:3', '1:1', '3:4', '9:16'];
const _artCraftGrokRatios = <String>[
  'auto',
  '16:9',
  '4:3',
  '3:2',
  '1:1',
  '2:3',
  '3:4',
  '9:16',
];
const _artCraftKlingRatios = <String>['16:9', '1:1', '9:16'];
const _artCraftVeoRatios = <String>['auto', '16:9', '9:16'];
const _artCraftViduRatios = <String>['16:9', '9:16', '4:3', '3:4', '1:1'];
const _bflProvider = VideoProviderDefinition(
  id: 'bfl',
  name: 'Black Forest Labs',
  description:
      'Multimodal video generation plus precise and creative finishing tools.',
  consoleUrl: 'https://dashboard.bfl.ai',
  docsUrl: 'https://docs.bfl.ai/flux_3/flux3_video',
  pricingUrl: 'https://bfl.ai/pricing',
  pricingSource: 'Published credits · converted at \$0.01/credit',
  progressReporting: ProviderProgressReporting.reported,
  resultDelivery: ProviderResultDelivery(
    availability: Duration(minutes: 10),
    keepOpenRecommended: true,
  ),
  models: <VideoModelDefinition>[
    VideoModelDefinition(
      id: 'flux-3-video',
      canonicalModelId: 'flux-3',
      label: 'FLUX 3',
      description: 'Multimodal generation, continuation, and draft enhance.',
      modes: <VideoMode>[
        VideoMode.t2v,
        VideoMode.i2v,
        VideoMode.v2v,
        VideoMode.draftEnhance,
      ],
      aspectRatios: _wideRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _fhd],
      minDuration: 5,
      maxDuration: 20,
      durationStep: 1,
      maxKeyframes: 10,
      usdPerSecond: .17,
      referenceUsdPerSecond: .17,
      supportsStartFrame: true,
      supportsEndFrame: true,
      supportsAutoDuration: true,
      supportsDraft: true,
      supportsTimedKeyframes: true,
    ),
    VideoModelDefinition(
      id: 'flux-tools-video-upscale-v1',
      canonicalModelId: 'flux-video-upscale',
      label: 'FLUX Video Upscale',
      description:
          'Source-faithful or creative super-resolution from 1.5× to 3×.',
      modes: <VideoMode>[VideoMode.upscale],
      aspectRatios: <String>['auto'],
      resolutions: <VideoResolutionDefinition>[
        VideoResolutionDefinition(
          'source',
          'Source aspect',
          '1.5×–3× · up to 4K',
        ),
      ],
      minDuration: 1,
      maxDuration: 20,
      durationStep: 1,
      maxKeyframes: 0,
      usdPerSecond: .10,
      supportsAudio: false,
    ),
  ],
);

const _ltxProvider = VideoProviderDefinition(
  id: 'ltx',
  name: 'LTX Studio',
  description: 'Production-focused video generation with native audio.',
  consoleUrl: 'https://console.ltx.io/',
  docsUrl: 'https://docs.ltx.io',
  pricingUrl: 'https://docs.ltx.io/pricing',
  resultDelivery: ProviderResultDelivery(availability: Duration(hours: 24)),
  models: <VideoModelDefinition>[
    VideoModelDefinition(
      id: 'ltx-2-3-fast',
      label: 'LTX 2.3 Fast',
      description: 'Economical 720p–4K long-form generation.',
      modes: <VideoMode>[VideoMode.t2v, VideoMode.i2v],
      aspectRatios: _ltxRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _fhd, _qhd, _uhd],
      minDuration: 6,
      maxDuration: 20,
      durationStep: 2,
      maxKeyframes: 2,
      usdPerSecond: .03,
      referenceUsdPerSecond: .03,
      supportsStartFrame: true,
      supportsEndFrame: true,
      maxDurationByResolution: <String, int>{'qhd': 10, '4k': 10},
    ),
    VideoModelDefinition(
      id: 'ltx-2-3-pro',
      label: 'LTX 2.3 Pro',
      description: 'High-fidelity 720p–4K video generation.',
      modes: <VideoMode>[VideoMode.t2v, VideoMode.i2v],
      aspectRatios: _ltxRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _fhd, _qhd, _uhd],
      minDuration: 6,
      maxDuration: 10,
      durationStep: 2,
      maxKeyframes: 2,
      usdPerSecond: .04,
      referenceUsdPerSecond: .04,
      supportsStartFrame: true,
      supportsEndFrame: true,
      maxAudioReferences: 1,
      maxReferenceAudioSeconds: 20,
      maxReferenceAudioSecondsByResolution: <String, int>{'qhd': 10, '4k': 10},
    ),
  ],
);

const _runwayRatios = <String>[
  '21:9',
  '16:9',
  '4:3',
  '3:2',
  '1:1',
  '2:3',
  '3:4',
  '9:16',
];
const _runwayCommonRatios = <String>['16:9', '4:3', '1:1', '3:4', '9:16'];
const _runwayPortraitRatios = <String>['16:9', '9:16'];

/// Runway's direct API exposes one model through several request endpoints.
/// Keeping those modes on one canonical definition lets Create switch request
/// shapes without duplicating the model in the library and cost desk.
const _runwayProvider = VideoProviderDefinition(
  id: 'runway',
  name: 'Runway',
  description:
      'Runway’s first-party video models, multimodal references, edits, and character performance.',
  consoleUrl: 'https://app.runwayml.com/',
  docsUrl: 'https://docs.dev.runwayml.com/guides/models/',
  pricingUrl: 'https://docs.dev.runwayml.com/guides/pricing/',
  pricingSource:
      'Published credits · converted at \$0.01/credit; the live model guide is checked for additions',
  progressReporting: ProviderProgressReporting.reported,
  resultDelivery: ProviderResultDelivery(
    availability: Duration(hours: 24),
    keepOpenRecommended: true,
  ),
  models: <VideoModelDefinition>[
    VideoModelDefinition(
      id: 'seedance2_5',
      canonicalModelId: 'seedance-2.5',
      label: 'Seedance 2.5',
      description:
          'Long-form generation and reference-video guidance with native audio.',
      modes: <VideoMode>[VideoMode.t2v, VideoMode.i2v, VideoMode.v2v],
      aspectRatios: _runwayCommonRatios,
      resolutions: <VideoResolutionDefinition>[_sd, _hd, _fhd],
      minDuration: 4,
      maxDuration: 30,
      durationStep: 1,
      maxKeyframes: 2,
      maxKeyframesByMode: <VideoMode, int>{VideoMode.v2v: 0},
      usdPerSecond: .30,
      referenceUsdPerSecond: .30,
      supportsStartFrame: true,
      supportsEndFrame: true,
      maxImageReferences: 30,
      maxVideoReferences: 10,
      maxAudioReferences: 10,
      framesExclusiveWithReferences: true,
      maxReferenceVideoSeconds: 30,
      maxReferenceAudioSeconds: 30,
      maxPromptCharacters: 15000,
      promptOptionalModes: <VideoMode>[VideoMode.i2v, VideoMode.v2v],
      maxSourceVideoSeconds: 30,
      supportsGuidanceWithSource: true,
    ),
    VideoModelDefinition(
      id: 'grok_imagine_1_5',
      canonicalModelId: 'grok-imagine-video-1.5',
      label: 'Grok Imagine 1.5',
      description:
          'Fast generation with image and audio guidance up to Full HD.',
      modes: <VideoMode>[VideoMode.t2v, VideoMode.i2v],
      aspectRatios: _runwayRatios,
      resolutions: <VideoResolutionDefinition>[_sd, _hd, _fhd],
      minDuration: 1,
      maxDuration: 15,
      durationStep: 1,
      maxKeyframes: 1,
      usdPerSecond: .16,
      referenceUsdPerSecond: .16,
      supportsStartFrame: true,
      maxImageReferences: 7,
      maxAudioReferences: 1,
      maxTotalReferences: 8,
      maxReferenceAudioSeconds: 15,
      minReferenceAudioSeconds: 3,
      requiresVisualReferenceForAudio: true,
      framesExclusiveWithReferences: true,
      aspectRatiosByMode: <VideoMode, List<String>>{
        VideoMode.i2v: <String>['auto'],
      },
      resolutionsByReferenceKind: <MediaReferenceKind, List<String>>{
        MediaReferenceKind.image: <String>['sd', 'hd'],
        MediaReferenceKind.audio: <String>['sd', 'hd'],
      },
      promptOptionalModes: <VideoMode>[VideoMode.i2v],
      promptOptionalWithFramesOnly: true,
    ),
    VideoModelDefinition(
      id: 'seedance2',
      canonicalModelId: 'seedance-2.0',
      label: 'Seedance 2.0',
      description:
          'Full-quality multimodal generation and video guidance up to 4K.',
      modes: <VideoMode>[VideoMode.t2v, VideoMode.i2v, VideoMode.v2v],
      aspectRatios: _runwayCommonRatios,
      resolutions: <VideoResolutionDefinition>[_sd, _hd, _fhd, _uhd],
      minDuration: 4,
      maxDuration: 15,
      durationStep: 1,
      maxKeyframes: 2,
      maxKeyframesByMode: <VideoMode, int>{VideoMode.v2v: 0},
      usdPerSecond: .36,
      referenceUsdPerSecond: .36,
      supportsStartFrame: true,
      supportsEndFrame: true,
      maxImageReferences: 9,
      maxVideoReferences: 3,
      maxAudioReferences: 3,
      framesExclusiveWithReferences: true,
      maxReferenceVideoSeconds: 15,
      maxReferenceAudioSeconds: 15,
      maxPromptCharacters: 3500,
      promptOptionalModes: <VideoMode>[VideoMode.i2v, VideoMode.v2v],
      promptOptionalWithFramesOnly: true,
      maxSourceVideoSeconds: 15,
      supportsGuidanceWithSource: true,
    ),
    VideoModelDefinition(
      id: 'seedance2_fast',
      canonicalModelId: 'seedance-2.0-fast',
      label: 'Seedance 2.0 Fast',
      description: 'Faster multimodal generation at 480p or 720p.',
      modes: <VideoMode>[VideoMode.t2v, VideoMode.i2v, VideoMode.v2v],
      aspectRatios: _runwayCommonRatios,
      resolutions: <VideoResolutionDefinition>[_sd, _hd],
      minDuration: 4,
      maxDuration: 15,
      durationStep: 1,
      maxKeyframes: 2,
      maxKeyframesByMode: <VideoMode, int>{VideoMode.v2v: 0},
      usdPerSecond: .29,
      referenceUsdPerSecond: .29,
      supportsStartFrame: true,
      supportsEndFrame: true,
      maxImageReferences: 9,
      maxVideoReferences: 3,
      maxAudioReferences: 3,
      framesExclusiveWithReferences: true,
      maxReferenceVideoSeconds: 15,
      maxReferenceAudioSeconds: 15,
      maxPromptCharacters: 3500,
      promptOptionalModes: <VideoMode>[VideoMode.i2v, VideoMode.v2v],
      promptOptionalWithFramesOnly: true,
      maxSourceVideoSeconds: 15,
      supportsGuidanceWithSource: true,
    ),
    VideoModelDefinition(
      id: 'seedance2_mini',
      canonicalModelId: 'seedance-2.0-mini',
      label: 'Seedance 2.0 Mini',
      description: 'Lowest-cost Seedance route with rich references.',
      modes: <VideoMode>[VideoMode.t2v, VideoMode.i2v, VideoMode.v2v],
      aspectRatios: _runwayCommonRatios,
      resolutions: <VideoResolutionDefinition>[_sd, _hd],
      minDuration: 4,
      maxDuration: 15,
      durationStep: 1,
      maxKeyframes: 2,
      maxKeyframesByMode: <VideoMode, int>{VideoMode.v2v: 0},
      usdPerSecond: .16,
      referenceUsdPerSecond: .16,
      supportsStartFrame: true,
      supportsEndFrame: true,
      maxImageReferences: 9,
      maxVideoReferences: 3,
      maxAudioReferences: 3,
      framesExclusiveWithReferences: true,
      maxReferenceVideoSeconds: 15,
      maxReferenceAudioSeconds: 15,
      maxPromptCharacters: 3500,
      promptOptionalModes: <VideoMode>[VideoMode.i2v, VideoMode.v2v],
      promptOptionalWithFramesOnly: true,
      maxSourceVideoSeconds: 15,
      supportsGuidanceWithSource: true,
    ),
    VideoModelDefinition(
      id: 'hailuo3',
      canonicalModelId: 'hailuo-3',
      label: 'Hailuo 3',
      description: 'Reference-rich MiniMax generation at 768p or 2K.',
      modes: <VideoMode>[VideoMode.t2v, VideoMode.i2v, VideoMode.v2v],
      aspectRatios: <String>['auto', ..._runwayCommonRatios, '21:9'],
      resolutions: <VideoResolutionDefinition>[_hd, _twoK],
      minDuration: 5,
      maxDuration: 15,
      durationStep: 1,
      maxKeyframes: 1,
      maxKeyframesByMode: <VideoMode, int>{VideoMode.v2v: 0},
      usdPerSecond: .10,
      referenceUsdPerSecond: .10,
      supportsStartFrame: true,
      maxImageReferences: 9,
      maxVideoReferences: 3,
      maxAudioReferences: 3,
      maxTotalReferences: 12,
      framesExclusiveWithReferences: true,
      maxReferenceVideoSeconds: 15,
      maxReferenceAudioSeconds: 15,
      maxSourceVideoSeconds: 15,
      supportsGuidanceWithSource: true,
    ),
    VideoModelDefinition(
      id: 'aleph2',
      canonicalModelId: 'aleph-2',
      label: 'Aleph 2',
      description: 'Source-faithful video editing with timed guidance images.',
      modes: <VideoMode>[VideoMode.v2v],
      aspectRatios: <String>['auto', ..._runwayRatios],
      resolutions: <VideoResolutionDefinition>[
        VideoResolutionDefinition('source', 'Source', 'Source resolution'),
      ],
      minDuration: 2,
      maxDuration: 30,
      durationStep: 1,
      maxKeyframes: 5,
      usdPerSecond: .28,
      referenceUsdPerSecond: .28,
      supportsStartFrame: true,
      supportsEndFrame: true,
      supportsTimedKeyframes: true,
      supportsSeed: true,
      promptOptionalModes: <VideoMode>[VideoMode.v2v],
      minSourceVideoSeconds: 2,
      maxSourceVideoSeconds: 30,
      durationFromSourceModes: <VideoMode>[VideoMode.v2v],
      sourceInputLabel: 'Video to edit',
      sourceInputHint:
          'Attach a 2–30 second clip. Optional timed images pin edits to exact moments.',
      supportsGuidanceWithSource: true,
      sourceGuidanceRequiresTimestamps: true,
    ),
    VideoModelDefinition(
      id: 'gen4.5',
      canonicalModelId: 'runway-gen-4.5',
      label: 'Gen-4.5',
      description: 'Runway’s highest-fidelity text and image generation.',
      modes: <VideoMode>[VideoMode.t2v, VideoMode.i2v],
      aspectRatios: <String>['21:9', ..._runwayCommonRatios],
      resolutions: <VideoResolutionDefinition>[_hd],
      minDuration: 2,
      maxDuration: 10,
      durationStep: 1,
      maxKeyframes: 1,
      usdPerSecond: .12,
      referenceUsdPerSecond: .12,
      supportsStartFrame: true,
      supportsSeed: true,
      maxPromptCharacters: 1000,
      aspectRatiosByMode: <VideoMode, List<String>>{
        VideoMode.t2v: _runwayPortraitRatios,
      },
    ),
    VideoModelDefinition(
      id: 'gen4_turbo',
      canonicalModelId: 'runway-gen-4-turbo',
      label: 'Gen-4 Turbo',
      description: 'Economical image-to-video generation.',
      modes: <VideoMode>[VideoMode.i2v],
      aspectRatios: <String>['21:9', ..._runwayCommonRatios],
      resolutions: <VideoResolutionDefinition>[_hd],
      minDuration: 2,
      maxDuration: 10,
      durationStep: 1,
      maxKeyframes: 1,
      usdPerSecond: .05,
      referenceUsdPerSecond: .05,
      supportsStartFrame: true,
      supportsSeed: true,
      maxPromptCharacters: 1000,
      promptOptionalModes: <VideoMode>[VideoMode.i2v],
    ),
    VideoModelDefinition(
      id: 'act_two',
      canonicalModelId: 'runway-act-two',
      label: 'Act-Two',
      description: 'Drive a character image or video from a performance clip.',
      modes: <VideoMode>[VideoMode.v2v],
      aspectRatios: <String>['21:9', ..._runwayCommonRatios],
      resolutions: <VideoResolutionDefinition>[_hd],
      minDuration: 3,
      maxDuration: 30,
      durationStep: 1,
      maxKeyframes: 0,
      usdPerSecond: .05,
      referenceUsdPerSecond: .05,
      maxImageReferences: 1,
      maxVideoReferences: 1,
      maxTotalReferences: 1,
      supportsAudio: false,
      supportsSeed: true,
      promptOptionalModes: <VideoMode>[VideoMode.v2v],
      minSourceVideoSeconds: 3,
      maxSourceVideoSeconds: 30,
      durationFromSourceModes: <VideoMode>[VideoMode.v2v],
      sourceInputLabel: 'Performance video',
      sourceInputHint:
          'Attach a 3–30 second performance, then one character image or video below.',
      referencePromptHint:
          'Exactly one image or video supplies the character to animate.',
      supportsGuidanceWithSource: true,
    ),
    VideoModelDefinition(
      id: 'veo3.1',
      canonicalModelId: 'veo-3.1',
      label: 'Veo 3.1',
      description: 'Premium Veo generation with optional synchronized audio.',
      modes: <VideoMode>[VideoMode.t2v, VideoMode.i2v],
      aspectRatios: _runwayPortraitRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _fhd],
      minDuration: 4,
      maxDuration: 8,
      durationStep: 2,
      maxKeyframes: 2,
      usdPerSecond: .40,
      referenceUsdPerSecond: .40,
      supportsStartFrame: true,
      supportsEndFrame: true,
      maxPromptCharacters: 1000,
      promptOptionalModes: <VideoMode>[VideoMode.i2v],
    ),
    VideoModelDefinition(
      id: 'veo3.1_fast',
      canonicalModelId: 'veo-3.1-fast',
      label: 'Veo 3.1 Fast',
      description: 'Faster Veo generation with optional synchronized audio.',
      modes: <VideoMode>[VideoMode.t2v, VideoMode.i2v],
      aspectRatios: _runwayPortraitRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _fhd],
      minDuration: 4,
      maxDuration: 8,
      durationStep: 2,
      maxKeyframes: 2,
      usdPerSecond: .15,
      referenceUsdPerSecond: .15,
      supportsStartFrame: true,
      supportsEndFrame: true,
      maxPromptCharacters: 1000,
      promptOptionalModes: <VideoMode>[VideoMode.i2v],
    ),
    VideoModelDefinition(
      id: 'happyhorse_1_0',
      canonicalModelId: 'happy-horse-1.0',
      label: 'Happy Horse 1.0',
      description: 'Alibaba generation from text or a first frame up to 1080p.',
      modes: <VideoMode>[VideoMode.t2v, VideoMode.i2v],
      aspectRatios: _runwayCommonRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _fhd],
      minDuration: 3,
      maxDuration: 15,
      durationStep: 1,
      maxKeyframes: 1,
      usdPerSecond: .15,
      referenceUsdPerSecond: .15,
      supportsStartFrame: true,
      maxPromptCharacters: 2500,
      promptOptionalModes: <VideoMode>[VideoMode.i2v],
      aspectRatiosByMode: <VideoMode, List<String>>{
        VideoMode.i2v: <String>['auto'],
      },
    ),
    VideoModelDefinition(
      id: 'gemini_omni_flash',
      canonicalModelId: 'gemini-omni-flash',
      label: 'Gemini Omni Flash',
      description: 'Generation and instruction-led video editing.',
      modes: <VideoMode>[VideoMode.t2v, VideoMode.i2v, VideoMode.v2v],
      aspectRatios: _runwayPortraitRatios,
      resolutions: <VideoResolutionDefinition>[_hd],
      minDuration: 3,
      maxDuration: 10,
      durationStep: 1,
      maxKeyframes: 1,
      maxKeyframesByMode: <VideoMode, int>{VideoMode.v2v: 0},
      usdPerSecond: .10,
      referenceUsdPerSecond: .10,
      supportsStartFrame: true,
      maxImageReferences: 5,
      maxReferencesByMode: <VideoMode, Map<MediaReferenceKind, int>>{
        VideoMode.i2v: <MediaReferenceKind, int>{MediaReferenceKind.image: 1},
        VideoMode.v2v: <MediaReferenceKind, int>{MediaReferenceKind.image: 5},
      },
      maxSourceVideoSeconds: 10,
      framesExclusiveWithReferences: true,
      promptOptionalModes: <VideoMode>[VideoMode.i2v],
      durationFromSourceModes: <VideoMode>[VideoMode.v2v],
      sourceInputLabel: 'Video to edit',
      sourceInputHint:
          'Attach a clip up to 10 seconds; optional images can guide the edit.',
      supportsGuidanceWithSource: true,
    ),
    VideoModelDefinition(
      id: 'magnific_video_upscaler_creative',
      canonicalModelId: 'magnific-video-upscaler-creative',
      label: 'Magnific Video Upscaler',
      description:
          'AI-detail video upscaling from 720p through 4K, billed per output frame.',
      modes: <VideoMode>[VideoMode.upscale],
      aspectRatios: <String>['auto'],
      resolutions: <VideoResolutionDefinition>[
        VideoResolutionDefinition('hd', '720p', 'Target 720p'),
        VideoResolutionDefinition('fhd', '1K', 'Target 1K'),
        VideoResolutionDefinition('qhd', '2K', 'Target 2K'),
        _uhd,
      ],
      minDuration: 1,
      maxDuration: 30,
      durationStep: 1,
      maxKeyframes: 0,
      usdPerSecond: .168,
      supportsAudio: false,
      maxSourceVideoSeconds: 30,
      durationFromSourceModes: <VideoMode>[VideoMode.upscale],
      sourceInputLabel: 'Video to upscale',
      sourceInputHint:
          'Attach a clip up to 30 seconds. Runway preserves its aspect ratio and bills each output frame.',
      upscaleUsesResolutionTargets: true,
    ),
  ],
);

const _artCraftProvider = VideoProviderDefinition(
  id: 'artcraft',
  name: 'ArtCraft',
  description:
      'A broad, live video model catalog behind ArtCraft’s API-key Omni API.',
  consoleUrl: 'https://app.getartcraft.com/',
  // ArtCraft's branded Omni API doc; it links onward to the unbranded
  // storyteller-docs.netlify.app reference, which stays allowlisted.
  docsUrl:
      'https://github.com/storytold/artcraft/blob/main/_docs/omni_api/artcraft_omni_api.md',
  pricingUrl: 'https://app.getartcraft.com/pricing',
  pricingSource:
      'Live configuration quotes with published defaults · \$0.01/credit',
  resultDelivery: ProviderResultDelivery(keepOpenRecommended: true),
  models: <VideoModelDefinition>[
    _ArtCraftModel(
      id: 'seedance_2p0',
      canonicalModelId: 'seedance-2.0',
      label: 'Seedance 2.0',
      description: 'Original Seedance with image, video, and audio references.',
      aspectRatios: _artCraftRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _sd, _fhd, _uhd],
      minDuration: 4,
      maxDuration: 15,
      maxKeyframes: 2,
      maxImageReferences: 9,
      maxVideoReferences: 3,
      maxAudioReferences: 3,
      framesExclusiveWithReferences: true,
      maxReferenceVideoSeconds: 15,
      maxReferenceAudioSeconds: 15,
      requiresVisualReferenceForAudio: true,
      usdPerSecond: .186,
    ),
    _ArtCraftModel(
      id: 'seedance_2p0_fast',
      canonicalModelId: 'seedance-2.0-fast',
      label: 'Seedance 2.0 Fast',
      description: 'Faster original Seedance 2.0 generation.',
      aspectRatios: _artCraftRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _sd],
      minDuration: 4,
      maxDuration: 15,
      maxKeyframes: 2,
      maxImageReferences: 9,
      maxVideoReferences: 3,
      maxAudioReferences: 3,
      framesExclusiveWithReferences: true,
      maxReferenceVideoSeconds: 15,
      maxReferenceAudioSeconds: 15,
      requiresVisualReferenceForAudio: true,
      usdPerSecond: .128,
    ),
    _ArtCraftModel(
      id: 'seedance_2p0_bp',
      label: 'Seedance 2.0 Plus',
      description: 'BytePlus Seedance 2.0 with broad reference support.',
      aspectRatios: _artCraftRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _sd, _fhd, _uhd],
      minDuration: 4,
      maxDuration: 15,
      maxKeyframes: 2,
      maxImageReferences: 9,
      maxVideoReferences: 3,
      maxAudioReferences: 3,
      framesExclusiveWithReferences: true,
      maxReferenceVideoSeconds: 15,
      maxReferenceAudioSeconds: 15,
      requiresVisualReferenceForAudio: true,
      usdPerSecond: .25,
    ),
    _ArtCraftModel(
      id: 'seedance_2p0_bp_fast',
      label: 'Seedance 2.0 Plus Fast',
      description: 'Faster BytePlus Seedance 2.0 generation.',
      aspectRatios: _artCraftRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _sd],
      minDuration: 4,
      maxDuration: 15,
      maxKeyframes: 2,
      maxImageReferences: 9,
      maxVideoReferences: 3,
      maxAudioReferences: 3,
      framesExclusiveWithReferences: true,
      maxReferenceVideoSeconds: 15,
      maxReferenceAudioSeconds: 15,
      requiresVisualReferenceForAudio: true,
      usdPerSecond: .20,
    ),
    _ArtCraftModel(
      id: 'seedance_2p0_bpu',
      label: 'Seedance 2.0 Plus Ultra',
      description: 'BytePlus Seedance 2.0 with the broadest creative range.',
      aspectRatios: _artCraftRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _sd, _fhd, _uhd],
      minDuration: 4,
      maxDuration: 15,
      maxKeyframes: 2,
      maxImageReferences: 9,
      maxVideoReferences: 3,
      maxAudioReferences: 3,
      framesExclusiveWithReferences: true,
      maxReferenceVideoSeconds: 15,
      maxReferenceAudioSeconds: 15,
      requiresVisualReferenceForAudio: true,
      usdPerSecond: .25,
    ),
    _ArtCraftModel(
      id: 'seedance_2p0_bpu_fast',
      label: 'Seedance 2.0 Plus Ultra Fast',
      description: 'Faster Plus Ultra Seedance 2.0 generation.',
      aspectRatios: _artCraftRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _sd],
      minDuration: 4,
      maxDuration: 15,
      maxKeyframes: 2,
      maxImageReferences: 9,
      maxVideoReferences: 3,
      maxAudioReferences: 3,
      framesExclusiveWithReferences: true,
      maxReferenceVideoSeconds: 15,
      maxReferenceAudioSeconds: 15,
      requiresVisualReferenceForAudio: true,
      usdPerSecond: .20,
    ),
    _ArtCraftModel(
      id: 'seedance_2p0_mini',
      canonicalModelId: 'seedance-2.0-mini',
      label: 'Seedance 2.0 Mini',
      description: 'Economical Volcengine Seedance with rich references.',
      aspectRatios: _artCraftRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _sd],
      minDuration: 4,
      maxDuration: 15,
      maxKeyframes: 2,
      maxImageReferences: 9,
      maxVideoReferences: 3,
      maxAudioReferences: 3,
      framesExclusiveWithReferences: true,
      maxReferenceVideoSeconds: 15,
      maxReferenceAudioSeconds: 15,
      requiresVisualReferenceForAudio: true,
      usdPerSecond: .09,
    ),
    _ArtCraftModel(
      id: 'seedance_2p0_bp_mini',
      label: 'Seedance 2.0 Plus Mini',
      description: 'Economical BytePlus Seedance with rich references.',
      aspectRatios: _artCraftRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _sd],
      minDuration: 4,
      maxDuration: 15,
      maxKeyframes: 2,
      maxImageReferences: 9,
      maxVideoReferences: 3,
      maxAudioReferences: 3,
      framesExclusiveWithReferences: true,
      maxReferenceVideoSeconds: 15,
      maxReferenceAudioSeconds: 15,
      requiresVisualReferenceForAudio: true,
      usdPerSecond: .092,
    ),
    _ArtCraftModel(
      id: 'seedance_2p0_bpu_mini',
      label: 'Seedance 2.0 Plus Ultra Mini',
      description: 'Economical Plus Ultra Seedance with rich references.',
      aspectRatios: _artCraftRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _sd],
      minDuration: 4,
      maxDuration: 15,
      maxKeyframes: 2,
      maxImageReferences: 9,
      maxVideoReferences: 3,
      maxAudioReferences: 3,
      framesExclusiveWithReferences: true,
      maxReferenceVideoSeconds: 15,
      maxReferenceAudioSeconds: 15,
      requiresVisualReferenceForAudio: true,
      usdPerSecond: .092,
    ),
    _ArtCraftModel(
      id: 'seedance_2p5',
      canonicalModelId: 'seedance-2.5',
      label: 'Seedance 2.5',
      description:
          'Long-form Seedance with pinned first/last frames or rich references.',
      aspectRatios: _artCraftRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _sd, _fhd],
      minDuration: 4,
      maxDuration: 30,
      maxKeyframes: 2,
      maxImageReferences: 30,
      maxVideoReferences: 10,
      maxAudioReferences: 10,
      framesExclusiveWithReferences: true,
      maxReferenceVideoSeconds: 30,
      maxReferenceAudioSeconds: 30,
      aspectRatiosWithFrames: <String>['auto'],
      usdPerSecond: .268,
    ),
    _ArtCraftModel(
      id: 'seedance_2p5_u',
      label: 'Seedance 2.5 Ultra',
      description:
          'Seedance Ultra with pinned first/last frames or rich references.',
      aspectRatios: _artCraftRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _sd, _fhd],
      minDuration: 4,
      maxDuration: 30,
      maxKeyframes: 2,
      maxImageReferences: 30,
      maxVideoReferences: 10,
      maxAudioReferences: 10,
      framesExclusiveWithReferences: true,
      maxReferenceVideoSeconds: 30,
      maxReferenceAudioSeconds: 30,
      aspectRatiosWithFrames: <String>['auto'],
      usdPerSecond: .316,
    ),
    _ArtCraftModel(
      id: 'seedance_2p5_preview',
      label: 'Seedance 2.5 Preview',
      description:
          'Reference-only Seedance preview for videos up to 30 seconds.',
      aspectRatios: _artCraftRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _sd],
      minDuration: 4,
      maxDuration: 30,
      maxKeyframes: 0,
      supportsStartFrame: false,
      supportsEndFrame: false,
      maxImageReferences: 30,
      maxVideoReferences: 10,
      maxAudioReferences: 10,
      maxReferenceVideoSeconds: 30,
      maxReferenceAudioSeconds: 30,
      usdPerSecond: .428,
      supportsText: false,
    ),
    _ArtCraftModel(
      id: 'seedance_1p5_pro',
      label: 'Seedance 1.5 Pro',
      description: 'High-quality Seedance with start and end frames.',
      aspectRatios: _artCraftAutoRatios,
      resolutions: <VideoResolutionDefinition>[_fhd, _hd, _sd],
      minDuration: 4,
      maxDuration: 12,
      maxKeyframes: 2,
      usdPerSecond: .16875,
      supportsAudio: true,
    ),
    _ArtCraftModel(
      id: 'flux_3',
      canonicalModelId: 'flux-3',
      label: 'FLUX 3',
      description: 'Multimodal FLUX video with synchronized audio.',
      aspectRatios: _artCraftAutoRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _fhd],
      minDuration: 5,
      maxDuration: 20,
      maxKeyframes: 2,
      usdPerSecond: .196,
      supportsAudio: true,
    ),
    _ArtCraftModel(
      id: 'flux_3_draft',
      canonicalModelId: 'flux-3-draft',
      label: 'FLUX 3 Draft',
      description: 'Fast, low-cost FLUX 3 drafts with audio.',
      aspectRatios: _artCraftAutoRatios,
      resolutions: <VideoResolutionDefinition>[_hd],
      minDuration: 5,
      maxDuration: 20,
      maxKeyframes: 2,
      usdPerSecond: .07,
      supportsAudio: true,
    ),
    _ArtCraftModel(
      id: 'grok_imagine_video',
      canonicalModelId: 'grok-imagine-video',
      label: 'Grok Imagine',
      description: 'Fast video generation with up to seven references.',
      aspectRatios: _artCraftGrokRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _sd],
      minDuration: 1,
      maxDuration: 15,
      maxKeyframes: 1,
      supportsEndFrame: false,
      maxImageReferences: 7,
      framesExclusiveWithReferences: true,
      maxDurationWithImageGuidance: 10,
      usdPerSecond: .09125,
    ),
    _ArtCraftModel(
      id: 'grok_imagine_video_1p5',
      canonicalModelId: 'grok-imagine-video-1.5',
      label: 'Grok Imagine 1.5',
      description: 'Fast, high-quality image-to-video generation.',
      aspectRatios: _artCraftGrokRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _sd, _fhd],
      minDuration: 1,
      maxDuration: 15,
      maxKeyframes: 1,
      supportsEndFrame: false,
      maxDurationWithImageGuidance: 10,
      usdPerSecond: .1475,
      supportsText: false,
    ),
    _ArtCraftModel(
      id: 'happy_horse_1p0',
      label: 'Happy Horse 1.0',
      description: 'Alibaba video generation up to Full HD.',
      aspectRatios: _artCraftCommonRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _fhd],
      minDuration: 3,
      maxDuration: 15,
      maxKeyframes: 1,
      supportsEndFrame: false,
      usdPerSecond: .17,
    ),
    _ArtCraftModel(
      id: 'kling_1p6_pro',
      label: 'Kling 1.6 Pro',
      description: 'Kling generation with start, end, and image references.',
      aspectRatios: _artCraftKlingRatios,
      resolutions: <VideoResolutionDefinition>[_hd],
      minDuration: 5,
      maxDuration: 10,
      durationStep: 5,
      maxKeyframes: 2,
      maxImageReferences: 4,
      usdPerSecond: .114,
    ),
    _ArtCraftModel(
      id: 'kling_2p5_turbo_pro',
      label: 'Kling 2.5 Turbo Pro',
      description: 'Fast Kling generation with first and last frames.',
      aspectRatios: _artCraftKlingRatios,
      resolutions: <VideoResolutionDefinition>[_hd],
      minDuration: 5,
      maxDuration: 10,
      durationStep: 5,
      maxKeyframes: 2,
      usdPerSecond: .082,
    ),
    _ArtCraftModel(
      id: 'kling_2p6_pro',
      label: 'Kling 2.6 Pro',
      description: 'High-quality Kling generation with first and last frames.',
      aspectRatios: _artCraftKlingRatios,
      resolutions: <VideoResolutionDefinition>[_hd],
      minDuration: 5,
      maxDuration: 10,
      durationStep: 5,
      maxKeyframes: 2,
      usdPerSecond: .162,
      supportsAudio: true,
    ),
    _ArtCraftModel(
      id: 'minimax_h3',
      label: 'MiniMax H3',
      description: 'Reference-rich MiniMax generation up to 2K.',
      aspectRatios: _artCraftRatios,
      resolutions: <VideoResolutionDefinition>[_twoK, _hd],
      minDuration: 5,
      maxDuration: 15,
      maxKeyframes: 2,
      maxImageReferences: 9,
      maxVideoReferences: 3,
      maxAudioReferences: 3,
      maxTotalReferences: 12,
      framesExclusiveWithReferences: true,
      maxReferenceVideoSeconds: 15,
      maxReferenceAudioSeconds: 15,
      requiresVisualReferenceForAudio: true,
      usdPerSecond: .30,
    ),
    _ArtCraftModel(
      id: 'veo_3_fast',
      label: 'Veo 3 Fast',
      description: 'Fast Veo video with synchronized audio.',
      aspectRatios: <String>['auto'],
      resolutions: <VideoResolutionDefinition>[_fhd, _hd],
      minDuration: 4,
      maxDuration: 8,
      maxKeyframes: 1,
      supportsEndFrame: false,
      usdPerSecond: .1725,
      supportsAudio: true,
    ),
    _ArtCraftModel(
      id: 'veo_3p1',
      canonicalModelId: 'veo-3.1',
      label: 'Veo 3.1',
      description: 'Premium Veo with references, audio, and 4K output.',
      aspectRatios: _artCraftVeoRatios,
      resolutions: <VideoResolutionDefinition>[_fhd, _hd, _uhd],
      minDuration: 4,
      maxDuration: 8,
      maxKeyframes: 2,
      maxImageReferences: 3,
      maxVideoReferences: 1,
      framesExclusiveWithReferences: true,
      usdPerSecond: .48,
      supportsAudio: true,
    ),
    _ArtCraftModel(
      id: 'veo_3p1_fast',
      canonicalModelId: 'veo-3.1-fast',
      label: 'Veo 3.1 Fast',
      description: 'Faster Veo 3.1 with references, audio, and 4K output.',
      aspectRatios: _artCraftVeoRatios,
      resolutions: <VideoResolutionDefinition>[_fhd, _hd, _uhd],
      minDuration: 4,
      maxDuration: 8,
      maxKeyframes: 2,
      maxImageReferences: 3,
      maxVideoReferences: 1,
      framesExclusiveWithReferences: true,
      usdPerSecond: .165,
      supportsAudio: true,
    ),
    _ArtCraftModel(
      id: 'veo_3p1_lite',
      canonicalModelId: 'veo-3.1-lite',
      label: 'Veo 3.1 Lite',
      description: 'Economical Veo with first and last frames plus audio.',
      aspectRatios: _artCraftVeoRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _fhd],
      minDuration: 4,
      maxDuration: 8,
      maxKeyframes: 2,
      usdPerSecond: .0575,
      supportsAudio: true,
    ),
    _ArtCraftModel(
      id: 'vidu_q3',
      canonicalModelId: 'vidu-q3',
      label: 'Vidu Q3',
      description: 'Vidu generation with references and synchronized audio.',
      aspectRatios: _artCraftViduRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _sd, _fhd],
      minDuration: 1,
      maxDuration: 16,
      maxKeyframes: 2,
      maxImageReferences: 4,
      usdPerSecond: .164,
      supportsAudio: true,
    ),
    _ArtCraftModel(
      id: 'vidu_q3_turbo',
      canonicalModelId: 'vidu-q3-turbo',
      label: 'Vidu Q3 Turbo',
      description:
          'Fast Vidu generation with first and last frames plus audio.',
      aspectRatios: _artCraftViduRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _sd, _fhd],
      minDuration: 1,
      maxDuration: 16,
      maxKeyframes: 2,
      usdPerSecond: .084,
      supportsAudio: true,
    ),
  ],
);

class _AtlasRouteModel extends VideoModelDefinition {
  const _AtlasRouteModel({
    required super.id,
    required super.canonicalModelId,
    required super.label,
    required super.description,
    required super.aspectRatios,
    required super.resolutions,
    required super.minDuration,
    required super.maxDuration,
    required super.usdPerSecond,
    super.durationStep = 1,
    super.supportsAudio = true,
    super.supportsSeed = false,
    bool imageRoute = false,
    bool supportsEndFrame = false,
  }) : super(
         modes: imageRoute
             ? const <VideoMode>[VideoMode.i2v]
             : const <VideoMode>[VideoMode.t2v],
         maxKeyframes: imageRoute ? (supportsEndFrame ? 2 : 1) : 0,
         referenceUsdPerSecond: imageRoute ? usdPerSecond : null,
         supportsStartFrame: imageRoute,
         supportsEndFrame: imageRoute && supportsEndFrame,
       );
}

const _atlasProvider = VideoProviderDefinition(
  id: 'atlas',
  name: 'Atlas Cloud',
  description: 'A broad model marketplace with live, preflight pricing.',
  consoleUrl: 'https://www.atlascloud.ai/console',
  docsUrl: 'https://www.atlascloud.ai/docs/models/video',
  pricingUrl: 'https://www.atlascloud.ai/pricing/models?sort=new',
  pricingSource:
      'Live Atlas Cloud 720p cost preflight, with published starting-rate fallback',
  resultDelivery: ProviderResultDelivery(keepOpenRecommended: true),
  models: <VideoModelDefinition>[
    VideoModelDefinition(
      id: 'bytedance/seedance-2.5/text-to-video',
      canonicalModelId: 'seedance-2.5',
      label: 'Seedance 2.5 · Text',
      description: 'Latest Seedance text-to-video with native audio.',
      modes: <VideoMode>[VideoMode.t2v],
      aspectRatios: _wideRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _sd, _fhd],
      minDuration: 4,
      maxDuration: 30,
      durationStep: 1,
      maxKeyframes: 0,
      usdPerSecond: .134,
      supportsAutoDuration: true,
    ),
    VideoModelDefinition(
      id: 'bytedance/seedance-2.5/image-to-video',
      canonicalModelId: 'seedance-2.5',
      label: 'Seedance 2.5 · Frames',
      description: 'First/last-frame guided Seedance generation.',
      modes: <VideoMode>[VideoMode.i2v],
      aspectRatios: <String>['auto'],
      resolutions: <VideoResolutionDefinition>[_hd, _sd, _fhd],
      minDuration: 4,
      maxDuration: 30,
      durationStep: 1,
      maxKeyframes: 2,
      usdPerSecond: .134,
      referenceUsdPerSecond: .134,
      supportsStartFrame: true,
      supportsEndFrame: true,
      supportsAutoDuration: true,
    ),
    VideoModelDefinition(
      id: 'bytedance/seedance-2.5/reference-to-video',
      canonicalModelId: 'seedance-2.5',
      label: 'Seedance 2.5 · References',
      description: 'Multimodal generation from images, videos, and audio.',
      modes: <VideoMode>[VideoMode.i2v],
      aspectRatios: _wideRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _sd, _fhd],
      minDuration: 4,
      maxDuration: 30,
      durationStep: 1,
      maxKeyframes: 0,
      usdPerSecond: .134,
      referenceUsdPerSecond: .134,
      maxImageReferences: 30,
      maxVideoReferences: 10,
      maxAudioReferences: 10,
      maxReferenceVideoSeconds: 30,
      maxReferenceAudioSeconds: 30,
      referencePromptHint:
          'Edit keeps duration on Auto; edit and extend preserve the source aspect ratio.',
      referenceTasks: <MediaReferenceTask>[
        MediaReferenceTask.reference,
        MediaReferenceTask.edit,
        MediaReferenceTask.extend,
      ],
      supportsAutoDuration: true,
    ),
    VideoModelDefinition(
      id: 'bytedance/seedance-2.0/text-to-video',
      canonicalModelId: 'seedance-2.0',
      label: 'Seedance 2.0 · Text',
      description: 'Full-quality Seedance text-to-video with native audio.',
      modes: <VideoMode>[VideoMode.t2v],
      aspectRatios: _wideRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _sd, _fhd, _uhd],
      minDuration: 4,
      maxDuration: 15,
      durationStep: 1,
      maxKeyframes: 0,
      usdPerSecond: .112,
      supportsAutoDuration: true,
      aspectRatiosByResolution: <String, List<String>>{
        '4k': <String>['16:9'],
      },
    ),
    VideoModelDefinition(
      id: 'bytedance/seedance-2.0/image-to-video',
      canonicalModelId: 'seedance-2.0',
      label: 'Seedance 2.0 · Frames',
      description: 'Full-quality first/last-frame Seedance generation.',
      modes: <VideoMode>[VideoMode.i2v],
      aspectRatios: _wideRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _sd, _fhd, _uhd],
      minDuration: 4,
      maxDuration: 15,
      durationStep: 1,
      maxKeyframes: 2,
      usdPerSecond: .112,
      referenceUsdPerSecond: .112,
      supportsStartFrame: true,
      supportsEndFrame: true,
      supportsAutoDuration: true,
      aspectRatiosByResolution: <String, List<String>>{
        '4k': <String>['16:9'],
      },
    ),
    VideoModelDefinition(
      id: 'bytedance/seedance-2.0/reference-to-video',
      canonicalModelId: 'seedance-2.0',
      label: 'Seedance 2.0 · References',
      description: 'Multimodal generation from images, videos, and audio.',
      modes: <VideoMode>[VideoMode.i2v],
      aspectRatios: _wideRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _sd, _fhd, _uhd],
      minDuration: 4,
      maxDuration: 15,
      durationStep: 1,
      maxKeyframes: 0,
      usdPerSecond: .112,
      referenceUsdPerSecond: .112,
      maxImageReferences: 9,
      maxVideoReferences: 3,
      maxAudioReferences: 3,
      maxReferenceVideoSeconds: 15,
      maxReferenceAudioSeconds: 15,
      requiresVisualReferenceForAudio: true,
      supportsAutoDuration: true,
      aspectRatiosByResolution: <String, List<String>>{
        '4k': <String>['16:9'],
      },
    ),
    VideoModelDefinition(
      id: 'bytedance/seedance-2.0-fast/text-to-video',
      canonicalModelId: 'seedance-2.0-fast',
      label: 'Seedance 2.0 Fast · Text',
      description: 'Faster Seedance text-to-video with native audio.',
      modes: <VideoMode>[VideoMode.t2v],
      aspectRatios: _wideRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _sd],
      minDuration: 4,
      maxDuration: 15,
      durationStep: 1,
      maxKeyframes: 0,
      usdPerSecond: .072,
      supportsAutoDuration: true,
    ),
    VideoModelDefinition(
      id: 'bytedance/seedance-2.0-fast/image-to-video',
      canonicalModelId: 'seedance-2.0-fast',
      label: 'Seedance 2.0 Fast · Frames',
      description: 'Faster first/last-frame Seedance generation.',
      modes: <VideoMode>[VideoMode.i2v],
      aspectRatios: _wideRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _sd],
      minDuration: 4,
      maxDuration: 15,
      durationStep: 1,
      maxKeyframes: 2,
      usdPerSecond: .072,
      referenceUsdPerSecond: .072,
      supportsStartFrame: true,
      supportsEndFrame: true,
      supportsAutoDuration: true,
    ),
    VideoModelDefinition(
      id: 'bytedance/seedance-2.0-fast/reference-to-video',
      canonicalModelId: 'seedance-2.0-fast',
      label: 'Seedance 2.0 Fast · References',
      description:
          'Faster multimodal generation from images, video, and audio.',
      modes: <VideoMode>[VideoMode.i2v],
      aspectRatios: _wideRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _sd],
      minDuration: 4,
      maxDuration: 15,
      durationStep: 1,
      maxKeyframes: 0,
      usdPerSecond: .072,
      referenceUsdPerSecond: .072,
      maxImageReferences: 9,
      maxVideoReferences: 3,
      maxAudioReferences: 3,
      maxReferenceVideoSeconds: 15,
      maxReferenceAudioSeconds: 15,
      requiresVisualReferenceForAudio: true,
      supportsAutoDuration: true,
    ),
    VideoModelDefinition(
      id: 'bytedance/seedance-2.0-mini/text-to-video',
      canonicalModelId: 'seedance-2.0-mini',
      label: 'Seedance 2.0 Mini · Text',
      description: 'Low-cost Seedance text-to-video.',
      modes: <VideoMode>[VideoMode.t2v],
      aspectRatios: _wideRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _sd],
      minDuration: 4,
      maxDuration: 15,
      durationStep: 1,
      maxKeyframes: 0,
      usdPerSecond: .039,
      supportsAutoDuration: true,
    ),
    VideoModelDefinition(
      id: 'bytedance/seedance-2.0-mini/image-to-video',
      canonicalModelId: 'seedance-2.0-mini',
      label: 'Seedance 2.0 Mini · Frames',
      description: 'Low-cost first/last-frame generation.',
      modes: <VideoMode>[VideoMode.i2v],
      aspectRatios: _wideRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _sd],
      minDuration: 4,
      maxDuration: 15,
      durationStep: 1,
      maxKeyframes: 2,
      usdPerSecond: .039,
      referenceUsdPerSecond: .039,
      supportsStartFrame: true,
      supportsEndFrame: true,
      supportsAutoDuration: true,
    ),
    VideoModelDefinition(
      id: 'bytedance/seedance-2.0-mini/reference-to-video',
      canonicalModelId: 'seedance-2.0-mini',
      label: 'Seedance 2.0 Mini · References',
      description: 'Low-cost multi-reference generation.',
      modes: <VideoMode>[VideoMode.i2v],
      aspectRatios: _wideRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _sd],
      minDuration: 4,
      maxDuration: 15,
      durationStep: 1,
      maxKeyframes: 0,
      usdPerSecond: .039,
      referenceUsdPerSecond: .039,
      maxImageReferences: 9,
      maxVideoReferences: 3,
      maxAudioReferences: 3,
      maxReferenceVideoSeconds: 15,
      maxReferenceAudioSeconds: 15,
      requiresVisualReferenceForAudio: true,
      supportsAutoDuration: true,
    ),
    _AtlasRouteModel(
      id: 'xai/grok-imagine-video-v1.5/text-to-video',
      canonicalModelId: 'grok-imagine-video-1.5',
      label: 'Grok Imagine 1.5 · Text',
      description: 'xAI text-to-video with native synchronized audio.',
      aspectRatios: _artCraftCommonRatios,
      resolutions: <VideoResolutionDefinition>[_sd, _hd, _fhd],
      minDuration: 1,
      maxDuration: 15,
      usdPerSecond: .08,
    ),
    _AtlasRouteModel(
      id: 'xai/grok-imagine-video-v1.5/image-to-video',
      canonicalModelId: 'grok-imagine-video-1.5',
      label: 'Grok Imagine 1.5 · Image',
      description: 'xAI image-to-video with native synchronized audio.',
      aspectRatios: _artCraftCommonRatios,
      resolutions: <VideoResolutionDefinition>[_sd, _hd, _fhd],
      minDuration: 1,
      maxDuration: 15,
      usdPerSecond: .08,
      imageRoute: true,
    ),
    _AtlasRouteModel(
      id: 'google/veo3.1-fast/text-to-video',
      canonicalModelId: 'veo-3.1-fast',
      label: 'Veo 3.1 Fast · Text',
      description: 'Fast Veo text generation with optional native audio.',
      aspectRatios: _ltxRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _fhd, _uhd],
      minDuration: 4,
      maxDuration: 8,
      durationStep: 2,
      usdPerSecond: .08,
    ),
    _AtlasRouteModel(
      id: 'google/veo3.1-fast/image-to-video',
      canonicalModelId: 'veo-3.1-fast',
      label: 'Veo 3.1 Fast · Frames',
      description: 'Fast Veo generation from first and last frames.',
      aspectRatios: _ltxRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _fhd, _uhd],
      minDuration: 4,
      maxDuration: 8,
      durationStep: 2,
      usdPerSecond: .08,
      imageRoute: true,
      supportsEndFrame: true,
    ),
    _AtlasRouteModel(
      id: 'alibaba/wan-2.7/text-to-video',
      canonicalModelId: 'wan-2.7',
      label: 'Wan 2.7 · Text',
      description: 'Wan text generation with multi-shot narrative support.',
      aspectRatios: _artCraftCommonRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _fhd, _qhd],
      minDuration: 2,
      maxDuration: 15,
      usdPerSecond: .10,
      supportsSeed: true,
    ),
    _AtlasRouteModel(
      id: 'alibaba/wan-2.7/image-to-video',
      canonicalModelId: 'wan-2.7',
      label: 'Wan 2.7 · Frames',
      description: 'Wan generation from first and optional last frames.',
      aspectRatios: _artCraftCommonRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _fhd],
      minDuration: 2,
      maxDuration: 15,
      usdPerSecond: .10,
      supportsSeed: true,
      imageRoute: true,
      supportsEndFrame: true,
    ),
    _AtlasRouteModel(
      id: 'kwaivgi/kling-v3.0-pro/text-to-video',
      canonicalModelId: 'kling-3.0-pro',
      label: 'Kling 3.0 Pro · Text',
      description: 'Kling Pro text generation with optional sound.',
      aspectRatios: _artCraftKlingRatios,
      resolutions: <VideoResolutionDefinition>[_fhd],
      minDuration: 3,
      maxDuration: 15,
      usdPerSecond: .095,
    ),
    _AtlasRouteModel(
      id: 'kwaivgi/kling-v3.0-pro/image-to-video',
      canonicalModelId: 'kling-3.0-pro',
      label: 'Kling 3.0 Pro · Frames',
      description: 'Kling Pro generation from first and last frames.',
      aspectRatios: _artCraftKlingRatios,
      resolutions: <VideoResolutionDefinition>[_fhd, _qhd],
      minDuration: 3,
      maxDuration: 15,
      usdPerSecond: .095,
      imageRoute: true,
      supportsEndFrame: true,
    ),
    _AtlasRouteModel(
      id: 'vidu/q3-turbo/text-to-video',
      canonicalModelId: 'vidu-q3-turbo',
      label: 'Vidu Q3 Turbo · Text',
      description: 'Fast Vidu text generation with optional audio.',
      aspectRatios: _artCraftViduRatios,
      resolutions: <VideoResolutionDefinition>[_sd, _hd, _fhd, _qhd],
      minDuration: 1,
      maxDuration: 16,
      usdPerSecond: .034,
    ),
    _AtlasRouteModel(
      id: 'vidu/q3-turbo/image-to-video',
      canonicalModelId: 'vidu-q3-turbo',
      label: 'Vidu Q3 Turbo · Image',
      description: 'Fast Vidu generation from a starting image.',
      aspectRatios: _artCraftViduRatios,
      resolutions: <VideoResolutionDefinition>[_sd, _hd, _fhd, _qhd],
      minDuration: 1,
      maxDuration: 16,
      usdPerSecond: .034,
      imageRoute: true,
    ),
    _AtlasRouteModel(
      id: 'pixverse/v6/text-to-video',
      canonicalModelId: 'pixverse-v6',
      label: 'PixVerse V6 · Text',
      description: 'PixVerse text generation with optional sound.',
      aspectRatios: _artCraftRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _fhd],
      minDuration: 1,
      maxDuration: 15,
      usdPerSecond: .025,
    ),
    _AtlasRouteModel(
      id: 'pixverse/v6/image-to-video',
      canonicalModelId: 'pixverse-v6',
      label: 'PixVerse V6 · Image',
      description: 'PixVerse generation from a starting image.',
      aspectRatios: _artCraftRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _fhd],
      minDuration: 1,
      maxDuration: 15,
      usdPerSecond: .025,
      imageRoute: true,
    ),
    _AtlasRouteModel(
      id: 'minimax/hailuo-2.3/t2v-standard',
      canonicalModelId: 'hailuo-2.3-standard',
      label: 'Hailuo 2.3 Standard · Text',
      description: 'Cinematic MiniMax text-to-video generation.',
      aspectRatios: <String>['auto'],
      resolutions: <VideoResolutionDefinition>[_hd],
      minDuration: 6,
      maxDuration: 10,
      durationStep: 4,
      usdPerSecond: .28,
      supportsAudio: false,
    ),
    _AtlasRouteModel(
      id: 'minimax/hailuo-2.3/i2v-standard',
      canonicalModelId: 'hailuo-2.3-standard',
      label: 'Hailuo 2.3 Standard · Image',
      description: 'Cinematic MiniMax generation from a starting image.',
      aspectRatios: <String>['auto'],
      resolutions: <VideoResolutionDefinition>[_hd],
      minDuration: 6,
      maxDuration: 10,
      durationStep: 4,
      usdPerSecond: .28,
      supportsAudio: false,
      imageRoute: true,
    ),
    _AtlasRouteModel(
      id: 'black-forest-labs/flux-3/text-to-video',
      canonicalModelId: 'flux-3',
      label: 'FLUX 3 · Text',
      description: 'FLUX 3 text-to-video with synchronized audio.',
      aspectRatios: _wideRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _fhd],
      minDuration: 5,
      maxDuration: 20,
      usdPerSecond: .17,
    ),
    _AtlasRouteModel(
      id: 'black-forest-labs/flux-3/image-to-video',
      canonicalModelId: 'flux-3',
      label: 'FLUX 3 · Image',
      description: 'FLUX 3 generation from a starting image.',
      aspectRatios: _wideRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _fhd],
      minDuration: 5,
      maxDuration: 20,
      usdPerSecond: .17,
      imageRoute: true,
    ),
  ],
);

const appleLocalProvider = VideoProviderDefinition(
  id: 'apple-local',
  adapter: 'apple-local',
  name: 'Apple Intelligence',
  description:
      'Keyless image creation through Apple Intelligence on this device, including a silent image-sequence video option.',
  consoleUrl: 'https://support.apple.com/121115',
  docsUrl: 'https://developer.apple.com/documentation/imageplayground',
  pricingUrl: 'https://support.apple.com/121115',
  pricingSource: 'Apple system service · no provider charge',
  requiresApiKey: false,
  isLocal: true,
  resultDelivery: ProviderResultDelivery(),
  progressReporting: ProviderProgressReporting.reported,
  models: <VideoModelDefinition>[
    VideoModelDefinition(
      id: 'apple-local-image',
      label: 'Apple Image',
      description:
          'Creates one still image with Apple Intelligence on this device.',
      modes: <VideoMode>[VideoMode.t2v],
      aspectRatios: _appleLocalRatios,
      resolutions: <VideoResolutionDefinition>[
        _appleLocalStandard,
        _appleLocalLarge,
      ],
      minDuration: 1,
      maxDuration: 1,
      durationStep: 1,
      maxKeyframes: 0,
      usdPerSecond: 0,
      supportsAudio: false,
      maxPromptCharacters: 900,
      outputKind: GenerationOutputKind.image,
      progressReporting: ProviderProgressReporting.reported,
    ),
    VideoModelDefinition(
      id: 'apple-local-animation',
      label: 'Apple Image Sequence',
      description:
          'Creates one Apple-generated image per selected second and encodes the sequence as a silent MP4.',
      modes: <VideoMode>[VideoMode.t2v],
      aspectRatios: _appleLocalRatios,
      resolutions: <VideoResolutionDefinition>[
        _appleLocalStandard,
        _appleLocalLarge,
      ],
      minDuration: 1,
      maxDuration: 8,
      durationStep: 1,
      maxKeyframes: 0,
      usdPerSecond: 0,
      supportsAudio: false,
      maxPromptCharacters: 900,
      progressReporting: ProviderProgressReporting.reported,
    ),
  ],
);

const bundledVideoProviders = <VideoProviderDefinition>[
  appleLocalProvider,
  _artCraftProvider,
  _atlasProvider,
  _bflProvider,
  _ltxProvider,
  _runwayProvider,
];

List<VideoProviderDefinition> mobileTestProviderCatalog(
  List<VideoProviderDefinition> providers,
) {
  final provider = providers
      .where(
        (candidate) =>
            candidate.id == mobileTestProviderId &&
            candidate.adapter == mobileTestProviderId,
      )
      .firstOrNull;
  final model = provider?.models
      .where((candidate) => candidate.id == mobileTestModelId)
      .firstOrNull;
  final resolution = model?.resolutions
      .where((candidate) => candidate.id == mobileTestResolutionId)
      .firstOrNull;
  if (provider == null || model == null || resolution == null) {
    return const <VideoProviderDefinition>[];
  }
  final appleProviders = providers.where(
    (candidate) => candidate.adapter == 'apple-local' && candidate.isLocal,
  );
  return <VideoProviderDefinition>[
    VideoProviderDefinition(
      id: provider.id,
      adapter: provider.adapter,
      name: provider.name,
      description: provider.description,
      consoleUrl: provider.consoleUrl,
      docsUrl: provider.docsUrl,
      pricingUrl: provider.pricingUrl,
      pricingSource: provider.pricingSource,
      requiresApiKey: provider.requiresApiKey,
      isLocal: provider.isLocal,
      resultDelivery: provider.resultDelivery,
      progressReporting: provider.progressReporting,
      models: <VideoModelDefinition>[
        model.constrainedForMobileTest(resolution),
      ],
    ),
    ...appleProviders,
  ];
}

List<VideoProviderDefinition> _activeVideoProviders = clawnsoleMobileTestBuild
    ? List<VideoProviderDefinition>.unmodifiable(
        mobileTestProviderCatalog(bundledVideoProviders),
      )
    : bundledVideoProviders;
bool _activeProviderCatalogIsMobileTest = clawnsoleMobileTestBuild;

List<VideoProviderDefinition> get videoProviders => _activeVideoProviders;
bool get activeProviderCatalogIsMobileTest =>
    _activeProviderCatalogIsMobileTest;

void installProviderCatalog(
  List<VideoProviderDefinition> providers, {
  bool mobileTest = false,
}) {
  _activeVideoProviders = List<VideoProviderDefinition>.unmodifiable(providers);
  _activeProviderCatalogIsMobileTest = mobileTest;
}

void resetProviderCatalog({bool mobileTestBuild = clawnsoleMobileTestBuild}) {
  _activeVideoProviders = mobileTestBuild
      ? List<VideoProviderDefinition>.unmodifiable(
          mobileTestProviderCatalog(bundledVideoProviders),
        )
      : bundledVideoProviders;
  _activeProviderCatalogIsMobileTest = mobileTestBuild;
}

VideoProviderDefinition? providerByIdOrNull(String id) =>
    videoProviders.where((provider) => provider.id == id).firstOrNull;

VideoProviderDefinition? providerByIdForRouting(String id) =>
    providerByIdOrNull(id) ??
    bundledVideoProviders.where((provider) => provider.id == id).firstOrNull;

VideoProviderDefinition providerById(String id) =>
    providerByIdOrNull(id) ??
    providerByIdOrNull('bfl') ??
    videoProviders.firstOrNull ??
    _bflProvider;

VideoProviderDefinition get artCraftProvider =>
    providerByIdOrNull('artcraft') ?? _artCraftProvider;
VideoProviderDefinition get atlasProvider =>
    providerByIdOrNull('atlas') ?? _atlasProvider;
VideoProviderDefinition get bflProvider =>
    providerByIdOrNull('bfl') ?? _bflProvider;
VideoProviderDefinition get ltxProvider =>
    providerByIdOrNull('ltx') ?? _ltxProvider;
VideoProviderDefinition get runwayProvider =>
    providerByIdOrNull('runway') ?? _runwayProvider;

String providerNameForHistory(String id) =>
    providerByIdForRouting(id)?.name ?? id;

VideoModelDefinition modelById(String providerId, String modelId) {
  final provider = providerById(providerId);
  return provider.models.firstWhere(
    (model) => model.id == modelId,
    orElse: () => provider.defaultModel,
  );
}

String canonicalModelIdFor(String providerId, String modelId) {
  final baseModelId = modelId.split(':').first;
  final provider = providerById(providerId);
  return provider.models
          .where((model) => model.id == baseModelId)
          .firstOrNull
          ?.canonicalId ??
      baseModelId;
}

ProviderProgressReporting progressReportingFor(
  String providerId,
  String modelId,
) {
  final provider = videoProviders
      .where((candidate) => candidate.id == providerId)
      .firstOrNull;
  if (provider == null) return ProviderProgressReporting.none;
  final baseModelId = modelId.split(':').first;
  final model = provider.models
      .where((candidate) => candidate.id == baseModelId)
      .firstOrNull;
  return model?.progressReporting ?? provider.progressReporting;
}

/// Returns only a percentage whose provider/model contract is trusted.
///
/// Keeping this check next to the catalog also hides stale persisted values
/// immediately, before the next provider poll has a chance to clear them.
double? trustedGenerationProgress(Generation generation) {
  if (progressReportingFor(generation.provider, generation.model) !=
      ProviderProgressReporting.reported) {
    return null;
  }
  return generation.progress?.clamp(0, 100).toDouble();
}

List<ProviderModelPrice> publishedProviderPrices(String providerId) {
  if (providerId == 'bfl') {
    return _availablePublishedPrices(providerId, const <ProviderModelPrice>[
      ProviderModelPrice(
        provider: 'bfl',
        model: 'flux-3-video:draft',
        canonicalModelId: 'flux-3',
        label: 'FLUX 3 · Draft HD',
        usdPerSecond: .06,
        referenceUsdPerSecond: .06,
        modes: <VideoMode>[VideoMode.t2v, VideoMode.i2v],
        source: 'published · draft',
        minDuration: 5,
        maxDuration: 20,
      ),
      ProviderModelPrice(
        provider: 'bfl',
        model: 'flux-3-video:hd',
        canonicalModelId: 'flux-3',
        label: 'FLUX 3 · HD',
        usdPerSecond: .17,
        referenceUsdPerSecond: .17,
        modes: <VideoMode>[VideoMode.t2v, VideoMode.i2v],
        source: 'published · 720p',
        minDuration: 5,
        maxDuration: 20,
      ),
      ProviderModelPrice(
        provider: 'bfl',
        model: 'flux-3-video:fhd',
        canonicalModelId: 'flux-3',
        label: 'FLUX 3 · Full HD',
        usdPerSecond: .29,
        referenceUsdPerSecond: .29,
        modes: <VideoMode>[VideoMode.t2v, VideoMode.i2v],
        source: 'published · 1080p',
        minDuration: 5,
        maxDuration: 20,
      ),
      ProviderModelPrice(
        provider: 'bfl',
        model: 'flux-tools-video-upscale-v1:precise',
        canonicalModelId: 'flux-video-upscale',
        label: 'FLUX Video Upscale · Precise',
        usdPerSecond: .07,
        modes: <VideoMode>[VideoMode.upscale],
        source: 'published · delivered output',
        minDuration: 1,
        maxDuration: 20,
        pricingUnit: 'per-megapixel-second',
      ),
      ProviderModelPrice(
        provider: 'bfl',
        model: 'flux-tools-video-upscale-v1:creative',
        canonicalModelId: 'flux-video-upscale',
        label: 'FLUX Video Upscale · Creative',
        usdPerSecond: .10,
        modes: <VideoMode>[VideoMode.upscale],
        source: 'published · delivered output',
        minDuration: 1,
        maxDuration: 20,
        pricingUnit: 'per-megapixel-second',
      ),
    ]);
  }
  if (providerId == 'ltx') {
    const rates = <String, Map<String, double>>{
      'ltx-2-3-fast': <String, double>{
        '720p': .03,
        '1080p': .06,
        '1440p': .12,
        '4K': .24,
      },
      'ltx-2-3-pro': <String, double>{
        '720p': .04,
        '1080p': .08,
        '1440p': .16,
        '4K': .32,
      },
    };
    return ltxProvider.models.expand((model) {
      final tiers = rates[model.id];
      if (tiers == null) return <ProviderModelPrice>[model.price('ltx')];
      return tiers.entries.map(
        (entry) => ProviderModelPrice(
          provider: 'ltx',
          model: '${model.id}:${entry.key}',
          canonicalModelId: model.canonicalId,
          label: '${model.label} · ${entry.key}',
          usdPerSecond: entry.value,
          referenceUsdPerSecond: entry.value,
          modes: model.modes,
          source: 'published · ${entry.key}',
          minDuration: model.minDuration,
          maxDuration: model.maxDuration,
          durationStep: model.durationStep,
        ),
      );
    }).toList();
  }
  if (providerId == 'runway') {
    ProviderModelPrice rate(
      String model,
      String label,
      double creditsPerSecond, {
      required List<VideoMode> modes,
      required int minimum,
      required int maximum,
      String? canonical,
      String detail = 'published',
    }) => ProviderModelPrice(
      provider: 'runway',
      model: model,
      canonicalModelId: canonical,
      label: label,
      usdPerSecond: creditsPerSecond * .01,
      referenceUsdPerSecond: creditsPerSecond * .01,
      modes: modes,
      source: '$detail · ${creditsPerSecond.toStringAsFixed(0)} credits/s',
      minDuration: minimum,
      maxDuration: maximum,
    );

    return _availablePublishedPrices(providerId, <ProviderModelPrice>[
      rate(
        'seedance2_5:480p',
        'Seedance 2.5 · 480p',
        20,
        modes: const <VideoMode>[VideoMode.t2v, VideoMode.i2v, VideoMode.v2v],
        minimum: 4,
        maximum: 30,
        canonical: 'seedance-2.5',
        detail: 'published · reference video adds 10 credits/input-s',
      ),
      rate(
        'seedance2_5:720p',
        'Seedance 2.5 · 720p',
        30,
        modes: const <VideoMode>[VideoMode.t2v, VideoMode.i2v, VideoMode.v2v],
        minimum: 4,
        maximum: 30,
        canonical: 'seedance-2.5',
        detail: 'published · reference video adds 15 credits/input-s',
      ),
      rate(
        'seedance2_5:1080p',
        'Seedance 2.5 · 1080p',
        68,
        modes: const <VideoMode>[VideoMode.t2v, VideoMode.i2v, VideoMode.v2v],
        minimum: 4,
        maximum: 30,
        canonical: 'seedance-2.5',
        detail: 'published · reference video adds 34 credits/input-s',
      ),
      for (final tier in const <(String, String, double)>[
        ('480p', '480p', 10),
        ('720p', '720p', 16),
        ('1080p', '1080p', 29),
      ])
        rate(
          'grok_imagine_1_5:${tier.$1}',
          'Grok Imagine 1.5 · ${tier.$2}',
          tier.$3,
          modes: const <VideoMode>[VideoMode.t2v, VideoMode.i2v],
          minimum: 1,
          maximum: 15,
          canonical: 'grok-imagine-video-1.5',
          detail: 'published · references add 1 credit each',
        ),
      for (final tier in const <(String, String, double)>[
        ('480p', '480p', 36),
        ('720p', '720p', 36),
        ('1080p', '1080p', 40),
        ('4K', '4K', 150),
      ])
        rate(
          'seedance2:${tier.$1}',
          'Seedance 2.0 · ${tier.$2}',
          tier.$3,
          modes: const <VideoMode>[VideoMode.t2v, VideoMode.i2v, VideoMode.v2v],
          minimum: 4,
          maximum: 15,
          canonical: 'seedance-2.0',
        ),
      for (final model in const <(String, String, double, String)>[
        ('seedance2_fast', 'Seedance 2.0 Fast', 29, 'seedance-2.0-fast'),
        ('seedance2_mini', 'Seedance 2.0 Mini', 16, 'seedance-2.0-mini'),
      ])
        for (final tier in const <String>['480p', '720p'])
          rate(
            '${model.$1}:$tier',
            '${model.$2} · $tier',
            model.$3,
            modes: const <VideoMode>[
              VideoMode.t2v,
              VideoMode.i2v,
              VideoMode.v2v,
            ],
            minimum: 4,
            maximum: 15,
            canonical: model.$4,
          ),
      rate(
        'hailuo3:720p',
        'Hailuo 3 · 768p',
        10,
        modes: const <VideoMode>[VideoMode.t2v, VideoMode.i2v, VideoMode.v2v],
        minimum: 5,
        maximum: 15,
        canonical: 'hailuo-3',
        detail: 'published · images add 2 credits each',
      ),
      rate(
        'hailuo3:1440p',
        'Hailuo 3 · 2K',
        15,
        modes: const <VideoMode>[VideoMode.t2v, VideoMode.i2v, VideoMode.v2v],
        minimum: 5,
        maximum: 15,
        canonical: 'hailuo-3',
        detail: 'published · images add 2 credits each',
      ),
      rate(
        'aleph2',
        'Aleph 2',
        28,
        modes: const <VideoMode>[VideoMode.v2v],
        minimum: 2,
        maximum: 30,
        canonical: 'aleph-2',
      ),
      rate(
        'gen4.5',
        'Gen-4.5',
        12,
        modes: const <VideoMode>[VideoMode.t2v, VideoMode.i2v],
        minimum: 2,
        maximum: 10,
        canonical: 'runway-gen-4.5',
      ),
      rate(
        'gen4_turbo',
        'Gen-4 Turbo',
        5,
        modes: const <VideoMode>[VideoMode.i2v],
        minimum: 2,
        maximum: 10,
        canonical: 'runway-gen-4-turbo',
      ),
      rate(
        'act_two',
        'Act-Two',
        5,
        modes: const <VideoMode>[VideoMode.v2v],
        minimum: 3,
        maximum: 30,
        canonical: 'runway-act-two',
      ),
      for (final model in const <(String, String, double, double, String)>[
        ('veo3.1', 'Veo 3.1', 40, 20, 'veo-3.1'),
        ('veo3.1_fast', 'Veo 3.1 Fast', 15, 10, 'veo-3.1-fast'),
      ]) ...<ProviderModelPrice>[
        rate(
          '${model.$1}:audio',
          '${model.$2} · Audio',
          model.$3,
          modes: const <VideoMode>[VideoMode.t2v, VideoMode.i2v],
          minimum: 4,
          maximum: 8,
          canonical: model.$5,
        ),
        rate(
          '${model.$1}:silent',
          '${model.$2} · Silent',
          model.$4,
          modes: const <VideoMode>[VideoMode.t2v, VideoMode.i2v],
          minimum: 4,
          maximum: 8,
          canonical: model.$5,
        ),
      ],
      rate(
        'happyhorse_1_0:720p',
        'Happy Horse 1.0 · 720p',
        15,
        modes: const <VideoMode>[VideoMode.t2v, VideoMode.i2v],
        minimum: 3,
        maximum: 15,
        canonical: 'happy-horse-1.0',
      ),
      rate(
        'happyhorse_1_0:1080p',
        'Happy Horse 1.0 · 1080p',
        30,
        modes: const <VideoMode>[VideoMode.t2v, VideoMode.i2v],
        minimum: 3,
        maximum: 15,
        canonical: 'happy-horse-1.0',
      ),
      rate(
        'gemini_omni_flash:generation',
        'Gemini Omni Flash · Generate',
        10,
        modes: const <VideoMode>[VideoMode.t2v, VideoMode.i2v],
        minimum: 3,
        maximum: 10,
        canonical: 'gemini-omni-flash',
        detail: 'published · image input adds 1 credit',
      ),
      rate(
        'gemini_omni_flash:edit',
        'Gemini Omni Flash · Edit',
        11,
        modes: const <VideoMode>[VideoMode.v2v],
        minimum: 3,
        maximum: 10,
        canonical: 'gemini-omni-flash',
        detail: 'published · includes input-video processing',
      ),
      for (final tier in const <(String, String, double)>[
        ('720p', '720p', .007),
        ('1080p', '1K', .007),
        ('1440p', '2K', .009),
        ('4K', '4K', .012),
      ])
        ProviderModelPrice(
          provider: 'runway',
          model: 'magnific_video_upscaler_creative:${tier.$1}',
          canonicalModelId: 'magnific-video-upscaler-creative',
          label: 'Magnific Video Upscaler · ${tier.$2}',
          usdPerSecond: tier.$3,
          modes: const <VideoMode>[VideoMode.upscale],
          source: 'published · per output frame',
          minDuration: 1,
          maxDuration: 30,
          pricingUnit: 'per-frame',
        ),
      const ProviderModelPrice(
        provider: 'runway',
        model: 'gwm1_avatars',
        canonicalModelId: 'gwm-1-avatars',
        label: 'GWM-1 Avatars · Realtime',
        usdPerSecond: .0033333333333333335,
        modes: <VideoMode>[],
        source:
            'published · interactive realtime only · 2-credit start + 2 credits/6s',
        createReady: false,
        pricingUnit: 'realtime-session',
      ),
    ]);
  }
  final provider = providerById(providerId);
  return provider.models.map((model) => model.price(provider.id)).toList();
}

List<ProviderModelPrice> _availablePublishedPrices(
  String providerId,
  List<ProviderModelPrice> prices,
) {
  final available = providerById(
    providerId,
  ).models.map((model) => model.id).toSet();
  return prices
      .where(
        (price) =>
            !price.createReady ||
            available.contains(price.model.split(':').first),
      )
      .toList();
}
