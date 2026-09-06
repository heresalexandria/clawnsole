import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import 'composer_tab_rail.dart' show railRuleColor;
import 'hardware.dart';

/// One tab on a [SectionTabRail].
class SectionTab {
  const SectionTab({
    required this.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.count,
    this.semanticLabel,
  });

  final Key key;
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  /// A facet count shown in a small pill after the label; null hides it.
  final int? count;

  /// Overrides [label] as the spoken name ('Media' → 'Media references').
  final String? semanticLabel;
}

/// A desk's section tabs: folder tabs standing on a hairline rule that runs
/// to the edge, the same construction as the Create heading's draft rail but
/// cut larger, because these switch whole desks rather than drafts.
///
/// Idle tabs are raised console keys resting on the rule; the tab in front
/// is cut from the surface beneath it, stands taller, wears a brass lip along
/// its top, and covers the rule, so the open section reads as continuous
/// with the content below rather than as a lit button.
class SectionTabRail extends StatelessWidget {
  const SectionTabRail({required this.tabs, super.key, this.semanticLabel});

  final List<SectionTab> tabs;

  /// The spoken name of the rail as a group ('References desk').
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: semanticLabel,
    child: Stack(
      alignment: Alignment.bottomLeft,
      children: <Widget>[
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 1,
          child: ColoredBox(color: railRuleColor(context)),
        ),
        SizedBox(
          width: double.infinity,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                for (
                  var index = 0;
                  index < tabs.length;
                  index += 1
                ) ...<Widget>[
                  if (index > 0) const SizedBox(width: 6),
                  _SectionTabKey(tab: tabs[index]),
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

/// The corner radius of a tab's shoulders.
const double _radius = 11;

double _verticalPadding({required bool selected}) =>
    isHardwareTouchPlatform ? (selected ? 13 : 11) : (selected ? 12 : 10);

BoxDecoration _fill(BuildContext context, {required bool selected}) {
  const radius = BorderRadius.vertical(top: Radius.circular(_radius));
  if (selected) {
    return BoxDecoration(color: context.colors.surface, borderRadius: radius);
  }
  final key = consoleKeyDecoration(context, selected: false);
  return BoxDecoration(gradient: key.gradient, borderRadius: radius);
}

class _SectionTabKey extends StatelessWidget {
  const _SectionTabKey({required this.tab});

  final SectionTab tab;

  void _handleTap() {
    hardwareSelectionFeedback();
    tab.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final selected = tab.selected;
    final foreground = selected
        ? context.colors.onSurface
        : context.colors.onSurfaceVariant;
    final count = tab.count;
    return MergeSemantics(
      child: Semantics(
        container: true,
        button: true,
        inMutuallyExclusiveGroup: true,
        selected: selected,
        label: tab.semanticLabel ?? tab.label,
        value: count != null && count > 0 ? '$count' : null,
        child: HardwareTouchTarget(
          onTap: _handleTap,
          alignment: Alignment.bottomCenter,
          child: Padding(
            // Idle tabs rest on the rule; the front tab covers it.
            padding: EdgeInsets.only(bottom: selected ? 0 : 1),
            child: CustomPaint(
              foregroundPainter: _SectionTabOutlinePainter(
                color: railRuleColor(context),
                lip: selected ? context.tokens.brass : null,
              ),
              child: InkWell(
                key: tab.key,
                onTap: _handleTap,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(_radius),
                ),
                child: ExcludeSemantics(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    padding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: _verticalPadding(selected: selected),
                    ),
                    decoration: _fill(context, selected: selected),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          tab.icon,
                          size: 16,
                          color: selected ? context.tokens.brass : foreground,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          tab.label,
                          style: TextStyle(
                            color: foreground,
                            fontSize: 13,
                            fontWeight: selected
                                ? FontWeight.w800
                                : FontWeight.w600,
                            letterSpacing: .2,
                          ),
                        ),
                        if (count != null && count > 0) ...<Widget>[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: context.colors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '$count',
                              style: TextStyle(
                                color: context.colors.onSurfaceVariant,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Strokes a tab's shoulders and sides and leaves the foot open onto the
/// rule. The tab in front also gets a brass lip along its top.
class _SectionTabOutlinePainter extends CustomPainter {
  const _SectionTabOutlinePainter({required this.color, this.lip});

  final Color color;
  final Color? lip;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = .5;
    const r = _radius;
    final path = Path()
      ..moveTo(inset, size.height)
      ..lineTo(inset, r)
      ..arcToPoint(const Offset(r, inset), radius: const Radius.circular(r))
      ..lineTo(size.width - r, inset)
      ..arcToPoint(
        Offset(size.width - inset, r),
        radius: const Radius.circular(r),
      )
      ..lineTo(size.width - inset, size.height);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final accent = lip;
    if (accent != null) {
      canvas.drawLine(
        const Offset(r, 1),
        Offset(size.width - r, 1),
        Paint()
          ..color = accent
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_SectionTabOutlinePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.lip != lip;
}
