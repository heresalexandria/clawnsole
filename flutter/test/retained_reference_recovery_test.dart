import 'dart:async';
import 'dart:typed_data';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/generation_status.dart';
import 'package:clawnsole/core/google_drive.dart';
import 'package:clawnsole/core/google_drive_session.dart';
import 'package:clawnsole/core/media_cache_gateway.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/provider_manifest.dart';
import 'package:clawnsole/core/temporary_media_host.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _first = AssetReference(
  kind: 'drive',
  value: 'first-private-video',
  label: 'First video',
  contentType: 'video/mp4',
);
const _second = AssetReference(
  kind: 'drive',
  value: 'second-private-video',
  label: 'Second video',
  contentType: 'video/mp4',
);
const _hosting = TemporaryMediaHostStatus(
  available: true,
  activeLeases: 0,
  pendingCleanup: 0,
  backendId: 'iCloudDrive',
  readiness: TemporaryMediaReadiness.ready,
  accountScope: 'fixture-icloud-account',
  cleanupSemantics: TemporaryMediaCleanupSemantics.deferredExpiry,
  sharingAccepted: true,
);

Generation _failed({bool twoReferences = true}) => Generation(
  localId: 'old-failed-operation',
  provider: 'apipod',
  model: 'seedance-2.5-r2v',
  status: 'Error',
  error: 'The saved video file is missing.',
  prompt: 'Continue the movement in @First and @Second.',
  mode: VideoMode.i2v,
  config: GenerationConfig(
    aspectRatio: '16:9',
    duration: 5,
    resolution: 'hd',
    generateAudio: false,
    safetyTolerance: 2,
    draft: false,
    references: [
      const MediaReferenceLabel(
        label: 'First video',
        promptName: 'First',
        kind: MediaReferenceKind.video,
        source: _first,
        durationSeconds: 4,
      ),
      if (twoReferences)
        const MediaReferenceLabel(
          label: 'Second video',
          promptName: 'Second',
          kind: MediaReferenceKind.video,
          source: _second,
          durationSeconds: 4,
        ),
    ],
  ),
  createdAt: DateTime.utc(2026, 11, 9),
  updatedAt: DateTime.utc(2026, 11, 9),
);

