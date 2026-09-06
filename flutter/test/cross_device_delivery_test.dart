import 'dart:async';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/google_drive.dart';
import 'package:clawnsole/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two devices share one Google Drive library. Every device increments a
/// record's statusCheckCount independently, so the copy that actually carries
/// the delivered film is routinely the copy with the *lower* counter. These
/// tests pin the reconciliation rules that let such a record land here.

final _now = DateTime.utc(2026, 9, 4, 12);

Generation _film(
  String id, {
  String status = 'Pending',
  String? resultUrl,
  AssetReference? resultAsset,
  int statusCheckCount = 0,
  DateTime? updatedAt,
  LibraryStorage storage = LibraryStorage.drive,
  bool canPoll = true,
}) => Generation(
  localId: id,
  provider: 'bfl',
  model: 'flux-3-video',
  status: status,
  prompt: 'A lighthouse at dusk.',
  mode: VideoMode.t2v,
  config: const GenerationConfig(
    aspectRatio: '16:9',
    duration: 5,
    resolution: 'hd',
    generateAudio: false,
    safetyTolerance: 2,
    draft: false,
  ),
  pollingUrl: canPoll ? 'https://api.bfl.ai/v1/get_result?id=$id' : null,
  resultUrl: resultUrl,
  resultAsset: resultAsset,
  statusCheckCount: statusCheckCount,
  createdAt: _now,
  updatedAt: updatedAt ?? _now,
  storage: storage,
);

const _driveAsset = AssetReference(
  kind: 'drive',
  value: 'drive-file-0001',
  label: 'film.mp4',
  contentType: 'video/mp4',
);

const _stagedAsset = AssetReference(
  kind: 'local',
  value: 'staged-0001.mp4',
  label: 'film.mp4',
  contentType: 'video/mp4',
);

LocalSnapshot _snapshot(
  List<Generation> films, {
  List<LibraryFolder> folders = const <LibraryFolder>[],
  List<SavedReference> references = const <SavedReference>[],
}) => LocalSnapshot(
  generations: films,
  folders: folders,
  savedReferences: references,
  preferences: const AppPreferences(),
  hasApiKey: true,
  connectedProviders: const <String>{'bfl'},
  storage: StorageStats(path: 'memory', bytes: 0, records: films.length),
);

/// A delivery gateway whose poll and retain results stand in for whatever the
/// data store hands back after reconciling with Drive — which is the *other*
/// device's record, complete with the other device's status counter.
class _DeviceGateway implements AppGateway, GenerationDeliveryGateway {
  _DeviceGateway({this.pollResult, this.retainResultValue});

  Generation? pollResult;
  Generation? retainResultValue;
  Completer<LocalSnapshot>? loading;
  LocalSnapshot? loadResult;
  int loads = 0;
  final polls = <String>[];
  final retains = <String>[];
  GoogleDriveConnection connection = const GoogleDriveConnection(
    state: GoogleDriveConnectionState.connected,
    folderName: 'Studio',
    folderId: 'folder-1',
  );

  @override
  Future<LocalSnapshot> load() {
    loads += 1;
    final pending = loading;
    if (pending != null) return pending.future;
    return Future<LocalSnapshot>.value(loadResult);
  }

  @override
  Future<Generation> pollStatus(Generation film) async {
    polls.add(film.localId);
    return pollResult ?? film;
  }

