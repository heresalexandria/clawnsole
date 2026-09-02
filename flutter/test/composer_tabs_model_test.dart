import 'dart:convert';

import 'package:clawnsole/core/composer_tabs.dart';
import 'package:clawnsole/core/google_drive.dart';
import 'package:clawnsole/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('composer tab records round-trip through JSON', () {
    final record = ComposerTabRecord(
      id: 'tab-1',
      title: 'Night market',
      prompt: 'A lantern-lit night market in the rain',
      providerId: 'artcraft',
      modelId: 'seedance-2.5',
      aspectRatio: '9:16',
      autoDuration: true,
      durationSeconds: 12,
      frameRate: 3,
      resolution: 'fhd',
      generateAudio: false,
      safetyTolerance: 3,
      draft: true,
      exactTiming: true,
      referenceTask: 'edit',
      upscale: false,
      upscaleFactor: 4,
      upscaleCreativity: 2,
      seed: 42,
      videoUrl: 'https://example.com/source.mp4',
      draftUrl: '',
      sourceGenerationId: 'gen-9',
      rewriteSummary: 'Slowed the dolly and warmed the lanterns.',
      localFolderId: 'folder-local',
      driveFolderId: 'folder-drive',
      createdAt: DateTime.utc(2026, 9, 1, 10),
      updatedAt: DateTime.utc(2026, 9, 2, 11, 30),
    );
    final json =
        jsonDecode(jsonEncode(record.toJson())) as Map<String, Object?>;
    final decoded = ComposerTabRecord.fromJson(json);

    expect(decoded.id, 'tab-1');
    expect(decoded.title, 'Night market');
    expect(decoded.prompt, record.prompt);
    expect(decoded.providerId, 'artcraft');
    expect(decoded.modelId, 'seedance-2.5');
    expect(decoded.aspectRatio, '9:16');
    expect(decoded.autoDuration, isTrue);
    expect(decoded.durationSeconds, 12);
    expect(decoded.frameRate, 3);
    expect(decoded.resolution, 'fhd');
    expect(decoded.generateAudio, isFalse);
    expect(decoded.safetyTolerance, 3);
    expect(decoded.draft, isTrue);
    expect(decoded.exactTiming, isTrue);
    expect(decoded.referenceTask, 'edit');
    expect(decoded.upscaleFactor, 4);
    expect(decoded.upscaleCreativity, 2);
    expect(decoded.seed, 42);
    expect(decoded.videoUrl, 'https://example.com/source.mp4');
    expect(decoded.draftUrl, '');
    expect(decoded.sourceGenerationId, 'gen-9');
    expect(decoded.rewriteSummary, 'Slowed the dolly and warmed the lanterns.');
    expect(decoded.localFolderId, 'folder-local');
    expect(decoded.driveFolderId, 'folder-drive');
    expect(decoded.createdAt, DateTime.utc(2026, 9, 1, 10));
    expect(decoded.updatedAt, DateTime.utc(2026, 9, 2, 11, 30));
    expect(
      json.containsKey('draftUrl'),
      isFalse,
      reason: 'empty urls stay out',
    );
  });

  test('composer tab decoding tolerates junk and applies defaults', () {
    final decoded = ComposerTabRecord.fromJson(<String, Object?>{
      'id': 'tab-2',
      'prompt': 7,
      'durationSeconds': 'eleven',
      'autoDuration': 'yes',
      'seed': null,
      'title': '   ',
      'upscaleFactor': 'x',
    });
    expect(decoded.id, 'tab-2');
    expect(decoded.prompt, '');
    expect(decoded.durationSeconds, 8);
    expect(decoded.autoDuration, isFalse);
    expect(decoded.seed, isNull);
    expect(decoded.title, isNull);
    expect(decoded.upscaleFactor, 2);
    expect(decoded.label, composerTabUntitled);
  });

  test('tab state drops id-less and duplicate records and keeps a valid '
      'active id', () {
    final state = ComposerTabsState.fromJson(<String, Object?>{
      'schemaVersion': 1,
      'activeTabId': 'missing',
      'tabs': <Object?>[
        <String, Object?>{'id': 'a', 'prompt': 'first'},
        <String, Object?>{'prompt': 'no id'},
        <String, Object?>{'id': 'a', 'prompt': 'duplicate'},
        <String, Object?>{'id': 'b', 'prompt': 'second'},
        'garbage',
      ],
    });
    expect(state.tabs.map((tab) => tab.id), <String>['a', 'b']);
    expect(state.tabs.first.prompt, 'first');
    expect(state.activeTabId, 'a');
    expect(state.activeTab?.id, 'a');

    final chosen = ComposerTabsState.fromJson(<String, Object?>{
      'activeTabId': 'b',
      'tabs': state.tabs.map((tab) => tab.toJson()).toList(),
    });
    expect(chosen.activeTabId, 'b');
    expect(chosen.activeTab?.prompt, 'second');
    expect(const ComposerTabsState().isEmpty, isTrue);
    expect(const ComposerTabsState().activeTab, isNull);
  });

  test('derived tab titles come from the first prompt line', () {
    expect(composerTabTitle(null, ''), composerTabUntitled);
    expect(composerTabTitle(' Custom ', 'ignored prompt'), 'Custom');
    expect(
      composerTabTitle(null, '\n\n  Short prompt  \nsecond'),
      'Short prompt',
    );
    expect(
      composerTabTitle(
        null,
        'A very long opening sentence that keeps going well past the limit',
      ),
      'A very long opening sentence…',
    );
    expect(
      composerTabTitle(null, 'Supercalifragilisticexpialidociously long'),
      'Supercalifragilisticexpialid…',
    );
    expect(
      composerTabTitle(null, 'tabs   collapse\twhitespace'),
      'tabs collapse whitespace',
    );
  });

  test('stored data keeps composer tabs on the device only', () {
    final data = StoredData(
      composerTabs: const ComposerTabsState(
        tabs: <ComposerTabRecord>[
          ComposerTabRecord(id: 't1', prompt: 'one'),
          ComposerTabRecord(id: 't2', prompt: 'two'),
        ],
        activeTabId: 't2',
      ),
    );
    final roundTrip = StoredData.fromJson(
      jsonDecode(data.encode()) as Map<String, Object?>,
    );
    expect(roundTrip.composerTabs?.tabs.map((tab) => tab.id), <String>[
      't1',
      't2',
    ]);
    expect(roundTrip.composerTabs?.activeTabId, 't2');
    expect(data.copyWith(clearComposerTabs: true).composerTabs, isNull);
    expect(
      data.copyWith(generations: const <Generation>[]).composerTabs,
      same(data.composerTabs),
    );
    expect(
      googleDrivePortableData(data).toJson().containsKey('composerTabs'),
      isFalse,
      reason: 'tabs are drafts, never Drive library data',
    );
    expect(
      StoredData.fromJson(<String, Object?>{
        'composerTabs': 'bad',
      }).composerTabs,
      isNull,
    );
  });

  test('preferences remember AI Rewrite choices per provider', () {
    const preferences = AppPreferences(
      rewriteProvider: 'anthropic',
      rewriteModels: <String, String>{
        'openai': 'gpt-5.5',
        'anthropic': 'claude-opus-5',
      },
      rewriteEfforts: <String, String>{'anthropic': 'max'},
    );
    final json =
        jsonDecode(jsonEncode(preferences.toJson())) as Map<String, Object?>;
    final decoded = AppPreferences.fromJson(json);
    expect(decoded.rewriteProvider, 'anthropic');
    expect(decoded.rewriteModels, <String, String>{
      'anthropic': 'claude-opus-5',
      'openai': 'gpt-5.5',
    });
    expect(decoded.rewriteEfforts, <String, String>{'anthropic': 'max'});
    expect(
      preferences.copyWith(clearRewriteProvider: true).rewriteProvider,
      isNull,
    );
    expect(
      preferences.copyWith(rewriteModels: <String, String>{}).rewriteEfforts,
      preferences.rewriteEfforts,
    );

    final legacy = AppPreferences.fromJson(<String, Object?>{
      'rewriteProvider': '  ',
      'rewriteModels': <String, Object?>{'openai': 1, 'anthropic': ' x '},
      'rewriteEfforts': 'nope',
    });
    expect(legacy.rewriteProvider, isNull);
    expect(legacy.rewriteModels, <String, String>{'anthropic': 'x'});
    expect(legacy.rewriteEfforts, isEmpty);
    expect(
      const AppPreferences().toJson().containsKey('rewriteModels'),
      isFalse,
    );
  });

  test('snapshots carry connected rewrite providers', () {
    const snapshot = LocalSnapshot(
      generations: <Generation>[],
      preferences: AppPreferences(),
      hasApiKey: false,
      storage: StorageStats(path: '/tmp/clawnsole.json', bytes: 0, records: 0),
      connectedRewriteProviders: <String>{'openai'},
    );
    final json =
        jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, Object?>;
    expect(json['connectedRewriteProviders'], <String>['openai']);
    expect(LocalSnapshot.fromJson(json).connectedRewriteProviders, <String>{
      'openai',
    });
    expect(
      snapshot
          .copyWith(connectedRewriteProviders: <String>{})
          .connectedRewriteProviders,
      isEmpty,
    );
    expect(
      LocalSnapshot.fromJson(<String, Object?>{}).connectedRewriteProviders,
      isEmpty,
    );
  });
}
