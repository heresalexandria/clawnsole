import 'package:flutter/material.dart';

/// Brand constants that keep their meaning in both appearance modes.
///
/// The palette is a midcentury sitting room: plum and navy upholstery,
/// walnut burl casework, brass hardware, and warm parchment paper.
abstract final class ClawnsoleColors {
  static const plum = Color(0xFF532B4E);
  static const plumInk = Color(0xFF271E25);
  static const navy = Color(0xFF26405F);

  /// Evening hunter felt: the money surface in dark mode, and the ink that
  /// writes on the pale baize in light mode.
  static const hunter = Color(0xFF2A4633);

  /// Daylight baize: the money surface in light mode.
  static const baize = Color(0xFFD6E3CB);
  static const hunterInk = Color(0xFF1D3325);
  static const hunterInkMuted = Color(0xFF4A6152);

  /// The lit side of a switch that is on, tuned per mode so it reads as a
  /// signal lamp rather than a dark blot on paper.
  static const signalGreen = Color(0xFF4A7C55);
  static const brass = Color(0xFF7C5B22);
  static const brassBright = Color(0xFFD9B36C);
  static const cream = Color(0xFFF3EAD9);
  static const creamMuted = Color(0xFFCFC1B0);
  static const danger = Color(0xFF96342B);
}

/// Bundled material photography used on panels and backdrops.
abstract final class ClawnsoleTextures {
  static const plumLeather = 'assets/textures/leather_plum.jpg';
  static const navyLeather = 'assets/textures/leather_navy.jpg';
  static const burlwood = 'assets/textures/wood_burl.jpg';
  static const linen = 'assets/textures/linen_cream.jpg';
}

/// Mode-aware tokens that sit outside the Material color roles.
@immutable
class ClawnsoleTokens extends ThemeExtension<ClawnsoleTokens> {
  const ClawnsoleTokens({
    required this.brass,
    required this.onPanel,
    required this.onPanelMuted,
    required this.panelBrass,
    required this.stitch,
    required this.canvas,
    required this.canvasTexture,
    required this.canvasTextureOpacity,
    required this.money,
    required this.onMoney,
    required this.onMoneyMuted,
    required this.moneyAccent,
    required this.switchOn,
    required this.brightness,
    required this.plumPanel,
    required this.navyPanel,
    required this.onContentPanel,
    required this.onContentPanelMuted,
    required this.contentPanelBrass,
  });

  /// Accent for eyebrows, the claw mark, and small hardware details.
  final Color brass;

  /// Primary text and icons placed on leather or wood panels.
  final Color onPanel;

  /// Secondary text placed on leather or wood panels.
  final Color onPanelMuted;

  /// Brass accent tuned for dark panel backgrounds in both modes.
  final Color panelBrass;

  /// Thread color for stitched panel borders.
  final Color stitch;

  /// Scaffold ground color behind the canvas texture.
  final Color canvas;

  /// Repeating material texture drawn behind every screen.
  final String canvasTexture;

  final double canvasTextureOpacity;

  /// The estimated-charge surface. Green is money in both modes, but the
  /// panel is pale baize on paper and deep hunter felt at night — light mode
  /// never carries a large dark block.
  final Color money;

  /// Primary text and numerals on [money].
  final Color onMoney;

  /// Secondary text on [money].
  final Color onMoneyMuted;

  /// Brass jewelry on [money]: the coin ring, the rate-card link, stitching.
  final Color moneyAccent;

  /// The lit side of a hardware switch that is on.
  final Color switchOn;

  /// Which room these tokens dress. Panels read it to choose their material.
  final Brightness brightness;

  /// Upholstered *content* panels — the Settings feature panel and the
  /// provider plaque. Unlike the rail casework they follow the mode: pale
  /// tinted linen on paper, dark leather at night. In light mode the only
  /// dark backgrounds left are buttons and the rail.
  final Color plumPanel;
  final Color navyPanel;

  /// Text and jewelry on a content panel.
  final Color onContentPanel;
  final Color onContentPanelMuted;
  final Color contentPanelBrass;

  static const light = ClawnsoleTokens(
    brass: ClawnsoleColors.brass,
    onPanel: ClawnsoleColors.cream,
    onPanelMuted: ClawnsoleColors.creamMuted,
    panelBrass: ClawnsoleColors.brassBright,
    stitch: ClawnsoleColors.brassBright,
    canvas: Color(0xFFF1EBDE),
    canvasTexture: ClawnsoleTextures.linen,
    canvasTextureOpacity: .55,
    money: ClawnsoleColors.baize,
    onMoney: ClawnsoleColors.hunterInk,
    onMoneyMuted: ClawnsoleColors.hunterInkMuted,
    moneyAccent: ClawnsoleColors.brass,
    switchOn: ClawnsoleColors.signalGreen,
    brightness: Brightness.light,
    plumPanel: Color(0xFFE6DCE4),
    navyPanel: Color(0xFFDCE3EE),
    onContentPanel: Color(0xFF29202F),
    onContentPanelMuted: Color(0xFF60566A),
    contentPanelBrass: ClawnsoleColors.brass,
  );

