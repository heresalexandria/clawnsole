import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_version.dart';
import '../core/models.dart';
import '../core/gateway.dart';
import '../core/shell_bridge.dart';
import '../core/update_status.dart';
import '../ui/create_screen.dart';
import '../ui/claw_mark.dart';
import '../ui/library_screen.dart';
import '../ui/panels.dart';
import '../ui/providers_screen.dart';
import '../ui/settings_screen.dart';
import '../ui/update_dialog.dart';
import 'app_controller.dart';
import 'app_theme.dart';

class ClawnsoleApp extends StatefulWidget {
  const ClawnsoleApp({super.key, this.gateway, this.checkForUpdates = true});

  final AppGateway? gateway;

  /// Whether to ask once at launch if a newer release exists. Widget tests
  /// turn this off so they never reach the network.
  final bool checkForUpdates;

  @override
  State<ClawnsoleApp> createState() => _ClawnsoleAppState();
}

class _ClawnsoleAppState extends State<ClawnsoleApp> {
  late final AppController controller;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<ShellUpdateEvent>? _shellUpdates;
  String? _lastNotice;
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    controller = AppController(gateway: widget.gateway);
    unawaited(controller.initialize());
    // A shell-menu "Check for Updates…" downloads through the same pipe, so
    // surface its progress modal no matter where the update started.
    _shellUpdates = updateEvents.listen((event) {
      if (event.phase != 'downloading' && event.phase != 'installing') return;
      final navigator = _navigatorKey.currentState;
      if (navigator != null) unawaited(showUpdateProgressDialog(navigator));
    });
    if (widget.checkForUpdates) {
      unawaited(
        Future<void>.delayed(
          const Duration(seconds: 4),
          UpdateStatus.instance.autoCheck,
        ),
      );
    }
  }

  @override
  void dispose() {
    unawaited(_shellUpdates?.cancel());
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Clawnsole',
    debugShowCheckedModeBanner: false,
    navigatorKey: _navigatorKey,
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
                      const ClawMark(
                        size: 19,
                        color: ClawnsoleColors.brassBright,
                      ),
                      const SizedBox(width: 11),
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
            AppSection.providers => ProvidersScreen(controller: controller),
            AppSection.settings => SettingsScreen(controller: controller),
          };

    return Scaffold(
      body: AppBackdrop(
        child: SafeArea(
          bottom: wide,
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
      ),
      bottomNavigationBar: wide ? null : _BottomNav(controller: controller),
    );
  }
}

