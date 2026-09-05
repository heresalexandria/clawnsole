import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../app/app_theme.dart';
import '../core/models.dart';
import '../core/reference_prompts.dart';
import '../core/screenplay.dart';
import 'screenplay_input.dart';

class PromptReferenceOption {
  const PromptReferenceOption({
    required this.id,
    required this.mention,
    required this.label,
  });

  final String id;
  final PromptReferenceMention mention;
  final String label;
}

class _ReferencePromptEditingController extends TextEditingController {
  _ReferencePromptEditingController({
    required super.text,
    required List<PromptReferenceMention> mentions,
  }) : _attachedMentions = mentions;

  List<PromptReferenceMention> _attachedMentions;
  bool screenplayMode = false;
  double screenplayWidth = 720;

  void updateMentions(List<PromptReferenceMention> mentions) {
    final current = _attachedMentions
        .map((mention) => '${mention.normalized}:${mention.authoringName}')
        .toSet();
    final next = mentions
        .map((mention) => '${mention.normalized}:${mention.authoringName}')
        .toSet();
    if (setEquals(current, next)) return;
    _attachedMentions = mentions;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final mentionRanges = promptReferenceMatches(
      text,
      available: _attachedMentions,
    ).map((match) => (start: match.start, end: match.end)).toList();
    if (!screenplayMode && mentionRanges.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final composing = value.composing;
    final hasComposing =
        withComposing &&
        composing.isValid &&
        !composing.isCollapsed &&
        composing.end <= text.length;
    final boundaries = <int>{
      if (screenplayMode) ...[
        ...RegExp(r'\n').allMatches(text).map((match) => match.end),
        ...RegExp(
          r'^ +',
          multiLine: true,
        ).allMatches(text).map((match) => match.end),
      ],
      0,
      text.length,
      for (final range in mentionRanges) ...<int>[range.start, range.end],
      if (hasComposing) ...<int>[composing.start, composing.end],
    }.toList()..sort();
    final colors = Theme.of(context).colorScheme;
    final children = <InlineSpan>[];
    for (var index = 0; index < boundaries.length - 1; index += 1) {
      final start = boundaries[index];
      final end = boundaries[index + 1];
      if (start == end) continue;
      final isMention = mentionRanges.any(
        (range) => start >= range.start && end <= range.end,
      );
      final isComposing =
          hasComposing && start >= composing.start && end <= composing.end;
      final lineStart = start == 0 ? 0 : text.lastIndexOf('\n', start - 1) + 1;
      final lineEnd = text.indexOf('\n', start);
      final element = screenplayMode
          ? screenplayElement(
              text.substring(lineStart, lineEnd < 0 ? text.length : lineEnd),
            )
          : null;
      final indent = element?.indent ?? 0;
      final isIndent =
          screenplayMode &&
          indent > 0 &&
          start == lineStart &&
          text.substring(start, end).trim().isEmpty;
      final fraction = switch (element) {
        ScreenplayElement.character => .34,
        ScreenplayElement.dialogue => .18,
        ScreenplayElement.parenthetical => .27,
        ScreenplayElement.transition => .62,
        _ => 0.0,
      };
      children.add(
        TextSpan(
          text: text.substring(start, end),
          style: TextStyle(
            // Scale only the leading spaces. Document offsets and clipboard
            // text remain plain text while page margins fit the viewport.
            letterSpacing: isIndent
                ? screenplayWidth * fraction / (end - start) -
                      (style?.fontSize ?? 14) * .6
                : null,
            color: isMention ? colors.onPrimaryContainer : null,
            backgroundColor: isMention ? colors.primaryContainer : null,
            fontWeight: isMention || element?.uppercase == true
                ? FontWeight.w700
                : null,
            decoration: isComposing ? TextDecoration.underline : null,
          ),
        ),
      );
    }
    return TextSpan(style: style, children: children);
  }
}

class ReferencePromptField extends StatefulWidget {
  const ReferencePromptField({
    required this.prompt,
    required this.formRevision,
    required this.references,
    required this.onChanged,
    this.expands = false,
    this.autofocus = false,
    this.maxLength,
    this.minLines = 4,
    this.screenplayMode = false,
    this.characterNames = const [],
    this.toolbar,
    super.key,
  });

