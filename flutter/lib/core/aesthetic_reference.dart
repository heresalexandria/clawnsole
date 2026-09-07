/// Text-only creative direction. Deliberately separate from media references.
class AestheticReference {
  AestheticReference({
    required this.id,
    required this.title,
    required this.text,
    required this.updatedAt,
    this.icon = 'sparkles',
    this.color = 0xffaf853c,
    List<String> tags = const <String>[],
    this.favorite = false,
  }) : tags = normalizeAestheticTags(tags);
  final String id;
  final String title;
  final String text;
  final String icon;
  final int color;

  /// Free-form labels for filtering ("noir", "1970s", "handheld"). Kept in
  /// entry order, trimmed, de-duplicated case-insensitively.
  final List<String> tags;

  /// Starred aesthetics list first wherever aesthetics are chosen.
  final bool favorite;
  final DateTime updatedAt;

  AestheticReference copyWith({
    String? id,
    String? title,
    String? text,
    String? icon,
    int? color,
    List<String>? tags,
    bool? favorite,
    DateTime? updatedAt,
  }) => AestheticReference(
    id: id ?? this.id,
    title: title ?? this.title,
    text: text ?? this.text,
    icon: icon ?? this.icon,
    color: color ?? this.color,
    tags: tags ?? this.tags,
    favorite: favorite ?? this.favorite,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  bool hasTag(String tag) {
    final needle = tag.trim().toLowerCase();
    return tags.any((item) => item.toLowerCase() == needle);
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'text': text,
    'icon': icon,
    'color': color,
    if (tags.isNotEmpty) 'tags': tags,
    if (favorite) 'favorite': true,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
  factory AestheticReference.fromJson(Map<String, Object?> json) =>
      AestheticReference(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        text: json['text'] as String? ?? '',
        icon: json['icon'] as String? ?? 'sparkles',
        color: (json['color'] as num?)?.toInt() ?? 0xffaf853c,
        tags: (json['tags'] as List<Object?>? ?? const <Object?>[])
            .whereType<String>()
            .toList(),
        favorite: json['favorite'] == true,
        updatedAt:
            DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.utc(1970),
      );
}

/// The longest tag an aesthetic keeps; longer entries are trimmed.
const int aestheticTagMaxLength = 40;

/// Trims, drops blanks, caps length, and removes case-insensitive repeats
/// while keeping the first spelling and the entry order.
List<String> normalizeAestheticTags(Iterable<String> tags) {
  final seen = <String>{};
  final result = <String>[];
  for (final raw in tags) {
    var tag = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (tag.startsWith('#')) tag = tag.substring(1).trim();
    if (tag.isEmpty) continue;
    if (tag.length > aestheticTagMaxLength) {
      tag = tag.substring(0, aestheticTagMaxLength).trimRight();
    }
    if (seen.add(tag.toLowerCase())) result.add(tag);
  }
  return List<String>.unmodifiable(result);
}

/// Splits a typed tag line ("noir, 1970s; handheld") into normalized tags.
List<String> parseAestheticTags(String value) =>
    normalizeAestheticTags(value.split(RegExp(r'[,;\n]')));

String appendAestheticPrompt(String prompt, AestheticReference? aesthetic) =>
    appendAestheticText(prompt, aesthetic?.text);

/// The same join for a definition that no longer belongs to any saved
/// aesthetic — a "Custom" definition edited in the composer, or the text a
/// film was rendered with after its aesthetic changed.
String appendAestheticText(String prompt, String? aesthetic) => [
  prompt.trim(),
  if (aesthetic != null) aesthetic.trim(),
].where((text) => text.isNotEmpty).join('\n\n');

/// Removes the aesthetic block [aesthetic] appended to [prompt] at
/// submission, leaving the direction (and its casting block) as it was
/// typed. Returns [prompt] unchanged when the block is not there.
String stripAestheticText(String prompt, String? aesthetic) {
  final block = aesthetic?.trim() ?? '';
  if (block.isEmpty) return prompt;
  final trimmed = prompt.trimRight();
  if (!trimmed.endsWith(block)) return prompt;
  return trimmed.substring(0, trimmed.length - block.length).trimRight();
}

/// The last paragraph of [prompt], used to recognize the aesthetic block on
/// films rendered before the aesthetic was recorded alongside the prompt.
String trailingPromptParagraph(String prompt) {
  final blocks = prompt.trim().split(RegExp(r'\n\s*\n'));
  return blocks.isEmpty ? '' : blocks.last.trim();
}
