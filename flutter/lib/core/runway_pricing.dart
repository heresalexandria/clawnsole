import 'dart:math' as math;

double runwayKling4DiscountFactor({DateTime? asOf}) =>
    (asOf ?? DateTime.now()).toUtc().isBefore(DateTime.utc(2026, 12, 1))
    ? .8
    : 1;

/// Runway rounds the list-price Kling 4 charge up before applying its temporary
/// 20% promotion, then rounds again. The promotion expires in UTC automatically.
double runwayKling4Credits({
  required String resolution,
  required double outputSeconds,
  required double inputSeconds,
  required bool hasInputVideo,
  DateTime? asOf,
}) {
  final fullHd = resolution == 'fhd';
  final credits = hasInputVideo
      ? (fullHd ? 14.1 : 9.4) *
            (outputSeconds + math.max(inputSeconds.clamp(0, 30), outputSeconds))
      : (fullHd ? 23.5 : 15.7) * outputSeconds;
  return (credits.ceil() * runwayKling4DiscountFactor(asOf: asOf))
      .ceilToDouble();
}

/// Exact USD clip totals for the cost desk's text/image rows. Video references
/// and source videos use their measured lengths in [runwayKling4Credits].
Map<int, double> runwayKling4DurationPrices({
  required String resolution,
  DateTime? asOf,
}) {
  final pricingTime = asOf ?? DateTime.now();
  return <int, double>{
    for (var seconds = 3; seconds <= 30; seconds++)
      seconds:
          runwayKling4Credits(
            resolution: resolution,
            outputSeconds: seconds.toDouble(),
            inputSeconds: 0,
            hasInputVideo: false,
            asOf: pricingTime,
          ) /
          100,
  };
}
