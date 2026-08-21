import 'dart:convert';

import 'package:clawnsole/core/bfl_api.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/web_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'WebGateway sends vault actions through the shell then refreshes state',
    () async {
      final calls = <(String, String)>[];
      var stateReads = 0;
      final gateway = WebGateway(
        baseUrl: Uri.parse('http://127.0.0.1:8787'),
        settingsVaultInvoker: (action, value) async {
          calls.add((action, value));
          return <String, Object?>{
            'ok': true,
            if (action == 'setup') 'recoveryCode': 'recovery-code-123',
          };
        },
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/state');
          stateReads += 1;
          return http.Response(
            jsonEncode(
              _snapshot(
                const SettingsVaultStatus(
                  state: SettingsVaultState.ready,
                  vaultId: 'vault-01',
                ),
              ).toJson(),
            ),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }),
      );

      final setup = await gateway.setupSettingsVault(' 1234567890 ');
      expect(setup.recoveryCode, 'recovery-code-123');
      expect(setup.snapshot.settingsVault.state, SettingsVaultState.ready);
      expect(gateway.settingsVaultStatus.vaultId, 'vault-01');

      await gateway.unlockSettingsVault(' unlock exactly ');
      await gateway.recoverSettingsVault(' recovery exactly ');
      await gateway.syncSettingsVault();
      await gateway.changeSettingsVaultPassphrase(' change exactly ');
      await gateway.forgetSettingsVaultUnlock();

      expect(calls, <(String, String)>[
        ('setup', ' 1234567890 '),
        ('unlock', ' unlock exactly '),
        ('recover', ' recovery exactly '),
        ('sync', ''),
        ('changePassphrase', ' change exactly '),
        ('forget', ''),
      ]);
      expect(stateReads, calls.length);
    },
  );

  test(
    'WebGateway surfaces sanitized shell vault errors without reading state',
    () async {
      var stateReads = 0;
      final gateway = WebGateway(
        baseUrl: Uri.parse('http://127.0.0.1:8787'),
        settingsVaultInvoker: (action, value) async => const <String, Object?>{
          'ok': false,
          'error': 'The passphrase did not unlock this vault.',
        },
        client: MockClient((request) async {
          stateReads += 1;
          return http.Response('{}', 200);
        }),
      );

      await expectLater(
        gateway.unlockSettingsVault('incorrect passphrase'),
        throwsA(
          isA<ProviderException>().having(
            (error) => error.message,
            'message',
            'The passphrase did not unlock this vault.',
          ),
        ),
      );
      expect(stateReads, 0);
    },
  );

  test('WebGateway requires the one-time setup recovery code', () async {
    var stateReads = 0;
    final gateway = WebGateway(
      baseUrl: Uri.parse('http://127.0.0.1:8787'),
      settingsVaultInvoker: (action, value) async => const <String, Object?>{
        'ok': true,
      },
      client: MockClient((request) async {
        stateReads += 1;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      gateway.setupSettingsVault('twelve chars'),
      throwsA(
        isA<ProviderException>().having(
          (error) => error.message,
          'message',
          contains('recovery code'),
        ),
      ),
    );
    expect(stateReads, 0);
  });
}

LocalSnapshot _snapshot(SettingsVaultStatus status) => LocalSnapshot(
  generations: const <Generation>[],
  preferences: const AppPreferences(),
  hasApiKey: false,
  storage: const StorageStats(path: 'memory', bytes: 0, records: 0),
  settingsVault: status,
);
