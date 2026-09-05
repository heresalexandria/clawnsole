import 'dart:async';
import 'dart:io';

import 'package:clawnsole/core/asset_stream.dart';
import 'package:clawnsole/core/background_delivery.dart';
import 'package:clawnsole/core/local_data_store_io.dart';
import 'package:clawnsole/core/models.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  final agedDirectories = <String>{};
  setUp(() async {
    root = await Directory.systemTemp.createTemp('retention-test-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  Future<Directory> oldStage(
    String name, {
    String fileName = 'media.part',
  }) async {
    final directory = await Directory('${root.path}/$name').create();
    final file = File('${directory.path}/$fileName');
    await file.writeAsString('keep');
    final old = DateTime.now().subtract(const Duration(days: 2));
    await file.setLastModified(old);
    agedDirectories.add(directory.path);
    return directory;
  }

  test('staging sweep removes only old owned inactive directories', () async {
    final abandoned = await oldStage('.clawnsole-retain-ABANDONED');
    final freshFile = await oldStage('.clawnsole-retain-FRESHFILE');
    await File('${freshFile.path}/media.part').writeAsString('fresh');
    final freshDirectory = await oldStage('.clawnsole-retain-FRESHDIR');
    agedDirectories.remove(freshDirectory.path);
    final foreign = await oldStage('unrelated');
    final unexpected = await oldStage(
      '.clawnsole-retain-FOREIGN',
      fileName: 'user-file.txt',
    );
    final liveProcess = await oldStage('.clawnsole-retain-$pid-ACTIVE');
    final unlocked = await oldStage('.clawnsole-retain-UNLOCKED');
    await File('${unlocked.path}/preserve-unlocked-stage').writeAsString('1');
    agedDirectories.add(unlocked.path);

    final staged = await IOOverrides.runWithIOOverrides(
      () => stageAssetStream(Stream.value([1, 2, 3]), directory: root.path),
      _AgedDirectoryStats(agedDirectories),
    );

    expect(await abandoned.exists(), isFalse);
    for (final retained in [
      freshFile,
      freshDirectory,
      foreign,
      unexpected,
      liveProcess,
      unlocked,
    ]) {
      expect(await retained.exists(), isTrue, reason: retained.path);
    }
    expect(await staged.openRead().expand((bytes) => bytes).toList(), [
      1,
      2,
      3,
    ]);
    await staged.dispose();
    // Housekeeping is throttled; newly appearing old directories wait for the
    // next process instead of adding a directory scan to every media write.
    final later = await oldStage('.clawnsole-retain-LATER');
    final next = await stageAssetStream(
      Stream.value([4]),
      directory: root.path,
    );
    expect(await later.exists(), isTrue);
    await next.dispose();
  });

  test('staging sweep never follows or removes links', () async {
    final foreign = await oldStage('foreign-target');
    final rootLink = await Link(
      '${root.path}/.clawnsole-retain-LINK',
    ).create(foreign.path);
    final childLink = await oldStage('.clawnsole-retain-CHILDLINK');
    await File('${childLink.path}/media.part').delete();
    final link = await Link(
      '${childLink.path}/media.part',
    ).create('${foreign.path}/media.part');
    agedDirectories.add(childLink.path);

    final staged = await IOOverrides.runWithIOOverrides(
      () => stageAssetStream(Stream.value([1]), directory: root.path),
      _AgedDirectoryStats(agedDirectories),
    );
    expect(await rootLink.exists(), isTrue);
    expect(await link.exists(), isTrue);
    expect(await File('${foreign.path}/media.part').readAsString(), 'keep');
    await staged.dispose();
  }, skip: Platform.isWindows);

  test(
    'unsupported staging locks preserve normal transfer functionality',
    () async {
      final staged = await IOOverrides.runWithIOOverrides(
        () => stageAssetStream(Stream.value([1, 2]), directory: root.path),
        _UnsupportedStagingLock(),
      );
      expect(await staged.openRead().expand((bytes) => bytes).toList(), [1, 2]);
      expect(
        await File(
          '${File(staged.path).parent.path}/preserve-unlocked-stage',
        ).exists(),
        isTrue,
      );
      await staged.dispose();
      expect(await root.list().isEmpty, isTrue);
    },
  );

  test(
    'local stream publishes complete bytes and digest only after EOF',
    () async {
      final store = LocalDataStore(documentsDirectory: root);
      final input = StreamController<List<int>>();
      final pending = store.writeAssetStream(
        input.stream,
        label: 'film.mp4',
        contentType: 'video/mp4',
        expectedLength: 6,
      );
      input.add([1, 2, 3]);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        await root
            .list(recursive: true)
            .where((e) => e.path.endsWith('.mp4'))
            .isEmpty,
        isTrue,
      );
      input.add([4, 5, 6]);
      await input.close();
      final asset = await pending;
      expect(asset.bytes, 6);
      expect(
        asset.sha256,
        crypto.sha256.convert([1, 2, 3, 4, 5, 6]).toString(),
      );
      expect(AssetReference.fromJson(asset.toJson()).sha256, asset.sha256);
      expect(await store.readAsset(asset), [1, 2, 3, 4, 5, 6]);
      expect(
        await root
            .list(recursive: true)
            .where((e) => e.path.endsWith('.part'))
            .isEmpty,
        isTrue,
      );
    },
  );

  for (final scenario
      in <({String name, List<List<int>> chunks, int? length, int max})>[
        (
          name: 'announced oversized',
          chunks: [
            [1],
          ],
          length: 10,
          max: 5,
        ),
        (
          name: 'unannounced oversized',
          chunks: [
            [1, 2, 3],
            [4, 5, 6],
          ],
          length: null,
          max: 5,
        ),
        (
          name: 'truncated',
          chunks: [
            [1, 2],
          ],
          length: 3,
          max: 5,
        ),
        (
          name: 'overlong',
          chunks: [
            [1, 2, 3],
          ],
          length: 2,
          max: 5,
        ),
        (name: 'empty', chunks: [], length: null, max: 5),
      ]) {
    test('${scenario.name} streams leave no asset or staging file', () async {
      final store = LocalDataStore(documentsDirectory: root);
      await expectLater(
        store.writeAssetStream(
          Stream.fromIterable(scenario.chunks),
          label: 'film.mp4',
          contentType: 'video/mp4',
          expectedLength: scenario.length,
          maxBytes: scenario.max,
        ),
        throwsA(isA<AssetTransferException>()),
      );
      expect(
        await root.list(recursive: true).where((e) => e is File).isEmpty,
        isTrue,
      );
    });
  }

  test(
    'checksum mismatch preserves the externally delivered original',
    () async {
      final original = File('${root.path}/background.mp4');
      await original.writeAsBytes([1, 2, 3]);
      final store = LocalDataStore(documentsDirectory: root);
      await expectLater(
        store.writeAssetStream(
          original.openRead(),
          label: 'film.mp4',
          contentType: 'video/mp4',
          expectedSha256: '00',
        ),
        throwsA(isA<AssetTransferException>()),
      );
      expect(await original.readAsBytes(), [1, 2, 3]);
    },
  );

  test(
    'idle stream times out, cancels producer and removes partial file',
    () async {
      var cancelled = false;
      final source = StreamController<List<int>>(
        onCancel: () {
          cancelled = true;
        },
      );
      final pending = stageAssetStream(
        source.stream,
        directory: root.path,
        idleTimeout: const Duration(milliseconds: 20),
      );
      source.add([1, 2]);
      await expectLater(pending, throwsA(isA<TimeoutException>()));
      expect(cancelled, isTrue);
      expect(await root.list().isEmpty, isTrue);
      await source.close();
    },
  );

  test('total deadline stops a continuously active trickle', () async {
    final source = StreamController<List<int>>();
    var cancelled = false;
    final timer = Timer.periodic(
      const Duration(milliseconds: 5),
      (_) => source.add([1]),
    );
    source.onCancel = () {
      cancelled = true;
      timer.cancel();
    };
    await expectLater(
      stageAssetStream(
        source.stream,
        directory: root.path,
        idleTimeout: const Duration(seconds: 1),
        totalTimeout: const Duration(milliseconds: 40),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(cancelled, isTrue);
    expect(await root.list().isEmpty, isTrue);
    await source.close();
  });

  test('disk preparation failure cancels unread source', () async {
    final blocker = File('${root.path}/not-a-directory');
    await blocker.writeAsString('keep');
    var cancelled = false;
    final source = StreamController<List<int>>(
      onCancel: () {
        cancelled = true;
      },
    );
    await expectLater(
      stageAssetStream(source.stream, directory: blocker.path),
      throwsA(isA<FileSystemException>()),
    );
    expect(cancelled, isTrue);
    expect(await blocker.readAsString(), 'keep');
    await source.close();
  });

  test(
    'deadline exhausted during file setup cancels an unread source',
    () async {
      var cancelled = false;
      final source = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      await expectLater(
        stageAssetStream(
          source.stream,
          directory: root.path,
          totalTimeout: Duration.zero,
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(cancelled, isTrue);
      expect(await root.list().isEmpty, isTrue);
      await source.close();
    },
  );

  test(
    'sink write failure cancels producer without consuming trailing chunks',
    () async {
      var produced = 0;
      var cancelled = false;
      Stream<List<int>> source() async* {
        try {
          for (var i = 0; i < 100; i++) {
            produced++;
            yield [i];
          }
        } finally {
          cancelled = true;
        }
      }

      await expectLater(
        consumeAssetStream(
          source(),
          write: (_) async {
            throw const FileSystemException('Disk full');
          },
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(produced, 1);
      expect(cancelled, isTrue);
    },
  );

  test(
    'published results survive pruning until metadata commits or a full wipe',
    () async {
      final store = LocalDataStore(documentsDirectory: root);
      final asset = await store.writeAssetStream(
        Stream.value([1, 2, 3]),
        label: 'film.mp4',
        contentType: 'video/mp4',
      );
      await store.pruneAssets([]);
      expect(await store.readAsset(asset), [1, 2, 3]);
      final now = DateTime.now().toUtc();
      final reference = SavedReference(
        id: 'film',
        name: 'film',
        kind: MediaReferenceKind.video,
        asset: asset,
        createdAt: now,
        updatedAt: now,
      );
      await Future.wait([
        store.write(StoredData(savedReferences: [reference])),
        store.pruneAssets([]),
      ]);
      expect(await store.readAsset(asset), [1, 2, 3]);
      await store.write(const StoredData());
      await store.pruneAssets([]);
      await expectLater(store.readAsset(asset), throwsStateError);
      final pending = await store.writeAssetStream(
        Stream.value([4, 5, 6]),
        label: 'pending.mp4',
        contentType: 'video/mp4',
      );
      await store.delete();
      await expectLater(store.readAsset(pending), throwsStateError);
    },
  );

  test(
    'platform pending result is a lazy file stream, never an eager copy',
    () async {
      const channel = MethodChannel('ai.clawnsole/background_delivery');
      final original = File('${root.path}/background.mp4');
      await original.writeAsBytes([1, 2, 3]);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => {'path': original.path, 'contentType': 'video/mp4'},
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final result = await MethodChannelBackgroundResultDelivery()
          .readPendingResult('film');
      expect(result!.expectedLength, 3);
      expect(result.path, original.path);
      // Mutating the file after metadata delivery is observable to the stream;
      // retention detects the length/digest change instead of retaining old RAM.
      await original.writeAsBytes([4, 5, 6]);
      expect(await result.openRead().expand((bytes) => bytes).toList(), [
        4,
        5,
        6,
      ]);
      expect(await original.exists(), isTrue);
    },
  );
}

final class _UnsupportedStagingLock extends IOOverrides {
  @override
  File createFile(String path) {
    final file = super.createFile(path);
    return path.endsWith('${Platform.pathSeparator}stage.lock')
        ? _UnsupportedLeaseFile(file)
        : file;
  }
}

final class _AgedDirectoryStats extends IOOverrides {
  _AgedDirectoryStats(this.paths);
  final Set<String> paths;

  @override
  Future<FileStat> stat(String path) async {
    final value = await super.stat(path);
    return paths.contains(path) ? _OldDirectoryStat(value) : value;
  }

  @override
  Future<FileSystemEntityType> fseGetType(String path, bool followLinks) async {
    if (!followLinks) {
      try {
        await super.createLink(path).target();
        return FileSystemEntityType.link;
      } on FileSystemException {
        // This real fixture entry is not a link.
      }
    }
    return (await super.stat(path)).type;
  }
}

class _OldDirectoryStat implements FileStat {
  _OldDirectoryStat(this.delegate);
  final FileStat delegate;

  @override
  DateTime get modified => DateTime.utc(2020);
  @override
  FileSystemEntityType get type => delegate.type;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnsupportedLeaseFile implements File {
  _UnsupportedLeaseFile(this.delegate);
  final File delegate;

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async =>
      throw const FileSystemException('Advisory leases unsupported');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
