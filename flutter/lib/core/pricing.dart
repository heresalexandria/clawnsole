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

/// Sources recorded only when a terminal poll confirmed the charge — either
/// the provider reported it in the terminal payload or the balance stayed
/// down after the run ended. Submit-time observations keep the legacy source
/// names ('provider-reported', 'balance-delta', …), so persisted records from
/// before this distinction parse unchanged and read as submit-time estimates.
const String terminalReportedCostSource = 'terminal-provider-reported';
const String terminalBalanceDeltaCostSource = 'terminal-balance-delta';

bool isTerminalRealizedCostSource(String? source) =>
    source == terminalReportedCostSource ||
    source == terminalBalanceDeltaCostSource;

/// Whether [generation]'s recorded cost reflects money actually spent.
///
/// Ready generations count. In-flight work is not settled yet. Failed
/// generations count only when a terminal poll confirmed the charge —
/// submit-time observations are estimates that providers commonly refund
/// when a generation fails.
bool countsTowardSpend(Generation generation) {
  if (generation.isReady) return true;
  if (generation.isFailed) {
    return isTerminalRealizedCostSource(generation.realizedCostSource);
  }
  return false;
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
  final before = generation.creditsBefore;
  final balanceDelta = before != null && balanceAfter != null
      ? before - balanceAfter
      : null;
  final measured = balanceDelta != null && balanceDelta > .0000001
      ? balanceDelta
      : null;
  if (terminal && (reported != null || measured != null)) {
    // Fresh terminal evidence supersedes the submit-time observation: it is
    // what the provider actually settled, and its source marks the record as
    // a confirmed charge even when the generation failed.
    final units = reported ?? measured!;
    return ResolvedProviderCost(
      providerUnits: units,
      usd: providerUnitsToUsd(generation.billingUnit, units),
      source: reported != null
          ? terminalReportedCostSource
          : terminalBalanceDeltaCostSource,
    );
  }
  final providerUnits = reported ?? measured ?? generation.cost;
  final existingUsd = generation.realizedCostUsd;
  if (providerUnits != null) {
    return ResolvedProviderCost(
      providerUnits: providerUnits,
      usd:
          existingUsd ??
          providerUnitsToUsd(generation.billingUnit, providerUnits),
      source:
          generation.realizedCostSource ??
          (reported != null
              ? 'provider-reported'
              : measured != null
              ? 'balance-delta'
              : 'legacy-provider-charge'),
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
  return ResolvedProviderCost(
    providerUnits: generation.cost,
    usd: existingUsd,
    source: generation.realizedCostSource,
  );
}

class RouteCostObservation {
  const RouteCostObservation({
    required this.realizedUsd,
    required this.sampleCount,
    this.quotedUsd,
  });

  final double realizedUsd;
  final double? quotedUsd;
  final int sampleCount;

  double? get variancePercent => quotedUsd == null || quotedUsd == 0
      ? null
      : (realizedUsd - quotedUsd!) / quotedUsd! * 100;
}

RouteCostObservation? routeCostObservation(
  ProviderModelPrice route,
  Iterable<Generation> history,
) {
  final matching = history.where((generation) {
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
  final quotes = matching.expand((generation) {
    final minimum = generation.quotedCostUsdMin;
    final maximum = generation.quotedCostUsdMax;
    if (minimum == null || maximum == null) return const <double>[];
    return <double>[(minimum + maximum) / 2];
  }).toList();
  return RouteCostObservation(
    realizedUsd: _median(realized),
    quotedUsd: quotes.isEmpty ? null : _median(quotes),
    sampleCount: realized.length,
  );
}

ProviderModelPrice? _pricedModel(
  String modelId,
  GenerationConfig config,
  List<ProviderModelPrice> prices,
) {
  final resolutionLabel = switch (config.resolution) {
    'fhd' => '1080p',
    'qhd' => '1440p',
    '4k' => '4K',
    _ => '720p',
  };
  return prices
      .where(
        (item) =>
            item.model == modelId || item.model == '$modelId:$resolutionLabel',
      )
      .lastOrNull;
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
  final pricedModel = _pricedModel(modelId, config, prices);
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
  final minimumSeconds = duration is num
      ? duration.toDouble()
      : model.minDuration.toDouble();
  final maximumSeconds = duration is num
      ? duration.toDouble()
      : model.maxDuration.toDouble();
  final rate = _providerRate(providerId, modelId, mode, config, prices);
  final pricedModel = _pricedModel(modelId, config, prices);
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
  if (providerId == 'artcraft') {
    final minimumUsd = _roundUsd(quotedTotal(minimumSeconds));
    final maximumUsd = _roundUsd(quotedTotal(maximumSeconds));
    return CostEstimate(
      minimumUsd: minimumUsd,
      maximumUsd: maximumUsd,
      basis: rate.source,
      providerUnitsMinimum: _roundCredits(minimumUsd / bflUsdPerCredit),
      providerUnitsMaximum: _roundCredits(maximumUsd / bflUsdPerCredit),
      providerUnitLabel: 'credits',
      rateUsd: rate.usdPerSecond,
      rateUnit: 'second',
      calculation: calculation,
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
