import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/reference_prompts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final references = promptReferenceMentions(const <MediaReferenceKind>[
    MediaReferenceKind.image,
    MediaReferenceKind.video,
    MediaReferenceKind.image,
    MediaReferenceKind.audio,
  ]);

  test('numbers prompt references independently by media kind', () {
    expect(references.map((reference) => reference.canonical), <String>[
      '@Image 1',
      '@Video 1',
      '@Image 2',
      '@Audio 1',
    ]);
  });

  test('recognizes spaced, compact, and case-insensitive authoring tags', () {
    expect(parsePromptReferenceMention('@Video 2')?.normalized, 'video2');
    expect(parsePromptReferenceMention('@image2')?.normalized, 'image2');
    expect(parsePromptReferenceMention('@AUDIO1')?.canonical, '@Audio 1');
    expect(parsePromptReferenceMention('@Image 0'), isNull);
    expect(parsePromptReferenceMention('@Image 2x'), isNull);
  });

  test('translates only attached reference mentions for each dialect', () {
    const prompt =
        'Match @Image2 to @video 1 and @Audio1; leave @Image 9 alone.';

    expect(
      translateReferencePrompt(
        prompt,
        dialect: ReferencePromptDialect.compactAt,
        available: references,
      ),
      'Match @image2 to @video1 and @audio1; leave @Image 9 alone.',
    );
    expect(
      translateReferencePrompt(
        prompt,
        dialect: ReferencePromptDialect.plainOrdinal,
        available: references,
      ),
      'Match image 2 to video 1 and audio 1; leave @Image 9 alone.',
    );
    expect(
      translateReferencePrompt(
        prompt,
        dialect: ReferencePromptDialect.angleBracketUpper,
        available: references,
      ),
      'Match <IMAGE_2> to <VIDEO_1> and <AUDIO_1>; leave @Image 9 alone.',
    );
  });

  test('translates custom authoring names to their provider ordinals', () {
    const custom = <PromptReferenceMention>[
      PromptReferenceMention(
        kind: MediaReferenceKind.video,
        number: 1,
        name: 'Video 2',
      ),
      PromptReferenceMention(
        kind: MediaReferenceKind.video,
        number: 2,
        name: 'Alexandria',
      ),
    ];

    expect(
      translateReferencePrompt(
        'Track @Video 2, then frame @Alexandria. Leave @Video 1 alone.',
        dialect: ReferencePromptDialect.compactAt,
        available: custom,
      ),
      'Track @video1, then frame @video2. Leave @Video 1 alone.',
    );
    expect(isReservedReferenceName('video1'), isTrue);
    expect(isReservedReferenceName('Video 17'), isTrue);
    expect(isReservedReferenceName('Alexandria'), isFalse);
  });

  test(
    'selects documented provider dialects without changing unknown models',
    () {
      expect(
        artCraftReferencePromptDialect('seedance_2p5'),
        ReferencePromptDialect.compactAt,
      );
      expect(
        artCraftReferencePromptDialect('grok_imagine_video'),
        ReferencePromptDialect.angleBracketUpper,
      );
      expect(
        artCraftReferencePromptDialect('minimax_h3'),
        ReferencePromptDialect.plainOrdinal,
      );
      expect(
        artCraftReferencePromptDialect('veo_3p1'),
        ReferencePromptDialect.canonical,
      );
    },
  );

  test('detaching a reference preserves later bindings as numbers shift', () {
    expect(
      detachReferenceFromPrompt(
        'Match @Image1 with @Image 2 and @Video1.',
        kind: MediaReferenceKind.image,
        number: 1,
        label: 'hero.png',
      ),
      'Match hero.png with @Image 1 and @Video1.',
    );
  });

  test('promoting a creative image leaves a clean first-frame prompt', () {
    expect(
      promoteImageReferenceToFirstFrame(
        '@Image 1 is the first frame, a sloth leans in near @Image 2.',
        number: 1,
      ),
      'the supplied first frame, a sloth leans in near @Image 1.',
    );
  });
}
