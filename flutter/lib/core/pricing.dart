import 'dart:math' as math;

import 'models.dart';
import 'provider_catalog.dart';

const double bflUsdPerCredit = 0.01;

const _textOrImageRates = <String, double>{'draft': 6, 'hd': 17, 'fhd': 29};

const _videoRates = <String, double>{'draft': 12, 'hd': 43, 'fhd': 54};

const double bflUpscaleMaximumOutputMegapixels = 13.75;
const double bflUpscaleMaximumDurationSeconds = 20;

double _median(List<double> values) {
  final ordered = List<double>.from(values)..sort();
  final middle = ordered.length ~/ 2;
  return ordered.length.isOdd
      ? ordered[middle]
      : (ordered[middle - 1] + ordered[middle]) / 2;
}

double _roundCredits(double value) =>
    (value.clamp(0, double.infinity) * 10).round() / 10;

double _roundUsd(double value) =>
    (value.clamp(0, double.infinity) * 10000).round() / 10000;

CreditEstimate estimateCredits(
  VideoMode mode,
  GenerationConfig config, [
  List<Generation> history = const <Generation>[],
  VideoSourceMetadata? sourceMetadata,
]) {
  if (mode == VideoMode.upscale) {
    final usdPerMegapixelSecond = config.upscaleCreativity == 0 ? .07 : .10;
    final outputMegapixels = sourceMetadata == null
        ? bflUpscaleMaximumOutputMegapixels
        : _upscaleOutputMegapixels(sourceMetadata, config.upscaleFactor);
    final durationSeconds = sourceMetadata == null
        ? bflUpscaleMaximumDurationSeconds
        : sourceMetadata.durationSeconds;
    return CreditEstimate(
      minimum: sourceMetadata == null
          ? 0
          : _roundCredits(
              outputMegapixels *
                  durationSeconds *
                  usdPerMegapixelSecond /
                  bflUsdPerCredit,
            ),
      maximum: _roundCredits(
        outputMegapixels *
            durationSeconds *
            usdPerMegapixelSecond /
            bflUsdPerCredit,
      ),
      basis: sourceMetadata == null
          ? 'published-input-limit-range'
          : 'input-derived-published-rate',
    );
  }
  final rates = mode == VideoMode.v2v ? _videoRates : _textOrImageRates;
  final published = config.draft && mode != VideoMode.draftEnhance
      ? rates['draft']!
      : rates[config.resolution]!;
  final duration = config.duration;
  final minimumSeconds = duration is num ? duration.toDouble() : 5.0;
  final maximumSeconds = duration is num ? duration.toDouble() : 20.0;
  return CreditEstimate(
    minimum: _roundCredits(published * minimumSeconds),
    maximum: _roundCredits(published * maximumSeconds),
    basis: 'bfl-rate',
  );
}

double _upscaleOutputMegapixels(VideoSourceMetadata source, double factor) =>
    (source.width * source.height * factor * factor / (1024 * 1024))
        .clamp(0, bflUpscaleMaximumOutputMegapixels)
        .toDouble();

String _secondsLabel(double seconds) => seconds == seconds.roundToDouble()
    ? seconds.toStringAsFixed(0)
    : seconds.toStringAsFixed(1);

String _upscaleCalculation(
  VideoSourceMetadata source,
  double factor,
  double outputMegapixels,
) {
  final sourcePixels = source.width * source.height;
  final cappedFactor = sourcePixels <= 0
      ? factor
      : math.sqrt(
          bflUpscaleMaximumOutputMegapixels * 1024 * 1024 / sourcePixels,
        );
  final effectiveFactor = factor < cappedFactor ? factor : cappedFactor;
  final outputWidth = (source.width * effectiveFactor).round();
  final outputHeight = (source.height * effectiveFactor).round();
  return '${source.width}×${source.height} × ${factor.toStringAsFixed(1)}× → '
      '≈$outputWidth×$outputHeight · ${outputMegapixels.toStringAsFixed(2)} MP '
      '· ${_secondsLabel(source.durationSeconds)} s';
}

double creditsToUsd(double credits) => credits * bflUsdPerCredit;

double providerUnitsToUsd(String billingUnit, double value) =>
    billingUnit == 'usd' ? value : creditsToUsd(value);

