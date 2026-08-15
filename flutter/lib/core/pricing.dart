import 'models.dart';

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
