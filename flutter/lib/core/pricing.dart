import 'models.dart';
import 'provider_catalog.dart';

const double bflUsdPerCredit = 0.01;

const _textOrImageRates = <String, double>{'draft': 6, 'hd': 17, 'fhd': 29};

const _videoRates = <String, double>{'draft': 12, 'hd': 41, 'fhd': 53};

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

bool _sameSignature(Generation item, VideoMode mode, GenerationConfig config) =>
    item.mode == mode &&
    item.config.resolution == config.resolution &&
    item.config.duration == config.duration &&
    item.config.generateAudio == config.generateAudio &&
    item.config.draft == config.draft;

CreditEstimate estimateCredits(
  VideoMode mode,
  GenerationConfig config, [
  List<Generation> history = const <Generation>[],
]) {
  final exact = history
      .where((item) => item.cost != null && _sameSignature(item, mode, config))
      .map((item) => item.cost!)
      .toList();
  if (exact.isNotEmpty) {
    final quote = _roundCredits(_median(exact));
    return CreditEstimate(
      minimum: quote,
      maximum: quote,
      basis: 'provider-history',
    );
  }

  final observedRates = history.expand((item) {
    final duration = item.config.duration;
    if (item.cost == null ||
        duration is! num ||
        duration <= 0 ||
        item.mode != mode ||
        item.config.resolution != config.resolution ||
        item.config.generateAudio != config.generateAudio ||
        item.config.draft != config.draft) {
      return const <double>[];
    }
    return <double>[item.cost! / duration];
  }).toList();

  final rates = mode == VideoMode.v2v ? _videoRates : _textOrImageRates;
  final published = config.draft && mode != VideoMode.draftEnhance
      ? rates['draft']!
      : rates[config.resolution]!;
  final rate = observedRates.isEmpty ? published : _median(observedRates);
  final duration = config.duration;
  final minimumSeconds = duration is num ? duration.toDouble() : 5.0;
  final maximumSeconds = duration is num ? duration.toDouble() : 20.0;
  return CreditEstimate(
    minimum: _roundCredits(rate * minimumSeconds),
    maximum: _roundCredits(rate * maximumSeconds),
    basis: observedRates.isEmpty ? 'bfl-rate' : 'provider-history',
  );
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
}) {
  final reported = providerCostFromPayload(payload);
  final before = generation.creditsBefore;
  final balanceDelta = before != null && balanceAfter != null
      ? before - balanceAfter
      : null;
  final measured = balanceDelta != null && balanceDelta > .0000001
      ? balanceDelta
      : null;
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
    final generationTier = generation.config.draft
        ? 'draft'
        : switch (generation.config.resolution) {
            'fhd' => route.provider == 'ltx' ? '1080p' : 'fhd',
            'qhd' => '1440p',
            '4k' => '4k',
            _ => 'hd',
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
      'ltx-2-3-fast': <String, double>{'fhd': .06, 'qhd': .12, '4k': .24},
      'ltx-2-3-pro': <String, double>{'fhd': .08, 'qhd': .16, '4k': .32},
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

  double quotedTotal(double seconds) {
    final wholeSeconds = seconds.round();
    if ((seconds - wholeSeconds).abs() < .0001) {
      final exact = pricedModel?.durationPrices[wholeSeconds];
      if (exact != null) return exact;
    }
    return rate.usdPerSecond * seconds;
  }

  if (providerId == 'bfl') {
    final credits = estimateCredits(mode, config, history);
    return CostEstimate(
      minimumUsd: creditsToUsd(credits.minimum),
      maximumUsd: creditsToUsd(credits.maximum),
      basis: credits.basis,
      providerUnitsMinimum: credits.minimum,
      providerUnitsMaximum: credits.maximum,
      providerUnitLabel: 'credits',
    );
  }
  return CostEstimate(
    minimumUsd: _roundUsd(quotedTotal(minimumSeconds)),
    maximumUsd: _roundUsd(quotedTotal(maximumSeconds)),
    basis: rate.source,
  );
}
