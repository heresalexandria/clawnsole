import 'dart:convert';

import 'package:clawnsole/core/generation_preferences.dart';
import 'package:clawnsole/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('generation preferences codec', () {
    const controls = GenerationPreferences(
      aspectRatio: '9:16',
      autoDuration: true,
      durationSeconds: 12,
      frameRate: 6,
      resolution: '1080p',
      generateAudio: false,
      safetyTolerance: 4,
      draft: true,
      exactTiming: true,
      upscaleFactor: 2.5,
      upscaleCreativity: 75,
    );

    test('round-trips every control through versioned JSON', () {
      final encoded = controls.toJson();
      expect(encoded['schemaVersion'], 1);
      final decoded = GenerationPreferences.tryFromJson(
        jsonDecode(jsonEncode(encoded)),
      );
      expect(decoded, controls);
      expect(decoded.hashCode, controls.hashCode);
    });

    test('keys distinguish punctuation inside provider and model ids', () {
      final keys = <String>{
        generationPreferenceKey('a/b', 'c'),
        generationPreferenceKey('a', 'b/c'),
        generationPreferenceKey('a|b', 'c'),
        generationPreferenceKey('a', 'b|c'),
        generationPreferenceKey('a"', '[b]'),
      };
      expect(keys, hasLength(5));
      expect(
        jsonDecode(generationPreferenceKey('provider/a', 'model|b')),
        <String>['provider/a', 'model|b'],
      );
    });

    test('missing fields retain original composer defaults', () {
      final decoded = GenerationPreferences.tryFromJson(<String, Object?>{});
      expect(decoded, const GenerationPreferences());
      expect(decoded!.toJson(), <String, Object?>{
        'schemaVersion': 1,
        'aspectRatio': '16:9',
        'autoDuration': false,
        'durationSeconds': 8,
        'frameRate': 2,
        'resolution': 'hd',
        'generateAudio': true,
        'safetyTolerance': 2,
        'draft': false,
        'exactTiming': false,
        'upscaleFactor': 2.0,
        'upscaleCreativity': 1,
      });
    });

    test('invalid containers and unsupported schema versions are ignored', () {
      for (final value in <Object?>[
        null,
        'broken',
        17,
        <Object?>[],
        <String, Object?>{'schemaVersion': 2, 'generateAudio': false},
        <String, Object?>{'schemaVersion': '1'},
        <String, Object?>{'schemaVersion': -1},
        <String, Object?>{'schemaVersion': double.infinity},
      ]) {
        expect(GenerationPreferences.tryFromJson(value), isNull);
      }
    });

    test(
      'malformed fields fall back independently without losing valid ones',
      () {
        final decoded = GenerationPreferences.tryFromJson(<String, Object?>{
          'aspectRatio': ' 9:16 ',
          'autoDuration': 'true',
          'durationSeconds': '12',
          'frameRate': <Object?>[],
          'resolution': ' ',
          'generateAudio': false,
          'safetyTolerance': null,
          'draft': 1,
          'exactTiming': <String, Object?>{},
          'upscaleFactor': double.nan,
          'upscaleCreativity': double.negativeInfinity,
        });
        expect(
          decoded,
          const GenerationPreferences(
            aspectRatio: '9:16',
            generateAudio: false,
          ),
        );
      },
    );

    test('finite scalars are bounded and non-finite numbers are safe', () {
      final bounded = GenerationPreferences.tryFromJson(<String, Object?>{
        'durationSeconds': 1e200,
        'frameRate': -20,
        'safetyTolerance': 1e200,
        'upscaleFactor': -10,
        'upscaleCreativity': 1e200,
      });
      expect(bounded!.durationSeconds, 86400);
      expect(bounded.frameRate, 1);
      expect(bounded.safetyTolerance, 1000);
      expect(bounded.upscaleFactor, 1);
      expect(bounded.upscaleCreativity, 100);
      expect(() => jsonEncode(bounded.toJson()), returnsNormally);

      for (final value in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          GenerationPreferences.tryFromJson(<String, Object?>{
            'durationSeconds': value,
            'frameRate': value,
            'safetyTolerance': value,
            'upscaleFactor': value,
            'upscaleCreativity': value,
          }),
          const GenerationPreferences(),
        );
      }
    });

    test('unknown fields cannot smuggle draft content into preferences', () {
      final decoded = GenerationPreferences.tryFromJson(<String, Object?>{
        ...controls.toJson(),
        'prompt': 'Private script',
        'seed': 4815,
        'screenplayMode': true,
        'referenceTask': 'edit',
        'references': <String>['private-reference'],
        'videoUrl': 'https://example.test/private-source',
        'mediaConfig': <String, Object?>{'base64': 'private-media'},
        'apiKey': 'private-key',
        'localFolderId': 'private-folder',
      });
      expect(decoded!.toJson(), controls.toJson());
      expect(
        GenerationPreferences.tryFromJson(<String, Object?>{
          'aspectRatio': 'x' * 129,
          'resolution': <String>['1080p'],
        }),
        const GenerationPreferences(),
      );
    });

    test('changing any reusable control changes record equality', () {
      final changes = <String, Object?>{
        'aspectRatio': '1:1',
        'autoDuration': false,
        'durationSeconds': 10,
        'frameRate': 4,
        'resolution': '720p',
        'generateAudio': true,
        'safetyTolerance': 3,
        'draft': false,
        'exactTiming': false,
        'upscaleFactor': 3,
        'upscaleCreativity': 25,
      };
      for (final entry in changes.entries) {
        final changed = GenerationPreferences.tryFromJson(<String, Object?>{
          ...controls.toJson(),
          entry.key: entry.value,
        });
        expect(changed, isNot(controls), reason: entry.key);
      }
    });
  });

  group('app generation preferences', () {
    const legacy = AppPreferences(
      activeSection: AppSection.library,
      libraryFilter: LibraryFilter.ready,
      recentWorkViewMode: GenerationViewMode.compact,
      libraryViewMode: GenerationViewMode.mini,
      provider: 'ltx',
      model: 'ltx-2-3-fast',
      defaultStorage: LibraryStorage.drive,
      libraryStorageFilter: LibraryStorageFilter.drive,
      referenceStorageFilter: LibraryStorageFilter.local,
      generationPlaceholderStyle: GenerationPlaceholderStyle.cyclone,
      lastLocalGenerationFolderId: 'local-folder',
      lastDriveGenerationFolderId: 'drive-folder',
      costDeskColumns: <String>['model', 'duration'],
      localVideoCacheMb: 250,
      localThumbnailCacheMb: 75,
      autoFixReferenceVideos: false,
      themeMode: AppThemeMode.dark,
      rewriteProvider: 'openai',
      rewriteModels: <String, String>{'openai': 'test-rewrite-model'},
      rewriteEfforts: <String, String>{'openai': 'high'},
      favoriteModels: <String>['ltx|ltx-2-3-fast'],
      favoriteProviders: <String>['ltx'],
      providerRetentionAcknowledgements: <String, String>{'ltx': 'digest'},
    );

    test('legacy preferences keep their exact serialized content', () {
      final json = legacy.toJson();
      expect(json.containsKey('generationPreferences'), isFalse);
      final restored = AppPreferences.fromJson(json);
      expect(restored.generationPreferences, isEmpty);
      expect(restored.toJson(), json);
      expect(const AppPreferences().generationPreferences, isEmpty);
    });

    test('round-trips multiple models while retaining unrelated settings', () {
      final controls = <String, GenerationPreferences>{
        generationPreferenceKey(
          'ltx',
          'ltx-2-3-fast',
        ): const GenerationPreferences(
          aspectRatio: '9:16',
          durationSeconds: 12,
        ),
        generationPreferenceKey('unknown/provider', 'future-model'):
            const GenerationPreferences(resolution: '4k', generateAudio: false),
      };
      final saved = legacy.copyWith(generationPreferences: controls);
      final restored = AppPreferences.fromJson(
        jsonDecode(jsonEncode(saved.toJson())) as Map<String, Object?>,
      );
      expect(restored.generationPreferences, controls);
      expect(
        restored.copyWith(generationPreferences: {}).toJson(),
        legacy.toJson(),
      );
      expect(
        restored.copyWith(themeMode: AppThemeMode.light).generationPreferences,
        controls,
      );
    });

    test('serialization order is stable for settings vault comparisons', () {
      final keyA = generationPreferenceKey('provider-a', 'model');
      final keyB = generationPreferenceKey('provider-b', 'model');
      final first = legacy.copyWith(
        generationPreferences: {
          keyA: const GenerationPreferences(),
          keyB: const GenerationPreferences(generateAudio: false),
        },
      );
      final second = legacy.copyWith(
        generationPreferences: {
          keyB: const GenerationPreferences(generateAudio: false),
          keyA: const GenerationPreferences(),
        },
      );
      expect(jsonEncode(first.toJson()), jsonEncode(second.toJson()));
    });

    test(
      'broken entries cannot invalidate valid models or other preferences',
      () {
        final validKey = generationPreferenceKey('bfl', 'flux-3-video');
        final restored = AppPreferences.fromJson(<String, Object?>{
          ...legacy.toJson(),
          'generationPreferences': <Object?, Object?>{
            validKey: <String, Object?>{'generateAudio': false},
            'future-model': <String, Object?>{'schemaVersion': 2},
            'bad-model': 'not settings',
            ' ': <String, Object?>{},
            42: <String, Object?>{},
          },
        });
        expect(restored.generationPreferences, <String, GenerationPreferences>{
          validKey: const GenerationPreferences(generateAudio: false),
        });
        expect(
          restored.copyWith(generationPreferences: {}).toJson(),
          legacy.toJson(),
        );
        for (final value in <Object?>[null, 'broken', 1, <Object?>[]]) {
          expect(
            AppPreferences.fromJson(<String, Object?>{
              ...legacy.toJson(),
              'generationPreferences': value,
            }).toJson(),
            legacy.toJson(),
          );
        }
      },
    );
  });
}
