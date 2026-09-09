import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import 'paint_cache.dart';

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

  /// The [tint] as the one [ColorFilter] this surface ever hands the engine.
  /// Filters compare by value, so an equal decoration never repaints; a
  /// single instance also keeps the decoration cheap to compare.
  ColorFilter? tintFilter(ClawnsoleTokens tokens) {
    final color = tint(tokens);
    if (color == null) return null;
    return _tintFilters[color] ??= ColorFilter.mode(color, BlendMode.color);
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

final Map<Color, ColorFilter> _tintFilters = <Color, ColorFilter>{};

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
    final tintFilter = surface.tintFilter(tokens);
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
    // Two pictures. The outer boundary keeps the page from re-recording the
    // photograph (and its colour filter, a native object per paint on the
    // web); the inner one keeps the panel's own content — ink splashes, a
    // hovered key — from re-recording it either.
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: surface.ground(tokens),
          borderRadius: borderRadius,
          image: asset == null
              ? null
              : DecorationImage(
                  image: AssetImage(asset),
                  fit: surface.tilesTexture(tokens)
                      ? BoxFit.none
                      : BoxFit.cover,
                  repeat: surface.tilesTexture(tokens)
                      ? ImageRepeat.repeat
                      : ImageRepeat.noRepeat,
                  opacity: surface.textureOpacity(tokens),
                  filterQuality: FilterQuality.medium,
                  colorFilter: tintFilter,
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
        child: RepaintBoundary(
          child: Material(type: MaterialType.transparency, child: content),
        ),
      ),
    );
  }
}

/// The dashed outlines already cut, by panel size and corner radius. A
/// stitched panel repaints on every hover inside it; measuring the outline
/// and extracting every dash again each time is work the eye never sees.
final PathCache<(Size, BorderRadius)> _stitchOutlines =
    PathCache<(Size, BorderRadius)>();

/// Saddle-stitch border drawn just inside a panel's edge.
class _StitchPainter extends CustomPainter {
  const _StitchPainter({required this.color, required this.borderRadius});

  final Color color;
  final BorderRadius borderRadius;

  static Path _cut(Size size, BorderRadius borderRadius) {
    const inset = 9.0;
    const dash = 5.5;
    const gap = 4.5;
    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect).deflate(inset).shift(Offset.zero);
    final outline = Path()..addRRect(rrect);
    final stitches = Path();
    for (final metric in outline.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + dash).clamp(0, metric.length).toDouble();
        stitches.addPath(metric.extractPath(distance, end), Offset.zero);
        distance = end + gap;
      }
    }
    return stitches;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final stitches = _stitchOutlines.obtain((
      size,
      borderRadius,
    ), () => _cut(size, borderRadius));
    canvas.drawPath(
      stitches,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_StitchPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.borderRadius != borderRadius;
}

/// One cut of the burlwood veneer.
///
/// A cabinetmaker taking facings out of one sheet of burl does not lay them
/// end to end — the figure would run straight through the joint and the
/// pieces would read as one board. The sheet is instead thought of as a grid
/// of patches, and each facing is taken from its own patch: [BurlwoodCut.run]
/// hands out patches from a stable hash of each key, and never lets a facing
/// take a patch within one row of the one above it, so the grain always
/// breaks at the joint.
///
/// The patch is expressed as a [DecorationImage] alignment against the
/// unscaled photograph, so a short row shows a genuinely different region
/// rather than the same region at a different zoom.
@immutable
class BurlwoodCut {
  const BurlwoodCut({
    required this.column,
    required this.row,
    required this.flipped,
  });

  /// The cut for a single key, with nothing above it to avoid.
  factory BurlwoodCut.of(String key) => run(<String>[key]).single;

  /// How the sheet is divided. Rows carry the variety: at the natural size
  /// of the photograph two neighbouring rows are ~139 px apart, well clear
  /// of any row of console height, while the columns only slide a wide
  /// facing along the sheet.
  static const int columns = 4;
  static const int rows = 8;
  static const int patches = columns * rows;

  final int column;
  final int row;

  /// Whether the cutter turned the facing over before laying it down.
  final bool flipped;

  /// Which patch of the sheet this is, 0 to [patches] - 1.
  int get patch => column * rows + row;

  /// Where the patch sits on the sheet, as a [DecorationImage] alignment.
  Alignment get alignment =>
      Alignment(-1 + 2 * column / (columns - 1), -1 + 2 * row / (rows - 1));

