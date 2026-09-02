import 'package:clawnsole/core/generation_status.dart';
import 'package:clawnsole/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('spread poll delay stays within ±20% and is stable per seed', () {
    final seen = <int>{};
    for (var failures = 0; failures <= 5; failures += 1) {
      final base = automaticPollDelay(failures).inMilliseconds;
      for (var sample = 0; sample < 200; sample += 1) {
        final seed = 'gen-$sample:$failures';
        final delay = spreadPollDelay(failures, seed: seed).inMilliseconds;
        expect(
          delay,
          inInclusiveRange((base * .8).floor(), (base * 1.2).ceil()),
        );
        expect(spreadPollDelay(failures, seed: seed).inMilliseconds, delay);
        if (failures == 0) seen.add(delay);
      }
    }
    // Different records must not collapse onto one schedule.
    expect(seen.length, greaterThan(20));
  });

  test('identifier-shaped failure text is recognized', () {
    expect(
      isIdentifierLikeFailureText('3c000d4a-9340-458f-b9b5-aa36af616aeb'),
      isTrue,
    );
    expect(isIdentifierLikeFailureText('https://example.com/x'), isTrue);
    expect(isIdentifierLikeFailureText('The request was moderated.'), isFalse);
    expect(isIdentifierLikeFailureText(null), isFalse);
    expect(isIdentifierLikeFailureText('   '), isFalse);
  });

  test('records written with a task id as the error load without it', () {
    final generation = Generation.fromJson(<String, Object?>{
      'localId': 'gen-1',
      'status': 'Task not found',
      'prompt': 'a red bicycle',
      'mode': 't2v',
      'config': <String, Object?>{},
      'createdAt': '2026-08-16T00:00:00Z',
      'updatedAt': '2026-08-16T00:00:00Z',
      'error': '3c000d4a-9340-458f-b9b5-aa36af616aeb',
    });
    expect(generation.error, isNull);
    expect(generation.isFailed, isTrue);
    expect(isExpiryShapedStatus(generation.status), isTrue);
  });

  test('theme mode round-trips through preferences JSON', () {
    const preferences = AppPreferences(themeMode: AppThemeMode.dark);
    final restored = AppPreferences.fromJson(preferences.toJson());
    expect(restored.themeMode, AppThemeMode.dark);
    expect(
      AppPreferences.fromJson(<String, Object?>{
        'themeMode': 'sepia',
      }).themeMode,
      AppThemeMode.system,
    );
    expect(const AppPreferences().themeMode, AppThemeMode.system);
  });
}
