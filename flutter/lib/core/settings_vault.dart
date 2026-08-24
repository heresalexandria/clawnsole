import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

const settingsVaultFormat = 'app.clawnsole.settings-vault';
const settingsVaultVersion = 1;
const settingsVaultPayloadVersion = 1;

const settingsVaultDefaultMemoryKiB = 64 * 1024;
const settingsVaultDefaultIterations = 3;
const settingsVaultDefaultParallelism = 1;

const settingsVaultMinimumMemoryKiB = 19 * 1024;
const settingsVaultMaximumMemoryKiB = 256 * 1024;
const settingsVaultMaximumIterations = 10;
const settingsVaultMaximumParallelism = 4;
const settingsVaultMaximumEncodedBytes = 1024 * 1024;
const settingsVaultMaximumPayloadBytes = 512 * 1024;

const _argon2Version = 19;
const _saltBytes = 16;
const _keyBytes = 32;
const _nonceBytes = 24;
const _macBytes = 16;
const _maximumPassphraseBytes = 1024;
const _maximumCredentialBytes = 8192;
const _maximumDeviceIdBytes = 128;
const _maximumProviderIdBytes = 64;
const _maximumJsonDepth = 32;
const _xchacha20Poly1305 = 'xchacha20-poly1305';

/// A malformed, unsupported, or unreasonably large vault envelope.
class SettingsVaultFormatException implements Exception {
  const SettingsVaultFormatException(this.message);

  final String message;

  @override
  String toString() => 'SettingsVaultFormatException: $message';
}

/// Authentication failed without distinguishing a wrong key from tampering.
class SettingsVaultAuthenticationException implements Exception {
  const SettingsVaultAuthenticationException([
    this.message = 'The settings vault could not be authenticated.',
  ]);

  final String message;

  @override
  String toString() => 'SettingsVaultAuthenticationException: $message';
}

/// Tunable Argon2id work factors written into each passphrase key slot.
///
/// The defaults deliberately use 64 MiB, three passes, and one lane so a vault
/// created on desktop remains practical to unlock on a mobile device.
class SettingsVaultKdfParameters {
  const SettingsVaultKdfParameters({
    this.memoryKiB = settingsVaultDefaultMemoryKiB,
    this.iterations = settingsVaultDefaultIterations,
    this.parallelism = settingsVaultDefaultParallelism,
  });

  final int memoryKiB;
  final int iterations;
  final int parallelism;

  void validate() {
    if (memoryKiB < settingsVaultMinimumMemoryKiB ||
        memoryKiB > settingsVaultMaximumMemoryKiB) {
      throw const SettingsVaultFormatException(
        'The Argon2id memory cost is outside the supported range.',
      );
    }
    if (iterations < 1 || iterations > settingsVaultMaximumIterations) {
      throw const SettingsVaultFormatException(
        'The Argon2id iteration count is outside the supported range.',
      );
    }
    if (parallelism < 1 || parallelism > settingsVaultMaximumParallelism) {
      throw const SettingsVaultFormatException(
        'The Argon2id parallelism is outside the supported range.',
      );
    }
  }
}

/// A last-writer-wins provider credential register.
///
/// A null [value] is a tombstone. Tombstones are retained so a stale device
/// cannot resurrect a provider key that another device deleted.
class VaultCredentialRecord {
  VaultCredentialRecord({
    required this.value,
    DateTime? createdAt,
    required DateTime updatedAt,
    required this.deviceId,
  }) : createdAt = (createdAt ?? updatedAt).toUtc(),
       updatedAt = updatedAt.toUtc() {
    _validateDeviceId(deviceId);
    if (value != null) {
      if (value!.isEmpty ||
          utf8.encode(value!).length > _maximumCredentialBytes) {
        throw ArgumentError('Invalid credential length.', 'value');
      }
    }
  }

  final String? value;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String deviceId;

  bool get isDeleted => value == null;

  Map<String, Object?> toJson() => <String, Object?>{
    'value': value,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'deviceId': deviceId,
  };

  factory VaultCredentialRecord.fromJson(Map<String, Object?> json) {
    if (!json.containsKey('value') ||
        (json['value'] != null && json['value'] is! String)) {
      throw const SettingsVaultFormatException(
        'A credential record has an invalid value.',
      );
    }
    return VaultCredentialRecord(
      value: json['value'] as String?,
      createdAt: _optionalDate(json['createdAt']),
      updatedAt: _requiredDate(json['updatedAt'], 'credential updatedAt'),
      deviceId: _requiredString(json['deviceId'], 'credential deviceId'),
    );
  }
}

/// A whole-preferences last-writer-wins register.
class VaultPreferencesRecord {
  VaultPreferencesRecord({
    required Map<String, Object?> value,
    DateTime? createdAt,
    required DateTime updatedAt,
    required this.deviceId,
  }) : value = _copyJsonMap(value),
       createdAt = (createdAt ?? updatedAt).toUtc(),
       updatedAt = updatedAt.toUtc() {
    _validateDeviceId(deviceId);
  }

