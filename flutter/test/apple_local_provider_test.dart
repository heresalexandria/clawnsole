import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/provider_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Apple Local is keyless and exposes still and animation modes', () {
    expect(appleLocalProvider.requiresApiKey, isFalse);
    expect(appleLocalProvider.isLocal, isTrue);
    expect(appleLocalProvider.models, hasLength(2));
    expect(
      modelById('apple-local', 'apple-local-image').outputKind,
      GenerationOutputKind.image,
    );
    expect(
      modelById('apple-local', 'apple-local-animation').supportsFrameRate,
      isTrue,
    );
  });

  test('local generation settings round-trip output kind and frame rate', () {
    final now = DateTime.utc(2026, 8, 18);
    final original = Generation(
      localId: 'local-test',
      provider: 'apple-local',
      model: 'apple-local-animation',
      billingUnit: 'local',
      outputKind: GenerationOutputKind.video,
      status: 'Pending',
      prompt: 'A fox waves',
      mode: VideoMode.t2v,
      config: const GenerationConfig(
        aspectRatio: '16:9',
        duration: 4,
        resolution: 'hd',
        generateAudio: false,
        safetyTolerance: 2,
        draft: false,
        frameRate: 3,
      ),
      createdAt: now,
      updatedAt: now,
    );

    final restored = Generation.fromJson(original.toJson());
    expect(restored.billingUnit, 'local');
    expect(restored.config.frameRate, 3);
    expect(restored.outputKind, GenerationOutputKind.video);
  });

  test('still image output kind is persisted explicitly', () {
    final now = DateTime.utc(2026, 8, 18);
    final original = Generation(
      localId: 'image-test',
      provider: 'apple-local',
      model: 'apple-local-image',
      billingUnit: 'local',
      outputKind: GenerationOutputKind.image,
      status: 'Ready',
      prompt: 'A painted lighthouse',
      mode: VideoMode.t2v,
      config: const GenerationConfig(
        aspectRatio: '1:1',
        duration: 1,
        resolution: 'fhd',
        generateAudio: false,
        safetyTolerance: 2,
        draft: false,
      ),
      createdAt: now,
      updatedAt: now,
    );

    final restored = Generation.fromJson(original.toJson());
    expect(restored.isImage, isTrue);
    expect(restored.toJson()['outputKind'], 'image');
  });
}