void main() {
  test(
    'retry compatibility failure never offers to submit the unrelated composer',
    () async {
      final gateway = _RecoveryGateway()
        ..connected = true
        ..submissionError = StateError(
          'The reference video codec is unsupported.',
        );
      final app = _controller(gateway)..autoFixReferenceVideos = false;
      app.updateForm((form) => form.prompt = 'An unrelated unfinished scene.');
      await app.retryGeneration(
        gateway.snapshot.generations.single,
        confirm: (_) async => true,
      );

      expect(gateway.submissions, hasLength(1));
      expect(app.notice, contains('Turn on Normalize visual references'));
      expect(app.noticeAction, isNull);
      expect(app.noticeActionLabel, isNull);
      await app.performNoticeAction();
      expect(gateway.submissions, hasLength(1));
      expect(app.form.prompt, 'An unrelated unfinished scene.');
    },
  );

  test(
    'detached retry does not inherit the active composer live quote',
    () async {
      final gateway = _QuoteGateway()..connected = true;
      final app = _controller(gateway);
      app.updateForm((form) {
        form.prompt = 'An unrelated long scene.';
        form.durationSeconds = 12;
      });
      await app.refreshProviderEstimate();
      expect(app.currentEstimate.maximumUsd, 99);
      gateway.quote = null;

      await app.retryGeneration(
        gateway.snapshot.generations.single,
        confirm: (_) async => true,
      );
      final attempted = gateway.submissions.single.record;
      expect(attempted.config.duration, 5);
      expect(attempted.quotedCostUsdMax, isNot(99));
      expect(app.currentEstimate.maximumUsd, 99);
      expect(app.form.durationSeconds, 12);
    },
  );

  test(
    'retry joins a startup Drive renewal before reading its sources',
    () async {
      final gateway = _RecoveryGateway()
        ..renewalGate = Completer<LocalSnapshot?>();
      final original = gateway.snapshot.generations.single.copyWith(
        storage: LibraryStorage.drive,
      );
      gateway.snapshot = gateway.snapshot.copyWith(generations: [original]);
      final app = _controller(gateway);
      final startup = app.resumeGoogleDrive();
      final retry = app.retryGeneration(original, confirm: (_) async => true);
      await Future<void>.delayed(Duration.zero);
      expect(gateway.renewals, [false]);
      expect(gateway.reads, isEmpty);
      expect(gateway.submissions, isEmpty);
      gateway.renewalGate!.complete(gateway.snapshot);
      await startup;
      await retry;
      expect(gateway.renewals, [false]);
      expect(gateway.reads, [_first.value, _second.value]);
      expect(gateway.submissions.single.record.storage, LibraryStorage.drive);
    },
  );

  test(
    'simultaneous retries create one attempt without changing the composer',
    () async {
      final gateway = _RecoveryGateway()
        ..connected = true
        ..readGate = Completer<void>();
      final app = _controller(gateway);
      app.updateForm((form) {
        form.prompt = 'Keep this unfinished scene.';
        form.durationSeconds = 12;
      });
      final tabId = app.activeComposerTabId;
      final original = gateway.snapshot.generations.single;
      final retry = app.retryGeneration(original, confirm: (_) async => true);
      await gateway.readStarted.future;
      await app.retryGeneration(original, confirm: (_) async => true);
      gateway.readGate!.complete();
      await retry;

      expect(gateway.submissions, hasLength(1));
      expect(
        gateway.submissions.single.record.localId,
        isNot(original.localId),
      );
      expect(gateway.submissions.single.record.config.duration, 5);
      expect(gateway.submissions.single.record.prompt, original.prompt);
      expect(app.activeComposerTabId, tabId);
      expect(app.composerTabs, hasLength(1));
      expect(app.form.prompt, 'Keep this unfinished scene.');
      expect(app.form.durationSeconds, 12);
      expect(app.form.references, isEmpty);
    },
  );

  test('unknown submission cannot become a fresh paid retry', () async {
    final gateway = _RecoveryGateway();
    final stale = gateway.snapshot.generations.single;
    gateway.snapshot = gateway.snapshot.copyWith(
      generations: [stale.copyWith(status: submissionUnknownStatus)],
    );
    final app = _controller(gateway);
    await app.retryGeneration(stale, confirm: (_) async => true);
    expect(gateway.submissions, isEmpty);
    expect(gateway.renewals, isEmpty);
    expect(gateway.reads, isEmpty);
  });

  test(
    'retry refuses empty retained bytes before provider submission',
    () async {
      final gateway = _RecoveryGateway()
        ..connected = true
        ..emptyReads = true;
      final app = _controller(gateway);
      await app.retryGeneration(
        gateway.snapshot.generations.single,
        confirm: (_) async => true,
      );
      expect(gateway.submissions, isEmpty);
      expect(app.notice, contains('unavailable'));
      expect(app.submitting, isFalse);
    },
  );

  test(
    'retry preserves recorded media when its saved reference has changed',
    () async {
      final gateway = _RecoveryGateway(twoReferences: false)..connected = true;
      final previous = gateway.snapshot.generations.single;
      final original = previous.copyWith(
        config: previous.config.copyWith(
          references: [
            const MediaReferenceLabel(
              label: 'Recorded normalized video',
              promptName: 'First',
              referenceId: 'saved-motion',
              kind: MediaReferenceKind.video,
              source: _first,
              durationSeconds: 4,
            ),
          ],
        ),
      );
      gateway.snapshot = gateway.snapshot.copyWith(
        generations: [original],
        savedReferences: [
          SavedReference(
            id: 'saved-motion',
            name: 'New motion',
            kind: MediaReferenceKind.video,
            asset: _second,
            publicSourceUrl: 'https://cdn.example.com/replacement.mp4',
            durationSeconds: 4,
            createdAt: original.createdAt,
            updatedAt: original.updatedAt,
          ),
        ],
      );
      final app = _controller(gateway);
      await app.retryGeneration(original, confirm: (_) async => true);
      final submission = gateway.submissions.single;
      expect(gateway.reads, [_first.value]);
      expect(submission.input['reference_videos'], [
        'data:video/mp4;base64,AQID',
      ]);
      expect(submission.record.config.references!.single.source, _first);
    },
  );

  test(
    'recorded public media retries without private hosting on this platform',
    () async {
      const url = 'https://cdn.example.com/original.mp4';
      final gateway = _RecoveryGateway(twoReferences: false)
        ..hostingStatus = const TemporaryMediaHostStatus(
          available: false,
          activeLeases: 0,
          pendingCleanup: 0,
          readiness: TemporaryMediaReadiness.unsupported,
          sharingAccepted: false,
        );
      final previous = gateway.snapshot.generations.single;
      final original = previous.copyWith(
        config: previous.config.copyWith(
          references: [
            const MediaReferenceLabel(
              label: 'Hosted video',
              promptName: 'First',
              kind: MediaReferenceKind.video,
              source: _first,
              publicSourceUrl: url,
              durationSeconds: 4,
            ),
          ],
        ),
      );
      gateway.snapshot = gateway.snapshot.copyWith(generations: [original]);
      final app = _controller(gateway);
      await app.retryGeneration(original, confirm: (_) async => true);
      expect(gateway.submissions.single.input['reference_videos'], [url]);
      expect(gateway.reads, isEmpty);
      expect(gateway.renewals, isEmpty);
    },
  );

  test(
    'private references reconnect and become inputs for fresh hosting',
    () async {
      final gateway = _RecoveryGateway();
      final app = _controller(gateway);
      await app.reuse(gateway.snapshot.generations.single);

      expect(gateway.renewals, [false]);
      expect(gateway.reads, [_first.value, _second.value]);
      expect(app.form.references.map((item) => item.retained), [
        _first,
        _second,
      ]);
      expect(app.form.references.every((item) => item.asset != null), isTrue);
      expect(app.needsTemporaryMediaHosting, isTrue);
      expect(app.validate(), isNull);
      await app.submit(providerRetentionRiskAcknowledged: true);
      final submission = gateway.submissions.single;
      expect(submission.record.localId, isNot('old-failed-operation'));
      expect(submission.input['reference_videos'], [
        'data:video/mp4;base64,AQID',
        'data:video/mp4;base64,BAUG',
      ]);
      expect(gateway.hostingChecks, greaterThan(0));
      expect(gateway.interactiveCalls, 0);
    },
  );

  test(
    'an expired connected session renews once before retrying a read',
    () async {
      final gateway = _RecoveryGateway()
        ..connected = true
        ..failReads = 1;
      final app = _controller(gateway);
      await app.reuse(gateway.snapshot.generations.single);

      expect(gateway.renewals, [true]);
      expect(gateway.reads, [_first.value, _first.value, _second.value]);
      expect(app.form.references.every((item) => item.asset != null), isTrue);
      expect(gateway.interactiveCalls, 0);
    },
  );

  test(
    'cached Drive references need neither a session nor a download',
    () async {
      final gateway = _RecoveryGateway()..cached = true;
      final app = _controller(gateway);
      await app.reuse(gateway.snapshot.generations.single);

      expect(gateway.reads, isEmpty);
      expect(gateway.renewals, isEmpty);
      expect(app.form.references.every((item) => item.asset != null), isTrue);
      expect(app.needsTemporaryMediaHosting, isTrue);
    },
  );

  test('failed renewal does not attempt a private download', () async {
    final gateway = _RecoveryGateway(twoReferences: false)
      ..allowRenewal = false;
    final app = _controller(gateway);
    await app.reuse(gateway.snapshot.generations.single);

    expect(gateway.renewals, [false]);
    expect(gateway.reads, isEmpty);
    expect(app.form.references.single.asset, isNull);
    expect(app.form.references.single.retained, _first);
  });

  test('persistent read failure gets only one renewal and retry', () async {
    final gateway = _RecoveryGateway(twoReferences: false)
      ..connected = true
      ..failReads = 10;
    final app = _controller(gateway);
    await app.reuse(gateway.snapshot.generations.single);

    expect(gateway.renewals, [true]);
    expect(gateway.reads, [_first.value, _first.value]);
    expect(app.form.references.single.asset, isNull);
    expect(app.form.references.single.retained, _first);
  });

  for (final cached in [false, true]) {
    test(
      'intentional sign-out only permits already-cached media ($cached)',
      () async {
        final gateway = _RecoveryGateway()..cached = cached;
        final schedule = GoogleDriveSessionSchedule()..suspend();
        final app = _controller(gateway, schedule: schedule);
        await app.reuse(gateway.snapshot.generations.single);

        expect(gateway.renewals, isEmpty);
        expect(gateway.reads, isEmpty);
        expect(app.form.references.every((item) => item.asset != null), cached);
      },
    );
  }

  testWidgets('startup restoration remains cache-only on a connected gateway', (
    tester,
  ) async {
    final gateway = _RecoveryGateway()
      ..connected = true
      ..configured = false;
    final app = _controller(gateway, autoDispose: false);
    try {
      await app.initialize();
      await tester.pump();

      expect(gateway.renewals, isEmpty);
      expect(gateway.reads, isEmpty);
      expect(app.form.references, hasLength(2));
      expect(app.form.references.every((item) => item.asset == null), isTrue);
    } finally {
      app.dispose();
    }
  });
}

