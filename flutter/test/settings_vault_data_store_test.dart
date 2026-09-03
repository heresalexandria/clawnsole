import 'dart:math';
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

  test('device ids survive base64url draws the id rules reject', () async {
    // The top six bits of the first random byte become the id's first
    // base64url character; 248-255 map to '-' or '_', which the vault's
    // device-id rules reject as a leading character. The generator must
    // redraw instead of failing the whole secure store (this exact draw
    // was a 1-in-32 flake that hid keys and Drive state until restart).
    final local = _MemoryStore(
      const StoredData(apiKeys: <String, String>{'bfl': 'legacy-bfl'}),
    );
    final store = SettingsVaultDataStore(
      delegate: local,
      secureStore: MemorySecureValueStore(),
      codec: fastCodec,
      clock: () => DateTime.utc(2026, 8, 21),
      random: _SequencedRandom(<int>[
        ...List<int>.filled(32, 250),
        ...List<int>.filled(32, 65),
      ]),
    );

    final first = await store.read();

    expect(first.apiKeyFor('bfl'), 'legacy-bfl');
    expect(
      store.settingsVaultStatus.state,
      isNot(SettingsVaultState.error),
      reason: store.settingsVaultStatus.message,
    );
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

  test('AI Rewrite keys and config sync after vault setup', () async {
    // Exercise the real feature order: a vault already exists, then the
    // user adds rewrite keys and chooses a provider/model/effort. Keys are
    // ordinary encrypted credentials and rewrite configuration is ordinary
    // AppPreferences, so neither path can drift from the rest of Settings.
    final server = _RemoteServer();
    final firstLocal = _MemoryStore(const StoredData());
    final first = SettingsVaultDataStore(
      delegate: firstLocal,
      secureStore: MemorySecureValueStore(),
      remote: _FakeRemote(server),
      codec: fastCodec,
      clock: () => DateTime.utc(2026, 9, 2, 12),
    );
    await first.read();
    await first.connectRemote('token', 'folder');
    await first.setup('a correct horse battery staple');
    await first.write(
      StoredData(
        apiKeys: const <String, String>{
          'openai': 'sk-openai-shared',
          'anthropic': 'sk-ant-shared',
        },
        preferences: const AppPreferences(
          themeMode: AppThemeMode.dark,
          libraryViewMode: GenerationViewMode.compact,
          rewriteProvider: 'anthropic',
          rewriteModels: <String, String>{
            'openai': 'gpt-5.5',
            'anthropic': 'claude-opus-5',
          },
          rewriteEfforts: <String, String>{'anthropic': 'max'},
        ),
        preferencesUpdatedAt: DateTime.utc(2026, 9, 2, 12, 1),
      ),
    );
    expect(server.text, isNot(contains('sk-openai-shared')));
    expect(server.text, isNot(contains('sk-ant-shared')));
    expect(firstLocal.data.encode(), isNot(contains('sk-openai-shared')));
    expect(firstLocal.data.encode(), isNot(contains('sk-ant-shared')));

    final second = SettingsVaultDataStore(
      delegate: _MemoryStore(const StoredData()),
      secureStore: MemorySecureValueStore(),
      remote: _FakeRemote(server),
      codec: fastCodec,
      clock: () => DateTime.utc(2026, 9, 2, 13),
    );
    await second.read();
    await second.connectRemote('token', 'folder');
    await second.unlock('a correct horse battery staple');
    final synced = await second.read();
    expect(synced.apiKeyFor('openai'), 'sk-openai-shared');
    expect(synced.apiKeyFor('anthropic'), 'sk-ant-shared');
    expect(synced.preferences.themeMode, AppThemeMode.dark);
    expect(synced.preferences.libraryViewMode, GenerationViewMode.compact);
    expect(synced.preferences.rewriteProvider, 'anthropic');
    expect(synced.preferences.rewriteModels, <String, String>{
      'anthropic': 'claude-opus-5',
      'openai': 'gpt-5.5',
    });
    expect(synced.preferences.rewriteEfforts, <String, String>{
      'anthropic': 'max',
    });
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

class _SequencedRandom implements Random {
  _SequencedRandom(this._values);

  final List<int> _values;
  int _index = 0;

  @override
  int nextInt(int max) => _index < _values.length ? _values[_index++] % max : 0;

  @override
  double nextDouble() => 0;

  @override
  bool nextBool() => false;
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
