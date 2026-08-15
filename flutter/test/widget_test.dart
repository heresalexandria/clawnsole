import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/app/clawnsole_app.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/pricing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses BFL published FLUX 3 video rates', () {
    const hdEightSeconds = GenerationConfig(
      aspectRatio: '16:9',
      duration: 8,
      resolution: 'hd',
      generateAudio: true,
      safetyTolerance: 2,
      draft: false,
    );
    const draftTenSeconds = GenerationConfig(
      aspectRatio: '16:9',
      duration: 10,
      resolution: 'hd',
      generateAudio: true,
      safetyTolerance: 2,
      draft: true,
    );

    expect(estimateCredits(VideoMode.t2v, hdEightSeconds).minimum, 136);
    expect(estimateCredits(VideoMode.v2v, hdEightSeconds).minimum, 328);
    expect(estimateCredits(VideoMode.t2v, draftTenSeconds).minimum, 60);
    expect(creditsToUsd(136), 1.36);

    const fhdAuto = GenerationConfig(
      aspectRatio: '16:9',
      duration: 'auto',
      resolution: 'fhd',
      generateAudio: true,
      safetyTolerance: 2,
      draft: false,
    );
    final autoEstimate = estimateCredits(VideoMode.v2v, fhdAuto);
    expect(autoEstimate.minimum, 265);
    expect(autoEstimate.maximum, 1060);
  });

  test('uses exact matching BFL history as the next estimate', () {
    final now = DateTime.utc(2026, 8, 15);
    const config = GenerationConfig(
      aspectRatio: '16:9',
      duration: 8,
      resolution: 'hd',
      generateAudio: true,
      safetyTolerance: 2,
      draft: false,
    );
    final history = <Generation>[
      Generation(
        localId: 'quote',
        status: 'Ready',
        prompt: 'Prior generation',
        mode: VideoMode.t2v,
        config: config,
        createdAt: now,
        updatedAt: now,
        cost: 130,
      ),
    ];

    final estimate = estimateCredits(VideoMode.t2v, config, history);
    expect(estimate.minimum, 130);
    expect(estimate.maximum, 130);
    expect(estimate.basis, 'provider-history');
  });

  test(
    'round-trips compact history, billing, and durable asset references',
    () {
      final now = DateTime.utc(2026, 8, 15);
      final original = StoredData(
        apiKey: 'secret',
        generations: <Generation>[
          Generation(
            localId: 'one',
            status: 'Ready',
            prompt: 'A patient sloth reaches for a brass switch.',
            mode: VideoMode.i2v,
            config: const GenerationConfig(
              aspectRatio: '16:9',
              duration: 8,
              resolution: 'hd',
              generateAudio: true,
              safetyTolerance: 2,
              draft: false,
              exactTiming: true,
              keyframes: <KeyframeLabel>[
                KeyframeLabel(
                  label: 'start.png',
                  seconds: 0,
                  source: AssetReference(
                    kind: 'local',
                    value: 'asset-input',
                    label: 'start.png',
                    contentType: 'image/png',
                    bytes: 42,
                  ),
                ),
              ],
            ),
            createdAt: now,
            updatedAt: now,
            estimatedCreditsMin: 136,
            estimatedCreditsMax: 136,
            creditsBefore: 500,
            creditsAfter: 364,
            cost: 136,
            resultAsset: const AssetReference(
              kind: 'local',
              value: 'asset-video',
              label: 'clawnsole.mp4',
              contentType: 'video/mp4',
              bytes: 1024,
            ),
          ),
        ],
      );

      final decoded = StoredData.decode(original.encode());
      expect(decoded.apiKey, 'secret');
      expect(decoded.generations.single.cost, 136);
      expect(decoded.generations.single.creditsAfter, 364);
      expect(decoded.generations.single.config.exactTiming, isTrue);
      expect(
        decoded.generations.single.config.keyframes!.single.source!.value,
        'asset-input',
      );
      expect(decoded.generations.single.resultAsset!.value, 'asset-video');
      expect(original.encode(), isNot(contains('data:image')));
    },
  );

  testWidgets('renders the Clawnsole Flutter shell', (tester) async {
    await tester.pumpWidget(const ClawnsoleApp());
    expect(find.text('Clawnsole'), findsOneWidget);
    expect(find.text('Create'), findsWidgets);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.system);
    expect(app.darkTheme, isNotNull);

    await tester.tap(find.byTooltip('Appearance: system'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('System'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
  });

  test('form exposes every FLUX 3 generation mode', () {
    final form = GenerationFormState();
    expect(VideoMode.values, hasLength(4));
    expect(form.mode, VideoMode.t2v);
  });
}
