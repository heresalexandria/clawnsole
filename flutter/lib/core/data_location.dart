import 'models.dart';

/// How a build exposes its durable data directory to the user.
///
/// Capabilities are read from the gateway, mirroring the GoogleDriveGateway
/// precedent, so presentation code never branches on `Platform` directly.
abstract interface class DataLocationGateway {
  /// True when this build can show the data folder to the user, either in
  /// the OS file manager or, on iOS, in the Files app.
  bool get supportsRevealDataFolder;

  /// True when the user can move the data directory from inside the app.
  bool get supportsDataRelocation;

  /// True when the desktop shell owns the directory picker and migration and
  /// restarts the app after a successful move; the in-app flow then only
  /// starts the shell's own dialog sequence.
  bool get shellManagesDataRelocation;

  Future<void> revealDataFolder();

  /// Whether [directory] already holds a Clawnsole library, so the caller can
  /// offer a portable handoff instead of ever overwriting silently.
  Future<bool> dataDirectoryHasLibrary(String directory);

  /// Copies the library into [directory] (or, with [useExistingLibrary],
  /// adopts the library already there) and reloads state from the new
  /// location. The previous copy is intentionally left in place.
  Future<LocalSnapshot> relocateDataDirectory(
    String directory, {
    bool useExistingLibrary = false,
  });

  /// Shell-managed relocation: the desktop shell shows its own picker and
  /// confirmation dialogs, migrates the files, and relaunches on success.
  Future<ShellDataRelocation> relocateDataDirectoryViaShell();
}

class ShellDataRelocation {
  const ShellDataRelocation({this.moved = false, this.canceled = false});

  final bool moved;
  final bool canceled;
}