AppController _controller(
  _RecoveryGateway gateway, {
  GoogleDriveSessionSchedule? schedule,
  bool autoDispose = true,
}) {
  final client = MockClient((_) async => http.Response('{}', 503));
  addTearDown(client.close);
  final controller =
      AppController(
          gateway: gateway,
          driveSessionSchedule: schedule,
          providerCatalogClient: ProviderCatalogClient(client: client),
        )
        ..snapshot = gateway.snapshot
        ..loading = false
        ..selectedProviderId = 'apipod'
        ..selectedModelId = 'seedance-2.5-r2v'
        ..temporaryMediaHostingStatus = gateway.hostingStatus;
  if (autoDispose) addTearDown(controller.dispose);
  return controller;
}

class _RecoveryGateway
    implements
        AppGateway,
        GoogleDriveGateway,
        MediaCacheGateway,
        TemporaryMediaHostingGateway {
  _RecoveryGateway({bool twoReferences = true})
    : snapshot = LocalSnapshot(
        generations: [_failed(twoReferences: twoReferences)],
        preferences: const AppPreferences(provider: 'apipod'),
        hasApiKey: true,
        connectedProviders: const {'apipod'},
        availableProviders: const {'apipod'},
        storage: const StorageStats(path: 'memory', bytes: 0, records: 1),
      );

  LocalSnapshot snapshot;
  bool connected = false;
  bool configured = true;
  bool cached = false;
  bool allowRenewal = true;
  bool emptyReads = false;
  Object? submissionError;
  Completer<LocalSnapshot?>? renewalGate;
  Completer<void>? readGate;
  final readStarted = Completer<void>();
  TemporaryMediaHostStatus hostingStatus = _hosting;
  int failReads = 0;
  int hostingChecks = 0;
  int interactiveCalls = 0;
  final reads = <String>[];
  final renewals = <bool>[];
  final submissions = <GenerationSubmission>[];

  Uint8List bytesFor(AssetReference reference) => Uint8List.fromList(
    reference.value == _first.value ? [1, 2, 3] : [4, 5, 6],
  );

  @override
  bool get usesCompanion => false;
  @override
  bool get supportsPhotoLibrarySave => false;
  @override
  bool get supportsLocalLibrary => true;
  @override
  String get persistenceDescription => 'Memory';
  @override
  bool get supportsTemporaryMediaHosting => true;
  @override
  Future<TemporaryMediaHostStatus> temporaryMediaHostStatus() async {
    hostingChecks++;
    return hostingStatus;
  }

  @override
  GoogleDriveConnection get googleDriveConnection => GoogleDriveConnection(
    state: connected
        ? GoogleDriveConnectionState.connected
        : GoogleDriveConnectionState.disconnected,
    folderId: configured ? 'fixture-folder' : '',
    folderName: configured ? 'Clawnsole' : '',
  );
  @override
  Future<LocalSnapshot?> resumeGoogleDrive({bool force = false}) async {
    renewals.add(force);
    if (!allowRenewal) return null;
    final result = renewalGate == null ? snapshot : await renewalGate!.future;
    if (result == null) return null;
    connected = true;
    return result;
  }

  @override
  Future<LocalSnapshot> connectGoogleDrive(String folderName) async {
    interactiveCalls++;
    connected = true;
    return snapshot;
  }

  @override
  Future<Uint8List?> cachedAssetBytes(AssetReference reference) async =>
      cached ? bytesFor(reference) : null;
  @override
  Future<Uint8List> readAsset(AssetReference reference) async {
    reads.add(reference.value);
    if (!readStarted.isCompleted) readStarted.complete();
    await readGate?.future;
    if (!connected) throw StateError('Drive is disconnected.');
    if (failReads > 0) {
      failReads--;
      throw StateError('The Drive session expired.');
    }
    return emptyReads ? Uint8List(0) : bytesFor(reference);
  }

  @override
  Future<LocalSnapshot> load() async => snapshot;
  @override
  Future<LocalSnapshot> setPreferences(AppPreferences preferences) async =>
      snapshot = snapshot.copyWith(preferences: preferences);
  @override
  Future<double> getCredits() async => 100;
  @override
  Uri mediaUri(String source) => Uri.parse(source);
  @override
  Future<Generation> submit(GenerationSubmission submission) async {
    submissions.add(submission);
    if (submissionError != null) throw submissionError!;
    return submission.record.copyWith(
      status: 'Pending',
      requestId: 'new-accepted-operation',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QuoteGateway extends _RecoveryGateway implements ProviderGateway {
  CostEstimate? quote = const CostEstimate(
    minimumUsd: 99,
    maximumUsd: 99,
    basis: 'active-composer-live-quote',
  );

  @override
  Future<CostEstimate?> quoteProviderCost(
    String provider,
    String model,
    Map<String, Object?> input,
  ) async => quote;

  @override
  Future<ProviderAccountStatus> getProviderAccount(String provider) async =>
      ProviderAccountStatus(provider: provider, balance: 100);
}
