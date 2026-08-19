import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import '../core/app_links.dart';
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
                const Text(
                  'Manage appearance, updates, and Clawnsole’s private local data.',
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
    child: Row(
      children: <Widget>[
        CircleAvatar(
          backgroundColor: context.colors.primaryContainer,
          child: Icon(
            Icons.hub_rounded,
            color: context.colors.onPrimaryContainer,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Provider access moved to its own desk',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 4),
              Text(
                'Set BFL, LTX, ArtCraft, and Atlas Cloud keys and compare live model costs in Providers.',
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          onPressed: () => unawaited(controller.navigate(AppSection.providers)),
          icon: const Icon(Icons.arrow_forward_rounded, size: 17),
          label: const Text('Open Providers'),
        ),
      ],
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
                    'Local project data',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'Compact JSON plus retained reference inputs and finished videos.',
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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      TexturePanel(
        stitched: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClawMark(size: 30, color: context.tokens.panelBrass),
            const SizedBox(height: 13),
            Text(
              'Room to stretch.',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: context.tokens.onPanel,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'History is uncapped. Uploaded references and completed videos remain local until their records are removed.',
              style: TextStyle(color: context.tokens.onPanelMuted),
            ),
            if (controller.gateway.usesCompanion) ...<Widget>[
              const SizedBox(height: 13),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .07),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'WEB MODE · Local companion active. No localStorage or IndexedDB history is used.',
                  style: TextStyle(
                    color: context.tokens.panelBrass,
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
              'Clear local data',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 5),
            const Text(
              'These actions update only Clawnsole data on this device.',
            ),
            const SizedBox(height: 12),
            _ClearButton(
              icon: Icons.delete_sweep_outlined,
              title: 'Clear history',
              subtitle: 'Records, retained inputs, and videos',
              onTap: () async {
                if (await confirm(
                  'Clear generation history?',
                  'This keeps your API key and preferences.',
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
              title: 'Delete all local data',
              subtitle: 'History, assets, preferences, and API key',
              danger: true,
              onTap: () async {
                if (await confirm(
                  'Delete all local data?',
                  'This permanently removes the Flutter app’s local JSON file.',
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
