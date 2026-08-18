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
  final bool supportsAutoDuration;
  final bool supportsAudio;
  final bool supportsDraft;
  final bool supportsTimedKeyframes;
  final bool supportsFrameRate;
  final GenerationOutputKind outputKind;

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
    source: provider == 'atlas' ? 'published · starting rate' : 'published',
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

const _hd = VideoResolutionDefinition('hd', 'HD', '1280 × 720');
const _fhd = VideoResolutionDefinition('fhd', 'Full HD', '1920 × 1080');
const _qhd = VideoResolutionDefinition('qhd', '1440p', '2560 × 1440');
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
      'Keyless image creation through Apple Intelligence on this device. The experimental animation mode renders a sequence of generated frames.',
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
      supportsAudio: false,
      outputKind: GenerationOutputKind.image,
    ),
    VideoModelDefinition(
      id: 'apple-local-animation',
      label: 'Frame Animation · Experimental',
      description:
          'Builds a simple silent MP4 through one Apple-generated cartoon image per frame.',
      modes: <VideoMode>[VideoMode.t2v, VideoMode.i2v],
      aspectRatios: _localRatios,
      resolutions: <VideoResolutionDefinition>[_local512, _local768],
      minDuration: 1,
      maxDuration: 8,
      durationStep: 1,
      maxKeyframes: 1,
      usdPerSecond: 0,
      supportsAudio: false,
      supportsFrameRate: true,
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
      id: 'ltx-2-5-fast',
      label: 'LTX 2.5 Fast',
      description: 'Longer, fast 720p–4K generations with audio.',
      modes: <VideoMode>[VideoMode.t2v, VideoMode.i2v],
      aspectRatios: _ltxRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _fhd, _qhd, _uhd],
      minDuration: 6,
      maxDuration: 20,
      durationStep: 2,
      maxKeyframes: 1,
      usdPerSecond: .09,
      referenceUsdPerSecond: .09,
      supportsAutoDuration: true,
    ),
    VideoModelDefinition(
      id: 'ltx-2-5-pro',
      label: 'LTX 2.5 Pro',
      description: 'Higher-fidelity 720p and 1080p video with audio.',
      modes: <VideoMode>[VideoMode.t2v, VideoMode.i2v],
      aspectRatios: _ltxRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _fhd],
      minDuration: 6,
      maxDuration: 10,
      durationStep: 2,
      maxKeyframes: 1,
      usdPerSecond: .12,
      referenceUsdPerSecond: .12,
      supportsAutoDuration: true,
    ),
    VideoModelDefinition(
      id: 'ltx-2-3-fast',
      label: 'LTX 2.3 Fast',
      description: 'Economical long-form generation up to 4K.',
      modes: <VideoMode>[VideoMode.t2v, VideoMode.i2v],
      aspectRatios: _ltxRatios,
      resolutions: <VideoResolutionDefinition>[_hd, _fhd, _qhd, _uhd],
      minDuration: 6,
      maxDuration: 20,
      durationStep: 2,
      maxKeyframes: 2,
      usdPerSecond: .03,
      referenceUsdPerSecond: .03,
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
      resolutions: <VideoResolutionDefinition>[_hd],
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
      resolutions: <VideoResolutionDefinition>[_hd],
      minDuration: 4,
      maxDuration: 30,
      durationStep: 1,
      maxKeyframes: 2,
      usdPerSecond: .134,
      referenceUsdPerSecond: .134,
      supportsAutoDuration: true,
    ),
    VideoModelDefinition(
      id: 'bytedance/seedance-2.5/reference-to-video',
      label: 'Seedance 2.5 · References',
      description: 'Reference-guided generation for visual identity.',
      modes: <VideoMode>[VideoMode.i2v],
      aspectRatios: _wideRatios,
      resolutions: <VideoResolutionDefinition>[_hd],
      minDuration: 4,
      maxDuration: 30,
      durationStep: 1,
      maxKeyframes: 30,
      usdPerSecond: .134,
      referenceUsdPerSecond: .134,
      supportsAutoDuration: true,
    ),
    VideoModelDefinition(
      id: 'bytedance/seedance-2.0-mini/text-to-video',
      label: 'Seedance 2.0 Mini · Text',
      description: 'Low-cost Seedance text-to-video.',
      modes: <VideoMode>[VideoMode.t2v],
      aspectRatios: _wideRatios,
      resolutions: <VideoResolutionDefinition>[_hd],
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
      resolutions: <VideoResolutionDefinition>[_hd],
      minDuration: 4,
      maxDuration: 15,
      durationStep: 1,
      maxKeyframes: 2,
      usdPerSecond: .039,
      referenceUsdPerSecond: .039,
      supportsAutoDuration: true,
    ),
    VideoModelDefinition(
      id: 'bytedance/seedance-2.0-mini/reference-to-video',
      label: 'Seedance 2.0 Mini · References',
      description: 'Low-cost multi-reference generation.',
      modes: <VideoMode>[VideoMode.i2v],
      aspectRatios: _wideRatios,
      resolutions: <VideoResolutionDefinition>[_hd],
      minDuration: 4,
      maxDuration: 15,
      durationStep: 1,
      maxKeyframes: 9,
      usdPerSecond: .039,
      referenceUsdPerSecond: .039,
      supportsAutoDuration: true,
    ),
  ],
);

const videoProviders = <VideoProviderDefinition>[
  appleLocalProvider,
  bflProvider,
  ltxProvider,
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
      'ltx-2-5-fast': <String, double>{
        '720p': .09,
        '1080p': .13,
        '1440p': .19,
        '4K': .30,
      },
      'ltx-2-5-pro': <String, double>{'720p': .12, '1080p': .17},
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
