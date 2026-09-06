import 'models.dart';

/// Plain-text screenplay elements. Indentation is deliberately compact so the
/// same editable document fits a phone and a desktop without horizontal scroll.
enum ScreenplayElement {
  scene('Scene heading', 0),
  action('Action', 0),
  character('Character', 8),
  dialogue('Dialogue', 4),
  parenthetical('Parenthetical', 6),
  transition('Transition', 12);

  const ScreenplayElement(this.label, this.indent);
  final String label;
  final int indent;
  bool get uppercase =>
      this == scene || this == character || this == transition;

  ScreenplayElement get next => switch (this) {
    scene || action || dialogue => action,
    character || parenthetical => dialogue,
    transition => scene,
  };
}

final _scene = RegExp(
  r'^(?:INT\.?/EXT\.?|INT\.|EXT\.|EST\.|I/E)(?:\s|$)',
  caseSensitive: false,
);
final _transition = RegExp(
  r'(?:TO:|FADE OUT\.|FADE IN:)$',
  caseSensitive: false,
);
final _mapping = RegExp(r'^\s*[^\n:]+:\s*@[^\n]+$');

bool isScreenplayMapping(String line) => _mapping.hasMatch(line);

String normalizeCharacterName(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();

String? screenplayCharacterNameProblem(String value) {
  final name = normalizeCharacterName(value);
  if (name.isEmpty) return null; // An empty assignment removes the mapping.
  if (name.length > 60 ||
      !RegExp(
        r"^[\p{L}\p{N}][\p{L}\p{N} .’'_-]*$",
        unicode: true,
      ).hasMatch(name) ||
      !RegExp(r'\p{L}', unicode: true).hasMatch(name)) {
    return 'Use up to 60 letters, numbers, spaces, apostrophes, or hyphens.';
  }
  if (_scene.hasMatch(name) || _transition.hasMatch(name)) {
    return 'Choose a character name rather than a scene or transition.';
  }
  return null;
}

/// Shared by native and companion storage boundaries.
String? referenceCharacterAssignmentProblem(
  SavedReference reference,
  Iterable<SavedReference> existing,
) {
  final name = normalizeCharacterName(reference.characterName ?? '');
  final problem = screenplayCharacterNameProblem(name);
  if (problem != null) return problem;
  if (name.isNotEmpty &&
      existing.any(
        (item) =>
            item.id != reference.id &&
            normalizeCharacterName(item.characterName ?? '') == name,
      )) {
    return 'Character names must be unique across references.';
  }
  return null;
}

ScreenplayElement screenplayElement(String line) {
  final text = line.trim();
  if (isScreenplayMapping(line)) return ScreenplayElement.action;
  final indent = line.length - line.trimLeft().length;
  if (indent >= 12) return ScreenplayElement.transition;
  if (indent >= 8) return ScreenplayElement.character;
  if (indent >= 6) return ScreenplayElement.parenthetical;
  if (indent >= 4) return ScreenplayElement.dialogue;
  if (_scene.hasMatch(text)) return ScreenplayElement.scene;
  if (_transition.hasMatch(text)) return ScreenplayElement.transition;
  if (text.startsWith('(')) return ScreenplayElement.parenthetical;
  return ScreenplayElement.action;
}

String formatScreenplayLine(String line, ScreenplayElement element) {
  if (isScreenplayMapping(line)) return line;
  var content = line.trimLeft();
  if (element.uppercase) content = content.toUpperCase();
  return '${' ' * element.indent}$content';
}

/// Import ordinary screenplay text without treating every capitalized action
/// entity as a speaker. A cue needs dialogue on the following line.
String formatScreenplay(String text) {
  final lines = text.replaceAll('\r\n', '\n').split('\n');
  var previous = ScreenplayElement.action;
  return List.generate(lines.length, (index) {
    final line = lines[index];
    final clean = line.trim();
    if (clean.isEmpty) {
      previous = ScreenplayElement.action;
      return line;
    }
    var element = screenplayElement(line);
    if (element == ScreenplayElement.action && !isScreenplayMapping(line)) {
      if (previous == ScreenplayElement.character ||
          previous == ScreenplayElement.parenthetical ||
          previous == ScreenplayElement.dialogue) {
        element = ScreenplayElement.dialogue;
      } else if (clean == clean.toUpperCase() &&
          screenplayCharacterNameProblem(clean) == null &&
          index + 1 < lines.length &&
          lines[index + 1].trim().isNotEmpty &&
          (index == 0 || lines[index - 1].trim().isEmpty)) {
        element = ScreenplayElement.character;
      }
    }
    previous = element;
    return formatScreenplayLine(line, element);
  }).join('\n');
}

/// Use the editor's character cues, never uppercase words in action text.
Set<String> screenplayCharacters(String text) {
  final result = <String>{};
  for (final line in formatScreenplay(text).split('\n')) {
    if (screenplayElement(line) == ScreenplayElement.character) {
      final name = line.trim().replaceFirst(RegExp(r'\s*\([^)]*\)\s*$'), '');
      if (name.isNotEmpty) result.add(name);
    }
  }
  return result;
}

bool screenplayMentionsCharacter(
  String script,
  String character, {
  bool caseSensitive = true,
}) {
  final body = script
      .split('\n')
      .where((line) => !isScreenplayMapping(line))
      .join('\n');
  return RegExp(
    '(?<![\\p{L}\\p{N}_@])${RegExp.escape(character)}(?![\\p{L}\\p{N}_])',
    unicode: true,
    caseSensitive: caseSensitive,
  ).hasMatch(body);
}

List<String> screenplayCompletions(
  String text,
  String line,
  Iterable<String> names,
) {
  final query = line.trimLeft().toUpperCase();
  final element = screenplayElement(line);
  if (query.contains('@') ||
      element == ScreenplayElement.dialogue ||
      element == ScreenplayElement.parenthetical) {
    return const [];
  }
  final options = <String>{
    if (element == ScreenplayElement.action ||
        element == ScreenplayElement.scene) ...[
      'INT.',
      'EXT.',
      'INT./EXT.',
      'EST.',
      'I/E',
    ],
    if (element == ScreenplayElement.transition) ...[
      'CUT TO:',
      'DISSOLVE TO:',
      'FADE OUT.',
    ],
    if (element == ScreenplayElement.scene)
      ...text
          .split('\n')
          .where((line) => _scene.hasMatch(line.trim()))
          .map((line) => line.trim()),
    if (element == ScreenplayElement.action ||
        element == ScreenplayElement.character) ...{
      ...names,
      ...screenplayCharacters(text),
    },
  };
  return options
      .where((option) => option.startsWith(query) && option != query)
      .take(8)
      .toList();
}

/// Reads casting lines out of text. The composer no longer keeps them in the
/// editable prompt — this parses legacy workspaces, reused films, and pasted
/// or rewritten text so [stripScreenplayMappings] can lift them into the cast.
Map<String, List<String>> screenplayMappings(String prompt) {
  final result = <String, List<String>>{};
  for (final line in prompt.split('\n').where(isScreenplayMapping)) {
    final colon = line.indexOf(':');
    final name = normalizeCharacterName(line.substring(0, colon));
    result
        .putIfAbsent(name, () => [])
        .addAll(
          line
              .substring(colon + 1)
              .split('@')
              .skip(1)
              .map(
                (name) => name.trim().replaceFirst(RegExp(r'[,;]$'), '').trim(),
              )
              .where((name) => name.isNotEmpty),
        );
  }
  return result;
}

/// Removes casting lines from [prompt], leaving the rest byte-identical. The
/// blank separator a casting block was written with goes with it, so lifting
/// legacy lines into the cast restores exactly the direction that was typed.
String stripScreenplayMappings(String prompt) {
  final lines = prompt.split('\n');
  if (!lines.any(isScreenplayMapping)) return prompt;
  final kept = <String>[];
  for (final line in lines) {
    if (!isScreenplayMapping(line)) {
      kept.add(line);
      continue;
    }
    while (kept.isNotEmpty && kept.last.trim().isEmpty) {
      kept.removeLast();
    }
  }
  final last = lines.lastWhere(
    (line) => line.trim().isNotEmpty,
    orElse: () => '',
  );
  if (isScreenplayMapping(last)) {
    while (kept.isNotEmpty && kept.last.trim().isEmpty) {
      kept.removeLast();
    }
  }
  return kept.join('\n');
}

/// The casting block appended to the direction at submission: one line per
/// cast member holding at least one reference, names in alphabetical order.
List<String> screenplayCastLines(Map<String, List<String>> mappings) {
  final names = mappings.keys.where((name) {
    final references = mappings[name];
    return name.isNotEmpty && references != null && references.isNotEmpty;
  }).toList()..sort();
  return [
    for (final name in names)
      '$name: ${mappings[name]!.toSet().map((item) => '@$item').join(' ')}',
  ];
}

String renameScreenplayCharacter(
  String prompt,
  String previous,
  String name, {
  bool caseSensitive = true,
}) {
  final pattern = RegExp(
    '(?<![\\p{L}\\p{N}_@])${RegExp.escape(previous)}(?![\\p{L}\\p{N}_])',
    unicode: true,
    caseSensitive: caseSensitive,
  );
  return prompt
      .split('\n')
      .map(
        (line) =>
            isScreenplayMapping(line) ? line : line.replaceAll(pattern, name),
      )
      .join('\n');
}
