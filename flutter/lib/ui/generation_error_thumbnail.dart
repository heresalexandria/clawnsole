import 'package:flutter/material.dart';

import '../core/generation_status.dart';
import '../core/models.dart';

/// Thumbnail for a generation that failed before delivering media: the SMPTE
/// color-bar test pattern with the error on a full-width black band centered
/// on the thumbnail. Dead air reads as dead air, the message stays
/// high-contrast in either theme, and the corner chips keep their usual
/// places instead of yielding the whole media zone to an error panel.
class GenerationErrorThumbnail extends StatelessWidget {
  const GenerationErrorThumbnail({
    required this.item,
    super.key,
    this.dense = false,
  });

  final Generation item;

  /// Tighter band metrics for mini, compact, and activity thumbnails.
  final bool dense;

  /// Whether [item] is a dead render with nothing better to show. Delivered
  /// media is ground truth: a late failure status on a playable record must
  /// not replace its media with test bars.
  static bool shouldShow(Generation item) =>
      !item.hasDeliveredMedia && (item.isFailed || item.error != null);

  /// The most specific problem the record carries. Identifier-shaped values
  /// (a bare task id stored by older builds) are never shown; an expired
  /// task explains itself instead.
  static String message(Generation item) {
    for (final candidate in <String?>[
      item.error,
      item.resultRetentionError,
      item.lastCheckError,
    ]) {
      if (candidate == null || candidate.trim().isEmpty) continue;
      if (isIdentifierLikeFailureText(candidate)) continue;
      return candidate;
    }
    if (isExpiryShapedStatus(item.status) || item.deliveryExpired) {
      return expiredGenerationMessage;
    }
    return 'This generation failed.';
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Generation failed: ${message(item)}',
    child: Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const CustomPaint(painter: SmpteColorBarsPainter()),
        Center(
          child: Container(
            key: ValueKey('generation-error-band-${item.localId}'),
            width: double.infinity,
            color: Colors.black,
            padding: EdgeInsets.symmetric(
              horizontal: dense ? 9 : 16,
              vertical: dense ? 6 : 11,
            ),
            child: Text(
              message(item),
              textAlign: TextAlign.center,
              maxLines: dense ? 3 : 6,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: dense ? 9.5 : 12,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// The SMPTE EG 1-1990 color-bar pattern: 75% bars over the top two thirds,
/// the castellation strip beneath them, and the −I / white / +Q / PLUGE row
/// along the bottom quarter.
class SmpteColorBarsPainter extends CustomPainter {
  const SmpteColorBarsPainter();

  static const Color _gray = Color(0xFFC0C0C0);
  static const Color _yellow = Color(0xFFC0C000);
  static const Color _cyan = Color(0xFF00C0C0);
  static const Color _green = Color(0xFF00C000);
  static const Color _magenta = Color(0xFFC000C0);
  static const Color _red = Color(0xFFC00000);
  static const Color _blue = Color(0xFF0000C0);
  static const Color _black = Color(0xFF131313);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _inPhase = Color(0xFF00214C);
  static const Color _quadrature = Color(0xFF32006A);
  static const Color _plugeDark = Color(0xFF090909);
  static const Color _plugeLight = Color(0xFF1D1D1D);

  static const List<Color> _topBars = <Color>[
    _gray,
    _yellow,
    _cyan,
    _green,
    _magenta,
    _red,
    _blue,
  ];
  static const List<Color> _castellation = <Color>[
    _blue,
    _black,
    _magenta,
    _black,
    _cyan,
    _black,
    _gray,
  ];

  /// Bottom-row cells as (color, width in top-bar units): −I, white, and +Q
  /// at five quarters each, then the PLUGE triplet under the red bar.
  static const List<(Color, double)> _bottomBars = <(Color, double)>[
    (_inPhase, 5 / 4),
    (_white, 5 / 4),
    (_quadrature, 5 / 4),
    (_black, 5 / 4),
    (_plugeDark, 1 / 3),
    (_black, 1 / 3),
    (_plugeLight, 1 / 3),
    (_black, 1),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = false;
    final barWidth = size.width / 7;
    final castellationTop = size.height * 2 / 3;
    final bottomTop = size.height * 3 / 4;
    for (var i = 0; i < 7; i++) {
      paint.color = _topBars[i];
      canvas.drawRect(
        Rect.fromLTRB(i * barWidth, 0, (i + 1) * barWidth, castellationTop),
        paint,
      );
      paint.color = _castellation[i];
      canvas.drawRect(
        Rect.fromLTRB(
          i * barWidth,
          castellationTop,
          (i + 1) * barWidth,
          bottomTop,
        ),
        paint,
      );
    }
    var left = 0.0;
    for (final (color, width) in _bottomBars) {
      paint.color = color;
      canvas.drawRect(
        Rect.fromLTRB(left, bottomTop, left + width * barWidth, size.height),
        paint,
      );
      left += width * barWidth;
    }
  }

  @override
  bool shouldRepaint(SmpteColorBarsPainter oldDelegate) => false;
}
