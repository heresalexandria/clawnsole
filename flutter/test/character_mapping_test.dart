import 'dart:async';
import 'dart:typed_data';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/screenplay.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'arbitrary names can be cast before any script or speaking cue',
    () async {
      final controller = _controller(references: [_reference('portrait.png')]);
      addTearDown(controller.dispose);

      expect(
        await controller.saveCharacterMapping(
          scriptName: 'quiet observer',
          name: 'Quiet Observer',
          referenceNames: ['portrait.png'],
        ),
        isNull,
      );

      expect(controller.scriptCharacterNames, ['QUIET OBSERVER']);
      expect(controller.characterMappingReferences('quiet observer'), [
        'portrait.png',
      ]);
      expect(
        controller.form.references.single.savedReferenceId,
        'portrait.png',
      );
      expect(screenplayCharacters(controller.form.prompt), isEmpty);
      // The casting never enters the editable text; it is appended on the way
      // out, where it counts toward the prompt limit.
      expect(controller.form.prompt, isEmpty);
      expect(controller.promptWithCast, 'QUIET OBSERVER: @portrait.png');
    },
  );

  test(
    'a reference-free cast survives controls edited on a blank prompt',
    () async {
      final controller = _controller();
      addTearDown(controller.dispose);
      await controller.saveCharacterMapping(
        scriptName: 'EXTRA',
        name: 'EXTRA',
        referenceNames: [],
      );

      controller.updateForm((form) => form.aspectRatio = '9:16');

      expect(controller.form.prompt, isEmpty);
      expect(controller.scriptCharacterNames, ['EXTRA']);
      controller.updateForm(
        (form) => form.prompt = 'The extra watches silently.',
      );
      expect(controller.scriptCharacterNames, ['EXTRA']);
      controller.updateForm((form) => form.prompt = '');
      expect(controller.scriptCharacterNames, isEmpty);
    },
  );

  test('restored action mentions preview defaults without a typing event', () {
    final controller = _controller(
      references: [_reference('lead.mp4', character: 'ÉLODIE')],
    );
    addTearDown(controller.dispose);
    controller.form
      ..screenplayMode = true
      ..prompt = 'Élodie walks into the empty station.';

    expect(controller.scriptCharacterNames, ['ÉLODIE']);
    expect(controller.characterMappingReferences('Élodie'), ['lead.mp4']);
    expect(controller.form.references, isEmpty);
    expect(controller.form.prompt, 'Élodie walks into the empty station.');
  });

  test(
    'saved card names and recognized media extensions match whole names',
    () {
      final controller = _controller(
        references: [
          _reference('Alice Smith.PNG'),
          _reference('Bob'),
          _reference('Captain.v2'),
        ],
      );
      addTearDown(controller.dispose);
      controller.form
        ..screenplayMode = true
        ..prompt = 'Alice Smith follows BOB. Captain.v2 waits.';

      expect(controller.scriptCharacterNames, [
        'ALICE SMITH',
        'BOB',
        'CAPTAIN.V2',
      ]);
      expect(controller.characterMappingReferences('alice smith'), [
        'Alice Smith.PNG',
      ]);
      expect(controller.characterMappingReferences('BOB'), ['Bob']);
      expect(controller.characterMappingReferences('Captain'), isEmpty);
      expect(controller.characterMappingReferences('Captain.v2'), [
        'Captain.v2',
      ]);
    },
  );

  test(
    'an assigned character name takes precedence over the card filename',
    () {
      final controller = _controller(
        references: [_reference('Alice.png', character: 'HERO')],
      );
      addTearDown(controller.dispose);
      controller.form
        ..screenplayMode = true
        ..prompt = 'Alice follows the hero.';

      expect(controller.scriptCharacterNames, ['HERO']);
      expect(controller.characterMappingReferences('ALICE'), isEmpty);
      expect(controller.characterMappingReferences('HERO'), ['Alice.png']);
    },
  );

  test(
    'attached references match their current name and explicit assignment',
    () {
      final controller = _controller();
      addTearDown(controller.dispose);
      controller.form
        ..screenplayMode = true
        ..prompt = 'The Watcher follows the pilot.'
        ..references = const [
          MediaReferenceDraft(
            id: 'one',
            label: 'Watcher.jpg',
            promptName: 'Watcher.jpg',
            kind: MediaReferenceKind.image,
            source: 'https://example.com/watcher.jpg',
          ),
          MediaReferenceDraft(
            id: 'two',
            label: 'Person.png',
            promptName: 'Person.png',
            kind: MediaReferenceKind.image,
            source: 'https://example.com/person.png',
          ),
        ];
      controller.form.draftCharacterNames['two'] = 'PILOT';

      expect(controller.scriptCharacterNames, ['PILOT', 'WATCHER']);
      expect(controller.characterMappingReferences('WATCHER'), ['Watcher.jpg']);
      expect(controller.characterMappingReferences('PILOT'), ['Person.png']);
      expect(controller.characterMappingReferences('PERSON'), isEmpty);
    },
  );

  test(
    'hidden, audio, partial names, and reference tags do not infer cast',
    () {
      final controller = _controller(
        references: [
          _reference('Alex.png'),
          _reference('Secret.png', hidden: true),
          _reference('Narrator.mp3', kind: MediaReferenceKind.audio),
          _reference('Elodie.png'),
        ],
      );
      addTearDown(controller.dispose);
      controller.form
        ..screenplayMode = true
        ..prompt =
            'Alexandria sees SECRET and the NARRATOR beside @Alex.png. '
            'Élodie watches TV and VHS tapes.';

      expect(controller.scriptCharacterNames, isEmpty);
      expect(controller.characterMappingReferences('SECRET'), isEmpty);
      expect(controller.characterMappingReferences('NARRATOR'), isEmpty);
      expect(controller.characterMappingReferences('ÉLODIE'), isEmpty);
      expect(controller.characterMappingReferences('TV'), isEmpty);
    },
  );

  test(
    'case-insensitive action matching casts once, out of the text',
    () async {
      final controller = _controller(references: [_reference('Alice.png')]);
      addTearDown(controller.dispose);
      controller.setScreenplayMode(true);

      controller.updateForm((form) => form.prompt = 'Alice turns.');
      expect(controller.form.references, hasLength(1));
      expect(controller.form.prompt, 'Alice turns.');
      expect(controller.form.characterMappings, {
        'ALICE': ['Alice.png'],
      });
      expect(controller.promptWithCast, 'Alice turns.\n\nALICE: @Alice.png');
      // A pasted casting line remains authored text, separate from the cast.
      controller.updateForm(
        (form) => form.prompt = 'Alice turns.\n\nALICE: @other',
      );
      expect(controller.form.prompt, 'Alice turns.\n\nALICE: @other');
      controller.updateForm((form) => form.prompt += '\nAlice sits.');
      expect(controller.characterMappingReferences('ALICE'), ['Alice.png']);
      // Clearing the cast is done in the editor, and it sticks through typing.
      await controller.saveCharacterMapping(
        scriptName: 'ALICE',
        name: 'ALICE',
        referenceNames: [],
      );
      controller.updateForm((form) => form.prompt += '\nAlice waits.');
      expect(controller.characterMappingReferences('ALICE'), isEmpty);
      expect(controller.form.characterMappings, isEmpty);
    },
  );

  test(
    'an authored cast line does not acquire conflicting automatic casting',
    () {
      final controller = _controller(references: [_reference('Alice.png')]);
      addTearDown(controller.dispose);
      controller.form.screenplayMode = true;
      controller.updateForm(
        (form) => form.prompt = 'Alice turns.\n\nAlice: @custom',
      );

      expect(controller.form.prompt, 'Alice turns.\n\nAlice: @custom');
      expect(controller.form.characterMappings, isEmpty);
      expect(controller.characterReferenceText, isEmpty);
      controller.updateForm((form) => form.prompt += '\nAlice sits.');
      expect(controller.form.references, isEmpty);
      // Removing the authored override allows automatic casting again.
      controller.updateForm((form) => form.prompt = 'Alice turns.');
      expect(controller.characterMappingReferences('ALICE'), ['Alice.png']);
      expect(controller.form.references, hasLength(1));
    },
  );

  test(
    'explicit clearing and a different-reference override beat defaults',
    () async {
      final controller = _controller(
        references: [_reference('Alice.png'), _reference('Alternate.png')],
      );
      addTearDown(controller.dispose);
      controller.form
        ..screenplayMode = true
        ..prompt = 'Alice watches silently.';
      expect(controller.characterMappingReferences('ALICE'), ['Alice.png']);

      await controller.saveCharacterMapping(
        scriptName: 'ALICE',
        name: 'ALICE',
        referenceNames: ['Alternate.png'],
      );
      expect(controller.characterMappingReferences('ALICE'), ['Alternate.png']);
      expect(
        controller.form.references.map((draft) => draft.savedReferenceId),
        ['Alternate.png'],
      );
      await controller.saveCharacterMapping(
        scriptName: 'ALICE',
        name: 'ALICE',
        referenceNames: [],
      );
      controller.updateForm((form) => form.prompt += '\nAlice turns.');
      expect(controller.characterMappingReferences('ALICE'), isEmpty);
      expect(controller.form.characterMappings, isEmpty);
    },
  );

  test(
    'manually cleared defaults stay clear before any direction is written',
    () async {
      final controller = _controller(references: [_reference('Alice.png')]);
      addTearDown(controller.dispose);
      await controller.saveCharacterMapping(
        scriptName: 'ALICE',
        name: 'ALICE',
        referenceNames: [],
      );
      controller.updateForm((form) => form.aspectRatio = '9:16');
      controller.setScreenplayMode(true);
      controller.updateForm((form) => form.prompt = 'Alice turns.');

      expect(controller.characterMappingReferences('ALICE'), isEmpty);
      expect(controller.form.references, isEmpty);
      expect(controller.form.prompt, 'Alice turns.');
    },
  );

  test(
    'manual mapping hydration stays in the originating composer tab',
    () async {
      final gateway = _MemoryGateway([_reference('Alice.png', local: true)]);
      gateway.pendingAsset = Completer<Uint8List>();
      final controller = _controller(gateway: gateway);
      addTearDown(controller.dispose);
      final original = controller.activeComposerTab;
      final saving = controller.saveCharacterMapping(
        scriptName: 'OBSERVER',
        name: 'OBSERVER',
        referenceNames: ['Alice.png'],
      );
      await gateway.readStarted.future;
      final next = controller.addComposerTab();
      controller.updateForm((form) => form.prompt = 'A different scene.');
      gateway.pendingAsset!.complete(Uint8List.fromList([1, 2, 3]));

      expect(await saving, isNull);
      expect(controller.activeComposerTab, same(next));
      expect(controller.form.prompt, 'A different scene.');
      expect(controller.form.references, isEmpty);
      expect(original.form.characterMappings, {
        'OBSERVER': ['Alice.png'],
      });
      expect(original.form.references.single.asset!.bytes, [1, 2, 3]);
    },
  );

  test(
    'failed automatic hydration removes its footer from the correct tab',
    () async {
      final gateway = _MemoryGateway([_reference('Alice.png', local: true)]);
      gateway.pendingAsset = Completer<Uint8List>();
      final controller = _controller(gateway: gateway);
      addTearDown(controller.dispose);
      final original = controller.activeComposerTab;
      controller.setScreenplayMode(true);
      controller.updateForm((form) => form.prompt = 'Alice turns.');
      await gateway.readStarted.future;
      final next = controller.addComposerTab();
      controller.updateForm((form) => form.prompt = 'Another scene.');
      gateway.pendingAsset!.completeError(StateError('Unavailable'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.activeComposerTab, same(next));
      expect(controller.form.prompt, 'Another scene.');
      expect(controller.form.references, isEmpty);
      expect(original.form.references, isEmpty);
      expect(original.form.characterMappings, isEmpty);
      controller.activateComposerTab(original.id);
      expect(controller.characterMappingReferences('ALICE'), isEmpty);
    },
  );
  test('opening cast reconciles a restored action-only script once', () {
    final controller = _controller(references: [_reference('Alice.png')]);
    addTearDown(controller.dispose);
    controller.form
      ..screenplayMode = true
      ..prompt = 'Alice waits without speaking.';

    controller.syncScreenplayCharacterMappings();

    expect(controller.form.references.single.savedReferenceId, 'Alice.png');
    expect(controller.form.characterMappings, {
      'ALICE': ['Alice.png'],
    });
    expect(controller.form.prompt, 'Alice waits without speaking.');
    final prompt = controller.form.prompt;
    controller.syncScreenplayCharacterMappings();
    expect(controller.form.prompt, prompt);
    expect(controller.form.references, hasLength(1));
  });

  test(
    'an explicit rename updates mixed-case action names and keeps tags intact',
    () async {
      final controller = _controller(references: [_reference('Alice.png')]);
      addTearDown(controller.dispose);
      controller.form
        ..screenplayMode = true
        ..prompt = 'Alice greets ALICE and alice. ALICEA watches @Alice.png.';

      await controller.saveCharacterMapping(
        scriptName: 'ALICE',
        name: 'HERO',
        referenceNames: ['Alice.png'],
        renameInScript: true,
      );

      expect(
        controller.form.prompt,
        'HERO greets HERO and HERO. ALICEA watches @Alice.png.',
      );
      expect(controller.promptWithCast, endsWith('\n\nHERO: @Alice.png'));
      expect(controller.scriptCharacterNames, ['HERO']);
      expect(controller.characterMappingReferences('HERO'), ['Alice.png']);
    },
  );

  test(
    'character mappings reject an already attached audio reference',
    () async {
      final controller = _controller();
      addTearDown(controller.dispose);
      controller.form.references = const [
        MediaReferenceDraft(
          id: 'voice',
          label: 'Voice.mp3',
          promptName: 'Voice.mp3',
          kind: MediaReferenceKind.audio,
          source: 'https://example.com/voice.mp3',
        ),
      ];

      expect(
        await controller.saveCharacterMapping(
          scriptName: 'NARRATOR',
          name: 'NARRATOR',
          referenceNames: ['Voice.mp3'],
        ),
        isNotNull,
      );
      expect(controller.form.prompt, isEmpty);
      expect(controller.form.screenplayCharacterAliases, isEmpty);
    },
  );
}

