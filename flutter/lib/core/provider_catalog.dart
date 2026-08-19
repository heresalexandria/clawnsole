import 'models.dart';

class VideoResolutionDefinition {
  const VideoResolutionDefinition(this.id, this.label, this.detail);

  final String id;
  final String label;
  final String detail;
}

class VideoModelDefinition {
  const VideoModelDefinition({
    required this.id,
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
    this.maxReferenceVideoSeconds,
    this.maxReferenceAudioSeconds,
    this.requiresVisualReferenceForAudio = false,
    this.maxDurationByResolution = const <String, int>{},
    this.aspectRatiosByResolution = const <String, List<String>>{},
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
    this.outputKind = GenerationOutputKind.video,
  });

  final String id;
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
  final int? maxReferenceVideoSeconds;
  final int? maxReferenceAudioSeconds;
  final bool requiresVisualReferenceForAudio;
  final Map<String, int> maxDurationByResolution;
  final Map<String, List<String>> aspectRatiosByResolution;
  final Map<MediaReferenceKind, List<String>> resolutionsByReferenceKind;
  final String? referencePromptHint;
  final List<MediaReferenceTask> referenceTasks;
  final bool supportsAutoDuration;
  final bool supportsAudio;
  final bool supportsDraft;
  final bool supportsTimedKeyframes;
  final bool supportsFrameRate;
  final GenerationOutputKind outputKind;

  int maxReferences(MediaReferenceKind kind) => switch (kind) {
    MediaReferenceKind.image => maxImageReferences,
    MediaReferenceKind.video => maxVideoReferences,
    MediaReferenceKind.audio => maxAudioReferences,
  };

  bool get supportsMediaReferences =>
      maxImageReferences > 0 ||
      maxVideoReferences > 0 ||
      maxAudioReferences > 0;

  int maxDurationFor(String resolution) =>
      maxDurationByResolution[resolution] ?? maxDuration;

  List<String> aspectRatiosFor(String resolution) =>
      aspectRatiosByResolution[resolution] ?? aspectRatios;

  bool supportsResolutionForReferences(
    String resolution,
    Iterable<MediaReferenceKind> kinds,
  ) => kinds.every(
    (kind) => resolutionsByReferenceKind[kind]?.contains(resolution) ?? true,
  );

  ProviderModelPrice price(String provider) => ProviderModelPrice(
    provider: provider,
    model: id,
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
    required this.shortName,
    required this.description,
    required this.consoleUrl,
    required this.docsUrl,
    required this.pricingUrl,
    required this.models,
    this.pricingSource = 'Published rate card',
    this.requiresApiKey = true,
    this.isLocal = false,
  });

  final String id;
  final String name;
  final String shortName;
  final String description;
  final String consoleUrl;
  final String docsUrl;
  final String pricingUrl;
  final String pricingSource;
  final List<VideoModelDefinition> models;
  final bool requiresApiKey;
  final bool isLocal;

  VideoModelDefinition get defaultModel => models.first;
  String get model => defaultModel.id;
  String get modelLabel => defaultModel.label;
  List<VideoMode> get modes => defaultModel.modes;
  List<String> get aspectRatios => defaultModel.aspectRatios;
  int get minDuration => defaultModel.minDuration;
  int get maxDuration => defaultModel.maxDuration;
  int get maxKeyframes => defaultModel.maxKeyframes;
}

