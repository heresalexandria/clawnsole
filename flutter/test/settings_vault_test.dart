import 'dart:convert';
import 'dart:typed_data';

import 'package:clawnsole/core/settings_vault.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

const _fastKdf = SettingsVaultKdfParameters(
  memoryKiB: settingsVaultMinimumMemoryKiB,
  iterations: 2,
  parallelism: 1,
);

void main() {
  group('VaultPayload', () {
    test('round trips credentials, tombstones, and preferences', () {
      final payload = VaultPayload(
        credentials: <String, VaultCredentialRecord>{
          'bfl': VaultCredentialRecord(
            value: 'bfl-secret',
            updatedAt: DateTime.utc(2026, 8, 20, 12),
            deviceId: 'iphone-a',
          ),
          'ltx': VaultCredentialRecord(
            value: null,
            updatedAt: DateTime.utc(2026, 8, 20, 13),
            deviceId: 'windows-b',
          ),
        },
        preferences: VaultPreferencesRecord(
          value: <String, Object?>{
            'themeMode': 'dark',
            'nested': <String, Object?>{
              'enabled': true,
              'levels': <Object?>[1, 2, null],
            },
          },
          updatedAt: DateTime.utc(2026, 8, 20, 14),
          deviceId: 'mac-c',
        ),
      );

      final decoded = VaultPayload.decode(payload.encode());

      expect(decoded.credentials['bfl']!.value, 'bfl-secret');
      expect(decoded.credentials['ltx']!.isDeleted, isTrue);
      expect(decoded.preferences!.value['themeMode'], 'dark');
      expect(decoded.preferences!.updatedAt, DateTime.utc(2026, 8, 20, 14));
    });

    test('merges independent providers and the newer same-provider record', () {
      final older = DateTime.utc(2026, 8, 20, 10);
      final newer = older.add(const Duration(minutes: 1));
      final merged = mergeVaultPayloads(
        VaultPayload(
          credentials: <String, VaultCredentialRecord>{
            'bfl': VaultCredentialRecord(
              value: 'old-bfl',
              updatedAt: older,
              deviceId: 'device-a',
            ),
            'ltx': VaultCredentialRecord(
              value: 'ltx-secret',
              updatedAt: newer,
              deviceId: 'device-a',
            ),
          },
        ),
        VaultPayload(
          credentials: <String, VaultCredentialRecord>{
            'bfl': VaultCredentialRecord(
              value: 'new-bfl',
              updatedAt: newer,
              deviceId: 'device-b',
            ),
            'atlas': VaultCredentialRecord(
              value: 'atlas-secret',
              updatedAt: newer,
              deviceId: 'device-b',
            ),
          },
        ),
      );

      expect(merged.credentials['bfl']!.value, 'new-bfl');
      expect(merged.credentials['ltx']!.value, 'ltx-secret');
      expect(merged.credentials['atlas']!.value, 'atlas-secret');
    });

    test('newer tombstones win and remain in the merged payload', () {
      final merged = mergeVaultPayloads(
        VaultPayload(
          credentials: <String, VaultCredentialRecord>{
            'bfl': VaultCredentialRecord(
              value: 'stale-secret',
              updatedAt: DateTime.utc(2026, 8, 20, 10),
              deviceId: 'device-a',
            ),
          },
        ),
        VaultPayload(
          credentials: <String, VaultCredentialRecord>{
            'bfl': VaultCredentialRecord(
              value: null,
              updatedAt: DateTime.utc(2026, 8, 20, 11),
              deviceId: 'device-b',
            ),
          },
        ),
      );

      expect(merged.credentials['bfl']!.isDeleted, isTrue);
      expect(
        merged.toJson()['credentials'].toString(),
        contains('value: null'),
      );
    });

    test('device id breaks timestamp ties deterministically', () {
      final timestamp = DateTime.utc(2026, 8, 20, 10);
      final left = VaultPayload(
        credentials: <String, VaultCredentialRecord>{
          'bfl': VaultCredentialRecord(
            value: 'device-a-secret',
            updatedAt: timestamp,
            deviceId: 'device-a',
          ),
        },
      );
      final right = VaultPayload(
        credentials: <String, VaultCredentialRecord>{
          'bfl': VaultCredentialRecord(
            value: 'device-z-secret',
            updatedAt: timestamp,
            deviceId: 'device-z',
          ),
        },
      );

      expect(
        mergeVaultPayloads(left, right).credentials['bfl']!.value,
        'device-z-secret',
      );
      expect(
        mergeVaultPayloads(right, left).credentials['bfl']!.value,
        'device-z-secret',
      );
    });

    test('legacy whole preferences use timestamp then device id', () {
      final merged = mergeVaultPayloads(
        VaultPayload(
          preferences: VaultPreferencesRecord(
            value: <String, Object?>{'theme': 'light'},
            updatedAt: DateTime.utc(2026, 8, 20, 10),
            deviceId: 'device-z',
          ),
        ),
        VaultPayload(
          preferences: VaultPreferencesRecord(
            value: <String, Object?>{'theme': 'dark'},
            updatedAt: DateTime.utc(2026, 8, 20, 11),
            deviceId: 'device-a',
          ),
        ),
      );

      expect(merged.preferences!.value, <String, Object?>{'theme': 'dark'});
    });

    test('independent preference fields merge without overwriting', () {
      final older = DateTime.utc(2026, 8, 20, 10);
      final newer = older.add(const Duration(minutes: 1));
      final merged = mergeVaultPayloads(
        VaultPayload(
          preferenceFields: <String, VaultPreferenceFieldRecord>{
            'provider': VaultPreferenceFieldRecord(
              value: 'ltx',
              updatedAt: newer,
              deviceId: 'iphone',
            ),
            'libraryViewMode': VaultPreferenceFieldRecord(
              value: 'full',
              updatedAt: older,
              deviceId: 'iphone',
            ),
          },
        ),
        VaultPayload(
          preferenceFields: <String, VaultPreferenceFieldRecord>{
            'provider': VaultPreferenceFieldRecord(
              value: 'bfl',
              updatedAt: older,
              deviceId: 'windows',
            ),
            'libraryViewMode': VaultPreferenceFieldRecord(
              value: 'compact',
              updatedAt: newer,
              deviceId: 'windows',
            ),
          },
        ),
      );

      expect(merged.preferences!.value['provider'], 'ltx');
      expect(merged.preferences!.value['libraryViewMode'], 'compact');
    });

    test('legacy preference payloads expand into per-field registers', () {
      final decoded = VaultPayload.decode(
        jsonEncode(<String, Object?>{
          'version': settingsVaultPayloadVersion,
          'credentials': <String, Object?>{},
          'preferences': <String, Object?>{
            'value': <String, Object?>{
              'provider': 'atlas',
              'libraryViewMode': 'mini',
            },
            'updatedAt': '2026-08-20T12:00:00.000Z',
            'deviceId': 'legacy-device',
          },
        }),
      );

      expect(decoded.preferenceFields.keys, <String>{
        'provider',
        'libraryViewMode',
      });
      expect(decoded.preferenceFields['provider']!.value, 'atlas');
    });

    test('rejects non-JSON preference values', () {
      expect(
        () => VaultPreferencesRecord(
          value: <String, Object?>{'invalid': DateTime.now()},
          updatedAt: DateTime.utc(2026),
          deviceId: 'device-a',
        ),
        throwsA(isA<SettingsVaultFormatException>()),
      );
    });
  });

  group('SettingsVaultCodec', () {
    test('production KDF defaults are 64 MiB, three passes, and one lane', () {
      final parameters = SettingsVaultCodec().kdfParameters;

      expect(parameters.memoryKiB, 64 * 1024);
      expect(parameters.iterations, 3);
      expect(parameters.parallelism, 1);
    });

    test('production KDF profile creates a valid envelope', () async {
      final codec = SettingsVaultCodec();
      final created = await codec.create(
        'a production profile sync phrase',
        VaultPayload(),
      );
      addTearDown(created.dataEncryptionKey.destroy);

      expect(
        created.envelope.passphraseSlot.parameters.memoryKiB,
        settingsVaultDefaultMemoryKiB,
      );
      expect(
        SettingsVaultEnvelope.decode(created.envelope.encode()).vaultId,
        created.envelope.vaultId,
      );
    });

    test(
      'creates an opaque envelope and unlocks with both credentials',
      () async {
        final codec = SettingsVaultCodec(kdfParameters: _fastKdf);
        final payload = _payload(
          credential: 'very-distinct-provider-secret-7b441e',
          preference: 'very-distinct-private-setting-a9193c',
        );
        final created = await codec.create(
          'a long sync passphrase for tests',
          payload,
        );
        addTearDown(created.dataEncryptionKey.destroy);

        final encoded = created.envelope.encode();
        expect(
          encoded,
          isNot(contains('very-distinct-provider-secret-7b441e')),
        );
        expect(
          encoded,
          isNot(contains('very-distinct-private-setting-a9193c')),
        );
        expect(created.recoveryCode, hasLength(43));
        expect(encoded, isNot(contains(created.recoveryCode)));
        expect(
          created.envelope.passphraseSlot.parameters.memoryKiB,
          settingsVaultMinimumMemoryKiB,
        );

        final decoded = SettingsVaultEnvelope.decode(encoded);
        final unlocked = await codec.unlock(
          decoded,
          'a long sync passphrase for tests',
        );
        addTearDown(unlocked.dataEncryptionKey.destroy);
        expect(
          unlocked.payload.credentials['bfl']!.value,
          'very-distinct-provider-secret-7b441e',
        );

        final recovered = await codec.unlockWithRecoveryCode(
          decoded,
          created.recoveryCode,
        );
        addTearDown(recovered.dataEncryptionKey.destroy);
        expect(
          recovered.payload.preferences!.value['privateSetting'],
          'very-distinct-private-setting-a9193c',
        );
      },
    );

    test(
      'updates use fresh payload nonces and decrypt with the same DEK',
      () async {
        final codec = SettingsVaultCodec(kdfParameters: _fastKdf);
        final created = await codec.create(
          'a long sync passphrase for updates',
          _payload(credential: 'first', preference: 'one'),
        );
        addTearDown(created.dataEncryptionKey.destroy);

        final first = await codec.updatePayload(
          created.envelope,
          created.dataEncryptionKey,
          _payload(credential: 'second', preference: 'two'),
        );
        final second = await codec.updatePayload(
          first,
          created.dataEncryptionKey,
          _payload(credential: 'third', preference: 'three'),
        );

        expect(
          first.payload.nonce,
          isNot(equals(created.envelope.payload.nonce)),
        );
        expect(second.payload.nonce, isNot(equals(first.payload.nonce)));
        expect(
          (await codec.decrypt(
            second,
            created.dataEncryptionKey,
          )).credentials['bfl']!.value,
          'third',
        );

        final unrelatedKey = SecretKeyData(
          Uint8List(32),
          overwriteWhenDestroyed: true,
        );
        addTearDown(unrelatedKey.destroy);
        await expectLater(
          codec.updatePayload(second, unrelatedKey, VaultPayload()),
          throwsA(isA<SettingsVaultAuthenticationException>()),
        );
      },
    );

    test(
      'rewrap changes only the passphrase slot and preserves recovery',
      () async {
        final codec = SettingsVaultCodec(kdfParameters: _fastKdf);
        final created = await codec.create(
          'the original long sync phrase',
          _payload(credential: 'secret', preference: 'setting'),
        );
        addTearDown(created.dataEncryptionKey.destroy);

        final rewrapped = await codec.rewrap(
          created.envelope,
          created.dataEncryptionKey,
          'the replacement long sync phrase',
        );

        expect(rewrapped.payload.toJson(), created.envelope.payload.toJson());
        expect(
          rewrapped.recoverySlot.toJson(),
          created.envelope.recoverySlot.toJson(),
        );
        expect(
          rewrapped.passphraseSlot.wrappedKey.nonce,
          isNot(equals(created.envelope.passphraseSlot.wrappedKey.nonce)),
        );

        final unlocked = await codec.unlock(
          rewrapped,
          'the replacement long sync phrase',
        );
        addTearDown(unlocked.dataEncryptionKey.destroy);
        expect(unlocked.payload.credentials['bfl']!.value, 'secret');

        final recovered = await codec.unlockWithRecoveryCode(
          rewrapped,
          created.recoveryCode,
        );
        addTearDown(recovered.dataEncryptionKey.destroy);
        expect(recovered.payload.credentials['bfl']!.value, 'secret');
      },
    );

    test('wrong passphrase and recovery code do not unlock', () async {
      final codec = SettingsVaultCodec(kdfParameters: _fastKdf);
      final created = await codec.create(
        'the correct long sync phrase',
        _payload(credential: 'secret', preference: 'setting'),
      );
      addTearDown(created.dataEncryptionKey.destroy);
      final other = await codec.create(
        'another valid long passphrase',
        VaultPayload(),
      );
      addTearDown(other.dataEncryptionKey.destroy);

      await expectLater(
        codec.unlock(created.envelope, 'an incorrect long passphrase'),
        throwsA(isA<SettingsVaultAuthenticationException>()),
      );
      await expectLater(
        codec.unlockWithRecoveryCode(created.envelope, other.recoveryCode),
        throwsA(isA<SettingsVaultAuthenticationException>()),
      );
    });

    test('payload and authenticated header tampering are rejected', () async {
      final codec = SettingsVaultCodec(kdfParameters: _fastKdf);
      final created = await codec.create(
        'a long tamper detection phrase',
        _payload(credential: 'secret', preference: 'setting'),
      );
      addTearDown(created.dataEncryptionKey.destroy);

      final payloadJson = _envelopeJson(created.envelope);
      final encryptedPayload = payloadJson['payload']! as Map<String, Object?>;
      encryptedPayload['mac'] = _flipBase64(encryptedPayload['mac']! as String);
      final tamperedPayload = SettingsVaultEnvelope.decode(
        jsonEncode(payloadJson),
      );
      await expectLater(
        codec.decrypt(tamperedPayload, created.dataEncryptionKey),
        throwsA(isA<SettingsVaultAuthenticationException>()),
      );

      final headerJson = _envelopeJson(created.envelope);
      headerJson['vaultId'] = _flipBase64(headerJson['vaultId']! as String);
      final tamperedHeader = SettingsVaultEnvelope.decode(
        jsonEncode(headerJson),
      );
      await expectLater(
        codec.decrypt(tamperedHeader, created.dataEncryptionKey),
        throwsA(isA<SettingsVaultAuthenticationException>()),
      );
    });
  });

  group('SettingsVaultEnvelope validation', () {
    late SettingsVaultCodec codec;
    late CreatedSettingsVault created;

    setUpAll(() async {
      codec = SettingsVaultCodec(kdfParameters: _fastKdf);
      created = await codec.create(
        'a long validation passphrase',
        VaultPayload(),
      );
    });

    tearDownAll(() => created.dataEncryptionKey.destroy());

    test('rejects unsupported versions and algorithms', () {
      final version = _envelopeJson(created.envelope)..['version'] = 2;
      expect(
        () => SettingsVaultEnvelope.decode(jsonEncode(version)),
        throwsA(isA<SettingsVaultFormatException>()),
      );

      final algorithm = _envelopeJson(created.envelope);
      (algorithm['payload']! as Map<String, Object?>)['algorithm'] = 'aes-cbc';
      expect(
        () => SettingsVaultEnvelope.decode(jsonEncode(algorithm)),
        throwsA(isA<SettingsVaultFormatException>()),
      );
    });

    test('rejects invalid base64 and hostile Argon2 parameters', () {
      final base64 = _envelopeJson(created.envelope);
      (base64['payload']! as Map<String, Object?>)['nonce'] = '***';
      expect(
        () => SettingsVaultEnvelope.decode(jsonEncode(base64)),
        throwsA(isA<SettingsVaultFormatException>()),
      );

      final memory = _envelopeJson(created.envelope);
      final slot = memory['passphraseSlot']! as Map<String, Object?>;
      (slot['kdf']! as Map<String, Object?>)['memoryKiB'] = 1;
      expect(
        () => SettingsVaultEnvelope.decode(jsonEncode(memory)),
        throwsA(isA<SettingsVaultFormatException>()),
      );
    });

    test('rejects oversized envelopes before parsing JSON', () {
      expect(
        () => SettingsVaultEnvelope.decode(
          'x' * (settingsVaultMaximumEncodedBytes + 1),
        ),
        throwsA(isA<SettingsVaultFormatException>()),
      );
    });

    test('rejects ciphertext larger than the bounded payload', () {
      final oversized = _envelopeJson(created.envelope);
      final payload = oversized['payload']! as Map<String, Object?>;
      payload['ciphertext'] = base64UrlEncode(
        Uint8List(settingsVaultMaximumPayloadBytes + 1),
      ).replaceAll('=', '');

      expect(
        () => SettingsVaultEnvelope.decode(jsonEncode(oversized)),
        throwsA(isA<SettingsVaultFormatException>()),
      );
    });
  });
}

VaultPayload _payload({
  required String credential,
  required String preference,
}) => VaultPayload(
  credentials: <String, VaultCredentialRecord>{
    'bfl': VaultCredentialRecord(
      value: credential,
      updatedAt: DateTime.utc(2026, 8, 20, 12),
      deviceId: 'test-device',
    ),
  },
  preferences: VaultPreferencesRecord(
    value: <String, Object?>{'privateSetting': preference},
    updatedAt: DateTime.utc(2026, 8, 20, 12),
    deviceId: 'test-device',
  ),
);

Map<String, Object?> _envelopeJson(SettingsVaultEnvelope envelope) =>
    (jsonDecode(envelope.encode())! as Map<Object?, Object?>).map(
      (key, value) => MapEntry(key! as String, _mutableJson(value)),
    );

Object? _mutableJson(Object? value) {
  if (value is Map<Object?, Object?>) {
    return value.map(
      (key, child) => MapEntry(key! as String, _mutableJson(child)),
    );
  }
  if (value is List<Object?>) return value.map(_mutableJson).toList();
  return value;
}

String _flipBase64(String value) =>
    '${value[0] == 'A' ? 'B' : 'A'}${value.substring(1)}';