  final Map<String, Object?> value;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String deviceId;

  Map<String, Object?> toJson() => <String, Object?>{
    'value': value,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'deviceId': deviceId,
  };

  factory VaultPreferencesRecord.fromJson(Map<String, Object?> json) {
    final value = json['value'];
    if (value is! Map<Object?, Object?>) {
      throw const SettingsVaultFormatException(
        'The preferences record has an invalid value.',
      );
    }
    return VaultPreferencesRecord(
      value: _stringMap(value, 'preferences value'),
      createdAt: _optionalDate(json['createdAt']),
      updatedAt: _requiredDate(json['updatedAt'], 'preferences updatedAt'),
      deviceId: _requiredString(json['deviceId'], 'preferences deviceId'),
    );
  }
}

/// The encrypted contents of a settings vault.
class VaultPayload {
  VaultPayload({
    Map<String, VaultCredentialRecord> credentials =
        const <String, VaultCredentialRecord>{},
    this.preferences,
  }) : credentials = Map<String, VaultCredentialRecord>.unmodifiable(
         _validatedCredentials(credentials),
       );

  final Map<String, VaultCredentialRecord> credentials;
  final VaultPreferencesRecord? preferences;

  Map<String, Object?> toJson() {
    final providers = credentials.keys.toList()..sort();
    return <String, Object?>{
      'version': settingsVaultPayloadVersion,
      'credentials': <String, Object?>{
        for (final provider in providers)
          provider: credentials[provider]!.toJson(),
      },
      if (preferences != null) 'preferences': preferences!.toJson(),
    };
  }

  String encode() {
    final encoded = jsonEncode(toJson());
    if (utf8.encode(encoded).length > settingsVaultMaximumPayloadBytes) {
      throw const SettingsVaultFormatException(
        'The settings vault payload is too large.',
      );
    }
    return encoded;
  }

  factory VaultPayload.decode(String source) {
    if (source.length > settingsVaultMaximumPayloadBytes ||
        utf8.encode(source).length > settingsVaultMaximumPayloadBytes) {
      throw const SettingsVaultFormatException(
        'The settings vault payload is too large.',
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const SettingsVaultFormatException(
        'The settings vault payload is not valid JSON.',
      );
    }
    if (decoded is! Map<Object?, Object?>) {
      throw const SettingsVaultFormatException(
        'The settings vault payload must be a JSON object.',
      );
    }
    final json = _stringMap(decoded, 'payload');
    if (json['version'] != settingsVaultPayloadVersion) {
      throw const SettingsVaultFormatException(
        'The settings vault payload version is not supported.',
      );
    }
    final rawCredentials = json['credentials'];
    if (rawCredentials is! Map<Object?, Object?>) {
      throw const SettingsVaultFormatException(
        'The settings vault credentials are invalid.',
      );
    }
    final credentials = <String, VaultCredentialRecord>{};
    for (final entry in rawCredentials.entries) {
      final provider = entry.key;
      if (provider is! String) {
        throw const SettingsVaultFormatException(
          'A settings vault provider identifier is invalid.',
        );
      }
      _validateProviderId(provider);
      if (entry.value is! Map<Object?, Object?>) {
        throw const SettingsVaultFormatException(
          'A settings vault credential record is invalid.',
        );
      }
      credentials[provider] = VaultCredentialRecord.fromJson(
        _stringMap(entry.value! as Map<Object?, Object?>, 'credential record'),
      );
    }
    final rawPreferences = json['preferences'];
    return VaultPayload(
      credentials: credentials,
      preferences: rawPreferences == null
          ? null
          : rawPreferences is Map<Object?, Object?>
          ? VaultPreferencesRecord.fromJson(
              _stringMap(rawPreferences, 'preferences record'),
            )
          : throw const SettingsVaultFormatException(
              'The settings vault preferences record is invalid.',
            ),
    );
  }
}

/// Deterministically merges two independently edited vault payloads.
VaultPayload mergeVaultPayloads(VaultPayload left, VaultPayload right) {
  final providers = <String>{
    ...left.credentials.keys,
    ...right.credentials.keys,
  };
  final credentials = <String, VaultCredentialRecord>{};
  for (final provider in providers) {
    final leftRecord = left.credentials[provider];
    final rightRecord = right.credentials[provider];
    credentials[provider] = switch ((leftRecord, rightRecord)) {
      (final VaultCredentialRecord value, null) => value,
      (null, final VaultCredentialRecord value) => value,
      (final VaultCredentialRecord first, final VaultCredentialRecord second) =>
        _newerCredential(first, second),
      _ => throw StateError('A merged provider record is missing.'),
    };
  }
  return VaultPayload(
    credentials: credentials,
    preferences: _newerPreferences(left.preferences, right.preferences),
  );
}

class SettingsVaultCiphertext {
  SettingsVaultCiphertext({
    required this.algorithm,
    required Uint8List nonce,
    required Uint8List ciphertext,
    required Uint8List mac,
  }) : nonce = Uint8List.fromList(nonce),
       ciphertext = Uint8List.fromList(ciphertext),
       mac = Uint8List.fromList(mac) {
    if (algorithm != _xchacha20Poly1305 ||
        this.nonce.length != _nonceBytes ||
        this.mac.length != _macBytes ||
        this.ciphertext.length > settingsVaultMaximumPayloadBytes) {
      throw const SettingsVaultFormatException(
        'The settings vault ciphertext is invalid.',
      );
    }
  }

