import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'durable_data_store.dart';
import 'google_drive.dart';
import 'models.dart';
import 'secure_value_store.dart';
import 'settings_vault.dart';
import 'settings_vault_gateway.dart';
import 'settings_vault_remote.dart';

const _secureStateKey = 'settings-vault-state-v1';
const _secureStateVersion = 1;

/// Keeps provider credentials in device-secure storage and synchronizes an
/// independently encrypted settings vault beside the portable Drive library.
///
/// Local writes always complete before a best-effort Drive sync. A network
/// failure therefore leaves a visible pending state without losing a verified
/// provider key or preference change.
class SettingsVaultDataStore
    implements DurableDataStore, SettingsVaultStatusSource {
  SettingsVaultDataStore({
    required DurableDataStore delegate,
    required SecureValueStore secureStore,
    SettingsVaultRemote? remote,
    SettingsVaultCodec? codec,
    DateTime Function()? clock,
    Random? random,
  }) : _delegate = delegate,
       _secureStore = secureStore,
       _remote = remote ?? GoogleDriveSettingsVaultRemote(),
       _codec = codec ?? SettingsVaultCodec(),
       _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  final DurableDataStore _delegate;
  final SecureValueStore _secureStore;
  final SettingsVaultRemote _remote;
  final SettingsVaultCodec _codec;
  final DateTime Function() _clock;
  final Random _random;

  _DeviceVaultState? _state;
  bool _stateLoaded = false;
  Future<void> _queue = Future<void>.value();
  SettingsVaultRemoteDocument? _remoteDocument;
  SettingsVaultStatus _status = const SettingsVaultStatus(
    state: SettingsVaultState.driveDisconnected,
    message: 'Connect Google Drive to sync encrypted settings.',
  );

  @override
  SettingsVaultStatus get settingsVaultStatus => _status;

  bool get isRemoteConnected => _remote.isConnected;

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = _queue.then((_) => operation());
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  @override
  Future<StoredData> read() => _serialized(_readInternal);

  Future<StoredData> _readInternal() async {
    final data = await _delegate.read();
    final state = await _ensureState(data);
    if (state == null) return _withoutCredentials(data);
    return _withCredentials(data, state);
  }

  @override
  Future<void> write(StoredData data) => _serialized(() async {
    final current = await _delegate.read();
    final state = await _ensureState(current);
    if (state == null) {
      if (_containsCredentials(data)) {
        throw StateError('Secure device storage is unavailable.');
      }
      await _delegate.write(_withoutCredentials(data));
      return;
    }

    final changed = _captureChanges(state, data, current);
    if (changed) await _persistState(state);
    await _delegate.write(_withoutCredentials(data));
    if (changed && _remote.isConnected && state.hasCachedKey) {
      try {
        await _syncInternal();
      } on Object {
        _status = SettingsVaultStatus(
          state: SettingsVaultState.pending,
          vaultId: state.vaultId,
          lastSyncedAt: _status.lastSyncedAt,
          message: 'Saved on this device; encrypted Drive sync is pending.',
        );
      }
    }
  });

  Future<void> connectRemote(
    String accessToken,
    String folderId,
  ) => _serialized(() async {
    final local = await _delegate.read();
    final state = await _ensureState(local);
    if (state == null) return;
    _status = SettingsVaultStatus(
      state: SettingsVaultState.syncing,
      vaultId: state.vaultId,
      message: 'Checking the encrypted settings vault…',
    );
    try {
      _remoteDocument = await _remote.connect(accessToken, folderId);
      final document = _remoteDocument;
      if (document == null) {
        _status = const SettingsVaultStatus(
          state: SettingsVaultState.setupRequired,
          message:
              'Create an encrypted vault to sync provider keys and settings.',
        );
        return;
      }
      final envelope = _decodeDocument(document);
      if (!state.hasCachedKey || state.vaultId != envelope.vaultId) {
        _status = SettingsVaultStatus(
          state: SettingsVaultState.locked,
          vaultId: envelope.vaultId,
          message: 'Enter the sync passphrase once on this device.',
          localCredentialCount: _localCredentialCount(state),
          hasLocalPreferences: state.preferenceFields.isNotEmpty,
        );
        return;
      }
      try {
        final key = _cachedKey(state);
        try {
          await _codec.decrypt(envelope, key);
        } finally {
          key.destroy();
        }
      } on SettingsVaultAuthenticationException {
        state
          ..vaultId = ''
          ..dataEncryptionKey = '';
        await _persistState(state);
        _status = SettingsVaultStatus(
          state: SettingsVaultState.locked,
          vaultId: envelope.vaultId,
          message: 'This device needs the sync passphrase again.',
          localCredentialCount: _localCredentialCount(state),
          hasLocalPreferences: state.preferenceFields.isNotEmpty,
        );
        return;
      }
      await _syncInternal();
    } on SettingsVaultFormatException catch (error) {
      _status = SettingsVaultStatus(
        state: SettingsVaultState.error,
        vaultId: state.vaultId,
        message: error.message,
      );
    } on Object catch (error) {
      _status = SettingsVaultStatus(
        state: SettingsVaultState.error,
        vaultId: state.vaultId,
        message: _safeMessage(error),
      );
    }
  });

  Future<void> disconnectRemote() => _serialized(() async {
    await _remote.disconnect();
    _remoteDocument = null;
    _status = SettingsVaultStatus(
      state: SettingsVaultState.driveDisconnected,
      vaultId: _state?.vaultId ?? '',
      lastSyncedAt: _status.lastSyncedAt,
      message:
          'Drive disconnected. Secure settings remain available on this device.',
    );
  });

  Future<String> setup(String passphrase) =>
      _serialized(() => _setupInternal(passphrase));

  Future<String> _setupInternal(String passphrase) async {
    final state = await _requireState();
    _requireRemote();
    final existing = await _remote.read();
    if (existing != null) {
      final envelope = _decodeDocument(existing);
      _status = SettingsVaultStatus(
        state: SettingsVaultState.locked,
        vaultId: envelope.vaultId,
        message: 'An encrypted vault already exists. Unlock it instead.',
        localCredentialCount: _localCredentialCount(state),
        hasLocalPreferences: state.preferenceFields.isNotEmpty,
      );
      throw StateError('An encrypted settings vault already exists.');
    }
    _status = const SettingsVaultStatus(
      state: SettingsVaultState.syncing,
      message: 'Creating the encrypted settings vault…',
    );
    final created = await _codec.create(passphrase, state.payload);
    try {
      return await _writeCreatedVault(state, created);
    } finally {
      created.dataEncryptionKey.destroy();
    }
  }

  /// Replaces only the encrypted Drive vault after explicit recovery consent.
  /// Local provider keys, preferences, and the portable Drive library remain.
  Future<String> reset(String passphrase) => _serialized(() async {
    final state = await _requireState();
    _requireRemote();
    _status = SettingsVaultStatus(
      state: SettingsVaultState.syncing,
      vaultId: state.vaultId,
      message: 'Preparing a replacement encrypted settings vault…',
    );
    final existing = await _remote.read();
    // Derive and validate the replacement before atomically overwriting the
    // old envelope with an ETag precondition.
    final created = await _codec.create(passphrase, state.payload);
    try {
      return await _writeCreatedVault(
        state,
        created,
        expectedEtag: existing?.etag,
      );
    } on Object {
      _status = SettingsVaultStatus(
        state: SettingsVaultState.pending,
        vaultId: state.vaultId,
        lastSyncedAt: _status.lastSyncedAt,
        message:
            'The replacement was not completed. Existing Drive data and local settings were kept.',
      );
      rethrow;
    } finally {
      created.dataEncryptionKey.destroy();
    }
  });

  Future<String> _writeCreatedVault(
    _DeviceVaultState state,
    CreatedSettingsVault created, {
    String? expectedEtag,
  }) async {
    final uploaded = await _remote.write(
      Uint8List.fromList(utf8.encode(created.envelope.encode())),
      expectedEtag: expectedEtag,
    );
    final verifiedDocument = await _remote.read() ?? uploaded;
    final verified = _decodeDocument(verifiedDocument);
    if (verified.vaultId != created.envelope.vaultId) {
      throw StateError('Google Drive returned a different settings vault.');
    }
    await _codec.decrypt(verified, created.dataEncryptionKey);
    state
      ..vaultId = verified.vaultId
      ..dataEncryptionKey = _encodeKey(created.dataEncryptionKey.bytes);
    await _persistState(state);
    _remoteDocument = verifiedDocument;
    _status = SettingsVaultStatus(
      state: SettingsVaultState.ready,
      vaultId: verified.vaultId,
      lastSyncedAt: _now(),
      message: 'Provider keys and settings are encrypted and synced.',
    );
    return created.recoveryCode;
  }

  Future<void> unlock(String passphrase) => _serialized(() async {
    final document = await _requireDocument();
    final envelope = _decodeDocument(document);
    UnlockedSettingsVault unlocked;
    try {
      unlocked = await _codec.unlock(envelope, passphrase);
    } on SettingsVaultAuthenticationException {
      _status = SettingsVaultStatus(
        state: SettingsVaultState.locked,
        vaultId: envelope.vaultId,
        message: 'The passphrase did not unlock this settings vault.',
        localCredentialCount: _localCredentialCount(_state),
        hasLocalPreferences: _state?.preferenceFields.isNotEmpty == true,
      );
      rethrow;
    }
    try {
      await _acceptUnlocked(
        document,
        envelope,
        unlocked.payload,
        unlocked.dataEncryptionKey,
      );
    } finally {
      unlocked.dataEncryptionKey.destroy();
    }
  });

  Future<void> recover(String recoveryCode) => _serialized(() async {
    final document = await _requireDocument();
    final envelope = _decodeDocument(document);
    UnlockedSettingsVault unlocked;
    try {
      unlocked = await _codec.unlockWithRecoveryCode(envelope, recoveryCode);
    } on SettingsVaultAuthenticationException {
      _status = SettingsVaultStatus(
        state: SettingsVaultState.locked,
        vaultId: envelope.vaultId,
        message: 'The recovery code did not unlock this settings vault.',
        localCredentialCount: _localCredentialCount(_state),
        hasLocalPreferences: _state?.preferenceFields.isNotEmpty == true,
      );
      rethrow;
    }
    try {
      await _acceptUnlocked(
        document,
        envelope,
        unlocked.payload,
        unlocked.dataEncryptionKey,
      );
    } finally {
      unlocked.dataEncryptionKey.destroy();
    }
  });

  Future<void> sync() => _serialized(_syncInternal);

  Future<void> _syncInternal() async {
    final state = await _requireState();
    _requireRemote();
    if (!state.hasCachedKey) {
      _status = SettingsVaultStatus(
        state: SettingsVaultState.locked,
        vaultId: state.vaultId,
        message: 'Enter the sync passphrase once on this device.',
        localCredentialCount: _localCredentialCount(state),
        hasLocalPreferences: state.preferenceFields.isNotEmpty,
      );
      throw StateError('Unlock the encrypted settings vault first.');
    }
    _status = SettingsVaultStatus(
      state: SettingsVaultState.syncing,
      vaultId: state.vaultId,
      lastSyncedAt: _status.lastSyncedAt,
      message: 'Syncing encrypted settings…',
    );
    final key = _cachedKey(state);
    try {
      for (var attempt = 0; attempt < 3; attempt += 1) {
        final document = await _requireDocument(refresh: true);
        final envelope = _decodeDocument(document);
        if (envelope.vaultId != state.vaultId) {
          throw StateError('The Google Drive settings vault has changed.');
        }
        final remotePayload = await _codec.decrypt(envelope, key);
        final merged = mergeVaultPayloads(state.payload, remotePayload);
        await _applyPayload(state, merged);
        if (merged.encode() == remotePayload.encode()) {
          _remoteDocument = document;
          _status = SettingsVaultStatus(
            state: SettingsVaultState.ready,
            vaultId: state.vaultId,
            lastSyncedAt: _now(),
            message: 'Provider keys and settings are encrypted and synced.',
          );
          return;
        }
        final updated = await _codec.updatePayload(envelope, key, merged);
        try {
          _remoteDocument = await _remote.write(
            Uint8List.fromList(utf8.encode(updated.encode())),
            expectedEtag: document.etag,
          );
          _status = SettingsVaultStatus(
            state: SettingsVaultState.ready,
            vaultId: state.vaultId,
            lastSyncedAt: _now(),
            message: 'Provider keys and settings are encrypted and synced.',
          );
          return;
        } on GoogleDriveException catch (error) {
          if (error.status != 412 || attempt == 2) rethrow;
        }
      }
      throw StateError('The encrypted settings vault changed repeatedly.');
    } on SettingsVaultAuthenticationException {
      _status = SettingsVaultStatus(
        state: SettingsVaultState.error,
        vaultId: state.vaultId,
        message:
            'The encrypted vault could not be authenticated. It was not overwritten.',
      );
      rethrow;
    } on SettingsVaultFormatException catch (error) {
      _status = SettingsVaultStatus(
        state: SettingsVaultState.error,
        vaultId: state.vaultId,
        lastSyncedAt: _status.lastSyncedAt,
        message: error.message,
      );
      rethrow;
    } on Object catch (error) {
      _status = SettingsVaultStatus(
        state: SettingsVaultState.pending,
        vaultId: state.vaultId,
        lastSyncedAt: _status.lastSyncedAt,
        message: _safeMessage(error),
      );
      rethrow;
    } finally {
      key.destroy();
    }
  }

  Future<void> changePassphrase(String newPassphrase) => _serialized(() async {
    final state = await _requireState();
    _requireRemote();
    if (!state.hasCachedKey) {
      throw StateError('Unlock the encrypted settings vault first.');
    }
    final key = _cachedKey(state);
    try {
      for (var attempt = 0; attempt < 3; attempt += 1) {
        final document = await _requireDocument(refresh: true);
        final envelope = _decodeDocument(document);
        if (envelope.vaultId != state.vaultId) {
          throw StateError('The Google Drive settings vault has changed.');
        }
        final rewrapped = await _codec.rewrap(envelope, key, newPassphrase);
        try {
          _remoteDocument = await _remote.write(
            Uint8List.fromList(utf8.encode(rewrapped.encode())),
            expectedEtag: document.etag,
          );
          _status = SettingsVaultStatus(
            state: SettingsVaultState.ready,
            vaultId: state.vaultId,
            lastSyncedAt: _now(),
            message: 'Sync passphrase changed on Google Drive.',
          );
          return;
        } on GoogleDriveException catch (error) {
          if (error.status != 412 || attempt == 2) rethrow;
        }
      }
      throw StateError('The encrypted settings vault changed repeatedly.');
    } on Object catch (error) {
      _status = SettingsVaultStatus(
        state: SettingsVaultState.pending,
        vaultId: state.vaultId,
        lastSyncedAt: _status.lastSyncedAt,
        message: _safeMessage(error),
      );
      rethrow;
    } finally {
      key.destroy();
    }
  });

  Future<void> forgetCachedUnlock() => _serialized(() async {
    final state = await _requireState();
    final vaultId = state.vaultId;
    state
      ..vaultId = ''
      ..dataEncryptionKey = '';
    await _persistState(state);
    _status = SettingsVaultStatus(
      state: _remote.isConnected
          ? SettingsVaultState.locked
          : SettingsVaultState.driveDisconnected,
      vaultId: vaultId,
      lastSyncedAt: _status.lastSyncedAt,
      message: _remote.isConnected
          ? 'Cached unlock removed. Local provider keys were kept.'
          : 'Cached unlock removed. Local provider keys were kept.',
      localCredentialCount: _localCredentialCount(state),
      hasLocalPreferences: state.preferenceFields.isNotEmpty,
    );
  });

  Future<void> _acceptUnlocked(
    SettingsVaultRemoteDocument document,
    SettingsVaultEnvelope envelope,
    VaultPayload remotePayload,
    SecretKeyData key,
  ) async {
    final state = await _requireState();
    final merged = mergeVaultPayloads(state.payload, remotePayload);
    state
      ..vaultId = envelope.vaultId
      ..dataEncryptionKey = _encodeKey(key.bytes);
    await _applyPayload(state, merged);
    _remoteDocument = document;
    if (merged.encode() != remotePayload.encode()) {
      final updated = await _codec.updatePayload(envelope, key, merged);
      try {
        _remoteDocument = await _remote.write(
          Uint8List.fromList(utf8.encode(updated.encode())),
          expectedEtag: document.etag,
        );
      } on GoogleDriveException catch (error) {
        if (error.status != 412) rethrow;
        _status = SettingsVaultStatus(
          state: SettingsVaultState.pending,
          vaultId: state.vaultId,
          message: 'Unlocked; another encrypted sync is pending.',
        );
        return;
      }
    }
    _status = SettingsVaultStatus(
      state: SettingsVaultState.ready,
      vaultId: state.vaultId,
      lastSyncedAt: _now(),
      message: 'Provider keys and settings are encrypted and synced.',
    );
  }

  Future<void> _applyPayload(
    _DeviceVaultState state,
    VaultPayload payload,
  ) async {
    state
      ..credentials = Map<String, VaultCredentialRecord>.from(
        payload.credentials,
      )
      ..preferenceFields = Map<String, VaultPreferenceFieldRecord>.from(
        payload.preferenceFields,
      );
    await _persistState(state);
    final current = await _delegate.read();
    final preferences = payload.preferences;
    await _delegate.write(
      _withoutCredentials(
        preferences == null
            ? current
            : current.copyWith(
                preferences: AppPreferences.fromJson(preferences.value),
                preferencesUpdatedAt: preferences.updatedAt,
              ),
      ),
    );
  }

  Future<_DeviceVaultState?> _ensureState(StoredData data) async {
    if (_stateLoaded) {
      final state = _state;
      if (state != null) {
        var changed = false;
        if (_containsCredentials(data)) {
          _captureLegacyCredentials(state, data);
          changed = true;
        }
        if (jsonEncode(_resolvedPreferenceJson(state)) !=
            jsonEncode(data.preferences.toJson())) {
          final currentPreferences = state.preferences;
          final candidateUpdatedAt = data.preferencesUpdatedAt;
          if (currentPreferences == null && !_hasLocalPreferences(data)) {
            // A fresh install's untouched defaults are not an edit and must
            // not outrank preferences already stored in a remote vault.
          } else if (currentPreferences == null ||
              (candidateUpdatedAt != null &&
                  candidateUpdatedAt.isAfter(currentPreferences.updatedAt))) {
            _capturePreferenceChanges(
              state,
              data.preferences.toJson(),
              base: _resolvedPreferenceJson(state),
              updatedAt:
                  candidateUpdatedAt ??
                  _nextTimestamp(currentPreferences?.updatedAt),
            );
            changed = true;
          } else {
            await _delegate.write(
              _withoutCredentials(
                data.copyWith(
                  preferences: AppPreferences.fromJson(
                    _resolvedPreferenceJson(state),
                  ),
                  preferencesUpdatedAt: currentPreferences.updatedAt,
                ),
              ),
            );
          }
        }
        if (changed) await _persistState(state);
        if (_containsCredentials(data)) {
          await _delegate.write(_withoutCredentials(data));
        }
      }
      return state;
    }
    _stateLoaded = true;
    try {
      final encoded = await _secureStore.read(_secureStateKey);
      final state = encoded == null
          ? _DeviceVaultState(deviceId: _randomId())
          : _DeviceVaultState.decode(encoded);
      _state = state;
      var changed = encoded == null;
      if (_containsCredentials(data)) {
        _captureLegacyCredentials(state, data);
        changed = true;
      }
      if (state.preferences == null && _hasLocalPreferences(data)) {
        _capturePreferenceChanges(
          state,
          data.preferences.toJson(),
          base: const AppPreferences().toJson(),
          updatedAt: data.preferencesUpdatedAt ?? _now(),
        );
        changed = true;
      }
      if (changed) await _persistState(state);
      if (_containsCredentials(data)) {
        await _delegate.write(_withoutCredentials(data));
      }
      return state;
    } on Object {
      _state = null;
      _status = SettingsVaultStatus(
        state: SettingsVaultState.error,
        message:
            'Secure settings on this device could not be opened. They were not overwritten.',
      );
      return null;
    }
  }

  Future<_DeviceVaultState> _requireState() async {
    final state = await _ensureState(await _delegate.read());
    if (state == null) {
      throw StateError('Secure settings on this device are unavailable.');
    }
    return state;
  }

  bool _captureChanges(
    _DeviceVaultState state,
    StoredData data,
    StoredData current,
  ) {
    var changed = false;
    final nextKeys = _normalizedKeys(data);
    final providers = <String>{...state.credentials.keys, ...nextKeys.keys};
    for (final provider in providers) {
      final previous = state.credentials[provider];
      final next = nextKeys[provider];
      if (previous?.value == next) continue;
      state.credentials[provider] = VaultCredentialRecord(
        value: next,
        updatedAt: _nextTimestamp(previous?.updatedAt),
        deviceId: state.deviceId,
      );
      changed = true;
    }
    final preferencesJson = data.preferences.toJson();
    if ((state.preferences != null || _hasLocalPreferences(data)) &&
        jsonEncode(_resolvedPreferenceJson(state)) !=
            jsonEncode(preferencesJson)) {
      _capturePreferenceChanges(
        state,
        preferencesJson,
        base: state.preferences == null
            ? current.preferences.toJson()
            : _resolvedPreferenceJson(state),
        updatedAt: _nextTimestamp(state.preferences?.updatedAt),
      );
      changed = true;
    }
    return changed;
  }

  void _captureLegacyCredentials(_DeviceVaultState state, StoredData data) {
    final now = _now();
    for (final entry in _normalizedKeys(data).entries) {
      if (state.credentials[entry.key]?.value == entry.value) continue;
      state.credentials[entry.key] = VaultCredentialRecord(
        value: entry.value,
        updatedAt: now,
        deviceId: state.deviceId,
      );
    }
  }

  void _capturePreferenceChanges(
    _DeviceVaultState state,
    Map<String, Object?> next, {
    required Map<String, Object?> base,
    required DateTime updatedAt,
  }) {
    final fields = <String>{...base.keys, ...next.keys};
    for (final field in fields) {
      final previous = state.preferenceFields[field];
      final baseValue = base[field];
      final nextValue = next[field];
      if (jsonEncode(baseValue) == jsonEncode(nextValue)) continue;
      if (jsonEncode(previous?.value) == jsonEncode(nextValue)) continue;
      state.preferenceFields[field] = VaultPreferenceFieldRecord(
        value: nextValue,
        updatedAt: updatedAt,
        deviceId: state.deviceId,
      );
    }
  }

  Future<void> _persistState(_DeviceVaultState state) =>
      _secureStore.write(_secureStateKey, state.encode());

  Future<SettingsVaultRemoteDocument> _requireDocument({
    bool refresh = false,
  }) async {
    _requireRemote();
    final document = refresh || _remoteDocument == null
        ? await _remote.read()
        : _remoteDocument;
    if (document == null) {
      _status = const SettingsVaultStatus(
        state: SettingsVaultState.setupRequired,
        message: 'Create an encrypted settings vault first.',
      );
      throw StateError('No encrypted settings vault exists on Google Drive.');
    }
    _remoteDocument = document;
    return document;
  }

  void _requireRemote() {
    if (!_remote.isConnected) {
      throw StateError('Connect Google Drive before syncing secure settings.');
    }
  }

  SettingsVaultEnvelope _decodeDocument(SettingsVaultRemoteDocument document) =>
      SettingsVaultEnvelope.decode(utf8.decode(document.bytes));

  SecretKeyData _cachedKey(_DeviceVaultState state) {
    final bytes = _decodeKey(state.dataEncryptionKey);
    return SecretKeyData(
      bytes,
      overwriteWhenDestroyed: true,
      debugLabel: 'Clawnsole cached settings vault DEK',
    );
  }

  String _encodeKey(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  Uint8List _decodeKey(String value) {
    try {
      final padded = value.padRight((value.length + 3) ~/ 4 * 4, '=');
      final bytes = base64Url.decode(padded);
      if (bytes.length != 32 || _encodeKey(bytes) != value) {
        throw const FormatException();
      }
      return Uint8List.fromList(bytes);
    } on Object {
      throw StateError('The cached settings vault key is invalid.');
    }
  }

  StoredData _withCredentials(StoredData data, _DeviceVaultState state) {
    final keys = <String, String>{
      for (final entry in state.credentials.entries)
        if (entry.value.value != null) entry.key: entry.value.value!,
    };
    return data.copyWith(apiKey: keys['bfl'] ?? '', apiKeys: keys);
  }

  StoredData _withoutCredentials(StoredData data) =>
      data.copyWith(apiKey: '', apiKeys: const <String, String>{});

  Map<String, String> _normalizedKeys(StoredData data) {
    final keys = <String, String>{
      for (final entry in data.apiKeys.entries)
        if (entry.value.trim().isNotEmpty) entry.key: entry.value.trim(),
    };
    if (data.apiKey.trim().isNotEmpty) keys['bfl'] = data.apiKey.trim();
    return keys;
  }

  bool _containsCredentials(StoredData data) =>
      data.apiKey.trim().isNotEmpty ||
      data.apiKeys.values.any((value) => value.trim().isNotEmpty);

  bool _hasLocalPreferences(StoredData data) =>
      data.preferencesUpdatedAt != null ||
      jsonEncode(data.preferences.toJson()) !=
          jsonEncode(const AppPreferences().toJson());

  Map<String, Object?> _resolvedPreferenceJson(_DeviceVaultState state) =>
      AppPreferences.fromJson(state.preferences?.value ?? const {}).toJson();

  int _localCredentialCount(_DeviceVaultState? state) =>
      state?.credentials.values.where((record) => !record.isDeleted).length ??
      0;

  DateTime _now() => _clock().toUtc();

  DateTime _nextTimestamp(DateTime? previous) {
    final now = _now();
    if (previous == null || now.isAfter(previous)) return now;
    return previous.add(const Duration(microseconds: 1));
  }

  String _randomId() =>
      'device-${base64Url.encode(List<int>.generate(24, (_) => _random.nextInt(256))).replaceAll('=', '')}';

  String _safeMessage(Object error) {
    if (error is StateError) return error.message;
    if (error is GoogleDriveException) return error.message;
    return 'Encrypted settings sync failed. Your local settings were kept.';
  }

  @override
  Future<void> delete() => _serialized(() async {
    if (_remote.isConnected) await _remote.delete();
    await _delegate.delete();
    await _secureStore.delete(_secureStateKey);
    _state = null;
    _stateLoaded = false;
    _remoteDocument = null;
    _status = const SettingsVaultStatus(
      state: SettingsVaultState.driveDisconnected,
    );
  });

  @override
  Future<AssetReference> writeAsset(
    Uint8List bytes, {
    required String label,
    required String contentType,
    LibraryStorage storage = LibraryStorage.local,
  }) => _delegate.writeAsset(
    bytes,
    label: label,
    contentType: contentType,
    storage: storage,
  );

  @override
  Future<AssetReference?> persistSource(
    String source, {
    required String label,
    AssetReference? retained,
    LibraryStorage storage = LibraryStorage.local,
  }) => _delegate.persistSource(
    source,
    label: label,
    retained: retained,
    storage: storage,
  );

  @override
  Future<Uint8List> readAsset(AssetReference reference) =>
      _delegate.readAsset(reference);

  @override
  Future<Uri> assetUri(AssetReference reference) =>
      _delegate.assetUri(reference);

  @override
  Future<void> pruneAssets(
    List<Generation> generations, [
    List<SavedReference> savedReferences = const <SavedReference>[],
  ]) => _delegate.pruneAssets(generations, savedReferences);

  @override
  Future<StorageStats> stats(int records) => _delegate.stats(records);
}

class _DeviceVaultState {
  _DeviceVaultState({
    required this.deviceId,
    Map<String, VaultCredentialRecord>? credentials,
    Map<String, VaultPreferenceFieldRecord>? preferenceFields,
    VaultPreferencesRecord? preferences,
    this.vaultId = '',
    this.dataEncryptionKey = '',
  }) : credentials = credentials ?? <String, VaultCredentialRecord>{},
       preferenceFields = Map<String, VaultPreferenceFieldRecord>.from(
         preferenceFields?.isNotEmpty == true
             ? preferenceFields!
             : VaultPayload(preferences: preferences).preferenceFields,
       );

  final String deviceId;
  Map<String, VaultCredentialRecord> credentials;
  Map<String, VaultPreferenceFieldRecord> preferenceFields;
  String vaultId;
  String dataEncryptionKey;

  bool get hasCachedKey => vaultId.isNotEmpty && dataEncryptionKey.isNotEmpty;

  VaultPreferencesRecord? get preferences =>
      VaultPayload(preferenceFields: preferenceFields).preferences;

  VaultPayload get payload => VaultPayload(
    credentials: credentials,
    preferenceFields: preferenceFields,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'version': _secureStateVersion,
    'deviceId': deviceId,
    'credentials': <String, Object?>{
      for (final provider in (credentials.keys.toList()..sort()))
        provider: credentials[provider]!.toJson(),
    },
    if (preferences != null) 'preferences': preferences!.toJson(),
    if (preferenceFields.isNotEmpty)
      'preferenceFields': <String, Object?>{
        for (final field in (preferenceFields.keys.toList()..sort()))
          field: preferenceFields[field]!.toJson(),
      },
    if (vaultId.isNotEmpty) 'vaultId': vaultId,
    if (dataEncryptionKey.isNotEmpty) 'dataEncryptionKey': dataEncryptionKey,
  };

  String encode() => jsonEncode(toJson());

  factory _DeviceVaultState.decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<Object?, Object?>) {
      throw const FormatException('Secure settings state is invalid.');
    }
    final json = decoded.map((key, value) => MapEntry(key.toString(), value));
    if (json['version'] != _secureStateVersion) {
      throw const FormatException('Secure settings state is unsupported.');
    }
    final rawCredentials = json['credentials'];
    if (rawCredentials is! Map<Object?, Object?>) {
      throw const FormatException('Secure credentials are invalid.');
    }
    final rawPreferenceFields = json['preferenceFields'];
    if (rawPreferenceFields != null &&
        rawPreferenceFields is! Map<Object?, Object?>) {
      throw const FormatException('Secure preference fields are invalid.');
    }
    return _DeviceVaultState(
      deviceId: json['deviceId'] as String,
      credentials: <String, VaultCredentialRecord>{
        for (final entry in rawCredentials.entries)
          entry.key.toString(): VaultCredentialRecord.fromJson(
            (entry.value as Map<Object?, Object?>).map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          ),
      },
      preferences: json['preferences'] is Map<Object?, Object?>
          ? VaultPreferencesRecord.fromJson(
              (json['preferences']! as Map<Object?, Object?>).map(
                (key, value) => MapEntry(key.toString(), value),
              ),
            )
          : null,
      preferenceFields: rawPreferenceFields is Map<Object?, Object?>
          ? <String, VaultPreferenceFieldRecord>{
              for (final entry in rawPreferenceFields.entries)
                entry.key.toString(): VaultPreferenceFieldRecord.fromJson(
                  (entry.value as Map<Object?, Object?>).map(
                    (key, value) => MapEntry(key.toString(), value),
                  ),
                ),
            }
          : null,
      vaultId: json['vaultId'] as String? ?? '',
      dataEncryptionKey: json['dataEncryptionKey'] as String? ?? '',
    );
  }
}
