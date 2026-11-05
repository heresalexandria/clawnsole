import 'models.dart';
import 'provider_catalog.dart';

const apipodProvider = VideoProviderDefinition(
  id: 'apipod',
  name: 'APIPod',
  description: 'Seedance 2.5 with native audio and hosted media references.',
  consoleUrl: 'https://www.apipod.ai/console/api-keys',
  docsUrl: 'https://docs.apipod.ai/',
  pricingUrl: 'https://www.apipod.ai/models/seedance-2.5',
  pricingSource:
      'Published APIPod estimates; final token usage determines cost',
  progressReporting: ProviderProgressReporting.reported,
  models: <VideoModelDefinition>[
    VideoModelDefinition(
      id: 'seedance-2.5-t2v',
      canonicalModelId: 'seedance-2.5',
      label: 'Seedance 2.5 · Text',
      description: 'Generate 4–30 seconds with synchronized audio.',
      modes: <VideoMode>[VideoMode.t2v],
      aspectRatios: _ratios,
      resolutions: _resolutions,
      minDuration: 4,
      maxDuration: 30,
      durationStep: 1,
      maxKeyframes: 0,
      usdPerSecond: .2205,
      maxPromptCharacters: 30000,
    ),
    VideoModelDefinition(
      id: 'seedance-2.5-i2v',
      canonicalModelId: 'seedance-2.5',
      label: 'Seedance 2.5 · Frames',
      description:
          'Animate hosted first and last frames. Public URLs required.',
      modes: <VideoMode>[VideoMode.i2v],
      aspectRatios: <String>['auto'],
      resolutions: _resolutions,
      minDuration: 4,
      maxDuration: 30,
      durationStep: 1,
      maxKeyframes: 2,
      supportsStartFrame: true,
      supportsEndFrame: true,
      requiresStartFrameWhenUsingFrames: true,
      requiresPublicMediaUrls: true,
      maxInputImageBytes: 30 * 1024 * 1024,
      usdPerSecond: .2205,
      referenceUsdPerSecond: .2205,
      maxPromptCharacters: 30000,
      referencePromptHint:
          'Use publicly reachable image URLs; local uploads are unavailable.',
    ),
    VideoModelDefinition(
      id: 'seedance-2.5-r2v',
      canonicalModelId: 'seedance-2.5',
      label: 'Seedance 2.5 · References',
      description:
          'Guide video with hosted images, clips, and audio. Public URLs required.',
      modes: <VideoMode>[VideoMode.i2v],
      aspectRatios: _ratios,
      resolutions: _resolutions,
      minDuration: 4,
      maxDuration: 30,
      durationStep: 1,
      maxKeyframes: 0,
      maxImageReferences: 30,
      maxVideoReferences: 10,
      maxAudioReferences: 10,
      maxReferenceVideoSeconds: 30,
      maxReferenceAudioSeconds: 30,
      minReferenceVideoSeconds: 2,
      minReferenceAudioSeconds: 2,
      requiresVisualReferenceForAudio: true,
      requiresPublicMediaUrls: true,
      maxInputImageBytes: 30 * 1024 * 1024,
      usdPerSecond: .2205,
      referenceUsdPerSecond: .2205,
      maxPromptCharacters: 30000,
      referencePromptHint:
          'Use public media URLs. Video/audio clips must be 2–30 seconds; each type totals at most 30 seconds. Audio also needs an image or video.',
    ),
  ],
);

const _ratios = <String>['auto', '16:9', '4:3', '1:1', '3:4', '9:16', '21:9'];
const _resolutions = <VideoResolutionDefinition>[
  VideoResolutionDefinition('hd', 'HD', '1280 × 720'),
  VideoResolutionDefinition('sd', '480p', '854 × 480'),
];

/// Published route rates, checked 2026-11-05. Video inputs are charged along
/// with the output at a lower rate; image/audio inputs do not trigger it.
double apipodRate(String resolution, {bool withVideo = false}) =>
    resolution == 'sd'
    ? (withVideo ? .0588 : .098)
    : (withVideo ? .1323 : .2205);

List<ProviderModelPrice> apipodPublishedPrices() => <ProviderModelPrice>[
  for (final model in apipodProvider.models)
    for (final resolution in model.resolutions)
      for (final withVideo in <bool>[
        false,
        if (model.maxVideoReferences > 0) true,
      ])
        ProviderModelPrice(
          provider: 'apipod',
          model:
              '${model.id}:${resolution.id == 'sd' ? '480p' : '720p'}${withVideo ? ':video-reference' : ''}',
          canonicalModelId: model.canonicalId,
          label:
              '${model.label} · ${resolution.label}${withVideo ? ' · video input + output' : ''}',
          usdPerSecond: apipodRate(resolution.id, withVideo: withVideo),
          referenceUsdPerSecond: model.modes.contains(VideoMode.i2v)
              ? apipodRate(resolution.id, withVideo: withVideo)
              : null,
          modes: model.modes,
          source:
              'Published APIPod estimate · final token usage determines cost',
          minDuration: 4,
          maxDuration: 30,
          durationStep: 1,
        ),
];

CostEstimate apipodEstimate(GenerationConfig config) {
  final videos = (config.references ?? const <MediaReferenceLabel>[])
      .where((reference) => reference.kind == MediaReferenceKind.video)
      .toList();
  if (videos.any((video) => video.durationSeconds == null)) {
    return const CostEstimate(
      minimumUsd: 0,
      maximumUsd: 0,
      basis:
          'Reading reference video duration to calculate the APIPod estimate.',
      isAvailable: false,
    );
  }
  final inputSeconds = videos.fold<double>(
    0,
    (sum, video) => sum + video.durationSeconds!,
  );
  final outputSeconds = config.duration is num
      ? (config.duration as num).toDouble()
      : 4.0;
  final rate = apipodRate(config.resolution, withVideo: videos.isNotEmpty);
  final total = ((inputSeconds + outputSeconds) * rate * 10000).round() / 10000;
  return CostEstimate(
    minimumUsd: total,
    maximumUsd: total,
    basis: 'Published APIPod estimate · final token usage determines cost',
    rateUsd: rate,
    rateUnit: 'second',
    calculation:
        '${outputSeconds.toStringAsFixed(0)} s output'
        '${videos.isEmpty ? '' : ' + $inputSeconds s reference video'}'
        ' · ${config.resolution == 'sd' ? '480p' : '720p'}',
  );
}
