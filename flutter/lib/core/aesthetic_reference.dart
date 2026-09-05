/// Text-only creative direction. Deliberately separate from media references.
class AestheticReference {
  const AestheticReference({
    required this.id,
    required this.title,
    required this.text,
    required this.updatedAt,
    this.icon = 'sparkles',
    this.color = 0xffaf853c,
  });
  final String id;
  final String title;
  final String text;
  final String icon;
  final int color;
  final DateTime updatedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'text': text,
    'icon': icon,
    'color': color,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
  factory AestheticReference.fromJson(Map<String, Object?> json) =>
      AestheticReference(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        text: json['text'] as String? ?? '',
        icon: json['icon'] as String? ?? 'sparkles',
        color: (json['color'] as num?)?.toInt() ?? 0xffaf853c,
        updatedAt:
            DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.utc(1970),
      );
}

String appendAestheticPrompt(String prompt, AestheticReference? aesthetic) => [
  prompt.trim(),
  if (aesthetic != null) aesthetic.text.trim(),
].where((text) => text.isNotEmpty).join('\n\n');