  final String algorithm;
  final Uint8List nonce;
  final Uint8List ciphertext;
  final Uint8List mac;

  Map<String, Object?> toJson() => <String, Object?>{
    'algorithm': algorithm,
    'nonce': _encodeBytes(nonce),
    'ciphertext': _encodeBytes(ciphertext),
    'mac': _encodeBytes(mac),
  };

  factory SettingsVaultCiphertext.fromJson(
    Map<String, Object?> json, {
    required int maximumCiphertextBytes,
    int? exactCiphertextBytes,
  }) {
    final algorithm = _requiredString(json['algorithm'], 'cipher algorithm');
    if (algorithm != _xchacha20Poly1305) {
      throw const SettingsVaultFormatException(
        'The settings vault cipher is not supported.',
      );
    }
    return SettingsVaultCiphertext(
      algorithm: algorithm,
      nonce: _decodeBytes(
        _requiredString(json['nonce'], 'cipher nonce'),
        name: 'cipher nonce',
        exactBytes: _nonceBytes,
      ),
      ciphertext: _decodeBytes(
        _requiredString(json['ciphertext'], 'ciphertext'),
        name: 'ciphertext',
        maximumBytes: maximumCiphertextBytes,
        exactBytes: exactCiphertextBytes,
      ),
      mac: _decodeBytes(
        _requiredString(json['mac'], 'cipher MAC'),
        name: 'cipher MAC',
        exactBytes: _macBytes,
      ),
    );
  }
}

class SettingsVaultPassphraseSlot {
  SettingsVaultPassphraseSlot({
    required this.type,
    required this.kdfAlgorithm,
    required this.kdfVersion,
    required this.parameters,
    required Uint8List salt,
    required this.keyBytes,
    required this.wrappedKey,
  }) : salt = Uint8List.fromList(salt) {
    parameters.validate();
    if (type != 'passphrase' ||
        kdfAlgorithm != 'argon2id' ||
        kdfVersion != _argon2Version ||
        this.salt.length != _saltBytes ||
        keyBytes != _keyBytes ||
        wrappedKey.ciphertext.length != _keyBytes) {
      throw const SettingsVaultFormatException(
        'The settings vault passphrase slot is invalid.',
      );
    }
  }

  final String type;
  final String kdfAlgorithm;
  final int kdfVersion;
  final SettingsVaultKdfParameters parameters;
  final Uint8List salt;
  final int keyBytes;
  final SettingsVaultCiphertext wrappedKey;

  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    'kdf': <String, Object?>{
      'algorithm': kdfAlgorithm,
      'version': kdfVersion,
      'salt': _encodeBytes(salt),
      'memoryKiB': parameters.memoryKiB,
      'iterations': parameters.iterations,
      'parallelism': parameters.parallelism,
      'keyBytes': keyBytes,
    },
    'wrappedKey': wrappedKey.toJson(),
  };

  factory SettingsVaultPassphraseSlot.fromJson(Map<String, Object?> json) {
    final kdf = _requiredMap(json['kdf'], 'passphrase KDF');
    final parameters = SettingsVaultKdfParameters(
      memoryKiB: _requiredInt(kdf['memoryKiB'], 'Argon2id memory'),
      iterations: _requiredInt(kdf['iterations'], 'Argon2id iterations'),
      parallelism: _requiredInt(kdf['parallelism'], 'Argon2id parallelism'),
    );
    parameters.validate();
    return SettingsVaultPassphraseSlot(
      type: _requiredString(json['type'], 'key slot type'),
      kdfAlgorithm: _requiredString(kdf['algorithm'], 'KDF algorithm'),
      kdfVersion: _requiredInt(kdf['version'], 'KDF version'),
      parameters: parameters,
      salt: _decodeBytes(
        _requiredString(kdf['salt'], 'KDF salt'),
        name: 'KDF salt',
        exactBytes: _saltBytes,
      ),
      keyBytes: _requiredInt(kdf['keyBytes'], 'derived key length'),
      wrappedKey: SettingsVaultCiphertext.fromJson(
        _requiredMap(json['wrappedKey'], 'wrapped key'),
        maximumCiphertextBytes: _keyBytes,
        exactCiphertextBytes: _keyBytes,
      ),
    );
  }
}

