import 'dart:typed_data';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/ui/generation_view_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Extend opens the next scene: the delivered film becomes the reference to
/// carry on from, the direction starts again at `Extend @name.`, and every
/// other choice — model, settings, aesthetic, and the references that still fit —
/// comes along.
void main() {
  test('only a delivered video on a reference model can be extended', () {
    final controller = _controller();
    addTearDown(controller.dispose);

    expect(controller.canExtend(_film()), isTrue);
    expect(controller.canExtend(_film(status: 'Working')), isFalse);
    expect(controller.canExtend(_film(delivered: false)), isFalse);
    expect(
      controller.canExtend(_film(outputKind: GenerationOutputKind.image)),
      isFalse,
    );
    // FLUX 3 renders video but takes no reference video to extend.
    expect(
      controller.canExtend(_film(provider: 'bfl', model: 'flux-3-video')),
      isFalse,
    );
    expect(
      controller.canExtend(_film(provider: 'nowhere', model: 'nothing')),
      isFalse,
    );
  });

  testWidgets('the card menu offers Extend only where it works', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);

    await _pumpMenu(tester, controller, _film());
    await tester.tap(find.byType(GenerationActionsMenu));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('generation-action-extend')), findsOne);
    expect(find.text('Extend'), findsOne);

    // Close the menu without running the action: this test is about what is
    // offered, and extend's own notice would outlive the tree.
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    await _pumpMenu(
      tester,
      controller,
      _film(provider: 'bfl', model: 'flux-3-video'),
    );
    await tester.tap(find.byType(GenerationActionsMenu));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('generation-action-extend')),
      findsNothing,
    );
  });

  test('extend writes the next scene and keeps every other choice', () async {
    final controller = _controller();
    addTearDown(controller.dispose);
    final aesthetic = controller.saveAestheticReference(
      title: 'Golden hour',
      text: 'Warm amber light.',
      icon: 'sun',
      color: 0xffaf853c,
    );

    await controller.extend(
      _film(
        title: 'Rooftop chase',
        prompt: 'A sloth climbs the fire escape.\n\nWarm amber light.',
        aestheticReferenceId: aesthetic,
        aestheticText: 'Warm amber light.',
      ),
    );

    expect(controller.form.prompt, 'Extend @Rooftop chase.');
    expect(controller.form.references, hasLength(1));
    expect(
      controller.referencePromptName(controller.form.references.single),
      'Rooftop chase',
    );
    expect(controller.form.references.single.kind, MediaReferenceKind.video);
    expect(controller.selectedAestheticReference?.id, aesthetic);
    expect(controller.form.aspectRatio, '9:16');
    expect(controller.form.durationSeconds, 5);
    expect(controller.selectedModelId, 'seedance2');
    expect(
      controller.generationPrompt,
      'Extend @Rooftop chase.\n\nWarm amber light.',
    );
    expect(controller.notice, 'Ready to extend “Rooftop chase”.');
    expect(controller.section, AppSection.create);
  });

  test('a screenplay carries its scene heading into the next scene', () async {
    final controller = _controller();
    addTearDown(controller.dispose);

    await controller.extend(
      _film(
        title: 'Apartment',
        screenplayMode: true,
        prompt:
            'INT. NYC APARTMENT - NIGHT\n\nThe sloth reaches for the lamp.\n\n'
            'EXT. ROOFTOP - NIGHT\n\nRain.',
      ),
    );

    expect(
      controller.form.prompt,
      'Extend @Apartment.\nINT. NYC APARTMENT - NIGHT',
    );
    expect(controller.form.screenplayMode, isTrue);
  });

  test(
    "the film's references come back, cast first, while the model has room",
    () async {
      final controller = _controller();
      addTearDown(controller.dispose);

      await controller.extend(
        _film(
          title: 'Rooftop chase',
          prompt: 'A sloth climbs.\n\nHERO: @Sloth\nRIVAL: @Moth',
          references: <MediaReferenceLabel>[
            _reference('Sloth', MediaReferenceKind.image),
            _reference('A prop', MediaReferenceKind.image),
            _reference('Moth', MediaReferenceKind.image),
          ],
        ),
      );

      // Nine image slots: everything fits, the cast ahead of the prop.
      expect(controller.form.references.map((item) => item.promptName), [
        'Rooftop chase',
        'Sloth',
        'Moth',
        'A prop',
      ]);
      expect(controller.form.characterMappings, {
        'HERO': ['Sloth'],
        'RIVAL': ['Moth'],
      });
      expect(controller.notice, 'Ready to extend “Rooftop chase”.');
    },
  );

  test('references that no longer fit beside the film are dropped, cast or '
      'not', () async {
    final controller = _controller();
    addTearDown(controller.dispose);

    // Seedance 2.0 takes three reference videos; the extended film is one,
    // so of the three the film was made with only two come back — the cast
    // first, and the prop is what gives way. The cast list is untouched.
    await controller.extend(
      _film(
        title: 'Rooftop chase',
        prompt: 'A sloth climbs.\n\nHERO: @Sloth\nRIVAL: @Moth',
        references: <MediaReferenceLabel>[
          _reference('A prop', MediaReferenceKind.video, seconds: 4),
          _reference('Sloth', MediaReferenceKind.video, seconds: 4),
          _reference('Moth', MediaReferenceKind.video, seconds: 4),
        ],
      ),
    );

    expect(controller.form.references.map((item) => item.promptName), [
      'Rooftop chase',
      'Sloth',
      'Moth',
    ]);
    expect(controller.form.characterMappings, {
      'HERO': ['Sloth'],
      'RIVAL': ['Moth'],
    });
    expect(controller.notice, contains('1 reference left out'));
    expect(controller.notice, contains('Seedance 2.0'));
  });

  test('characters over the model limit are left out, and said so', () async {
    final controller = _controller();
    addTearDown(controller.dispose);

    await controller.extend(
      _film(
        title: 'Rooftop chase',
        prompt: 'A sloth climbs.\n\nHERO: @Sloth\nRIVAL: @Moth\nEXTRA: @Bat',
        references: <MediaReferenceLabel>[
          _reference('Sloth', MediaReferenceKind.video, seconds: 4),
          _reference('Moth', MediaReferenceKind.video, seconds: 4),
          _reference('Bat', MediaReferenceKind.video, seconds: 4),
        ],
      ),
    );

    // Seedance 2.0 takes three reference videos; the extended film is one.
    expect(controller.form.references.map((item) => item.promptName), [
      'Rooftop chase',
      'Sloth',
      'Moth',
    ]);
    expect(controller.form.characterMappings, {
      'HERO': ['Sloth'],
      'RIVAL': ['Moth'],
    });
    expect(controller.notice, contains('1 reference left out'));
    expect(controller.notice, contains('Seedance 2.0'));
  });

  test('extend never lands on top of a draft in progress', () async {
    final controller = _controller();
    addTearDown(controller.dispose);
    controller.updateForm((form) => form.prompt = 'Something else entirely.');

    await controller.extend(_film(title: 'Rooftop chase'));

    expect(controller.composerTabs, hasLength(2));
    expect(controller.form.prompt, 'Extend @Rooftop chase.');
    expect(
      controller.composerTabs.first.form.prompt,
      'Something else entirely.',
    );
    expect(controller.composerTabs.first.form.references, isEmpty);
  });

  test('an untitled film is named after its own direction', () async {
    final controller = _controller();
    addTearDown(controller.dispose);

    await controller.extend(_film(prompt: 'A sloth climbs.'));

    expect(controller.form.prompt, 'Extend @A sloth climbs.');
    expect(
      controller.referencePromptName(controller.form.references.single),
      'A sloth climbs',
    );
  });
}

