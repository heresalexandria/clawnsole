import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/app_theme.dart';
import '../core/app_version.dart';
import '../core/shell_bridge.dart';
import '../core/store_update.dart';
import '../core/update_status.dart';
import 'claw_mark.dart';
import 'formatters.dart';

/// One stream of update progress: what the desktop shell reports, plus
/// failures the app detects on its own. Both the launch-time listener and the
/// progress modal read from here, so an update started from the system menu
/// and one started in the app look identical.
final StreamController<ShellUpdateEvent> _updateEvents =
    StreamController<ShellUpdateEvent>.broadcast();
StreamSubscription<ShellUpdateEvent>? _shellSubscription;

Stream<ShellUpdateEvent> get updateEvents {
  _shellSubscription ??= shellUpdater?.events.listen(_updateEvents.add);
  return _updateEvents.stream;
}

void reportUpdateFailure(String message) =>
    _updateEvents.add(ShellUpdateEvent(phase: 'error', message: message));

/// Starts a verified in-place macOS update and opens the shared progress UI.
Future<bool> startAvailableUpdate(
  NavigatorState navigator, {
  ShellUpdater? updater,
}) async {
  final active = updater ?? shellUpdater;
  if (active == null) return false;
  unawaited(showUpdateProgressDialog(navigator));
  try {
    final outcome = await active.start();
    if (outcome['started'] == true) return true;
    reportUpdateFailure(
      outcome['error']?.toString() ?? 'Clawnsole could not start this update.',
    );
  } on Object catch (error) {
    reportUpdateFailure(error.toString().replaceFirst('Exception: ', ''));
  }
  return false;
}

/// Shows the running version, whether a newer release exists, and — where the
/// shell can do it — installs that release in place.
Future<void> showVersionDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => const _VersionDialog(),
);

class _VersionDialog extends StatefulWidget {
  const _VersionDialog();

  @override
  State<_VersionDialog> createState() => _VersionDialogState();
}

class _VersionDialogState extends State<_VersionDialog> {
  final UpdateStatus _status = UpdateStatus.instance;

  @override
  void initState() {
    super.initState();
    // Opening the dialog is an explicit ask, so re-check rather than trusting
    // the launch-time result — except where the store owns updates, since a
    // GitHub tag says nothing about what the mobile store has published.
    if (!storeManagedPlatform) unawaited(_status.refresh());
  }

