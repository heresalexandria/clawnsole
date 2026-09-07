import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/core/composer_tabs.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/generation_preferences.dart';
import 'package:clawnsole/core/google_drive.dart';
import 'package:clawnsole/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'a blank tab inherits settings and leaves creative inputs behind',
    () async {
      final controller = await _controller();
      final source = controller.activeComposerTab;
      controller.updateForm((form) {
        form
          ..aspectRatio = '9:16'
          ..durationSeconds = 17
          ..resolution = 'fhd'
          ..safetyTolerance = 3;
      });
      controller.setGenerateAudio(false);
      // Populate all creative state independently of mode reconciliation. None
      // of it belongs to the next blank production recipe.
      source.form
        ..prompt = 'A private story.'
        ..screenplayMode = true
        ..aestheticReferenceId = 'warm-light'
        ..seed = 4321
        ..videoUrl = 'https://example.com/source.mp4'
        ..videoSavedReferenceId = 'source-reference'
        ..videoThumbnailBytes = Uint8List.fromList([1, 2])
        ..draftUrl = 'https://example.com/draft.mp4'
        ..references = [
          const MediaReferenceDraft(
            id: 'hero',
            label: 'Hero',
            kind: MediaReferenceKind.image,
            source: 'https://example.com/hero.png',
          ),
        ]
        ..keyframes = [
          const KeyframeDraft(
            id: 'start',
            label: 'Start',
            role: KeyframeRole.start,
            source: 'https://example.com/start.png',
            seconds: 0,
          ),
        ];
      source.form.screenplayLinkedCharacters.add('HERO');
      source.form.screenplayCharacterAliases['HERO'] = 'LEAD';
      source.form.draftCharacterNames['hero'] = 'HERO';
      source
        ..title = 'Opening'
        ..sourceGenerationId = 'previous-film'
        ..rewriteSummary = 'A slower entrance.';

      final next = controller.addComposerTab();

      expect(next.providerId, source.providerId);
      expect(next.modelId, source.modelId);
      _expectSettings(
        next.form,
        ratio: '9:16',
        seconds: 17,
        resolution: 'fhd',
        audio: false,
      );
      expect(next.form.safetyTolerance, 3);
      // The format and the aesthetic are the film's, not the model's: they
      // follow the director into the next draft.
      expect(next.form.screenplayMode, isTrue);
      expect(next.form.aestheticReferenceId, 'warm-light');
      _expectBlank(next);
      expect(source.form.prompt, 'A private story.');
      expect(source.form.references, hasLength(1));
      expect(source.form.keyframes, hasLength(1));
      expect(source.form.seed, 4321);
      expect(source.title, 'Opening');
    },
  );

  test(
    'background tabs inherit without moving or mutating the active tab',
    () async {
      final controller = await _controller();
      controller.updateForm((form) {
        form
          ..prompt = 'Keep working here.'
          ..aspectRatio = '1:1'
          ..durationSeconds = 12;
      });
      final original = controller.activeComposerTab;
      final next = controller.addComposerTab(activate: false);

      expect(controller.activeComposerTab, same(original));
      expect(controller.form.prompt, 'Keep working here.');
      expect(next.form.aspectRatio, '1:1');
      expect(next.form.durationSeconds, 12);
      _expectBlank(next);
    },
  );

  test(
    'closing the only tab preserves its last-used settings in its replacement',
    () async {
      final controller = await _controller();
      controller.updateForm((form) {
        form
          ..prompt = 'Closing this story.'
          ..aspectRatio = '21:9'
          ..autoDuration = true
          ..durationSeconds = 14
          ..draft = true;
      });
      controller.setGenerateAudio(false);
      final previousId = controller.activeComposerTabId;

      controller.closeComposerTab(previousId);

      expect(controller.activeComposerTabId, isNot(previousId));
      expect(controller.form.aspectRatio, '21:9');
      expect(controller.form.autoDuration, isTrue);
      expect(controller.form.durationSeconds, 14);
      expect(controller.form.draft, isTrue);
      expect(controller.form.generateAudio, isFalse);
      _expectBlank(controller.activeComposerTab);
    },
  );

  test('a new draft opens in the format the last one used', () async {
    final controller = await _controller();
    controller.setScreenplayMode(true);
    controller.selectAestheticReference('warm-light');

    final screenplay = controller.addComposerTab();
    expect(screenplay.form.screenplayMode, isTrue);
    expect(screenplay.form.aestheticReferenceId, 'warm-light');
    expect(screenplay.form.prompt, isEmpty);

    // Nothing has been directed in the new tab yet, so Reuse, Extend and
    // Enhance may still fill it in place rather than opening another.
    expect(screenplay.isBlank, isTrue);

    controller.setScreenplayMode(false);
    controller.selectAestheticReference(null);
    final plaintext = controller.addComposerTab();
    expect(plaintext.form.screenplayMode, isFalse);
    expect(plaintext.form.aestheticReferenceId, isNull);
    expect(plaintext.isBlank, isTrue);
  });

  test('the replacement for the last closed tab keeps its format', () async {
    final controller = await _controller();
    controller.setScreenplayMode(true);
    controller.selectAestheticReference('warm-light');

    controller.closeComposerTab(controller.activeComposerTabId);

    expect(controller.form.screenplayMode, isTrue);
    expect(controller.form.aestheticReferenceId, 'warm-light');
    expect(controller.activeComposerTab.isBlank, isTrue);
  });

  test(
    'switching model inside a draft leaves the format and aesthetic alone',
    () async {
      final controller = await _controller();
      await controller.selectProviderModel('ltx', 'ltx-2-3-fast');
      controller.updateForm((form) => form.durationSeconds = 18);
      controller.setScreenplayMode(true);
      controller.selectAestheticReference('warm-light');

      // The per-model record still restores its own controls, and carries no
      // opinion at all about the format.
      await controller.selectModel('ltx-2-3-pro');
      controller.updateForm((form) => form.durationSeconds = 6);
      expect(controller.form.screenplayMode, isTrue);
      expect(controller.form.aestheticReferenceId, 'warm-light');

      await controller.selectModel('ltx-2-3-fast');
      expect(controller.form.durationSeconds, 18);
      expect(controller.form.screenplayMode, isTrue);
      expect(controller.form.aestheticReferenceId, 'warm-light');

      // A new draft on the pro model still gets the pro model's controls.
      final next = controller.addComposerTab();
      expect(next.form.screenplayMode, isTrue);
      await controller.selectModel('ltx-2-3-pro');
      expect(controller.form.durationSeconds, 6);
      expect(controller.form.screenplayMode, isTrue);
      expect(next.form.prompt, isEmpty);
    },
  );

  test(
    'each model of a provider remembers its own generation settings',
    () async {
      final controller = await _controller();
      await controller.selectProviderModel('ltx', 'ltx-2-3-fast');
      controller.updateForm((form) {
        form
          ..prompt = 'The same draft survives model changes.'
          ..aspectRatio = '9:16'
          ..durationSeconds = 18
          ..resolution = 'fhd';
      });
      controller.setGenerateAudio(false);

      await controller.selectModel('ltx-2-3-pro');
      controller.updateForm((form) {
        form
          ..aspectRatio = '16:9'
          ..durationSeconds = 6
          ..resolution = 'hd';
      });
      controller.setGenerateAudio(true);
      await controller.selectModel('ltx-2-3-fast');
      _expectSettings(
        controller.form,
        ratio: '9:16',
        seconds: 18,
        resolution: 'fhd',
        audio: false,
      );
      expect(controller.form.prompt, 'The same draft survives model changes.');
      await controller.selectModel('ltx-2-3-pro');
      _expectSettings(
        controller.form,
        ratio: '16:9',
        seconds: 6,
        resolution: 'hd',
        audio: true,
      );
    },
  );

  test(
    'provider switches restore independent audio and automatic duration choices',
    () async {
      final controller = await _controller();
      controller.updateForm((form) {
        form
          ..aspectRatio = '21:9'
          ..durationSeconds = 19
          ..autoDuration = true
          ..resolution = 'fhd';
      });
      controller.setGenerateAudio(false);
      await controller.selectProvider('ltx');
      controller.updateForm((form) {
        form
          ..aspectRatio = '9:16'
          ..durationSeconds = 6
          ..resolution = 'hd';
      });
      controller.setGenerateAudio(true);
      await controller.selectProvider('bfl');

      _expectSettings(
        controller.form,
        ratio: '21:9',
        seconds: 19,
        resolution: 'fhd',
        audio: false,
      );
      expect(controller.form.autoDuration, isTrue);
      await controller.selectProvider('ltx');
      _expectSettings(
        controller.form,
        ratio: '9:16',
        seconds: 6,
        resolution: 'hd',
        audio: true,
      );
      expect(controller.form.autoDuration, isFalse);
    },
  );

  test(
    'opening or typing in an older tab cannot replace newer defaults',
    () async {
      final controller = await _controller();
      controller.updateForm((form) {
        form
          ..aspectRatio = '9:16'
          ..durationSeconds = 10;
      });
      controller.setGenerateAudio(false);
      final older = controller.activeComposerTab;
      final newer = controller.addComposerTab();
      controller.updateForm((form) {
        form
          ..aspectRatio = '1:1'
          ..durationSeconds = 18;
      });
      controller.setGenerateAudio(true);

      controller.activateComposerTab(older.id);
      controller.updateForm((form) => form.prompt = 'Only this story changed.');
      final fresh = controller.addComposerTab();

      _expectSettings(
        fresh.form,
        ratio: '1:1',
        seconds: 18,
        resolution: 'hd',
        audio: true,
      );
      _expectSettings(
        older.form,
        ratio: '9:16',
        seconds: 10,
        resolution: 'hd',
        audio: false,
      );
      expect(older.form.prompt, 'Only this story changed.');
      expect(newer.form.durationSeconds, 18);
    },
  );

  test(
    'editing a generation knob in an older tab deliberately updates the default',
    () async {
      final controller = await _controller();
      controller.updateForm((form) => form.durationSeconds = 10);
      final older = controller.activeComposerTab;
      controller.addComposerTab();
      controller.updateForm((form) => form.durationSeconds = 18);
      controller.activateComposerTab(older.id);
      controller.updateForm((form) => form.durationSeconds = 13);

      expect(controller.addComposerTab().form.durationSeconds, 13);
    },
  );

  test(
    'upscaler finishing settings carry over without carrying source media',
    () async {
      final controller = await _controller();
      await controller.selectModel('flux-tools-video-upscale-v1');
      controller.updateForm((form) {
        form
          ..videoUrl = 'https://example.com/source.mp4'
          ..upscaleFactor = 3
          ..upscaleCreativity = 0
          ..safetyTolerance = 1;
      });

      final next = controller.addComposerTab();

      expect(next.form.upscale, isTrue);
      expect(next.form.mode, VideoMode.upscale);
      expect(next.form.upscaleFactor, 3);
      expect(next.form.upscaleCreativity, 0);
      expect(next.form.safetyTolerance, 1);
      expect(next.form.generateAudio, isFalse);
      _expectBlank(next);
    },
  );

  test(
    'settings survive JSON persistence and restart without saved composer tabs',
    () async {
      final gateway = _PreferencesGateway();
      final controller = await _controller(gateway: gateway);
      controller.updateForm((form) {
        form
          ..prompt = 'Private story, never a default.'
          ..aspectRatio = '9:16'
          ..durationSeconds = 17
          ..resolution = 'fhd';
      });
      controller.setGenerateAudio(false);
      await controller.selectProvider('ltx');
      controller.updateForm((form) {
        form
          ..aspectRatio = '16:9'
          ..durationSeconds = 6
          ..resolution = 'qhd';
      });
      controller.addComposerTab();
      await _settle();

      final restarted = await _controller(
        gateway: _PreferencesGateway(snapshot: gateway.snapshot),
      );
      await restarted.selectProvider('bfl');
      _expectSettings(
        restarted.form,
        ratio: '9:16',
        seconds: 17,
        resolution: 'fhd',
        audio: false,
      );
      _expectBlank(restarted.activeComposerTab);
      await restarted.selectProvider('ltx');
      expect(restarted.form.aspectRatio, '16:9');
      expect(restarted.form.durationSeconds, 6);
      expect(restarted.form.resolution, 'qhd');
    },
  );

  test(
    'legacy tabs seed the most recently edited model settings without changing old drafts',
    () async {
      final gateway = _TabsGateway(
        stored: ComposerTabsState(
          activeTabId: 'older',
          tabs: [
            ComposerTabRecord(
              id: 'older',
              providerId: 'bfl',
              modelId: 'flux-3-video',
              prompt: 'First story.',
              aspectRatio: '9:16',
              durationSeconds: 10,
              updatedAt: DateTime.utc(2026, 9, 1),
            ),
            ComposerTabRecord(
              id: 'newer',
              providerId: 'bfl',
              modelId: 'flux-3-video',
              prompt: 'Second story.',
              aspectRatio: '1:1',
              durationSeconds: 18,
              resolution: 'fhd',
              generateAudio: false,
              updatedAt: DateTime.utc(2026, 9, 2),
            ),
          ],
        ),
      );
      final controller = await _controller(gateway: gateway);
      expect(controller.form.prompt, 'First story.');
      expect(controller.form.durationSeconds, 10);

      final fresh = controller.addComposerTab();

      _expectSettings(
        fresh.form,
        ratio: '1:1',
        seconds: 18,
        resolution: 'fhd',
        audio: false,
      );
      _expectBlank(fresh);
      expect(controller.composerTabs.first.form.prompt, 'First story.');
      expect(controller.composerTabs.first.form.durationSeconds, 10);
    },
  );

  test(
    'legacy history seeds each actual model rather than the startup selection',
    () async {
      final gateway = _PreferencesGateway();
      gateway.snapshot = gateway.snapshot.copyWith(
        generations: [
          _historyGeneration(
            'latest-ltx',
            provider: 'ltx',
            model: 'ltx-2-3-fast',
            seconds: 6,
            ratio: '9:16',
            at: DateTime.utc(2026, 9, 5),
          ),
          _historyGeneration(
            'previous-bfl',
            provider: 'bfl',
            model: 'flux-3-video',
            seconds: 17,
            ratio: '21:9',
            at: DateTime.utc(2026, 9, 4),
          ),
        ],
      );
      final controller = await _controller(gateway: gateway);

      final blank = controller.addComposerTab();
      expect(blank.providerId, 'bfl');
      expect(blank.form.durationSeconds, 17);
      expect(blank.form.aspectRatio, '21:9');
      _expectBlank(blank);
      await controller.selectProviderModel('ltx', 'ltx-2-3-fast');
      expect(controller.form.durationSeconds, 6);
      expect(controller.form.aspectRatio, '9:16');
      _expectBlank(controller.activeComposerTab);
    },
  );

  test(
    'slider edits coalesce durable writes and prompt edits do not write defaults',
    () async {
      final gateway = _PreferencesGateway();
      final controller = await _controller(gateway: gateway);
      controller.updateForm((form) => form.durationSeconds = 10);
      controller.updateForm((form) => form.durationSeconds = 12);
      controller.updateForm((form) => form.durationSeconds = 14);
      expect(gateway.preferenceWrites, 0);

      await Future<void>.delayed(
        AppController.composerTabsSaveDebounce +
            const Duration(milliseconds: 50),
      );
      expect(gateway.preferenceWrites, 1);
      expect(
        gateway
            .snapshot
            .preferences
            .generationPreferences[generationPreferenceKey(
              'bfl',
              'flux-3-video',
            )]
            ?.durationSeconds,
        14,
      );
      controller.updateForm((form) => form.prompt = 'Only a story edit.');
      await Future<void>.delayed(
        AppController.composerTabsSaveDebounce +
            const Duration(milliseconds: 50),
      );
      expect(gateway.preferenceWrites, 1);
    },
  );

  test(
    'untouched legacy blank tabs do not replace actual draft settings',
    () async {
      final gateway = _TabsGateway(
        stored: ComposerTabsState(
          activeTabId: 'untouched',
          tabs: [
            ComposerTabRecord(
              id: 'actual-draft',
              prompt: 'The last real shot.',
              durationSeconds: 17,
              updatedAt: DateTime.utc(2026, 9, 4),
            ),
            ComposerTabRecord(
              id: 'untouched',
              updatedAt: DateTime.utc(2026, 9, 5),
            ),
          ],
        ),
      );
      final controller = await _controller(gateway: gateway);

      expect(controller.form.durationSeconds, 8);
      expect(controller.addComposerTab().form.durationSeconds, 17);
      expect(controller.composerTabs.first.form.prompt, 'The last real shot.');
    },
  );

  test(
    'untouched legacy blank tabs do not replace actual generation settings',
    () async {
      final gateway = _TabsGateway(
        stored: ComposerTabsState(
          activeTabId: 'untouched',
          tabs: [
            ComposerTabRecord(
              id: 'untouched',
              updatedAt: DateTime.utc(2026, 9, 5),
            ),
          ],
        ),
      );
      gateway.snapshot = gateway.snapshot.copyWith(
        generations: [
          _historyGeneration(
            'actual-generation',
            provider: 'bfl',
            model: 'flux-3-video',
            seconds: 17,
            ratio: '21:9',
            at: DateTime.utc(2026, 9, 4),
          ),
        ],
      );
      final controller = await _controller(gateway: gateway);

      final blank = controller.addComposerTab();
      expect(blank.form.durationSeconds, 17);
      expect(blank.form.aspectRatio, '21:9');
      _expectBlank(blank);
    },
  );

  for (final detail in [0, 1]) {
    test(
      'target-resolution upscaler remembers $detail percent creative detail',
      () async {
        final controller = await _controller();
        await controller.selectProviderModel(
          'runway',
          'magnific_video_upscaler_creative',
        );
        expect(controller.form.upscaleCreativity, 50);
        controller.updateForm((form) {
          form
            ..upscaleCreativity = detail
            ..resolution = '4k'
            ..videoUrl = 'https://example.com/source.mp4';
        });

        final blank = controller.addComposerTab();
        expect(blank.form.upscaleCreativity, detail);
        expect(blank.form.resolution, '4k');
        _expectBlank(blank);
        await controller.selectModel('seedance2_5');
        await controller.selectModel('magnific_video_upscaler_creative');
        expect(controller.form.upscaleCreativity, detail);
        expect(controller.form.resolution, '4k');
        _expectBlank(controller.activeComposerTab);
      },
    );
  }

  test(
    'startup migration yields to remote preferences without writing local defaults',
    () async {
      final gateway = _DrivePreferencesGateway(
        stored: const ComposerTabsState(
          activeTabId: 'legacy-draft',
          tabs: [
            ComposerTabRecord(
              id: 'legacy-draft',
              prompt: 'Existing story.',
              durationSeconds: 10,
            ),
          ],
        ),
      );
      gateway.resumeGate = Completer<LocalSnapshot?>();
      final controller = await _controller(gateway: gateway);
      await gateway.resumeStarted.future;
      await Future<void>.delayed(
        AppController.composerTabsSaveDebounce +
            const Duration(milliseconds: 50),
      );
      expect(gateway.preferenceWrites, 0);

      gateway.resumeGate!.complete(_withBflDuration(gateway.snapshot, 19));
      await _settle();

      expect(controller.googleDriveBusy, isFalse);
      expect(controller.composerTabs.first.form.durationSeconds, 10);
      expect(controller.composerTabs.first.form.prompt, 'Existing story.');
      expect(controller.addComposerTab().form.durationSeconds, 19);
    },
  );

  test(
    'a knob edited while manual Drive refresh waits beats the older remote value',
    () async {
      final gateway = _DrivePreferencesGateway();
      final controller = await _controller(gateway: gateway);
      gateway.refreshGate = Completer<LocalSnapshot>();
      final refresh = controller.refreshGoogleDrive();
      await gateway.refreshStarted.future;
      controller.updateForm((form) => form.durationSeconds = 14);

      gateway.refreshGate!.complete(_withBflDuration(gateway.snapshot, 6));
      await refresh;

      expect(controller.form.durationSeconds, 14);
      expect(controller.addComposerTab().form.durationSeconds, 14);
      await _settle();
      expect(
        gateway
            .snapshot
            .preferences
            .generationPreferences[generationPreferenceKey(
              'bfl',
              'flux-3-video',
            )]
            ?.durationSeconds,
        14,
      );
    },
  );

  test(
    'restored settings are constrained by the selected model capabilities',
    () async {
      final gateway = _PreferencesGateway();
      gateway.snapshot = gateway.snapshot.copyWith(
        preferences: AppPreferences(
          generationPreferences: {
            generationPreferenceKey(
              'ltx',
              'ltx-2-3-pro',
            ): const GenerationPreferences(
              aspectRatio: 'unsupported-ratio',
              resolution: 'retired-resolution',
              durationSeconds: 1000,
              autoDuration: true,
              generateAudio: false,
              draft: true,
              exactTiming: true,
            ),
            generationPreferenceKey('bfl', 'flux-tools-video-upscale-v1'):
                const GenerationPreferences(generateAudio: true),
          },
        ),
      );
      final controller = await _controller(gateway: gateway);
      await controller.selectProviderModel('ltx', 'ltx-2-3-pro');

      _expectSettings(
        controller.form,
        ratio: '16:9',
        seconds: 10,
        resolution: 'hd',
        audio: false,
      );
      expect(controller.form.autoDuration, isFalse);
      expect(controller.form.draft, isFalse);
      expect(controller.form.exactTiming, isFalse);
      final fresh = controller.addComposerTab();
      expect(fresh.form.durationSeconds, 10);
      expect(fresh.form.autoDuration, isFalse);
      await controller.selectProviderModel(
        'bfl',
        'flux-tools-video-upscale-v1',
      );
      expect(controller.form.generateAudio, isFalse);
      expect(controller.form.aspectRatio, 'auto');
      expect(controller.form.resolution, 'source');
    },
  );

  test(
    'saved preferences outrank legacy tabs without changing the restored drafts',
    () async {
      final gateway = _TabsGateway(
        stored: ComposerTabsState(
          activeTabId: 'existing',
          tabs: [
            ComposerTabRecord(
              id: 'existing',
              prompt: 'An existing story.',
              durationSeconds: 18,
              updatedAt: DateTime.utc(2026, 9, 5),
            ),
          ],
        ),
      );
      gateway.snapshot = gateway.snapshot.copyWith(
        preferences: AppPreferences(
          generationPreferences: {
            generationPreferenceKey('bfl', 'flux-3-video'):
                const GenerationPreferences(durationSeconds: 7),
          },
        ),
      );
      final controller = await _controller(gateway: gateway);
      expect(controller.form.durationSeconds, 18);
      expect(controller.form.prompt, 'An existing story.');

      expect(controller.addComposerTab().form.durationSeconds, 7);
      expect(controller.composerTabs.first.form.durationSeconds, 18);
    },
  );

  test(
    'switching away from an older model draft keeps its newer defaults',
    () async {
      final controller = await _controller();
      controller.updateForm((form) => form.durationSeconds = 10);
      final older = controller.activeComposerTab;
      controller.addComposerTab();
      controller.updateForm((form) => form.durationSeconds = 18);
      controller.activateComposerTab(older.id);

      await controller.selectProvider('ltx');
      await controller.selectProvider('bfl');

      expect(controller.form.durationSeconds, 18);
      expect(controller.addComposerTab().form.durationSeconds, 18);
    },
  );

  test(
    'selecting the current model does not reset an older draft to newer defaults',
    () async {
      final controller = await _controller();
      controller.updateForm((form) => form.durationSeconds = 10);
      final older = controller.activeComposerTab;
      controller.addComposerTab();
      controller.updateForm((form) => form.durationSeconds = 18);
      controller.activateComposerTab(older.id);

      await controller.selectModel('flux-3-video');
      expect(controller.form.durationSeconds, 10);
      await controller.selectProviderModel('bfl', 'flux-3-video');
      expect(controller.form.durationSeconds, 10);
      await controller.selectProvider('bfl');
      expect(controller.form.durationSeconds, 10);
      expect(controller.addComposerTab().form.durationSeconds, 18);
    },
  );

  test(
    'Generate captures preferences before preflight and never overwrites later edits',
    () async {
      final gateway = _PreferencesGateway();
      final controller = await _controller(gateway: gateway);
      controller.updateForm((form) {
        form
          ..prompt = 'The submitted take.'
          ..durationSeconds = 10;
      });
      final source = controller.activeComposerTab;
      controller.addComposerTab();
      controller.updateForm((form) => form.durationSeconds = 18);
      controller.activateComposerTab(source.id);
      gateway.snapshot = gateway.snapshot.copyWith(hasApiKey: true);
      controller.snapshot = gateway.snapshot;
      gateway.creditGate = Completer<double>();

      final operation = controller.submit(
        providerRetentionRiskAcknowledged: true,
      );
      await gateway.creditStarted.future;
      expect(controller.addComposerTab().form.durationSeconds, 10);
      controller.updateForm((form) {
        form
          ..prompt = 'Next story.'
          ..durationSeconds = 14;
      });
      gateway.creditGate!.complete(1000);
      await operation;

      expect(gateway.submissions, hasLength(1));
      expect(gateway.submissions.single.record.prompt, 'The submitted take.');
      expect(gateway.submissions.single.record.config.duration, 10);
      expect(controller.form.prompt, 'Next story.');
      expect(controller.addComposerTab().form.durationSeconds, 14);
    },
  );
}

