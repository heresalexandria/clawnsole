import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import '../core/app_links.dart';
import '../core/google_drive.dart';
import '../core/models.dart';
import '../core/provider_catalog.dart';
import 'claw_mark.dart';
import 'common_widgets.dart';
import 'panels.dart';
import 'formatters.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({required this.controller, super.key});

  final AppController controller;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<bool> _confirm(String title, String detail) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(detail),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final split = constraints.maxWidth >= 1050;
      final main = Column(
        children: <Widget>[
          _GenerationAppearanceCard(controller: widget.controller),
          const SizedBox(height: 18),
          _ProviderAccessCard(controller: widget.controller),
          if (widget.controller.supportsGoogleDrive) ...<Widget>[
            const SizedBox(height: 18),
            _GoogleDriveSection(controller: widget.controller),
          ],
          const SizedBox(height: 18),
          _StorageSection(controller: widget.controller),
        ],
      );
      final side = _SettingsSide(
        controller: widget.controller,
        confirm: _confirm,
      );
      return SingleChildScrollView(
        padding: EdgeInsets.all(constraints.maxWidth < 620 ? 16 : 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1320),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Eyebrow('Personal setup', icon: Icons.tune_rounded),
                const SizedBox(height: 10),
                Text(
                  'Settings.',
                  style: Theme.of(context).textTheme.displayLarge,
                ),
                const SizedBox(height: 10),
                Text(
                  widget.controller.supportsGoogleDrive
                      ? 'Manage appearance, Drive sync, and this device’s private keys.'
                      : 'Manage appearance, updates, and Clawnsole’s private local data.',
                ),
                const SizedBox(height: 24),
                if (split)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(flex: 7, child: main),
                      const SizedBox(width: 20),
                      Expanded(flex: 4, child: side),
                    ],
                  )
                else ...<Widget>[main, const SizedBox(height: 18), side],
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _GenerationAppearanceCard extends StatelessWidget {
  const _GenerationAppearanceCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CircleAvatar(
          backgroundColor: context.colors.primaryContainer,
          child: Icon(
            Icons.live_tv_rounded,
            color: context.colors.onPrimaryContainer,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Generation appearance',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Choose what plays in the preview while a video is rendering.',
                style: TextStyle(color: context.colors.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<GenerationPlaceholderStyle>(
                key: const ValueKey('generation-placeholder-style'),
                initialValue: controller.generationPlaceholderStyle,
                decoration: const InputDecoration(
                  labelText: 'Generation Placeholder',
                  helperText:
                      'Static recreates analog broadcast snow; Cyclone keeps the luminous ribbon field.',
                ),
                items: GenerationPlaceholderStyle.values
                    .map(
                      (style) => DropdownMenuItem<GenerationPlaceholderStyle>(
                        value: style,
                        child: Text(style.label),
                      ),
                    )
                    .toList(),
                onChanged: (style) {
                  if (style != null) {
                    unawaited(controller.setGenerationPlaceholderStyle(style));
                  }
                },
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ProviderAccessCard extends StatelessWidget {
  const _ProviderAccessCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final summary = Row(
          children: <Widget>[
            CircleAvatar(
              backgroundColor: context.colors.primaryContainer,
              child: Icon(
                Icons.hub_rounded,
                color: context.colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Provider access moved to its own desk',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 4),
                  Text(
                    controller.supportsLocalLibrary
                        ? 'Set provider keys and compare live model costs in Providers.'
                        : 'Set an Atlas Cloud key for the verified backend-free Pages route.',
                  ),
                ],
              ),
            ),
          ],
        );
        final action = FilledButton.icon(
          onPressed: () => unawaited(controller.navigate(AppSection.providers)),
          icon: const Icon(Icons.arrow_forward_rounded, size: 17),
          label: const Text('Open Providers'),
        );

        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[summary, const SizedBox(height: 14), action],
          );
        }
        return Row(
          children: <Widget>[
            Expanded(child: summary),
            const SizedBox(width: 16),
            action,
          ],
        );
      },
    ),
  );
}