  final String prompt;
  final int formRevision;
  final List<PromptReferenceOption> references;
  final ValueChanged<String> onChanged;
  final bool expands;
  final bool autofocus;
  final int? maxLength;
  final int minLines;
  final bool screenplayMode;
  final List<String> characterNames;
  final Widget? toolbar;

  @override
  State<ReferencePromptField> createState() => _ReferencePromptFieldState();
}

class _ReferencePromptFieldState extends State<ReferencePromptField> {
  late final _ReferencePromptEditingController _controller;
  late final FocusNode _focusNode;
  late TextEditingValue _lastEditingValue;
  bool _typingReference = false;
  final OverlayPortalController _suggestionsOverlay = OverlayPortalController();
  // Preserve the portal's attachment to its controller when format controls
  // or the Expanded wrapper change the editor's position in the widget tree.
  final GlobalKey _portalKey = GlobalKey();
  final GlobalKey _fieldKey = GlobalKey();
  RenderEditable? _editable;
  _PromptMentionQuery? _query;
  List<PromptReferenceOption> _suggestions = const <PromptReferenceOption>[];
  int? _highlightedSuggestion;
  int? _screenplayHighlight;
  bool _dismissScreenplaySuggestions = false;

  List<String> get _screenplaySuggestions =>
      !widget.screenplayMode || _dismissScreenplaySuggestions
      ? const []
      : screenplayCompletions(
          _controller.text,
          screenplayCurrentLine(_controller.value).line,
          widget.characterNames,
        );

  @override
  void initState() {
    super.initState();
    _controller =
        _ReferencePromptEditingController(
            text: widget.prompt,
            mentions: _mentions(widget.references),
          )
          ..screenplayMode = widget.screenplayMode
          ..addListener(_editingChanged);
    _lastEditingValue = _controller.value;
    // Handle menu navigation at the primary focus. A surrounding Focus can
    // lose Enter to EditableText's multiline action before bubbling reaches
    // it, which inserts a newline instead of accepting the highlighted tag.
    _focusNode = FocusNode(onKeyEvent: _handleKeyEvent);
  }

  @override
  void didUpdateWidget(covariant ReferencePromptField oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.screenplayMode = widget.screenplayMode;
    _controller.updateMentions(_mentions(widget.references));
    if (oldWidget.formRevision != widget.formRevision ||
        (_controller.text != widget.prompt &&
            oldWidget.prompt != widget.prompt)) {
      final previous = _controller.value;
      _controller.value = TextEditingValue(
        text: widget.prompt,
        selection:
            widget.prompt.startsWith(previous.text) &&
                previous.selection.isValid
            ? previous.selection
            : TextSelection.collapsed(
                offset: previous.selection.isValid
                    ? previous.selection.extentOffset.clamp(
                        0,
                        widget.prompt.length,
                      )
                    : widget.prompt.length,
              ),
      );
    } else {
      _refreshSuggestions();
    }
  }

  List<PromptReferenceMention> _mentions(
    List<PromptReferenceOption> references,
  ) => references.map((reference) => reference.mention).toList();

  void _editingChanged() {
    final value = _controller.value;
    if (value.text != _lastEditingValue.text) {
      _typingReference = true;
    } else if (value.selection != _lastEditingValue.selection) {
      // Moving through an existing tag is text navigation, not a request to
      // complete it. Only typing should start a reference menu.
      _typingReference = false;
    }
    _lastEditingValue = value;
    _refreshSuggestions();
  }

