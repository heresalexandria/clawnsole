import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clawnsole/core/bfl_api.dart';
import 'package:clawnsole/core/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../tool/clawnsole_companion.dart';

void main() {
  test(
    'remote media keeps ranges and sandbox headers while rejecting active documents',
    () async {
      var type = 'video/mp4';
      var content = <int>[0x3c, 1, 2, 3, 4, 5];
      String? forwardedRange;
      final harness = await _Harness.create(
        media: (request) async {
          forwardedRange = request.headers['range'];
          return http.StreamedResponse(
            Stream.value(content),
            forwardedRange == null ? 200 : 206,
            contentLength: content.length,
            headers: {
              'content-type': type,
              'content-range': 'bytes 2-7/8',
              'accept-ranges': 'bytes',
              'set-cookie': 'provider-cookie=private',
            },
          );
        },
      );
      addTearDown(harness.close);
      final path =
          '/media?url=${Uri.encodeQueryComponent('https://media.example/clip.mp4')}';
      final ranged = await http.get(
        harness.base.resolve(path),
        headers: {'Range': 'bytes=2-7'},
      );
      expect(ranged.statusCode, 206);
      expect(forwardedRange, 'bytes=2-7');
      expect(ranged.bodyBytes, content);
      expect(ranged.headers['content-range'], 'bytes 2-7/8');
      expect(ranged.headers['x-content-type-options'], 'nosniff');
      expect(
        ranged.headers['content-security-policy'],
        contains("sandbox; default-src 'none'"),
      );
      expect(ranged.headers['set-cookie'], isNull);
      for (final active in ['text/html', 'image/svg+xml', 'application/xml']) {
        type = active;
        final rejected = await http.get(harness.base.resolve(path));
        expect(rejected.statusCode, 415, reason: active);
      }
      type = 'video/mp4';
      content = utf8.encode(
        '  <!doctype html><script>window.clawnsole</script>',
      );
      final mislabeled = await http.get(harness.base.resolve(path));
      expect(mislabeled.statusCode, 415);
      expect(mislabeled.body, isNot(contains('<script>')));
    },
  );

  test(
    'retained media rejects active bytes and supports local file ranges',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.close);
      final bad = await harness.store.writeAsset(
        Uint8List.fromList(utf8.encode('<svg onload="x()"/>')),
        label: 'clip.mp4',
        contentType: 'video/mp4',
      );
      final good = await harness.store.writeAsset(
        Uint8List.fromList([0, 1, 2, 3, 4, 5]),
        label: 'clip.mp4',
        contentType: 'video/mp4',
      );
      await harness.store.write(
        StoredData(
          generations: [
            _film('bad').copyWith(resultAsset: bad),
            _film('good').copyWith(resultAsset: good),
          ],
        ),
      );
      for (final route in ['/assets', '/asset-cache']) {
        expect(
          (await http.get(
            harness.base.resolve('$route?id=${bad.value}'),
          )).statusCode,
          415,
        );
        final seek = await http.get(
          harness.base.resolve('$route?id=${good.value}'),
          headers: {'Range': 'bytes=2-4'},
        );
        expect(seek.statusCode, 206);
        expect(seek.bodyBytes, [2, 3, 4]);
        expect(seek.headers['content-range'], 'bytes 2-4/6');
        expect(seek.headers['x-content-type-options'], 'nosniff');
      }
    },
  );

  test(
    'status-only persists ready receipts without downloading and retention streams a large result once',
    () async {
      var transfers = 0;
      var providerPosts = 0;
      const size = 10 * 1024 * 1024;
      final harness = await _Harness.create(
        provider: (request) async {
          if (request.method == 'POST') providerPosts++;
          return http.Response(
            jsonEncode(
              request.url.path.contains('credits')
                  ? {'credits': 10}
                  : {
                      'status': 'Ready',
                      'result': {'sample': 'https://media.example/film'},
                    },
            ),
            200,
          );
        },
        media: (_) async {
          transfers++;
          return http.StreamedResponse(
            Stream<List<int>>.fromIterable(
              List.generate(160, (_) => List<int>.filled(64 * 1024, 42)),
            ),
            200,
            contentLength: size,
            headers: {'content-type': 'video/mp4'},
          );
        },
      );
      addTearDown(harness.close);
      await harness.store.write(
        StoredData(
          generations: [
            _film(
              'one',
              status: 'Pending',
            ).copyWith(resultRetentionFailures: 3),
          ],
        ),
      );
      final polled = await harness.post('/generations/status', {
        'localId': 'one',
        'pollingUrl': 'https://api.bfl.ai/v1/get_result?id=one',
        'statusOnly': true,
      });
      expect(polled.statusCode, 200);
      final receipt = (await harness.store.read()).generations.single;
      expect(receipt.status, 'Ready');
      expect(receipt.resultUrl, 'https://media.example/film');
      expect(receipt.resultAsset, isNull);
      expect(receipt.resultRetentionFailures, 3);
      expect(receipt.lastResultRetentionAttemptAt, isNull);
      expect(transfers, 0);
      expect(
        (await harness.post('/generations/retain', {
          'localId': 'one',
        })).statusCode,
        200,
      );
      final saved = (await harness.store.read()).generations.single;
      expect(saved.resultAsset?.bytes, size);
      expect(saved.resultAsset?.sha256, hasLength(64));
      expect(
        (await harness.store.resolveAssetFile(saved.resultAsset!)).lengthSync(),
        size,
      );
      expect(saved.resultRetentionFailures, 0);
      await harness.post('/generations/retain', {'localId': 'one'});
      expect(transfers, 1);
      expect(providerPosts, 0);
    },
  );

  test(
    'concurrent retains deduplicate each film and preserve other records and edits',
    () async {
      final release = Completer<void>();
      final entered = Completer<void>();
      var transfers = 0;
      final harness = await _Harness.create(
        media: (_) async {
          transfers++;
          if (transfers == 2) entered.complete();
          Stream<List<int>> stream() async* {
            yield List.filled(512, 1);
            await release.future;
            yield List.filled(512, 2);
          }

          return http.StreamedResponse(
            stream(),
            200,
            contentLength: 1024,
            headers: {'content-type': 'video/mp4'},
          );
        },
      );
      addTearDown(harness.close);
      await harness.store.write(
        StoredData(generations: [_film('one'), _film('two')]),
      );
      final requests = [
        harness.post('/generations/retain', {'localId': 'one'}),
        harness.post('/generations/retain', {'localId': 'one'}),
        harness.post('/generations/retain', {'localId': 'two'}),
      ];
      await entered.future.timeout(const Duration(seconds: 5));
      final old = await harness.store.read();
      await harness.store.write(
        old.copyWith(
          generations: old.generations
              .map((film) => film.copyWith(favorite: true))
              .toList(),
        ),
      );
      release.complete();
      expect(
        (await Future.wait(requests)).map((response) => response.statusCode),
        everyElement(200),
      );
      expect(transfers, 2);
      final films = (await harness.store.read()).generations;
      expect(films, hasLength(2));
      expect(
        films.every((film) => film.resultAsset != null && film.favorite),
        isTrue,
      );
    },
  );

  test(
    'truncated retained downloads leave no published or partial asset',
    () async {
      final harness = await _Harness.create(
        media: (_) async => http.StreamedResponse(
          Stream.value(List<int>.filled(600, 1)),
          200,
          contentLength: 1000,
          headers: {'content-type': 'video/mp4'},
        ),
      );
      addTearDown(harness.close);
      await harness.store.write(StoredData(generations: [_film('one')]));
      expect(
        (await harness.post('/generations/retain', {
          'localId': 'one',
        })).statusCode,
        200,
      );
      final saved = (await harness.store.read()).generations.single;
      expect(saved.resultAsset, isNull);
      expect(saved.resultRetentionFailures, 1);
      expect(saved.resultRetentionError, contains('truncated'));
      expect(await harness.store.assets.list().toList(), isEmpty);
    },
  );

  test(
    'status-only failures keep retention history and never rescue-download',
    () async {
      var downloads = 0;
      final harness = await _Harness.create(
        provider: (_) async =>
            http.Response('{"error":"temporarily unavailable"}', 503),
        media: (_) async {
          downloads++;
          return http.StreamedResponse(Stream.value([1, 2, 3]), 200);
        },
      );
      addTearDown(harness.close);
      final prior = _film('one').copyWith(
        resultRetentionFailures: 4,
        resultRetentionError: 'Earlier transfer failed',
        lastResultRetentionAttemptAt: DateTime.utc(2026, 9, 4),
      );
      await harness.store.write(StoredData(generations: [prior]));
      final response = await harness.post('/generations/status', {
        'localId': 'one',
        'pollingUrl': prior.pollingUrl,
        'statusOnly': true,
      });
      expect(response.statusCode, 200);
      final saved = (await harness.store.read()).generations.single;
      expect(downloads, 0);
      expect(saved.resultRetentionFailures, 4);
      expect(saved.resultRetentionError, 'Earlier transfer failed');
      expect(
        saved.lastResultRetentionAttemptAt,
        prior.lastResultRetentionAttemptAt,
      );
      expect(saved.consecutiveCheckFailures, 1);
    },
  );

  test('deleting a film during a transfer never resurrects it', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final harness = await _Harness.create(
      media: (_) async {
        Stream<List<int>> stream() async* {
          yield List.filled(512, 1);
          entered.complete();
          await release.future;
          yield List.filled(512, 2);
        }

        return http.StreamedResponse(
          stream(),
          200,
          contentLength: 1024,
          headers: {'content-type': 'video/mp4'},
        );
      },
    );
    addTearDown(harness.close);
    await harness.store.write(StoredData(generations: [_film('one')]));
    final pending = harness.post('/generations/retain', {'localId': 'one'});
    await entered.future.timeout(const Duration(seconds: 5));
    expect(
      (await http.delete(
        harness.base.resolve('/generations?id=one'),
      )).statusCode,
      200,
    );
    release.complete();
    expect((await pending).statusCode, 404);
    expect((await harness.store.read()).generations, isEmpty);
  });

  test(
    'pruning protects pending stream and byte publications through metadata commit',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.close);
      final streamed = await harness.store.writeAssetStream(
        Stream.value([1, 2, 3]),
        label: 'stream.mp4',
        contentType: 'video/mp4',
        expectedLength: 3,
      );
      final bytes = await harness.store.writeAsset(
        Uint8List.fromList([4, 5, 6]),
        label: 'bytes.mp4',
        contentType: 'video/mp4',
      );
      await harness.store.pruneAssets([]);
      expect(await harness.store.readAsset(streamed), [1, 2, 3]);
      expect(await harness.store.readAsset(bytes), [4, 5, 6]);
      final committed = StoredData(
        generations: [
          _film('stream').copyWith(resultAsset: streamed),
          _film('bytes').copyWith(resultAsset: bytes),
        ],
      );
      // The prune caller's roots are stale, but the committed roots are current.
      await Future.wait([
        harness.store.write(committed),
        harness.store.pruneAssets([]),
      ]);
      expect(await harness.store.readAsset(streamed), [1, 2, 3]);
      expect(await harness.store.readAsset(bytes), [4, 5, 6]);
      await harness.store.write(const StoredData());
      await harness.store.pruneAssets([]);
      expect(await harness.store.assets.list().toList(), isEmpty);
    },
  );

  test('metadata JSON bodies enforce size bounds before parsing', () async {
    final harness = await _Harness.create();
    addTearDown(harness.close);
    final response = await http.post(
      harness.base.resolve('/generations/status'),
      body: 'x' * (2 * 1024 * 1024 + 1),
    );
    expect(response.statusCode, 413);
    expect(response.body, contains('too large'));
  });
}