void _expectSettings(
  GenerationFormState form, {
  required String ratio,
  required int seconds,
  required String resolution,
  required bool audio,
}) {
  expect(form.aspectRatio, ratio);
  expect(form.durationSeconds, seconds);
  expect(form.resolution, resolution);
  expect(form.generateAudio, audio);
}

/// No direction and nothing attached. The format and the chosen aesthetic are
/// deliberately absent: they inherit from the draft the tab was opened from.
void _expectBlank(ComposerTab tab) {
  expect(tab.form.prompt, isEmpty);
  expect(tab.form.screenplayLinkedCharacters, isEmpty);
  expect(tab.form.screenplayCharacterAliases, isEmpty);
  expect(tab.form.draftCharacterNames, isEmpty);
  expect(tab.form.references, isEmpty);
  expect(tab.form.keyframes, isEmpty);
  expect(tab.form.seed, isNull);
  expect(tab.form.videoUrl, isEmpty);
  expect(tab.form.videoAsset, isNull);
  expect(tab.form.videoSavedReferenceId, isNull);
  expect(tab.form.videoThumbnailBytes, isNull);
  expect(tab.form.videoMetadata, isNull);
  expect(tab.form.draftUrl, isEmpty);
  expect(tab.form.draftAsset, isNull);
  expect(tab.title, isNull);
  expect(tab.sourceGenerationId, isNull);
  expect(tab.rewriteSummary, isNull);
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 30));