class SettingsVaultRecoverySlot {
  SettingsVaultRecoverySlot({
    required this.type,
    required this.encoding,
    required this.keyBytes,
    required this.wrappedKey,
  }) {
    if (type != 'recovery-code' ||
        encoding != 'base64url' ||
        keyBytes != _keyBytes ||
        wrappedKey.ciphertext.length != _keyBytes) {
      throw const SettingsVaultFormatException(
        'The settings vault recovery slot is invalid.',
      );
    }
  }

  final String type;
  final String encoding;
  final int keyBytes;
  final SettingsVaultCiphertext wrappedKey;

  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    'encoding': encoding,
    'keyBytes': keyBytes,
    'wrappedKey': wrappedKey.toJson(),
  };

  factory SettingsVaultRecoverySlot.fromJson(Map<String, Object?> json) =>
      SettingsVaultRecoverySlot(
        type: _requiredString(json['type'], 'recovery slot type'),
        encoding: _requiredString(json['encoding'], 'recovery code encoding'),
        keyBytes: _requiredInt(json['keyBytes'], 'recovery key length'),
        wrappedKey: SettingsVaultCiphertext.fromJson(
          _requiredMap(json['wrappedKey'], 'recovery wrapped key'),
          maximumCiphertextBytes: _keyBytes,
          exactCiphertextBytes: _keyBytes,
        ),
      );
}

/// The public, JSON-serializable encrypted vault envelope.
class SettingsVaultEnvelope {
  SettingsVaultEnvelope({
    required this.format,
    required this.version,
    required this.vaultId,
    required this.passphraseSlot,
    required this.recoverySlot,
    required this.payload,
  }) {
    if (format != settingsVaultFormat || version != settingsVaultVersion) {
      throw const SettingsVaultFormatException(
        'The settings vault format or version is not supported.',
      );
    }
    _decodeBytes(vaultId, name: 'vault id', exactBytes: 16);
  }

  final String format;
  final int version;
  final String vaultId;
  final SettingsVaultPassphraseSlot passphraseSlot;
  final SettingsVaultRecoverySlot recoverySlot;
  final SettingsVaultCiphertext payload;

  Map<String, Object?> toJson() => <String, Object?>{
    'format': format,
    'version': version,
    'vaultId': vaultId,
    'passphraseSlot': passphraseSlot.toJson(),
    'recoverySlot': recoverySlot.toJson(),
    'payload': payload.toJson(),
  };

  String encode() {
    final encoded = jsonEncode(toJson());
    if (utf8.encode(encoded).length > settingsVaultMaximumEncodedBytes) {
      throw const SettingsVaultFormatException(
        'The settings vault envelope is too large.',
      );
    }
    return encoded;
  }

  factory SettingsVaultEnvelope.decode(String source) {
    if (source.length > settingsVaultMaximumEncodedBytes ||
        utf8.encode(source).length > settingsVaultMaximumEncodedBytes) {
      throw const SettingsVaultFormatException(
        'The settings vault envelope is too large.',
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const SettingsVaultFormatException(
        'The settings vault envelope is not valid JSON.',
      );
    }
    if (decoded is! Map<Object?, Object?>) {
      throw const SettingsVaultFormatException(
        'The settings vault envelope must be a JSON object.',
      );
    }
    final json = _stringMap(decoded, 'vault envelope');
    final format = _requiredString(json['format'], 'vault format');
    final version = _requiredInt(json['version'], 'vault version');
    if (format != settingsVaultFormat || version != settingsVaultVersion) {
      throw const SettingsVaultFormatException(
        'The settings vault format or version is not supported.',
      );
    }
    return SettingsVaultEnvelope(
      format: format,
      version: version,
      vaultId: _requiredString(json['vaultId'], 'vault id'),
      passphraseSlot: SettingsVaultPassphraseSlot.fromJson(
        _requiredMap(json['passphraseSlot'], 'passphrase slot'),
      ),
      recoverySlot: SettingsVaultRecoverySlot.fromJson(
        _requiredMap(json['recoverySlot'], 'recovery slot'),
      ),
      payload: SettingsVaultCiphertext.fromJson(
        _requiredMap(json['payload'], 'encrypted payload'),
        maximumCiphertextBytes: settingsVaultMaximumPayloadBytes,
      ),
    );
  }
}

class CreatedSettingsVault {
  const CreatedSettingsVault({
    required this.envelope,
    required this.dataEncryptionKey,
    required this.recoveryCode,
  });

  final SettingsVaultEnvelope envelope;
  final SecretKeyData dataEncryptionKey;

