import 'dart:typed_data';

import 'package:clawnsole/core/bfl_api.dart';
import 'package:clawnsole/core/direct_gateway.dart';
import 'package:clawnsole/core/durable_data_store.dart';
import 'package:clawnsole/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('session metadata round-trips with backward-compatible defaults', () {
    final now = DateTime.utc(2026, 8, 30, 12);
    final data = StoredData(
      preferences: const AppPreferences(
        lastLocalGenerationSessionId: 'session-local',
        lastDriveGenerationSessionId: 'session-drive',
      ),
      folders: <LibraryFolder>[
        LibraryFolder(
          id: 'session-local',
          name: 'Clockwork Garden',
          createdAt: now,
          role: LibraryFolderRole.session,
          automaticName: true,
        ),
      ],
      generations: <Generation>[
        _generation(now, folderId: 'session-local', sessionId: 'session-local'),
      ],
    );

    final json = data.toJson();
    final decoded = StoredData.decode(data.encode());

    expect(json['schemaVersion'], 24);
    expect(decoded.folders.single.role, LibraryFolderRole.session);
    expect(decoded.folders.single.automaticName, isTrue);
    expect(decoded.folders.single.isSession, isTrue);
    expect(decoded.generations.single.sessionId, 'session-local');
    expect(decoded.preferences.lastLocalGenerationSessionId, 'session-local');
    expect(decoded.preferences.lastDriveGenerationSessionId, 'session-drive');
    expect(
      decoded.generations.single.copyWith(clearSession: true).sessionId,
      isNull,
    );
    expect(
      decoded.preferences
          .copyWith(clearLastLocalGenerationSession: true)
          .lastLocalGenerationSessionId,
      isNull,
    );

    final legacyFolder = LibraryFolder.fromJson(<String, Object?>{
      'id': 'legacy-folder',
      'name': 'Legacy folder',
      'createdAt': now.toIso8601String(),
    });
    final legacyGeneration = Generation.fromJson(
      _generation(now).toJson()..remove('sessionId'),
    );
    final legacyPreferences = AppPreferences.fromJson(
      const <String, Object?>{},
    );

    expect(legacyFolder.role, LibraryFolderRole.standard);
    expect(legacyFolder.automaticName, isFalse);
    expect(legacyFolder.isSession, isFalse);
    expect(legacyGeneration.sessionId, isNull);
    expect(legacyPreferences.lastLocalGenerationSessionId, isNull);
    expect(legacyPreferences.lastDriveGenerationSessionId, isNull);
  });

  test(
    'folder saves retain session fields and deletion is orthogonal',
    () async {
      final now = DateTime.utc(2026, 8, 30, 12);
      final session = LibraryFolder(
        id: 'session',
        name: 'Clockwork Garden',
        createdAt: now,
        role: LibraryFolderRole.session,
        automaticName: true,
      );
      final destination = LibraryFolder(
        id: 'destination',
        name: 'Client work',
        createdAt: now,
      );
      final otherSession = LibraryFolder(
        id: 'other-session',
        name: 'Other session',
        createdAt: now,
        role: LibraryFolderRole.session,
      );
      final store = _MemoryStore(
        StoredData(
          folders: <LibraryFolder>[session, destination, otherSession],
          generations: <Generation>[
            _generation(
              now,
              folderId: destination.id,
              sessionId: session.id,
            ).copyWith(tags: const <String>['Campaign']),
          ],
        ),
      );
      final gateway = DirectGateway(store: store);

      await gateway.saveLibraryFolder(
        session.copyWith(name: 'Clockwork Garden Film'),
      );
      final savedSession = store.data.folders.singleWhere(
        (folder) => folder.id == session.id,
      );
      expect(savedSession.role, LibraryFolderRole.session);
      expect(savedSession.automaticName, isTrue);

      await expectLater(
        gateway.saveLibraryFolder(
          LibraryFolder(
            id: 'invalid-child',
            name: 'Invalid child',
            createdAt: now,
            parentId: session.id,
          ),
        ),
        throwsA(isA<StateError>()),
      );
      await gateway.setGenerationOrganization(
        'generation',
        folderId: session.id,
        tags: const <String>['Campaign'],
      );
      expect(store.data.generations.single.folderId, session.id);
      await expectLater(
        gateway.setGenerationOrganization(
          'generation',
          folderId: otherSession.id,
          tags: const <String>['Campaign'],
        ),
        throwsA(isA<StateError>()),
      );
      await gateway.setGenerationOrganization(
        'generation',
        folderId: destination.id,
        tags: const <String>['Campaign'],
      );

      await gateway.deleteLibraryFolder(destination.id);
      expect(store.data.generations.single.folderId, isNull);
      expect(store.data.generations.single.sessionId, session.id);

      await gateway.deleteLibraryFolder(session.id);
      expect(store.data.generations.single.folderId, isNull);
      expect(store.data.generations.single.sessionId, isNull);
      expect(store.data.generations.single.tags, const <String>['Campaign']);
    },
  );

  test(
    'provider replacements preserve a concurrently changed session',
    () async {
      final now = DateTime.utc(2026, 8, 30, 12);
      final store = _MemoryStore(const StoredData(apiKey: 'key'));
      final gateway = DirectGateway(
        store: store,
        api: _SessionChangingApi(store),
      );

      final accepted = await gateway.submit(
        GenerationSubmission(
          record: _generation(
            now,
            sessionId: 'initial-session',
          ).copyWith(status: 'submitting'),
          input: const <String, Object?>{
            'prompt': 'A clockwork garden at sunrise',
            'mode': 't2v',
            'duration': 8,
            'resolution': 'hd',
            'aspect_ratio': '16:9',
          },
        ),
      );

      expect(accepted.requestId, 'provider-receipt');
      expect(accepted.sessionId, 'edited-session');
      expect(store.data.generations.single.sessionId, 'edited-session');
    },
  );
}

