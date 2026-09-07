import 'dart:convert';
import 'dart:async';

import 'package:clawnsole/core/media_content_policy.dart';
import 'package:clawnsole/core/bfl_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('media types reject active documents and preserve passive formats', () {
    for (final mime in <String>[
      'text/html',
      'image/svg+xml',
      'application/xml',
      'text/xml',
      'application/javascript',
      'application/pdf',
    ]) {
      expect(
        () => passiveMediaContentType(mime),
        throwsA(isA<ProviderException>()),
      );
    }
    expect(passiveMediaContentType('Video/MP4; codec=avc1'), 'video/mp4');
    expect(passiveMediaContentType('image/png'), 'image/png');
    expect(passiveMediaContentType(null), 'application/octet-stream');
  });

  test('mislabeled documents are rejected across split chunks', () async {
    for (final text in <String>[
      '\ufeff  <!DOCTYPE html><html>',
      '<?xml version="1.0"?><svg/>',
      '<svg onload="x()"/>',
    ]) {
      final bytes = utf8.encode(text);
      final stream = Stream<List<int>>.fromIterable(
        bytes.map((byte) => <int>[byte]),
      );
      expect(
        validatedPassiveMediaStream(stream),
        throwsA(isA<ProviderException>()),
      );
    }
  });

  test('a stalled media prefix times out and cancels the upstream', () async {
    var cancelled = false;
    final controller = StreamController<List<int>>(
      onCancel: () {
        cancelled = true;
      },
    );
    await expectLater(
      validatedPassiveMediaStream(
        controller.stream,
        idleTimeout: const Duration(milliseconds: 10),
        totalTimeout: const Duration(milliseconds: 30),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(cancelled, isTrue);
    await controller.close();
  });

  test(
    'prefix inspection keeps bytes and does not buffer the full result',
    () async {
      var delivered = 0;
      Stream<List<int>> input() async* {
        for (var index = 0; index < 100; index++) {
          delivered++;
          yield List<int>.filled(128, index);
        }
      }

      final validated = await validatedPassiveMediaStream(input());
      expect(delivered, 4);
      final chunks = await validated.toList();
      expect(
        chunks.expand((chunk) => chunk),
        List<int>.generate(12800, (index) => index ~/ 128),
      );
    },
  );

  test(
    'abandoned playback releases a source waiting after its prefix',
    () async {
      var cancelled = false;
      final source = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      source.add(List.filled(passiveMediaSniffBytes, 42));
      final validated = await validatedPassiveMediaStream(source.stream);
      final received = Completer<void>();
      final subscription = validated.listen((_) => received.complete());
      await received.future;
      // Let the generator begin waiting for a tail that never arrives.
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel().timeout(const Duration(seconds: 2));
      expect(cancelled, isTrue);
      await source.close();
    },
  );
}