  @override
  Future<Generation> retainResult(Generation film) async {
    retains.add(film.localId);
    return retainResultValue ?? film;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The same gateway wearing the Drive interface, so the periodic
/// cross-device refresh believes the library is connected.
class _DriveDeviceGateway extends _DeviceGateway implements GoogleDriveGateway {
  @override
  GoogleDriveConnection get googleDriveConnection => connection;

  @override
  bool get supportsLocalLibrary => true;
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  group('delivery rank', () {
    test('ranks a published film above one still staged on its device', () {
      expect(_film('a', resultAsset: _driveAsset).deliveryRank, 3);
      expect(_film('a', resultAsset: _stagedAsset).deliveryRank, 2);
      expect(_film('a', resultUrl: 'https://cdn.test/a.mp4').deliveryRank, 1);
      expect(_film('a').deliveryRank, 0);
    });

    test('a Drive record whose asset is staged elsewhere is flagged', () {
      expect(
        _film('a', resultAsset: _stagedAsset).awaitsOriginDeviceUpload,
        isTrue,
      );
      expect(
        _film('a', resultAsset: _driveAsset).awaitsOriginDeviceUpload,
        isFalse,
      );
      expect(
        _film(
          'a',
          resultAsset: _stagedAsset,
          storage: LibraryStorage.local,
        ).awaitsOriginDeviceUpload,
        isFalse,
        reason: 'a local-library film is never waiting on a Drive upload',
      );
    });
  });

  group('in-memory work updates', () {
    test(
      'a delivered poll result lands despite a lower status counter',
      () async {
        // This device polled the shared record thirty times; the device that
        // actually produced the film polled it five.
        final gateway = _DeviceGateway(
          pollResult: _film(
            'shared',
            status: 'Ready',
            resultAsset: _driveAsset,
            statusCheckCount: 5,
            updatedAt: _now.subtract(const Duration(minutes: 3)),
          ),
        );
        final controller = AppController(gateway: gateway)
          ..snapshot = _snapshot(<Generation>[
            _film('shared', statusCheckCount: 30),
          ]);
        addTearDown(controller.dispose);

        await controller.pollWorking(ignoreSchedule: true);
        await _flush();

        expect(gateway.polls, <String>['shared']);
        expect(
          controller.generations.single.resultAsset,
          _driveAsset,
          reason:
              'the film another device published is ground truth, however many '
              'times this device polled the record',
        );
      },
    );

    test(
      'a delivered retention result lands despite a lower counter',
      () async {
        final gateway = _DeviceGateway(
          retainResultValue: _film(
            'shared',
            status: 'Ready',
            resultAsset: _driveAsset,
            statusCheckCount: 4,
            updatedAt: _now.subtract(const Duration(minutes: 3)),
          ),
        );
        final controller = AppController(gateway: gateway)
          ..snapshot = _snapshot(<Generation>[
            _film(
              'shared',
              status: 'Ready',
              resultUrl: 'https://cdn.test/expired.mp4',
              statusCheckCount: 30,
            ),
          ]);
        addTearDown(controller.dispose);

        await controller.pollWorking(ignoreSchedule: true);
        await _flush();
        await _flush();

        expect(gateway.retains, <String>['shared']);
        expect(controller.generations.single.resultAsset, _driveAsset);
        expect(controller.notice, 'Your film is ready and safely saved.');
      },
    );

    test('an older update never drops a delivered result asset', () async {
      final gateway = _DeviceGateway(
        pollResult: _film(
          'shared',
          status: 'Task not found',
          statusCheckCount: 99,
          updatedAt: _now.add(const Duration(hours: 1)),
        ),
      );
      final controller = AppController(gateway: gateway)
        ..snapshot = _snapshot(<Generation>[
          _film(
            'shared',
            status: 'Ready',
            resultAsset: _driveAsset,
            statusCheckCount: 5,
          ),
        ]);
      addTearDown(controller.dispose);

      await controller.pollWorking(ignoreSchedule: true);
      await _flush();

      expect(controller.generations.single.resultAsset, _driveAsset);
      expect(controller.generations.single.status, 'Ready');
    });

    test('a strictly older, no-better update is still refused', () async {
      final gateway = _DeviceGateway(
        pollResult: _film(
          'shared',
          status: 'Pending',
          statusCheckCount: 2,
          updatedAt: _now.subtract(const Duration(hours: 1)),
        ),
      );
      final controller = AppController(gateway: gateway)
        ..snapshot = _snapshot(<Generation>[
          _film(
            'shared',
            status: 'Ready',
            resultUrl: 'https://cdn.test/live.mp4',
            statusCheckCount: 9,
          ),
        ]);
      addTearDown(controller.dispose);

      await controller.pollWorking(ignoreSchedule: true);
      await _flush();

      expect(controller.generations.single.status, 'Ready');
      expect(controller.generations.single.statusCheckCount, 9);
    });
  });

  group('periodic Drive refresh', () {
    test('a superseded read still lands another device\'s film', () async {
      final gateway = _DriveDeviceGateway();
      final controller = AppController(gateway: gateway)
        ..snapshot = _snapshot(<Generation>[
          _film(
            'shared',
            status: 'Ready',
            resultUrl: 'https://cdn.test/expired.mp4',
            statusCheckCount: 30,
          ),
          _film('other', statusCheckCount: 1),
        ]);
      addTearDown(controller.dispose);

      // The Drive read is in flight...
      gateway.loading = Completer<LocalSnapshot>();
      final refresh = controller.refreshDriveLibraryForTesting();
      await _flush();
      expect(gateway.loads, 1);

      // ...while a local poll writes a new in-memory revision.
      controller.snapshot = _snapshot(<Generation>[
        _film(
          'shared',
          status: 'Ready',
          resultUrl: 'https://cdn.test/expired.mp4',
          statusCheckCount: 30,
        ),
        _film(
          'other',
          statusCheckCount: 2,
          updatedAt: _now.add(const Duration(minutes: 1)),
        ),
      ]);

      gateway.loading!.complete(
        _snapshot(<Generation>[
          _film(
            'shared',
            status: 'Ready',
            resultAsset: _driveAsset,
            statusCheckCount: 6,
          ),
          _film('other', statusCheckCount: 1),
          _film('made-elsewhere', statusCheckCount: 0),
        ]),
      );
      await refresh;
      await _flush();

      final shared = controller.generations.singleWhere(
        (item) => item.localId == 'shared',
      );
      expect(
        shared.resultAsset,
        _driveAsset,
        reason:
            'a periodic refresh that overlapped a local poll must not starve',
      );
      expect(
        controller.generations
            .singleWhere((item) => item.localId == 'other')
            .statusCheckCount,
        2,
        reason: 'the newer in-memory poll receipt survives the reconcile',
      );
      expect(
        controller.generations.map((item) => item.localId),
        containsAll(<String>['shared', 'other', 'made-elsewhere']),
      );
    });

    test('a superseded read keeps records only this device knows', () async {
      final gateway = _DriveDeviceGateway();
      final folder = LibraryFolder(
        id: 'folder-local',
        name: 'Just created',
        createdAt: _now,
        updatedAt: _now,
      );
      final controller = AppController(gateway: gateway)
        ..snapshot = _snapshot(
          <Generation>[_film('submitted-here', statusCheckCount: 0)],
          folders: <LibraryFolder>[folder],
        );
      addTearDown(controller.dispose);

      gateway.loading = Completer<LocalSnapshot>();
      final refresh = controller.refreshDriveLibraryForTesting();
      await _flush();
      controller.snapshot = _snapshot(
        <Generation>[_film('submitted-here', statusCheckCount: 1)],
        folders: <LibraryFolder>[folder],
      );
      gateway.loading!.complete(_snapshot(const <Generation>[]));
      await refresh;
      await _flush();

      expect(controller.generations.map((item) => item.localId), <String>[
        'submitted-here',
      ], reason: 'a card submitted while the read ran must not be erased');
      expect(
        controller.folders.map((item) => item.id),
        contains('folder-local'),
      );
    });
  });

  group('Drive merge ranking', () {
    test('a published film beats a staged one under clock skew', () {
      final base = _film('shared', status: 'Ready', statusCheckCount: 3);
      // Device A staged the film locally, then published it to Drive.
      final published = base.copyWith(
        resultAsset: _driveAsset,
        statusCheckCount: 4,
        updatedAt: _now.subtract(const Duration(minutes: 20)),
      );
      // Device B's clock runs ahead and it still holds the staged reference.
      final staged = base.copyWith(
        resultAsset: _stagedAsset,
        statusCheckCount: 31,
        updatedAt: _now.add(const Duration(minutes: 20)),
      );

      final merged = mergeGoogleDriveData(
        base: StoredData(generations: <Generation>[base]),
        next: StoredData(generations: <Generation>[staged]),
        remote: StoredData(generations: <Generation>[published]),
      );

      expect(merged.generations.single.resultAsset, _driveAsset);
    });

    test('a staged film still beats a record with no media at all', () {
      final base = _film('shared', statusCheckCount: 3);
      final staged = base.copyWith(
        status: 'Ready',
        resultAsset: _stagedAsset,
        statusCheckCount: 4,
        updatedAt: _now.subtract(const Duration(minutes: 20)),
      );
      final empty = base.copyWith(
        status: 'Pending',
        statusCheckCount: 40,
        updatedAt: _now.add(const Duration(minutes: 20)),
      );

      final merged = mergeGoogleDriveData(
        base: StoredData(generations: <Generation>[base]),
        next: StoredData(generations: <Generation>[staged]),
        remote: StoredData(generations: <Generation>[empty]),
      );

      expect(merged.generations.single.resultAsset, _stagedAsset);
    });
  });
}
