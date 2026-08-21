import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/google_drive.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/settings_vault_gateway.dart';
import 'package:clawnsole/ui/providers_screen.dart';
import 'package:clawnsole/ui/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'vault setup preserves the exact passphrase and gates recovery dismissal',
    (tester) async {
      String? copiedText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copiedText =
                  (call.arguments as Map<Object?, Object?>)['text'] as String?;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final gateway = _VaultGateway(SettingsVaultState.setupRequired);
      final controller = await _controller(gateway);
      await _pumpSettings(tester, controller);

      await tester.ensureVisible(
        find.byKey(const ValueKey('settings-vault-setup')),
      );
      await tester.tap(find.byKey(const ValueKey('settings-vault-setup')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('settings-vault-passphrase')),
        'too short',
      );
      await tester.enterText(
        find.byKey(const ValueKey('settings-vault-passphrase-confirmation')),
        'too short',
      );
      await tester.tap(
        find.byKey(const ValueKey('settings-vault-passphrase-submit')),
      );
      await tester.pump();
      expect(find.text('Enter at least 12 characters.'), findsOneWidget);

      final overlongPassphrase = List<String>.filled(300, '🦀').join();
      await tester.enterText(
        find.byKey(const ValueKey('settings-vault-passphrase')),
        overlongPassphrase,
      );
      await tester.enterText(
        find.byKey(const ValueKey('settings-vault-passphrase-confirmation')),
        overlongPassphrase,
      );
      await tester.tap(
        find.byKey(const ValueKey('settings-vault-passphrase-submit')),
      );
      await tester.pump();
      expect(
        find.text('The passphrase must be at most 1,024 encoded bytes.'),
        findsOneWidget,
      );
      expect(gateway.values, isEmpty);

      const exactPassphrase = ' 1234567890 ';
      await tester.enterText(
        find.byKey(const ValueKey('settings-vault-passphrase')),
        exactPassphrase,
      );
      await tester.enterText(
        find.byKey(const ValueKey('settings-vault-passphrase-confirmation')),
        exactPassphrase,
      );
      await tester.tap(
        find.byKey(const ValueKey('settings-vault-passphrase-submit')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(gateway.values.single, ('setup', exactPassphrase));
      expect(
        find.byKey(const ValueKey('settings-vault-recovery-code')),
        findsOneWidget,
      );
      final done = tester.widget<FilledButton>(
        find.byKey(const ValueKey('settings-vault-recovery-done')),
      );
      expect(done.onPressed, isNull);

      await tester.tap(
        find.byKey(const ValueKey('settings-vault-recovery-copy')),
      );
      await tester.pump();
      expect(copiedText, gateway.recoveryCode);
      await tester.tap(find.text('I saved this recovery code somewhere safe.'));
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('settings-vault-recovery-done')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Save your recovery code'), findsNothing);
      controller.dispose();
    },
  );

  testWidgets('locked vault accepts exact passphrase or recovery input', (
    tester,
  ) async {
    final gateway = _VaultGateway(SettingsVaultState.locked);
    final controller = await _controller(gateway);
    await _pumpSettings(tester, controller);

    await tester.ensureVisible(
      find.byKey(const ValueKey('settings-vault-unlock')),
    );
    await tester.tap(find.byKey(const ValueKey('settings-vault-unlock')));
    await tester.pumpAndSettle();
    const exactPassphrase = ' passphrase ';
    await tester.enterText(
      find.byKey(const ValueKey('settings-vault-passphrase')),
      exactPassphrase,
    );
    await tester.tap(
      find.byKey(const ValueKey('settings-vault-passphrase-submit')),
    );
    await tester.pumpAndSettle();
    expect(gateway.values.last, ('unlock', exactPassphrase));
    expect(find.text('Encrypted settings are synced'), findsOneWidget);

    gateway.setState(SettingsVaultState.locked);
    await controller.refreshGoogleDrive();
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('settings-vault-recover')),
    );
    await tester.tap(find.byKey(const ValueKey('settings-vault-recover')));
    await tester.pumpAndSettle();
    const exactRecovery = ' recovery-code-with-spaces ';
    await tester.enterText(
      find.byKey(const ValueKey('settings-vault-recovery-input')),
      exactRecovery,
    );
    await tester.tap(
      find.byKey(const ValueKey('settings-vault-recovery-submit')),
    );
    await tester.pumpAndSettle();
    expect(gateway.values.last, ('recover', exactRecovery));
    controller.dispose();
  });

  testWidgets(
    'pending vault exposes sync, passphrase change, and forget flows',
    (tester) async {
      final gateway = _VaultGateway(SettingsVaultState.pending);
      final controller = await _controller(gateway);
      await _pumpSettings(tester, controller);

      expect(find.text('Encrypted settings sync pending'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('settings-vault-sync')),
      );
      await tester.tap(find.byKey(const ValueKey('settings-vault-sync')));
      await tester.pumpAndSettle();
      expect(gateway.values.last, ('sync', ''));

      await tester.ensureVisible(
        find.byKey(const ValueKey('settings-vault-change-passphrase')),
      );
      await tester.tap(
        find.byKey(const ValueKey('settings-vault-change-passphrase')),
      );
      await tester.pumpAndSettle();
      const changed = ' changed passphrase ';
      await tester.enterText(
        find.byKey(const ValueKey('settings-vault-passphrase')),
        changed,
      );
      await tester.enterText(
        find.byKey(const ValueKey('settings-vault-passphrase-confirmation')),
        changed,
      );
      await tester.tap(
        find.byKey(const ValueKey('settings-vault-passphrase-submit')),
      );
      await tester.pumpAndSettle();
      expect(gateway.values.last, ('changePassphrase', changed));

      await tester.ensureVisible(
        find.byKey(const ValueKey('settings-vault-forget')),
      );
      await tester.tap(find.byKey(const ValueKey('settings-vault-forget')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('settings-vault-forget-confirm')),
      );
      await tester.pumpAndSettle();
      expect(gateway.values.last, ('forget', ''));
      expect(find.text('Encrypted settings are locked'), findsOneWidget);
      controller.dispose();
    },
  );

  testWidgets('provider copy reports encrypted sync and pending state', (
    tester,
  ) async {
    final gateway = _VaultGateway(
      SettingsVaultState.pending,
      connectedProviders: const <String>{'bfl'},
    );
    final controller = await _controller(gateway);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildClawnsoleTheme(Brightness.light),
        home: Scaffold(body: ProvidersScreen(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Choose where Clawnsole renders. Provider keys are secure on this device; encrypted Drive sync is pending.',
      ),
      findsOneWidget,
    );
    expect(find.text('Connected · sync pending'), findsOneWidget);
    controller.dispose();
  });
}