  void _refreshSuggestions() {
    _preserveAncestorScrollForSelectAll();
    if (widget.screenplayMode && mounted) setState(() {});
    final query =
        _typingReference &&
            _focusNode.hasFocus &&
            _controller.value.composing.isCollapsed
        ? _mentionQuery(_controller.value, widget.references)
        : null;
    final suggestions = query == null
        ? const <PromptReferenceOption>[]
        : widget.references.where((reference) {
            final name = reference.mention.authoringName
                .replaceAll(' ', '')
                .toLowerCase();
            return name.startsWith(query.normalized);
          }).toList();
    if (!mounted ||
        (_query == query && _sameOptions(_suggestions, suggestions))) {
      return;
    }
    setState(() {
      _query = query;
      _suggestions = suggestions;
      _highlightedSuggestion = null;
    });
    if (suggestions.isEmpty) {
      _suggestionsOverlay.hide();
    } else {
      // Normal text-input notifications happen between frames, so the real
      // caret render object is available immediately. didUpdateWidget can
      // also reach this path during build; defer discovery in that case.
      try {
        _editable ??= _findRenderEditable();
      } on FlutterError {
        // The post-frame fallback below will discover it safely.
      }
      _suggestionsOverlay.show();
      if (_editable == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _suggestions.isEmpty) return;
          _editable = _findRenderEditable();
          if (_editable != null) setState(() {});
        });
      }
    }
  }

  void _preserveAncestorScrollForSelectAll() {
    final selection = _controller.selection;
    if (_controller.text.isEmpty ||
        selection.baseOffset != 0 ||
        selection.extentOffset != _controller.text.length) {
      return;
    }
    final position = Scrollable.maybeOf(context)?.position;
    if (position == null || !position.hasPixels) return;
    unawaited(_restoreScrollAfterSelectionReveal(position, position.pixels));
  }

  Future<void> _restoreScrollAfterSelectionReveal(
    ScrollPosition position,
    double offset,
  ) async {
    // Platform-native context menus can bypass Flutter's SelectAllTextIntent
    // and send a selection update through the text input connection. The first
    // frame lets EditableText attach its reveal animation; the second reaches
    // its first tick so jumpTo can cancel it before it moves the page.
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !position.hasPixels || !position.hasContentDimensions) {
      return;
    }
    final target = offset.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    // jumpTo also cancels EditableText's in-flight ancestor reveal animation
    // when its first tick has not moved the position yet.
    position.jumpTo(target);
  }

  bool _sameOptions(
    List<PromptReferenceOption> left,
    List<PromptReferenceOption> right,
  ) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      if (left[index].id != right[index].id) return false;
    }
    return true;
  }

  void _select(PromptReferenceOption option) {
    final query = _query;
    if (query == null) return;
    final nextText = _controller.text.replaceRange(
      query.start,
      query.end,
      option.mention.canonical,
    );
    final caret = query.start + option.mention.canonical.length;
    _controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: caret),
    );
    widget.onChanged(nextText);
    _focusNode.requestFocus();
  }

  Object? _selectAllWithoutRevealing(SelectAllTextIntent intent) {
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
    return null;
  }

  void _changeElement(ScreenplayElement element) {
    _controller.value = setScreenplayElement(_controller.value, element);
    _dismissScreenplaySuggestions = false;
    widget.onChanged(_controller.text);
    _focusNode.requestFocus();
  }

  void _cycleElement(bool reverse) {
    final current = screenplayElement(
      screenplayCurrentLine(_controller.value).line,
    );
    final next =
        ScreenplayElement.values[(current.index + (reverse ? -1 : 1)) %
            ScreenplayElement.values.length];
    _changeElement(next);
  }

  void _completeScreenplay(String suggestion) {
    final current = screenplayCurrentLine(_controller.value);
    var element = screenplayElement(suggestion);
    if (element == ScreenplayElement.action) {
      element = ScreenplayElement.character;
    }
    final line = formatScreenplayLine(suggestion, element);
    _controller.value = TextEditingValue(
      text: _controller.text.replaceRange(current.start, current.end, line),
      selection: TextSelection.collapsed(offset: current.start + line.length),
    );
    _screenplayHighlight = null;
    widget.onChanged(_controller.text);
    _focusNode.requestFocus();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if ((event is! KeyDownEvent && event is! KeyRepeatEvent) ||
        !_controller.value.composing.isCollapsed) {
      return KeyEventResult.ignored;
    }
    if (widget.screenplayMode) {
      if (event.logicalKey == LogicalKeyboardKey.tab) {
        _cycleElement(HardwareKeyboard.instance.isShiftPressed);
        return KeyEventResult.handled;
      }
      final options = _screenplaySuggestions;
      if (event.logicalKey == LogicalKeyboardKey.escape && options.isNotEmpty) {
        setState(() => _dismissScreenplaySuggestions = true);
        return KeyEventResult.handled;
      }
      if (_suggestions.isEmpty && options.isNotEmpty) {
        if (HardwareKeyboard.instance.isAltPressed &&
            (event.logicalKey == LogicalKeyboardKey.arrowDown ||
                event.logicalKey == LogicalKeyboardKey.arrowUp)) {
          setState(
            () => _screenplayHighlight =
                ((_screenplayHighlight ??
                        (event.logicalKey == LogicalKeyboardKey.arrowDown
                            ? -1
                            : 0)) +
                    (event.logicalKey == LogicalKeyboardKey.arrowDown
                        ? 1
                        : -1)) %
                options.length,
          );
          return KeyEventResult.handled;
        }
        if ((event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
            _screenplayHighlight != null) {
          _completeScreenplay(
            options[_screenplayHighlight!.clamp(0, options.length - 1)],
          );
          return KeyEventResult.handled;
        }
      }
    }
    if (!HardwareKeyboard.instance.isAltPressed &&
        {
          LogicalKeyboardKey.arrowUp,
          LogicalKeyboardKey.arrowDown,
          LogicalKeyboardKey.arrowLeft,
          LogicalKeyboardKey.arrowRight,
        }.contains(event.logicalKey)) {
      _screenplayHighlight = null;
    }
    if (_suggestions.isEmpty) {
      return KeyEventResult.ignored;
    }
    // Modified arrows belong to the text field (selection, word/paragraph
    // movement). Only unmodified Up/Down navigate an actively typed @ query.
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isShiftPressed ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }
    if ({
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.home,
      LogicalKeyboardKey.end,
      LogicalKeyboardKey.escape,
    }.contains(event.logicalKey)) {
      _typingReference = false;
      _refreshSuggestions();
      return event.logicalKey == LogicalKeyboardKey.escape
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _highlightedSuggestion = _highlightedSuggestion == null
              ? 0
              : (_highlightedSuggestion! + 1) % _suggestions.length;
        } else {
          _highlightedSuggestion = _highlightedSuggestion == null
              ? _suggestions.length - 1
              : (_highlightedSuggestion! - 1) % _suggestions.length;
        }
      });
      return KeyEventResult.handled;
    }
    if ((event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
        _highlightedSuggestion != null) {
      _select(_suggestions[_highlightedSuggestion!]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  RenderEditable? _findRenderEditable() {
    final field = _fieldKey.currentContext;
    if (field == null) return null;
    RenderEditable? editable;
    void visit(Element element) {
      if (editable != null) return;
      final renderObject = element.findRenderObject();
      if (renderObject is RenderEditable) {
        editable = renderObject;
        return;
      }
      element.visitChildElements(visit);
    }

    field.visitChildElements(visit);
    return editable;
  }

  Widget _buildSuggestionsOverlay(BuildContext context) {
    if (_suggestions.isEmpty) return const SizedBox.shrink();
    final overlay = Overlay.of(context).context.findRenderObject();
    final editable = _editable;
    final field = _fieldKey.currentContext?.findRenderObject();
    if (overlay is! RenderBox || editable == null || field is! RenderBox) {
      return const SizedBox.shrink();
    }

    final selection = _controller.selection;
    final caretOffset = selection.isValid
        ? selection.extentOffset.clamp(0, _controller.text.length)
        : _controller.text.length;
    final caret = editable.getLocalRectForCaret(
      TextPosition(offset: caretOffset),
    );
    final caretTop = overlay.globalToLocal(
      editable.localToGlobal(caret.topLeft),
    );
    final caretBottom = overlay.globalToLocal(
      editable.localToGlobal(caret.bottomLeft),
    );
    final mediaQuery = MediaQuery.of(context);
    const margin = 8.0;
    const gap = 6.0;
    final minimumTop = mediaQuery.padding.top + margin;
    final maximumBottom =
        overlay.size.height - mediaQuery.padding.bottom - margin;
    final availableWidth = overlay.size.width - margin * 2;
    final menuWidth = field.size.width
        .clamp(240.0, 360.0)
        .clamp(0.0, availableWidth);
    final menuHeight = (_suggestions.length * 44.0).clamp(44.0, 260.0);
    final left = caretTop.dx.clamp(
      margin,
      (overlay.size.width - menuWidth - margin).clamp(margin, double.infinity),
    );
    final below = caretBottom.dy + gap;
    final above = caretTop.dy - menuHeight - gap;
    final top = below + menuHeight <= maximumBottom
        ? below
        : above >= minimumTop
        ? above
        : below.clamp(
            minimumTop,
            (maximumBottom - menuHeight).clamp(minimumTop, double.infinity),
          );

    return Positioned(
      left: left,
      top: top,
      width: menuWidth,
      child: _suggestionsMenu(),
    );
  }

  Widget _suggestionsMenu() => Container(
    key: const ValueKey('prompt-reference-suggestions'),
    decoration: BoxDecoration(
      color: context.colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: context.colors.outlineVariant),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: Colors.black.withValues(alpha: .08),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 260),
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: _suggestions
            .asMap()
            .entries
            .map(
              (entry) => ColoredBox(
                color: _highlightedSuggestion == entry.key
                    ? context.colors.primaryContainer
                    : Colors.transparent,
                child: InkWell(
                  key: ValueKey(
                    'prompt-reference-${entry.value.mention.normalized}',
                  ),
                  onTap: () => _select(entry.value),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          switch (entry.value.mention.kind) {
                            MediaReferenceKind.image => Icons.image_rounded,
                            MediaReferenceKind.video =>
                              Icons.video_library_rounded,
                            MediaReferenceKind.audio =>
                              Icons.graphic_eq_rounded,
                          },
                          size: 18,
                          color: context.colors.primary,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          entry.value.mention.canonical,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            entry.value.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: context.colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    ),
  );

  @override
  void dispose() {
    _controller
      ..removeListener(_editingChanged)
      ..dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _controller.screenplayWidth = (constraints.maxWidth - 36).clamp(
        0.0,
        double.infinity,
      );
      final promptField = OverlayPortal(
        key: _portalKey,
        controller: _suggestionsOverlay,
        overlayChildBuilder: _buildSuggestionsOverlay,
        child: Actions(
          actions: <Type, Action<Intent>>{
            // EditableText normally asks every ancestor Scrollable to reveal the
            // selection endpoint after Select All. The prompt has its own
            // internal scroller, so that request only makes the surrounding
            // Create screen jump. Preserve the selection behavior without
            // propagating a reveal.
            SelectAllTextIntent: CallbackAction<SelectAllTextIntent>(
              onInvoke: _selectAllWithoutRevealing,
            ),
          },
          child: TextFormField(
            key: _fieldKey,
            controller: _controller,
            focusNode: _focusNode,
            autofocus: widget.autofocus,
            expands: widget.expands,
            textAlign: widget.expands ? TextAlign.left : TextAlign.start,
            textAlignVertical: widget.expands ? TextAlignVertical.top : null,
            minLines: widget.expands ? null : widget.minLines,
            maxLines: widget.expands ? null : 10,
            maxLength: widget.maxLength ?? 50000,
            maxLengthEnforcement: MaxLengthEnforcement.enforced,
            inputFormatters: widget.screenplayMode
                ? [
                    ScreenplayInputFormatter(
                      characterNames: widget.characterNames,
                    ),
                  ]
                : null,
            textCapitalization: widget.screenplayMode
                ? TextCapitalization.none
                : TextCapitalization.sentences,
            autocorrect: !widget.screenplayMode,
            style: TextStyle(
              fontFamily: promptFontFamily,
              fontSize: 14,
              height: 1.55,
            ),
            onChanged: (value) {
              _dismissScreenplaySuggestions = false;
              _screenplayHighlight = null;
              widget.onChanged(value);
            },
            decoration: InputDecoration(
              hintText: widget.screenplayMode
                  ? 'INT. LOCATION - DAY\n\nDescribe the action. Tab to write a character.'
                  : widget.references.isEmpty
                  ? 'A single continuous shot… describe movement, framing, sound, and what must stay consistent.'
                  : 'A single continuous shot… type @ to mention an attached reference.',
              counterText: '',
              alignLabelWithHint: true,
            ),
          ),
        ),
      );
      final screenplayControls = <Widget>[
        if (widget.screenplayMode) ...[
          DropdownButton<ScreenplayElement>(
            key: const ValueKey('screenplay-element-picker'),
            isDense: true,
            style: Theme.of(context).textTheme.labelMedium,
            value: screenplayElement(
              screenplayCurrentLine(_controller.value).line,
            ),
            underline: const SizedBox.shrink(),
            items: ScreenplayElement.values
                .map(
                  (element) => DropdownMenuItem(
                    value: element,
                    child: Text(element.label),
                  ),
                )
                .toList(),
            onChanged: (element) {
              if (element != null) _changeElement(element);
            },
          ),
          TextButton.icon(
            onPressed: () => _cycleElement(true),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Prev'),
            style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
            key: const ValueKey('screenplay-previous-element'),
          ),
          TextButton.icon(
            onPressed: () => _cycleElement(false),
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: const Text('Next'),
            style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
            key: const ValueKey('screenplay-next-element'),
          ),
        ],
      ];
      final editor = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (widget.toolbar != null) widget.toolbar!,
          if (widget.screenplayMode) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                MediaQuery.sizeOf(context).width < 620
                    ? 'Tap the element menu or arrows to change line type. Return continues the script.'
                    : 'Enter continues the script · Tab / Shift Tab changes element',
                style: TextStyle(
                  fontSize: 11,
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
          if (widget.expands) Expanded(child: promptField) else promptField,
          if (widget.screenplayMode)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                key: const ValueKey('screenplay-element-toolbar'),
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: screenplayControls,
              ),
            ),
          if (_screenplaySuggestions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _screenplaySuggestions.indexed
                      .map(
                        (entry) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: InputChip(
                            label: Text(entry.$2),
                            selected: _screenplayHighlight == entry.$1,
                            onPressed: () => _completeScreenplay(entry.$2),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
        ],
      );
      return editor;
    },
  );
}

class _PromptMentionQuery {
  const _PromptMentionQuery({
    required this.start,
    required this.end,
    required this.normalized,
  });

  final int start;
  final int end;
  final String normalized;

  @override
  bool operator ==(Object other) =>
      other is _PromptMentionQuery &&
      start == other.start &&
      end == other.end &&
      normalized == other.normalized;

  @override
  int get hashCode => Object.hash(start, end, normalized);
}

_PromptMentionQuery? _mentionQuery(
  TextEditingValue value,
  List<PromptReferenceOption> references,
) {
  final selection = value.selection;
  if (!selection.isValid || !selection.isCollapsed) return null;
  final beforeCaret = value.text.substring(0, selection.extentOffset);
  final start = beforeCaret.lastIndexOf('@');
  if (start < 0) return null;
  final candidate = beforeCaret.substring(start);
  if (candidate.substring(1).contains('@') ||
      candidate.contains('\n') ||
      candidate.contains('\r')) {
    return null;
  }
  if (references.any(
    (reference) =>
        reference.mention.canonical.toLowerCase() == candidate.toLowerCase(),
  )) {
    return null;
  }
  return _PromptMentionQuery(
    start: start,
    end: selection.extentOffset,
    normalized: candidate.substring(1).replaceAll(' ', '').toLowerCase(),
  );
}