double usdToProviderUnits(String billingUnit, double value) =>
    billingUnit == 'usd' ? value : value / bflUsdPerCredit;

double? providerCostFromPayload(Object? payload, [int depth = 0]) {
  if (payload is! Map<Object?, Object?> || depth > 3) return null;
  for (final key in const <String>[
    'actual_cost',
    'realized_cost',
    'charged_amount',
    'cost_in_credits',
    'credits_used',
    'cost',
    'price',
  ]) {
    final raw = payload[key];
    final value = raw is num ? raw.toDouble() : double.tryParse('$raw');
    if (value != null && value.isFinite && value >= 0) return value;
  }
  for (final key in const <String>['billing', 'usage', 'data', 'state']) {
    final nested = providerCostFromPayload(payload[key], depth + 1);
    if (nested != null) return nested;
  }
  return null;
}

double? recordedRealizedCostUsd(Generation generation) {
  final realized = generation.realizedCostUsd;
  if (realized != null) return realized;
  final legacy = generation.cost;
  return legacy == null
      ? null
      : providerUnitsToUsd(generation.billingUnit, legacy);
}

/// A task-specific amount returned with terminal provider status.
const String terminalReportedCostSource = 'terminal-provider-reported';

/// Historical account-delta labels remain readable, but are never evidence of
/// a task charge: other jobs, devices, refunds and deposits share the balance.
const String terminalBalanceDeltaCostSource = 'terminal-balance-delta';
const String accountBalanceObservationCostSource =
    'account-balance-observation';

const String providerQuoteCostSource = 'provider-quote';

bool isAccountBalanceCostSource(String? source) =>
    source == 'balance-delta' ||
    source == terminalBalanceDeltaCostSource ||
    source == accountBalanceObservationCostSource;

bool isTerminalRealizedCostSource(String? source) =>
    source == terminalReportedCostSource;

/// Historical inferred amounts stay visible as observations, but are excluded
/// from spend and route calibration. A fixed published price is still a quote.
bool countsTowardSpend(Generation generation) {
  if (isAccountBalanceCostSource(generation.realizedCostSource) ||
      generation.realizedCostSource == 'deterministic-route-price' ||
      generation.realizedCostSource == providerQuoteCostSource) {
    return false;
  }
  if (generation.isReady) return true;
  return generation.isFailed &&
      isTerminalRealizedCostSource(generation.realizedCostSource);
}

class ResolvedProviderCost {
  const ResolvedProviderCost({this.providerUnits, this.usd, this.source});

  final double? providerUnits;
  final double? usd;
  final String? source;
}

ResolvedProviderCost resolveProviderCost(
  Generation generation,
  Object? payload, {
  double? balanceAfter,
  bool allowDeterministicQuote = false,
  bool terminal = false,
}) {
  final reported = providerCostFromPayload(payload);
  // balanceAfter is intentionally account-level context only. Never attribute
  // its delta to this job, including when the job is terminal.
  if (reported != null) {
    return ResolvedProviderCost(
      providerUnits: reported,
      usd: providerUnitsToUsd(generation.billingUnit, reported),
      source:
          payload is Map && payload['cost_source'] == providerQuoteCostSource
          ? providerQuoteCostSource
          : terminal
          ? terminalReportedCostSource
          : 'provider-reported',
    );
  }
  final existingUsd = generation.realizedCostUsd;
  if (generation.cost != null || existingUsd != null) {
    return ResolvedProviderCost(
      providerUnits: generation.cost,
      usd:
          existingUsd ??
          providerUnitsToUsd(generation.billingUnit, generation.cost!),
      source: isAccountBalanceCostSource(generation.realizedCostSource)
          ? accountBalanceObservationCostSource
          : generation.realizedCostSource ?? 'legacy-provider-charge',
    );
  }
  final minimum = generation.quotedCostUsdMin;
  final maximum = generation.quotedCostUsdMax;
  if (allowDeterministicQuote &&
      minimum != null &&
      maximum != null &&
      (minimum - maximum).abs() < .0000001) {
    return ResolvedProviderCost(
      providerUnits: usdToProviderUnits(generation.billingUnit, minimum),
      usd: minimum,
      source: 'deterministic-route-price',
    );
  }
  return const ResolvedProviderCost();
}

