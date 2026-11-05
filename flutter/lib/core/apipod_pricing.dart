import 'apipod_models.dart';
import 'apipod_pricing_data.dart';
import 'models.dart';
import 'provider_catalog.dart' show VideoModelDefinition;

const _basis =
    'Published APIPod estimate · final provider usage determines cost';

String apipodResolution(String value) => switch (value) {
  'sd' => '480p',
  'hd' => '720p',
  'fhd' => '1080p',
  'qhd' => '2k',
  _ => value.toLowerCase(),
};

/// Published pricing is a base charge plus linear dimensions, multiplied by
/// discrete dimensions. Unspecified price tiers produce a range, never a
/// falsely precise quote. These are estimates, not settled provider charges.
CostEstimate apipodEstimate(
  String modelId,
  VideoMode mode,
  GenerationConfig config, {
  VideoSourceMetadata? sourceMetadata,
}) {
  final dimensions = apipodPricingDimensions[modelId];
  final models = apipodModels.where((model) => model.id == modelId);
  if (dimensions == null || models.isEmpty) {
    return _unavailable('APIPod pricing is unavailable for this route.');
  }
  final model = models.single;
  final linear = _map(dimensions['linear_dimensions']);
  final discrete = _map(dimensions['discrete_dimensions']);
  final videos = (config.references ?? const <MediaReferenceLabel>[])
      .where((reference) => reference.kind == MediaReferenceKind.video)
      .toList();
  final hasSource = mode == VideoMode.v2v;
  final billInput =
      modelId.startsWith('seedance-2.') && discrete.containsKey('video_count');
  if (billInput && videos.any((video) => video.durationSeconds == null)) {
    return _unavailable(
      'Reading reference video duration for the APIPod estimate.',
    );
  }
  if (hasSource &&
      sourceMetadata == null &&
      (billInput || model.durationFromSourceModes.contains(mode)) &&
      linear.isNotEmpty) {
    return _unavailable(
      'Reading source video duration for the APIPod estimate.',
    );
  }
  if (mode == VideoMode.draftEnhance) {
    // A pasted task ID carries no trustworthy duration or media billing data.
    return _unavailable(
      'APIPod prices the final render using its original draft duration and media.',
    );
  }
  double outputMin = config.duration is num
      ? (config.duration as num).toDouble()
      : model.minDuration.toDouble();
  double outputMax = config.duration is num
      ? outputMin
      : model.maxDuration.toDouble();
  if (model.durationFromSourceModes.contains(mode) && sourceMetadata != null) {
    outputMin = sourceMetadata.durationSeconds
        .clamp(0, model.maxDuration)
        .toDouble();
    outputMax = outputMin;
  }
  final inputSeconds = billInput
      ? videos.fold<double>(0, (sum, video) => sum + video.durationSeconds!) +
            (hasSource ? sourceMetadata?.durationSeconds ?? 0 : 0)
      : 0.0;
  var minimum = (dimensions['base_price'] as num?)?.toDouble() ?? 0;
  var maximum = minimum;
  for (final entry in linear.entries) {
    if (entry.key != 'duration' || entry.value is! num) {
      return _unavailable(
        'APIPod pricing depends on additional provider usage.',
      );
    }
    minimum += (outputMin + inputSeconds) * (entry.value as num);
    maximum += (outputMax + inputSeconds) * (entry.value as num);
  }
  final resolution = apipodResolution(config.resolution);
  final videoCount = videos.length + (hasSource ? 1 : 0);
  for (final entry in discrete.entries) {
    final values = _map(entry.value);
    final selected = switch (entry.key) {
      'resolution' => resolution,
      'duration' => config.duration.toString(),
      'video_count' => videoCount.toString(),
      'quality' => config.resolution == 'fhd' ? 'pro' : 'std',
      'price_tier' when modelId.startsWith('kling-3.') =>
        resolution == '4k'
            ? '4k'
            : '$resolution-${config.generateAudio ? 'audio' : 'silent'}',
      _ => null,
    };
    final matches = values.entries
        .where((value) => value.key.toLowerCase() == selected?.toLowerCase())
        .toList();
    if (matches.isNotEmpty && matches.first.value is num) {
      final multiplier = (matches.first.value as num).toDouble();
      minimum *= multiplier;
      maximum *= multiplier;
    } else if (entry.key == 'video_count' && videoCount == 0) {
      // Missing zero is the published identity multiplier (no video input).
      continue;
    } else {
      var candidates = values.entries;
      if (entry.key == 'price_tier') {
        candidates = candidates.where(
          (value) => value.key.startsWith('$resolution-'),
        );
      }
      final multipliers =
          candidates
              .map((value) => value.value)
              .whereType<num>()
              .map((value) => value.toDouble())
              .toList()
            ..sort();
      if (multipliers.isEmpty) {
        return _unavailable(
          'APIPod has no published price for these settings.',
        );
      }
      minimum *= multipliers.first;
      maximum *= multipliers.last;
    }
  }
  return CostEstimate(
    minimumUsd: _round(minimum),
    maximumUsd: _round(maximum),
    basis: _basis,
    rateUsd: linear.containsKey('duration') && outputMax + inputSeconds > 0
        ? maximum / (outputMax + inputSeconds)
        : maximum,
    rateUnit: linear.containsKey('duration') ? 'second' : 'generation',
    calculation:
        '${config.duration} s · $resolution'
        '${inputSeconds > 0 ? ' + $inputSeconds s input video' : ''}',
  );
}

List<ProviderModelPrice> apipodPublishedPrices() => [
  for (final model in apipodModels)
    for (final resolution in model.resolutions)
      ProviderModelPrice(
        provider: 'apipod',
        model: '${model.id}:${apipodResolution(resolution.id)}',
        canonicalModelId: model.canonicalId,
        label: '${model.label} · ${resolution.label}',
        usdPerSecond: 0,
        modes: model.modes,
        source: _basis,
        minDuration: model.minDuration,
        maxDuration: model.maxDuration,
        durationStep: model.durationStep,
        // Explicit duration prices also represent flat per-request routes
        // correctly in the cost desk; zero is never used as a rate fallback.
        pricingUnit: _needsInputQuote(model, resolution.id)
            ? 'variable'
            : 'per-generation',
        durationPrices: {
          for (
            var duration = model.minDuration;
            duration <= model.maxDuration;
            duration += model.durationStep
          )
            if (!_needsInputQuote(model, resolution.id) &&
                (model.durationOptions.isEmpty ||
                    model.durationOptions.contains(duration)))
              duration: apipodEstimate(
                model.id,
                model.modes.first,
                GenerationConfig(
                  aspectRatio: model.aspectRatios.first,
                  duration: duration,
                  resolution: resolution.id,
                  generateAudio: model.supportsAudio,
                  safetyTolerance: 2,
                  draft: false,
                ),
              ).maximumUsd,
        },
      ),
];

bool _needsInputQuote(VideoModelDefinition model, String resolution) =>
    (model.modes.contains(VideoMode.v2v) &&
        _map(
          apipodPricingDimensions[model.id]?['linear_dimensions'],
        ).isNotEmpty) ||
    (model.draftSourceIsTaskId &&
        (model.resolutionsByMode[VideoMode.draftEnhance] ?? const <String>[])
            .contains(resolution));

Map<String, Object?> _map(Object? value) => value is Map
    ? value.map((key, value) => MapEntry(key.toString(), value))
    : const {};
double _round(double value) => (value * 10000).round() / 10000;
CostEstimate _unavailable(String reason) => CostEstimate(
  minimumUsd: 0,
  maximumUsd: 0,
  basis: reason,
  isAvailable: false,
);
