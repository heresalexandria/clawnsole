import 'package:flutter/foundation.dart';

import 'app_version.dart';
import 'shell_bridge.dart';
import 'update_check.dart';

/// Whether the operating system's store owns installation for this build.
bool get storeManagedPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android);

/// The app-wide answer to "is there a newer Clawnsole?".
///
/// One instance backs both the version chip's badge and the version dialog so
/// a launch-time check is reused instead of repeated per surface.
class UpdateStatus extends ChangeNotifier {
  UpdateStatus._()
    : _shellProvider = _defaultShellUpdater,
      _storeManagedProvider = _defaultStoreManagedPlatform,
      _releaseChecker = checkLatestRelease;

  @visibleForTesting
  UpdateStatus.forTesting(ShellUpdater updater)
    : _shellProvider = (() => updater),
      _storeManagedProvider = (() => false),
      _releaseChecker = checkLatestRelease;

  @visibleForTesting
  UpdateStatus.forMobileTesting(
    Future<UpdateCheckResult> Function() releaseChecker,
  ) : this.forReleaseTesting(releaseChecker, storeManaged: true);

  @visibleForTesting
  UpdateStatus.forReleaseTesting(
    Future<UpdateCheckResult> Function() releaseChecker, {
    bool storeManaged = false,
  }) : _shellProvider = (() => null),
       _storeManagedProvider = (() => storeManaged),
       _releaseChecker = releaseChecker;

  static final UpdateStatus instance = UpdateStatus._();

  final ShellUpdater? Function() _shellProvider;
  final bool Function() _storeManagedProvider;
  final Future<UpdateCheckResult> Function() _releaseChecker;

  UpdateCheckResult? result;
  bool checking = false;
  bool _autoChecked = false;

  ShellUpdater? get desktopUpdater => _shellProvider();

  bool get hasDesktopUpdater => desktopUpdater != null;

  bool get isStoreManaged => _storeManagedProvider();

  /// Every supported surface can query the public stable-release endpoint.
  bool get supportsAutomaticChecks => true;

  bool get updateAvailable => result?.available == true;

  /// True when this surface can download and install the update itself.
  bool get canSelfUpdate => hasDesktopUpdater && result?.installable == true;

  /// True when iOS or Android must hand the update off to its app store.
  bool get requiresStoreUpdate => isStoreManaged && _isMajorUpdateDetected;

  /// True only after a supported update path successfully detects a release
  /// across a major-version compatibility boundary.
  bool get requiresMajorUpdate =>
      _isMajorUpdateDetected && (canSelfUpdate || isStoreManaged);

  bool get _isMajorUpdateDetected {
    final value = result;
    final latest = value?.latest;
    return value != null &&
        value.error == null &&
        value.available &&
        latest != null &&
        isMajorVersionUpgrade(latest, value.current);
  }

  /// True when a shell is present but declines to install in place, which is
  /// how unpackaged development builds report themselves.
  bool get shellDeclinesInstall =>
      hasDesktopUpdater && result?.installable != true;

  /// Checks once per app launch on every supported surface.
  ///
  /// A launch check is always fresh. The macOS shell keeps its own persisted
  /// result for background throttling, but reusing that result here could hide
  /// a release published since the previous launch until the version was
  /// clicked manually.
  Future<void> autoCheck() async {
    if (_autoChecked || !supportsAutomaticChecks) return;
    _autoChecked = true;
    await refresh(force: true);
  }

  /// Re-checks from the 24-hour timer without bypassing the macOS shell's
  /// persisted throttle.
  Future<void> backgroundCheck() async {
    if (!supportsAutomaticChecks) return;
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
          ? await _releaseChecker()
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

bool _defaultStoreManagedPlatform() => storeManagedPlatform;