class RouteCostObservation {
  const RouteCostObservation({
    required this.realizedUsd,
    required this.sampleCount,
    this.quotedUsd,
    this.pairedSampleCount = 0,
    this.medianVariancePercent,
  });

  final double realizedUsd;
  final double? quotedUsd;
  final int sampleCount;
  final int pairedSampleCount;
  final double? medianVariancePercent;

  double? get variancePercent => medianVariancePercent;
}

RouteCostObservation? routeCostObservation(
  ProviderModelPrice route,
  Iterable<Generation> history,
) {
  final matching = history.where((generation) {
    if (!countsTowardSpend(generation) ||
        recordedRealizedCostUsd(generation) == null ||
        !route.modes.contains(generation.mode)) {
      return false;
    }
    if (generation.provider != route.provider) return false;
    if (generation.model == route.model) return true;
    if (!route.model.startsWith('${generation.model}:')) return false;
    final routeTier = route.model.split(':').last.toLowerCase();
    final generationTier = generation.mode == VideoMode.upscale
        ? generation.config.upscaleCreativity == 0
              ? 'precise'
              : 'creative'
        : generation.config.draft
        ? 'draft'
        : switch (generation.config.resolution) {
            'fhd' => route.provider == 'ltx' ? '1080p' : 'fhd',
            'qhd' => '1440p',
            '4k' => '4k',
            _ => route.provider == 'ltx' ? '720p' : 'hd',
          };
    return routeTier == generationTier;
  }).toList();
  final realized = matching
      .map(recordedRealizedCostUsd)
      .whereType<double>()
      .toList();
  if (realized.isEmpty) return null;
  final pairedRealized = <double>[];
  final quotes = <double>[];
  final variances = <double>[];
  for (final generation in matching) {
    final minimum = generation.quotedCostUsdMin;
    final maximum = generation.quotedCostUsdMax;
    final actual = recordedRealizedCostUsd(generation)!;
    if (minimum == null || maximum == null || !actual.isFinite) continue;
    final quote = (minimum + maximum) / 2;
    if (!quote.isFinite || quote <= 0) continue;
    pairedRealized.add(actual);
    quotes.add(quote);
    // Compare each film with its own quote before summarizing. Duration and
    // configuration cannot mismatch the actual and expected amount.
    variances.add((actual - quote) / quote * 100);
  }
  return RouteCostObservation(
    realizedUsd: _median(quotes.isEmpty ? realized : pairedRealized),
    quotedUsd: quotes.isEmpty ? null : _median(quotes),
    sampleCount: quotes.isEmpty ? realized.length : pairedRealized.length,
    pairedSampleCount: quotes.length,
    medianVariancePercent: variances.isEmpty ? null : _median(variances),
  );
}

ProviderModelPrice? _pricedModel(
  String modelId,
  VideoMode mode,
  GenerationConfig config,
  List<ProviderModelPrice> prices,
) {
  final resolutionLabel = switch (config.resolution) {
    'sd' => '480p',
    'hd' => '720p',
    'fhd' => '1080p',
    'qhd' => '1440p',
    '4k' => '4K',
    _ => '720p',
  };
  final routeSpecific = <String>[
    if (modelId == 'veo3.1' || modelId == 'veo3.1_fast')
      '$modelId:${config.generateAudio ? 'audio' : 'silent'}',
    if (modelId == 'gemini_omni_flash')
      '$modelId:${mode == VideoMode.v2v ? 'edit' : 'generation'}',
    if (mode == VideoMode.v2v) '$modelId:$resolutionLabel:edit',
    '$modelId:$resolutionLabel:${config.generateAudio ? 'audio' : 'silent'}',
    '$modelId:$resolutionLabel',
    modelId,
  ];
  for (final candidate in routeSpecific) {
    final match = prices.where((item) => item.model == candidate).firstOrNull;
    if (match != null) return match;
  }
  return null;
}

