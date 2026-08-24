import 'models.dart';

/// The stable, provider-neutral reference name shown in Clawnsole prompts.
class PromptReferenceMention {
  const PromptReferenceMention({
    required this.kind,
    required this.number,
    this.name,
  });

  final MediaReferenceKind kind;
  final int number;
  final String? name;

  String get defaultName => '${kind.label} $number';

  String get authoringName {
    final clean = name?.trim() ?? '';
    return clean.isEmpty ? defaultName : clean;
  }

  String get canonical => '@$authoringName';

  String get normalized => '${kind.name}$number';

  bool get usesDefaultName =>
      authoringName.toLowerCase() == defaultName.toLowerCase();
}

enum ReferencePromptDialect {
  /// Clawnsole's readable authoring form, for example `@Video 1`.
  canonical,

  /// Compact tags used by Seedance prompt examples, for example `@video1`.
  compactAt,

  /// Ordered natural-language labels, for example `video 1`.
  plainOrdinal,

  /// xAI reference placeholders, for example `<VIDEO_1>`.
  angleBracketUpper,
}

final RegExp _mentionPattern = RegExp(
  r'@(image|video|audio)\s*(\d+)(?![A-Za-z0-9_])',
  caseSensitive: false,
);

final RegExp _reservedReferenceNamePattern = RegExp(
  r'^(?:image|video|audio)\s*\d+$',
  caseSensitive: false,
);

bool isReservedReferenceName(String value) =>
    _reservedReferenceNamePattern.hasMatch(value.trim());

class PromptReferenceTextMatch {
  const PromptReferenceTextMatch({
    required this.start,
    required this.end,
    required this.mention,
  });

  final int start;
  final int end;
  final PromptReferenceMention mention;
}

List<PromptReferenceTextMatch> promptReferenceMatches(
  String value, {
  required Iterable<PromptReferenceMention> available,
}) {
  final mentions = available.toList();
  final matches = <PromptReferenceTextMatch>[];

  for (final match in _mentionPattern.allMatches(value)) {
    final parsed = parsePromptReferenceMention(match.group(0)!);
    if (parsed == null) continue;
    final mention = mentions.where((candidate) {
      return candidate.usesDefaultName &&
          candidate.kind == parsed.kind &&
          candidate.number == parsed.number;
    }).firstOrNull;
    if (mention != null) {
      matches.add(
        PromptReferenceTextMatch(
          start: match.start,
          end: match.end,
          mention: mention,
        ),
      );
    }
  }

  for (final mention in mentions.where(
    (candidate) => !candidate.usesDefaultName,
  )) {
    final escaped = RegExp.escape(mention.canonical);
    final pattern = RegExp('$escaped(?![A-Za-z0-9_])', caseSensitive: false);
    for (final match in pattern.allMatches(value)) {
      matches.add(
        PromptReferenceTextMatch(
          start: match.start,
          end: match.end,
          mention: mention,
        ),
      );
    }
  }

  matches.sort((left, right) {
    final start = left.start.compareTo(right.start);
    if (start != 0) return start;
    return right.end.compareTo(left.end);
  });
  final distinct = <PromptReferenceTextMatch>[];
  var end = -1;
  for (final match in matches) {
    if (match.start < end) continue;
    distinct.add(match);
    end = match.end;
  }
  return distinct;
}

List<PromptReferenceMention> promptReferenceMentions(
  Iterable<MediaReferenceKind> kinds, {
  Map<MediaReferenceKind, List<String>> names =
      const <MediaReferenceKind, List<String>>{},
}) {
  final counts = <MediaReferenceKind, int>{};
  return kinds.map((kind) {
    final number = (counts[kind] ?? 0) + 1;
    counts[kind] = number;
    final kindNames = names[kind] ?? const <String>[];
    return PromptReferenceMention(
      kind: kind,
      number: number,
      name: number <= kindNames.length ? kindNames[number - 1] : null,
    );
  }).toList();
}

const String referencePromptNamesInputKey = '_clawnsole_reference_names';

Map<MediaReferenceKind, List<String>> referencePromptNamesFromInput(
  Map<String, Object?> input,
) {
  final raw = input[referencePromptNamesInputKey];
  if (raw is! Map<Object?, Object?>) {
    return const <MediaReferenceKind, List<String>>{};
  }
  return <MediaReferenceKind, List<String>>{
    for (final kind in MediaReferenceKind.values)
      kind: switch (raw[kind.name]) {
        final List<Object?> values =>
          values.map((value) => value?.toString().trim() ?? '').toList(),
        _ => const <String>[],
      },
  };
}

