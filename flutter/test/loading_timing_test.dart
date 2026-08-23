import 'package:clawnsole/core/loading_timing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preview timing starts from measured and conservative baselines', () {
    expect(
      loadingBaseline(LoadingOperation.generationPreviewBuild),
      const Duration(milliseconds: 700),
    );
    expect(
      loadingBaseline(LoadingOperation.generationPreviewRead),
      const Duration(milliseconds: 900),
    );
  });

  test(
    'personal timings influence estimates without one sample taking over',
    () {
      final estimator = LoadingTimingEstimator();
      estimator.record(
        LoadingOperation.generationPreviewBuild,
        const Duration(milliseconds: 1300),
      );

      expect(estimator.sampleCount(LoadingOperation.generationPreviewBuild), 1);
      expect(
        estimator.expected(LoadingOperation.generationPreviewBuild),
        const Duration(milliseconds: 900),
      );
    },
  );

  test('timing history ignores noise and remains bounded', () {
    final estimator = LoadingTimingEstimator();
    estimator
      ..record(
        LoadingOperation.generationPreviewRead,
        const Duration(milliseconds: 10),
      )
      ..record(
        LoadingOperation.generationPreviewRead,
        const Duration(minutes: 1),
      );
    for (var index = 0; index < 12; index += 1) {
      estimator.record(
        LoadingOperation.generationPreviewRead,
        Duration(milliseconds: 500 + index),
      );
    }

    expect(estimator.sampleCount(LoadingOperation.generationPreviewRead), 9);
  });
}