class _StorageSection extends StatelessWidget {
  const _StorageSection({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            CircleAvatar(
              backgroundColor: context.colors.secondaryContainer,
              child: Icon(
                Icons.storage_rounded,
                color: context.colors.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    controller.supportsGoogleDrive
                        ? controller.supportsLocalLibrary
                              ? 'Combined project data'
                              : 'Drive project data'
                        : 'Local project data',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    controller.supportsGoogleDrive
                        ? controller.supportsLocalLibrary
                              ? 'Local and Drive metadata, retained inputs, and finished media.'
                              : 'Drive metadata, retained inputs, and finished media.'
                        : 'Compact JSON plus retained reference inputs and finished videos.',
                  ),
                ],
              ),
            ),
            Text(
              formatBytes(
                controller.storage.bytes + controller.storage.assetBytes,
              ),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: <Widget>[
            Expanded(
              child: _Stat(
                value: formatBytes(controller.storage.bytes),
                label: 'Metadata',
              ),
            ),
            Expanded(
              child: _Stat(
                value: formatBytes(controller.storage.assetBytes),
                label: '${controller.storage.assets} assets',
              ),
            ),
            Expanded(
              child: _Stat(
                value: '${controller.storage.records}',
                label: 'Generations',
              ),
            ),
            Expanded(
              child: _Stat(
                value: controller.storage.lastUpdated == null
                    ? 'Not yet'
                    : relativeTime(controller.storage.lastUpdated!),
                label: 'Last write',
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'DATA FILE',
                style: TextStyle(
                  fontSize: 9.5,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700,
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 5),
              SelectableText(
                controller.storage.path.isEmpty
                    ? 'Not created yet'
                    : controller.storage.path,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
              const SizedBox(height: 8),
              Text(
                controller.gateway.persistenceDescription,
                style: const TextStyle(fontSize: 11.5, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _GoogleDriveSection extends StatefulWidget {
  const _GoogleDriveSection({required this.controller});

  final AppController controller;

  @override
  State<_GoogleDriveSection> createState() => _GoogleDriveSectionState();
}

class _GoogleDriveSectionState extends State<_GoogleDriveSection> {
  late final TextEditingController _folder = TextEditingController(
    text: widget.controller.googleDriveConnection.folderName.isEmpty
        ? 'Clawnsole'
        : widget.controller.googleDriveConnection.folderName,
  );

  @override
  void dispose() {
    _folder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connection = widget.controller.googleDriveConnection;
    final connected = connection.isConnected;
    final unavailable =
        connection.state == GoogleDriveConnectionState.unavailable;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              CircleAvatar(
                backgroundColor: context.colors.primaryContainer,
                child: Icon(
                  Icons.cloud_sync_rounded,
                  color: context.colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Google Drive library',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      connected
                          ? connection.accountLabel.isEmpty
                                ? 'Synced with “${connection.folderName}”.'
                                : 'Synced with “${connection.folderName}” as ${connection.accountLabel}.'
                          : 'Use one portable library across every Clawnsole surface.',
                    ),
                  ],
                ),
              ),
              Icon(
                connected ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                color: connected
                    ? context.colors.primary
                    : context.colors.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _folder,
            enabled: !connected && !widget.controller.googleDriveBusy,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: 'Drive folder name',
              helperText:
                  'Clawnsole creates or reopens an app-owned folder with this name.',
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              if (!connected)
                FilledButton.icon(
                  onPressed: unavailable || widget.controller.googleDriveBusy
                      ? null
                      : () =>
                            widget.controller.connectGoogleDrive(_folder.text),
                  icon: widget.controller.googleDriveBusy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_to_drive_rounded, size: 18),
                  label: const Text('Connect Drive'),
                )
              else ...<Widget>[
                FilledButton.tonalIcon(
                  onPressed: widget.controller.googleDriveBusy
                      ? null
                      : widget.controller.refreshGoogleDrive,
                  icon: const Icon(Icons.sync_rounded, size: 18),
                  label: const Text('Refresh'),
                ),
                OutlinedButton.icon(
                  onPressed: widget.controller.googleDriveBusy
                      ? null
                      : widget.controller.disconnectGoogleDrive,
                  icon: const Icon(Icons.link_off_rounded, size: 18),
                  label: const Text('Disconnect this device'),
                ),
                if (widget.controller.supportsLocalLibrary &&
                    (widget.controller.generations.any(
                          (item) => item.storage == LibraryStorage.local,
                        ) ||
                        widget.controller.savedReferences.any(
                          (item) => item.storage == LibraryStorage.local,
                        )))
                  OutlinedButton.icon(
                    onPressed: widget.controller.googleDriveBusy
                        ? null
                        : widget.controller.copyLocalLibraryToGoogleDrive,
                    icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                    label: const Text('Copy local library to Drive'),
                  ),
              ],
            ],
          ),
          if (connected) ...<Widget>[
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Default for new generations and references',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(width: 12),
                StorageDestinationButton(controller: widget.controller),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              unavailable
                  ? connection.message
                  : 'Drive items include generated media, references, and folders. Provider keys and preferences stay in secure storage and sync only through your passphrase-encrypted vault when enabled. Copying local items keeps the originals.',
              style: const TextStyle(fontSize: 11.5, height: 1.4),
            ),
          ),
          if (connection.message.isNotEmpty && !unavailable) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              connection.message,
              style: TextStyle(
                fontSize: 11,
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
          if (widget.controller.supportsSettingsVault) ...<Widget>[
            const Divider(height: 32),
            _SettingsVaultPanel(controller: widget.controller),
          ],
        ],
      ),
    );
  }
}

class _SettingsVaultPassphraseDialog extends StatefulWidget {
  const _SettingsVaultPassphraseDialog({
    required this.title,
    required this.detail,
    required this.actionLabel,
    required this.confirm,
  });

