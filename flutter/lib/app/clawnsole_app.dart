import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../ui/create_screen.dart';
import '../ui/library_screen.dart';
import '../ui/settings_screen.dart';
import 'app_controller.dart';
import 'app_theme.dart';

class ClawnsoleApp extends StatefulWidget {
  const ClawnsoleApp({super.key});

  @override
  State<ClawnsoleApp> createState() => _ClawnsoleAppState();
}

class _ClawnsoleAppState extends State<ClawnsoleApp> {
  late final AppController controller;
  String? _lastNotice;

  @override
  void initState() {
    super.initState();
    controller = AppController();
    unawaited(controller.initialize());
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Clawnsole',
    debugShowCheckedModeBanner: false,
    theme: buildClawnsoleTheme(),
    home: AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (controller.notice != null && controller.notice != _lastNotice) {
          _lastNotice = controller.notice;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted || controller.notice == null) return;
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Row(
                    children: <Widget>[
                      const Icon(
                        Icons.pets_rounded,
                        color: ClawnsoleColors.mustard,
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(controller.notice!)),
                    ],
                  ),
                ),
              );
          });
        }
        return _AppShell(controller: controller);
      },
    ),
  );
}

class _AppShell extends StatelessWidget {
  const _AppShell({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final body = controller.loading
        ? const Center(child: CircularProgressIndicator())
        : controller.loadError != null
        ? _ConnectionError(controller: controller)
        : switch (controller.section) {
            AppSection.create => CreateScreen(controller: controller),
            AppSection.library => LibraryScreen(controller: controller),
            AppSection.settings => SettingsScreen(controller: controller),
          };

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: <Widget>[
            if (wide) _SideRail(controller: controller),
            Expanded(
              child: Column(
                children: <Widget>[
                  _TopBar(controller: controller, compact: !wide),
                  Expanded(child: body),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: wide ? null : _BottomNav(controller: controller),
    );
  }
}

class _SideRail extends StatelessWidget {
  const _SideRail({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => Container(
    width: 88,
    color: ClawnsoleColors.forest,
    padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
    child: Column(
      children: <Widget>[
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => unawaited(controller.navigate(AppSection.create)),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: ClawnsoleColors.clay,
              borderRadius: BorderRadius.circular(17),
            ),
            alignment: Alignment.center,
            child: const Text(
              'C',
              style: TextStyle(
                color: Colors.white,
                fontFamily: 'Georgia',
                fontSize: 25,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 36),
        _RailButton(
          icon: Icons.auto_awesome_rounded,
          label: 'Create',
          selected: controller.section == AppSection.create,
          onTap: () => unawaited(controller.navigate(AppSection.create)),
        ),
        _RailButton(
          icon: Icons.video_library_rounded,
          label: 'Library',
          badge: controller.workingCount,
          selected: controller.section == AppSection.library,
          onTap: () => unawaited(controller.navigate(AppSection.library)),
        ),
        const Spacer(),
        const Icon(Icons.pets_rounded, color: ClawnsoleColors.sage, size: 21),
        const SizedBox(height: 14),
        _RailButton(
          icon: Icons.tune_rounded,
          label: 'Settings',
          selected: controller.section == AppSection.settings,
          onTap: () => unawaited(controller.navigate(AppSection.settings)),
        ),
      ],
    ),
  );
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 3),
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withValues(alpha: .12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Column(
              children: <Widget>[
                Icon(
                  icon,
                  size: 21,
                  color: selected ? Colors.white : ClawnsoleColors.sage,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: selected ? Colors.white : ClawnsoleColors.sage,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (badge > 0)
              Positioned(
                right: 4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: ClawnsoleColors.mustard,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$badge',
                    style: const TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller, required this.compact});

  final AppController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    height: 70,
    padding: EdgeInsets.symmetric(horizontal: compact ? 15 : 28),
    decoration: const BoxDecoration(
      color: ClawnsoleColors.paper,
      border: Border(bottom: BorderSide(color: ClawnsoleColors.line)),
    ),
    child: Row(
      children: <Widget>[
        InkWell(
          onTap: () => unawaited(controller.navigate(AppSection.create)),
          child: Text(
            'Clawnsole®',
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: compact ? 20 : 23,
              fontWeight: FontWeight.w700,
              color: ClawnsoleColors.forest,
            ),
          ),
        ),
        const Spacer(),
        if (!compact)
          const _TopPill(icon: Icons.circle, label: 'FLUX 3', active: true),
        if (!compact) const SizedBox(width: 8),
        InkWell(
          onTap: controller.hasApiKey
              ? () => unawaited(controller.refreshCredits())
              : null,
          borderRadius: BorderRadius.circular(11),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              color: controller.creditError == null
                  ? ClawnsoleColors.cream
                  : const Color(0xFFFFE8E3),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: ClawnsoleColors.line),
            ),
            child: Row(
              children: <Widget>[
                if (controller.refreshingCredits)
                  const SizedBox.square(
                    dimension: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  const Icon(
                    Icons.toll_rounded,
                    size: 17,
                    color: ClawnsoleColors.clay,
                  ),
                const SizedBox(width: 7),
                Text(
                  controller.credits == null
                      ? (controller.hasApiKey ? '— credits' : 'Add key')
                      : '${controller.credits!.toStringAsFixed(controller.credits! % 1 == 0 ? 0 : 1)} cr',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (!compact)
          _TopPill(
            icon: Icons.key_rounded,
            label: controller.hasApiKey ? 'API key set' : 'Add API key',
            active: controller.hasApiKey,
            onTap: () => unawaited(controller.navigate(AppSection.settings)),
          ),
      ],
    ),
  );
}

class _TopPill extends StatelessWidget {
  const _TopPill({
    required this.icon,
    required this.label,
    this.active = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(11),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFE7EFE8) : ClawnsoleColors.cream,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: ClawnsoleColors.line),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 14, color: ClawnsoleColors.forestSoft),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    ),
  );
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => NavigationBar(
    selectedIndex: controller.section.index,
    onDestinationSelected: (index) =>
        unawaited(controller.navigate(AppSection.values[index])),
    backgroundColor: ClawnsoleColors.paper,
    indicatorColor: const Color(0xFFE1E9DF),
    destinations: const <NavigationDestination>[
      NavigationDestination(
        icon: Icon(Icons.auto_awesome_rounded),
        label: 'Create',
      ),
      NavigationDestination(
        icon: Icon(Icons.video_library_rounded),
        label: 'Library',
      ),
      NavigationDestination(icon: Icon(Icons.tune_rounded), label: 'Settings'),
    ],
  );
}

class _ConnectionError extends StatelessWidget {
  const _ConnectionError({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(
              Icons.cloud_off_rounded,
              size: 46,
              color: ClawnsoleColors.clay,
            ),
            const SizedBox(height: 18),
            Text(
              controller.gateway.usesCompanion
                  ? 'Start the local companion.'
                  : 'Clawnsole could not open its local data.',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              controller.gateway.usesCompanion
                  ? 'Run “dart run tool/clawnsole_companion.dart” from the flutter directory, then reload this page. Browser storage is intentionally not used.'
                  : controller.loadError!,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            if (controller.gateway.usesCompanion)
              SelectableText(
                controller.loadError ?? '',
                style: const TextStyle(
                  fontSize: 11,
                  color: ClawnsoleColors.muted,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
