import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../ui/create_screen.dart';
import '../ui/claw_mark.dart';
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
  ThemeMode _themeMode = ThemeMode.system;

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
    theme: buildClawnsoleTheme(Brightness.light),
    darkTheme: buildClawnsoleTheme(Brightness.dark),
    themeMode: _themeMode,
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
                      ClawMark(size: 20, color: context.colors.tertiary),
                      const SizedBox(width: 10),
                      Expanded(child: Text(controller.notice!)),
                    ],
                  ),
                ),
              );
          });
        }
        return _AppShell(
          controller: controller,
          themeMode: _themeMode,
          onThemeModeChanged: (mode) => setState(() => _themeMode = mode),
        );
      },
    ),
  );
}

class _AppShell extends StatelessWidget {
  const _AppShell({
    required this.controller,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final AppController controller;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

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
                  _TopBar(
                    controller: controller,
                    compact: !wide,
                    themeMode: themeMode,
                    onThemeModeChanged: onThemeModeChanged,
                  ),
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
    color: ClawnsoleColors.rail,
    padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
    child: Column(
      children: <Widget>[
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => unawaited(controller.navigate(AppSection.create)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(17),
            child: Image.asset(
              'assets/icon.png',
              width: 48,
              height: 48,
              fit: BoxFit.cover,
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
        const ClawMark(color: ClawnsoleColors.railMuted, size: 21),
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
            SizedBox(
              width: double.infinity,
              child: Column(
                children: <Widget>[
                  Icon(
                    icon,
                    size: 21,
                    color: selected ? Colors.white : ClawnsoleColors.railMuted,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      color: selected
                          ? Colors.white
                          : ClawnsoleColors.railMuted,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (badge > 0)
              Positioned(
                right: 4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: context.colors.tertiary,
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
  const _TopBar({
    required this.controller,
    required this.compact,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final AppController controller;
  final bool compact;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  Widget build(BuildContext context) => Container(
    height: 70,
    padding: EdgeInsets.symmetric(horizontal: compact ? 15 : 28),
    decoration: BoxDecoration(
      color: context.colors.surface,
      border: Border(bottom: BorderSide(color: context.colors.outlineVariant)),
    ),
    child: Row(
      children: <Widget>[
        InkWell(
          onTap: () => unawaited(controller.navigate(AppSection.create)),
          child: Text(
            'Clawnsole',
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: compact ? 20 : 23,
              fontWeight: FontWeight.w700,
              color: context.colors.primary,
            ),
          ),
        ),
        const Spacer(),
        if (!compact)
          const _TopPill(
            icon: Icons.hub_rounded,
            label: 'Provider · BFL / FLUX 3',
            active: true,
          ),
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
                  ? context.colors.surfaceContainerLow
                  : context.colors.errorContainer,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: context.colors.outlineVariant),
            ),
            child: Row(
              children: <Widget>[
                if (controller.refreshingCredits)
                  const SizedBox.square(
                    dimension: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    Icons.toll_rounded,
                    size: 17,
                    color: context.colors.primary,
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
        _ThemeModeButton(mode: themeMode, onChanged: onThemeModeChanged),
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
        color: active
            ? context.colors.primaryContainer
            : context.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 14, color: context.colors.secondary),
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

class _ThemeModeButton extends StatelessWidget {
  const _ThemeModeButton({required this.mode, required this.onChanged});

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return PopupMenuButton<ThemeMode>(
      tooltip: 'Appearance: ${mode.name}',
      initialValue: mode,
      onSelected: onChanged,
      icon: Icon(dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded),
      itemBuilder: (context) => <PopupMenuEntry<ThemeMode>>[
        _themeChoice(ThemeMode.system, Icons.brightness_auto_rounded, 'System'),
        _themeChoice(ThemeMode.light, Icons.light_mode_rounded, 'Light'),
        _themeChoice(ThemeMode.dark, Icons.dark_mode_rounded, 'Dark'),
      ],
    );
  }

  PopupMenuItem<ThemeMode> _themeChoice(
    ThemeMode value,
    IconData icon,
    String label,
  ) => PopupMenuItem<ThemeMode>(
    value: value,
    child: Row(
      children: <Widget>[
        Icon(icon, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(label)),
        if (mode == value) const Icon(Icons.check_rounded, size: 18),
      ],
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
    backgroundColor: context.colors.surface,
    indicatorColor: context.colors.primaryContainer,
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
            Icon(
              Icons.cloud_off_rounded,
              size: 46,
              color: context.colors.primary,
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
                style: TextStyle(
                  fontSize: 11,
                  color: context.colors.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
