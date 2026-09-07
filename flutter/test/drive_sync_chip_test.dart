import 'dart:convert';
import 'dart:typed_data';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/core/asset_extensions.dart';
import 'package:clawnsole/core/durable_data_store.dart';
import 'package:clawnsole/core/google_drive.dart';
import 'package:clawnsole/core/google_drive_auth_base.dart';
import 'package:clawnsole/core/google_drive_store.dart';
import 'package:clawnsole/core/google_drive_upload_pump.dart';
import 'package:clawnsole/core/hybrid_data_store.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/web_gateway.dart';
import 'package:clawnsole/ui/common_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/memory_asset_streaming.dart';

/// A `local`-kind asset on a Drive-tagged record names a file that exists on
/// exactly one device. The chip used to read "Syncing…" on every device that
/// could see the record, including the ones that can never publish those
/// bytes — so a film staged on a Mac that is closed said "Syncing…" on the
/// phone forever, and a manual refresh could not change that.
///
/// These tests pin the two halves of the fix: this device's upload pass says
/// what its own queue is doing, and the chip says only what is true here.
void main() {
  final now = DateTime.utc(2026, 9, 6, 12);

  setUp(resetDriveUploadQueue);
  tearDown(resetDriveUploadQueue);

  Generation film(
    String id, {
    AssetReference? resultAsset,
    AssetReference? thumbnailAsset,
    LibraryStorage storage = LibraryStorage.drive,
    String? resultUrl,
    DateTime? updatedAt,
  }) => Generation(
    localId: id,
    status: 'Ready',
    prompt: 'a long quiet take',
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
    updatedAt: updatedAt ?? now,
    resultUrl: resultUrl,
    resultAsset: resultAsset,
    thumbnailAsset: thumbnailAsset,
    storage: storage,
  );

  SavedReference savedReference(
    String id, {
    required AssetReference asset,
    LibraryStorage storage = LibraryStorage.drive,
  }) => SavedReference(
    id: id,
    name: id,
    kind: MediaReferenceKind.image,
    asset: asset,
    createdAt: now,
    updatedAt: now,
    storage: storage,
  );

  const staged = AssetReference(
    kind: 'local',
    value: 'staged-1',
    label: 'film.mp4',
    contentType: 'video/mp4',
  );
  const published = AssetReference(
    kind: 'drive',
    value: 'drive-1',
    label: 'film.mp4',
    contentType: 'video/mp4',
  );

  group('the chip', () {
    test('says nothing about a published or local record', () {
      installDriveUploadQueue(
        const DriveUploadQueueReport(reported: true, queued: <String>{'x'}),
      );
      expect(
        generationPendingDriveUpload(film('a', resultAsset: published)),
        DriveUploadState.published,
      );
      expect(
        generationPendingDriveUpload(
          film('a', resultAsset: staged, storage: LibraryStorage.local),
        ),
        DriveUploadState.published,
        reason: 'a local-library record is not waiting for Drive at all',
      );
    });

    test('says Syncing only while this device holds the bytes', () {
      installDriveUploadQueue(
        DriveUploadQueueReport(reported: true, queued: <String>{staged.value}),
      );
      expect(
        generationPendingDriveUpload(film('a', resultAsset: staged)),
        DriveUploadState.uploading,
      );
      expect(
        StorageBadge.labelFor(DriveUploadState.uploading, LibraryStorage.drive),
        'Syncing…',
      );
    });

    test('waits, rather than syncing, for another device', () {
      installDriveUploadQueue(
        DriveUploadQueueReport(reported: true, foreign: <String>{staged.value}),
      );
      expect(
        generationPendingDriveUpload(film('a', resultAsset: staged)),
        DriveUploadState.awaitingOtherDevice,
      );
      expect(
        StorageBadge.labelFor(
          DriveUploadState.awaitingOtherDevice,
          LibraryStorage.drive,
        ),
        'Awaiting upload',
      );
    });

    test('waits when no pass has reported yet', () {
      expect(
        generationPendingDriveUpload(film('a', resultAsset: staged)),
        DriveUploadState.awaitingUpload,
        reason: 'a surface with no local pump must not claim a sync',
      );
    });

    test('reports a stalled queue as stalled', () {
      installDriveUploadQueue(
        DriveUploadQueueReport(
          reported: true,
          queued: <String>{staged.value},
          stalledDetail: 'Google Drive is not connected on this device.',
        ),
      );
      expect(
        generationPendingDriveUpload(film('a', resultAsset: staged)),
        DriveUploadState.stalled,
      );
      expect(
        StorageBadge.labelFor(DriveUploadState.stalled, LibraryStorage.drive),
        'Sync stalled',
      );
    });

    test('describes the least finished asset of a record', () {
      // The film published; its preview is still on the device that made it.
      installDriveUploadQueue(
        const DriveUploadQueueReport(
          reported: true,
          foreign: <String>{'thumb-1'},
        ),
      );
      expect(
        generationPendingDriveUpload(
          film(
            'a',
            resultAsset: published,
            thumbnailAsset: const AssetReference(
              kind: 'local',
              value: 'thumb-1',
              label: 'thumb.jpg',
              contentType: 'image/jpeg',
            ),
          ),
        ),
        DriveUploadState.awaitingOtherDevice,
        reason: 'the record is only as published as its least published asset',
      );
    });

    test('a saved reference only claims a sync this device is running', () {
      installDriveUploadQueue(
        DriveUploadQueueReport(reported: true, queued: <String>{staged.value}),
      );
      expect(
        savedReferencePendingDriveUpload(savedReference('r', asset: staged)),
        isTrue,
      );
      installDriveUploadQueue(
        DriveUploadQueueReport(reported: true, foreign: <String>{staged.value}),
      );
      expect(
        savedReferencePendingDriveUpload(savedReference('r', asset: staged)),
        isFalse,
      );
    });

    testWidgets('renders one label per state', (tester) async {
      for (final (state, label) in <(DriveUploadState, String)>[
        (DriveUploadState.published, 'Drive'),
        (DriveUploadState.uploading, 'Syncing…'),
        (DriveUploadState.stalled, 'Sync stalled'),
        (DriveUploadState.awaitingUpload, 'Awaiting upload'),
        (DriveUploadState.awaitingOtherDevice, 'Awaiting upload'),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: StorageBadge(
                  storage: LibraryStorage.drive,
                  pendingUpload: state,
                ),
              ),
            ),
          ),
        );
        expect(find.text(label), findsOneWidget, reason: '$state');
        if (state != DriveUploadState.uploading) {
          expect(
            find.text('Syncing…'),
            findsNothing,
            reason: 'only an upload running here may claim a sync',
          );
        }
      }
    });

    test('the player blames the right device', () {
      installDriveUploadQueue(
        DriveUploadQueueReport(reported: true, queued: <String>{staged.value}),
      );
      expect(
        generationDeliveryUnavailableDetail(film('a', resultAsset: staged)),
        contains('uploading from this device'),
      );
      installDriveUploadQueue(
        DriveUploadQueueReport(reported: true, foreign: <String>{staged.value}),
      );
      expect(
        generationDeliveryUnavailableDetail(film('a', resultAsset: staged)),
        contains('the device that made it'),
      );
    });
  });

  group('the upload pass', () {
    Future<(HybridDataStore, _MemoryStore, _MemoryDriveStore)> connected({
      bool connect = true,
    }) async {
      final local = _MemoryStore(const StoredData());
      final drive = _MemoryDriveStore(const StoredData());
      final hybrid = HybridDataStore(local: local, drive: drive);
      if (connect) await hybrid.connect('token', 'Clawnsole');
      return (hybrid, local, drive);
    }

    test('reports its own queue before it starts uploading', () async {
      final (hybrid, _, _) = await connected();
      final mine = await hybrid.writeAsset(
        Uint8List.fromList(<int>[1, 2, 3]),
        label: 'film.mp4',
        contentType: 'video/mp4',
        storage: LibraryStorage.drive,
      );
      await hybrid.write(
        StoredData(generations: <Generation>[film('a', resultAsset: mine)]),
      );

      final reports = <DriveUploadQueueReport>[];
      await runDriveUploadPass(
        hybrid: hybrid,
        read: hybrid.read,
        write: hybrid.write,
        onReport: reports.add,
      );

      expect(reports.first.queued, <String>{
        mine.value,
      }, reason: 'a film staged a moment ago reads as syncing from frame one');
      expect(reports.first.foreign, isEmpty);
      expect(
        reports.last.queued,
        isEmpty,
        reason: 'once published nothing is pending at all',
      );
    });

    test('reports another device\'s staged media as foreign', () async {
      final (hybrid, _, drive) = await connected();
      await hybrid.write(
        StoredData(
          generations: <Generation>[film('theirs', resultAsset: staged)],
        ),
      );

      final reports = <DriveUploadQueueReport>[];
      final done = await runDriveUploadPass(
        hybrid: hybrid,
        read: hybrid.read,
        write: hybrid.write,
        onReport: reports.add,
      );

      expect(done, isTrue, reason: 'nothing this device can publish is left');
      expect(drive.assets, isEmpty);
      expect(reports.last.foreign, <String>{staged.value});
      expect(reports.last.queued, isEmpty);

      installDriveUploadQueue(reports.last);
      expect(
        generationPendingDriveUpload(film('theirs', resultAsset: staged)),
        DriveUploadState.awaitingOtherDevice,
      );
    });

    test('a disconnected Drive is a stall, not a sync', () async {
      final hybrid = HybridDataStore(
        local: _MemoryStore(
          StoredData(
            savedReferences: <SavedReference>[
              savedReference('r', asset: staged),
            ],
          ),
        ),
        drive: _MemoryDriveStore(const StoredData()),
      );

      final reports = <DriveUploadQueueReport>[];
      final done = await runDriveUploadPass(
        hybrid: hybrid,
        swap: (_) async {},
        onReport: reports.add,
      );

      expect(done, isFalse, reason: 'the pump keeps retrying');
      expect(reports.single.isStalled, isTrue);
      expect(reports.single.stalledDetail, contains('not connected'));
      installDriveUploadQueue(reports.single);
      expect(
        savedReferencePendingDriveUpload(savedReference('r', asset: staged)),
        isFalse,
        reason: 'a stalled queue is not a sync in progress',
      );
    });

    test('a re-introduced staged id is re-swapped, not re-uploaded', () async {
      final (hybrid, local, drive) = await connected();
      final mine = await hybrid.writeAsset(
        Uint8List.fromList(<int>[9, 9, 9]),
        label: 'film.mp4',
        contentType: 'video/mp4',
        storage: LibraryStorage.drive,
      );
      await hybrid.write(
        StoredData(generations: <Generation>[film('a', resultAsset: mine)]),
      );
      final ledger = DriveUploadLedger();
      final reports = <DriveUploadQueueReport>[];
      Future<bool> pass() => runDriveUploadPass(
        hybrid: hybrid,
        ledger: ledger,
        read: hybrid.read,
        write: hybrid.write,
        onReport: reports.add,
      );

      expect(await pass(), isTrue);
      final swapped = (await hybrid.read()).generations.single.resultAsset!;
      expect(swapped.kind, 'drive');
      expect(drive.assets, hasLength(1));

      // A cross-device merge brings the pre-swap record back. The staged file
      // is gone by now — publishing adopted it into the Drive media cache —
      // so without the ledger this record is stuck saying it is not on Drive.
      local.assets.remove(mine.value);
      await hybrid.write(
        StoredData(generations: <Generation>[film('a', resultAsset: mine)]),
      );

      expect(await pass(), isTrue);
      final repaired = (await hybrid.read()).generations.single.resultAsset!;
      expect(repaired.value, swapped.value);
      expect(
        drive.assets,
        hasLength(1),
        reason: 'the film is not uploaded to Drive a second time',
      );
      expect(reports.last.queued, isEmpty);
      expect(reports.last.foreign, isEmpty);
      installDriveUploadQueue(reports.last);
      expect(
        generationPendingDriveUpload(film('a', resultAsset: repaired)),
        DriveUploadState.published,
      );
    });

    test('never moves bytes a local-library record still keeps', () async {
      final (hybrid, local, drive) = await connected();
      // Persisting an input reuses the file already on disk, so a Drive
      // generation and a local reference can name the same staged asset.
      final shared = await hybrid.writeAsset(
        Uint8List.fromList(<int>[7]),
        label: 'subject.png',
        contentType: 'image/png',
        storage: LibraryStorage.drive,
      );
      final mine = await hybrid.writeAsset(
        Uint8List.fromList(<int>[9, 9]),
        label: 'film.mp4',
        contentType: 'video/mp4',
        storage: LibraryStorage.drive,
      );
      await hybrid.write(
        StoredData(
          generations: <Generation>[
            film('a', resultAsset: mine, thumbnailAsset: shared),
          ],
          savedReferences: <SavedReference>[
            savedReference(
              'kept-local',
              asset: shared,
              storage: LibraryStorage.local,
            ),
          ],
        ),
      );

      expect(
        await runDriveUploadPass(
          hybrid: hybrid,
          read: hybrid.read,
          write: hybrid.write,
        ),
        isTrue,
      );

      expect(drive.adopted, contains(mine.value));
      expect(
        drive.adopted,
        isNot(contains(shared.value)),
        reason: 'adopting is a rename; the local reference still needs it',
      );
      expect(local.assets.containsKey(shared.value), isTrue);
      final reference = (await hybrid.read()).savedReferences.single;
      expect(reference.asset.kind, 'local');
      expect(reference.asset.value, shared.value);
    });

    test('remembers a foreign id between passes', () async {
      final (hybrid, _, _) = await connected();
      await hybrid.write(
        StoredData(
          generations: <Generation>[film('theirs', resultAsset: staged)],
        ),
      );
      final ledger = DriveUploadLedger();
      final reports = <DriveUploadQueueReport>[];
      Future<bool> pass() => runDriveUploadPass(
        hybrid: hybrid,
        ledger: ledger,
        read: hybrid.read,
        write: hybrid.write,
        onReport: reports.add,
      );

      await pass();
      reports.clear();
      await pass();

      expect(reports.first.foreign, <String>{
        staged.value,
      }, reason: 'the chip must not flip back to "Syncing…" between passes');
      expect(reports.first.queued, isEmpty);
    });
  });

  group('the manual refresh', () {
    test('kicks a pass and reports what is still pending', () async {
      final gateway = _StatusGateway(
        client: MockClient((request) async {
          switch (request.url.path) {
            case '/composer-tabs':
              return http.Response('{}', 200);
            case '/state':
            case '/drive/refresh':
              return http.Response(
                jsonEncode(
                  LocalSnapshot(
                    generations: <Generation>[film('a', resultAsset: staged)],
                    preferences: const AppPreferences(),
                    hasApiKey: false,
                    storage: const StorageStats(
                      path: 'memory',
                      bytes: 0,
                      records: 1,
                    ),
                  ).toJson(),
                ),
                200,
              );
            default:
              throw StateError('Unexpected request: ${request.url}');
          }
        }),
      );
      final controller = AppController(gateway: gateway)..loading = false;
      addTearDown(controller.dispose);

      await controller.refreshGoogleDrive();

      expect(gateway.flushes, 1, reason: 'the refresh re-kicks the pass');
      expect(controller.notice, contains('Google Drive data refreshed.'));
      expect(
        controller.notice,
        contains('1 file(s) waiting on the device that made them'),
      );
      expect(
        generationPendingDriveUpload(film('a', resultAsset: staged)),
        DriveUploadState.awaitingOtherDevice,
        reason: 'the pass report reaches the chip helpers',
      );
    });

    test(
      'another device\'s film is not this device\'s background work',
      () async {
        final gateway = _StatusGateway(
          client: MockClient(
            (request) async =>
                throw StateError('Unexpected request: ${request.url}'),
          ),
        );
        final controller = AppController(gateway: gateway)
          ..loading = false
          ..snapshot = LocalSnapshot(
            generations: <Generation>[film('a', resultAsset: staged)],
            preferences: const AppPreferences(),
            hasApiKey: false,
            storage: const StorageStats(path: 'memory', bytes: 0, records: 1),
          );
        addTearDown(controller.dispose);

        expect(controller.pendingDriveUploadCount, 1);
        expect(
          controller.hasOutgoingDriveUploads,
          isFalse,
          reason: 'iOS must not stay awake for an upload it cannot perform',
        );
      },
    );

    test('reports a stalled queue on this device', () async {
      final gateway = _StatusGateway(
        client: MockClient((request) async {
          switch (request.url.path) {
            case '/composer-tabs':
              return http.Response('{}', 200);
            case '/state':
            case '/drive/refresh':
              return http.Response(
                jsonEncode(
                  LocalSnapshot(
                    generations: <Generation>[film('a', resultAsset: staged)],
                    preferences: const AppPreferences(),
                    hasApiKey: false,
                    storage: const StorageStats(
                      path: 'memory',
                      bytes: 0,
                      records: 1,
                    ),
                  ).toJson(),
                ),
                200,
              );
            default:
              throw StateError('Unexpected request: ${request.url}');
          }
        }),
        report: DriveUploadQueueReport(
          reported: true,
          queued: <String>{staged.value},
          stalledDetail: 'Google Drive is not connected on this device.',
        ),
      );
      final controller = AppController(gateway: gateway)..loading = false;
      addTearDown(controller.dispose);

      await controller.refreshGoogleDrive();

      expect(controller.notice, contains('1 upload(s) stalled on this device'));
      expect(controller.notice, contains('not connected'));
    });
  });
}

