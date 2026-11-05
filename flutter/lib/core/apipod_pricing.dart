import 'apipod_models.dart';
import 'apipod_model_groups.dart';
import 'apipod_pricing_data.dart';
import 'apipod_schema_data.dart';
import 'bfl_api.dart';
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

/// The public quote endpoint accepts billing dimensions without prompts or
/// media URLs. Input videos are rounded up individually, matching its media
/// probing behavior, before their seconds are included in Seedance billing.
class ApipodQuoteRequest {
  const ApipodQuoteRequest({
    required this.model,
    required this.dimensions,
    required this.hasVideo,
    required this.billableSeconds,
    required this.modelLabel,
    required this.outputSeconds,
    required this.inputSeconds,
  });

  final String model;
  final Map<String, String> dimensions;
  final bool hasVideo;
  final double? billableSeconds;
  final String modelLabel;
  final double outputSeconds;
  final double inputSeconds;

  String get calculation =>
      '$modelLabel · ${_number(outputSeconds)} s output'
      '${inputSeconds > 0 ? ' + ${_number(inputSeconds)} s input video (each rounded up)' : ''}'
      '${inputSeconds > 0 ? ' = ${_number(outputSeconds + inputSeconds)} billable seconds' : ''}';

  Map<String, Object?> toJson() => {
    'model_id': model,
    'dimensions': dimensions,
    if (hasVideo) 'has_video_material': true,
  };
}

ApipodQuoteRequest? apipodQuoteRequest(
  String model,
  Map<String, Object?> input,
) {
  int count(String field, String type) {
    final direct = input[field];
    if (direct is List) return direct.length;
    final types = input['reference_types'];
    return types is List ? types.where((value) => value == type).length : 0;
  }

  final images = count('reference_images', 'image');
  final videos = count('reference_videos', 'video');
  final audios = count('reference_audios', 'audio');
  final rawFrames = input['keyframe_count'];
  if (rawFrames != null && rawFrames is! int) return null;
  if (input['generate_audio'] != null && input['generate_audio'] is! bool) {
    return null;
  }
  final frames = rawFrames is int
      ? rawFrames
      : input['keyframes'] is List
      ? (input['keyframes']! as List).length
      : 0;
  final modeName = input['mode'];
  final mode = VideoMode.values
      .where((value) => value.wireValue == modeName)
      .firstOrNull;
  if (modeName != null && mode == null) return null;
  if (mode == VideoMode.draftEnhance) return null;
  final hasSource =
      mode == VideoMode.v2v ||
      input['has_source_video'] == true ||
      [
        'start_video',
        'input_video',
      ].any((key) => input[key] != null && input[key] != '');
  final resolution = input['resolution']?.toString();
  try {
    model = resolveApipodRoute(
      model,
      mode: mode,
      keyframeCount: frames,
      imageReferenceCount: images,
      videoReferenceCount: videos,
      audioReferenceCount: audios,
      hasSourceVideo: hasSource,
      resolution: resolution,
    );
  } on ProviderException {
    return null;
  }
  final definition = apipodModels.singleWhere((item) => item.id == model);
  final pricing = apipodPricingDimensions[model];
  if (pricing == null) return null;
  final linear = _map(pricing['linear_dimensions']);
  final discrete = _map(pricing['discrete_dimensions']);
  final properties = _map(apipodRouteSchemas[model]?['properties']);
  final resolutionId = resolution ?? definition.resolutions.first.id;
  final normalizedResolution = apipodResolution(resolutionId);
  final choices = _map(properties['resolution'])['enum'];
  final wireResolution = choices is List
      ? choices
                .whereType<String>()
                .where((choice) => choice.toLowerCase() == normalizedResolution)
                .firstOrNull ??
            normalizedResolution
      : normalizedResolution;
  final sourceSeconds = _positive(input['source_duration']);
  if (hasSource && sourceSeconds == null) return null;
  final selectedMode = hasSource
      ? VideoMode.v2v
      : mode ?? definition.modes.first;
  final sourceDuration = definition.durationComesFromSource(selectedMode);
  final outputSeconds = sourceDuration
      ? sourceSeconds?.ceil().clamp(0, definition.maxDuration).toDouble()
      : _positive(input['duration'] ?? definition.minDuration);
  if (outputSeconds == null) return null;
  if (!sourceDuration &&
      (outputSeconds != outputSeconds.roundToDouble() ||
          outputSeconds < definition.minDuration ||
          outputSeconds > definition.maxDuration ||
          (definition.durationOptions.isNotEmpty &&
              !definition.durationOptions.contains(outputSeconds.toInt())))) {
    return null;
  }
  final videoCount = videos + (hasSource ? 1 : 0);
  final billInput =
      model.startsWith('seedance-2.') && discrete.containsKey('video_count');
  var billableSeconds = outputSeconds;
  if (billInput && videos > 0) {
    final pending = input['reference_video_duration_pending'];
    if (pending != null && pending != 0 && pending != false) return null;
    final durations = input['reference_video_durations_seconds'];
    if (durations is List && durations.length == videos) {
      for (final raw in durations) {
        final seconds = _positive(raw);
        if (seconds == null) return null;
        billableSeconds += seconds.ceil();
      }
    } else if (videos == 1) {
      final seconds = _positive(input['reference_video_duration_seconds']);
      if (seconds == null) return null;
      billableSeconds += seconds.ceil();
    } else {
      return null;
    }
  }
  if (billInput && hasSource) billableSeconds += sourceSeconds!.ceil();
  final dimensions = <String, String>{
    'duration': _number(billableSeconds),
    if (properties.containsKey('resolution') ||
        discrete.containsKey('resolution'))
      'resolution': wireResolution,
    if (properties.containsKey('quality') || discrete.containsKey('quality'))
      'quality': resolutionId == 'fhd' ? 'pro' : 'std',
    if (properties.containsKey('generate_audio'))
      'generate_audio': '${input['generate_audio'] ?? true}',
    if (discrete.containsKey('video_count') || videoCount > 0)
      'video_count': '$videoCount',
    if (discrete.containsKey('extra_image_count'))
      'extra_image_count': '${(images + frames - 1).clamp(0, 100)}',
  };
  if (discrete.containsKey('price_tier')) {
    if (model.startsWith('kling-3.')) {
      dimensions['price_tier'] = normalizedResolution == '4k'
          ? '4k'
          : '$normalizedResolution-${input['generate_audio'] == false ? 'silent' : 'audio'}';
    } else if (model == 'kling-4.0-r2v') {
      dimensions['price_tier'] =
          '$normalizedResolution-${videoCount + audios > 0 ? 'enhanced' : 'basic'}';
    } else {
      return null;
    }
  }
  return ApipodQuoteRequest(
    model: model,
    dimensions: Map.unmodifiable(dimensions),
    hasVideo: videoCount > 0,
    billableSeconds: linear.containsKey('duration') ? billableSeconds : null,
    modelLabel: definition.selectionLabel,
    outputSeconds: outputSeconds,
    inputSeconds: billableSeconds - outputSeconds,
  );
}

