import 'dart:convert';
import 'dart:math' as math;

import 'models.dart';
import 'provider_catalog.dart';

// Measured 2026-08-23 with five-second, SD, text-only Seedance 2.5 runs.
// ArtCraft is the midpoint of 127.8s and 97.1s; Atlas measured 237.6s.
const _artCraftSeedance25FiveSecondSd = Duration(seconds: 112);
const _atlasSeedance25FiveSecondSd = Duration(seconds: 237);

enum GenerationProgressBasis { reported, historical, baseline, indeterminate }

class GenerationProgressEstimate {
  const GenerationProgressEstimate({
    required this.basis,
    this.percentage,
    this.expectedDuration,
    this.sampleCount = 0,
  });

  final GenerationProgressBasis basis;
  final double? percentage;
  final Duration? expectedDuration;
  final int sampleCount;

  bool get isEstimated =>
      basis == GenerationProgressBasis.historical ||
      basis == GenerationProgressBasis.baseline;
}

/// Resolves live generation progress without confusing a progress-shaped API
/// field with a trustworthy percentage.
///
/// Provider-reported progress wins only for routes that explicitly opt in.
/// Other routes use the median of comparable completed work, blended with a
/// benchmark baseline while the personal sample is still small. With neither
/// source available the UI remains honestly indeterminate.
GenerationProgressEstimate generationProgressEstimate(
  Generation generation,
  Iterable<Generation> history, {
  DateTime? now,
}) {
  final reported = trustedGenerationProgress(generation);
  if (reported != null) {
    return GenerationProgressEstimate(
      basis: GenerationProgressBasis.reported,
      percentage: reported,
    );
  }

  final baseline = benchmarkGenerationDuration(generation);
  final historical = history
      .where(
        (candidate) =>
            candidate.localId != generation.localId &&
            candidate.isReady &&
            _hasComparableTiming(generation, candidate),
      )
      .map(observedGenerationDuration)
      .whereType<Duration>()
      .where((duration) => duration > Duration.zero)
      .toList();
  final historicalMedian = _medianDuration(historical);

  late final GenerationProgressBasis basis;
  late final Duration? expected;
  if (historicalMedian != null) {
    basis = GenerationProgressBasis.historical;
    if (baseline == null) {
      expected = historicalMedian;
    } else {
      // Two virtual benchmark samples keep the first personal observation
      // from swinging the bar wildly. At five comparable runs the user's
      // actual median supplies more than 70% of the estimate.
      final personalWeight = historical.length.clamp(1, 8);
      expected = Duration(
        milliseconds:
            ((baseline.inMilliseconds * 2 +
                        historicalMedian.inMilliseconds * personalWeight) /
                    (2 + personalWeight))
                .round(),
      );
    }
  } else if (baseline != null) {
    basis = GenerationProgressBasis.baseline;
    expected = baseline;
  } else {
    return const GenerationProgressEstimate(
      basis: GenerationProgressBasis.indeterminate,
    );
  }

  final startedAt = generation.providerAcceptedAt ?? generation.createdAt;
  final elapsed = (now ?? DateTime.now().toUtc()).difference(startedAt);
  return GenerationProgressEstimate(
    basis: basis,
    percentage: _estimatedPercentage(elapsed, expected),
    expectedDuration: expected,
    sampleCount: historical.length,
  );
}

/// The wall-clock time from provider acceptance to the first completed state.
///
/// New records use explicit timestamps. Older history remains useful by
/// reading provider timestamps from the retained response, then falling back
/// to Clawnsole's creation/update times when no stronger evidence exists.
Duration? observedGenerationDuration(Generation generation) {
  final providerPayload = _providerPayload(generation.lastProviderResponse);
  final startedAt =
      generation.providerAcceptedAt ??
      providerGenerationStartedAt(providerPayload) ??
      generation.createdAt;
  final completedAt =
      generation.providerCompletedAt ??
      providerGenerationCompletedAt(providerPayload) ??
      (generation.isReady ? generation.updatedAt : null);
  if (completedAt == null || completedAt.isBefore(startedAt)) return null;
  return completedAt.difference(startedAt);
}

DateTime? providerGenerationStartedAt(Object? payload) => _findTimestamp(
  payload,
  const <String>{'maybe_first_started_at', 'started_at', 'created_at'},
);

DateTime? providerGenerationCompletedAt(Object? payload) =>
    _findTimestamp(payload, const <String>{
      'maybe_successfully_completed_at',
      'completed_at',
      'finished_at',
    });