  /// A canonical base64url encoding of 256 random bits, displayed once.
  final String recoveryCode;
}

class UnlockedSettingsVault {
  const UnlockedSettingsVault({
    required this.payload,
    required this.dataEncryptionKey,
  });

  final VaultPayload payload;
  final SecretKeyData dataEncryptionKey;
}

/// Creates, unlocks, decrypts, updates, and rewraps settings vault envelopes.
class SettingsVaultCodec {
  SettingsVaultCodec({this.kdfParameters = const SettingsVaultKdfParameters()});

  final SettingsVaultKdfParameters kdfParameters;
  final Cipher _cipher = Xchacha20.poly1305Aead();
  final Random _random = Random.secure();

  Future<CreatedSettingsVault> create(
    String passphrase,
    VaultPayload payload,
  ) async {
    _validateNewPassphrase(passphrase);
    kdfParameters.validate();
    final vaultId = _encodeBytes(_randomBytes(16));
    final salt = _randomBytes(_saltBytes);
    final dataEncryptionKey = SecretKeyData.randomWithBuffer(
      Uint8List(_keyBytes),
      random: _random,
      overwriteWhenDestroyed: true,
      debugLabel: 'Clawnsole settings vault DEK',
    );
    SecretKey? wrappingKey;
    SecretKeyData? recoveryKey;
    try {
      wrappingKey = await _deriveWrappingKey(passphrase, salt, kdfParameters);
      recoveryKey = SecretKeyData.randomWithBuffer(
        Uint8List(_keyBytes),
        random: _random,
        overwriteWhenDestroyed: true,
        debugLabel: 'Clawnsole settings vault recovery key',
      );
      final recoveryCode = _encodeBytes(recoveryKey.bytes);
      final placeholderSlot = SettingsVaultPassphraseSlot(
        type: 'passphrase',
        kdfAlgorithm: 'argon2id',
        kdfVersion: _argon2Version,
        parameters: kdfParameters,
        salt: salt,
        keyBytes: _keyBytes,
        wrappedKey: await _encrypt(
          dataEncryptionKey.bytes,
          wrappingKey,
          _wrappingAad(vaultId, kdfParameters, salt),
          maximumPlaintextBytes: _keyBytes,
        ),
      );
      final envelope = SettingsVaultEnvelope(
        format: settingsVaultFormat,
        version: settingsVaultVersion,
        vaultId: vaultId,
        passphraseSlot: placeholderSlot,
        recoverySlot: SettingsVaultRecoverySlot(
          type: 'recovery-code',
          encoding: 'base64url',
          keyBytes: _keyBytes,
          wrappedKey: await _encrypt(
            dataEncryptionKey.bytes,
            recoveryKey,
            _recoveryAad(vaultId),
            maximumPlaintextBytes: _keyBytes,
          ),
        ),
        payload: await _encryptPayload(vaultId, dataEncryptionKey, payload),
      );
      return CreatedSettingsVault(
        envelope: envelope,
        dataEncryptionKey: dataEncryptionKey,
        recoveryCode: recoveryCode,
      );
    } on Object {
      dataEncryptionKey.destroy();
      rethrow;
    } finally {
      wrappingKey?.destroy();
      recoveryKey?.destroy();
    }
  }

  Future<UnlockedSettingsVault> unlock(
    SettingsVaultEnvelope envelope,
    String passphrase,
  ) async {
    _validateUnlockPassphrase(passphrase);
    final slot = envelope.passphraseSlot;
    SecretKey? wrappingKey;
    SecretKeyData? dataEncryptionKey;
    try {
      wrappingKey = await _deriveWrappingKey(
        passphrase,
        slot.salt,
        slot.parameters,
      );
      final bytes = await _decryptBox(
        slot.wrappedKey,
        wrappingKey,
        _wrappingAad(envelope.vaultId, slot.parameters, slot.salt),
      );
      if (bytes.length != _keyBytes) {
        throw const SettingsVaultAuthenticationException();
      }
      dataEncryptionKey = SecretKeyData(
        bytes,
        overwriteWhenDestroyed: true,
        debugLabel: 'Clawnsole settings vault DEK',
      );
      final payload = await decrypt(envelope, dataEncryptionKey);
      return UnlockedSettingsVault(
        payload: payload,
        dataEncryptionKey: dataEncryptionKey,
      );
    } on SettingsVaultAuthenticationException {
      dataEncryptionKey?.destroy();
      rethrow;
    } on Object {
      dataEncryptionKey?.destroy();
      throw const SettingsVaultAuthenticationException();
    } finally {
      wrappingKey?.destroy();
    }
  }