  static const dark = ClawnsoleTokens(
    brass: ClawnsoleColors.brassBright,
    onPanel: ClawnsoleColors.cream,
    onPanelMuted: ClawnsoleColors.creamMuted,
    panelBrass: ClawnsoleColors.brassBright,
    stitch: ClawnsoleColors.brassBright,
    canvas: Color(0xFF15100C),
    canvasTexture: ClawnsoleTextures.plumLeather,
    canvasTextureOpacity: .12,
    money: ClawnsoleColors.hunter,
    onMoney: ClawnsoleColors.cream,
    onMoneyMuted: ClawnsoleColors.creamMuted,
    moneyAccent: ClawnsoleColors.brassBright,
    switchOn: ClawnsoleColors.hunter,
    brightness: Brightness.dark,
    plumPanel: Color(0xFF352A34),
    navyPanel: Color(0xFF272E3A),
    onContentPanel: ClawnsoleColors.cream,
    onContentPanelMuted: ClawnsoleColors.creamMuted,
    contentPanelBrass: ClawnsoleColors.brassBright,
  );

  @override
  ClawnsoleTokens copyWith({
    Color? brass,
    Color? onPanel,
    Color? onPanelMuted,
    Color? panelBrass,
    Color? stitch,
    Color? canvas,
    String? canvasTexture,
    double? canvasTextureOpacity,
    Color? money,
    Color? onMoney,
    Color? onMoneyMuted,
    Color? moneyAccent,
    Color? switchOn,
    Brightness? brightness,
    Color? plumPanel,
    Color? navyPanel,
    Color? onContentPanel,
    Color? onContentPanelMuted,
    Color? contentPanelBrass,
  }) => ClawnsoleTokens(
    brass: brass ?? this.brass,
    onPanel: onPanel ?? this.onPanel,
    onPanelMuted: onPanelMuted ?? this.onPanelMuted,
    panelBrass: panelBrass ?? this.panelBrass,
    stitch: stitch ?? this.stitch,
    canvas: canvas ?? this.canvas,
    canvasTexture: canvasTexture ?? this.canvasTexture,
    canvasTextureOpacity: canvasTextureOpacity ?? this.canvasTextureOpacity,
    money: money ?? this.money,
    onMoney: onMoney ?? this.onMoney,
    onMoneyMuted: onMoneyMuted ?? this.onMoneyMuted,
    moneyAccent: moneyAccent ?? this.moneyAccent,
    switchOn: switchOn ?? this.switchOn,
    brightness: brightness ?? this.brightness,
    plumPanel: plumPanel ?? this.plumPanel,
    navyPanel: navyPanel ?? this.navyPanel,
    onContentPanel: onContentPanel ?? this.onContentPanel,
    onContentPanelMuted: onContentPanelMuted ?? this.onContentPanelMuted,
    contentPanelBrass: contentPanelBrass ?? this.contentPanelBrass,
  );

  @override
  ClawnsoleTokens lerp(ThemeExtension<ClawnsoleTokens>? other, double t) {
    if (other is! ClawnsoleTokens) return this;
    return ClawnsoleTokens(
      brass: Color.lerp(brass, other.brass, t)!,
      onPanel: Color.lerp(onPanel, other.onPanel, t)!,
      onPanelMuted: Color.lerp(onPanelMuted, other.onPanelMuted, t)!,
      panelBrass: Color.lerp(panelBrass, other.panelBrass, t)!,
      stitch: Color.lerp(stitch, other.stitch, t)!,
      canvas: Color.lerp(canvas, other.canvas, t)!,
      canvasTexture: t < .5 ? canvasTexture : other.canvasTexture,
      canvasTextureOpacity:
          canvasTextureOpacity +
          (other.canvasTextureOpacity - canvasTextureOpacity) * t,
      money: Color.lerp(money, other.money, t)!,
      onMoney: Color.lerp(onMoney, other.onMoney, t)!,
      onMoneyMuted: Color.lerp(onMoneyMuted, other.onMoneyMuted, t)!,
      moneyAccent: Color.lerp(moneyAccent, other.moneyAccent, t)!,
      switchOn: Color.lerp(switchOn, other.switchOn, t)!,
      brightness: t < .5 ? brightness : other.brightness,
      plumPanel: Color.lerp(plumPanel, other.plumPanel, t)!,
      navyPanel: Color.lerp(navyPanel, other.navyPanel, t)!,
      onContentPanel: Color.lerp(onContentPanel, other.onContentPanel, t)!,
      onContentPanelMuted: Color.lerp(
        onContentPanelMuted,
        other.onContentPanelMuted,
        t,
      )!,
      contentPanelBrass: Color.lerp(
        contentPanelBrass,
        other.contentPanelBrass,
        t,
      )!,
    );
  }
}

