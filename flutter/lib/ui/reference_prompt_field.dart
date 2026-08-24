import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/services.dart';

import '../app/app_theme.dart';
import '../core/models.dart';
import '../core/reference_prompts.dart';

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
    final composing = value.composing;
    final hasComposing =
        withComposing &&
        composing.isValid &&
        !composing.isCollapsed &&
        composing.end <= text.length;
    final boundaries = <int>{
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
      children.add(
        TextSpan(
          text: text.substring(start, end),
          style: TextStyle(
            color: isMention ? colors.onPrimaryContainer : null,
            backgroundColor: isMention ? colors.primaryContainer : null,
            fontWeight: isMention ? FontWeight.w700 : null,
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
    super.key,
  });

  final String prompt;
  final int formRevision;
  final List<PromptReferenceOption> references;
  final ValueChanged<String> onChanged;
  final bool expands;
  final bool autofocus;
  final int? maxLength;

  @override
  State<ReferencePromptField> createState() => _ReferencePromptFieldState();
}

class _ReferencePromptFieldState extends State<ReferencePromptField> {
  late final _ReferencePromptEditingController _controller;
  late final FocusNode _focusNode;
  _PromptMentionQuery? _query;
  List<PromptReferenceOption> _suggestions = const <PromptReferenceOption>[];
  int? _highlightedSuggestion;

  @override
  void initState() {
    super.initState();
    _controller = _ReferencePromptEditingController(
      text: widget.prompt,
      mentions: _mentions(widget.references),
    )..addListener(_refreshSuggestions);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant ReferencePromptField oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.updateMentions(_mentions(widget.references));
    if (oldWidget.formRevision != widget.formRevision ||
        (_controller.text != widget.prompt &&
            oldWidget.prompt != widget.prompt)) {
      _controller.value = TextEditingValue(
        text: widget.prompt,
        selection: TextSelection.collapsed(offset: widget.prompt.length),
      );
    } else {
      _refreshSuggestions();
    }
  }

  List<PromptReferenceMention> _mentions(
    List<PromptReferenceOption> references,
  ) => references.map((reference) => reference.mention).toList();

  void _refreshSuggestions() {
    _preserveAncestorScrollForSelectAll();
    final query = _mentionQuery(_controller.value, widget.references);
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

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _suggestions.isEmpty) {
      return KeyEventResult.ignored;
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

  @override
  void dispose() {
    _controller
      ..removeListener(_refreshSuggestions)
      ..dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final promptField = Focus(
      onKeyEvent: _handleKeyEvent,
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
          controller: _controller,
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          expands: widget.expands,
          minLines: widget.expands ? null : 4,
          maxLines: widget.expands ? null : 10,
          maxLength: widget.maxLength ?? 50000,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
          style: const TextStyle(fontSize: 14.5, height: 1.5),
          onChanged: widget.onChanged,
          decoration: InputDecoration(
            hintText: widget.references.isEmpty
                ? 'A single continuous shot… describe movement, framing, sound, and what must stay consistent.'
                : 'A single continuous shot… type @ to mention an attached reference.',
            counterText: '',
            alignLabelWithHint: true,
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (widget.expands) Expanded(child: promptField) else promptField,
        if (_suggestions.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          Container(
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
                                    MediaReferenceKind.image =>
                                      Icons.image_rounded,
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
          ),
        ],
      ],
    );
  }
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