Generation _historyGeneration(
  String id, {
  required String provider,
  required String model,
  required int seconds,
  required String ratio,
  required DateTime at,
}) => Generation(
  localId: id,
  provider: provider,
  model: model,
  status: 'Ready',
  prompt: 'A previous story for $id.',
  mode: VideoMode.t2v,
  config: GenerationConfig(
    aspectRatio: ratio,
    duration: seconds,
    resolution: 'hd',
    generateAudio: true,
    safetyTolerance: 2,
    draft: false,
  ),
  createdAt: at,
  updatedAt: at,
);

LocalSnapshot _withBflDuration(LocalSnapshot snapshot, int seconds) =>
    snapshot.copyWith(
      preferences: AppPreferences(
        generationPreferences: {
          generationPreferenceKey('bfl', 'flux-3-video'): GenerationPreferences(
            durationSeconds: seconds,
          ),
        },
      ),
    );

Future<AppController> _controller({_PreferencesGateway? gateway}) async {
  final controller = AppController(gateway: gateway ?? _PreferencesGateway());
  addTearDown(controller.dispose);
  await controller.initialize();
  await _settle();
  return controller;
}

class _PreferencesGateway implements AppGateway {
  _PreferencesGateway({
    this.snapshot = const LocalSnapshot(
      generations: [],
      preferences: AppPreferences(),
      hasApiKey: false,
      storage: StorageStats(path: 'memory', bytes: 0, records: 0),
    ),
  });

