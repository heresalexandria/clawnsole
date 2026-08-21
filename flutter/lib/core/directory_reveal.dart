import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

/// True when [revealDirectory] can show a directory on the running platform:
/// a file-manager window on desktop, the Files app on iOS. Android has no
/// reliable folder-view intent, so it stays hidden there.
bool get canRevealDirectory =>
    Platform.isMacOS ||
    Platform.isWindows ||
    Platform.isLinux ||
    Platform.isIOS;

/// Opens [directory] for the user. Desktop launches the platform file
/// manager detached; iOS opens the app's documents tree in the Files app via
/// the `shareddocuments://` scheme enabled in Info.plist.
Future<void> revealDirectory(String directory) async {
  if (Platform.isIOS) {
    final opened = await launchUrl(
      Uri.parse('shareddocuments://$directory'),
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      throw StateError('The Files app could not be opened on this device.');
    }
    return;
  }
  final command = Platform.isMacOS
      ? 'open'
      : Platform.isWindows
      ? 'explorer.exe'
      : Platform.isLinux
      ? 'xdg-open'
      : null;
  if (command == null) {
    throw StateError('Opening the data folder is not supported here.');
  }
  await Process.start(command, <String>[
    directory,
  ], mode: ProcessStartMode.detached);
}