  Future<VaultPayload> decrypt(
    SettingsVaultEnvelope envelope,
    SecretKey dataEncryptionKey,
  ) async {
    try {
      final cleartext = await _decryptBox(
        envelope.payload,
        dataEncryptionKey,
        _payloadAad(envelope.vaultId),
      );
      if (cleartext.length > settingsVaultMaximumPayloadBytes) {
        throw const SettingsVaultFormatException(
          'The settings vault payload is too large.',
        );
      }
      return VaultPayload.decode(utf8.decode(cleartext));
    } on SettingsVaultFormatException {
      rethrow;
    } on Object {
      throw const SettingsVaultAuthenticationException();
    }
  }

  Future<UnlockedSettingsVault> unlockWithRecoveryCode(
    SettingsVaultEnvelope envelope,
    String recoveryCode,
  ) async {
    final recoveryBytes = _decodeBytes(
      recoveryCode,
      name: 'recovery code',
      exactBytes: _keyBytes,
    );
    if (_encodeBytes(recoveryBytes) != recoveryCode) {
      throw const SettingsVaultFormatException(
        'The recovery code is not in canonical base64url form.',
      );
    }
    final recoveryKey = SecretKeyData(
      recoveryBytes,
      overwriteWhenDestroyed: true,
      debugLabel: 'Clawnsole settings vault recovery key',
    );
    SecretKeyData? dataEncryptionKey;
    try {
      final bytes = await _decryptBox(
        envelope.recoverySlot.wrappedKey,
        recoveryKey,
        _recoveryAad(envelope.vaultId),
      );
      if (bytes.length != _keyBytes) {
        throw const SettingsVaultAuthenticationException();
      }
      dataEncryptionKey = SecretKeyData(
        bytes,
        overwriteWhenDestroyed: true,
        debugLabel: 'Clawnsole settings vault DEK',
      );
      final payload = await decrypt(envelope, dataEncryptionKey);
      return UnlockedSettingsVault(
        payload: payload,
        dataEncryptionKey: dataEncryptionKey,
      );
    } on SettingsVaultAuthenticationException {
      dataEncryptionKey?.destroy();
      rethrow;
    } on Object {
      dataEncryptionKey?.destroy();
      throw const SettingsVaultAuthenticationException();
    } finally {
      recoveryKey.destroy();
    }
  }

  Future<SettingsVaultEnvelope> updatePayload(
    SettingsVaultEnvelope envelope,
    SecretKey dataEncryptionKey,
    VaultPayload payload,
  ) async {
    // Never replace the valid ciphertext with data encrypted by a stale or
    // unrelated locally cached key.
    await decrypt(envelope, dataEncryptionKey);
    return SettingsVaultEnvelope(
      format: envelope.format,
      version: envelope.version,
      vaultId: envelope.vaultId,
      passphraseSlot: envelope.passphraseSlot,
      recoverySlot: envelope.recoverySlot,
      payload: await _encryptPayload(
        envelope.vaultId,
        dataEncryptionKey,
        payload,
      ),
    );
  }

  Future<SettingsVaultEnvelope> rewrap(
    SettingsVaultEnvelope envelope,
    SecretKey dataEncryptionKey,
    String newPassphrase,
  ) async {
    _validateNewPassphrase(newPassphrase);
    kdfParameters.validate();
    // Authenticate the caller-supplied DEK before replacing the only key slot.
    await decrypt(envelope, dataEncryptionKey);
    final salt = _randomBytes(_saltBytes);
    SecretKey? wrappingKey;
    try {
      wrappingKey = await _deriveWrappingKey(
        newPassphrase,
        salt,
        kdfParameters,
      );
      final keyBytes = await dataEncryptionKey.extractBytes();
      if (keyBytes.length != _keyBytes) {
        throw ArgumentError.value(
          keyBytes.length,
          'dataEncryptionKey',
          'A settings vault key must contain 32 bytes.',
        );
      }
      return SettingsVaultEnvelope(
        format: envelope.format,
        version: envelope.version,
        vaultId: envelope.vaultId,
        passphraseSlot: SettingsVaultPassphraseSlot(
          type: 'passphrase',
          kdfAlgorithm: 'argon2id',
          kdfVersion: _argon2Version,
          parameters: kdfParameters,
          salt: salt,
          keyBytes: _keyBytes,
          wrappedKey: await _encrypt(
            keyBytes,
            wrappingKey,
            _wrappingAad(envelope.vaultId, kdfParameters, salt),
            maximumPlaintextBytes: _keyBytes,
          ),
        ),
        recoverySlot: envelope.recoverySlot,
        payload: envelope.payload,
      );
    } finally {
      wrappingKey?.destroy();
    }
  }

  Future<SettingsVaultCiphertext> _encryptPayload(
    String vaultId,
    SecretKey key,
    VaultPayload payload,
  ) => _encrypt(
    utf8.encode(payload.encode()),
    key,
    _payloadAad(vaultId),
    maximumPlaintextBytes: settingsVaultMaximumPayloadBytes,
  );

