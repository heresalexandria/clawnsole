import 'dart:io';
import 'dart:typed_data';

import 'package:clawnsole/core/local_data_store_io.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/temporary_media_host.dart';
import 'package:clawnsole/core/temporary_media_source_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late LocalDataStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'temporary-media-source.',
    );
    store = LocalDataStore(documentsDirectory: directory);
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'retained private asset is preferred and streamed without rewriting it',
    () async {
      final retained = await store.writeAsset(
        Uint8List.fromList([1, 2, 3]),
        label: 'source.mp4',
        contentType: 'video/mp4',
      );
      final staged = await stageTemporaryMediaSource(
        TemporaryMediaSource(
          source: 'data:video/mp4;base64,BAUG',
          label: 'source.mp4',
          kind: MediaReferenceKind.video,
          retained: retained,
        ),
        store,
        directory: directory.path,
      );
      expect(await File(staged.path).readAsBytes(), [1, 2, 3]);
      expect(await store.readAsset(retained), [1, 2, 3]);
      final path = staged.path;
      await staged.dispose();
      expect(await File(path).exists(), isFalse);
    },
  );

  test('imported inline bytes use bounded staging', () async {
    final staged = await stageTemporaryMediaSource(
      const TemporaryMediaSource(
        source: 'data:video/mp4;base64,AQID',
        label: 'clip.mp4',
        kind: MediaReferenceKind.video,
      ),
      store,
      directory: directory.path,
    );
    expect(staged.length, 3);
    expect(await File(staged.path).readAsBytes(), [1, 2, 3]);
    await staged.dispose();
    await expectLater(
      stageTemporaryMediaSource(
        const TemporaryMediaSource(
          source: 'data:video/mp4;base64,AQID',
          label: 'clip.mp4',
          kind: MediaReferenceKind.video,
        ),
        store,
        directory: directory.path,
        maxBytes: 2,
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('inline source survives a retained file moving to Drive', () async {
    final retained = await store.writeAsset(
      Uint8List.fromList([1, 2, 3]),
      label: 'source.mp4',
      contentType: 'video/mp4',
    );
    final original = File.fromUri(await store.assetUri(retained));
    await original.rename('${directory.path}/published-cache.mp4');

    final source = TemporaryMediaSource(
      source: 'data:video/mp4;base64,AQID',
      label: 'source.mp4',
      kind: MediaReferenceKind.video,
      retained: retained,
    );
    final staged = await stageTemporaryMediaSource(
      source,
      store,
      directory: directory.path,
    );
    expect(await File(staged.path).readAsBytes(), [1, 2, 3]);
    await staged.dispose();

    await expectLater(
      stageTemporaryMediaSource(source, store, maxBytes: 2),
      throwsA(isA<Exception>()),
      reason: 'fallback still applies the configured staging size limit',
    );
  });

  test('inline fallback must match the retained size and checksum', () async {
    final retained = await store.writeAssetStream(
      Stream.value([1, 2, 3]),
      label: 'source.mp4',
      contentType: 'video/mp4',
    );
    expect(retained.sha256, isNotNull);
    await File.fromUri(await store.assetUri(retained)).delete();
    for (final encoded in ['BAUG', 'AQI=']) {
      await expectLater(
        stageTemporaryMediaSource(
          TemporaryMediaSource(
            source: 'data:video/mp4;base64,$encoded',
            label: 'source.mp4',
            kind: MediaReferenceKind.video,
            retained: retained,
          ),
          store,
          directory: directory.path,
        ),
        throwsA(isA<Exception>()),
      );
    }
    expect(
      await directory
          .list()
          .where(
            (entry) => entry.path
                .split(Platform.pathSeparator)
                .last
                .startsWith('.clawnsole-retain-'),
          )
          .toList(),
      isEmpty,
    );
  });

  test(
    'inline fallback also handles a retained stream failing after open',
    () async {
      final streamFailure = StateError(
        'The retained file moved before reading.',
      );
      final failingStore = _FailingStreamStore(streamFailure);
      const retained = AssetReference(
        kind: 'local',
        value: 'moved-source',
        label: 'source.mp4',
        contentType: 'video/mp4',
        bytes: 3,
      );
      final staged = await stageTemporaryMediaSource(
        const TemporaryMediaSource(
          source: 'data:video/mp4;base64,AQID',
          label: 'source.mp4',
          kind: MediaReferenceKind.video,
          retained: retained,
        ),
        failingStore,
        directory: directory.path,
      );
      expect(await File(staged.path).readAsBytes(), [1, 2, 3]);
      await staged.dispose();
      expect(await directory.list().toList(), isEmpty);

      await expectLater(
        stageTemporaryMediaSource(
          const TemporaryMediaSource(
            source: '',
            label: 'source.mp4',
            kind: MediaReferenceKind.video,
            retained: retained,
          ),
          failingStore,
          directory: directory.path,
        ),
        throwsA(same(streamFailure)),
        reason: 'without imported bytes, preserve the original storage failure',
      );
      expect(await directory.list().toList(), isEmpty);
    },
  );

  test(
    'existing files outside the asset store cannot become hosted references',
    () async {
      final outside = await Directory.systemTemp.createTemp('unowned-media.');
      addTearDown(() => outside.delete(recursive: true));
      final source = File('${outside.path}/private.mp4');
      await source.writeAsBytes([1, 2, 3]);
      for (final value in [source.path, source.uri.toString()]) {
        await expectLater(
          stageTemporaryMediaSource(
            TemporaryMediaSource(
              source: value,
              label: 'clip.mp4',
              kind: MediaReferenceKind.video,
              contentType: 'video/mp4',
            ),
            store,
            directory: directory.path,
          ),
          throwsStateError,
        );
        expect(await source.readAsBytes(), [1, 2, 3]);
      }
      expect(await directory.list().toList(), isEmpty);
    },
  );

  test('network and relative paths are never fetched or staged', () async {
    for (final value in [
      'https://cdn.example.com/clip.mp4',
      'https://127.0.0.1/clip.mp4',
      'http://internal/clip.mp4',
      'relative.mp4',
      '',
    ]) {
      await expectLater(
        stageTemporaryMediaSource(
          TemporaryMediaSource(
            source: value,
            label: 'clip.mp4',
            kind: MediaReferenceKind.video,
          ),
          store,
        ),
        throwsStateError,
      );
    }
  });
}

class _FailingStreamStore extends LocalDataStore {
  _FailingStreamStore(this.failure);

  final Object failure;

  @override
  Future<Stream<List<int>>> openAssetRead(AssetReference reference) async =>
      Stream<List<int>>.error(failure);
}
