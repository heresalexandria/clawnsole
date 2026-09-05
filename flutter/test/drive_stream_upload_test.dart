import 'dart:async';
import 'dart:convert';

import 'package:clawnsole/core/google_drive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('Drive upload streams bytes before the source has finished', () async {
    final receivedFirstMedia = Completer<void>();
    final releaseRest = Completer<void>();
    final observed = <int>[];
    late http.BaseRequest request;
    final client = MockClient.streaming((incoming, body) async {
      request = incoming;
      await for (final chunk in body) {
        observed.addAll(chunk);
        if (chunk.length == 2 &&
            chunk[0] == 1 &&
            !receivedFirstMedia.isCompleted) {
          receivedFirstMedia.complete();
        }
      }
      return http.StreamedResponse(
        Stream.value(
          utf8.encode(
            jsonEncode({
              'id': 'asset-id',
              'name': 'film.mp4',
              'mimeType': 'video/mp4',
              'size': '4',
            }),
          ),
        ),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    Stream<List<int>> media() async* {
      yield [1, 2];
      await releaseRest.future;
      yield [3, 4];
    }

    final upload = GoogleDriveApi(accessToken: 'test-token', client: client)
        .createFileStream(
          parentId: 'selected-folder',
          name: 'film.mp4',
          bytes: media(),
          length: 4,
          contentType: 'video/mp4',
        );
    await receivedFirstMedia.future.timeout(const Duration(seconds: 2));
    releaseRest.complete();
    final file = await upload;
    expect(file.size, 4);
    expect(request.contentLength, observed.length);
    expect(request.headers['Authorization'], 'Bearer test-token');
    expect(request.headers['Content-Type'], startsWith('multipart/related;'));
    expect(
      utf8.decode(observed, allowMalformed: true),
      contains('"parents":["selected-folder"]'),
    );
    expect(observed, containsAllInOrder([1, 2, 3, 4]));
  });

  test(
    'stalled upload aborts its HTTP request and source subscription',
    () async {
      var sourceCancelled = false;
      var requestAborted = false;
      final source = StreamController<List<int>>(
        onCancel: () {
          sourceCancelled = true;
        },
      );
      final client = _AbortAwareClient(() {
        requestAborted = true;
      });
      final upload = GoogleDriveApi(accessToken: 'test-token', client: client)
          .createFileStream(
            parentId: 'folder',
            name: 'film.mp4',
            bytes: source.stream,
            length: 4,
            contentType: 'video/mp4',
            timeout: const Duration(milliseconds: 30),
          );
      source.add([1, 2]);
      await expectLater(
        upload,
        throwsA(
          anyOf(isA<TimeoutException>(), isA<http.RequestAbortedException>()),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(requestAborted, isTrue);
      expect(sourceCancelled, isTrue);
      await source.close();
    },
  );
}

class _AbortAwareClient extends http.BaseClient {
  _AbortAwareClient(this.onAbort);
  final void Function() onAbort;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final complete = Completer<http.StreamedResponse>();
    final subscription = request.finalize().listen(
      (_) {},
      onError: (Object _) {},
    );
    unawaited(
      (request as http.Abortable).abortTrigger!.then((_) async {
        onAbort();
        await subscription.cancel();
        complete.completeError(http.RequestAbortedException(request.url));
      }),
    );
    return complete.future;
  }
}
