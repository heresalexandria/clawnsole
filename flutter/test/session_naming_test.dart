import 'package:clawnsole/core/session_naming.dart';
import 'package:characters/characters.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('ai.clawnsole/session_naming');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'fallback extracts a compact subject from visual prompt boilerplate',
    () {
      expect(
        fallbackSessionName(
          'Create a cinematic blue-hour tracking shot following a red fox '
          'through a snowy pine forest.',
        ),
        'Blue-Hour Red Fox Snowy Pine Forest',
      );
    },
  );

  test('fallback favors repeated meaningful terms while preserving order', () {
    expect(
      fallbackSessionName(
        'Fox enters a forest. The forest surrounds the fox while forest '
        'mist gathers.',
      ),
      'Fox Enters Forest Surrounds Mist Gathers',
    );
  });

  test('fallback drops conversational request boilerplate', () {
    expect(
      fallbackSessionName(
        'Can you make me a video of my cat walking down the street at sunset?',
      ),
      'Cat Walking Down Street Sunset',
    );
  });

  test(
    'fallback removes URLs, reference markers, controls, and separators',
    () {
      expect(
        fallbackSessionName(
          'Animate @Image 1 with @Video2 / a lantern\nnear '
          'https://example.test/private?id=7',
        ),
        'Lantern Near',
      );
    },
  );

  test('fallback handles empty and non-Latin prompts', () {
    expect(fallbackSessionName('  https://example.test/a  '), 'New session');
    expect(fallbackSessionName('月明かりの下で赤い狐が森を走る'), '月明かりの下で赤い狐が森を走る');
    expect(
      fallbackSessionName('', fallback: 'Untitled project'),
      'Untitled project',
    );
  });

  test('fallback stays within the folder limit without splitting emoji', () {
    final value = fallbackSessionName(
      'https://example.test/only-reference',
      fallback: List<String>.filled(20, '👩🏽‍🎨').join(),
    );
    expect(value.length, lessThanOrEqualTo(maxSessionNameCharacters));
    expect(
      value.characters.every((character) => character == '👩🏽‍🎨'),
      isTrue,
    );
  });

  test(
    'platform generator bounds input and sanitizes the native title',
    () async {
      MethodCall? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            received = call;
            return 'Session title: “red fox / winter: study?”\nExtra commentary';
          });

      final generated = await const PlatformSessionNameGenerator().generate(
        List<String>.filled(3000, 'a').join(),
      );

      expect(generated, 'red fox winter study');
      expect(received?.method, 'generate');
      final arguments = received?.arguments as Map<Object?, Object?>;
      expect(
        (arguments['source']! as String).length,
        maxSessionNamingSourceCharacters,
      );
    },
  );

  test(
    'platform generator silently falls back when native naming fails',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(code: 'unavailable');
          });

      expect(
        await const PlatformSessionNameGenerator().generate('A fox in snow'),
        isNull,
      );
    },
  );
}