Future<AppController> _controller(_VaultGateway gateway) async {
  final controller = AppController(gateway: gateway);
  await controller.initialize();
  return controller;
}

Future<void> _pumpSettings(
  WidgetTester tester,
  AppController controller,
) async {
  await tester.binding.setSurfaceSize(const Size(850, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildClawnsoleTheme(Brightness.light),
      home: Scaffold(
        body: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => SettingsScreen(controller: controller),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _VaultGateway
    implements AppGateway, GoogleDriveGateway, SettingsVaultGateway {
  _VaultGateway(
    SettingsVaultState state, {
    Set<String> connectedProviders = const <String>{},
  }) : _snapshot = _makeSnapshot(state, connectedProviders);

  LocalSnapshot _snapshot;
  final List<(String, String)> values = <(String, String)>[];
  final String recoveryCode = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFG';

  void setState(SettingsVaultState state) {
    _snapshot = _makeSnapshot(state, _snapshot.connectedProviders);
  }

  LocalSnapshot _update(SettingsVaultState state) {
    setState(state);
    return _snapshot;
  }

  @override
  SettingsVaultStatus get settingsVaultStatus => _snapshot.settingsVault;

  @override
  GoogleDriveConnection get googleDriveConnection =>
      const GoogleDriveConnection(
        state: GoogleDriveConnectionState.connected,
        folderName: 'Clawnsole',
        folderId: 'drive-root',
      );

  @override
  bool get supportsLocalLibrary => true;

  @override
  bool get usesCompanion => false;

  @override
  bool get supportsPhotoLibrarySave => false;

  @override
  String get persistenceDescription => 'Memory';

  @override
  Future<LocalSnapshot> load() async => _snapshot;

  @override
  Future<SettingsVaultSetupResult> setupSettingsVault(String passphrase) async {
    values.add(('setup', passphrase));
    return SettingsVaultSetupResult(
      snapshot: _update(SettingsVaultState.ready),
      recoveryCode: recoveryCode,
    );
  }

  @override
  Future<LocalSnapshot> unlockSettingsVault(String passphrase) async {
    values.add(('unlock', passphrase));
    return _update(SettingsVaultState.ready);
  }

  @override
  Future<LocalSnapshot> recoverSettingsVault(String recoveryCode) async {
    values.add(('recover', recoveryCode));
    return _update(SettingsVaultState.ready);
  }

  @override
  Future<LocalSnapshot> syncSettingsVault() async {
    values.add(('sync', ''));
    return _update(SettingsVaultState.ready);
  }

  @override
  Future<LocalSnapshot> changeSettingsVaultPassphrase(
    String newPassphrase,
  ) async {
    values.add(('changePassphrase', newPassphrase));
    return _update(SettingsVaultState.ready);
  }

  @override
  Future<LocalSnapshot> forgetSettingsVaultUnlock() async {
    values.add(('forget', ''));
    return _update(SettingsVaultState.locked);
  }

  @override
  Future<LocalSnapshot> connectGoogleDrive(String folderName) async =>
      _snapshot;

  @override
  Future<LocalSnapshot> disconnectGoogleDrive() async => _snapshot;

  @override
  Future<LocalSnapshot> refreshGoogleDrive() async => _snapshot;

  @override
  Future<LocalSnapshot?> resumeGoogleDrive({bool force = false}) async => null;

  @override
  Future<GoogleDriveCopyResult> copyLocalLibraryToGoogleDrive({
    Set<String> generationIds = const <String>{},
    Set<String> referenceIds = const <String>{},
  }) async =>
      GoogleDriveCopyResult(snapshot: _snapshot, generations: 0, references: 0);

  @override
  Future<GoogleDriveCopyResult> moveLocalLibraryToGoogleDrive() async =>
      GoogleDriveCopyResult(snapshot: _snapshot, generations: 0, references: 0);

  @override
  Future<LocalSnapshot> setApiKey(String value) async => _snapshot;

  @override
  Future<double> verifyKey([String? candidate]) async => 0;

  @override
  Future<double> getCredits() async => 0;

  @override
  Future<LocalSnapshot> setPreferences(AppPreferences preferences) async =>
      _snapshot;

  @override
  Future<Generation> submit(GenerationSubmission submission) async =>
      submission.record;

  @override
  Future<Generation> poll(Generation generation) async => generation;

  @override
  Future<LocalSnapshot> deleteGeneration(String localId) async => _snapshot;

  @override
  Future<LocalSnapshot> clearHistory() async => _snapshot;

  @override
  Future<LocalSnapshot> clearPreferences() async => _snapshot;

  @override
  Future<LocalSnapshot> clearApiKey() async => _snapshot;

  @override
  Future<LocalSnapshot> clearAll() async => _snapshot;

  @override
  Future<Uri> assetUri(AssetReference reference) async =>
      Uri.parse(reference.value);

  @override
  Future<Uint8List> readAsset(AssetReference reference) async => Uint8List(0);

  @override
  Uri mediaUri(String source) => Uri.parse(source);

  @override
  Future<Uint8List> downloadMedia(String source) async => Uint8List(0);

  @override
  Future<void> saveMediaToPhotoLibrary(
    Uint8List bytes,
    String fileName,
    String contentType,
  ) async {}
}

LocalSnapshot _makeSnapshot(
  SettingsVaultState state,
  Set<String> connectedProviders,
) => LocalSnapshot(
  generations: const <Generation>[],
  preferences: const AppPreferences(),
  hasApiKey: connectedProviders.contains('bfl'),
  connectedProviders: connectedProviders,
  availableProviders: const <String>{'bfl'},
  storage: const StorageStats(path: 'memory', bytes: 0, records: 0),
  settingsVault: SettingsVaultStatus(
    state: state,
    vaultId: state == SettingsVaultState.setupRequired ? '' : 'vault-01',
    message: state == SettingsVaultState.pending
        ? 'Waiting for Google Drive.'
        : '',
  ),
);