  final String title;
  final String detail;
  final String actionLabel;
  final bool confirm;

  @override
  State<_SettingsVaultPassphraseDialog> createState() =>
      _SettingsVaultPassphraseDialogState();
}

class _SettingsVaultPassphraseDialogState
    extends State<_SettingsVaultPassphraseDialog> {
  static const _maximumEncodedBytes = 1024;

  final _passphrase = TextEditingController();
  final _confirmation = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _passphrase.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _passphrase.text;
    if (value.isEmpty || (widget.confirm && value.runes.length < 12)) {
      setState(() {
        _error = widget.confirm
            ? 'Enter at least 12 characters.'
            : 'Enter your sync passphrase.';
      });
      return;
    }
    if (utf8.encode(value).length > _maximumEncodedBytes) {
      setState(() {
        _error = 'The passphrase must be at most 1,024 encoded bytes.';
      });
      return;
    }
    if (widget.confirm && value != _confirmation.text) {
      setState(() {
        _error = 'The passphrases do not match exactly.';
      });
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(widget.detail),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('settings-vault-passphrase'),
              controller: _passphrase,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              autofocus: true,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Sync passphrase',
                helperText: widget.confirm
                    ? 'Use at least 12 characters. Spaces count.'
                    : 'Enter it exactly. Spaces count.',
              ),
            ),
            if (widget.confirm) ...<Widget>[
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('settings-vault-passphrase-confirmation'),
                controller: _confirmation,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: 'Confirm sync passphrase',
                ),
              ),
            ],
            if (_error != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                _error!,
                key: const ValueKey('settings-vault-passphrase-error'),
                style: TextStyle(color: context.colors.error),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('settings-vault-passphrase-submit'),
        onPressed: _submit,
        child: Text(widget.actionLabel),
      ),
    ],
  );
}

class _SettingsVaultRecoveryDialog extends StatefulWidget {
  const _SettingsVaultRecoveryDialog();

  @override
  State<_SettingsVaultRecoveryDialog> createState() =>
      _SettingsVaultRecoveryDialogState();
}

class _SettingsVaultRecoveryDialogState
    extends State<_SettingsVaultRecoveryDialog> {
  final _recoveryCode = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _recoveryCode.dispose();
    super.dispose();
  }

  void _submit() {
    if (_recoveryCode.text.isEmpty) {
      setState(() => _error = 'Enter your recovery code.');
      return;
    }
    Navigator.pop(context, _recoveryCode.text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Use recovery code'),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text(
            'Enter the recovery code exactly as it was shown when the vault was created.',
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('settings-vault-recovery-input'),
            controller: _recoveryCode,
            autocorrect: false,
            enableSuggestions: false,
            autofocus: true,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(labelText: 'Recovery code'),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: context.colors.error)),
          ],
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('settings-vault-recovery-submit'),
        onPressed: _submit,
        child: const Text('Recover'),
      ),
    ],
  );
}

