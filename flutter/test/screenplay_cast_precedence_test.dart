import 'package:clawnsole/core/screenplay.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('authored casting suppresses only matching generated names', () {
    const prompt = 'Extend @Film.\n\n  Alexandria: @New clip\n';
    const mappings = {
      'ALEXANDRIA': ['Earlier clip'],
      'OTHER': ['Other clip'],
    };

    expect(screenplayCastLines(mappings, authoredPrompt: prompt), [
      'OTHER: @Other clip',
    ]);
    expect(screenplayCastLines(mappings), [
      'ALEXANDRIA: @Earlier clip',
      'OTHER: @Other clip',
    ]);
    expect(mappings['ALEXANDRIA'], ['Earlier clip']);
  });

  test(
    'script and casting aliases match normalized names in either direction',
    () {
      const aliases = {'  Alexandria  ': '  The   Hero '};
      for (final inlineName in ['alexandria', 'the hero']) {
        final prompt = '$inlineName: @New clip';
        expect(
          screenplayAuthoredMappingNames(prompt, characterAliases: aliases),
          {'ALEXANDRIA', 'THE HERO'},
        );
        expect(
          screenplayCastLines(
            const {
              'The Hero': ['Earlier clip'],
              'SECOND HERO': ['Other clip'],
            },
            authoredPrompt: prompt,
            characterAliases: aliases,
          ),
          ['SECOND HERO: @Other clip'],
        );
      }
    },
  );

  test(
    'descriptive authored casting wins without changing legacy extraction',
    () {
      const prompt = 'Alice: use @Alternate for appearance.\n';
      const aliases = {'alice': 'THE HERO'};
      expect(
        screenplayAuthoredMappingNames(prompt, characterAliases: aliases),
        {'ALICE', 'THE HERO'},
      );
      expect(
        screenplayCastLines(
          const {
            'THE HERO': ['Earlier clip'],
            'OTHER': ['Other clip'],
          },
          authoredPrompt: prompt,
          characterAliases: aliases,
        ),
        ['OTHER: @Other clip'],
      );
      expect(screenplayMappings(prompt), isEmpty);
    },
  );

  test(
    'emails, body mentions, and unfinished names do not suppress casting',
    () {
      const prompt =
          'ALICE: send to alice@example.test\n'
          'Use @Alternate for Alice.\n'
          'ALICE: @\n'
          'ALICE: @@invalid\n'
          'EXT. HARBOR: use @Alternate\n'
          'invalid/name: use @Alternate';
      expect(screenplayAuthoredMappingNames(prompt), isEmpty);
      expect(
        screenplayCastLines(const {
          'ALICE': ['Earlier clip'],
        }, authoredPrompt: prompt),
        ['ALICE: @Earlier clip'],
      );
    },
  );
}
