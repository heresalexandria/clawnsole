import 'dart:convert';
import 'dart:io';

import 'package:clawnsole/core/bfl_api.dart';
import 'package:clawnsole/core/hybrid_data_store.dart';
import 'package:clawnsole/core/local_data_store_io.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/native_gateway.dart';
import 'package:clawnsole/core/secure_value_store.dart';
import 'package:clawnsole/core/settings_vault_data_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../tool/clawnsole_companion.dart';

void main() {
  for (final schemaVersion in <int>[24, 25]) {
    test(
      'schema $schemaVersion warning choices migrate into settings without losing data',
      () {
        final credentialId = providerCredentialAcknowledgementId(
          'bfl',
          'test-key',
        );
        final migrated = StoredData.fromJson(<String, Object?>{
          'schemaVersion': schemaVersion,
          'providerRetentionAcknowledgements': <String, String>{
            'bfl': credentialId,
          },
          'preferences': const AppPreferences(
            themeMode: AppThemeMode.dark,
          ).toJson(),
          'preferencesUpdatedAt': '2026-01-01T00:00:00Z',
          'driveFolderId': 'existing-folder',
        });

        expect(
          migrated.preferences.providerRetentionAcknowledgements['bfl'],
          credentialId,
        );
        expect(migrated.preferences.themeMode, AppThemeMode.dark);
        expect(migrated.driveFolderId, 'existing-folder');
        expect(
          migrated.preferencesUpdatedAt!.isAfter(DateTime.utc(2026)),
          isTrue,
        );
        final encoded = migrated.toJson();
        expect(encoded['schemaVersion'], 26);
        expect(
          encoded.containsKey('providerRetentionAcknowledgements'),
          isFalse,
        );
        final restarted = StoredData.decode(migrated.encode());
        expect(
          restarted.providerRetentionAcknowledgements,
          migrated.providerRetentionAcknowledgements,
        );
        expect(restarted.preferencesUpdatedAt, migrated.preferencesUpdatedAt);
        // Once migrated, clearing preferences must not resurrect an old choice.
        expect(
          StoredData.fromJson(<String, Object?>{
            ...encoded,
            'preferences': const AppPreferences().toJson(),
            'providerRetentionAcknowledgements': <String, String>{
              'bfl': credentialId,
            },
          }).providerRetentionAcknowledgements,
          isEmpty,
        );
      },
    );
  }

  test(
    'native warning choices survive local restart and unrelated settings',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'clawnsole-warning-native.',
      );
      addTearDown(() => directory.delete(recursive: true));
      final secure = MemorySecureValueStore();
      NativeGateway openGateway() => NativeGateway(
        hybridStore: HybridDataStore(
          local: LocalDataStore(documentsDirectory: directory),
        ),
        secureValueStore: secure,
        isIos: false,
      );
      final gateway = openGateway();
      await gateway.setApiKey('test-key');
      final before = await gateway.load();
      expect(before.providerRetentionAcknowledgements, isEmpty);
      final accepted = await gateway.acknowledgeProviderRetentionRisk('bfl');
      expect(accepted.providerRetentionAcknowledgements, contains('bfl'));
      // This UI save was captured before the warning was accepted.
      await gateway.setPreferences(
        before.preferences.copyWith(themeMode: AppThemeMode.dark),
      );

      final restarted = openGateway();
      final restored = await restarted.load();
      expect(restored.providerRetentionAcknowledgements, contains('bfl'));
      expect(restored.preferences.themeMode, AppThemeMode.dark);
      final disk = await LocalDataStore(documentsDirectory: directory).read();
      expect(disk.preferences.providerRetentionAcknowledgements, isNotEmpty);
      expect(disk.encode(), isNot(contains('test-key')));
      await restarted.clearPreferences();
      expect(
        (await restarted.load()).providerRetentionAcknowledgements,
        isEmpty,
      );
    },
  );

  test(
    'companion returns cached warning choices on accept, refresh and restart',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'clawnsole-warning-companion.',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/clawnsole.json');
      final secure = MemorySecureValueStore();
      final client = http.Client();
      addTearDown(client.close);

      // Each pass constructs a fresh local store, vault, companion and HTTP server.
      for (var launch = 0; launch < 2; launch += 1) {
        final hybrid = HybridDataStore(local: CompanionStore(file));
        final vault = SettingsVaultDataStore(
          delegate: hybrid,
          secureStore: secure,
        );
        if (launch == 0) {
          await vault.write(const StoredData().withApiKey('bfl', 'test-key'));
        }
        final app = CompanionApp.hybrid(
          store: CompanionHybridStore(hybrid, vault: vault),
          api: BflApi(),
        );
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final subscription = server.listen(app.handle);
        final uri = Uri.parse('http://127.0.0.1:${server.port}/state');
        Future<LocalSnapshot> action(String name, Object? value) async {
          final response = await client.patch(
            uri,
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(<String, Object?>{'action': name, 'value': value}),
          );
          expect(response.statusCode, 200, reason: response.body);
          return LocalSnapshot.fromJson(
            jsonDecode(response.body) as Map<String, Object?>,
          );
        }

        try {
          if (launch == 0) {
            final accepted = await action(
              'acknowledgeProviderRetentionRisk',
              'bfl',
            );
            expect(accepted.providerRetentionAcknowledgements, contains('bfl'));
            final changed = await action(
              'setPreferences',
              const AppPreferences(themeMode: AppThemeMode.dark).toJson(),
            );
            expect(changed.providerRetentionAcknowledgements, contains('bfl'));
          }
          final response = await client.get(uri);
          expect(response.statusCode, 200);
          final restored = LocalSnapshot.fromJson(
            jsonDecode(response.body) as Map<String, Object?>,
          );
          expect(restored.providerRetentionAcknowledgements, contains('bfl'));
          expect(restored.preferences.themeMode, AppThemeMode.dark);
          expect(
            restored.preferences.providerRetentionAcknowledgements,
            isNotEmpty,
          );
          expect(await file.readAsString(), isNot(contains('test-key')));
          if (launch == 1) {
            final changedKey = await action(
              'setProviderApiKey',
              <String, String>{'provider': 'bfl', 'apiKey': 'replacement-key'},
            );
            expect(changedKey.providerRetentionAcknowledgements, isEmpty);
          }
        } finally {
          await subscription.cancel();
          await server.close(force: true);
        }
      }
    },
  );
}