class _SettingsVaultPanel extends StatefulWidget {
  const _SettingsVaultPanel({required this.controller});

  final AppController controller;

  @override
  State<_SettingsVaultPanel> createState() => _SettingsVaultPanelState();
}

class _SettingsVaultPanelState extends State<_SettingsVaultPanel> {
  Future<String?> _requestPassphrase({
    required String title,
    required String detail,
    required String actionLabel,
    bool confirm = false,
  }) => showDialog<String>(
    context: context,
    builder: (dialogContext) => _SettingsVaultPassphraseDialog(
      title: title,
      detail: detail,
      actionLabel: actionLabel,
      confirm: confirm,
    ),
  );

  Future<String?> _requestRecoveryCode() => showDialog<String>(
    context: context,
    builder: (dialogContext) => const _SettingsVaultRecoveryDialog(),
  );

  Future<void> _showRecoveryCode(String recoveryCode) async {
    var acknowledged = false;
    var copied = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => PopScope(
          canPop: acknowledged,
          child: AlertDialog(
            title: const Text('Save your recovery code'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text(
                    'This is shown once. Store it in a password manager. It can unlock your encrypted settings if you forget the passphrase.',
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SelectableText(
                      recoveryCode,
                      key: const ValueKey('settings-vault-recovery-code'),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    key: const ValueKey('settings-vault-recovery-copy'),
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: recoveryCode),
                      );
                      setDialogState(() => copied = true);
                    },
                    icon: Icon(
                      copied ? Icons.check_rounded : Icons.copy_rounded,
                      size: 17,
                    ),
                    label: Text(copied ? 'Copied' : 'Copy recovery code'),
                  ),
                  CheckboxListTile(
                    key: const ValueKey('settings-vault-recovery-ack'),
                    contentPadding: EdgeInsets.zero,
                    value: acknowledged,
                    onChanged: (value) =>
                        setDialogState(() => acknowledged = value == true),
                    title: const Text(
                      'I saved this recovery code somewhere safe.',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              FilledButton(
                key: const ValueKey('settings-vault-recovery-done'),
                onPressed: acknowledged
                    ? () => Navigator.pop(dialogContext)
                    : null,
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _setup() async {
    final passphrase = await _requestPassphrase(
      title: 'Set up encrypted settings sync',
      detail:
          'Your provider keys and preferences will be encrypted before they are stored in Google Drive. You will enter this passphrase once on each new device.',
      actionLabel: 'Create vault',
      confirm: true,
    );
    if (passphrase == null || !mounted) return;
    final recoveryCode = await widget.controller.setupSettingsVault(passphrase);
    if (!mounted) return;
    setState(() {});
    if (recoveryCode != null && recoveryCode.isNotEmpty) {
      await _showRecoveryCode(recoveryCode);
    }
  }

  Future<void> _unlock() async {
    final passphrase = await _requestPassphrase(
      title: 'Unlock encrypted settings',
      detail:
          'Enter your sync passphrase once. Clawnsole will remember the vault key securely on this device.',
      actionLabel: 'Unlock',
    );
    if (passphrase == null || !mounted) return;
    await widget.controller.unlockSettingsVault(passphrase);
    if (mounted) setState(() {});
  }

  Future<void> _recover() async {
    final recoveryCode = await _requestRecoveryCode();
    if (recoveryCode == null || !mounted) return;
    await widget.controller.recoverSettingsVault(recoveryCode);
    if (mounted) setState(() {});
  }

  Future<void> _changePassphrase() async {
    final passphrase = await _requestPassphrase(
      title: 'Change sync passphrase',
      detail:
          'Use the new passphrase on future devices. Devices that already remember this vault remain connected.',
      actionLabel: 'Change passphrase',
      confirm: true,
    );
    if (passphrase == null || !mounted) return;
    await widget.controller.changeSettingsVaultPassphrase(passphrase);
    if (mounted) setState(() {});
  }

  Future<void> _forget() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Forget vault unlock on this device?'),
        content: const Text(
          'Your local provider keys and encrypted Drive vault will be kept. You will need the passphrase or recovery code before this device can sync them again.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('settings-vault-forget-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Forget unlock'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.controller.forgetSettingsVaultUnlock();
    if (mounted) setState(() {});
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset encrypted settings sync?'),
        content: const Text(
          'Use this only if the passphrase and recovery code are both lost. The encrypted vault on Drive will be replaced for every device. Provider keys and preferences on this device, plus your Drive library and media, will be kept. Other devices will need the new passphrase.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('settings-vault-reset-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Replace vault'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final passphrase = await _requestPassphrase(
      title: 'Create a new sync passphrase',
      detail:
          'This passphrase replaces the inaccessible vault. You will use it once on every other device.',
      actionLabel: 'Reset encrypted sync',
      confirm: true,
    );
    if (passphrase == null || !mounted) return;
    final recoveryCode = await widget.controller.resetSettingsVault(passphrase);
    if (!mounted) return;
    setState(() {});
    if (recoveryCode != null && recoveryCode.isNotEmpty) {
      await _showRecoveryCode(recoveryCode);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.controller.settingsVaultStatus;
    final busy =
        widget.controller.settingsVaultBusy ||
        status.state == SettingsVaultState.syncing;
    final (icon, title, detail) = switch (status.state) {
      SettingsVaultState.unavailable => (
        Icons.lock_outline_rounded,
        'Encrypted settings sync unavailable',
        'This build cannot access the secure settings vault.',
      ),
      SettingsVaultState.driveDisconnected => (
        Icons.cloud_off_rounded,
        'Encrypted settings sync paused',
        'Connect Google Drive to set up or resume encrypted provider-key and preference sync.',
      ),
      SettingsVaultState.setupRequired => (
        Icons.enhanced_encryption_outlined,
        'Protect and sync provider keys',
        'Create a sync passphrase once, then enter it on each new device. The passphrase is never stored.',
      ),
      SettingsVaultState.locked => (
        Icons.lock_rounded,
        'Encrypted settings are locked',
        status.localCredentialCount > 0 || status.hasLocalPreferences
            ? 'Unlocking will safely merge this device’s ${status.localCredentialCount} provider key${status.localCredentialCount == 1 ? '' : 's'}${status.hasLocalPreferences ? ' and preferences' : ''} with the encrypted Drive vault. Newer edits win per key and preference.'
            : 'This Drive has a Clawnsole vault. Unlock it once on this device with your passphrase or recovery code.',
      ),
      SettingsVaultState.syncing => (
        Icons.sync_rounded,
        'Syncing encrypted settings',
        'Provider keys and preferences are being encrypted and synchronized.',
      ),
      SettingsVaultState.ready => (
        Icons.verified_user_rounded,
        'Encrypted settings are synced',
        'Provider keys and preferences are encrypted before they leave this device.',
      ),
      SettingsVaultState.pending => (
        Icons.cloud_upload_outlined,
        'Encrypted settings sync pending',
        'Your latest settings are secure on this device and will remain pending until Drive sync succeeds.',
      ),
      SettingsVaultState.error => (
        Icons.sync_problem_rounded,
        'Encrypted settings need attention',
        'Your local provider keys remain available. Try syncing again or unlock the vault again if prompted.',
      ),
    };
    final message = status.message.trim();
    return Container(
      key: const ValueKey('settings-vault-panel'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, color: context.colors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(detail, style: const TextStyle(height: 1.35)),
                  ],
                ),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.only(left: 10),
                  child: SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
          if (status.lastSyncedAt != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              'Last synced ${relativeTime(status.lastSyncedAt!)}',
              style: TextStyle(
                fontSize: 11,
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
          if (message.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              message,
              key: const ValueKey('settings-vault-status-message'),
              style: TextStyle(
                fontSize: 11,
                color: status.state == SettingsVaultState.error
                    ? context.colors.error
                    : context.colors.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: switch (status.state) {
              SettingsVaultState.setupRequired => <Widget>[
                FilledButton.icon(
                  key: const ValueKey('settings-vault-setup'),
                  onPressed: busy ? null : _setup,
                  icon: const Icon(Icons.lock_rounded, size: 17),
                  label: const Text('Set up encrypted sync'),
                ),
              ],
              SettingsVaultState.locked => <Widget>[
                FilledButton.icon(
                  key: const ValueKey('settings-vault-unlock'),
                  onPressed: busy ? null : _unlock,
                  icon: const Icon(Icons.lock_open_rounded, size: 17),
                  label: const Text('Unlock with passphrase'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('settings-vault-recover'),
                  onPressed: busy ? null : _recover,
                  icon: const Icon(Icons.key_rounded, size: 17),
                  label: const Text('Use recovery code'),
                ),
                TextButton.icon(
                  key: const ValueKey('settings-vault-reset'),
                  onPressed: busy ? null : _reset,
                  icon: const Icon(Icons.restart_alt_rounded, size: 17),
                  label: const Text('Lost both? Reset encrypted sync'),
                ),
              ],
              SettingsVaultState.ready ||
              SettingsVaultState.pending => <Widget>[
                FilledButton.tonalIcon(
                  key: const ValueKey('settings-vault-sync'),
                  onPressed: busy ? null : widget.controller.syncSettingsVault,
                  icon: const Icon(Icons.sync_rounded, size: 17),
                  label: const Text('Sync now'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('settings-vault-change-passphrase'),
                  onPressed: busy ? null : _changePassphrase,
                  icon: const Icon(Icons.password_rounded, size: 17),
                  label: const Text('Change passphrase'),
                ),
                TextButton.icon(
                  key: const ValueKey('settings-vault-forget'),
                  onPressed: busy ? null : _forget,
                  icon: const Icon(Icons.phonelink_erase_rounded, size: 17),
                  label: const Text('Forget cached unlock'),
                ),
              ],
              SettingsVaultState.error => <Widget>[
                FilledButton.tonalIcon(
                  key: const ValueKey('settings-vault-sync'),
                  onPressed: busy ? null : widget.controller.syncSettingsVault,
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                  label: const Text('Try sync again'),
                ),
                TextButton.icon(
                  key: const ValueKey('settings-vault-forget'),
                  onPressed: busy ? null : _forget,
                  icon: const Icon(Icons.phonelink_erase_rounded, size: 17),
                  label: const Text('Forget cached unlock'),
                ),
                TextButton.icon(
                  key: const ValueKey('settings-vault-reset'),
                  onPressed: busy ? null : _reset,
                  icon: const Icon(Icons.restart_alt_rounded, size: 17),
                  label: const Text('Reset encrypted sync'),
                ),
              ],
              _ => const <Widget>[],
            },
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      Text(
        value,
        style: const TextStyle(
          fontFamily: 'Fraunces',
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          color: context.colors.onSurfaceVariant,
        ),
      ),
    ],
  );
}

class _SettingsSide extends StatelessWidget {
  const _SettingsSide({required this.controller, required this.confirm});

  final AppController controller;
  final Future<bool> Function(String title, String detail) confirm;

  @override
  Widget build(BuildContext context) {
    final ink = PanelSurface.plumLeather.ink(context.tokens);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TexturePanel(
          stitched: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ClawMark(size: 30, color: ink.accent),
              const SizedBox(height: 13),
              Text(
                'Room to stretch.',
                style: Theme.of(
                  context,
                ).textTheme.headlineMedium?.copyWith(color: ink.on),
              ),
              const SizedBox(height: 8),
              Text(
                controller.supportsGoogleDrive
                    ? controller.supportsLocalLibrary
                          ? 'Local and Drive items appear together with clear badges. Retained media is pruned only when nothing else uses it.'
                          : 'Drive keeps this browser’s portable library. Retained media is pruned only when nothing else uses it.'
                    : 'History is uncapped. Saved references stay local until you delete them; retained generation media is pruned only when nothing else uses it.',
                style: TextStyle(color: ink.onMuted),
              ),
              if (controller.gateway.usesCompanion) ...<Widget>[
                const SizedBox(height: 13),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: ink.on.withValues(alpha: .07),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'WEB MODE · Local companion active. No localStorage or IndexedDB history is used.',
                    style: TextStyle(
                      color: ink.accent,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .4,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 15),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                controller.supportsGoogleDrive
                    ? 'Clear Clawnsole data'
                    : 'Clear local data',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 5),
              Text(
                controller.supportsGoogleDrive
                    ? controller.supportsLocalLibrary
                          ? 'These actions cover both Local and connected Drive items. Provider keys remain in secure storage and may also exist in your encrypted sync vault.'
                          : 'These actions cover connected Drive items and this device’s secure settings.'
                    : 'These actions update only Clawnsole data on this device.',
              ),
              const SizedBox(height: 12),
              _ClearButton(
                icon: Icons.delete_sweep_outlined,
                title: 'Clear history',
                subtitle: 'Generation records and unshared media',
                onTap: () async {
                  if (await confirm(
                    'Clear generation history?',
                    'This keeps saved references, their folders and tags, your API keys, and preferences.',
                  )) {
                    await controller.clearHistory();
                  }
                },
              ),
              _ClearButton(
                icon: Icons.restart_alt_rounded,
                title: 'Reset preferences',
                subtitle: 'Navigation and filter state',
                onTap: controller.clearPreferences,
              ),
              _ClearButton(
                icon: Icons.warning_amber_rounded,
                title: controller.supportsGoogleDrive
                    ? controller.supportsLocalLibrary
                          ? 'Delete Local and Drive data'
                          : 'Delete Drive and device data'
                    : 'Delete all local data',
                subtitle:
                    'History, saved references, assets, preferences, and securely stored provider keys',
                danger: true,
                onTap: () async {
                  if (await confirm(
                    controller.supportsGoogleDrive
                        ? controller.supportsLocalLibrary
                              ? 'Delete Local and Drive data?'
                              : 'Delete Drive and device data?'
                        : 'Delete all local data?',
                    controller.supportsGoogleDrive
                        ? controller.supportsLocalLibrary
                              ? 'This permanently removes Clawnsole metadata and assets from this device and the connected Drive folder. It also deletes the shared encrypted settings vault, so synced provider keys and recovery access are removed for every device. This cannot be undone.'
                              : 'This permanently removes Clawnsole metadata and assets from the connected Drive folder. It also deletes the shared encrypted settings vault for every device and this device’s secure settings. This cannot be undone.'
                        : 'This permanently removes the Flutter app’s local JSON file.',
                  )) {
                    await controller.clearAll();
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 15),
        OutlinedButton.icon(
          onPressed: () => unawaited(launchUrl(Uri.parse(bflProvider.docsUrl))),
          icon: const Icon(Icons.open_in_new_rounded, size: 16),
          label: const Text('FLUX 3 documentation'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () =>
              unawaited(launchUrl(Uri.parse(clawnsolePrivacyPolicyUrl))),
          icon: const Icon(Icons.privacy_tip_outlined, size: 16),
          label: const Text('Privacy policy'),
        ),
        const SizedBox(height: 15),
        const _CreatorCard(),
      ],
    );
  }
}

class _CreatorCard extends StatelessWidget {
  const _CreatorCard();

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: EdgeInsets.zero,
    child: Semantics(
      link: true,
      label: 'Made by Alexandria — opens heresalexandria.com',
      child: InkWell(
        key: const ValueKey('alexandria-profile-link'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => unawaited(launchUrl(Uri.parse(alexandriaWebsiteUrl))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              const CircleAvatar(
                radius: 21,
                backgroundImage: AssetImage('assets/profile-alexandria.jpg'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Made by Alexandria',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Visit heresalexandria.com',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.open_in_new_rounded,
                size: 17,
                color: context.colors.primary,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ClearButton extends StatelessWidget {
  const _ClearButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Future<void> Function() onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(
      icon,
      color: danger ? context.colors.error : context.colors.primary,
    ),
    title: Text(
      title,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: danger ? context.colors.error : null,
      ),
    ),
    subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
    trailing: const Icon(Icons.chevron_right_rounded, size: 17),
    onTap: () => unawaited(onTap()),
  );
}
