/// Async work with a useful duration estimate but no provider- or byte-level
/// progress signal.
enum LoadingOperation { generationPreviewBuild, generationPreviewRead }

/// Conservative first-run expectations for local UI work.
///
/// The preview-build baseline was measured on 2026-08-23 from four fresh
/// previews in a real Clawnsole Electron library containing generated 30-second
/// films. They took 524-656 ms (640 ms median) from retained film creation to
/// the first cached frame; 700 ms leaves a little headroom. Preview reads may
/// cross Google Drive, so their unmeasured network component gets a wider
/// first-run allowance.
Duration loadingBaseline(LoadingOperation operation) => switch (operation) {
  LoadingOperation.generationPreviewBuild => const Duration(milliseconds: 700),
  LoadingOperation.generationPreviewRead => const Duration(milliseconds: 900),
};

/// Learns a small, process-local timing profile for estimated loading bars.
///
/// Two virtual baseline samples prevent one unusually warm or cold operation
/// from making the next estimate jump. Samples stay device-local and bounded;
/// they are neither synced as preferences nor added to compact history JSON.
class LoadingTimingEstimator {
  final Map<LoadingOperation, List<Duration>> _samples =
      <LoadingOperation, List<Duration>>{};

  static const int _maximumSamples = 9;
  static const Duration _minimumSample = Duration(milliseconds: 50);
  static const Duration _maximumSample = Duration(seconds: 30);

  Duration expected(LoadingOperation operation) {
    final baseline = loadingBaseline(operation);
    final samples = _samples[operation];
    if (samples == null || samples.isEmpty) return baseline;
    final ordered = samples.map((item) => item.inMicroseconds).toList()..sort();
    final middle = ordered.length ~/ 2;
    final medianMicros = ordered.length.isOdd
        ? ordered[middle]
        : ((ordered[middle - 1] + ordered[middle]) / 2).round();
    final personalWeight = samples.length.clamp(1, 8);
    return Duration(
      microseconds:
          ((baseline.inMicroseconds * 2 + medianMicros * personalWeight) /
                  (2 + personalWeight))
              .round(),
    );
  }

  int sampleCount(LoadingOperation operation) =>
      _samples[operation]?.length ?? 0;

  void record(LoadingOperation operation, Duration elapsed) {
    if (elapsed < _minimumSample || elapsed > _maximumSample) return;
    final samples = _samples.putIfAbsent(operation, () => <Duration>[]);
    samples.add(elapsed);
    if (samples.length > _maximumSamples) samples.removeAt(0);
  }
}