  Future<SettingsVaultCiphertext> _encrypt(
    List<int> cleartext,
    SecretKey key,
    List<int> aad, {
    required int maximumPlaintextBytes,
  }) async {
    if (cleartext.length > maximumPlaintextBytes) {
      throw const SettingsVaultFormatException(
        'The settings vault plaintext is too large.',
      );
    }
    final box = await _cipher.encrypt(
      cleartext,
      secretKey: key,
      nonce: _randomBytes(_nonceBytes),
      aad: aad,
    );
    return SettingsVaultCiphertext(
      algorithm: _xchacha20Poly1305,
      nonce: Uint8List.fromList(box.nonce),
      ciphertext: Uint8List.fromList(box.cipherText),
      mac: Uint8List.fromList(box.mac.bytes),
    );
  }

  Future<List<int>> _decryptBox(
    SettingsVaultCiphertext box,
    SecretKey key,
    List<int> aad,
  ) async {
    try {
      return await _cipher.decrypt(
        SecretBox(box.ciphertext, nonce: box.nonce, mac: Mac(box.mac)),
        secretKey: key,
        aad: aad,
      );
    } on Object {
      throw const SettingsVaultAuthenticationException();
    }
  }

  Future<SecretKeyData> _deriveWrappingKey(
    String passphrase,
    Uint8List salt,
    SettingsVaultKdfParameters parameters,
  ) async {
    parameters.validate();
    final passwordBytes = Uint8List.fromList(utf8.encode(passphrase));
    final algorithm = DartArgon2id(
      parallelism: parameters.parallelism,
      memory: parameters.memoryKiB,
      iterations: parameters.iterations,
      hashLength: _keyBytes,
    );
    final state = algorithm.newState();
    try {
      final bytes = await state.deriveKeyBytes(
        password: passwordBytes,
        nonce: salt,
      );
      return SecretKeyData(
        bytes,
        overwriteWhenDestroyed: true,
        debugLabel: 'Clawnsole settings vault wrapping key',
      );
    } finally {
      passwordBytes.fillRange(0, passwordBytes.length, 0);
      state.tryReleaseMemory();
    }
  }

  Uint8List _randomBytes(int length) => Uint8List.fromList(
    List<int>.generate(length, (_) => _random.nextInt(256)),
  );
}

VaultCredentialRecord _newerCredential(
  VaultCredentialRecord left,
  VaultCredentialRecord right,
) {
  final metadata = _compareRegisterMetadata(
    left.updatedAt,
    left.deviceId,
    right.updatedAt,
    right.deviceId,
  );
  if (metadata != 0) return metadata > 0 ? left : right;
  if (left.isDeleted != right.isDeleted) return left.isDeleted ? left : right;
  return (left.value ?? '').compareTo(right.value ?? '') >= 0 ? left : right;
}

VaultPreferencesRecord? _newerPreferences(
  VaultPreferencesRecord? left,
  VaultPreferencesRecord? right,
) {
  if (left == null) return right;
  if (right == null) return left;
  final metadata = _compareRegisterMetadata(
    left.updatedAt,
    left.deviceId,
    right.updatedAt,
    right.deviceId,
  );
  if (metadata != 0) return metadata > 0 ? left : right;
  return jsonEncode(left.value).compareTo(jsonEncode(right.value)) >= 0
      ? left
      : right;
}

int _compareRegisterMetadata(
  DateTime leftTime,
  String leftDevice,
  DateTime rightTime,
  String rightDevice,
) {
  final time = leftTime.compareTo(rightTime);
  return time != 0 ? time : leftDevice.compareTo(rightDevice);
}

Map<String, VaultCredentialRecord> _validatedCredentials(
  Map<String, VaultCredentialRecord> credentials,
) {
  final result = <String, VaultCredentialRecord>{};
  for (final entry in credentials.entries) {
    _validateProviderId(entry.key);
    result[entry.key] = entry.value;
  }
  return result;
}

void _validateProviderId(String value) {
  if (value.isEmpty ||
      utf8.encode(value).length > _maximumProviderIdBytes ||
      !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(value)) {
    throw const SettingsVaultFormatException(
      'A settings vault provider identifier is invalid.',
    );
  }
}

void _validateDeviceId(String value) {
  if (value.isEmpty ||
      utf8.encode(value).length > _maximumDeviceIdBytes ||
      !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]*$').hasMatch(value)) {
    throw const SettingsVaultFormatException(
      'A settings vault device identifier is invalid.',
    );
  }
}

void _validateNewPassphrase(String passphrase) {
  if (passphrase.runes.length < 12) {
    throw ArgumentError(
      'A sync passphrase must contain at least 12 characters.',
      'passphrase',
    );
  }
  _validateUnlockPassphrase(passphrase);
}