extension ClawnsoleThemeContext on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
  ClawnsoleTokens get tokens =>
      Theme.of(this).extension<ClawnsoleTokens>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? ClawnsoleTokens.dark
          : ClawnsoleTokens.light);
}

ColorScheme _lightScheme() => const ColorScheme(
  brightness: Brightness.light,
  primary: ClawnsoleColors.plum,
  onPrimary: Color(0xFFFBF3E6),
  primaryContainer: Color(0xFFEDDCE6),
  onPrimaryContainer: Color(0xFF3E1F3A),
  secondary: ClawnsoleColors.navy,
  onSecondary: Color(0xFFF5F1E6),
  secondaryContainer: Color(0xFFDBE2EE),
  onSecondaryContainer: Color(0xFF1A2E47),
  tertiary: ClawnsoleColors.brass,
  onTertiary: Color(0xFFFFF8E6),
  tertiaryContainer: Color(0xFFEFE2C0),
  onTertiaryContainer: Color(0xFF46330D),
  error: ClawnsoleColors.danger,
  onError: Color(0xFFFFF6F0),
  errorContainer: Color(0xFFF3D8CF),
  onErrorContainer: Color(0xFF571D15),
  surface: Color(0xFFFBF7ED),
  onSurface: Color(0xFF29202F),
  onSurfaceVariant: Color(0xFF60566A),
  surfaceContainerLowest: Color(0xFFFEFCF6),
  surfaceContainerLow: Color(0xFFF4EEE0),
  surfaceContainer: Color(0xFFEEE6D4),
  surfaceContainerHigh: Color(0xFFE7DDC8),
  surfaceContainerHighest: Color(0xFFDFD4BB),
  outline: Color(0xFF877D8C),
  outlineVariant: Color(0xFFDBD1BF),
  shadow: Color(0xFF3A2C24),
  scrim: Colors.black,
  inverseSurface: Color(0xFF2E2436),
  onInverseSurface: ClawnsoleColors.cream,
  inversePrimary: Color(0xFFE3C6DD),
);

// Dark mode is a warm evening study — espresso neutrals that flatter the
// burlwood, navy, hunter green, and plum rather than a violet-cast gray.
ColorScheme _darkScheme() => const ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFF6E3D66),
  onPrimary: Color(0xFFFBF3E6),
  primaryContainer: Color(0xFF4C2B47),
  onPrimaryContainer: Color(0xFFF0DCEA),
  secondary: Color(0xFFAFC3E6),
  onSecondary: Color(0xFF172A45),
  secondaryContainer: Color(0xFF27364E),
  onSecondaryContainer: Color(0xFFD7E2F5),
  tertiary: Color(0xFFD9B4D0),
  onTertiary: Color(0xFF3C2140),
  tertiaryContainer: Color(0xFF4C2F49),
  onTertiaryContainer: Color(0xFFF4DFF2),
  error: Color(0xFFF0B3A8),
  onError: Color(0xFF491710),
  errorContainer: Color(0xFF5E241B),
  onErrorContainer: Color(0xFFFBDCD5),
  surface: Color(0xFF211B15),
  onSurface: Color(0xFFF1E9DB),
  onSurfaceVariant: Color(0xFFB9AB9B),
  surfaceContainerLowest: Color(0xFF120E0A),
  surfaceContainerLow: Color(0xFF28211A),
  surfaceContainer: Color(0xFF2E261E),
  surfaceContainerHigh: Color(0xFF362D24),
  surfaceContainerHighest: Color(0xFF3E342A),
  outline: Color(0xFF877866),
  outlineVariant: Color(0xFF41372C),
  shadow: Colors.black,
  scrim: Colors.black,
  inverseSurface: Color(0xFFEFE7D9),
  onInverseSurface: Color(0xFF28211A),
  inversePrimary: ClawnsoleColors.plum,
);

const _display = 'Fraunces';
const _text = 'DM Sans';

