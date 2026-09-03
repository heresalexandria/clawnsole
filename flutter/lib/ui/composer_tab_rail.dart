import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import 'hardware.dart';

/// The Create heading's tab rail: one tab per open draft plus a "+" tab,
/// standing on a hairline rule that runs on to [trailing] (the model plaque)
/// or, without one, to the edge.
///
/// Tabs are console keys cut as folder tabs: rounded on top, square where
/// they meet the rule. Idle tabs rest on the line; the tab in front stands a
/// touch taller, lit plum, and covers the line beneath it, so the open draft
/// reads as continuous with the composer below.
class ComposerTabRail extends StatelessWidget {
  const ComposerTabRail({required this.controller, super.key, this.trailing});

  final AppController controller;

  /// What ends the rule on the right, bottom-aligned with the tabs.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tabs = controller.composerTabs;
    final activeId = controller.activeComposerTabId;
    final rail = Semantics(
      container: true,
      label: 'Composer tabs',
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
                  for (final tab in tabs) ...<Widget>[
                    _ComposerTabKey(
                      key: ValueKey<String>('composer-tab-${tab.id}'),
                      controller: controller,
                      tab: tab,
                      selected: tab.id == activeId,
                      closable: tabs.length > 1,
                      position: tabs.indexOf(tab) + 1,
                      total: tabs.length,
                    ),
                    const SizedBox(width: 4),
                  ],
                  _NewComposerTabKey(controller: controller),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    final end = trailing;
    if (end == null) return rail;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(child: rail),
        const SizedBox(width: 18),
        end,
      ],
    );
  }
}

/// The hairline the tabs stand on: the same thread as card borders.
Color railRuleColor(BuildContext context) => context.colors.outlineVariant;

/// The corner radius of a tab's shoulders.
const double _tabRadius = 9;

/// How close together two taps must land to count as a rename gesture.
const Duration _renameTapWindow = Duration(milliseconds: 320);

/// The fill of a tab: the console-key gradient (raised when idle, lit plum
/// in front) cut with rounded shoulders and a flat foot. The outline is
/// painted separately so the foot can stay open onto the rule.
BoxDecoration _tabFill(BuildContext context, {required bool selected}) {
  final key = consoleKeyDecoration(context, selected: selected);
  return BoxDecoration(
    gradient: key.gradient,
    boxShadow: key.boxShadow,
    borderRadius: const BorderRadius.vertical(top: Radius.circular(_tabRadius)),
  );
}

