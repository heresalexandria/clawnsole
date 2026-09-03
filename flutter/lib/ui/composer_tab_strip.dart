import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import 'hardware.dart';

/// The Create screen's composer tabs: one console key per open draft, plus a
/// key that opens another.
///
/// The strip is a single scrolling line at every width, so it never grows a
/// second row on the heading and never pushes the composer below the fold.
/// Keys read exactly like the ratio strip and the library filters: raised
/// when idle, lit plum when the draft is in front.
class ComposerTabStrip extends StatelessWidget {
  const ComposerTabStrip({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final tabs = controller.composerTabs;
    final activeId = controller.activeComposerTabId;
    return Semantics(
      container: true,
      label: 'Composer tabs',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
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
              const SizedBox(width: 5),
            ],
            _NewComposerTabKey(controller: controller),
          ],
        ),
      ),
    );
  }
}

/// How close together two taps must land to count as a rename gesture.
const Duration _renameTapWindow = Duration(milliseconds: 320);

/// One draft's key: an optional rewrite mark, its label, and a close control.
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
          child: ExcludeSemantics(
            child: InkWell(
              onTap: _handleTap,
              onLongPress: () => unawaited(_rename()),
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding: EdgeInsets.fromLTRB(10, 7, closable ? 3 : 10, 7),
                decoration: consoleKeyDecoration(
                  context,
                  selected: selected,
                  radius: 10,
                ),
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
                    if (closable)
                      _CloseTabButton(controller: widget.controller, tab: tab),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The tiny × inside a tab key. It is its own button node so a screen reader
/// can close a draft without leaving the strip.
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

/// The trailing "+" key that opens another draft.
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
      child: Tooltip(
        message: 'New tab',
        child: ExcludeSemantics(
          child: InkWell(
            key: const ValueKey('composer-tab-add'),
            onTap: _add,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: consoleKeyDecoration(
                context,
                selected: false,
                radius: 10,
              ),
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
