import 'models.dart';

/// The stable, provider-neutral reference name shown in Clawnsole prompts.
class PromptReferenceMention {
  const PromptReferenceMention({required this.kind, required this.number});

  final MediaReferenceKind kind;
  final int number;

  String get canonical => '@${kind.label} $number';

  String get normalized => '${kind.name}$number';
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

Iterable<RegExpMatch> promptReferenceMatches(String value) =>
    _mentionPattern.allMatches(value);

List<PromptReferenceMention> promptReferenceMentions(
  Iterable<MediaReferenceKind> kinds,
) {
  final counts = <MediaReferenceKind, int>{};
  return kinds.map((kind) {
    final number = (counts[kind] ?? 0) + 1;
    counts[kind] = number;
    return PromptReferenceMention(kind: kind, number: number);
  }).toList();
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
  final attached = available.map((mention) => mention.normalized).toSet();
  return prompt.replaceAllMapped(_mentionPattern, (match) {
    final mention = parsePromptReferenceMention(match.group(0)!);
    if (mention == null || !attached.contains(mention.normalized)) {
      return match.group(0)!;
    }
    return switch (dialect) {
      ReferencePromptDialect.canonical => mention.canonical,
      ReferencePromptDialect.compactAt =>
        '@${mention.kind.name}${mention.number}',
      ReferencePromptDialect.plainOrdinal =>
        '${mention.kind.name} ${mention.number}',
      ReferencePromptDialect.angleBracketUpper =>
        '<${mention.kind.name.toUpperCase()}_${mention.number}>',
    };
  });
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
