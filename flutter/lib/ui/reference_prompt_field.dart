import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals, setEquals;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
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

/// One line of a screenplay as the highlighter sees it: where it starts and
/// which element it is. Computed once per text, not once per span.
typedef _ScreenplayLine = ({int start, int end, ScreenplayElement element});

/// The plain word a character name would complete: where it starts, where the
/// caret is, and the letters typed so far.
typedef _CharacterNameQuery = ({int start, int end, String prefix});

/// One row of the completion menu. The `@` mentions and the character names
/// share the overlay, so they also share its look, position and key handling.
class _SuggestionRow {
  const _SuggestionRow({
    required this.key,
    required this.icon,
    required this.title,
    required this.onSelect,
    this.subtitle,
  });

  final Key key;
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onSelect;
}

class _ReferencePromptEditingController extends TextEditingController {
  _ReferencePromptEditingController({
    required super.text,
    required List<PromptReferenceMention> mentions,
  }) : _attachedMentions = mentions;

  List<PromptReferenceMention> _attachedMentions;
  bool screenplayMode = false;
  double screenplayWidth = 720;

  // buildTextSpan runs on every frame the editor rebuilds — each keystroke,
  // caret move, and parent rebuild. The document scans it needs (mention
  // matches, one element per screenplay line) depend only on the text and
  // the attached mentions, so they are kept until either changes.
  String? _scannedText;
  List<PromptReferenceMention>? _scannedMentions;
  bool _scannedScreenplay = false;
  List<({int start, int end})> _mentionRanges = const [];
  List<_ScreenplayLine> _lines = const [];

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

  void _scan() {
    if (_scannedText == text &&
        _scannedScreenplay == screenplayMode &&
        identical(_scannedMentions, _attachedMentions)) {
      return;
    }
    _scannedText = text;
    _scannedScreenplay = screenplayMode;
    _scannedMentions = _attachedMentions;
    _mentionRanges = promptReferenceMatches(
      text,
      available: _attachedMentions,
    ).map((match) => (start: match.start, end: match.end)).toList();
    if (!screenplayMode) {
      _lines = const [];
      return;
    }
    final lines = <_ScreenplayLine>[];
    var start = 0;
    while (true) {
      final newline = text.indexOf('\n', start);
      final end = newline < 0 ? text.length : newline;
      lines.add((
        start: start,
        end: end,
        element: screenplayElement(text.substring(start, end)),
      ));
      if (newline < 0) break;
      start = newline + 1;
    }
    _lines = lines;
  }