  LocalSnapshot snapshot;
  int preferenceWrites = 0;
  final List<GenerationSubmission> submissions = [];
  final Completer<void> creditStarted = Completer<void>();
  Completer<double>? creditGate;

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
    preferenceWrites += 1;
    snapshot = snapshot.copyWith(
      preferences: AppPreferences.fromJson(
        jsonDecode(jsonEncode(preferences.toJson())) as Map<String, Object?>,
      ),
    );
    return snapshot;
  }

  @override
  Future<double> getCredits() async {
    if (!creditStarted.isCompleted) creditStarted.complete();
    return creditGate == null ? 1000 : creditGate!.future;
  }

  @override
  Future<Generation> submit(GenerationSubmission submission) async {
    submissions.add(submission);
    return submission.record.copyWith(status: 'Pending');
  }

  @override
  Future<Generation> poll(Generation generation) async => generation;

  @override
  Future<Uri> assetUri(AssetReference reference) async =>
      Uri.parse(reference.value);

  @override
  Future<Uint8List> readAsset(AssetReference reference) async => Uint8List(0);

  @override
  Uri mediaUri(String source) => Uri.parse(source);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TabsGateway extends _PreferencesGateway implements ComposerTabsGateway {
  _TabsGateway({this.stored});

  ComposerTabsState? stored;

  @override
  Future<ComposerTabsState?> loadComposerTabs() async => stored;

  @override
  Future<void> saveComposerTabs(
    ComposerTabsState state, {
    bool publishNow = false,
  }) async {
    stored = state;
  }

  @override
  Future<void> publishComposerTabs() async {}
}

class _DrivePreferencesGateway extends _TabsGateway
    implements GoogleDriveGateway {
  _DrivePreferencesGateway({super.stored});

  Completer<LocalSnapshot?>? resumeGate;
  Completer<LocalSnapshot>? refreshGate;
  final Completer<void> resumeStarted = Completer<void>();
  final Completer<void> refreshStarted = Completer<void>();

  @override
  GoogleDriveConnection get googleDriveConnection =>
      const GoogleDriveConnection(
        state: GoogleDriveConnectionState.disconnected,
        folderId: 'test-library',
      );

  @override
  bool get supportsLocalLibrary => true;

  @override
  Future<LocalSnapshot?> resumeGoogleDrive({bool force = false}) async {
    if (!resumeStarted.isCompleted) resumeStarted.complete();
    final resumed = await resumeGate?.future;
    if (resumed != null) snapshot = resumed;
    return resumed;
  }

  @override
  Future<LocalSnapshot> refreshGoogleDrive() async {
    if (!refreshStarted.isCompleted) refreshStarted.complete();
    snapshot = await refreshGate!.future;
    return snapshot;
  }
}
