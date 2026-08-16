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
  UpdateStatus._();

  static final UpdateStatus instance = UpdateStatus._();

  UpdateCheckResult? result;
  bool checking = false;
  bool _autoChecked = false;

  bool get updateAvailable => result?.available == true;

  /// True when this surface can download and install the update itself.
  bool get canSelfUpdate => shellUpdater != null && result?.installable == true;

  /// True when a shell is present but declines to install in place, which is
  /// how unpackaged development builds report themselves.
  bool get shellDeclinesInstall =>
      shellUpdater != null && result?.installable != true;

  /// Checks once per app launch. Store-managed platforms skip it entirely.
  Future<void> autoCheck() async {
    if (_autoChecked || storeManagedPlatform) return;
    _autoChecked = true;
    await refresh();
  }

  Future<void> refresh() async {
    if (checking) return;
    checking = true;
    notifyListeners();
    UpdateCheckResult value;
    final shell = shellUpdater;
    try {
      value = shell == null
          ? await checkLatestRelease()
          : UpdateCheckResult.fromShell(await shell.check());
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