Generation _generation(DateTime now, {String? folderId, String? sessionId}) =>
    Generation(
      localId: 'generation',
      status: 'Ready',
      prompt: 'A clockwork garden at sunrise',
      mode: VideoMode.t2v,
      config: const GenerationConfig(
        aspectRatio: '16:9',
        duration: 8,
        resolution: 'hd',
        generateAudio: true,
        safetyTolerance: 2,
        draft: false,
      ),
      createdAt: now,
      updatedAt: now,
      folderId: folderId,
      sessionId: sessionId,
    );

class _MemoryStore implements DurableDataStore {
  _MemoryStore(this.data);

  StoredData data;

  @override
  Future<StoredData> read() async => data;

  @override
  Future<void> write(StoredData value) async => data = value;

  @override
  Future<void> delete() async => data = const StoredData();

  @override
  Future<AssetReference> writeAsset(
    Uint8List bytes, {
    required String label,
    required String contentType,
    LibraryStorage storage = LibraryStorage.local,
  }) => throw UnsupportedError('Assets are not used by this test.');

  @override
  Future<AssetReference?> persistSource(
    String source, {
    required String label,
    AssetReference? retained,
    LibraryStorage storage = LibraryStorage.local,
  }) => throw UnsupportedError('Assets are not used by this test.');

  @override
  Future<Uint8List> readAsset(AssetReference reference) =>
      throw UnsupportedError('Assets are not used by this test.');

  @override
  Future<Uri> assetUri(AssetReference reference) =>
      throw UnsupportedError('Assets are not used by this test.');

  @override
  Future<void> pruneAssets(
    List<Generation> generations, [
    List<SavedReference> savedReferences = const <SavedReference>[],
  ]) async {}

  @override
  Future<StorageStats> stats(int records) async => StorageStats(
    path: 'memory',
    bytes: data.encode().length,
    records: records,
  );
}

class _SessionChangingApi extends BflApi {
  _SessionChangingApi(this.store);

  final _MemoryStore store;
  bool _changed = false;

  @override
  Future<double> getCredits(String apiKey) async {
    if (!_changed) {
      _changed = true;
      final generation = store.data.generations.single;
      await store.write(
        store.data.copyWith(
          generations: <Generation>[
            generation.copyWith(sessionId: 'edited-session'),
          ],
        ),
      );
    }
    return 100;
  }

  @override
  Future<Map<String, Object?>> submit(
    String apiKey,
    Map<String, Object?> input, {
    String model = 'flux-3-video',
  }) async => const <String, Object?>{
    'id': 'provider-receipt',
    'polling_url': 'https://api.bfl.ai/v1/get_result?id=provider-receipt',
  };
}
