import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import '../core/models.dart';
import '../core/provider_catalog.dart';

/// Failed generations start a new attempt from their saved recipe; completed
/// generations continue to restore their settings into the composer.
Future<void> reuseOrRetryGeneration(
  BuildContext context,
  AppController controller,
  Generation item,
) async {
  if (!item.isFailed || item.hasDeliveredMedia) {
    await controller.reuse(item);
    return;
  }
  await controller.retryGeneration(
    item,
    confirm: (confirmation) async {
      if (!context.mounted) return false;
      if (confirmation.needsMediaSharingConsent &&
          !await showMediaSharingConsent(context, controller)) {
        return false;
      }
      if (!context.mounted) return false;
      if (confirmation.requiresProviderRetentionAcknowledgement) {
        final suppressFutureWarnings = await _showProviderRetentionWarning(
          context,
          confirmation.provider,
        );
        if (suppressFutureWarnings == null || !context.mounted) return false;
        if (suppressFutureWarnings) {
          try {
            await controller.acknowledgeProviderRetentionRisk(
              providerId: confirmation.provider.id,
            );
          } on Object catch (error) {
            controller.showErrorNotice(error);
            return false;
          }
        }
      }
      return true;
    },
  );
}

Future<void> submitWithProviderWarnings(
  BuildContext context,
  AppController controller,
) async {
  if (controller.needsTemporaryMediaHosting) {
    await controller.refreshTemporaryMediaHostingStatus();
    if (!context.mounted) return;
    if (controller.needsMediaHostingSetup) {
      controller.showNotice(controller.publicMediaUrlHint);
      return;
    }
    if (controller.needsMediaSharingConsent &&
        !await showMediaSharingConsent(context, controller)) {
      return;
    }
    if (!context.mounted) return;
  }
  if (controller.requiresProviderRetentionAcknowledgement) {
    final suppressFutureWarnings = await _showProviderRetentionWarning(
      context,
      controller.selectedProvider,
    );
    if (suppressFutureWarnings == null || !context.mounted) return;
    if (suppressFutureWarnings) {
      try {
        await controller.acknowledgeProviderRetentionRisk();
      } on Object catch (error) {
        controller.showErrorNotice(error);
        return;
      }
    }
    await controller.submit(providerRetentionRiskAcknowledged: true);
    return;
  }
  await controller.submit();
}

Future<bool> showMediaSharingConsent(
  BuildContext context,
  AppController controller,
) async {
  final shown = controller.temporaryMediaHostingStatus;
  if (shown == null || !shown.available) return false;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const ValueKey('media-sharing-consent-dialog'),
      title: const Text('Allow iCloud references?'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Text(controller.mediaSharingDisclosure),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('confirm-media-sharing'),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Allow iCloud references'),
        ),
      ],
    ),
  );
  if (accepted != true || !context.mounted) return false;
  return controller.acceptTemporaryMediaSharing(shown);
}

/// Returns whether later warnings should be suppressed, or null when canceled.
Future<bool?> _showProviderRetentionWarning(
  BuildContext context,
  VideoProviderDefinition provider,
) async {
  var understood = false;
  var suppressFutureWarnings = false;
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        icon: Icon(
          Icons.warning_amber_rounded,
          color: context.colors.error,
          size: 30,
        ),
        title: Text('Keep Clawnsole open for ${provider.name}'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'When generating with ${provider.name}, keep Clawnsole '
                  'open and active and maintain an internet connection '
                  'until Clawnsole confirms the result is saved.',
                ),
                const SizedBox(height: 12),
                Text(_providerRetentionDetail(provider)),
                const SizedBox(height: 12),
                const Text(
                  'If Clawnsole cannot retrieve the completed result in '
                  'time, you may lose access to the generation even if '
                  'the provider charged for it.',
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  key: const ValueKey('provider-retention-warning-checkbox'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: understood,
                  onChanged: (value) =>
                      setState(() => understood = value ?? false),
                  title: const Text(
                    'I understand that closing or backgrounding the app '
                    'or going offline may cause me to lose this result.',
                  ),
                ),
                CheckboxListTile(
                  key: const ValueKey(
                    'suppress-provider-retention-warning-checkbox',
                  ),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: suppressFutureWarnings,
                  onChanged: (value) =>
                      setState(() => suppressFutureWarnings = value ?? false),
                  title: Text(
                    "Don't show this warning again for ${provider.name}.",
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('accept-provider-retention-warning'),
            onPressed: understood
                ? () => Navigator.pop(dialogContext, suppressFutureWarnings)
                : null,
            child: const Text('Accept & generate'),
          ),
        ],
      ),
    ),
  );
}

String _providerRetentionDetail(VideoProviderDefinition provider) {
  final availability = provider.resultDelivery.availability;
  if (availability == null) {
    return '${provider.name} does not publish a dependable result-retention '
        'window, so later retrieval cannot be guaranteed.';
  }
  final minutes = availability.inMinutes;
  final window = minutes % (24 * 60) == 0
      ? '${minutes ~/ (24 * 60)} ${minutes == 24 * 60 ? 'day' : 'days'}'
      : minutes % 60 == 0
      ? '${minutes ~/ 60} ${minutes == 60 ? 'hour' : 'hours'}'
      : '$minutes ${minutes == 1 ? 'minute' : 'minutes'}';
  return '${provider.name} hosts completed results for only $window after '
      'completion.';
}
