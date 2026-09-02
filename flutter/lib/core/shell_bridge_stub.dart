import 'shell_bridge.dart';

Future<bool?> openShellExternalUrl(Uri url, ExternalUrlPurpose purpose) async =>
    null;

/// Native mobile builds have no in-place shell updater; the App Store and
/// Play Store own updates there.
ShellUpdater? createShellUpdater() => null;

Stream<String> createShellNavigationStream() => const Stream<String>.empty();

Future<bool> shellNotify(String title, String body) async => false;
