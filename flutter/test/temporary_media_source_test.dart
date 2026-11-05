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

  test('data, file URLs and absolute paths use bounded staging', () async {
    final source = File('${directory.path}/clip.mp4');
    await source.writeAsBytes([1, 2, 3]);
    for (final value in [
      'data:video/mp4;base64,AQID',
      source.uri.toString(),
      source.path,
    ]) {
      final staged = await stageTemporaryMediaSource(
        TemporaryMediaSource(
          source: value,
          label: 'clip.mp4',
          kind: MediaReferenceKind.video,
        ),
        store,
        directory: directory.path,
      );
      expect(staged.length, 3);
      expect(await File(staged.path).readAsBytes(), [1, 2, 3]);
      await staged.dispose();
    }
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