void _validateUnlockPassphrase(String passphrase) {
  final length = utf8.encode(passphrase).length;
  if (length < 1 || length > _maximumPassphraseBytes) {
    throw ArgumentError(
      'The sync passphrase has an invalid encoded length.',
      'passphrase',
    );
  }
}

List<int> _wrappingAad(
  String vaultId,
  SettingsVaultKdfParameters parameters,
  Uint8List salt,
) => utf8.encode(
  '$settingsVaultFormat\n$settingsVaultVersion\n$vaultId\npassphrase\n'
  'argon2id\n$_argon2Version\n${parameters.memoryKiB}\n'
  '${parameters.iterations}\n${parameters.parallelism}\n$_keyBytes\n'
  '${_encodeBytes(salt)}\n$_xchacha20Poly1305',
);

List<int> _payloadAad(String vaultId) => utf8.encode(
  '$settingsVaultFormat\n$settingsVaultVersion\n$vaultId\npayload\n'
  '$_xchacha20Poly1305',
);

List<int> _recoveryAad(String vaultId) => utf8.encode(
  '$settingsVaultFormat\n$settingsVaultVersion\n$vaultId\nrecovery-code\n'
  'base64url\n$_keyBytes\n$_xchacha20Poly1305',
);

String _encodeBytes(List<int> bytes) =>
    base64UrlEncode(bytes).replaceAll('=', '');

Uint8List _decodeBytes(
  String source, {
  required String name,
  int? exactBytes,
  int? maximumBytes,
}) {
  if (source.isEmpty || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(source)) {
    throw SettingsVaultFormatException('The $name is not valid base64url.');
  }
  final limit = exactBytes ?? maximumBytes ?? settingsVaultMaximumPayloadBytes;
  if (source.length > ((limit + 2) ~/ 3) * 4) {
    throw SettingsVaultFormatException('The $name is too large.');
  }
  final remainder = source.length % 4;
  if (remainder == 1) {
    throw SettingsVaultFormatException('The $name is not valid base64url.');
  }
  final padded = '$source${'=' * ((4 - remainder) % 4)}';
  Uint8List bytes;
  try {
    bytes = Uint8List.fromList(base64Url.decode(padded));
  } on FormatException {
    throw SettingsVaultFormatException('The $name is not valid base64url.');
  }
  if ((exactBytes != null && bytes.length != exactBytes) ||
      (maximumBytes != null && bytes.length > maximumBytes)) {
    throw SettingsVaultFormatException('The $name has an invalid length.');
  }
  return bytes;
}

Map<String, Object?> _requiredMap(Object? value, String name) {
  if (value is! Map<Object?, Object?>) {
    throw SettingsVaultFormatException('The $name must be a JSON object.');
  }
  return _stringMap(value, name);
}

Map<String, Object?> _stringMap(Map<Object?, Object?> value, String name) {
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw SettingsVaultFormatException(
        'The $name contains a non-string key.',
      );
    }
    result[entry.key! as String] = entry.value;
  }
  return result;
}

String _requiredString(Object? value, String name) {
  if (value is! String || value.isEmpty) {
    throw SettingsVaultFormatException('The $name must be a string.');
  }
  return value;
}

int _requiredInt(Object? value, String name) {
  if (value is! int) {
    throw SettingsVaultFormatException('The $name must be an integer.');
  }
  return value;
}

DateTime? _optionalDate(Object? value) {
  if (value == null) return null;
  return _requiredDate(value, 'createdAt');
}

DateTime _requiredDate(Object? value, String name) {
  if (value is! String) {
    throw SettingsVaultFormatException('The $name must be a timestamp.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw SettingsVaultFormatException('The $name must be a timestamp.');
  }
  return parsed.toUtc();
}

Map<String, Object?> _copyJsonMap(Map<String, Object?> value) {
  final copy = _copyJsonValue(value, 0);
  return Map<String, Object?>.unmodifiable(copy! as Map<String, Object?>);
}

Object? _copyJsonValue(Object? value, int depth) {
  if (depth > _maximumJsonDepth) {
    throw const SettingsVaultFormatException(
      'The preferences value is nested too deeply.',
    );
  }
  if (value == null || value is bool || value is String) return value;
  if (value is num) {
    if (value is double && !value.isFinite) {
      throw const SettingsVaultFormatException(
        'The preferences value contains a non-finite number.',
      );
    }
    return value;
  }
  if (value is List<Object?>) {
    return List<Object?>.unmodifiable(
      value.map((child) => _copyJsonValue(child, depth + 1)),
    );
  }
  if (value is Map<Object?, Object?>) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw const SettingsVaultFormatException(
          'The preferences value contains a non-string key.',
        );
      }
      result[entry.key! as String] = _copyJsonValue(entry.value, depth + 1);
    }
    return Map<String, Object?>.unmodifiable(result);
  }
  throw const SettingsVaultFormatException(
    'The preferences value is not JSON-compatible.',
  );
}