class _SideRail extends StatelessWidget {
  const _SideRail({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => TexturePanel(
    surface: PanelSurface.burlwood,
    borderRadius: BorderRadius.zero,
    shadowed: false,
    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
    child: SizedBox(
      width: 72,
      child: Column(
        children: <Widget>[
          InkWell(
            borderRadius: BorderRadius.circular(15),
            onTap: () => unawaited(controller.navigate(AppSection.create)),
            child: SizedBox.square(
              dimension: 48,
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset(
                    'assets/icon.png',
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 34),
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
          _RailButton(
            icon: Icons.hub_rounded,
            label: 'Providers',
            selected: controller.section == AppSection.providers,
            onTap: () => unawaited(controller.navigate(AppSection.providers)),
          ),
          const Spacer(),
          _RailButton(
            icon: Icons.tune_rounded,
            label: 'Settings',
            selected: controller.section == AppSection.settings,
            onTap: () => unawaited(controller.navigate(AppSection.settings)),
          ),
        ],
      ),
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
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final color = selected ? tokens.onPanel : tokens.onPanelMuted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 3),
          decoration: BoxDecoration(
            color: selected
                ? Colors.white.withValues(alpha: .13)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected
                  ? tokens.panelBrass.withValues(alpha: .4)
                  : Colors.transparent,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              SizedBox(
                width: double.infinity,
                child: Column(
                  children: <Widget>[
                    Icon(icon, size: 21, color: color),
                    const SizedBox(height: 5),
                    Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        color: color,
                        fontSize: 10,
                        letterSpacing: .3,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (badge > 0)
                Positioned(right: 2, top: -6, child: _CountBadge(count: badge)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
    decoration: BoxDecoration(
      color: context.tokens.panelBrass,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      '$count',
      style: const TextStyle(
        color: ClawnsoleColors.plumInk,
        fontSize: 9.5,
        fontWeight: FontWeight.w700,
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
    height: 64,
    padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 26),
    decoration: BoxDecoration(
      color: context.colors.surface.withValues(alpha: .84),
      border: Border(bottom: BorderSide(color: context.colors.outlineVariant)),
    ),
    child: Row(
      children: <Widget>[
        Expanded(
          child: Row(
            children: <Widget>[
              Flexible(
                child: InkWell(
                  onTap: () =>
                      unawaited(controller.navigate(AppSection.create)),
                  borderRadius: BorderRadius.circular(9),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        ClawMark(
                          size: compact ? 19 : 21,
                          color: context.tokens.brass,
                        ),
                        const SizedBox(width: 9),
                        Flexible(
                          child: Text(
                            'Clawnsole',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Fraunces',
                              fontSize: compact ? 19 : 21,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -.3,
                              color: context.colors.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _VersionChip(compact: compact),
            ],
          ),
        ),
        _CreditsPill(controller: controller),
        const SizedBox(width: 8),
        if (!compact) ...<Widget>[
          _KeyPill(controller: controller),
          const SizedBox(width: 8),
        ],
        _ThemeModeButton(mode: themeMode, onChanged: onThemeModeChanged),
      ],
    ),
  );
}

class _VersionChip extends StatelessWidget {
  const _VersionChip({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: UpdateStatus.instance,
    builder: (context, _) {
      final available = UpdateStatus.instance.updateAvailable;
      final latest = UpdateStatus.instance.result?.latest;
      return Tooltip(
        message: available
            ? 'Clawnsole $latest is available'
            : 'About this version and updates',
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => unawaited(showVersionDialog(context)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'v$clawnsoleVersion',
                  style: TextStyle(
                    fontSize: compact ? 11 : 12,
                    fontWeight: FontWeight.w400,
                    letterSpacing: .2,
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
                if (available) ...<Widget>[
                  const SizedBox(width: 5),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: context.tokens.brass,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _CreditsPill extends StatelessWidget {
  const _CreditsPill({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: controller.hasApiKey
        ? () => unawaited(controller.refreshCredits())
        : () => unawaited(controller.navigate(AppSection.providers)),
    borderRadius: BorderRadius.circular(999),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: controller.creditError == null
            ? context.colors.surfaceContainerLow
            : context.colors.errorContainer,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          if (controller.refreshingCredits)
            const SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(Icons.toll_rounded, size: 15, color: context.tokens.brass),
          const SizedBox(width: 7),
          Text(
            _balanceText(controller),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );

  String _balanceText(AppController controller) {
    if (!controller.hasApiKey) return 'Add key';
    final account = controller.providerAccounts[controller.selectedProviderId];
    if (account?.balance == null) {
      return '${controller.selectedProvider.shortName} connected';
    }
    if (account!.currency == 'credits') {
      return '${account.balance!.toStringAsFixed(account.balance! % 1 == 0 ? 0 : 1)} cr';
    }
    return '\$${account.balance!.toStringAsFixed(2)}';
  }
}

class _KeyPill extends StatelessWidget {
  const _KeyPill({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final active = controller.hasApiKey;
    return InkWell(
      onTap: () => unawaited(controller.navigate(AppSection.providers)),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: active
              ? context.colors.primaryContainer
              : context.colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? Colors.transparent : context.colors.outlineVariant,
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.key_rounded,
              size: 14,
              color: active
                  ? context.colors.onPrimaryContainer
                  : context.colors.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              active
                  ? '${controller.selectedProvider.shortName} connected'
                  : 'Add provider key',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: active
                    ? context.colors.onPrimaryContainer
                    : context.colors.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
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
      icon: Icon(
        dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
        size: 21,
      ),
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
  Widget build(BuildContext context) => TexturePanel(
    surface: PanelSurface.burlwood,
    borderRadius: BorderRadius.zero,
    shadowed: false,
    padding: EdgeInsets.zero,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(
          children: <Widget>[
            _BottomNavButton(
              icon: Icons.auto_awesome_rounded,
              label: 'Create',
              selected: controller.section == AppSection.create,
              onTap: () => unawaited(controller.navigate(AppSection.create)),
            ),
            _BottomNavButton(
              icon: Icons.video_library_rounded,
              label: 'Library',
              badge: controller.workingCount,
              selected: controller.section == AppSection.library,
              onTap: () => unawaited(controller.navigate(AppSection.library)),
            ),
            _BottomNavButton(
              icon: Icons.hub_rounded,
              label: 'Providers',
              selected: controller.section == AppSection.providers,
              onTap: () => unawaited(controller.navigate(AppSection.providers)),
            ),
            _BottomNavButton(
              icon: Icons.tune_rounded,
              label: 'Settings',
              selected: controller.section == AppSection.settings,
              onTap: () => unawaited(controller.navigate(AppSection.settings)),
            ),
          ],
        ),
      ),
    ),
  );
}

class _BottomNavButton extends StatelessWidget {
  const _BottomNavButton({
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
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final color = selected ? tokens.onPanel : tokens.onPanelMuted;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? Colors.white.withValues(alpha: .13)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected
                  ? tokens.panelBrass.withValues(alpha: .4)
                  : Colors.transparent,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: <Widget>[
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(icon, size: 22, color: color),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 10.5,
                      letterSpacing: .3,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              if (badge > 0)
                Positioned(
                  right: 16,
                  top: -3,
                  child: _CountBadge(count: badge),
                ),
            ],
          ),
        ),
      ),
    );
  }
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
            ClawMark(size: 42, color: context.tokens.brass),
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
