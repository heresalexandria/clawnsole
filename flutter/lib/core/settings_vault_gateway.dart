import 'models.dart';

abstract interface class SettingsVaultStatusSource {
  SettingsVaultStatus get settingsVaultStatus;
}

class SettingsVaultSetupResult {
  const SettingsVaultSetupResult({
    required this.snapshot,
    required this.recoveryCode,
  });

  final LocalSnapshot snapshot;
  final String recoveryCode;
}

abstract interface class SettingsVaultGateway
    implements SettingsVaultStatusSource {
  Future<SettingsVaultSetupResult> setupSettingsVault(String passphrase);
  Future<LocalSnapshot> unlockSettingsVault(String passphrase);
  Future<LocalSnapshot> recoverSettingsVault(String recoveryCode);
  Future<LocalSnapshot> syncSettingsVault();
  Future<LocalSnapshot> changeSettingsVaultPassphrase(String newPassphrase);

  /// Replaces an inaccessible encrypted Drive vault while preserving this
  /// device's provider keys, preferences, and portable Drive library.
  Future<SettingsVaultSetupResult> resetSettingsVault(String newPassphrase);

  /// Erases only this device's cached vault key. Local provider credentials
  /// remain available; another sync requires the passphrase or recovery code.
  Future<LocalSnapshot> forgetSettingsVaultUnlock();
}