/// Benchmark-derived Seedance 2.5 route duration before personal history is
/// available. The five-second SD anchors are measured through each provider;
/// duration scaling is intentionally sublinear because queue/startup time is a
/// large part of short video latency.
Duration? benchmarkGenerationDuration(Generation generation) {
  final fiveSecondAnchor = switch ((generation.provider, generation.model)) {
    ('artcraft', 'seedance_2p5') => _artCraftSeedance25FiveSecondSd,
    (
      'atlas',
      'bytedance/seedance-2.5/text-to-video' ||
          'bytedance/seedance-2.5/image-to-video' ||
          'bytedance/seedance-2.5/reference-to-video',
    ) =>
      _atlasSeedance25FiveSecondSd,
    _ => null,
  };
  if (fiveSecondAnchor == null) return null;
  final rawDuration = generation.config.duration;
  final outputSeconds = rawDuration is num
      ? rawDuration.toDouble().clamp(1, 120)
      : 5.0;
  final resolutionFactor = switch (generation.config.resolution) {
    'fhd' => 1.35,
    'hd' => 1.15,
    _ => 1.0,
  };
  final referenceCount = _referenceCount(generation);
  final referenceFactor = 1 + .05 * referenceCount.clamp(0, 6);
  final seconds =
      fiveSecondAnchor.inMilliseconds /
      1000 *
      math.pow(outputSeconds / 5, .45) *
      resolutionFactor *
      referenceFactor;
  return Duration(milliseconds: (seconds * 1000).round());
}

double _estimatedPercentage(Duration elapsed, Duration expected) {
  if (elapsed <= Duration.zero || expected <= Duration.zero) return 0;
  final ratio = elapsed.inMilliseconds / expected.inMilliseconds;
  final fraction = ratio <= .8
      ? ratio
      : .8 + .18 * (1 - math.exp(-1.5 * (ratio - .8)));
  return (fraction * 100).clamp(0, 98).toDouble();
}

bool _hasComparableTiming(Generation target, Generation candidate) =>
    target.provider == candidate.provider &&
    target.model == candidate.model &&
    target.mode == candidate.mode &&
    target.config.duration == candidate.config.duration &&
    target.config.resolution == candidate.config.resolution &&
    target.config.generateAudio == candidate.config.generateAudio &&
    _referenceSignature(target) == _referenceSignature(candidate);

String _referenceSignature(Generation generation) {
  final keyframes = generation.config.keyframes?.length ?? 0;
  final images =
      generation.config.references
          ?.where((item) => item.kind == MediaReferenceKind.image)
          .length ??
      0;
  final videos =
      generation.config.references
          ?.where((item) => item.kind == MediaReferenceKind.video)
          .length ??
      0;
  final audios =
      generation.config.references
          ?.where((item) => item.kind == MediaReferenceKind.audio)
          .length ??
      0;
  final source = generation.config.source == null ? 0 : 1;
  return '$keyframes/$images/$videos/$audios/$source';
}

int _referenceCount(Generation generation) {
  final references = generation.config.references?.length ?? 0;
  final keyframes = generation.config.keyframes?.length ?? 0;
  final source = generation.config.source == null ? 0 : 1;
  return references + keyframes + source;
}

Duration? _medianDuration(List<Duration> durations) {
  if (durations.isEmpty) return null;
  final ordered = durations.map((item) => item.inMilliseconds).toList()..sort();
  final middle = ordered.length ~/ 2;
  final milliseconds = ordered.length.isOdd
      ? ordered[middle]
      : ((ordered[middle - 1] + ordered[middle]) / 2).round();
  return Duration(milliseconds: milliseconds);
}

Object? _providerPayload(String? response) {
  if (response == null || response.trim().isEmpty) return null;
  try {
    return jsonDecode(response);
  } on FormatException {
    return null;
  }
}

DateTime? _findTimestamp(Object? value, Set<String> keys) {
  if (value is Map<Object?, Object?>) {
    for (final entry in value.entries) {
      if (!keys.contains(entry.key.toString().toLowerCase())) continue;
      final parsed = DateTime.tryParse(entry.value?.toString() ?? '');
      if (parsed != null) return parsed.toUtc();
    }
    for (final child in value.values) {
      final found = _findTimestamp(child, keys);
      if (found != null) return found;
    }
  } else if (value is List<Object?>) {
    for (final child in value) {
      final found = _findTimestamp(child, keys);
      if (found != null) return found;
    }
  }
  return null;
}
