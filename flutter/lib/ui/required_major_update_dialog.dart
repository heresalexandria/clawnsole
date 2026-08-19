import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import '../core/store_update.dart';
import '../core/update_status.dart';
import 'claw_mark.dart';
import 'update_dialog.dart';

/// Blocks the app behind a breaking release with a supported update path.
Future<void> showRequiredMajorUpdateDialog(
  NavigatorState navigator, {
  required UpdateStatus status,
  StoreUpdateOpener? storeUpdateOpener,
}) => showDialog<void>(
  context: navigator.context,
  barrierDismissible: false,
  builder: (context) => RequiredMajorUpdateDialog(
    status: status,
    storeUpdateOpener: storeUpdateOpener,
  ),
);

class RequiredMajorUpdateDialog extends StatefulWidget {
  const RequiredMajorUpdateDialog({
    required this.status,
    this.storeUpdateOpener,
    super.key,
  });

  final UpdateStatus status;
  final StoreUpdateOpener? storeUpdateOpener;

  @override
  State<RequiredMajorUpdateDialog> createState() =>
      _RequiredMajorUpdateDialogState();
}

class _RequiredMajorUpdateDialogState extends State<RequiredMajorUpdateDialog> {
  bool _starting = false;
  String? _storeError;

  Future<void> _update() async {
    if (_starting) return;
    setState(() {
      _starting = true;
      _storeError = null;
    });
    if (widget.status.requiresStoreUpdate) {
      final opener = widget.storeUpdateOpener ?? openClawnsoleStore;
      final opened = await opener(defaultTargetPlatform);
      if (!mounted) return;
      setState(() {
        _starting = false;
        if (!opened) {
          _storeError =
              'Clawnsole could not open the store. Check your connection and '
              'try again.';
        }
      });
      return;
    }
    final started = await startAvailableUpdate(
      Navigator.of(context),
      updater: widget.status.desktopUpdater,
    );
    if (mounted && !started) setState(() => _starting = false);
  }

  @override
  Widget build(BuildContext context) {
    final latest = widget.status.result?.latest ?? 'the latest version';
    final storeDestination = widget.status.requiresStoreUpdate
        ? clawnsoleStoreDestination(defaultTargetPlatform)
        : null;
    final storeName = storeDestination?.name ?? 'app store';
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Row(
          children: <Widget>[
            ClawMark(size: 22, color: context.tokens.brass),
            const SizedBox(width: 10),
            const Expanded(child: Text('Required update')),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.colors.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.security_update_good_rounded,
                      color: context.colors.onPrimaryContainer,
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        'Clawnsole $latest is required.',
                        style: TextStyle(
                          color: context.colors.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'This major release includes breaking compatibility changes. '
                'Update Clawnsole before continuing to use the app.',
                style: TextStyle(
                  height: 1.5,
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                storeDestination != null
                    ? 'Install the update from $storeName, then reopen '
                          'Clawnsole.'
                    : 'The download is verified against the release '
                          'checksums, installed in place, and Clawnsole '
                          'reopens automatically.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              if (_storeError != null) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  _storeError!,
                  key: const Key('required-major-update-store-error'),
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: context.colors.error,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: <Widget>[
          FilledButton.icon(
            key: const Key('required-major-update-button'),
            onPressed: _starting ? null : () => unawaited(_update()),
            icon: _starting
                ? const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    storeDestination != null
                        ? Icons.open_in_new_rounded
                        : Icons.download_rounded,
                    size: 17,
                  ),
            label: Text(
              _starting
                  ? storeDestination != null
                        ? 'Opening $storeName…'
                        : 'Starting update…'
                  : storeDestination != null
                  ? 'Open $storeName'
                  : 'Update to $latest',
            ),
          ),
        ],
      ),
    );
  }
}
