import 'package:clawnsole/core/generation_timing.dart';
import 'package:clawnsole/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const config = GenerationConfig(
    aspectRatio: '16:9',
    duration: 5,
    resolution: 'sd',
    generateAudio: false,
    safetyTolerance: 2,
    draft: false,
  );
  final acceptedAt = DateTime.utc(2026, 8, 23, 12);

  Generation generation({
    required String id,
    String provider = 'artcraft',
    String model = 'seedance_2p5',
    String status = 'Pending',
    GenerationConfig generationConfig = config,
    DateTime? completedAt,
    String? providerResponse,
  }) => Generation(
    localId: id,
    provider: provider,
    model: model,
    status: status,
    prompt: 'A sloth waits with measurable restraint.',
    mode: VideoMode.t2v,
    config: generationConfig,
    createdAt: acceptedAt.subtract(const Duration(seconds: 1)),
    updatedAt: completedAt ?? acceptedAt,
    providerAcceptedAt: acceptedAt,
    providerCompletedAt: completedAt,
    lastProviderResponse: providerResponse,
  );

  test('Seedance 2.5 baselines are provider-specific', () {
    expect(
      benchmarkGenerationDuration(generation(id: 'artcraft')),
      const Duration(seconds: 112),
    );
    expect(
      benchmarkGenerationDuration(
        generation(
          id: 'atlas',
          provider: 'atlas',
          model: 'bytedance/seedance-2.5/text-to-video',
        ),
      ),
      const Duration(seconds: 237),
    );
  });

  test('baseline progress moves without trusting ArtCraft zero percent', () {
    final item = generation(id: 'working');
    final estimate = generationProgressEstimate(
      item,
      const <Generation>[],
      now: acceptedAt.add(const Duration(seconds: 56)),
    );

    expect(estimate.basis, GenerationProgressBasis.baseline);
    expect(estimate.expectedDuration, const Duration(seconds: 112));
    expect(estimate.percentage, closeTo(50, .1));
  });

  test('comparable personal history progressively tunes the baseline', () {
    final item = generation(id: 'working');
    final history = <Generation>[
      generation(
        id: 'fast',
        status: 'Ready',
        completedAt: acceptedAt.add(const Duration(seconds: 80)),
      ),
      generation(
        id: 'slow',
        status: 'Ready',
        completedAt: acceptedAt.add(const Duration(seconds: 100)),
      ),
      generation(
        id: 'other-provider',
        provider: 'atlas',
        model: 'bytedance/seedance-2.5/text-to-video',
        status: 'Ready',
        completedAt: acceptedAt.add(const Duration(seconds: 300)),
      ),
    ];

    final estimate = generationProgressEstimate(
      item,
      history,
      now: acceptedAt.add(const Duration(seconds: 50)),
    );

    // Personal median 90s blended with two virtual 112s benchmark samples.
    expect(estimate.basis, GenerationProgressBasis.historical);
    expect(estimate.sampleCount, 2);
    expect(estimate.expectedDuration, const Duration(seconds: 101));
    expect(estimate.percentage, closeTo(49.5, .1));
  });

  test('legacy ArtCraft provider timestamps remain usable history', () {
    final legacy = Generation(
      localId: 'legacy',
      provider: 'artcraft',
      model: 'seedance_2p5',
      status: 'Ready',
      prompt: 'Legacy timing',
      mode: VideoMode.i2v,
      config: config,
      createdAt: DateTime.utc(2026, 8, 20, 11, 55),
      updatedAt: DateTime.utc(2026, 8, 20, 12, 10),
      lastProviderResponse: '''
        {
          "state": {
            "created_at": "2026-08-20T12:00:00Z",
            "maybe_result": {
              "maybe_successfully_completed_at": "2026-08-20T12:04:00Z"
            }
          }
        }
      ''',
    );

    expect(observedGenerationDuration(legacy), const Duration(minutes: 4));
  });

  test('unknown routes stay indeterminate without comparable history', () {
    final item = generation(
      id: 'unknown',
      provider: 'ltx',
      model: 'ltx-2-3-fast',
    );
    final estimate = generationProgressEstimate(item, const <Generation>[]);

    expect(estimate.basis, GenerationProgressBasis.indeterminate);
    expect(estimate.percentage, isNull);
  });
}
