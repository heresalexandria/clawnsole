import 'dart:typed_data';

import 'package:clawnsole/core/durable_data_store.dart';
import 'package:clawnsole/core/google_drive.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/secure_value_store.dart';
import 'package:clawnsole/core/settings_vault.dart';
import 'package:clawnsole/core/settings_vault_data_store.dart';
import 'package:clawnsole/core/settings_vault_remote.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fastCodec = SettingsVaultCodec(
    kdfParameters: const SettingsVaultKdfParameters(
      memoryKiB: settingsVaultMinimumMemoryKiB,
      iterations: 1,
    ),
  );

  test('migrates legacy plaintext keys before sanitizing local JSON', () async {
    final local = _MemoryStore(
      const StoredData(
        apiKey: 'legacy-bfl',
        apiKeys: <String, String>{'bfl': 'legacy-bfl', 'ltx': 'legacy-ltx'},
      ),
    );
    final secure = MemorySecureValueStore();
    final store = SettingsVaultDataStore(
      delegate: local,
      secureStore: secure,
      codec: fastCodec,
      clock: () => DateTime.utc(2026, 8, 20),
    );

    final first = await store.read();

    expect(first.apiKeyFor('bfl'), 'legacy-bfl');
    expect(first.apiKeyFor('ltx'), 'legacy-ltx');
    expect(local.data.encode(), isNot(contains('legacy-')));
    expect(secure.values.values.single, contains('legacy-bfl'));

    final restarted = SettingsVaultDataStore(
      delegate: local,
      secureStore: secure,
      codec: fastCodec,
      clock: () => DateTime.utc(2026, 8, 20, 0, 1),
    );
    expect((await restarted.read()).apiKeyFor('ltx'), 'legacy-ltx');
    expect(local.data.encode(), isNot(contains('legacy-')));
  });

  test('setup and one-time unlock synchronize keys and preferences', () async {
    final server = _RemoteServer();
    final firstLocal = _MemoryStore(
      StoredData(
        apiKeys: const <String, String>{'bfl': 'shared-bfl'},
        preferences: const AppPreferences(provider: 'ltx'),
        preferencesUpdatedAt: DateTime.utc(2026, 8, 20, 12),
      ),
    );
    final first = SettingsVaultDataStore(
      delegate: firstLocal,
      secureStore: MemorySecureValueStore(),
      remote: _FakeRemote(server),
      codec: fastCodec,
      clock: () => DateTime.utc(2026, 8, 20, 12),
    );
    await first.read();
    await first.connectRemote('token', 'folder');
    final recovery = await first.setup('a correct horse battery staple');

    expect(recovery, hasLength(43));
    expect(first.settingsVaultStatus.state, SettingsVaultState.ready);
    expect(server.text, isNot(contains('shared-bfl')));
    expect(server.text, isNot(contains('"provider":"ltx"')));

    final second = SettingsVaultDataStore(
      delegate: _MemoryStore(const StoredData()),
      secureStore: MemorySecureValueStore(),
      remote: _FakeRemote(server),
      codec: fastCodec,
      // A fresh device may have a later clock than the device that created the
      // vault. Its untouched defaults still must not overwrite synced prefs.
      clock: () => DateTime.utc(2026, 8, 20, 13),
    );
    await second.read();
    await second.connectRemote('token', 'folder');
    expect(second.settingsVaultStatus.state, SettingsVaultState.locked);
    await second.unlock('a correct horse battery staple');

    final synced = await second.read();
    expect(synced.apiKeyFor('bfl'), 'shared-bfl');
    expect(synced.preferences.provider, 'ltx');
    expect(second.settingsVaultStatus.state, SettingsVaultState.ready);
  });

  test('a Drive failure keeps the verified local save pending', () async {
    final server = _RemoteServer();
    final local = _MemoryStore(const StoredData());
    final store = SettingsVaultDataStore(
      delegate: local,
      secureStore: MemorySecureValueStore(),
      remote: _FakeRemote(server),
      codec: fastCodec,
      clock: () => DateTime.utc(2026, 8, 20, 12),
    );
    await store.read();
    await store.connectRemote('token', 'folder');
    await store.setup('a correct horse battery staple');
    server.failWrites = true;

    await store.write((await store.read()).withApiKey('atlas', 'local-atlas'));

    expect((await store.read()).apiKeyFor('atlas'), 'local-atlas');
    expect(local.data.encode(), isNot(contains('local-atlas')));
    expect(store.settingsVaultStatus.state, SettingsVaultState.pending);
  });

  test('a Drive ETag conflict is rebased and retried', () async {
    final server = _RemoteServer();
    final store = SettingsVaultDataStore(
      delegate: _MemoryStore(const StoredData()),
      secureStore: MemorySecureValueStore(),
      remote: _FakeRemote(server),
      codec: fastCodec,
      clock: () => DateTime.utc(2026, 8, 20, 12),
    );
    await store.read();
    await store.connectRemote('token', 'folder');
    await store.setup('a correct horse battery staple');
    server.conflictsRemaining = 1;

    await store.write((await store.read()).withApiKey('ltx', 'rebased-ltx'));

    expect(store.settingsVaultStatus.state, SettingsVaultState.ready);
    expect(server.conflictsRemaining, 0);
    expect(server.writeCount, 2);
  });

  test('wrong passphrase never writes or replaces the remote vault', () async {
    final server = _RemoteServer();
    final creator = SettingsVaultDataStore(
      delegate: _MemoryStore(
        const StoredData(apiKeys: <String, String>{'bfl': 'do-not-overwrite'}),
      ),
      secureStore: MemorySecureValueStore(),
      remote: _FakeRemote(server),
      codec: fastCodec,
    );
    await creator.read();
    await creator.connectRemote('token', 'folder');
    await creator.setup('a correct horse battery staple');
    final writes = server.writeCount;
    final ciphertext = Uint8List.fromList(server.bytes!);

    final second = SettingsVaultDataStore(
      delegate: _MemoryStore(const StoredData()),
      secureStore: MemorySecureValueStore(),
      remote: _FakeRemote(server),
      codec: fastCodec,
    );
    await second.read();
    await second.connectRemote('token', 'folder');

    await expectLater(
      second.unlock('this passphrase is definitely wrong'),
      throwsA(isA<SettingsVaultAuthenticationException>()),
    );
    expect(server.writeCount, writes);
    expect(server.bytes, ciphertext);
  });

  test(
    'independent preference edits from two devices merge per field',
    () async {
      final server = _RemoteServer();
      var firstNow = DateTime.utc(2026, 8, 20, 10);
      var secondNow = firstNow;
      final first = SettingsVaultDataStore(
        delegate: _MemoryStore(const StoredData()),
        secureStore: MemorySecureValueStore(),
        remote: _FakeRemote(server),
        codec: fastCodec,
        clock: () => firstNow,
      );
      await first.read();
      await first.connectRemote('token', 'folder');
      await first.setup('a correct horse battery staple');

      final second = SettingsVaultDataStore(
        delegate: _MemoryStore(const StoredData()),
        secureStore: MemorySecureValueStore(),
        remote: _FakeRemote(server),
        codec: fastCodec,
        clock: () => secondNow,
      );
      await second.read();
      await second.connectRemote('token', 'folder');
      await second.unlock('a correct horse battery staple');

      firstNow = DateTime.utc(2026, 8, 20, 10, 1);
      await first.write(
        (await first.read()).copyWith(
          preferences: const AppPreferences(provider: 'ltx'),
          preferencesUpdatedAt: firstNow,
        ),
      );
      secondNow = DateTime.utc(2026, 8, 20, 10, 2);
      await second.write(
        (await second.read()).copyWith(
          preferences: const AppPreferences(
            libraryViewMode: GenerationViewMode.compact,
          ),
          preferencesUpdatedAt: secondNow,
        ),
      );

      final verifier = SettingsVaultDataStore(
        delegate: _MemoryStore(const StoredData()),
        secureStore: MemorySecureValueStore(),
        remote: _FakeRemote(server),
        codec: fastCodec,
      );
      await verifier.read();
      await verifier.connectRemote('token', 'folder');
      await verifier.unlock('a correct horse battery staple');
      final merged = await verifier.read();

      expect(merged.preferences.provider, 'ltx');
      expect(merged.preferences.libraryViewMode, GenerationViewMode.compact);
    },
  );

  test(
    'locked status explains the local data that unlock will merge',
    () async {
      final server = _RemoteServer();
      final creator = SettingsVaultDataStore(
        delegate: _MemoryStore(const StoredData()),
        secureStore: MemorySecureValueStore(),
        remote: _FakeRemote(server),
        codec: fastCodec,
      );
      await creator.read();
      await creator.connectRemote('token', 'folder');
      await creator.setup('a correct horse battery staple');

      final joining = SettingsVaultDataStore(
        delegate: _MemoryStore(
          StoredData(
            apiKeys: const <String, String>{'atlas': 'local-atlas'},
            preferences: const AppPreferences(provider: 'atlas'),
            preferencesUpdatedAt: DateTime.utc(2026, 8, 20, 12),
          ),
        ),
        secureStore: MemorySecureValueStore(),
        remote: _FakeRemote(server),
        codec: fastCodec,
      );
      await joining.read();
      await joining.connectRemote('token', 'folder');

      expect(joining.settingsVaultStatus.state, SettingsVaultState.locked);
      expect(joining.settingsVaultStatus.localCredentialCount, 1);
      expect(joining.settingsVaultStatus.hasLocalPreferences, isTrue);
    },
  );

  test(
    'reset replaces only the vault and preserves local secure data',
    () async {
      final server = _RemoteServer();
      final local = _MemoryStore(
        StoredData(
          apiKeys: const <String, String>{'bfl': 'preserved-key'},
          preferences: const AppPreferences(provider: 'ltx'),
          preferencesUpdatedAt: DateTime.utc(2026, 8, 20, 12),
        ),
      );
      final store = SettingsVaultDataStore(
        delegate: local,
        secureStore: MemorySecureValueStore(),
        remote: _FakeRemote(server),
        codec: fastCodec,
      );
      await store.read();
      await store.connectRemote('token', 'folder');
      await store.setup('old correct horse battery staple');
      final oldCiphertext = Uint8List.fromList(server.bytes!);

      await expectLater(
        store.reset('too short'),
        throwsA(isA<ArgumentError>()),
      );
      expect(server.bytes, orderedEquals(oldCiphertext));

      server.failWrites = true;
      await expectLater(
        store.reset('temporary correct horse battery staple'),
        throwsA(isA<GoogleDriveException>()),
      );
      server.failWrites = false;
      expect(server.bytes, orderedEquals(oldCiphertext));
      expect((await store.read()).apiKeyFor('bfl'), 'preserved-key');

      final recovery = await store.reset('new correct horse battery staple');

      expect(recovery, hasLength(43));
      expect(server.bytes, isNot(orderedEquals(oldCiphertext)));
      expect((await store.read()).apiKeyFor('bfl'), 'preserved-key');
      expect((await store.read()).preferences.provider, 'ltx');
      expect(local.data.encode(), isNot(contains('preserved-key')));

      final joining = SettingsVaultDataStore(
        delegate: _MemoryStore(const StoredData()),
        secureStore: MemorySecureValueStore(),
        remote: _FakeRemote(server),
        codec: fastCodec,
      );
      await joining.read();
      await joining.connectRemote('token', 'folder');
      await expectLater(
        joining.unlock('old correct horse battery staple'),
        throwsA(isA<SettingsVaultAuthenticationException>()),
      );
      await joining.unlock('new correct horse battery staple');
      expect((await joining.read()).apiKeyFor('bfl'), 'preserved-key');
    },
  );
}

