import 'package:flutter/services.dart';

import 'models.dart';
import 'provider_catalog.dart';

/// Posts local "your film is ready" alerts through the platform shell.
///
/// The iOS shell shows an alert only while the app is not in the foreground —
/// an active app already displays the finished generation — and only after
/// the user granted permission. Shells without a handler make every call a
/// no-op that answers false.
abstract interface class GenerationNotifier {
  /// Asks for permission when the system has no recorded answer yet (so the
  /// user is prompted at most once) and reports whether alerts may be posted.
  Future<bool> requestPermission();

  /// Posts an alert immediately and reports whether it was shown. A later
  /// post with the same [threadId] replaces the earlier alert instead of
  /// stacking a duplicate.
  Future<bool> notify({
    required String title,
    required String body,
    String? threadId,
  });
}

class MethodChannelGenerationNotifier implements GenerationNotifier {
  MethodChannelGenerationNotifier();

  static const MethodChannel _channel = MethodChannel(
    'ai.clawnsole/notifications',
  );

  bool _unsupported = false;

  @override
  Future<bool> requestPermission() => _invoke('requestPermission');

  @override
  Future<bool> notify({
    required String title,
    required String body,
    String? threadId,
  }) => _invoke('notify', <String, Object?>{
    'title': title,
    'body': body,
    if (threadId != null) 'threadId': threadId,
  });

  Future<bool> _invoke(String method, [Map<String, Object?>? arguments]) async {
    if (_unsupported) return false;
    try {
      return await _channel.invokeMethod<bool>(method, arguments) ?? false;
    } on MissingPluginException {
      _unsupported = true;
      return false;
    } on PlatformException {
      // An alert is a courtesy, never a product failure.
      return false;
    }
  }
}

/// The alert text for a finished generation.
class GenerationReadyNotice {
  const GenerationReadyNotice({required this.title, required this.body});

  final String title;
  final String body;
}

/// A fixed title plus the prompt's opening and the provider that made it.
GenerationReadyNotice generationReadyNotice(Generation item) {
  final excerpt = promptExcerpt(item.prompt);
  final provider = providerNameForHistory(item.provider);
  return GenerationReadyNotice(
    title: item.isImage ? 'Your image is ready' : 'Your film is ready',
    body: excerpt.isEmpty ? provider : '$excerpt · $provider',
  );
}

/// The prompt's first [maxLength] characters on one line, with an ellipsis
/// when it was cut. Counts code points so an emoji is never split.
String promptExcerpt(String prompt, {int maxLength = 80}) {
  final collapsed = prompt.replaceAll(RegExp(r'\s+'), ' ').trim();
  final runes = collapsed.runes;
  if (runes.length <= maxLength) return collapsed;
  return '${String.fromCharCodes(runes.take(maxLength)).trimRight()}…';
}
