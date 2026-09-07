import 'dart:convert';
import 'dart:typed_data';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/core/create_defaults.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/ui/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/settings_tabs.dart';

void main() {
  group('the record', () {
    test('asking for nothing writes nothing but its version', () {
      expect(CreateDefaults.none.isEmpty, isTrue);
      expect(CreateDefaults.none.toJson(), <String, Object?>{
        'schemaVersion': CreateDefaults.schemaVersion,
      });
      expect(
        const AppPreferences().toJson().containsKey('createDefaults'),
        isFalse,
      );
    });

    test('every answer survives a round trip through the settings record', () {
      const defaults = CreateDefaults(
        screenplayMode: true,
        providerId: 'ltx',
        modelId: 'ltx-2-3-fast',
        aspectRatio: '9:16',
        resolution: 'fhd',
        duration: CreateDurationDefault.seconds(12),
        generateAudio: false,
        draft: true,
        aestheticReferenceId: 'warm-light',
      );
      const preferences = AppPreferences(createDefaults: defaults);

      final restored = AppPreferences.fromJson(
        jsonDecode(jsonEncode(preferences.toJson())) as Map<String, Object?>,
      );

      expect(restored.createDefaults, defaults);
      expect(restored.createDefaults.duration?.seconds, 12);
    });

    test('an Auto duration and a None aesthetic are their own answers', () {
      const defaults = CreateDefaults(
        duration: CreateDurationDefault.auto(),
        aestheticReferenceId: CreateDefaults.noAesthetic,
      );
      final json = defaults.toJson();

      expect(json['duration'], 'auto');
      expect(json['aestheticReferenceId'], '');
      final restored = CreateDefaults.tryFromJson(
        jsonDecode(jsonEncode(json)) as Map<String, Object?>,
      );
      expect(restored?.duration?.isAuto, isTrue);
      expect(restored?.aestheticReferenceId, CreateDefaults.noAesthetic);
      // "None" is not "Last used": the record is not empty.
      expect(restored?.isEmpty, isFalse);
    });

    test('a half-named model is no model at all', () {
      const half = CreateDefaults(providerId: 'ltx');
      expect(half.hasModel, isFalse);
      expect(half.toJson().containsKey('providerId'), isFalse);
      expect(
        CreateDefaults.tryFromJson(<String, Object?>{
          'schemaVersion': 1,
          'modelId': 'ltx-2-3-fast',
        })?.hasModel,
        isFalse,
      );
    });

    test('an unreadable or newer record leaves every field unset', () {
      expect(CreateDefaults.tryFromJson('nonsense'), isNull);
      expect(
        CreateDefaults.tryFromJson(<String, Object?>{'schemaVersion': 99}),
        isNull,
      );
      final partial = CreateDefaults.tryFromJson(<String, Object?>{
        'schemaVersion': 1,
        'screenplayMode': 'yes',
        'duration': -4,
        'aspectRatio': '   ',
      });
      expect(partial?.isEmpty, isTrue);
    });
  });

  group('opening a blank draft', () {
    test('a set format beats what the last draft was using', () async {
      final controller = await _controller();
      controller.setScreenplayMode(true);

      await controller.setCreateDefaults(
        const CreateDefaults(screenplayMode: false),
      );
      final next = controller.addComposerTab();

      expect(next.form.screenplayMode, isFalse);
      expect(next.isBlank, isTrue);

      await controller.setCreateDefaults(
        const CreateDefaults(screenplayMode: true),
      );
      controller.setScreenplayMode(false);
      expect(controller.addComposerTab().form.screenplayMode, isTrue);
    });

    test('a set model builds the tab on its own remembered controls', () async {
      final controller = await _controller();
      // Give the pro model controls of its own, then leave the draft on fast.
      await controller.selectProviderModel('ltx', 'ltx-2-3-pro');
      controller.updateForm((form) => form.durationSeconds = 6);
      await controller.selectProviderModel('ltx', 'ltx-2-3-fast');
      controller.updateForm((form) => form.durationSeconds = 18);

      await controller.setCreateDefaults(
        const CreateDefaults(providerId: 'ltx', modelId: 'ltx-2-3-pro'),
      );
      final next = controller.addComposerTab();

      expect(next.providerId, 'ltx');
      expect(next.modelId, 'ltx-2-3-pro');
      expect(next.form.durationSeconds, 6);
    });

    test('a model the catalog no longer has falls back to last used', () async {
      final controller = await _controller();
      await controller.selectProviderModel('ltx', 'ltx-2-3-fast');

      await controller.setCreateDefaults(
        const CreateDefaults(providerId: 'ltx', modelId: 'ltx-2-3-withdrawn'),
      );
      final withdrawnModel = controller.addComposerTab();
      expect(withdrawnModel.providerId, 'ltx');
      expect(withdrawnModel.modelId, 'ltx-2-3-fast');

      await controller.setCreateDefaults(
        const CreateDefaults(providerId: 'nobody', modelId: 'ltx-2-3-pro'),
      );
      final withdrawnProvider = controller.addComposerTab();
      expect(withdrawnProvider.providerId, 'ltx');
      expect(withdrawnProvider.modelId, 'ltx-2-3-fast');
    });

    test('the other controls override inheritance one by one', () async {
      final controller = await _controller();
      await controller.selectProviderModel('ltx', 'ltx-2-3-fast');
      controller.updateForm((form) {
        form
          ..aspectRatio = '16:9'
          ..resolution = 'hd'
          ..durationSeconds = 18;
      });
      controller.setGenerateAudio(true);

      await controller.setCreateDefaults(
        const CreateDefaults(
          aspectRatio: '9:16',
          duration: CreateDurationDefault.seconds(6),
          generateAudio: false,
        ),
      );
      final next = controller.addComposerTab();

      expect(next.form.aspectRatio, '9:16');
      expect(next.form.durationSeconds, 6);
      expect(next.form.generateAudio, isFalse);
      // Silence asked for here is as deliberate as reaching for the switch.
      expect(next.generateAudioExplicitlyDisabled, isTrue);
      // Untouched rows still inherit.
      expect(next.form.resolution, 'hd');
    });

    test('None clears the aesthetic while Last used inherits it', () async {
      final controller = await _controller();
      controller.selectAestheticReference('warm-light');

      expect(
        controller.addComposerTab().form.aestheticReferenceId,
        'warm-light',
      );

      await controller.setCreateDefaults(
        const CreateDefaults(aestheticReferenceId: CreateDefaults.noAesthetic),
      );
      expect(controller.addComposerTab().form.aestheticReferenceId, isNull);
    });

    test(
      'an aesthetic the library has lost starts the draft with none',
      () async {
        final controller = await _controller();
        controller.saveAestheticReference(
          title: 'Golden',
          text: 'Warm amber light.',
          icon: 'sun',
          color: 0xffaf853c,
        );
        final id = controller.aestheticReferences.single.id;
        await controller.setCreateDefaults(
          CreateDefaults(aestheticReferenceId: id),
        );
        expect(controller.addComposerTab().form.aestheticReferenceId, id);

        controller.deleteAestheticReference(id);
        expect(controller.addComposerTab().form.aestheticReferenceId, isNull);
      },
    );

    test('Reuse and Extend keep the film’s own settings', () async {
      final controller = await _controller();
      await controller.setCreateDefaults(
        const CreateDefaults(
          screenplayMode: true,
          providerId: 'ltx',
          modelId: 'ltx-2-3-pro',
          aspectRatio: '9:16',
        ),
      );
      // Occupy the open tab so Reuse has to open one of its own.
      controller.updateForm((form) => form.prompt = 'Work in progress.');

      await controller.reuse(_film());
      final reused = controller.activeComposerTab;

      expect(reused.providerId, 'ltx');
      expect(reused.modelId, 'ltx-2-3-fast');
      expect(reused.form.aspectRatio, '16:9');
      expect(reused.form.screenplayMode, isFalse);
      expect(reused.form.prompt, 'A film already made.');
    });

    test('Reset puts every row back on Last used', () async {
      final controller = await _controller();
      await controller.setCreateDefaults(
        const CreateDefaults(screenplayMode: true, aspectRatio: '9:16'),
      );
      expect(controller.createDefaults.isEmpty, isFalse);

      await controller.setCreateDefaults(CreateDefaults.none);

      expect(controller.createDefaults.isEmpty, isTrue);
      controller.setScreenplayMode(false);
      expect(controller.addComposerTab().form.screenplayMode, isFalse);
    });
  });

  testWidgets('the Defaults desk opens on Last used and persists a change', (
    tester,
  ) async {
    final gateway = _DefaultsGateway();
    final controller = AppController(gateway: gateway);
    await controller.initialize();
    await tester.binding.setSurfaceSize(const Size(1000, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildClawnsoleTheme(Brightness.light),
        home: Scaffold(body: SettingsScreen(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    await openSettingsTab(tester, SettingsTab.defaults);

    // Every row is present, and every row reads Last used.
    for (final key in <String>[
      'create-default-format',
      'create-default-model',
      'create-default-aspect-ratio',
      'create-default-resolution',
      'create-default-duration',
      'create-default-audio',
      'create-default-draft',
      'create-default-aesthetic',
    ]) {
      expect(
        find.byKey(ValueKey<String>(key)),
        findsOneWidget,
        reason: 'the $key row',
      );
    }
    expect(find.text('Last used'), findsWidgets);
    // Nothing to reset until something is asked for.
    expect(find.byKey(const ValueKey('create-defaults-reset')), findsNothing);

    // At desk width the three segments must stay whole inside the control
    // column: the control scales down rather than clipping "Screenplay".
    final screenplay = find.text('Screenplay');
    final format = find.byKey(const ValueKey('create-default-format'));
    expect(tester.getRect(format).right, lessThanOrEqualTo(1000));
    expect(tester.getRect(screenplay).right, lessThanOrEqualTo(1000));
    expect(
      tester.getRect(screenplay).right,
      lessThanOrEqualTo(tester.getRect(format).right + .5),
    );
    await tester.tap(screenplay);
    await tester.pumpAndSettle();

    expect(controller.createDefaults.screenplayMode, isTrue);
    expect(gateway.saved.last.createDefaults.screenplayMode, isTrue);
    expect(controller.addComposerTab().form.screenplayMode, isTrue);

    final reset = find.byKey(const ValueKey('create-defaults-reset'));
    expect(reset, findsOneWidget);
    await tester.ensureVisible(reset);
    await tester.tap(reset);
    await tester.pumpAndSettle();

    expect(controller.createDefaults.isEmpty, isTrue);
    expect(gateway.saved.last.createDefaults.isEmpty, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}

Future<AppController> _controller() async {
  final controller = AppController(gateway: _DefaultsGateway());
  addTearDown(controller.dispose);
  await controller.initialize();
  await Future<void>.delayed(const Duration(milliseconds: 30));
  return controller;
}

Generation _film() => Generation(
  localId: 'film-a',
  provider: 'ltx',
  model: 'ltx-2-3-fast',
  prompt: 'A film already made.',
  status: 'Ready',
  mode: VideoMode.t2v,
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 1),
  config: const GenerationConfig(
    aspectRatio: '16:9',
    duration: 8,
    resolution: 'hd',
    generateAudio: true,
    safetyTolerance: 2,
    draft: false,
  ),
);

class _DefaultsGateway implements AppGateway {
  LocalSnapshot snapshot = const LocalSnapshot(
    generations: <Generation>[],
    preferences: AppPreferences(),
    hasApiKey: false,
    storage: StorageStats(path: 'memory', bytes: 0, records: 0),
  );
  final List<AppPreferences> saved = <AppPreferences>[];

  @override
  bool get usesCompanion => false;

  @override
  bool get supportsPhotoLibrarySave => false;

  @override
  String get persistenceDescription => 'Memory';

  @override
  Future<LocalSnapshot> load() async => snapshot;

  @override
  Future<LocalSnapshot> setPreferences(AppPreferences preferences) async {
    // Round-trip through JSON so a default that cannot survive the settings
    // record fails here rather than in the field.
    final stored = AppPreferences.fromJson(
      jsonDecode(jsonEncode(preferences.toJson())) as Map<String, Object?>,
    );
    saved.add(stored);
    snapshot = snapshot.copyWith(preferences: stored);
    return snapshot;
  }

  @override
  Future<double> getCredits() async => 1000;

  @override
  Future<Generation> poll(Generation generation) async => generation;

  @override
  Future<Uint8List> readAsset(AssetReference reference) async => Uint8List(0);

  @override
  Uri mediaUri(String source) => Uri.parse(source);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