Generation _film(String id, {String status = 'Ready'}) => Generation(
  localId: id,
  status: status,
  prompt: 'Synthetic fixture',
  mode: VideoMode.t2v,
  config: const GenerationConfig(
    aspectRatio: '16:9',
    duration: 8,
    resolution: 'hd',
    generateAudio: true,
    safetyTolerance: 2,
    draft: false,
  ),
  createdAt: DateTime.utc(2026, 9, 5),
  updatedAt: DateTime.utc(2026, 9, 5),
  pollingUrl: 'https://api.bfl.ai/v1/get_result?id=$id',
  resultUrl: status == 'Ready' ? 'https://media.example/$id' : null,
);

class _Harness {
  _Harness(this.root, this.store, this.server, this.subscription);
  final Directory root;
  final CompanionStore store;
  final HttpServer server;
  final StreamSubscription<HttpRequest> subscription;
  Uri get base => Uri.parse('http://127.0.0.1:${server.port}');
  static Future<_Harness> create({
    Future<http.StreamedResponse> Function(http.BaseRequest)? media,
    Future<http.Response> Function(http.Request)? provider,
  }) async {
    final root = await Directory.systemTemp.createTemp(
      'clawnsole-media-safety.',
    );
    final store = CompanionStore(File('${root.path}/data.json'));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final app = CompanionApp(
      store: store,
      api: BflApi(
        client: MockClient(
          provider ?? (_) async => http.Response('{"credits":10}', 200),
        ),
      ),
      fallbackApiKeys: const {'bfl': 'synthetic-key'},
      mediaClientFactory: () => _StreamClient(
        media ??
            (_) async => http.StreamedResponse(
              Stream.value([0, 1, 2]),
              200,
              headers: {'content-type': 'video/mp4'},
            ),
      ),
    );
    return _Harness(root, store, server, server.listen(app.handle));
  }

  Future<http.Response> post(String path, Map<String, Object?> value) =>
      http.post(
        base.resolve(path),
        headers: {'content-type': 'application/json'},
        body: jsonEncode(value),
      );
  Future<void> close() async {
    await subscription.cancel();
    await server.close(force: true);
    await root.delete(recursive: true);
  }
}

class _StreamClient extends http.BaseClient {
  _StreamClient(this.respond);
  final Future<http.StreamedResponse> Function(http.BaseRequest) respond;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      respond(request);
}