class _RemoteServer {
  Uint8List? bytes;
  int etag = 0;
  int writeCount = 0;
  bool failWrites = false;
  int conflictsRemaining = 0;

  String get text => bytes == null ? '' : String.fromCharCodes(bytes!);
}

class _FakeRemote implements SettingsVaultRemote {
  _FakeRemote(this.server);

  final _RemoteServer server;
  bool connected = false;

  @override
  bool get isConnected => connected;

  SettingsVaultRemoteDocument? get document => server.bytes == null
      ? null
      : SettingsVaultRemoteDocument(
          Uint8List.fromList(server.bytes!),
          etag: '${server.etag}',
        );

  @override
  Future<SettingsVaultRemoteDocument?> connect(
    String accessToken,
    String folderId,
  ) async {
    connected = true;
    return document;
  }

  @override
  Future<SettingsVaultRemoteDocument?> read() async => document;

  @override
  Future<SettingsVaultRemoteDocument> write(
    Uint8List bytes, {
    String? expectedEtag,
  }) async {
    if (server.failWrites) {
      throw const GoogleDriveException('offline', status: 503);
    }
    if (server.conflictsRemaining > 0) {
      server
        ..conflictsRemaining -= 1
        ..etag += 1;
      throw const GoogleDriveException('conflict', status: 412);
    }
    if (expectedEtag != null && expectedEtag != '${server.etag}') {
      throw const GoogleDriveException('conflict', status: 412);
    }
    server
      ..bytes = Uint8List.fromList(bytes)
      ..etag += 1
      ..writeCount += 1;
    return document!;
  }

  @override
  Future<void> disconnect() async => connected = false;

  @override
  Future<void> delete() async {
    server.bytes = null;
  }
}

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
  }) async => AssetReference(
    kind: storage == LibraryStorage.drive ? 'drive' : 'local',
    value: 'memory',
    label: label,
  );

  @override
  Future<AssetReference?> persistSource(
    String source, {
    required String label,
    AssetReference? retained,
    LibraryStorage storage = LibraryStorage.local,
  }) async => retained;

  @override
  Future<Uint8List> readAsset(AssetReference reference) async => Uint8List(0);

  @override
  Future<Uri> assetUri(AssetReference reference) async => Uri();

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