SavedReference _reference(
  String name, {
  String? character,
  MediaReferenceKind kind = MediaReferenceKind.image,
  bool hidden = false,
  bool local = false,
}) => SavedReference(
  id: name,
  name: name,
  characterName: character,
  kind: kind,
  hidden: hidden,
  asset: AssetReference(
    kind: local ? 'local' : 'remote',
    value: local ? name : 'https://example.com/$name',
    label: name,
  ),
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

AppController _controller({
  List<SavedReference> references = const [],
  _MemoryGateway? gateway,
}) {
  final memory = gateway ?? _MemoryGateway(references);
  return AppController(gateway: memory)
    ..selectedProviderId = 'artcraft'
    ..selectedModelId = 'seedance_2p5'
    ..snapshot = memory.snapshot;
}

class _MemoryGateway implements AppGateway {
  _MemoryGateway(List<SavedReference> references)
    : snapshot = LocalSnapshot(
        generations: const [],
        preferences: const AppPreferences(),
        hasApiKey: false,
        storage: const StorageStats(path: 'memory', bytes: 0, records: 0),
        savedReferences: references,
      );

  LocalSnapshot snapshot;
  Completer<Uint8List>? pendingAsset;
  final readStarted = Completer<void>();

  @override
  bool get usesCompanion => false;

  @override
  bool get supportsPhotoLibrarySave => false;

  @override
  String get persistenceDescription => 'Memory';

  @override
  Future<LocalSnapshot> setPreferences(AppPreferences preferences) async {
    snapshot = snapshot.copyWith(preferences: preferences);
    return snapshot;
  }

  @override
  Future<Uint8List> readAsset(AssetReference reference) async {
    if (!readStarted.isCompleted) readStarted.complete();
    return pendingAsset?.future ?? Uint8List.fromList([1, 2, 3]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