PromptReferenceMention? parsePromptReferenceMention(String value) {
  final match = _mentionPattern.firstMatch(value.trim());
  if (match == null || match.start != 0 || match.end != value.trim().length) {
    return null;
  }
  final kindName = match.group(1)!.toLowerCase();
  final number = int.tryParse(match.group(2)!);
  if (number == null || number < 1) return null;
  final kind = MediaReferenceKind.values
      .where((candidate) => candidate.name == kindName)
      .firstOrNull;
  return kind == null
      ? null
      : PromptReferenceMention(kind: kind, number: number);
}

String translateReferencePrompt(
  String prompt, {
  required ReferencePromptDialect dialect,
  required Iterable<PromptReferenceMention> available,
}) {
  final matches = promptReferenceMatches(prompt, available: available);
  if (matches.isEmpty) return prompt;
  final result = StringBuffer();
  var offset = 0;
  for (final match in matches) {
    result.write(prompt.substring(offset, match.start));
    final mention = match.mention;
    result.write(switch (dialect) {
      ReferencePromptDialect.canonical => PromptReferenceMention(
        kind: mention.kind,
        number: mention.number,
      ).canonical,
      ReferencePromptDialect.compactAt =>
        '@${mention.kind.name}${mention.number}',
      ReferencePromptDialect.plainOrdinal =>
        '${mention.kind.name} ${mention.number}',
      ReferencePromptDialect.angleBracketUpper =>
        '<${mention.kind.name.toUpperCase()}_${mention.number}>',
    });
    offset = match.end;
  }
  result.write(prompt.substring(offset));
  return result.toString();
}

String renameReferenceInPrompt(
  String prompt, {
  required String oldName,
  required String newName,
}) {
  final cleanOld = oldName.trim();
  final cleanNew = newName.trim();
  if (cleanOld.isEmpty || cleanNew.isEmpty || cleanOld == cleanNew) {
    return prompt;
  }
  final ordinal = parsePromptReferenceMention('@$cleanOld');
  if (ordinal != null) {
    return prompt.replaceAllMapped(_mentionPattern, (match) {
      final candidate = parsePromptReferenceMention(match.group(0)!);
      return candidate?.normalized == ordinal.normalized
          ? '@$cleanNew'
          : match.group(0)!;
    });
  }
  final pattern = RegExp(
    '${RegExp.escape('@$cleanOld')}(?![A-Za-z0-9_])',
    caseSensitive: false,
  );
  return prompt.replaceAll(pattern, '@$cleanNew');
}

String detachReferenceFromPrompt(
  String prompt, {
  required MediaReferenceKind kind,
  required int number,
  required String label,
}) => prompt.replaceAllMapped(_mentionPattern, (match) {
  final mention = parsePromptReferenceMention(match.group(0)!);
  if (mention == null || mention.kind != kind) return match.group(0)!;
  if (mention.number == number) {
    final readableLabel = label.trim();
    return readableLabel.isEmpty
        ? 'removed ${kind.name} reference'
        : readableLabel;
  }
  if (mention.number > number) {
    return PromptReferenceMention(
      kind: kind,
      number: mention.number - 1,
    ).canonical;
  }
  return match.group(0)!;
});

/// Removes a promoted image from creative-reference numbering and leaves a
/// provider-neutral phrase in its place. The common "@Image 1 is the first
/// frame" wording is collapsed so the resulting motion prompt stays natural.
String promoteImageReferenceToFirstFrame(
  String prompt, {
  required int number,
  String? authoringName,
}) {
  const replacement = 'the supplied first frame';
  final detached = authoringName == null
      ? detachReferenceFromPrompt(
          prompt,
          kind: MediaReferenceKind.image,
          number: number,
          label: replacement,
        )
      : renameReferenceInPrompt(
          prompt,
          oldName: authoringName,
          newName: replacement,
        ).replaceAll('@$replacement', replacement);
  return detached.replaceAll(
    RegExp(
      r'\bthe supplied first frame\s+'
      r'(?:(?:is|as|for|should\s+be|must\s+be|use(?:d)?\s+as)\s+)'
      r'(?:the\s+)?(?:first|initial|opening|start(?:ing)?)\s+'
      r'(?:frame|image)\b',
      caseSensitive: false,
    ),
    replacement,
  );
}

ReferencePromptDialect artCraftReferencePromptDialect(String model) {
  if (model.startsWith('seedance_')) {
    return ReferencePromptDialect.compactAt;
  }
  if (model.startsWith('grok_imagine_video')) {
    return ReferencePromptDialect.angleBracketUpper;
  }
  if (model == 'minimax_h3') {
    return ReferencePromptDialect.plainOrdinal;
  }
  return ReferencePromptDialect.canonical;
}

ReferencePromptDialect atlasReferencePromptDialect(String model) =>
    model.startsWith('bytedance/seedance-')
    ? ReferencePromptDialect.compactAt
    : ReferencePromptDialect.canonical;
