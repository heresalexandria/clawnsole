import 'models.dart';

/// Published ArtCraft reference-video pricing, audited 2026-10-30 against
/// storytold/artcraft-services' providers/artcraft/*/cost.rs. The public quote
/// endpoint requires ArtCraft media tokens to select these rates; URLs and
/// unuploaded local references cannot select them through that endpoint.
CostEstimate? artCraftReferenceEstimate(
  String model,
  Map<String, Object?> input,
) {
  final videos = input['reference_videos'];
  final kinds = input['reference_types'];
  final pendingVideos = input['reference_video_duration_pending'];
  final hasVideo =
      videos is List && videos.isNotEmpty ||
      kinds is List && kinds.contains('video') ||
      input.containsKey('reference_video_duration_seconds') ||
      pendingVideos is num && pendingVideos > 0;
  final output = input['duration'];
  if (!hasVideo || output is! num || !output.isFinite || output <= 0) {
    return null;
  }
  final resolution = input['resolution']?.toString() ?? 'hd';
  final centiCents = switch (model) {
    'seedance_2p0' => switch (resolution) {
      'sd' => 881,
      'fhd' => 5110,
      '4k' => 11380,
      _ => 2205,
    },
    'seedance_2p0_fast' => resolution == 'sd' ? 841 : 1560,
    'seedance_2p0_bp' || 'seedance_2p0_bpu' => switch (resolution) {
      'sd' => 1020,
      'fhd' => 5780,
      '4k' => 11900,
      _ => 2570,
    },
    'seedance_2p0_bp_fast' ||
    'seedance_2p0_bpu_fast' => resolution == 'sd' ? 965 : 2050,
    'seedance_2p0_mini' => resolution == 'sd' ? 435 : 1070,
    'seedance_2p0_bp_mini' ||
    'seedance_2p0_bpu_mini' => resolution == 'sd' ? 450 : 1095,
    _ => null,
  };
  double minimum;
  double maximum;
  if (centiCents != null) {
    minimum = maximum = (centiCents * output / 100).ceilToDouble();
  } else if (model == 'seedance_2p5' || model == 'seedance_2p5_u') {
    final centsPerSecond = model == 'seedance_2p5'
        ? switch (resolution) {
            'sd' => 7.24279835,
            'fhd' => 38.49728574,
            _ => 15.84362140,
          }
        : switch (resolution) {
            'sd' => 8.55967078,
            'fhd' => 41.84487580,
            _ => 18.72427984,
          };
    final seconds = input['reference_video_duration_seconds'];
    final pending = input['reference_video_duration_pending'];
    final complete =
        seconds is num &&
        seconds.isFinite &&
        seconds > 0 &&
        !(pending is num && pending > 0);
    final minimumInput = seconds is num && seconds.isFinite && seconds > 0
        ? seconds.ceil().clamp(4, 30)
        : 4;
    final maximumInput = complete ? minimumInput : 30;
    minimum = (centsPerSecond * (output + minimumInput)).ceilToDouble();
    maximum = (centsPerSecond * (output + maximumInput)).ceilToDouble();
  } else {
    return null;
  }
  return CostEstimate(
    minimumUsd: minimum / 100,
    maximumUsd: maximum / 100,
    providerUnitsMinimum: minimum,
    providerUnitsMaximum: maximum,
    providerUnitLabel: 'credits',
    basis: minimum == maximum
        ? 'artcraft-published-reference-rate'
        : 'artcraft-published-reference-duration-range',
  );
}
