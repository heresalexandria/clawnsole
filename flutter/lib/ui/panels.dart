import 'package:flutter/material.dart';

import '../app/app_theme.dart';

/// The material a [TexturePanel] is upholstered or veneered with.
enum PanelSurface { plumLeather, navyLeather, burlwood, hunterFelt }

extension on PanelSurface {
  /// Bundled photograph, or null for a solid finish.
  String? get asset => switch (this) {
    PanelSurface.plumLeather => ClawnsoleTextures.plumLeather,
    PanelSurface.navyLeather => ClawnsoleTextures.navyLeather,
    PanelSurface.burlwood => ClawnsoleTextures.burlwood,
    PanelSurface.hunterFelt => null,
  };

  /// Flat stand-in while the texture decodes, and the finish itself for
  /// solid surfaces.
  Color get ground => switch (this) {
    PanelSurface.plumLeather => const Color(0xFF352A34),
    PanelSurface.navyLeather => const Color(0xFF272E3A),
    PanelSurface.burlwood => const Color(0xFF3A2417),
    PanelSurface.hunterFelt => const Color(0xFF2A4633),
  };

  /// Hue-shifts the photographed material toward the brand palette.
  Color? get tint => switch (this) {
    PanelSurface.plumLeather => const Color(0xFF4A2C48),
    PanelSurface.navyLeather => const Color(0xFF2A3D60),
    PanelSurface.burlwood => null,
    PanelSurface.hunterFelt => null,
  };
}

/// A dark upholstered panel: leather or burlwood, optionally stitched.
///
/// Panels stay dark in both appearance modes, like the furniture they borrow
/// from; use [ClawnsoleTokens.onPanel] colors for their content.
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
    final asset = surface.asset;
    final tint = surface.tint;
    Widget content = Padding(padding: padding, child: child);
    if (stitched) {
      content = CustomPaint(
        foregroundPainter: _StitchPainter(
          color: context.tokens.stitch.withValues(alpha: .45),
          borderRadius: borderRadius,
        ),
        child: content,
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: surface.ground,
        borderRadius: borderRadius,
        image: asset == null
            ? null
            : DecorationImage(
                image: AssetImage(asset),
                fit: BoxFit.cover,
                colorFilter: tint == null
                    ? null
                    : ColorFilter.mode(tint, BlendMode.color),
              ),
        boxShadow: shadowed
            ? <BoxShadow>[
                BoxShadow(
                  color: context.colors.shadow.withValues(alpha: .18),
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
