import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import '../core/provider_catalog.dart';
import 'common_widgets.dart';
import 'formatters.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({required this.controller, super.key});

  final AppController controller;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final keyController = TextEditingController();
  bool showKey = false;
  bool saving = false;
  bool checking = false;
  double? checkedCredits;
  String? checkError;

  @override
  void dispose() {
    keyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (keyController.text.trim().isEmpty) {
      widget.controller.showNotice('Paste a BFL API key first.');
      return;
    }
    setState(() => saving = true);
    try {
      await widget.controller.saveKey(keyController.text);
      keyController.clear();
      checkedCredits = null;
      checkError = null;
    } on Object catch (error) {
      widget.controller.showNotice(error.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _verify() async {
    setState(() {
      checking = true;
      checkError = null;
      checkedCredits = null;
    });
    try {
      checkedCredits = await widget.controller.verifyKey(keyController.text);
    } on Object catch (error) {
      checkError = error.toString();
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

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
          _ApiKeySection(
            controller: widget.controller,
            keyController: keyController,
            showKey: showKey,
            saving: saving,
            checking: checking,
            checkedCredits: checkedCredits,
            checkError: checkError,
            onToggleVisibility: () => setState(() => showKey = !showKey),
            onSave: _save,
            onVerify: _verify,
          ),
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
                  'Connect your provider and keep a close eye on Clawnsole’s local data.',
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

class _ApiKeySection extends StatelessWidget {
  const _ApiKeySection({
    required this.controller,
    required this.keyController,
    required this.showKey,
    required this.saving,
    required this.checking,
    required this.checkedCredits,
    required this.checkError,
    required this.onToggleVisibility,
    required this.onSave,
    required this.onVerify,
  });

  final AppController controller;
  final TextEditingController keyController;
  final bool showKey;
  final bool saving;
  final bool checking;
  final double? checkedCredits;
  final String? checkError;
  final VoidCallback onToggleVisibility;
  final Future<void> Function() onSave;
  final Future<void> Function() onVerify;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const CircleAvatar(
              backgroundColor: Color(0xFFE3EBE0),
              child: Icon(Icons.key_rounded, color: ClawnsoleColors.forest),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Black Forest Labs',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    controller.gateway.usesCompanion
                        ? 'Your key is sent only to the loopback companion and stored in its local JSON file.'
                        : 'Your key stays inside this app’s private local JSON file.',
                  ),
                ],
              ),
            ),
            if (controller.hasApiKey)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCE9DE),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.check_rounded,
                      size: 13,
                      color: ClawnsoleColors.forest,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Connected',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        const Text(
          'BFL API key',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 7),
        TextField(
          controller: keyController,
          obscureText: !showKey,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            hintText: controller.hasApiKey
                ? 'Saved — paste a replacement'
                : 'bfl_••••••••••••••••',
            suffixIcon: IconButton(
              onPressed: onToggleVisibility,
              icon: Icon(
                showKey
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          controller.gateway.usesCompanion
              ? 'The browser receives only whether a key exists. Start the loopback companion before using the web build.'
              : 'The app sandbox protects this file from other apps. It is removed when you clear the key or delete all local data.',
          style: const TextStyle(fontSize: 9),
        ),
        if (checking ||
            checkedCredits != null ||
            checkError != null) ...<Widget>[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: checkError == null
                  ? const Color(0xFFE3EBE0)
                  : const Color(0xFFF8DFD9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: <Widget>[
                if (checking)
                  const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    checkError == null
                        ? Icons.check_circle_outline_rounded
                        : Icons.warning_amber_rounded,
                    size: 17,
                    color: checkError == null
                        ? ClawnsoleColors.forest
                        : ClawnsoleColors.danger,
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    checking
                        ? 'Checking with BFL…'
                        : checkError ??
                              'Key verified · ${formatCredits(checkedCredits!)} credits available',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 15),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            FilledButton.icon(
              onPressed: saving ? null : () => unawaited(onSave()),
              icon: saving
                  ? const SizedBox.square(
                      dimension: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.key_rounded, size: 17),
              label: Text(controller.hasApiKey ? 'Replace key' : 'Save key'),
            ),
            OutlinedButton.icon(
              onPressed:
                  checking ||
                      (keyController.text.isEmpty && !controller.hasApiKey)
                  ? null
                  : () => unawaited(onVerify()),
              icon: const Icon(Icons.refresh_rounded, size: 17),
              label: const Text('Verify & check credits'),
            ),
            if (controller.hasApiKey)
              TextButton(
                onPressed: () => unawaited(controller.removeKey()),
                child: const Text(
                  'Remove',
                  style: TextStyle(color: ClawnsoleColors.danger),
                ),
              ),
          ],
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
            const CircleAvatar(
              backgroundColor: Color(0xFFF0DFD5),
              child: Icon(
                Icons.storage_rounded,
                color: ClawnsoleColors.clayDark,
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
            color: ClawnsoleColors.cream,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'DATA FILE',
                style: TextStyle(
                  fontSize: 8,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              SelectableText(
                controller.storage.path.isEmpty
                    ? 'Not created yet'
                    : controller.storage.path,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
              ),
              const SizedBox(height: 8),
              Text(
                controller.gateway.persistenceDescription,
                style: const TextStyle(fontSize: 9),
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
        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
      ),
      const SizedBox(height: 3),
      Text(label, style: const TextStyle(fontSize: 8)),
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
      SurfaceCard(
        color: ClawnsoleColors.forest,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(
              Icons.pets_rounded,
              color: ClawnsoleColors.mustard,
              size: 30,
            ),
            const SizedBox(height: 13),
            Text(
              'Room to stretch.',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 8),
            const Text(
              'History is uncapped. Uploaded references and completed videos remain local until their records are removed.',
              style: TextStyle(color: Colors.white70),
            ),
            if (controller.gateway.usesCompanion) ...<Widget>[
              const SizedBox(height: 13),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'WEB MODE · Local companion active. No localStorage or IndexedDB history is used.',
                  style: TextStyle(
                    color: ClawnsoleColors.mustard,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
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
    ],
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
      color: danger ? ClawnsoleColors.danger : ClawnsoleColors.clayDark,
    ),
    title: Text(
      title,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w900,
        color: danger ? ClawnsoleColors.danger : null,
      ),
    ),
    subtitle: Text(subtitle, style: const TextStyle(fontSize: 8)),
    trailing: const Icon(Icons.chevron_right_rounded, size: 17),
    onTap: () => unawaited(onTap()),
  );
}