  Future<void> _install() async {
    final navigator = Navigator.of(context);
    navigator.pop();
    await startAvailableUpdate(navigator, updater: _status.desktopUpdater);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _status,
    builder: (context, _) {
      final result = _status.result;
      final checking = _status.checking && result == null;
      final available = _status.updateAvailable;
      final canSelfUpdate = _status.canSelfUpdate;
      final storeName =
          clawnsoleStoreDestination(defaultTargetPlatform)?.name ?? 'app store';
      return AlertDialog(
        title: Row(
          children: <Widget>[
            ClawMark(size: 22, color: context.tokens.brass),
            const SizedBox(width: 10),
            const Expanded(child: Text('Clawnsole')),
            Text(
              'v$clawnsoleVersion',
              style: TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: storeManagedPlatform
              ? _DialogLine(
                  icon: Icons.storefront_rounded,
                  text: 'Updates for this app arrive through $storeName.',
                )
              : checking
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: <Widget>[
                      SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text('Checking for a newer release…'),
                    ],
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (result?.error != null)
                      _DialogLine(
                        icon: Icons.cloud_off_rounded,
                        text:
                            'Clawnsole could not check for updates.\n${result!.error}',
                      )
                    else if (available) ...<Widget>[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: context.colors.primaryContainer,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              Icons.new_releases_rounded,
                              size: 18,
                              color: context.colors.onPrimaryContainer,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                'Clawnsole ${result!.latest} is available.',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: context.colors.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        canSelfUpdate
                            ? 'Clawnsole verifies the download against the release checksums, installs it in place, and reopens itself.'
                            : storeManagedPlatform
                            ? 'Updates for this app arrive through $storeName.'
                            : _status.shellDeclinesInstall
                            ? 'This development build updates from source with git rather than replacing itself.'
                            : 'This build can open the GitHub release for a manual update.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ] else
                      _DialogLine(
                        icon: Icons.check_circle_outline_rounded,
                        iconColor: context.tokens.brass,
                        text: 'You are running the latest release.',
                      ),
                    if (_status.checking && result != null) ...<Widget>[
                      const SizedBox(height: 12),
                      Row(
                        children: <Widget>[
                          const SizedBox.square(
                            dimension: 13,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 9),
                          Text(
                            'Checking again…',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
        ),
        actions: <Widget>[
          if (!storeManagedPlatform && !checking && !available)
            OutlinedButton.icon(
              onPressed: _status.checking
                  ? null
                  : () => unawaited(_status.refresh()),
              icon: const Icon(Icons.refresh_rounded, size: 15),
              label: const Text('Check again'),
            ),
          if (!storeManagedPlatform && !checking && available && canSelfUpdate)
            FilledButton.icon(
              onPressed: () => unawaited(_install()),
              icon: const Icon(Icons.download_rounded, size: 16),
              label: Text('Download and install ${result!.latest}'),
            )
          else if (!storeManagedPlatform && !checking && available)
            FilledButton.icon(
              onPressed: () =>
                  unawaited(launchUrl(Uri.parse(result!.releaseUrl))),
              icon: const Icon(Icons.open_in_new_rounded, size: 15),
              label: const Text('View release'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

class _DialogLine extends StatelessWidget {
  const _DialogLine({required this.icon, required this.text, this.iconColor});

  final IconData icon;
  final String text;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Icon(icon, size: 17, color: iconColor ?? context.colors.onSurfaceVariant),
      const SizedBox(width: 9),
      Expanded(child: Text(text, style: const TextStyle(height: 1.45))),
    ],
  );
}

bool _progressDialogOpen = false;

/// Shows a blocking modal that follows an in-place update from first byte to
/// relaunch. Safe to call more than once; only one opens.
Future<void> showUpdateProgressDialog(NavigatorState navigator) async {
  if (_progressDialogOpen || !navigator.mounted) return;
  _progressDialogOpen = true;
  try {
    await showDialog<void>(
      context: navigator.context,
      barrierDismissible: false,
      builder: (context) => const _UpdateProgressDialog(),
    );
  } finally {
    _progressDialogOpen = false;
  }
}

class _UpdateProgressDialog extends StatefulWidget {
  const _UpdateProgressDialog();

  @override
  State<_UpdateProgressDialog> createState() => _UpdateProgressDialogState();
}

class _UpdateProgressDialogState extends State<_UpdateProgressDialog> {
  StreamSubscription<ShellUpdateEvent>? _subscription;
  ShellUpdateEvent _latest = const ShellUpdateEvent(phase: 'downloading');

  @override
  void initState() {
    super.initState();
    _subscription = updateEvents.listen((event) {
      if (mounted) setState(() => _latest = event);
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final event = _latest;
    final failed = event.phase == 'error';
    final installing = event.phase == 'installing';
    final title = failed
        ? 'Update failed'
        : installing
        ? 'Installing Clawnsole ${event.version ?? ''}'.trim()
        : 'Downloading Clawnsole ${event.version ?? ''}'.trim();
    final detail = failed
        ? (event.message ?? 'The update could not be installed.')
        : installing
        ? 'The download was verified against the release checksums. Clawnsole will close and reopen itself in a moment.'
        : event.received != null && event.total != null && event.total! > 0
        ? '${formatBytes(event.received!)} of ${formatBytes(event.total!)}'
        : 'Contacting GitHub releases…';
    return PopScope(
      canPop: failed,
      child: AlertDialog(
        title: Row(
          children: <Widget>[
            ClawMark(size: 20, color: context.tokens.brass),
            const SizedBox(width: 10),
            Expanded(child: Text(title)),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (!failed) ...<Widget>[
                LinearProgressIndicator(
                  value: installing ? null : event.fraction,
                  minHeight: 7,
                  borderRadius: BorderRadius.circular(99),
                  backgroundColor: context.colors.surfaceContainerHigh,
                ),
                const SizedBox(height: 12),
              ],
              Text(detail, style: const TextStyle(height: 1.45)),
            ],
          ),
        ),
        actions: <Widget>[
          if (failed)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
        ],
      ),
    );
  }
}
