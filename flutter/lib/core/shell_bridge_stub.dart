import 'shell_bridge.dart';

Future<bool?> openShellExternalUrl(Uri url, ExternalUrlPurpose purpose) async =>
    null;

/// Native mobile builds have no in-place shell updater; the App Store and
/// Play Store own updates there.
ShellUpdater? createShellUpdater() => null;
