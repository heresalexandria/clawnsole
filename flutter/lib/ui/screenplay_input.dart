import 'package:flutter/services.dart';

import '../core/screenplay.dart';

({int start, int end, String line}) screenplayCurrentLine(
  TextEditingValue value,
) {
  final caret = value.selection.isValid
      ? value.selection.extentOffset
      : value.text.length;
  final start = caret == 0 ? 0 : value.text.lastIndexOf('\n', caret - 1) + 1;
  final end = value.text.indexOf('\n', caret);
  return (
    start: start,
    end: end < 0 ? value.text.length : end,
    line: value.text.substring(start, end < 0 ? value.text.length : end),
  );
}

TextEditingValue setScreenplayElement(
  TextEditingValue value,
  ScreenplayElement element,
) {
  final current = screenplayCurrentLine(value);
  var content = current.line.trimLeft();
  if (element == ScreenplayElement.scene &&
      screenplayElement(content) != ScreenplayElement.scene) {
    content = 'INT. $content';
  }
  if (element == ScreenplayElement.parenthetical && !content.startsWith('(')) {
    content = content.isEmpty ? '(' : '($content)';
  }
  final line = formatScreenplayLine(content, element);
  final oldIndent = current.line.length - current.line.trimLeft().length;
  final relative = value.selection.isValid
      ? value.selection.extentOffset - current.start
      : current.line.length;
  final caret = content.isEmpty || current.line.trim().isEmpty
      ? line.length
      : (relative - oldIndent + element.indent).clamp(
          element.indent,
          line.length,
        );
  return TextEditingValue(
    text: value.text.replaceRange(current.start, current.end, line),
    selection: TextSelection.collapsed(offset: current.start + caret),
  );
}

/// Handles hardware and software keyboard edits identically, and leaves active
/// IME compositions alone. Programmatic changes and undo do not pass through it.
class ScreenplayInputFormatter extends TextInputFormatter {
  const ScreenplayInputFormatter({this.characterNames = const []});

  final List<String> characterNames;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.composing.isCollapsed ||
        !newValue.selection.isCollapsed ||
        !newValue.selection.isValid ||
        oldValue.text == newValue.text) {
      return newValue;
    }
    final oldLine = screenplayCurrentLine(oldValue);
    final caret = newValue.selection.extentOffset;
    final insertedNewline =
        caret > 0 &&
        newValue.text[caret - 1] == '\n' &&
        newValue.text.length ==
            oldValue.text.length -
                (oldValue.selection.isValid
                    ? oldValue.selection.end - oldValue.selection.start
                    : 0) +
                1;
    if (insertedNewline) {
      if (!oldValue.selection.isCollapsed) return newValue;
      var element = screenplayElement(oldLine.line);
      var baseText = newValue.text;
      var insertion = caret;
      final cue = oldLine.line.trim();
      if (element == ScreenplayElement.action &&
          cue.isNotEmpty &&
          oldValue.selection.extentOffset == oldLine.end &&
          !isScreenplayMapping(oldLine.line) &&
          ((cue == cue.toUpperCase() &&
                  screenplayCharacterNameProblem(cue) == null) ||
              characterNames.contains(normalizeCharacterName(cue)))) {
        element = ScreenplayElement.character;
      }
      if (element.uppercase && oldValue.selection.extentOffset == oldLine.end) {
        final formatted = formatScreenplayLine(oldLine.line, element);
        baseText = baseText.replaceRange(oldLine.start, caret - 1, formatted);
        insertion += formatted.length - oldLine.line.length;
      }
      if (oldLine.line.trim().isEmpty) {
        // Return on an empty indented element returns to action.
        return TextEditingValue(
          text: newValue.text.replaceRange(oldLine.start, caret, '\n'),
          selection: TextSelection.collapsed(offset: oldLine.start + 1),
        );
      }
      final next = element.next;
      final extra =
          '${next == ScreenplayElement.action || next == ScreenplayElement.scene ? '\n' : ''}${next == ScreenplayElement.scene ? 'INT. ' : ' ' * next.indent}';
      var text = baseText.replaceRange(insertion, insertion, extra);
      var offset = insertion + extra.length;
      if (element == ScreenplayElement.parenthetical &&
          !oldLine.line.trimRight().endsWith(')')) {
        text = text.replaceRange(insertion - 1, insertion - 1, ')');
        offset++;
      }
      return TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: offset),
      );
    }
    final current = screenplayCurrentLine(newValue);
    if (newValue.text.length - oldValue.text.length > 2 &&
        newValue.text.contains('\n')) {
      final formatted = formatScreenplay(newValue.text);
      final lines = formatted.split('\n');
      final lineIndex =
          newValue.text.substring(0, caret).split('\n').length - 1;
      final prefixLength = lines
          .take(lineIndex)
          .fold<int>(0, (count, line) => count + line.length + 1);
      final originalIndent =
          current.line.length - current.line.trimLeft().length;
      final newIndent =
          lines[lineIndex].length - lines[lineIndex].trimLeft().length;
      final relative = (caret - current.start - originalIndent + newIndent)
          .clamp(0, lines[lineIndex].length);
      return TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: prefixLength + relative),
      );
    }
    // Cut, deletion and selection replacement retain their exact text.
    if (newValue.text.length <= oldValue.text.length) {
      return newValue;
    }
    var element = screenplayElement(current.line);
    if (current.line.trimLeft().startsWith('(') &&
        element == ScreenplayElement.dialogue) {
      element = ScreenplayElement.parenthetical;
    }
    if (!element.uppercase && element != ScreenplayElement.parenthetical) {
      return newValue;
    }
    final formatted = formatScreenplayLine(current.line, element);
    if (formatted == current.line) return newValue;
    return TextEditingValue(
      text: newValue.text.replaceRange(current.start, current.end, formatted),
      selection: TextSelection.collapsed(
        offset: (caret + formatted.length - current.line.length).clamp(
          current.start,
          current.start + formatted.length,
        ),
      ),
    );
  }
}
