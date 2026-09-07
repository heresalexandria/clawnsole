import 'dart:async';
import 'dart:convert';

import 'bfl_api.dart';

/// Media comes from providers and user-selected files, never from trusted app
/// code. In particular SVG is a document format even though its MIME is image/*.
String passiveMediaContentType(String? raw) {
  final type = raw?.split(';').first.trim().toLowerCase() ?? '';
  if (type.isEmpty || type == 'application/octet-stream') {
    return 'application/octet-stream';
  }
  const allowed = <String>{
    'video/mp4',
    'video/mpeg',
    'video/quicktime',
    'video/webm',
    'video/x-m4v',
    'video/x-msvideo',
    'video/ogg',
    'audio/mpeg',
    'audio/mp4',
    'audio/wav',
    'audio/x-wav',
    'audio/wave',
    'audio/aac',
    'audio/ogg',
    'audio/webm',
    'audio/flac',
    'audio/x-flac',
    'image/png',
    'image/jpeg',
    'image/jpg',
    'image/webp',
    'image/gif',
    'image/avif',
    'image/heic',
    'image/heif',
    'image/bmp',
    'image/tiff',
  };
  if (!allowed.contains(type)) {
    throw const ProviderException(
      'The download is not a supported image, audio, or video file.',
      status: 415,
    );
  }
  return type;
}

const passiveMediaSniffBytes = 512;

/// Additional defense against a server claiming video/mp4 for an active HTML,
/// SVG or XML document. This is not a codec validator: browser media decoders
/// remain responsible for recognizing the supported passive file formats.
void validatePassiveMediaPrefix(List<int> bytes) {
  final prefix = utf8
      .decode(bytes.take(passiveMediaSniffBytes).toList(), allowMalformed: true)
      .replaceAll('\u0000', '')
      .replaceFirst('\ufeff', '')
      .trimLeft()
      .toLowerCase();
  if (prefix.startsWith('<')) {
    throw const ProviderException(
      'The download contains an active document instead of media.',
      status: 415,
    );
  }
}

/// Preflights only a bounded prefix and returns a one-shot stream which keeps
/// every byte. Cancelling or rejecting also releases the upstream subscription.
Future<Stream<List<int>>> validatedPassiveMediaStream(
  Stream<List<int>> input, {
  Duration idleTimeout = const Duration(seconds: 30),
  Duration totalTimeout = const Duration(minutes: 8),
}) async {
  final iterator = StreamIterator<List<int>>(input);
  final initial = <List<int>>[];
  final prefix = <int>[];
  final clock = Stopwatch()..start();
  Future<bool> next() {
    final remaining = totalTimeout - clock.elapsed;
    if (remaining <= Duration.zero) {
      throw TimeoutException('The media preflight exceeded its deadline.');
    }
    return iterator.moveNext().timeout(
      remaining < idleTimeout ? remaining : idleTimeout,
    );
  }

  try {
    while (prefix.length < passiveMediaSniffBytes && await next()) {
      final chunk = iterator.current;
      if (chunk.isEmpty) continue;
      initial.add(chunk);
      prefix.addAll(chunk.take(passiveMediaSniffBytes - prefix.length));
    }
    validatePassiveMediaPrefix(prefix);
  } on Object {
    await iterator.cancel();
    rethrow;
  }
  final body = () async* {
    try {
      for (final chunk in initial) {
        yield chunk;
      }
      while (await iterator.moveNext()) {
        yield iterator.current;
      }
    } finally {
      await iterator.cancel();
    }
  }();
  // An async* generator cannot reach its finally block while moveNext is
  // waiting on a stalled source. Release that iterator directly on consumer
  // cancellation, then tear down the forwarding subscription. This also
  // applies to an HTTP player that abandons a download mid-stream.
  late final StreamController<List<int>> output;
  late StreamSubscription<List<int>> subscription;
  output = StreamController<List<int>>(
    onListen: () {
      subscription = body.listen(
        output.add,
        onError: output.addError,
        onDone: output.close,
      );
    },
    onPause: () => subscription.pause(),
    onResume: () => subscription.resume(),
    onCancel: () async {
      await iterator.cancel();
      await subscription.cancel();
    },
  );
  return output.stream;
}
