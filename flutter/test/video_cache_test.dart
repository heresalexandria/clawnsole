import 'dart:async';
import 'dart:io';

import 'package:clawnsole/core/video_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('clawnsole-video-cache.');
  });

  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  VideoCache cache({int maxBytes = VideoCache.defaultVideoCacheBytes}) =>
      VideoCache(directory: () async => temporary, maxBytes: maxBytes);

  Stream<List<int>> bytes(int length, [int fill = 7]) =>
      Stream<List<int>>.value(List<int>.filled(length, fill));

  test('lookup misses cold and hits after a put', () async {
    final subject = cache();
    expect(await subject.lookup('drive-file-one'), isNull);

    final stored = await subject.put('drive-file-one', '.mp4', bytes(4));
    expect(stored.path, endsWith('drive-file-one.mp4'));
    expect(await stored.readAsBytes(), List<int>.filled(4, 7));

    final hit = await subject.lookup('drive-file-one');
    expect(hit?.path, stored.path);
    expect(await subject.lookup('never-written'), isNull);
    expect(await subject.usedBytes(), 4);
  });

  test('a hit refreshes recency so the untouched file evicts first', () async {
    final subject = cache(maxBytes: 10);
    final old = DateTime.now().subtract(const Duration(hours: 2));
    await (await subject.put('older', '.mp4', bytes(4))).setLastModified(old);
    await (await subject.put(
      'newer',
      '.mp4',
      bytes(4),
    )).setLastModified(old.add(const Duration(minutes: 1)));

    // Touch the stale one: it becomes the most recently used.
    expect(await subject.lookup('older'), isNotNull);

    await subject.put('third', '.mp4', bytes(4));
    expect(await subject.lookup('older'), isNotNull);
    expect(await subject.lookup('newer'), isNull);
    expect(await subject.lookup('third'), isNotNull);
  });

  test(
    'eviction removes least recently used files until under the cap',
    () async {
      final subject = cache(maxBytes: 10);
      final base = DateTime.now().subtract(const Duration(hours: 3));
      await (await subject.put(
        'first',
        '.mp4',
        bytes(4),
      )).setLastModified(base);
      await (await subject.put(
        'second',
        '.mp4',
        bytes(4),
      )).setLastModified(base.add(const Duration(minutes: 1)));

      await subject.put('third', '.mp4', bytes(4));

      expect(await subject.lookup('first'), isNull);
      expect(await subject.lookup('second'), isNotNull);
      expect(await subject.lookup('third'), isNotNull);
      expect(await subject.usedBytes(), 8);
    },
  );

  test('shrinking the cap sweeps immediately and zero clears', () async {
    final subject = cache(maxBytes: 100);
    final base = DateTime.now().subtract(const Duration(hours: 3));
    await (await subject.put('first', '.mp4', bytes(6))).setLastModified(base);
    await (await subject.put(
      'second',
      '.mp4',
      bytes(6),
    )).setLastModified(base.add(const Duration(minutes: 1)));
    await (await subject.put(
      'third',
      '.mp4',
      bytes(6),
    )).setLastModified(base.add(const Duration(minutes: 2)));

    await subject.setMaxBytes(12);
    expect(await subject.lookup('first'), isNull);
    expect(await subject.usedBytes(), 12);

    await subject.setMaxBytes(0);
    expect(subject.enabled, isFalse);
    expect(await subject.usedBytes(), 0);
    expect(await subject.lookup('second'), isNull);
  });

  test('concurrent puts for one key share a single download', () async {
    final subject = cache();
    var pulls = 0;
    Stream<List<int>> counted() async* {
      pulls += 1;
      yield List<int>.filled(3, 1);
    }

    final first = subject.put('shared', '.mp4', counted());
    final second = subject.put('shared', '.mp4', counted());
    expect(identical(first, second), isTrue);
    await first;
    await second;
    expect(pulls, 1);
  });

  test('progress listeners observe streamed bytes and completion', () async {
    final subject = cache();
    final events = <(int, int?, bool)>[];
    void listener(int received, int? total, bool done) =>
        events.add((received, total, done));
    subject.addProgressListener('film', listener);

    await subject.put(
      'film',
      '.mp4',
      Stream<List<int>>.fromIterable(<List<int>>[
        List<int>.filled(2, 0),
        List<int>.filled(3, 0),
      ]),
      expectedLength: 5,
    );

    expect(events, <(int, int?, bool)>[
      (2, 5, false),
      (5, 5, false),
      (5, 5, true),
    ]);

    subject.removeProgressListener('film', listener);
    await subject.put('film-two', '.mp4', bytes(1));
    expect(events, hasLength(3));
  });

  test('a failed download leaves no partial or cached file', () async {
    final subject = cache();
    Stream<List<int>> failing() async* {
      yield List<int>.filled(2, 0);
      throw const FileSystemException('stream interrupted');
    }

    await expectLater(
      subject.put('broken', '.mp4', failing()),
      throwsA(isA<FileSystemException>()),
    );
    expect(await subject.lookup('broken'), isNull);
    expect(
      temporary.listSync().whereType<File>().where(
        (file) => file.path.contains('broken'),
      ),
      isEmpty,
    );
  });

  test('invalid keys never touch the disk', () async {
    final subject = cache();
    expect(await subject.lookup('../escape'), isNull);
    expect(
      () => subject.put('../escape', '.mp4', bytes(1)),
      throwsArgumentError,
    );
  });
}