/// A [WebGateway] that also answers for this device's upload pump, the way
/// the native gateway does.
class _StatusGateway extends WebGateway implements DriveUploadStatusSource {
  _StatusGateway({required super.client, DriveUploadQueueReport? report})
    : _report =
          report ??
          const DriveUploadQueueReport(
            reported: true,
            foreign: <String>{'staged-1'},
          ),
      super(
        baseUrl: Uri.parse('http://127.0.0.1:8787'),
        driveAuthorizer: _FixtureAuthorizer(),
      );

  final DriveUploadQueueReport _report;
  int flushes = 0;
  void Function()? _listener;

  @override
  DriveUploadQueueReport get driveUploadStatus => _report;

  @override
  set onDriveUploadStatus(void Function()? listener) => _listener = listener;

  @override
  Future<bool> flushDriveUploads() async {
    flushes += 1;
    _listener?.call();
    return _report.queued.isEmpty;
  }
}

class _FixtureAuthorizer implements GoogleDriveAuthorizer {
  @override
  bool get isAvailable => true;

  @override
  String get unavailableMessage => '';

  @override
  Future<String> authorize() async => 'token';

  @override
  Future<String?> authorizeSilently() async => 'token';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryStore implements DurableDataStore {
  _MemoryStore(this.data);

  StoredData data;
  final Map<String, Uint8List> assets = <String, Uint8List>{};
  int _assetCounter = 0;

  @override
  Future<StoredData> read() async => data;

  @override
  Future<void> write(StoredData value) async => data = value;

  @override
  Future<AssetReference> writeAsset(
    Uint8List bytes, {
    required String label,
    required String contentType,
    LibraryStorage storage = LibraryStorage.local,
  }) async {
    final id = 'local-asset-${_assetCounter++}';
    assets[id] = bytes;
    return AssetReference(
      kind: 'local',
      value: id,
      label: label,
      contentType: contentType,
      bytes: bytes.length,
    );
  }

  @override
  Future<AssetReference?> persistSource(
    String source, {
    required String label,
    AssetReference? retained,
    LibraryStorage storage = LibraryStorage.local,
  }) async => retained;

  @override
  Future<Uint8List> readAsset(AssetReference reference) async {
    final bytes = assets[reference.value];
    if (bytes == null) throw StateError('Missing asset ${reference.value}.');
    return bytes;
  }

  @override
  Future<Uri> assetUri(AssetReference reference) async =>
      Uri.file('/tmp/clawnsole-test/${reference.value}');

  @override
  Future<void> pruneAssets(
    List<Generation> generations, [
    List<SavedReference> savedReferences = const <SavedReference>[],
  ]) async {}

  @override
  Future<void> delete() async {
    data = const StoredData();
    assets.clear();
  }

  @override
  Future<StorageStats> stats(int records) async =>
      StorageStats(path: 'memory', bytes: 0, records: records);
}

class _MemoryDriveStore extends GoogleDriveStore with MemoryAssetStreaming {
  _MemoryDriveStore(this.data);

