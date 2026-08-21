import 'settings_vault_shell_stub.dart'
    if (dart.library.js_interop) 'settings_vault_shell_web.dart';

typedef SettingsVaultShellInvoker =
    Future<Map<String, Object?>> Function(String action, String value);

Future<Map<String, Object?>> invokeSettingsVaultShell(
  String action,
  String value,
) => invokePlatformSettingsVault(action, value);
