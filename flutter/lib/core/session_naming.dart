import 'package:characters/characters.dart';

import 'session_naming_platform_stub.dart'
    if (dart.library.io) 'session_naming_platform_native.dart'
    if (dart.library.js_interop) 'session_naming_platform_web.dart'
    as platform;

const int maxSessionNameCharacters = 48;
const int maxSessionNamingSourceCharacters = 2048;

/// Optional semantic refinement for the deterministic session name.
///
/// Implementations must stay local to the device and return null whenever the
/// platform model is unavailable. Callers deliberately treat this as
/// best-effort work after persisting [fallbackSessionName].
abstract interface class SessionNameGenerator {
  Future<String?> generate(String source);
}

/// Uses Apple Foundation Models where the installed platform exposes it.
///
/// iOS reaches the on-device model through a method channel. The Electron
/// renderer reaches the same model through its sandboxed native-shell bridge.
/// Android, Windows, older Apple OS versions, and ordinary web builds return
/// null and keep the deterministic fallback.
class PlatformSessionNameGenerator implements SessionNameGenerator {
  const PlatformSessionNameGenerator();

  @override
  Future<String?> generate(String source) async {
    final bounded = _truncateWithoutSplitting(
      source.trim(),
      maxSessionNamingSourceCharacters,
    );
    if (bounded.isEmpty) return null;
    try {
      final generated = await platform.generatePlatformSessionName(bounded);
      if (generated == null) return null;
      final clean = _cleanGeneratedName(generated);
      return clean.isEmpty ? null : clean;
    } on Object {
      // Automatic naming is decorative. Platform errors must never delay or
      // fail a generation after its deterministic session has been created.
      return null;
    }
  }
}

/// Produces a compact, deterministic title without network or model access.
///
/// Repeated meaningful terms win, then their original order is restored so a
/// long prompt still yields a readable phrase. Common prompt boilerplate and
/// reference markers are ignored. The result is safe for the existing
/// 48-code-unit library-folder contract and never splits a grapheme cluster.
String fallbackSessionName(String source, {String fallback = 'New session'}) {
  final cleaned = _cleanSource(source);
  final tokens = _wordPattern
      .allMatches(cleaned)
      .map((match) => match.group(0)!)
      .where((token) => token.length <= 40)
      .toList(growable: false);
  final meaningful = tokens
      .asMap()
      .entries
      .where((entry) => !_ignoredTerms.contains(entry.value.toLowerCase()))
      .toList(growable: false);

  final candidates = meaningful.isEmpty
      ? tokens.asMap().entries.toList(growable: false)
      : meaningful;
  final frequencies = <String, int>{};
  final first = <String, int>{};
  final original = <String, String>{};
  for (final entry in candidates) {
    final key = entry.value.toLowerCase();
    frequencies[key] = (frequencies[key] ?? 0) + 1;
    first.putIfAbsent(key, () => entry.key);
    original.putIfAbsent(key, () => entry.value);
  }
  final ranked = original.keys.toList()
    ..sort((a, b) {
      final byFrequency = frequencies[b]!.compareTo(frequencies[a]!);
      return byFrequency != 0 ? byFrequency : first[a]!.compareTo(first[b]!);
    });
  final selected = ranked.take(6).toList()
    ..sort((a, b) => first[a]!.compareTo(first[b]!));
  final title = selected
      .map((key) => _titleCaseToken(original[key]!))
      .join(' ');
  return _sanitizeName(title, fallback: fallback);
}