TextTheme _textTheme() => const TextTheme(
  displayLarge: TextStyle(
    fontFamily: _display,
    fontSize: 46,
    height: 1.04,
    letterSpacing: -.8,
    fontWeight: FontWeight.w600,
  ),
  displayMedium: TextStyle(
    fontFamily: _display,
    fontSize: 38,
    height: 1.05,
    letterSpacing: -.6,
    fontWeight: FontWeight.w600,
  ),
  headlineLarge: TextStyle(
    fontFamily: _display,
    fontSize: 32,
    height: 1.08,
    letterSpacing: -.4,
    fontWeight: FontWeight.w600,
  ),
  headlineMedium: TextStyle(
    fontFamily: _display,
    fontSize: 25,
    height: 1.12,
    letterSpacing: -.2,
    fontWeight: FontWeight.w600,
  ),
  headlineSmall: TextStyle(
    fontFamily: _display,
    fontSize: 20,
    height: 1.18,
    fontWeight: FontWeight.w600,
  ),
  titleLarge: TextStyle(
    fontSize: 16.5,
    height: 1.32,
    letterSpacing: -.1,
    fontWeight: FontWeight.w700,
  ),
  titleMedium: TextStyle(
    fontSize: 14.5,
    height: 1.3,
    fontWeight: FontWeight.w700,
  ),
  titleSmall: TextStyle(fontSize: 13, height: 1.3, fontWeight: FontWeight.w700),
  bodyLarge: TextStyle(fontSize: 15, height: 1.55),
  bodyMedium: TextStyle(fontSize: 13.5, height: 1.5),
  bodySmall: TextStyle(fontSize: 12, height: 1.45),
  labelLarge: TextStyle(
    fontSize: 13.5,
    letterSpacing: .1,
    fontWeight: FontWeight.w700,
  ),
  labelMedium: TextStyle(
    fontSize: 12,
    letterSpacing: .3,
    fontWeight: FontWeight.w700,
  ),
  labelSmall: TextStyle(
    fontSize: 11,
    letterSpacing: .7,
    fontWeight: FontWeight.w700,
  ),
);

ThemeData buildClawnsoleTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = dark ? _darkScheme() : _lightScheme();
  final tokens = dark ? ClawnsoleTokens.dark : ClawnsoleTokens.light;

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: _text,
    textTheme: _textTheme(),
    visualDensity: VisualDensity.standard,
    scaffoldBackgroundColor: tokens.canvas,
    extensions: <ThemeExtension<dynamic>>[tokens],
  );

  OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );

  return base.copyWith(
    dividerColor: scheme.outlineVariant,
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark
          ? scheme.surfaceContainerLow
          : scheme.surfaceContainerLowest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      border: inputBorder(scheme.outlineVariant),
      enabledBorder: inputBorder(scheme.outlineVariant),
      focusedBorder: inputBorder(scheme.primary, 1.6),
      hintStyle: TextStyle(
        color: scheme.onSurfaceVariant.withValues(alpha: .8),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontFamily: _text,
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          letterSpacing: .1,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: dark ? scheme.tertiary : scheme.primary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        side: BorderSide(
          color: dark ? scheme.outline : const Color(0xFFC4B8A6),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        textStyle: const TextStyle(
          fontFamily: _text,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          letterSpacing: .1,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: dark ? scheme.tertiary : scheme.primary,
        textStyle: const TextStyle(
          fontFamily: _text,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: dark ? const Color(0xFF96628D) : scheme.primary,
      inactiveTrackColor: scheme.outlineVariant,
      thumbColor: dark ? const Color(0xFF96628D) : scheme.primary,
      overlayColor: scheme.primary.withValues(alpha: .1),
      valueIndicatorColor: ClawnsoleColors.plumInk,
      valueIndicatorTextStyle: const TextStyle(
        color: ClawnsoleColors.cream,
        fontFamily: _text,
        fontWeight: FontWeight.w700,
      ),
      // ignore: deprecated_member_use, opts into the 2024 slider appearance.
      year2023: false,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? scheme.onPrimary
            : scheme.outline,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? scheme.primary
            : scheme.surfaceContainerHigh,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.transparent
            : scheme.outline,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: dark ? scheme.tertiary : scheme.primary,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: dark ? const Color(0xFF30281F) : ClawnsoleColors.plumInk,
      contentTextStyle: const TextStyle(
        fontFamily: _text,
        color: ClawnsoleColors.cream,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        height: 1.4,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: dark ? scheme.surfaceContainerHigh : scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: scheme.shadow.withValues(alpha: .4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      textStyle: TextStyle(
        fontFamily: _text,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: scheme.onSurface,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: _textTheme().headlineMedium?.copyWith(
        color: scheme.onSurface,
      ),
      contentTextStyle: _textTheme().bodyMedium?.copyWith(
        color: scheme.onSurface,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: ClawnsoleColors.plumInk,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: const TextStyle(
        fontFamily: _text,
        color: ClawnsoleColors.cream,
        fontSize: 11.5,
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      titleTextStyle: _textTheme().titleSmall?.copyWith(
        color: scheme.onSurface,
      ),
      subtitleTextStyle: _textTheme().bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    ),
  );
}