({double usdPerSecond, String source}) _providerRate(
  String providerId,
  String modelId,
  VideoMode mode,
  GenerationConfig config,
  List<ProviderModelPrice> prices,
) {
  if (providerId == 'bfl') {
    if (mode == VideoMode.upscale) {
      return (
        usdPerSecond: config.upscaleCreativity == 0 ? .07 : .10,
        source: 'published-output-megapixel-rate',
      );
    }
    final rates = mode == VideoMode.v2v ? _videoRates : _textOrImageRates;
    final credits = config.draft && mode != VideoMode.draftEnhance
        ? rates['draft']!
        : rates[config.resolution] ?? rates['hd']!;
    return (usdPerSecond: creditsToUsd(credits), source: 'published-rate');
  }
  if (providerId == 'ltx' &&
      config.references?.any((item) => item.kind == MediaReferenceKind.audio) ==
          true) {
    return (usdPerSecond: .10, source: 'published-rate');
  }
  final pricedModel = _pricedModel(modelId, mode, config, prices);
  if (pricedModel?.pricingUnit == 'per-frame') {
    return (
      usdPerSecond: pricedModel!.usdPerSecond * 24,
      source: '${pricedModel.source} · estimated at 24 fps',
    );
  }
  if (pricedModel != null && pricedModel.pricingUnit != 'catalog-base') {
    return (
      usdPerSecond: mode == VideoMode.i2v
          ? pricedModel.referenceUsdPerSecond ?? pricedModel.usdPerSecond
          : pricedModel.usdPerSecond,
      source: pricedModel.source,
    );
  }
  if (providerId == 'ltx') {
    const rates = <String, Map<String, double>>{
      'ltx-2-3-fast': <String, double>{
        'hd': .03,
        'fhd': .06,
        'qhd': .12,
        '4k': .24,
      },
      'ltx-2-3-pro': <String, double>{
        'hd': .04,
        'fhd': .08,
        'qhd': .16,
        '4k': .32,
      },
    };
    return (
      usdPerSecond:
          rates[modelId]?[config.resolution] ??
          modelById(providerId, modelId).usdPerSecond,
      source: 'published-rate',
    );
  }
  final model = modelById(providerId, modelId);
  return (
    usdPerSecond: mode == VideoMode.i2v
        ? model.referenceUsdPerSecond ?? model.usdPerSecond
        : model.usdPerSecond,
    source: 'published-fallback',
  );
}

