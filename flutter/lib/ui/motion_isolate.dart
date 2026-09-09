import 'package:flutter/widgets.dart';

/// Confines a self-rebuilding animation to its own layout and paint island.
///
/// Material's indeterminate progress indicators, [RotationTransition], and
/// the implicitly animated widgets rebuild themselves on every vsync. Since
/// Flutter 3.27 a rebuild anywhere below a [LayoutBuilder] schedules that
/// builder's layout callback, which marks every ancestor up to the nearest
/// relayout boundary dirty; each of those then re-runs layout and marks paint,
/// so one 10 px spinner inside a card re-recorded the whole studio page —
/// composer hardware, texture panels, shadows and all — 120 times a second.
///
/// This widget breaks that chain in two places. The tight-sized
/// [LayoutBuilder] is a relayout boundary and owns the rebuild scope, so the
/// child's rebuilds stay inside it; the [RepaintBoundary] outside keeps the
/// repaint to this island. The child renders exactly as before.
///
/// Give it a tight size: both dimensions, or one when the parent already
/// fixes the other (a bar stretched by `Positioned(left: 0, right: 0)` only
/// needs its height). Without a tight size the isolation does not hold, and
/// debug builds say so.
class MotionIsolate extends StatelessWidget {
  const MotionIsolate({
    required this.child,
    super.key,
    this.width,
    this.height,
  });

  final Widget child;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: SizedBox(
      width: width,
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          assert(
            constraints.isTight,
            'MotionIsolate needs a tight size to hold an animation apart from '
            'the page; it received $constraints.',
          );
          return child;
        },
      ),
    ),
  );
}