final RegExp _wordPattern = RegExp(
  r"[\p{L}\p{M}\p{N}]+(?:[-'’][\p{L}\p{M}\p{N}]+)*",
  unicode: true,
);
final RegExp _urlPattern = RegExp(r'(?:https?|data):\S+', caseSensitive: false);
final RegExp _referencePattern = RegExp(
  r'@\s*(?:image|video|audio)\s*\d+\b',
  caseSensitive: false,
);
final RegExp _controlPattern = RegExp(r'[\u0000-\u001f\u007f-\u009f]');
final RegExp _unsafeFolderPattern = RegExp(r'''[\\/:*?"<>|]''');
final RegExp _edgePunctuation = RegExp(
  r'''^[\s"'“”‘’.,;:!?…_\-–—]+|[\s"'“”‘’.,;:!?…_\-–—]+$''',
);

const Set<String> _ignoredTerms = <String>{
  'a',
  'an',
  'and',
  'animate',
  'animation',
  'are',
  'as',
  'at',
  'based',
  'be',
  'by',
  'can',
  'camera',
  'cinematic',
  'create',
  'creates',
  'creating',
  'could',
  'depict',
  'for',
  'follow',
  'following',
  'follows',
  'from',
  'generate',
  'generates',
  'generating',
  'high-quality',
  'i',
  'image',
  'in',
  'into',
  'is',
  'it',
  'just',
  'like',
  'look',
  'make',
  'me',
  'my',
  'of',
  'on',
  'or',
  'our',
  'please',
  'render',
  'scene',
  'show',
  'shot',
  'some',
  'something',
  'that',
  'the',
  'this',
  'tracking',
  'through',
  'to',
  'use',
  'used',
  'uses',
  'using',
  'video',
  'want',
  'we',
  'while',
  'would',
  'with',
  'you',
  'your',
};

String _cleanSource(String source) => source
    .replaceAll(_urlPattern, ' ')
    .replaceAll(_referencePattern, ' ')
    .replaceAll('@', ' ')
    .replaceAll(_controlPattern, ' ')
    .replaceAll(_unsafeFolderPattern, ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String _cleanGeneratedName(String source) {
  String? firstLine;
  for (final line in source.split(RegExp(r'[\r\n]+'))) {
    if (line.trim().isNotEmpty) {
      firstLine = line.trim();
      break;
    }
  }
  if (firstLine == null || _urlPattern.hasMatch(firstLine)) return '';
  final withoutLabel = firstLine.replaceFirst(
    RegExp(r'^(?:session\s+)?title\s*:\s*', caseSensitive: false),
    '',
  );
  return _sanitizeName(withoutLabel, fallback: '');
}

String _sanitizeName(String source, {required String fallback}) {
  var clean = source
      .replaceAll(_controlPattern, ' ')
      .replaceAll(_unsafeFolderPattern, ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(_edgePunctuation, '')
      .trim();
  clean = _truncateWithoutSplitting(
    clean,
    maxSessionNameCharacters,
  ).replaceAll(_edgePunctuation, '').trimRight();
  if (clean.isNotEmpty) return clean;

  final safeFallback = fallback
      .replaceAll(_controlPattern, ' ')
      .replaceAll(_unsafeFolderPattern, ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(_edgePunctuation, '')
      .trim();
  return _truncateWithoutSplitting(
    safeFallback.isEmpty ? 'New session' : safeFallback,
    maxSessionNameCharacters,
  );
}

String _titleCaseToken(String token) {
  if (token.isEmpty || token.toUpperCase() == token) return token;
  // Preserve intentional mixed casing such as iPhone, eBike, or FLUX3.
  if (token.substring(1).contains(RegExp(r'[A-Z]'))) return token;
  return token
      .split('-')
      .map((part) {
        if (part.isEmpty) return part;
        final characters = part.characters;
        return '${characters.first.toUpperCase()}${characters.skip(1).join()}';
      })
      .join('-');
}

String _truncateWithoutSplitting(String source, int maximumCodeUnits) {
  if (source.length <= maximumCodeUnits) return source;
  final output = StringBuffer();
  var length = 0;
  for (final character in source.characters) {
    if (length + character.length > maximumCodeUnits) break;
    output.write(character);
    length += character.length;
  }
  return output.toString().trimRight();
}