MediaReferenceLabel _reference(
  String name,
  MediaReferenceKind kind, {
  double? seconds,
}) => MediaReferenceLabel(
  label: '$name.file',
  kind: kind,
  promptName: name,
  durationSeconds: seconds,
  source: AssetReference(
    kind: 'remote',
    value: 'https://example.invalid/$name',
    label: name,
  ),
);

Generation _film({
  String? title,
  String prompt = 'A sloth climbs the fire escape.',
  String status = 'Ready',
  bool delivered = true,
  bool screenplayMode = false,
  String provider = 'runway',
  String model = 'seedance2',
  GenerationOutputKind outputKind = GenerationOutputKind.video,
  String? aestheticReferenceId,
  String? aestheticText,
  List<MediaReferenceLabel> references = const <MediaReferenceLabel>[],
}) {
  final now = DateTime.utc(2026, 9, 1);
  return Generation(
    localId: 'film-1',
    status: status,
    prompt: prompt,
    title: title,
    mode: VideoMode.t2v,
    provider: provider,
    model: model,
    outputKind: outputKind,
    config: GenerationConfig(
      aspectRatio: '9:16',
      duration: 5,
      resolution: 'hd',
      generateAudio: true,
      safetyTolerance: 2,
      draft: false,
      screenplayMode: screenplayMode,
      references: references.isEmpty ? null : references,
    ),
    aestheticReferenceId: aestheticReferenceId,
    aestheticText: aestheticText,
    resultUrl: delivered ? 'https://example.invalid/film-1.mp4' : null,
    createdAt: now,
    updatedAt: now,
  );
}

AppController _controller() => AppController(gateway: _ExtendGateway())
  ..selectedProviderId = 'runway'
  ..selectedModelId = 'seedance2'
  ..loading = false
  ..snapshot = const LocalSnapshot(
    generations: [],
    preferences: AppPreferences(),
    hasApiKey: false,
    storage: StorageStats(path: 'memory', bytes: 0, records: 0),
  );

Future<void> _pumpMenu(
  WidgetTester tester,
  AppController controller,
  Generation item,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildClawnsoleTheme(Brightness.light),
      home: Scaffold(
        body: Center(
          child: GenerationActionsMenu(controller: controller, item: item),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _ExtendGateway implements AppGateway {
  @override
  bool get usesCompanion => false;

  @override
  bool get supportsPhotoLibrarySave => false;

  @override
  String get persistenceDescription => 'Memory';

  @override
  Future<LocalSnapshot> load() async => const LocalSnapshot(
    generations: [],
    preferences: AppPreferences(),
    hasApiKey: false,
    storage: StorageStats(path: 'memory', bytes: 0, records: 0),
  );

  @override
  Future<LocalSnapshot> setPreferences(AppPreferences preferences) async =>
      LocalSnapshot(
        generations: const [],
        preferences: preferences,
        hasApiKey: false,
        storage: const StorageStats(path: 'memory', bytes: 0, records: 0),
      );

  @override
  Future<Uint8List> readAsset(AssetReference reference) async => Uint8List(0);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