class _ArtCraftModel extends VideoModelDefinition {
  const _ArtCraftModel({
    required super.id,
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
    super.maxReferenceVideoSeconds,
    super.maxReferenceAudioSeconds,
    super.requiresVisualReferenceForAudio,
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
const _localRatios = <String>['16:9', '4:3', '1:1', '3:4', '9:16'];
const _local512 = VideoResolutionDefinition(
  'hd',
  'Standard',
  '512 px long edge',
);
const _local768 = VideoResolutionDefinition('fhd', 'Large', '768 px long edge');

const appleLocalProvider = VideoProviderDefinition(
  id: 'apple-local',
  name: 'Apple Local',
  shortName: 'Local',
  description:
      'Keyless still-image creation through Apple Intelligence on this device.',
  consoleUrl: '',
  docsUrl: 'https://developer.apple.com/documentation/imageplayground',
  pricingUrl: '',
  pricingSource: 'Apple system service · no provider charge',
  requiresApiKey: false,
  isLocal: true,
  models: <VideoModelDefinition>[
    VideoModelDefinition(
      id: 'apple-local-image',
      label: 'Local Image',
      description: 'One still image generated with Apple Image Playground.',
      modes: <VideoMode>[VideoMode.t2v, VideoMode.i2v],
      aspectRatios: _localRatios,
      resolutions: <VideoResolutionDefinition>[_local512, _local768],
      minDuration: 1,
      maxDuration: 1,
      durationStep: 1,
      maxKeyframes: 1,
      usdPerSecond: 0,
      supportsStartFrame: true,
      supportsAudio: false,
      outputKind: GenerationOutputKind.image,
    ),
  ],
);

const bflProvider = VideoProviderDefinition(
  id: 'bfl',
  name: 'Black Forest Labs',
  shortName: 'BFL',
  description: 'Multimodal video with synchronized audio and keyframe control.',
  consoleUrl: 'https://dashboard.bfl.ai',
  docsUrl: 'https://docs.bfl.ai/flux_3/flux3_video',
  pricingUrl: 'https://bfl.ai/pricing',
  pricingSource: 'Published credits · converted at \$0.01/credit',
  models: <VideoModelDefinition>[
    VideoModelDefinition(
      id: 'flux-3-video',
      label: 'FLUX 3',
      description: 'Multimodal generation, continuation, and draft enhance.',
      modes: VideoMode.values,
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
  ],
);

const ltxProvider = VideoProviderDefinition(
  id: 'ltx',
  name: 'LTX Studio',
  shortName: 'LTX',
  description: 'Production-focused video generation with native audio.',
  consoleUrl: 'https://console.ltx.io/',
  docsUrl: 'https://docs.ltx.io',
  pricingUrl: 'https://docs.ltx.io/pricing',
  models: <VideoModelDefinition>[
    VideoModelDefinition(
      id: 'ltx-2-3-fast',
      label: 'LTX 2.3 Fast',
      description: 'Economical long-form generation up to 4K.',
      modes: <VideoMode>[VideoMode.t2v, VideoMode.i2v],
      aspectRatios: _ltxRatios,
      resolutions: <VideoResolutionDefinition>[_fhd, _qhd, _uhd],
      minDuration: 6,
      maxDuration: 20,
      durationStep: 2,
      maxKeyframes: 2,
      usdPerSecond: .06,
      referenceUsdPerSecond: .06,
      supportsStartFrame: true,
      supportsEndFrame: true,
      maxDurationByResolution: <String, int>{'qhd': 10, '4k': 10},
    ),
    VideoModelDefinition(
      id: 'ltx-2-3-pro',
      label: 'LTX 2.3 Pro',
      description: 'High-fidelity 1080p–4K video generation.',
      modes: <VideoMode>[VideoMode.t2v, VideoMode.i2v],
      aspectRatios: _ltxRatios,
      resolutions: <VideoResolutionDefinition>[_fhd, _qhd, _uhd],
      minDuration: 6,
      maxDuration: 10,
      durationStep: 2,
      maxKeyframes: 2,
      usdPerSecond: .08,
      referenceUsdPerSecond: .08,
      supportsStartFrame: true,
      supportsEndFrame: true,
      maxAudioReferences: 1,
      maxReferenceAudioSeconds: 20,
      resolutionsByReferenceKind: <MediaReferenceKind, List<String>>{
        MediaReferenceKind.audio: <String>['fhd'],
      },
    ),
  ],
);

const artCraftProvider = VideoProviderDefinition(
  id: 'artcraft',
  name: 'ArtCraft',
  shortName: 'Art',
  description:
      'A broad, live video model catalog behind ArtCraft’s API-key Omni API.',
  consoleUrl: 'https://app.getartcraft.com/',
  docsUrl: 'https://storyteller-docs.netlify.app/',
  pricingUrl: 'https://app.getartcraft.com/pricing',
  pricingSource:
      'Live model availability · published default credit quotes converted at \$0.01/credit',
  models: <VideoModelDefinition>[
    _ArtCraftModel(
      id: 'seedance_2p0',
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
      maxReferenceVideoSeconds: 15,
      maxReferenceAudioSeconds: 15,
      requiresVisualReferenceForAudio: true,
      usdPerSecond: .186,
    ),
    _ArtCraftModel(
      id: 'seedance_2p0_fast',
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
      maxReferenceVideoSeconds: 15,
      maxReferenceAudioSeconds: 15,
      requiresVisualReferenceForAudio: true,
      usdPerSecond: .20,
    ),
    _ArtCraftModel(
      id: 'seedance_2p0_mini',
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
      maxReferenceVideoSeconds: 15,
      maxReferenceAudioSeconds: 15,
      requiresVisualReferenceForAudio: true,
      usdPerSecond: .092,
    ),
    _ArtCraftModel(
      id: 'seedance_2p5',
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
      maxReferenceVideoSeconds: 30,
      maxReferenceAudioSeconds: 30,
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
      maxReferenceVideoSeconds: 30,
      maxReferenceAudioSeconds: 30,
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
      label: 'Grok Imagine',
      description: 'Fast video generation with up to seven references.',
      aspectRatios: _artCraftGrokRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _sd],
      minDuration: 1,
      maxDuration: 15,
      maxKeyframes: 1,
      supportsEndFrame: false,
      maxImageReferences: 7,
      usdPerSecond: .09125,
    ),
    _ArtCraftModel(
      id: 'grok_imagine_video_1p5',
      label: 'Grok Imagine 1.5',
      description: 'Fast, high-quality image-to-video generation.',
      aspectRatios: _artCraftGrokRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _sd, _fhd],
      minDuration: 1,
      maxDuration: 15,
      maxKeyframes: 1,
      supportsEndFrame: false,
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
      label: 'Veo 3.1',
      description: 'Premium Veo with references, audio, and 4K output.',
      aspectRatios: _artCraftVeoRatios,
      resolutions: <VideoResolutionDefinition>[_fhd, _hd, _uhd],
      minDuration: 4,
      maxDuration: 8,
      maxKeyframes: 2,
      maxImageReferences: 3,
      maxVideoReferences: 1,
      usdPerSecond: .48,
      supportsAudio: true,
    ),
    _ArtCraftModel(
      id: 'veo_3p1_fast',
      label: 'Veo 3.1 Fast',
      description: 'Faster Veo 3.1 with references, audio, and 4K output.',
      aspectRatios: _artCraftVeoRatios,
      resolutions: <VideoResolutionDefinition>[_fhd, _hd, _uhd],
      minDuration: 4,
      maxDuration: 8,
      maxKeyframes: 2,
      maxImageReferences: 3,
      maxVideoReferences: 1,
      usdPerSecond: .165,
      supportsAudio: true,
    ),
    _ArtCraftModel(
      id: 'veo_3p1_lite',
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

const atlasProvider = VideoProviderDefinition(
  id: 'atlas',
  name: 'Atlas Cloud',
  shortName: 'Atlas',
  description: 'A broad model marketplace with live, preflight pricing.',
  consoleUrl: 'https://www.atlascloud.ai/console',
  docsUrl: 'https://www.atlascloud.ai/docs/models/video',
  pricingUrl: 'https://www.atlascloud.ai/pricing/models?sort=new',
  pricingSource:
      'Live Atlas 720p cost preflight, with published starting-rate fallback',
  models: <VideoModelDefinition>[
    VideoModelDefinition(
      id: 'bytedance/seedance-2.5/text-to-video',
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
      label: 'Seedance 2.5 · Frames',
      description: 'First/last-frame guided Seedance generation.',
      modes: <VideoMode>[VideoMode.i2v],
      aspectRatios: _wideRatios,
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
          'Name inputs with @Image1, @Video1, or @Audio1. Edit keeps duration on Auto; edit and extend preserve the source aspect ratio.',
      referenceTasks: <MediaReferenceTask>[
        MediaReferenceTask.reference,
        MediaReferenceTask.edit,
        MediaReferenceTask.extend,
      ],
      supportsAutoDuration: true,
    ),
    VideoModelDefinition(
      id: 'bytedance/seedance-2.0/text-to-video',
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
      referencePromptHint:
          'Name inputs as image 1, video 1, or audio 1 in the prompt.',
      supportsAutoDuration: true,
      aspectRatiosByResolution: <String, List<String>>{
        '4k': <String>['16:9'],
      },
    ),
    VideoModelDefinition(
      id: 'bytedance/seedance-2.0-fast/text-to-video',
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
      referencePromptHint:
          'Name inputs as image 1, video 1, or audio 1 in the prompt.',
      supportsAutoDuration: true,
    ),
    VideoModelDefinition(
      id: 'bytedance/seedance-2.0-mini/text-to-video',
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
      referencePromptHint:
          'Name inputs as image 1, video 1, or audio 1 in the prompt.',
      supportsAutoDuration: true,
    ),
  ],
);

const videoProviders = <VideoProviderDefinition>[
  appleLocalProvider,
  bflProvider,
  ltxProvider,
  artCraftProvider,
  atlasProvider,
];

VideoProviderDefinition providerById(String id) => videoProviders.firstWhere(
  (provider) => provider.id == id,
  orElse: () => bflProvider,
);

VideoModelDefinition modelById(String providerId, String modelId) {
  final provider = providerById(providerId);
  return provider.models.firstWhere(
    (model) => model.id == modelId,
    orElse: () => provider.defaultModel,
  );
}

List<ProviderModelPrice> publishedProviderPrices(String providerId) {
  if (providerId == 'bfl') {
    return const <ProviderModelPrice>[
      ProviderModelPrice(
        provider: 'bfl',
        model: 'flux-3-video:draft',
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
        label: 'FLUX 3 · Full HD',
        usdPerSecond: .29,
        referenceUsdPerSecond: .29,
        modes: <VideoMode>[VideoMode.t2v, VideoMode.i2v],
        source: 'published · 1080p',
        minDuration: 5,
        maxDuration: 20,
      ),
    ];
  }
  if (providerId == 'ltx') {
    const rates = <String, Map<String, double>>{
      'ltx-2-3-fast': <String, double>{'1080p': .06, '1440p': .12, '4K': .24},
      'ltx-2-3-pro': <String, double>{'1080p': .08, '1440p': .16, '4K': .32},
    };
    return ltxProvider.models.expand((model) {
      return rates[model.id]!.entries.map(
        (entry) => ProviderModelPrice(
          provider: 'ltx',
          model: '${model.id}:${entry.key}',
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
