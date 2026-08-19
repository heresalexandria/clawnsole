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
