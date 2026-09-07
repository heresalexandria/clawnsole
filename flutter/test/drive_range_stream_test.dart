import 'dart:async';

import 'package:clawnsole/core/google_drive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  for (final honorsRange in [true, false]) {
    test(
      'Drive range streams and stops upstream when Range is ${honorsRange ? 'honored' : 'ignored'}',
      () async {
        final source = StreamController<List<int>>();
        var cancelled = false;
        source.onCancel = () => cancelled = true;
        final client = _RangeClient(
          (request) => http.StreamedResponse(
            source.stream,
            honorsRange ? 206 : 200,
            contentLength: honorsRange ? 4 : 100,
          ),
        );
        final api = GoogleDriveApi(accessToken: 'test-token', client: client);
        final download = await api.readFileRangeStream('film-id', 3, 6);
        expect(client.request.headers['Range'], 'bytes=3-6');
        expect(client.request.headers['Authorization'], 'Bearer test-token');
        expect(download.contentLength, 4);
        final iterator = StreamIterator(download.stream);
        if (!honorsRange) source.add([0, 1, 2]);
        source.add([3, 4]);
        expect(
          await iterator.moveNext().timeout(const Duration(seconds: 2)),
          isTrue,
        );
        expect(iterator.current, [3, 4]);
        // Delivery has begun even though the source has not finished. A
        // server ignoring Range is cut off as soon as the window is complete.
        source.add(honorsRange ? [5, 6] : [5, 6, 7, 8]);
        expect(await iterator.moveNext(), isTrue);
        expect(iterator.current, [5, 6]);
        expect(await iterator.moveNext(), isFalse);
        expect(cancelled, isTrue);
        await source.close();
      },
    );
  }

  test('abandoned Drive range cancels its upstream subscription', () async {
    var cancelled = false;
    final source = StreamController<List<int>>(
      onCancel: () => cancelled = true,
    );
    final api = GoogleDriveApi(
      accessToken: 'test-token',
      client: _RangeClient((_) => http.StreamedResponse(source.stream, 206)),
    );
    final download = await api.readFileRangeStream('film-id', 1, 1000000000);
    final iterator = StreamIterator(download.stream);
    source.add([1, 2]);
    expect(await iterator.moveNext(), isTrue);
    final waiting = iterator.moveNext();
    await Future<void>.delayed(Duration.zero);
    await iterator.cancel().timeout(const Duration(seconds: 2));
    expect(await waiting, isFalse);
    expect(cancelled, isTrue);
    await source.close();
  });
}

class _RangeClient extends http.BaseClient {
  _RangeClient(this.respond);
  final http.StreamedResponse Function(http.BaseRequest) respond;
  late http.BaseRequest request;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    this.request = request;
    return respond(request);
  }
}