  /// The line holding [offset], by binary search over the scanned lines.
  _ScreenplayLine _lineAt(int offset) {
    var low = 0;
    var high = _lines.length - 1;
    while (low < high) {
      final middle = (low + high + 1) >> 1;
      if (_lines[middle].start <= offset) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return _lines[low];
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    _scan();
    final mentionRanges = _mentionRanges;
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
      if (screenplayMode)
        for (final line in _lines) ...<int>[
          line.start,
          // The leading spaces are their own span so only they stretch.
          if (line.element.indent > 0)
            line.start + _leadingSpaces(text, line.start, line.end),
          if (line.end < text.length) line.end + 1,
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
      final line = screenplayMode ? _lineAt(start) : null;
      final element = line?.element;
      final indent = element?.indent ?? 0;
      final isIndent =
          screenplayMode &&
          indent > 0 &&
          start == line!.start &&
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

  static int _leadingSpaces(String text, int start, int end) {
    var count = 0;
    while (start + count < end && text.codeUnitAt(start + count) == 0x20) {
      count += 1;
    }
    return count;
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
    this.hintText,
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
  final String? hintText;

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
  _CharacterNameQuery? _nameQuery;
  List<String> _nameSuggestions = const <String>[];
  // Escape dismisses names for the word being typed, so the dismissal is
  // remembered against that word's start rather than against a match.
  int? _dismissedNameStart;
  int? _highlightedSuggestion;
  int? _screenplayHighlight;
  bool _allowFocusTraversal = false;
  bool _dismissScreenplaySuggestions = false;
  bool _suggestionsRefreshPending = false;

  // Completions scan the whole script for character cues. They are read
  // several times per build and per key event, so they are computed once
  // per editing value and set of names.
  TextEditingValue? _suggestionsValue;
  List<String>? _suggestionsNames;
  List<String> _screenplaySuggestionsCache = const [];

  /// What the screenplay cue flow offers at the caret, whether or not it has
  /// been dismissed. The character-name menu stands down wherever this is
  /// non-empty, so the two never compete for one caret.
  List<String> get _screenplayCompletionsAtCaret {
    if (!widget.screenplayMode) return const [];
    final value = _controller.value;
    if (_suggestionsValue != value ||
        !listEquals(_suggestionsNames, widget.characterNames)) {
      _suggestionsValue = value;
      _suggestionsNames = widget.characterNames;
      _screenplaySuggestionsCache = screenplayCompletions(
        value.text,
        screenplayCurrentLine(value).line,
        widget.characterNames,
      );
    }
    return _screenplaySuggestionsCache;
  }

  List<String> get _screenplaySuggestions =>
      _dismissScreenplaySuggestions ? const [] : _screenplayCompletionsAtCaret;

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
    _focusNode = FocusNode(onKeyEvent: _handleKeyEvent)
      ..addListener(_focusChanged);
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

  void _focusChanged() {
    if (!_focusNode.hasFocus) _typingReference = false;
    _refreshSuggestions();
  }

  void _refreshSuggestions() {
    // External draft changes can update the editing controller during build.
    // OverlayPortal cannot show or hide in that phase; refresh once after the
    // frame so resets and restored text cannot assert or leave a stale menu.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (!_suggestionsRefreshPending) {
        _suggestionsRefreshPending = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _suggestionsRefreshPending = false;
          if (mounted) _refreshSuggestions();
        });
      }
      return;
    }
    _preserveAncestorScrollForSelectAll();
    if (widget.screenplayMode && mounted) setState(() {});
    final value = _controller.value;
    final typing =
        _typingReference && _focusNode.hasFocus && value.composing.isCollapsed;
    final query = typing ? _mentionQuery(value, widget.references) : null;
    final suggestions = query == null
        ? const <PromptReferenceOption>[]
        : widget.references.where((reference) {
            final name = reference.mention.authoringName
                .replaceAll(' ', '')
                .toLowerCase();
            return name.startsWith(query.normalized);
          }).toList();
    // The dismissal expires with the word, not with the match, so a word that
    // stops matching and matches again stays dismissed until the caret leaves.
    final word = _typedWord(value);
    if (word == null || word.start != _dismissedNameStart) {
      _dismissedNameStart = null;
    }
    final nameQuery =
        word != null &&
            typing &&
            query == null &&
            _dismissedNameStart == null &&
            _screenplayCompletionsAtCaret.isEmpty
        ? (
            start: word.start,
            end: word.end,
            prefix: value.text.substring(word.start, word.end),
          )
        : null;
    final names = nameQuery == null
        ? const <String>[]
        : _characterNameMatches(nameQuery.prefix, widget.characterNames);
    final matchedNameQuery = names.isEmpty ? null : nameQuery;
    if (!mounted ||
        (_query == query &&
            _sameOptions(_suggestions, suggestions) &&
            _nameQuery == matchedNameQuery &&
            listEquals(_nameSuggestions, names))) {
      return;
    }
    setState(() {
      _query = query;
      _suggestions = suggestions;
      _nameQuery = matchedNameQuery;
      _nameSuggestions = names;
      // A name list starts on its first row, so Down leaves it for the second.
      // The mention list keeps its own start, where Down opens on the first.
      _highlightedSuggestion = names.isEmpty ? null : 0;
    });
    if (suggestions.isEmpty && names.isEmpty) {
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
          if (!mounted || _rows.isEmpty) return;
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
    _controller.value = _completeReference(_controller.value, query, option);
    widget.onChanged(_controller.text);
    _focusNode.requestFocus();
  }

  void _selectName(String name) {
    final query = _nameQuery;
    if (query == null) return;
    _controller.value = _completeName(_controller.value, query, name);
    widget.onChanged(_controller.text);
    _focusNode.requestFocus();
  }

  /// A character name is ordinary prose: the stored spelling replaces the
  /// typed prefix with no tag, no styling, and — like a completed `@` mention
  /// — no trailing space, so the director keeps punctuating the sentence.
  TextEditingValue _completeName(
    TextEditingValue value,
    _CharacterNameQuery query,
    String name,
  ) => TextEditingValue(
    text: value.text.replaceRange(query.start, query.end, name),
    selection: TextSelection.collapsed(offset: query.start + name.length),
  );

  void _dismissNameSuggestions() {
    final query = _nameQuery;
    if (query != null) _dismissedNameStart = query.start;
  }

  TextEditingValue _completeReference(
    TextEditingValue value,
    _PromptMentionQuery query,
    PromptReferenceOption option,
  ) {
    final nextText = value.text.replaceRange(
      query.start,
      query.end,
      option.mention.canonical,
    );
    final caret = query.start + option.mention.canonical.length;
    return TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: caret),
    );
  }

  TextEditingValue _formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final query = _query;
    final nameQuery = _nameQuery;
    final keyboard = HardwareKeyboard.instance;
    // Software keyboards send multiline Return as an editing value instead of
    // a KeyEvent. Only accept a single newline at the active query's caret;
    // leave composition, selection replacement, multiline paste and modified
    // Return alone.
    final completionEnd = query != null && _suggestions.isNotEmpty
        ? query.end
        : nameQuery != null && _nameSuggestions.isNotEmpty
        ? nameQuery.end
        : null;
    if (completionEnd != null &&
        _focusNode.hasFocus &&
        oldValue.composing.isCollapsed &&
        newValue.composing.isCollapsed &&
        oldValue.selection.isCollapsed &&
        oldValue.selection.extentOffset == completionEnd &&
        newValue.selection.isCollapsed &&
        newValue.selection.extentOffset == completionEnd + 1 &&
        newValue.text.length == oldValue.text.length + 1 &&
        newValue.text[completionEnd] == '\n' &&
        !keyboard.isShiftPressed &&
        !keyboard.isControlPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isAltPressed &&
        newValue.text ==
            oldValue.text.replaceRange(completionEnd, completionEnd, '\n')) {
      return query != null && _suggestions.isNotEmpty
          ? _completeReference(
              oldValue,
              query,
              _suggestions[_highlightedSuggestion ?? 0],
            )
          : _completeName(
              oldValue,
              nameQuery!,
              _nameSuggestions[(_highlightedSuggestion ?? 0).clamp(
                0,
                _nameSuggestions.length - 1,
              )],
            );
    }
    final formatted = widget.screenplayMode
        ? ScreenplayInputFormatter(
            characterNames: widget.characterNames,
          ).formatEditUpdate(oldValue, newValue)
        : newValue;
    // Keep ordinary typing/paste bounded, but insert reference names atomically
    // like click and hardware-key completion. Truncating a completed name can
    // silently turn it back into an unrecognized partial tag.
    return LengthLimitingTextInputFormatter(
      widget.maxLength ?? 50000,
      maxLengthEnforcement: MaxLengthEnforcement.enforced,
    ).formatEditUpdate(oldValue, formatted);
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
    final keyboard = HardwareKeyboard.instance;
    final unmodified =
        !keyboard.isShiftPressed &&
        !keyboard.isControlPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isAltPressed;
    // Tab accepts a character name before the screenplay editor reads it as an
    // element change. The two never offer completions at the same caret, so
    // element cycling is untouched wherever the name menu is closed.
    if (event.logicalKey == LogicalKeyboardKey.tab &&
        unmodified &&
        _nameSuggestions.isNotEmpty) {
      _selectName(
        _nameSuggestions[(_highlightedSuggestion ?? 0).clamp(
          0,
          _nameSuggestions.length - 1,
        )],
      );
      return KeyEventResult.handled;
    }
    if (widget.screenplayMode) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _allowFocusTraversal = true;
        _typingReference = false;
        _dismissNameSuggestions();
        _refreshSuggestions();
        setState(() => _dismissScreenplaySuggestions = true);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.tab &&
          !_allowFocusTraversal &&
          !HardwareKeyboard.instance.isControlPressed &&
          !HardwareKeyboard.instance.isMetaPressed &&
          !HardwareKeyboard.instance.isAltPressed) {
        _cycleElement(HardwareKeyboard.instance.isShiftPressed);
        return KeyEventResult.handled;
      }
      if (event.logicalKey != LogicalKeyboardKey.tab) {
        _allowFocusTraversal = false;
      }
      final options = _screenplaySuggestions;
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
    final rows = _rows;
    if (rows.isEmpty) {
      return KeyEventResult.ignored;
    }
    // Modified arrows belong to the text field (selection, word/paragraph
    // movement). Only unmodified Up/Down navigate an actively typed query.
    if (!unmodified) {
      return KeyEventResult.ignored;
    }
    if ({
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.home,
      LogicalKeyboardKey.end,
      LogicalKeyboardKey.escape,
    }.contains(event.logicalKey)) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _dismissNameSuggestions();
      }
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
              : (_highlightedSuggestion! + 1) % rows.length;
        } else {
          _highlightedSuggestion = _highlightedSuggestion == null
              ? rows.length - 1
              : (_highlightedSuggestion! - 1) % rows.length;
        }
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      rows[(_highlightedSuggestion ?? 0).clamp(0, rows.length - 1)].onSelect();
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

  /// Only one of the two lists is ever populated: the mention flow wins while
  /// an `@` query is being typed, and names complete the plain word otherwise.
  List<_SuggestionRow> get _rows => <_SuggestionRow>[
    for (final option in _suggestions)
      _SuggestionRow(
        key: ValueKey('prompt-reference-${option.mention.normalized}'),
        icon: switch (option.mention.kind) {
          MediaReferenceKind.image => Icons.image_rounded,
          MediaReferenceKind.video => Icons.video_library_rounded,
          MediaReferenceKind.audio => Icons.graphic_eq_rounded,
        },
        title: option.mention.canonical,
        subtitle: option.label,
        onSelect: () => _select(option),
      ),
    for (final name in _nameSuggestions)
      _SuggestionRow(
        key: ValueKey('prompt-character-$name'),
        icon: Icons.person_rounded,
        title: name,
        onSelect: () => _selectName(name),
      ),
  ];

  Widget _buildSuggestionsOverlay(BuildContext context) {
    final rows = _rows;
    if (rows.isEmpty) return const SizedBox.shrink();
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
    final menuHeight = (rows.length * 44.0).clamp(44.0, 260.0);
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
      // Keep the overlay in this editor's tap region. The app dismisses the
      // keyboard on outside pointer-down, before a suggestion's onTap can run.
      child: TextFieldTapRegion(
        groupId: _focusNode,
        child: _suggestionsMenu(rows),
      ),
    );
  }

  Widget _suggestionsMenu(List<_SuggestionRow> rows) => Container(
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
        children: rows.indexed
            .map(
              (entry) => ColoredBox(
                key: entry.$2.key,
                color: (_highlightedSuggestion ?? 0) == entry.$1
                    ? context.colors.primaryContainer
                    : Colors.transparent,
                child: InkWell(
                  canRequestFocus: false,
                  onTap: entry.$2.onSelect,
                  child: Container(
                    // A finger-sized row, and the height the menu reserves.
                    constraints: const BoxConstraints(minHeight: 44),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          entry.$2.icon,
                          size: 18,
                          color: context.colors.primary,
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            entry.$2.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (entry.$2.subtitle case final subtitle?) ...<Widget>[
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: context.colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
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
    _focusNode
      ..removeListener(_focusChanged)
      ..dispose();
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
            groupId: _focusNode,
            controller: _controller,
            focusNode: _focusNode,
            autofocus: widget.autofocus,
            expands: widget.expands,
            textAlign: widget.expands ? TextAlign.left : TextAlign.start,
            textAlignVertical: widget.expands ? TextAlignVertical.top : null,
            minLines: widget.expands ? null : widget.minLines,
            maxLines: widget.expands ? null : 10,
            maxLength: widget.maxLength ?? 50000,
            maxLengthEnforcement: MaxLengthEnforcement.none,
            inputFormatters: [
              TextInputFormatter.withFunction(_formatEditUpdate),
            ],
            // Screenplay pages want sentence capitalization too: the core
            // uppercases scene headings, cues and transitions itself when it
            // formats a line, so the soft keyboard's shift cannot fight it.
            textCapitalization: TextCapitalization.sentences,
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
              hintText:
                  widget.hintText ??
                  (widget.screenplayMode
                      ? 'INT. LOCATION - DAY\n\nDescribe the action. Tab to write a character.'
                      : widget.references.isEmpty
                      ? 'A single continuous shot… describe movement, framing, sound, and what must stay consistent.'
                      : 'A single continuous shot… type @ to mention an attached reference.'),
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
                    : 'Enter continues the script · Tab / Shift Tab changes element · Esc then Tab leaves the editor',
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

final _wordCharacter = RegExp(r'[\p{L}\p{N}_]', unicode: true);
final _letter = RegExp(r'\p{L}', unicode: true);

/// The letters-only word that ends exactly at the caret. Null when the caret
/// sits inside a word the director is editing, when nothing has been typed,
/// or when the letters continue a tag or an alphanumeric token.
({int start, int end})? _typedWord(TextEditingValue value) {
  final selection = value.selection;
  if (!selection.isValid || !selection.isCollapsed) return null;
  final text = value.text;
  final caret = selection.extentOffset;
  if (caret <= 0 || caret > text.length) return null;
  if (caret < text.length && _wordCharacter.hasMatch(text[caret])) return null;
  var start = caret;
  while (start > 0 && _letter.hasMatch(text[start - 1])) {
    start -= 1;
  }
  if (start == caret) return null;
  if (start > 0 &&
      (text[start - 1] == '@' || _wordCharacter.hasMatch(text[start - 1]))) {
    return null;
  }
  return (start: start, end: caret);
}

/// Names whose spelling begins with [prefix], in the order they were given.
/// A word already spelled as a name in full is finished, not a query.
List<String> _characterNameMatches(String prefix, List<String> names) {
  final query = prefix.toLowerCase();
  if (names.any((name) => name.toLowerCase() == query)) return const <String>[];
  final seen = <String>{};
  final matches = <String>[];
  for (final name in names) {
    final candidate = name.toLowerCase();
    if (!candidate.startsWith(query) || !seen.add(candidate)) continue;
    matches.add(name);
    if (matches.length == 8) break;
  }
  return matches;
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
