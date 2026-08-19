import 'package:flutter/foundation.dart';

import 'app_version.dart';
import 'shell_bridge.dart';
import 'update_check.dart';

/// Whether the operating system's store owns updates for this build, which
/// makes an in-app update check pointless.
bool get storeManagedPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android);

/// The app-wide answer to "is there a newer Clawnsole?".
///
/// One instance backs both the version chip's badge and the version dialog so
/// a launch-time check is reused instead of repeated per surface.
class UpdateStatus extends ChangeNotifier {
  UpdateStatus._() : _shellProvider = _defaultShellUpdater;

  @visibleForTesting
  UpdateStatus.forTesting(ShellUpdater updater)
    : _shellProvider = (() => updater);

  static final UpdateStatus instance = UpdateStatus._();

  final ShellUpdater? Function() _shellProvider;

  UpdateCheckResult? result;
  bool checking = false;
  bool _autoChecked = false;

  ShellUpdater? get desktopUpdater => _shellProvider();

  bool get hasDesktopUpdater => desktopUpdater != null;

  bool get updateAvailable => result?.available == true;

  /// True when this surface can download and install the update itself.
  bool get canSelfUpdate => hasDesktopUpdater && result?.installable == true;

  /// True only after the packaged macOS shell successfully detects an
  /// installable release across a major-version compatibility boundary.
  bool get requiresMajorUpdate {
    final value = result;
    final latest = value?.latest;
    return value != null &&
        value.error == null &&
        value.available &&
        canSelfUpdate &&
        latest != null &&
        isMajorVersionUpgrade(latest, value.current);
  }

  /// True when a shell is present but declines to install in place, which is
  /// how unpackaged development builds report themselves.
  bool get shellDeclinesInstall =>
      hasDesktopUpdater && result?.installable != true;

  /// Checks once per app launch, and only inside the macOS desktop shell.
  Future<void> autoCheck() async {
    if (_autoChecked || !hasDesktopUpdater) return;
    _autoChecked = true;
    await refresh(force: false);
  }

  /// Re-checks from the macOS shell's 24-hour timer without bypassing its
  /// persisted throttle.
  Future<void> backgroundCheck() async {
    if (!hasDesktopUpdater) return;
    await refresh(force: false);
  }

  Future<void> refresh({bool force = true}) async {
    if (checking) return;
    checking = true;
    notifyListeners();
    UpdateCheckResult value;
    final shell = desktopUpdater;
    try {
      value = shell == null
          ? await checkLatestRelease()
          : UpdateCheckResult.fromShell(await shell.check(force: force));
    } on Object catch (error) {
      value = UpdateCheckResult(
        current: clawnsoleVersion,
        error: error.toString().replaceFirst('Exception: ', ''),
      );
    }
    result = value;
    checking = false;
    notifyListeners();
  }
}

ShellUpdater? _defaultShellUpdater() => shellUpdater;
