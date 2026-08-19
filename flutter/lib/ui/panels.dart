import 'package:flutter/material.dart';

import '../app/app_theme.dart';

/// The material a [TexturePanel] is upholstered or veneered with.
enum PanelSurface { plumLeather, navyLeather, burlwood, hunterFelt }

/// Foreground colors for content placed on a [PanelSurface].
@immutable
class PanelInk {
  const PanelInk({
    required this.on,
    required this.onMuted,
    required this.accent,
  });

  /// Primary text and icons.
  final Color on;

  /// Secondary text.
  final Color onMuted;

  /// Brass jewelry: the claw, small marks, keylines.
  final Color accent;
}

extension PanelSurfaceMaterial on PanelSurface {
  /// Whether this panel is casework — the cabinet the app is built into,
  /// which stays dark in both modes. Everything else is content, and in
  /// light mode content never sits on a dark background.
  bool get isCasework => this == PanelSurface.burlwood;

  /// Bundled photograph, or null for a solid finish. Content panels are
  /// upholstered in leather at night and in pale tinted linen on paper.
  String? asset(ClawnsoleTokens tokens) {
    final dark = tokens.brightness == Brightness.dark;
    return switch (this) {
      PanelSurface.burlwood => ClawnsoleTextures.burlwood,
      PanelSurface.plumLeather =>
        dark ? ClawnsoleTextures.plumLeather : ClawnsoleTextures.linen,
      PanelSurface.navyLeather =>
        dark ? ClawnsoleTextures.navyLeather : ClawnsoleTextures.linen,
      PanelSurface.hunterFelt => null,
    };
  }

  /// Flat stand-in while the texture decodes, and the finish itself for
  /// solid surfaces.
  Color ground(ClawnsoleTokens tokens) => switch (this) {
    PanelSurface.plumLeather => tokens.plumPanel,
    PanelSurface.navyLeather => tokens.navyPanel,
    PanelSurface.burlwood => const Color(0xFF3A2417),
    PanelSurface.hunterFelt => tokens.money,
  };

  /// Hue-shifts the photographed material toward the brand palette. Only the
  /// dark leathers are tinted; a pale panel takes its color from [ground] and
  /// uses the linen purely as tooth, because tinting a light photograph pushes
  /// it straight to candy.
  Color? tint(ClawnsoleTokens tokens) {
    if (tokens.brightness == Brightness.light && !isCasework) return null;
    return switch (this) {
      PanelSurface.plumLeather => const Color(0xFF4A2C48),
      PanelSurface.navyLeather => const Color(0xFF2A3D60),
      PanelSurface.burlwood => null,
      PanelSurface.hunterFelt => null,
    };
  }

  /// How strongly the photograph reads. Pale panels want a whisper of weave
  /// over their color; dark upholstery is the photograph itself.
  double textureOpacity(ClawnsoleTokens tokens) =>
      tokens.brightness == Brightness.light && !isCasework ? .35 : 1;

  /// Linen is a small tile and repeats; the leathers and burl are shot to
  /// cover a panel.
  bool tilesTexture(ClawnsoleTokens tokens) =>
      tokens.brightness == Brightness.light && !isCasework;

  /// Thread color for a stitched border on this surface.
  Color stitch(ClawnsoleTokens tokens) => switch (this) {
    PanelSurface.hunterFelt => tokens.moneyAccent,
    PanelSurface.burlwood => tokens.stitch,
    _ => tokens.contentPanelBrass,
  };

  /// Colors for text and icons placed on this panel.
  PanelInk ink(ClawnsoleTokens tokens) => switch (this) {
    // Casework is dark in both modes, so its content stays cream.
    PanelSurface.burlwood => PanelInk(
      on: tokens.onPanel,
      onMuted: tokens.onPanelMuted,
      accent: tokens.panelBrass,
    ),
    PanelSurface.hunterFelt => PanelInk(
      on: tokens.onMoney,
      onMuted: tokens.onMoneyMuted,
      accent: tokens.moneyAccent,
    ),
    _ => PanelInk(
      on: tokens.onContentPanel,
      onMuted: tokens.onContentPanelMuted,
      accent: tokens.contentPanelBrass,
    ),
  };
}

/// An upholstered panel: leather, burlwood, or felt, optionally stitched.
///
/// The leather and wood panels stay dark in both appearance modes, like the
/// furniture they borrow from; use [ClawnsoleTokens.onPanel] colors for their
/// content. The hunter felt is the exception — it is the money surface, so it
/// reads as pale baize on paper and deep felt at night, and its content uses
/// the [ClawnsoleTokens.onMoney] colors.
class TexturePanel extends StatelessWidget {
  const TexturePanel({
    required this.child,
    super.key,
    this.surface = PanelSurface.plumLeather,
    this.stitched = false,
    this.padding = const EdgeInsets.all(18),
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.shadowed = true,
  });

  final Widget child;
  final PanelSurface surface;
  final bool stitched;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final bool shadowed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final asset = surface.asset(tokens);
    final tint = surface.tint(tokens);
    Widget content = Padding(padding: padding, child: child);
    if (stitched) {
      content = CustomPaint(
        foregroundPainter: _StitchPainter(
          color: surface.stitch(tokens).withValues(alpha: .45),
          borderRadius: borderRadius,
        ),
        child: content,
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: surface.ground(tokens),
        borderRadius: borderRadius,
        image: asset == null
            ? null
            : DecorationImage(
                image: AssetImage(asset),
                fit: surface.tilesTexture(tokens) ? BoxFit.none : BoxFit.cover,
                repeat: surface.tilesTexture(tokens)
                    ? ImageRepeat.repeat
                    : ImageRepeat.noRepeat,
                opacity: surface.textureOpacity(tokens),
                filterQuality: FilterQuality.medium,
                colorFilter: tint == null
                    ? null
                    : ColorFilter.mode(tint, BlendMode.color),
              ),
        boxShadow: shadowed
            ? <BoxShadow>[
                BoxShadow(
                  color: context.colors.shadow.withValues(
                    // Pale panels sit on paper; they need lift, not drama.
                    alpha: tokens.brightness == Brightness.dark ? .18 : .1,
                  ),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Material(type: MaterialType.transparency, child: content),
    );
  }
}

/// Saddle-stitch border drawn just inside a panel's edge.
class _StitchPainter extends CustomPainter {
  const _StitchPainter({required this.color, required this.borderRadius});

  final Color color;
  final BorderRadius borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 9.0;
    const dash = 5.5;
    const gap = 4.5;
    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect).deflate(inset).shift(Offset.zero);
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + dash).clamp(0, metric.length).toDouble();
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_StitchPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.borderRadius != borderRadius;
}

/// Screen backdrop: the theme's canvas color under a faint material texture.
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.canvas,
        image: DecorationImage(
          image: AssetImage(tokens.canvasTexture),
          repeat: ImageRepeat.repeat,
          opacity: tokens.canvasTextureOpacity,
          filterQuality: FilterQuality.medium,
        ),
      ),
      child: child,
    );
  }
}
