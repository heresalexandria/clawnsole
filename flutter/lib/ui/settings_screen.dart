import 'dart:async';

import 'package:flutter/material.dart';
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
                          ? 'Synced with “${connection.folderName}”.'
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
                  : 'Drive items include generated media, references, folders, and non-secret preferences. Provider API keys never leave this device. Copying local items keeps the originals.',
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
                          ? 'These actions cover both Local and connected Drive items. API keys remain device-only.'
                          : 'These actions cover connected Drive items and this browser’s device settings. API keys remain device-only.'
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
                    'History, saved references, assets, preferences, and device API keys',
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
                              ? 'This permanently removes Clawnsole metadata and assets from this device and the connected Drive folder, plus device API keys.'
                              : 'This permanently removes Clawnsole metadata and assets from the connected Drive folder, plus settings and API keys from this browser.'
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