CostEstimate estimateCost(
  String providerId,
  String modelId,
  VideoMode mode,
  GenerationConfig config, [
  List<Generation> history = const <Generation>[],
  List<ProviderModelPrice> prices = const <ProviderModelPrice>[],
  VideoSourceMetadata? sourceMetadata,
]) {
  final duration = config.duration;
  final model = modelById(providerId, modelId);
  final sourceDuration = model.durationComesFromSource(mode)
      ? sourceMetadata?.durationSeconds
      : null;
  final minimumSeconds =
      sourceDuration ??
      (duration is num ? duration.toDouble() : model.minDuration.toDouble());
  final maximumSeconds =
      sourceDuration ??
      (duration is num ? duration.toDouble() : model.maxDuration.toDouble());
  final rate = _providerRate(providerId, modelId, mode, config, prices);
  final pricedModel = _pricedModel(modelId, mode, config, prices);
  final durationLabel = minimumSeconds == maximumSeconds
      ? '${_secondsLabel(minimumSeconds)} s'
      : '${_secondsLabel(minimumSeconds)}–${_secondsLabel(maximumSeconds)} s Auto';
  final resolutionLabel =
      model.resolutions
          .where((resolution) => resolution.id == config.resolution)
          .firstOrNull
          ?.label ??
      config.resolution;
  final calculation = <String>[
    durationLabel,
    resolutionLabel,
    if (config.aspectRatio != 'auto') config.aspectRatio,
    mode.shortLabel,
    if (config.draft) 'draft',
    if (config.keyframes?.isNotEmpty == true)
      '${config.keyframes!.length} keyframe${config.keyframes!.length == 1 ? '' : 's'}',
    if (config.references?.isNotEmpty == true)
      '${config.references!.length} reference${config.references!.length == 1 ? '' : 's'}',
    if (config.generateAudio) 'audio',
  ].join(' · ');

  double quotedTotal(double seconds) {
    final wholeSeconds = seconds.round();
    if ((seconds - wholeSeconds).abs() < .0001) {
      final exact = pricedModel?.durationPrices[wholeSeconds];
      if (exact != null) return exact;
    }
    return rate.usdPerSecond * seconds;
  }

  if (providerId == 'bfl') {
    final credits = estimateCredits(mode, config, history, sourceMetadata);
    final upscale = mode == VideoMode.upscale;
    final outputMegapixels = sourceMetadata == null || !upscale
        ? null
        : _upscaleOutputMegapixels(sourceMetadata, config.upscaleFactor);
    return CostEstimate(
      minimumUsd: creditsToUsd(credits.minimum),
      maximumUsd: creditsToUsd(credits.maximum),
      basis: credits.basis,
      providerUnitsMinimum: credits.minimum,
      providerUnitsMaximum: credits.maximum,
      providerUnitLabel: 'credits',
      rateUsd: rate.usdPerSecond,
      rateUnit: upscale ? 'megapixel-second' : 'second',
      calculation: upscale
          ? sourceMetadata == null
                ? 'Add a source video to calculate from its dimensions and duration.'
                : _upscaleCalculation(
                    sourceMetadata,
                    config.upscaleFactor,
                    outputMegapixels!,
                  )
          : calculation,
    );
  }
  if (providerId == 'artcraft' || providerId == 'runway') {
    final knownInputSurchargeUsd = providerId == 'runway'
        ? _runwayKnownInputSurchargeUsd(modelId, mode, config, sourceMetadata)
        : 0.0;
    final minimumUsd = _roundUsd(
      quotedTotal(minimumSeconds) + knownInputSurchargeUsd,
    );
    final maximumUsd = _roundUsd(
      quotedTotal(maximumSeconds) + knownInputSurchargeUsd,
    );
    return CostEstimate(
      minimumUsd: minimumUsd,
      maximumUsd: maximumUsd,
      basis:
          providerId == 'runway' &&
              (config.references?.any(
                        (item) => item.kind != MediaReferenceKind.audio,
                      ) ==
                      true ||
                  config.keyframes?.isNotEmpty == true ||
                  mode == VideoMode.v2v)
          ? '${rate.source} · provider receipt settles input/reference surcharges'
          : rate.source,
      providerUnitsMinimum: _roundCredits(minimumUsd / bflUsdPerCredit),
      providerUnitsMaximum: _roundCredits(maximumUsd / bflUsdPerCredit),
      providerUnitLabel: 'credits',
      rateUsd: rate.usdPerSecond,
      rateUnit: pricedModel?.pricingUnit == 'per-frame'
          ? 'second · 24 fps estimate'
          : 'second',
      calculation: knownInputSurchargeUsd > 0
          ? '$calculation · ${_roundCredits(knownInputSurchargeUsd / bflUsdPerCredit)} known input credits'
          : calculation,
    );
  }
  return CostEstimate(
    minimumUsd: _roundUsd(quotedTotal(minimumSeconds)),
    maximumUsd: _roundUsd(quotedTotal(maximumSeconds)),
    basis: rate.source,
    rateUsd: rate.usdPerSecond,
    rateUnit: 'second',
    calculation: calculation,
  );
}

double _runwayKnownInputSurchargeUsd(
  String modelId,
  VideoMode mode,
  GenerationConfig config,
  VideoSourceMetadata? sourceMetadata,
) {
  final references = config.references ?? const <MediaReferenceLabel>[];
  final keyframes = config.keyframes ?? const <KeyframeLabel>[];
  if (modelId == 'seedance2_5') {
    final inputCreditsPerSecond = switch (config.resolution) {
      'sd' => 10.0,
      'fhd' => 34.0,
      _ => 15.0,
    };
    final referenceVideoSeconds = references
        .where((item) => item.kind == MediaReferenceKind.video)
        .map((item) => item.durationSeconds)
        .whereType<double>()
        .fold<double>(0, (sum, seconds) => sum + seconds);
    final sourceSeconds = mode == VideoMode.v2v
        ? sourceMetadata?.durationSeconds ?? 0
        : 0;
    return creditsToUsd(
      (referenceVideoSeconds + sourceSeconds) * inputCreditsPerSecond,
    );
  }
  if (modelId == 'grok_imagine_1_5') {
    return creditsToUsd((references.length + keyframes.length).toDouble());
  }
  if (modelId == 'hailuo3') {
    final imageCount =
        references
            .where((item) => item.kind == MediaReferenceKind.image)
            .length +
        keyframes.length;
    return creditsToUsd(imageCount * 2.0);
  }
  if (modelId == 'gemini_omni_flash' && mode == VideoMode.i2v) {
    return creditsToUsd((references.length + keyframes.length).toDouble());
  }
  return 0;
}