/// Strokes a tab's shoulders and sides and leaves the foot open.
class _TabOutlinePainter extends CustomPainter {
  const _TabOutlinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = .5;
    const r = _tabRadius;
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
  }

  @override
  bool shouldRepaint(_TabOutlinePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// One draft's tab: an optional rewrite mark, its label, and a close control.
class _ComposerTabKey extends StatefulWidget {
  const _ComposerTabKey({
    required this.controller,
    required this.tab,
    required this.selected,
    required this.closable,
    required this.position,
    required this.total,
    super.key,
  });

  final AppController controller;
  final ComposerTab tab;
  final bool selected;
  final bool closable;
  final int position;
  final int total;

  @override
  State<_ComposerTabKey> createState() => _ComposerTabKeyState();
}

class _ComposerTabKeyState extends State<_ComposerTabKey> {
  /// Double-tap is recognised here rather than through `onDoubleTap`, which
  /// would hold every ordinary tab switch back for the double-tap timeout.
  DateTime? _lastTap;

  void _handleTap() {
    final now = DateTime.now();
    final previous = _lastTap;
    _lastTap = now;
    hardwareSelectionFeedback();
    widget.controller.activateComposerTab(widget.tab.id);
    if (previous != null && now.difference(previous) < _renameTapWindow) {
      _lastTap = null;
      unawaited(_rename());
    }
  }

  Future<void> _rename() async {
    final renamed = await showComposerTabRenameDialog(context, widget.tab);
    if (renamed == null) return;
    widget.controller.renameComposerTab(widget.tab.id, renamed);
  }

  @override
  Widget build(BuildContext context) {
    final tab = widget.tab;
    final selected = widget.selected;
    final closable = widget.closable;
    final foreground = selected
        ? context.colors.onPrimary
        : context.colors.onSurface;
    final summary = tab.rewriteSummary?.trim() ?? '';
    return MergeSemantics(
      child: Semantics(
        container: true,
        button: true,
        inMutuallyExclusiveGroup: true,
        selected: selected,
        label: 'Tab ${widget.position} of ${widget.total}, ${tab.label}',
        hint: 'Long press to rename',
        onTap: _handleTap,
        child: HardwareTouchTarget(
          onTap: _handleTap,
          alignment: Alignment.bottomCenter,
          child: ExcludeSemantics(
            child: Padding(
              // Idle tabs rest on the rule; the front tab covers it.
              padding: EdgeInsets.only(bottom: selected ? 0 : 1),
              child: CustomPaint(
                foregroundPainter: _TabOutlinePainter(
                  color: selected
                      ? context.colors.primary
                      : railRuleColor(context),
                ),
                child: InkWell(
                  onTap: _handleTap,
                  onLongPress: () => unawaited(_rename()),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(_tabRadius),
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    padding: EdgeInsets.fromLTRB(
                      11,
                      selected ? 8 : 6,
                      closable || selected ? 4 : 11,
                      selected ? 8 : 6,
                    ),
                    decoration: _tabFill(context, selected: selected),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (summary.isNotEmpty) ...<Widget>[
                          Tooltip(
                            message: summary,
                            child: Icon(
                              Icons.auto_awesome,
                              size: 12,
                              color: selected
                                  ? context.colors.onPrimary
                                  : context.tokens.brass,
                            ),
                          ),
                          const SizedBox(width: 5),
                        ],
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 160),
                          child: Text(
                            tab.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                            style: TextStyle(
                              color: foreground,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (selected)
                          _RenameTabButton(tab: tab, onTap: _rename),
                        if (closable)
                          _CloseTabButton(
                            controller: widget.controller,
                            tab: tab,
                          ),
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

/// The small pencil on the tab in front: the visible way to rename a draft
/// (long-press and double-tap still work on any tab).
class _RenameTabButton extends StatelessWidget {
  const _RenameTabButton({required this.tab, required this.onTap});

  final ComposerTab tab;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Rename tab ${tab.label}',
    onTap: () => unawaited(onTap()),
    child: HardwareTouchTarget(
      onTap: () => unawaited(onTap()),
      minWidth: 32,
      child: Tooltip(
        message: 'Rename tab',
        child: InkResponse(
          key: ValueKey<String>('composer-tab-rename-${tab.id}'),
          onTap: () => unawaited(onTap()),
          radius: 14,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Icon(
              Icons.edit_outlined,
              size: 12,
              color: context.colors.onPrimary.withValues(alpha: .85),
            ),
          ),
        ),
      ),
    ),
  );
}

/// The tiny × inside a tab. It is its own button node so a screen reader
/// can close a draft without leaving the rail.
class _CloseTabButton extends StatelessWidget {
  const _CloseTabButton({required this.controller, required this.tab});

  final AppController controller;
  final ComposerTab tab;

  void _close() {
    hardwareSelectionFeedback();
    controller.closeComposerTab(tab.id);
  }

  @override
  Widget build(BuildContext context) {
    final selected = tab.id == controller.activeComposerTabId;
    return Semantics(
      button: true,
      label: 'Close tab ${tab.label}',
      onTap: _close,
      child: HardwareTouchTarget(
        onTap: _close,
        minWidth: 32,
        child: Tooltip(
          message: 'Close tab',
          child: InkResponse(
            key: ValueKey<String>('composer-tab-close-${tab.id}'),
            onTap: _close,
            radius: 14,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              child: Icon(
                Icons.close_rounded,
                size: 13,
                color: selected
                    ? context.colors.onPrimary
                    : context.colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The trailing "+" tab that opens another draft.
class _NewComposerTabKey extends StatelessWidget {
  const _NewComposerTabKey({required this.controller});

  final AppController controller;

  void _add() {
    hardwareSelectionFeedback();
    controller.addComposerTab();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'New tab',
    onTap: _add,
    child: HardwareTouchTarget(
      onTap: _add,
      alignment: Alignment.bottomCenter,
      child: Tooltip(
        message: 'New tab',
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 1),
            child: CustomPaint(
              foregroundPainter: _TabOutlinePainter(
                color: railRuleColor(context),
              ),
              child: InkWell(
                key: const ValueKey('composer-tab-add'),
                onTap: _add,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(_tabRadius),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: _tabFill(context, selected: false),
                  child: Icon(
                    Icons.add_rounded,
                    size: 15,
                    color: context.colors.onSurfaceVariant,
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

/// Asks for a tab's name. Returns the typed name, an empty string to go back
/// to the prompt-derived label, or null when the director cancels.
Future<String?> showComposerTabRenameDialog(
  BuildContext context,
  ComposerTab tab,
) => showDialog<String>(
  context: context,
  builder: (dialogContext) => _RenameTabDialog(title: tab.title ?? ''),
);

/// The dialog owns its field controller so it outlives the closing
/// animation, which still rebuilds the field after the pop.
class _RenameTabDialog extends StatefulWidget {
  const _RenameTabDialog({required this.title});

  final String title;

  @override
  State<_RenameTabDialog> createState() => _RenameTabDialogState();
}

class _RenameTabDialogState extends State<_RenameTabDialog> {
  late final TextEditingController _field = TextEditingController(
    text: widget.title,
  );

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Name this tab'),
    content: TextField(
      key: const ValueKey('composer-tab-rename-field'),
      controller: _field,
      autofocus: true,
      decoration: const InputDecoration(
        labelText: 'Tab name',
        helperText: 'Leave empty to name it after the direction.',
      ),
      onSubmitted: (value) => Navigator.pop(context, value),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('composer-tab-rename-save'),
        onPressed: () => Navigator.pop(context, _field.text),
        child: const Text('Save'),
      ),
    ],
  );
}