  StoredData data;
  final Map<String, Uint8List> assets = <String, Uint8List>{};
  int _assetCounter = 0;
  GoogleDriveConnection _memoryConnection = const GoogleDriveConnection(
    state: GoogleDriveConnectionState.disconnected,
  );

  @override
  GoogleDriveConnection get connection => _memoryConnection;

  @override
  Future<StoredData> connect(String accessToken, String folderName) async {
    _memoryConnection = GoogleDriveConnection(
      state: GoogleDriveConnectionState.connected,
      folderName: folderName,
      folderId: 'drive-root',
    );
    return data;
  }

  @override
  Future<StoredData> read() async => data;

  @override
  Future<void> write(StoredData value) async =>
      data = googleDrivePortableData(value);

  @override
  Future<AssetReference> writeAsset(
    Uint8List bytes, {
    required String label,
    required String contentType,
    LibraryStorage storage = LibraryStorage.drive,
  }) async {
    final id = 'drive-asset-${_assetCounter++}';
    assets[id] = bytes;
    return AssetReference(
      kind: 'drive',
      value: id,
      label: label,
      contentType: contentType,
      bytes: bytes.length,
    );
  }

  @override
  Future<Uint8List> readAsset(AssetReference reference) async =>
      assets[reference.value] ?? Uint8List(0);

  /// Records which staged originals the pass moved into the Drive cache.
  final List<String> adopted = <String>[];

  @override
  Future<Uri?> adoptPublishedAsset(
    AssetReference reference,
    Uri localFile,
  ) async {
    adopted.add(localFile.pathSegments.last);
    return localFile;
  }

  @override
  Future<StoredData> repairMissingCachedAssets(StoredData value) async => value;

  @override
  Future<StorageStats> stats(int records) async =>
      StorageStats(path: 'drive', bytes: 0, records: records);
}