  /// Cuts for [keys] in the order the facings will be laid, so that no two
  /// touching facings come off the same part of the sheet.
  static List<BurlwoodCut> run(Iterable<String> keys) {
    final cuts = <BurlwoodCut>[];
    int? above;
    for (final key in keys) {
      final hash = _hash(key);
      var patch = hash % patches;
      // An odd stride is coprime with a thirty-two patch sheet, so walking
      // by it always finds a clear patch rather than giving up.
      final stride = 1 + 2 * (hash ~/ patches % (patches ~/ 2));
      for (var guard = 0; guard < patches; guard++) {
        if (above == null || !_touches(patch, above)) break;
        patch = (patch + stride) % patches;
      }
      cuts.add(
        BurlwoodCut(
          column: patch ~/ rows,
          row: patch % rows,
          flipped: hash & 0x20 != 0,
        ),
      );
      above = patch;
    }
    return cuts;
  }

  /// Whether two patches would show continuous grain if laid together.
  static bool _touches(int a, int b) => (a % rows - b % rows).abs() < 2;

  /// A stable string hash. Deliberately not [String.hashCode], which the
  /// language does not promise to keep the same between runs.
  static int _hash(String key) {
    var h = 0x1505;
    for (var i = 0; i < key.length; i++) {
      h = ((h * 33) ^ key.codeUnitAt(i)) & 0x3fffffff;
    }
    return h;
  }

  @override
  bool operator ==(Object other) =>
      other is BurlwoodCut &&
      other.column == column &&
      other.row == row &&
      other.flipped == flipped;

  @override
  int get hashCode => Object.hash(column, row, flipped);

  @override
  String toString() =>
      'BurlwoodCut(column: $column, row: $row, flipped: $flipped)';
}

/// A facing of burlwood casework cut at [cut], with [child] laid over it.
///
/// Casework is the cabinet the app is built into, so this stays dark in both
/// appearance modes; take content colors from
/// `PanelSurface.burlwood.ink(tokens)`. The flat finish underneath carries
/// [groundKey] — it is what shows while the photograph decodes, and it is
/// the color the facing reads as.
///
/// Anything tappable inside must bring its own transparent [Material]: the
/// veneer is opaque, and a splash painted by an ancestor would be lost
/// behind it.
class BurlwoodSlice extends StatelessWidget {
  const BurlwoodSlice({
    required this.cut,
    required this.child,
    super.key,
    this.groundKey,
    this.jointed = true,
  });

  final BurlwoodCut cut;
  final Widget child;

  /// Goes on the flat stand-in beneath the photograph.
  final Key? groundKey;

  /// Draws the saw line along the top edge, where this facing was parted
  /// from its neighbour.
  final bool jointed;

  @override
  Widget build(BuildContext context) {
    Widget veneer = DecoratedBox(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: const AssetImage(ClawnsoleTextures.burlwood),
          // Unscaled, so the alignment picks a region of the sheet rather
          // than the same region seen closer or further away, and at the
          // same grain as the rail's own veneer.
          fit: BoxFit.none,
          alignment: cut.alignment,
          // Facings are meant to be smaller than the 1024 px sheet, which
          // every row in the app is; a larger one gets wood with a seam
          // rather than a band of flat finish.
          repeat: ImageRepeat.repeat,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
    if (cut.flipped) {
      veneer = Transform.scale(scaleX: -1, child: veneer);
    }
    return ColoredBox(
      key: groundKey,
      color: PanelSurface.burlwood.ground(context.tokens),
      child: Stack(
        children: <Widget>[
          Positioned.fill(child: veneer),
          // A whisper of shade so cream ink clears the bright figure
          // wherever the cut happens to land.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Colors.black.withValues(alpha: .1),
                    Colors.black.withValues(alpha: .26),
                  ],
                ),
                border: jointed
                    ? Border(
                        top: BorderSide(
                          color: Colors.black.withValues(alpha: .5),
                        ),
                      )
                    : null,
              ),
            ),
          ),
          // The fresh edge just under the kerf, catching the room.
          if (jointed)
            Positioned(
              top: 1,
              left: 0,
              right: 0,
              height: 1,
              child: ColoredBox(color: Colors.white.withValues(alpha: .07)),
            ),
          child,
        ],
      ),
    );
  }
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
      // The tiled texture is recorded once; whatever the screen does above
      // it paints into its own picture.
      child: RepaintBoundary(child: child),
    );
  }
}
