import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:clawnsole/core/bfl_api.dart';
import 'package:clawnsole/core/google_drive.dart';
import 'package:clawnsole/core/google_drive_store.dart';
import 'package:clawnsole/core/hybrid_data_store.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/video_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../tool/clawnsole_companion.dart';

void main() {
  for (final mode in ['cold seek', 'uncached seek', 'uncached full']) {
    test('$mode delivers bytes before the full video arrives', () async {
      final directory = await Directory.systemTemp.createTemp(
        'clawnsole-playback-stream-',
      );
      final source = StreamController<List<int>>();
      final released = Completer<void>();
      source.onCancel = () {
        if (!released.isCompleted) released.complete();
      };
      final store = _StreamingStore(directory, source.stream, mode);
      final cache = mode == 'cold seek'
          ? VideoCache(
              directory: () async => Directory('${directory.path}/cache'),
            )
          : null;
      final application = CompanionApp.hybrid(
        store: store,
        api: BflApi(),
        videoCache: cache,
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen(application.handle);
      final client = http.Client();
      try {
        final request = http.Request(
          'GET',
          Uri.parse(
            'http://127.0.0.1:${server.port}/assets?id=drive-stream-film',
          ),
        );
        if (mode != 'uncached full') request.headers['Range'] = 'bytes=1-';
        final responseFuture = client.send(request);
        // The announced 1 GiB movie remains incomplete. A buffered route
        // cannot even start its response while this source stays open.
        source.add(Uint8List.fromList(List.filled(64 * 1024, 42)));
        final response = await responseFuture.timeout(
          const Duration(seconds: 3),
          onTimeout: () =>
              throw StateError('Response headers waited for the full film.'),
        );
        expect(response.statusCode, mode == 'uncached full' ? 200 : 206);
        final iterator = StreamIterator(response.stream);
        expect(
          await iterator.moveNext().timeout(const Duration(seconds: 3)),
          isTrue,
        );
        expect(iterator.current, everyElement(42));
        expect(source.isClosed, isFalse);
        expect(store.bufferedReads, 0);
        await iterator.cancel();
        client.close();
        // Give the socket a write so the abandoned peer is observable.
        source.add(Uint8List(64 * 1024));
        await released.future.timeout(
          const Duration(seconds: 3),
          onTimeout: () =>
              throw StateError('Playback did not release upstream.'),
        );
      } finally {
        client.close();
        await source.close();
        await subscription.cancel();
        await server.close(force: true);
        await directory.delete(recursive: true);
      }
    });
  }

  test(
    'uncached legacy film keeps suffix ranges without buffered reads',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'clawnsole-legacy-playback-',
      );
      final store = _StreamingStore(
        directory,
        Stream.value([1, 2, 3, 4, 5, 6]),
        'legacy',
      );
      final application = CompanionApp.hybrid(store: store, api: BflApi());
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen(application.handle);
      try {
        final response = await http.get(
          Uri.parse(
            'http://127.0.0.1:${server.port}/assets?id=drive-stream-film',
          ),
          headers: {'Range': 'bytes=-2'},
        );
        expect(response.statusCode, 206);
        expect(response.headers['content-range'], 'bytes 4-5/6');
        expect(response.bodyBytes, [5, 6]);
        expect(store.bufferedReads, 0);
      } finally {
        await subscription.cancel();
        await server.close(force: true);
        await directory.delete(recursive: true);
      }
    },
  );
}

class _StreamingStore extends CompanionHybridStore {
  _StreamingStore(Directory directory, this.source, this.mode)
    : super(
        HybridDataStore(
          local: CompanionStore(File('${directory.path}/library.json')),
          drive: GoogleDriveStore(),
        ),
      );

  final Stream<List<int>> source;
  final String mode;
  int bufferedReads = 0;
  static const size = 1024 * 1024 * 1024;

  @override
  Future<StoredData> readLocal() async {
    final now = DateTime.utc(2026, 9, 7);
    return StoredData(
      generations: [
        Generation(
          localId: 'film',
          status: 'Ready',
          prompt: 'streamed movie',
          mode: VideoMode.t2v,
          config: const GenerationConfig(
            aspectRatio: '16:9',
            duration: 8,
            resolution: 'hd',
            generateAudio: true,
            safetyTolerance: 2,
            draft: false,
          ),
          createdAt: now,
          updatedAt: now,
          resultAsset: AssetReference(
            kind: 'drive',
            value: 'drive-stream-film',
            label: 'film.mp4',
            contentType: 'video/mp4',
            bytes: mode == 'legacy' ? null : size,
          ),
        ),
      ],
    );
  }

  @override
  Future<Uint8List> readAsset(AssetReference reference) async {
    bufferedReads++;
    throw StateError('Video playback must stream.');
  }

  @override
  Future<Uint8List> readDriveAssetRange(
    AssetReference reference,
    int start,
    int end,
  ) async {
    bufferedReads++;
    throw StateError('Video seeking must stream.');
  }

  @override
  Future<GoogleDriveByteStream> readDriveAssetRangeStream(
    AssetReference reference,
    int start,
    int end,
  ) async => GoogleDriveByteStream(source, contentLength: end - start + 1);

  @override
  Future<GoogleDriveByteStream> readDriveAssetStream(
    AssetReference reference,
  ) async => mode == 'cold seek'
      ? GoogleDriveByteStream(
          Stream.value(Uint8List(1024)),
          contentLength: 1024,
        )
      : GoogleDriveByteStream(
          source,
          contentLength: mode == 'legacy' ? 6 : size,
        );
}
