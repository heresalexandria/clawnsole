import 'models.dart';

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
    required this.usdPerSecond,
    this.referenceUsdPerSecond,
    this.supportsStartFrame = false,
    this.supportsEndFrame = false,
    this.maxImageReferences = 0,
    this.maxVideoReferences = 0,
    this.maxAudioReferences = 0,
    this.maxTotalReferences,
    this.framesExclusiveWithReferences = false,
    this.maxReferenceVideoSeconds,
    this.maxReferenceAudioSeconds,
    this.maxReferenceVideoSecondsByResolution = const <String, int>{},
    this.maxReferenceAudioSecondsByResolution = const <String, int>{},
    this.requiresVisualReferenceForAudio = false,
    this.maxDurationWithImageGuidance,
    this.maxDurationByResolution = const <String, int>{},
    this.aspectRatiosByResolution = const <String, List<String>>{},
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
  final double usdPerSecond;
  final double? referenceUsdPerSecond;
  final bool supportsStartFrame;
  final bool supportsEndFrame;
  final int maxImageReferences;
  final int maxVideoReferences;
  final int maxAudioReferences;
  final int? maxTotalReferences;

  /// The provider exposes pinned-keyframe and creative-reference modes as
  /// separate request shapes, so a generation cannot combine both.
  final bool framesExclusiveWithReferences;

  final int? maxReferenceVideoSeconds;
  final int? maxReferenceAudioSeconds;
  final Map<String, int> maxReferenceVideoSecondsByResolution;
  final Map<String, int> maxReferenceAudioSecondsByResolution;
  final bool requiresVisualReferenceForAudio;
  final int? maxDurationWithImageGuidance;
  final Map<String, int> maxDurationByResolution;
  final Map<String, List<String>> aspectRatiosByResolution;
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
  final GenerationOutputKind outputKind;

  /// Overrides the provider-wide progress contract for this model route.
  final ProviderProgressReporting? progressReporting;

  String get canonicalId => canonicalModelId ?? id;

  int maxReferences(MediaReferenceKind kind) => switch (kind) {
    MediaReferenceKind.image => maxImageReferences,
    MediaReferenceKind.video => maxVideoReferences,
    MediaReferenceKind.audio => maxAudioReferences,
  };

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

  List<String> aspectRatiosFor(String resolution, {bool withFrames = false}) =>
      withFrames && aspectRatiosWithFrames != null
      ? aspectRatiosWithFrames!
      : aspectRatiosByResolution[resolution] ?? aspectRatios;

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
  });

  final String id;
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
const bflProvider = VideoProviderDefinition(
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

const ltxProvider = VideoProviderDefinition(
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

const artCraftProvider = VideoProviderDefinition(
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
      description: 'Long-form Seedance with up to 30 reference images.',
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
      description: 'Long-form Seedance Ultra with extensive references.',
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

const atlasProvider = VideoProviderDefinition(
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

const videoProviders = <VideoProviderDefinition>[
  artCraftProvider,
  atlasProvider,
  bflProvider,
  ltxProvider,
];

VideoProviderDefinition providerById(String id) => videoProviders.firstWhere(
  (provider) => provider.id == id,
  orElse: () => bflProvider,
);

String providerNameForHistory(String id) =>
    id == 'apple-local' ? 'Apple Local · Retired' : providerById(id).name;

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
    return const <ProviderModelPrice>[
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
    ];
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
      return rates[model.id]!.entries.map(
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
  final provider = providerById(providerId);
  return provider.models.map((model) => model.price(provider.id)).toList();
}