double? _positive(Object? value) =>
    value is num && value.isFinite && value > 0 ? value.toDouble() : null;
String _number(double value) =>
    value == value.roundToDouble() ? '${value.toInt()}' : '$value';

/// Published pricing is a base charge plus linear dimensions, multiplied by
/// discrete dimensions. Unspecified price tiers produce a range, never a
/// falsely precise quote. These are estimates, not settled provider charges.
CostEstimate apipodEstimate(
  String modelId,
  VideoMode mode,
  GenerationConfig config, {
  VideoSourceMetadata? sourceMetadata,
}) {
  final references = config.references ?? const <MediaReferenceLabel>[];
  try {
    modelId = resolveApipodRoute(
      modelId,
      mode: mode,
      keyframeCount: config.keyframes?.length ?? 0,
      imageReferenceCount: references
          .where((item) => item.kind == MediaReferenceKind.image)
          .length,
      videoReferenceCount: references
          .where((item) => item.kind == MediaReferenceKind.video)
          .length,
      audioReferenceCount: references
          .where((item) => item.kind == MediaReferenceKind.audio)
          .length,
      hasSourceVideo: mode == VideoMode.v2v,
      resolution: config.resolution,
    );
  } on ProviderException {
    return _unavailable('APIPod pricing is unavailable for these inputs.');
  }
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
  if (billInput &&
      videos.any((video) => _positive(video.durationSeconds) == null)) {
    return _unavailable(
      'Reading reference video duration for the APIPod estimate.',
    );
  }
  if (hasSource &&
      _positive(sourceMetadata?.durationSeconds) == null &&
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
        .ceil()
        .clamp(0, model.maxDuration)
        .toDouble();
    outputMax = outputMin;
  }
  final inputSeconds = billInput
      ? videos.fold<double>(
              0,
              (sum, video) => sum + video.durationSeconds!.ceil(),
            ) +
            (hasSource ? sourceMetadata!.durationSeconds.ceil() : 0)
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
        '${_number(outputMin)}${outputMax == outputMin ? '' : '–${_number(outputMax)}'} s output · $resolution'
        '${inputSeconds > 0 ? ' + ${_number(inputSeconds)} s input video (rounded per clip)' : ''}',
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
