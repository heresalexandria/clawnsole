import 'dart:convert';

import 'package:clawnsole/core/composer_tabs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'schema 6 migrates to automatic casting and future schemas are refused',
    () {
      final old = ComposerTabsState.fromJson({
        'schemaVersion': 6,
        'tabs': [
          {
            'id': 'old',
            'characterMappings': {
              'HERO': ['Portrait'],
            },
          },
        ],
      });
      expect(old.tabs.single.characterReferenceTextOverride, isNull);
      expect(old.tabs.single.characterMappings['HERO'], ['Portrait']);
      expect(old.toJson()['schemaVersion'], 7);
      expect(
        () => ComposerTabsState.fromJson({'schemaVersion': 8}),
        throwsUnsupportedError,
      );
    },
  );

  test('cast overrides preserve verbatim text, explicit empty, and auto', () {
    for (final value in <String?>[
      null,
      '',
      ' HERO: @Portrait\nKeep the scar. ',
    ]) {
      final original = ComposerTabRecord(
        id: 'draft',
        prompt: 'A synthetic scene.',
        characterMappings: const {
          'HERO': ['Portrait'],
        },
        characterReferenceTextOverride: value,
      );
      final restored = _roundTrip(
        ComposerTabsState(tabs: [original]),
      ).tabs.single;
      expect(restored.characterReferenceTextOverride, value);
      expect(restored.characterMappings, original.characterMappings);
      expect(restored.prompt, original.prompt);
      expect(
        restored.toJson().containsKey('characterReferenceTextOverride'),
        value != null,
      );
    }
    final old = ComposerTabRecord.fromJson({
      'id': 'old',
      'characterMappings': {
        'HERO': ['Portrait'],
      },
    });
    expect(old.characterReferenceTextOverride, isNull);
    expect(old.characterMappings['HERO'], ['Portrait']);
  });

  test(
    'draft copies, model changes, and closed recovery keep the override',
    () {
      const record = ComposerTabRecord(
        id: 'closed',
        characterReferenceTextOverride: '',
        characterMappings: {
          'HERO': ['Portrait'],
        },
      );
      final saved = _roundTrip(
        const ComposerTabsState(closedTabs: [record], closedTabIds: {'closed'}),
      );
      final reopened = saved.closedTabs.single.copyWith(
        id: 'reopened',
        providerId: 'krea',
        modelId: 'bytedance/seedance-2-5',
      );
      expect(reopened.characterReferenceTextOverride, '');
      expect(reopened.characterMappings, record.characterMappings);
      final edited = reopened.copyWith(characterReferenceTextOverride: 'Cast.');
      expect(edited.characterReferenceTextOverride, 'Cast.');
      expect(
        edited
            .copyWith(clearCharacterReferenceTextOverride: true)
            .characterReferenceTextOverride,
        isNull,
      );
      expect(
        edited
            .copyWith(clearCharacterReferenceTextOverride: true)
            .characterMappings,
        record.characterMappings,
      );
    },
  );

  test(
    'Drive publication and merge preserve edits without replacing local tabs',
    () {
      final then = DateTime.utc(2026, 9, 7, 12);
      const draft = ComposerTabRecord(
        id: 'remote-draft',
        characterReferenceTextOverride:
            'HERO: preserve the custom instruction.',
        characterMappings: {
          'HERO': ['Portrait'],
        },
      );
      final first = ComposerTabsState(
        deviceId: 'first-device',
        deviceName: 'First',
        updatedAt: then,
        tabs: const [draft],
        activeTabId: draft.id,
      );
      final portable = _roundTrip(first.asDrivePortable());
      expect(portable.tabs, isEmpty);
      expect(portable.deviceId, isNull);
      final published = portable.devices.single.drafts.single;
      expect(
        published.characterReferenceTextOverride,
        draft.characterReferenceTextOverride,
      );
      expect(published.characterMappings, draft.characterMappings);

      final second = ComposerTabsState(
        deviceId: 'second-device',
        updatedAt: then,
        tabs: const [
          ComposerTabRecord(id: 'local', prompt: 'Local direction.'),
        ],
        activeTabId: 'local',
      );
      final merged = mergeComposerWorkspaces(second, portable)!;
      expect(merged.tabs.single.id, 'local');
      final copied = merged
          .deviceById('first-device')!
          .drafts
          .single
          .copyWith(id: 'local-copy');
      expect(
        copied.characterReferenceTextOverride,
        draft.characterReferenceTextOverride,
      );

      // A later explicit clear is a newer choice, not missing metadata to fill
      // from an older device snapshot.
      final cleared = first.copyWith(
        updatedAt: then.add(const Duration(minutes: 1)),
        tabs: [draft.copyWith(characterReferenceTextOverride: '')],
      );
      final latest = mergeComposerWorkspaces(
        merged,
        _roundTrip(cleared.asDrivePortable()),
      )!;
      expect(
        latest
            .deviceById('first-device')!
            .drafts
            .single
            .characterReferenceTextOverride,
        '',
      );
      expect(latest.tabs.single.id, 'local');
    },
  );

  test('a custom casting block is visible as a draft on other devices', () {
    expect(const ComposerTabRecord(id: 'auto').isBlankDraft, isTrue);
    expect(
      const ComposerTabRecord(
        id: 'custom',
        characterReferenceTextOverride: 'Custom casting.',
      ).isBlankDraft,
      isFalse,
    );
    expect(
      const ComposerTabRecord(
        id: 'cleared',
        characterReferenceTextOverride: '',
      ).isBlankDraft,
      isFalse,
    );
  });
}

ComposerTabsState _roundTrip(ComposerTabsState state) =>
    ComposerTabsState.fromJson(
      jsonDecode(jsonEncode(state.toJson())) as Map<String, Object?>,
    );
