import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clawnsole/core/generation_status.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/temporary_media_host.dart';
import 'package:clawnsole/core/temporary_media_host_io.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 11, 5);
const _local = 'data:video/mp4;base64,AQID';
const _config = GenerationConfig(
  aspectRatio: '16:9',
  duration: 5,
  resolution: 'hd',
  generateAudio: true,
  safetyTolerance: 2,
  draft: false,
  references: [
    MediaReferenceLabel(
      label: 'Original',
      kind: MediaReferenceKind.video,
      source: AssetReference(
        kind: 'local',
        value: 'original',
        label: 'Original',
        contentType: 'video/mp4',
      ),
    ),
  ],
);
Generation _record(
  String id, {
  String status = 'submitting',
  String? requestId,
  String? pollingUrl,
}) => Generation(
  localId: id,
  provider: 'apipod',
  model: 'seedance-2.5-r2v',
  prompt: 'Private prompt',
  status: status,
  mode: VideoMode.i2v,
  config: _config,
  createdAt: _now,
  updatedAt: _now,
  requestId: requestId,
  pollingUrl: pollingUrl,
);
Map<String, Object?> _input() => {
  'mode': 'i2v',
  'prompt': 'Private prompt',
  'reference_videos': [_local],
};

void main() {
  test(
    'account changes during native publication preserve old-account recovery',
    () async {
      final journal = _Journal();
      final apple = _SnapshotBackend(journal)
        ..consentedAccounts.addAll(['apple-one', 'apple-two'])
        ..createGate = Completer<void>();
      final host = TemporaryMediaHost(
        journal: journal,
        backend: apple,
        clock: () => _now,
      );
      final prepare = host.prepare(_record('one'), _input());
      final rejected = expectLater(prepare, throwsStateError);
      await apple.createStarted.future;
      apple.account = 'apple-two';
      await host.status();
      apple.createGate!.complete();
      await rejected;
      expect(apple.released, 0);
      expect(journal.leases.single.scopeId, 'apple-one');
      expect(
        journal.leases.single.state,
        TemporaryMediaLeaseState.cleanupPending,
      );
      expect((await host.status()).pendingCleanup, 1);
      apple.account = 'apple-one';
      await host.reconcile([]);
      expect(apple.released, 1);
      expect(
        journal.leases.single.state,
        TemporaryMediaLeaseState.sourceRemoved,
      );
      expect(journal.leases.single.publishedExpiresAt, apple.expiry);
    },
  );

  test(
    'overlapping legacy and terminal cleanup serialize ownership for one operation',
    () async {
      final journal = _Journal();
      final legacy = _Backend(journal);
      await TemporaryMediaHost(
        journal: journal,
        backend: legacy,
      ).prepare(_record('legacy'), _input());
      // This ID is from the original version-one lease algorithm.
      expect(
        journal.leases.single.id,
        'tm_8e1ae9569cfe7e777ab565ee77e72c71875321f856f4661ed43a47db6561a437',
      );
      final apple = _SnapshotBackend(journal)
        ..consentedAccounts.add('apple-one');
      final host = TemporaryMediaHost(
        journal: journal,
        backend: apple,
        cleanupBackends: {'googleDrive': legacy},
        clock: () => _now,
      );
      await host.prepare(_record('legacy'), _input());
      legacy.releaseGate = Completer<void>();
      final disconnect = host.releaseAll(backendId: 'googleDrive');
      await legacy.releaseStarted.future;
      final terminal = host.release('legacy');
      legacy.releaseGate!.complete();
      await Future.wait([disconnect, terminal]);
      expect(legacy.released, 1);
      expect(apple.released, 1);
      expect(journal.leases.single.backendId, 'iCloudDrive');
      expect(
        journal.leases.single.state,
        TemporaryMediaLeaseState.sourceRemoved,
      );
    },
  );

  test(
    'consent shown for an old account cannot approve the newly signed-in account',
    () async {
      final journal = _Journal();
      final apple = _SnapshotBackend(journal);
      final host = TemporaryMediaHost(journal: journal, backend: apple);
      final displayed = await host.status();
      apple.account = 'apple-two';
      await expectLater(
        host.acceptSharing(
          expectedBackendId: displayed.backendId,
          expectedAccountScope: displayed.accountScope!,
        ),
        throwsStateError,
      );
      expect(apple.consentedAccounts, isEmpty);
      await expectLater(
        host.acceptSharing(
          expectedBackendId: 'googleDrive',
          expectedAccountScope: 'apple-two',
        ),
        throwsStateError,
      );
      expect(apple.consentedAccounts, isEmpty);
    },
  );

  test(
    'recovered snapshots redact Apple bearer URLs without storing the URLs',
    () async {
      final journal = _Journal();
      final apple = _SnapshotBackend(journal)
        ..consentedAccounts.add('apple-one');
      final host = TemporaryMediaHost(
        journal: journal,
        backend: apple,
        clock: () => _now,
      );
      await host.prepare(_record('one'), _input());
      await host.release('one');
      final restarted = TemporaryMediaHost(
        journal: journal,
        backend: _Backend(journal), // active host may change on a later launch
        clock: () => _now,
      );
      await restarted.status();
      const cdn =
          'https://cvws.icloud-content.com/B/no-native-file-id?secret=value';
      const attachment =
          'https://www.icloud.com/attachment/?u=public-capability';
      expect(
        restarted.redactText('source $cdn and $attachment'),
        'source «temporary media URL» and «temporary media URL»',
      );
      const unrelated = 'https://icloud-content.com.example.net/ordinary';
      expect(restarted.redactText(unrelated), unrelated);
      final receipt = jsonEncode(
        journal.leases.map((lease) => lease.toJson()).toList(),
      );
      expect(receipt, isNot(contains(cdn)));
      expect(receipt, isNot(contains(attachment)));
    },
  );

  test(
    'local recovery metadata redacts expired Apple links without checking an unavailable host',
    () async {
      final journal = _Journal()
        ..leases = [
          TemporaryMediaLease(
            id: 'retained-publication',
            operationId: 'old-operation',
            scopeId: 'old-account',
            backendId: 'iCloudDrive',
            cleanupSemantics: TemporaryMediaCleanupSemantics.deferredExpiry,
            provider: 'apipod',
            model: 'seedance-2.5-r2v',
            createdAt: _now.subtract(const Duration(days: 40)),
            updatedAt: _now.subtract(const Duration(days: 40)),
            state: TemporaryMediaLeaseState.sourceRemoved,
            publicationAttemptedAt: _now.subtract(const Duration(days: 40)),
            publishedExpiresAt: _now.subtract(const Duration(days: 10)),
            sourceRemovedAt: _now.subtract(const Duration(days: 40)),
          ),
        ];
      final unavailable = _UnavailableMetadataBackend(journal);
      final host = TemporaryMediaHost(
        journal: journal,
        backend: unavailable,
        clock: () => _now,
      );
      const link = 'https://cvws.icloud-content.com/B/old?bearer=secret';
      expect(host.redactText(link), link);
      await host.loadRecoveryMetadata();
      expect(host.redactText(link), '«temporary media URL»');
      expect(unavailable.readinessChecks, 0);
      expect(journal.leases, hasLength(1)); // Loading does not mutate receipts.
      expect(unavailable.created, 0);
      expect(unavailable.released, 0);
    },
  );

  test(
    'confirmed pre-publication failure removes the source intent without inventing a snapshot',
    () async {
      final journal = _Journal();
      final apple = _UnpublishedSnapshotBackend(journal)
        ..consentedAccounts.add('apple-one');
      final host = TemporaryMediaHost(
        journal: journal,
        backend: apple,
        clock: () => _now,
      );
      await expectLater(
        host.prepare(_record('one'), _input()),
        throwsStateError,
      );
      expect(apple.released, 1);
      expect(journal.leases, isEmpty);
      final status = await host.status();
      expect(status.publishedSnapshots, 0);
      expect(status.pendingCleanup, 0);
    },
  );

  test(
    'an absent native receipt cannot erase an already recorded publication',
    () async {
      final journal = _Journal();
      final original = _SnapshotBackend(journal)
        ..consentedAccounts.add('apple-one');
      await TemporaryMediaHost(
        journal: journal,
        backend: original,
        clock: () => _now,
      ).prepare(_record('one'), _input());
      final missingReceipt = _UnpublishedSnapshotBackend(journal);
      final restarted = TemporaryMediaHost(
        journal: journal,
        backend: missingReceipt,
        clock: () => _now,
      );
      await restarted.release('one');
      expect(
        journal.leases.single.state,
        TemporaryMediaLeaseState.sourceRemoved,
      );
      expect(journal.leases.single.publishedExpiresAt, original.expiry);
      expect((await restarted.status()).publishedSnapshots, 1);
    },
  );

  test(
    'unavailable active host never falls back to legacy Google Drive',
    () async {
      final journal = _Journal();
      final legacy = _Backend(journal);
      final apple = _SnapshotBackend(journal)
        ..account = null
        ..readiness = TemporaryMediaReadiness.signedOut;
      final host = TemporaryMediaHost(
        journal: journal,
        backend: apple,
        cleanupBackends: {'googleDrive': legacy},
      );
      final status = await host.status();
      expect(status.available, isFalse);
      expect(status.backendId, 'iCloudDrive');
      expect(status.readiness, TemporaryMediaReadiness.signedOut);
      expect(status.sharingAccepted, isFalse);
      await expectLater(
        host.prepare(_record('one'), _input()),
        throwsStateError,
      );
      expect(legacy.created, 0);
      expect(apple.created, 0);
      expect(journal.leases, isEmpty);
    },
  );

  test(
    'device/account consent is enforced before any publication and sending',
    () async {
      final journal = _Journal();
      final apple = _SnapshotBackend(journal);
      final host = TemporaryMediaHost(
        journal: journal,
        backend: apple,
        clock: () => _now,
      );
      expect((await host.status()).available, isTrue);
      expect((await host.status()).sharingAccepted, isFalse);
      await expectLater(
        host.prepare(_record('one'), _input()),
        throwsStateError,
      );
      expect(apple.created, 0);
      await host.acceptSharing(
        expectedBackendId: 'iCloudDrive',
        expectedAccountScope: 'apple-one',
      );
      expect((await host.status()).sharingAccepted, isTrue);
      await host.prepare(_record('one'), _input());
      apple.consentedAccounts.clear();
      await expectLater(host.beforeSend('one'), throwsStateError);
      expect(journal.leases.single.state, TemporaryMediaLeaseState.prepared);
      // Consent withdrawal must not prevent source-copy cleanup.
      await host.release('one');
      expect(apple.copies, isEmpty);
      expect(
        journal.leases.single.state,
        TemporaryMediaLeaseState.sourceRemoved,
      );
    },
  );

  test(
    'fresh account checks reject a switch before send and defer old-account cleanup',
    () async {
      final journal = _Journal();
      final apple = _SnapshotBackend(journal)
        ..consentedAccounts.addAll(['apple-one', 'apple-two']);
      final host = TemporaryMediaHost(
        journal: journal,
        backend: apple,
        clock: () => _now,
      );
      await host.prepare(_record('one'), _input());
      final checks = apple.readinessChecks;
      apple.account = 'apple-two';
      await expectLater(host.beforeSend('one'), throwsStateError);
      expect(apple.readinessChecks, greaterThan(checks));
      await host.release('one');
      expect(apple.released, 0);
      expect((await host.status()).pendingCleanup, 1);
      apple.account = 'apple-one';
      await host.reconcile([]);
      expect(apple.released, 1);
      expect((await host.status()).pendingCleanup, 0);
      expect((await host.status()).publishedSnapshots, 1);
      await host.prepare(_record('two'), _input());
      await host.beforeSend('two');
      apple.scopeId = 'changed-by-native-account-notification';
      expect(() => host.assertCanSend('two'), throwsStateError);
    },
  );

  test(
    'legacy cleanup routes by backend even when both accounts have the same scope',
    () async {
      final journal = _Journal();
      final legacy = _Backend(journal);
      await TemporaryMediaHost(
        journal: journal,
        backend: legacy,
      ).prepare(_record('legacy'), _input());
      final apple = _SnapshotBackend(journal)
        ..account = legacy.scopeId
        ..consentedAccounts.add(legacy.scopeId!);
      final host = TemporaryMediaHost(
        journal: journal,
        backend: apple,
        cleanupBackends: {'googleDrive': legacy},
        clock: () => _now,
      );
      await host.prepare(_record('apple'), _input());
      await host.releaseAll(backendId: 'googleDrive');
      expect(legacy.released, 1);
      expect(apple.released, 0);
      expect(journal.leases.single.backendId, 'iCloudDrive');
      expect(journal.leases.single.state, TemporaryMediaLeaseState.prepared);
      await host.release('apple');
      expect(
        journal.leases.single.state,
        TemporaryMediaLeaseState.sourceRemoved,
      );
    },
  );

  test(
    'source removal keeps URL-free snapshot metadata until the reported expiry',
    () async {
      var time = _now;
      final journal = _Journal();
      final apple = _SnapshotBackend(journal)
        ..consentedAccounts.add('apple-one');
      final host = TemporaryMediaHost(
        journal: journal,
        backend: apple,
        clock: () => time,
      );
      final input = await host.prepare(_record('one'), _input());
      await host.release('one');
      expect(apple.copies, isEmpty);
      expect(apple.snapshots, hasLength(1));
      final restarted = TemporaryMediaHost(
        journal: journal,
        backend: apple,
        clock: () => time,
      );
      final status = await restarted.status();
      expect(status.activeLeases, 0);
      expect(status.pendingCleanup, 0);
      expect(status.publishedSnapshots, 1);
      expect(status.latestPublishedExpiry, apple.expiry);
      expect(
        status.cleanupSemantics,
        TemporaryMediaCleanupSemantics.deferredExpiry,
      );
      expect(
        TemporaryMediaHostStatus.fromJson(status.toJson()).toJson(),
        status.toJson(),
      );
      final receipt = jsonEncode(
        journal.leases.map((lease) => lease.toJson()).toList(),
      );
      expect(
        receipt,
        isNot(contains((input['reference_videos'] as List).single)),
      );
      await restarted.reconcile([]);
      expect(apple.released, 1);
      time = apple.expiry!.add(const Duration(seconds: 1));
      expect((await restarted.status()).publishedSnapshots, 0);
      expect(journal.leases, isEmpty);
      // Pruning metadata is not a remote revocation operation.
      expect(apple.snapshots, hasLength(1));
    },
  );

  test(
    'publication during create with a lost response recovers its expiry before cleanup',
    () async {
      final journal = _Journal();
      final apple = _SnapshotBackend(journal)
        ..consentedAccounts.add('apple-one')
        ..loseCreateResponse = true;
      final host = TemporaryMediaHost(
        journal: journal,
        backend: apple,
        clock: () => _now,
      );
      await expectLater(
        host.prepare(_record('one'), _input()),
        throwsStateError,
      );
      expect(apple.snapshots, hasLength(1));
      expect(apple.copies, isEmpty);
      expect(journal.leases.single.publishedExpiresAt, apple.expiry);
      expect(
        journal.leases.single.state,
        TemporaryMediaLeaseState.sourceRemoved,
      );
      expect((await host.status()).publishedSnapshotsUnknownExpiry, 0);
    },
  );

  test(
    'unknown-expiry publications remain visible; expiry never drops pending cleanup',
    () async {
      var time = _now;
      final journal = _Journal();
      final apple = _SnapshotBackend(journal)
        ..consentedAccounts.add('apple-one')
        ..expiry = null;
      final host = TemporaryMediaHost(
        journal: journal,
        backend: apple,
        clock: () => time,
      );
      await host.prepare(_record('unknown'), _input());
      await host.release('unknown');
      time = _now.add(const Duration(days: 90));
      expect((await host.status()).publishedSnapshotsUnknownExpiry, 1);
      expect(journal.leases, hasLength(1));

      time = _now;
      apple.expiry = _now.add(const Duration(days: 30));
      await host.prepare(_record('pending'), _input());
      apple.failure = 'release';
      await host.release('pending');
      time = _now.add(const Duration(days: 90));
      final status = await host.status();
      expect(status.pendingCleanup, 1);
      expect(status.publishedSnapshots, 1); // only the unknown-expiry snapshot
      expect(journal.leases, hasLength(2));
    },
  );

  test(
    'version-one journal migration preserves legacy ownership and writes version two',
    () async {
      final directory = await Directory.systemTemp.createTemp('media-v1.');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/leases.json');
      final legacy =
          TemporaryMediaLease(
              id: 'legacy',
              operationId: 'operation',
              scopeId: 'drive-library',
              provider: 'apipod',
              model: 'seedance',
              createdAt: _now,
              updatedAt: _now,
              fileId: 'owned-copy',
              permissionId: 'public-reader',
            ).toJson()
            ..remove('backendId')
            ..remove('cleanupSemantics');
      await file.writeAsString(
        jsonEncode({
          'version': 1,
          'leases': [legacy],
        }),
      );
      final journal = FileTemporaryMediaLeaseJournal(() async => file);
      final migrated = await journal.read();
      expect(migrated.single.backendId, 'googleDrive');
      expect(migrated.single.permissionId, 'public-reader');
      await journal.write(migrated);
      final next = jsonDecode(await file.readAsString()) as Map;
      expect(next['version'], 2);
      expect((next['leases'] as List).single['backendId'], 'googleDrive');
      await file.writeAsString(
        jsonEncode({
          'version': 2,
          'leases': [legacy],
        }),
      );
      await expectLater(journal.read(), throwsFormatException);
    },
  );

  test(
    'final synchronous send check rejects disconnect during journal or receipt persistence',
    () async {
      final journal = _Journal();
      final backend = _Backend(journal);
      final host = TemporaryMediaHost(journal: journal, backend: backend);
      await host.prepare(_record('writing'), _input());
      journal.submittingGate = Completer<void>();
      final beforeSend = host.beforeSend('writing');
      final rejected = expectLater(beforeSend, throwsStateError);
      await journal.submittingStarted.future;
      host.suspend();
      journal.submittingGate!.complete();
      await rejected;
      await host.releaseAll();
      host.resume();
      await host.prepare(_record('receipt'), _input());
      await host.beforeSend('receipt');
      expect(() => host.assertCanSend('receipt'), returnsNormally);
      // Simulate disconnect while the gateway awaits its separate record write.
      host.suspend();
      await host.releaseAll();
      expect(() => host.assertCanSend('receipt'), throwsStateError);
      host.resume();
      expect(() => host.assertCanSend('receipt'), throwsStateError);
    },
  );

  test(
    'disconnect suspension drains uploads and rejects new or revoked hosted sends',
    () async {
      final journal = _Journal();
      final backend = _Backend(journal)..createGate = Completer<void>();
      final host = TemporaryMediaHost(journal: journal, backend: backend);
      final preparing = host.prepare(_record('uploading'), _input());
      final rejected = expectLater(preparing, throwsStateError);
      await backend.createStarted.future;
      host.suspend();
      final draining = host.releaseAll();
      await expectLater(
        host.prepare(_record('new'), _input()),
        throwsStateError,
      );
      expect((await host.status()).available, isFalse);
      backend.createGate!.complete();
      await rejected;
      await draining;
      expect(backend.publicFiles, isEmpty);
      expect(backend.copies, isEmpty);
      expect(journal.leases, isEmpty);
      host.resume();
      await host.prepare(_record('revoked'), _input());
      await host.release('revoked');
      await expectLater(host.beforeSend('revoked'), throwsStateError);
      expect(journal.leases, isEmpty);
    },
  );

  test(
    'intent and uploaded identifiers are durable before sharing; originals stay private',
    () async {
      final journal = _Journal();
      final backend = _Backend(journal);
      final host = TemporaryMediaHost(
        journal: journal,
        backend: backend,
        clock: () => _now,
      );
      final input = _input();
      final prepared = await host.prepare(_record('one'), input);
      final url = (prepared['reference_videos'] as List).single;
      expect(url, startsWith('https://media.example.com/'));
      expect(input['reference_videos'], [_local]);
      expect(_config.references!.single.source!.value, 'original');
      expect(backend.created, 1);
      expect(backend.sources.single.retained!.value, 'original');
      expect(journal.leases.single.state, TemporaryMediaLeaseState.prepared);
      final persisted = jsonEncode(
        journal.leases.map((item) => item.toJson()).toList(),
      );
      expect(persisted, isNot(contains(_local)));
      expect(persisted, isNot(contains(url)));
      expect(persisted, isNot(contains('Private prompt')));
      expect(host.hostedUrlsFor('one'), {url});
      expect(
        host.redactResponse({
          'result': [url, 'echo $url'],
        }),
        {
          'result': ['«temporary media URL»', 'echo «temporary media URL»'],
        },
      );
      final restarted = TemporaryMediaHost(journal: journal, backend: backend);
      await restarted.status();
      final fileId = journal.leases.single.fileId!;
      expect(
        restarted.redactText('https://drive.google.com/uc?id=$fileId'),
        '«temporary media URL»',
      );
      expect(
        restarted.redactText(
          'https://drive.google.com/uc?id=$fileId\\u0026export=download).',
        ),
        '«temporary media URL»',
      );
    },
  );

  test(
    'public URLs bypass Drive and local input gives an actionable disconnected error',
    () async {
      final journal = _Journal();
      final backend = _Backend(journal)..scopeId = null;
      final host = TemporaryMediaHost(journal: journal, backend: backend);
      final input = {
        'reference_videos': ['https://cdn.example.com/video.mp4'],
      };
      expect(await host.prepare(_record('public'), input), input);
      expect(journal.reads, 0);
      await expectLater(
        host.prepare(_record('private'), _input()),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Connect Google Drive'),
          ),
        ),
      );
      expect(journal.leases, isEmpty);
      expect(backend.created, 0);
    },
  );

  test(
    'all canonical media slots are replaced without changing timestamps or prompts',
    () async {
      final journal = _Journal();
      final backend = _Backend(journal);
      final host = TemporaryMediaHost(journal: journal, backend: backend);
      final input = <String, Object?>{
        'mode': 'v2v',
        'prompt': _local,
        'keyframes': [
          [0.0, 'data:image/png;base64,AQID'],
          [5.0, 'https://cdn.example.com/end.png'],
        ],
        'reference_images': ['data:image/png;base64,BAUG'],
        'reference_videos': [_local],
        'reference_audios': ['data:audio/wav;base64,BwgJ'],
        'start_video': 'file:///private/source.mp4',
      };
      final prepared = await host.prepare(_record('slots'), input);
      expect(prepared['prompt'], _local);
      expect((prepared['keyframes'] as List).first, [
        0.0,
        startsWith('https://media.example.com/'),
      ]);
      expect((prepared['keyframes'] as List).last, [
        5.0,
        'https://cdn.example.com/end.png',
      ]);
      expect(backend.created, 5);
      expect(input['start_video'], 'file:///private/source.mp4');
      expect(
        temporaryMediaSlots(_config, {
          'mode': 'draft_enhance',
          'draft_task_id': 'task',
          'reference_videos': [_local],
        }),
        isEmpty,
      );
    },
  );

  test(
    'concurrent generations own separate copies, repeated slots share one per generation',
    () async {
      final journal = _Journal();
      final backend = _Backend(journal);
      final host = TemporaryMediaHost(journal: journal, backend: backend);
      await Future.wait([
        host.prepare(_record('a'), _input()),
        host.prepare(_record('b'), _input()),
      ]);
      expect(backend.created, 2);
      await host.beforeSend('a');
      await host.beforeSend('b');
      await host.release('a');
      expect(journal.leases.single.operationId, 'b');
      expect(backend.publicFiles, {journal.leases.single.fileId});
      await host.reconcile([], activeOperations: {'b'});
      expect(journal.leases, hasLength(1));
      await host.releaseAll();
      expect(backend.publicFiles, isEmpty);
      expect(journal.leases, isEmpty);

      final duplicateConfig = _config.copyWith(references: []);
      final record = _record('duplicates').copyWith(config: duplicateConfig);
      await host.prepare(record, {
        'reference_videos': [_local, _local],
      });
      expect(journal.leases, hasLength(1));
    },
  );

  test(
    'lost upload or permission responses are recovered and revoked before a failed prepare returns',
    () async {
      for (final failure in ['upload', 'share']) {
        final journal = _Journal();
        final backend = _Backend(journal)..failure = failure;
        final host = TemporaryMediaHost(journal: journal, backend: backend);
        await expectLater(
          host.prepare(_record(failure), _input()),
          throwsStateError,
        );
        expect(journal.leases, isEmpty);
        expect(backend.copies, isEmpty);
        expect(backend.publicFiles, isEmpty);
      }
    },
  );

  test(
    'journal failure prevents uploading and never silently discards malformed state',
    () async {
      final journal = _Journal()..failWrite = true;
      final backend = _Backend(journal);
      final host = TemporaryMediaHost(journal: journal, backend: backend);
      await expectLater(host.prepare(_record('a'), _input()), throwsStateError);
      expect(backend.created, 0);
      expect(backend.publicFiles, isEmpty);
    },
  );

  test(
    'cleanup failure is durable, scope-bound and retried after reconnection',
    () async {
      final journal = _Journal();
      final backend = _Backend(journal);
      final host = TemporaryMediaHost(journal: journal, backend: backend);
      await host.prepare(_record('a'), _input());
      backend.failure = 'release';
      await host.release('a');
      expect((await host.status()).pendingCleanup, 1);
      expect(
        (await host.status()).lastCleanupError,
        contains('source-copy cleanup is pending'),
      );
      final restarted = TemporaryMediaHost(journal: journal, backend: backend);
      backend
        ..scopeId = 'different-account'
        ..failure = null;
      await restarted.reconcile([]);
      expect(backend.publicFiles, hasLength(1));
      backend.scopeId = 'library-one';
      await restarted.onConnection([]);
      expect(backend.publicFiles, isEmpty);
      expect((await restarted.status()).pendingCleanup, 0);
    },
  );

  test(
    'restart revokes unused prepared media but retains ambiguous submissions for 24h',
    () async {
      final journal = _Journal();
      final backend = _Backend(journal);
      final host = TemporaryMediaHost(
        journal: journal,
        backend: backend,
        clock: () => _now,
      );
      await host.prepare(_record('prepared'), _input());
      await host.prepare(_record('ambiguous'), _input());
      await host.beforeSend('ambiguous');
      var clock = _now.add(const Duration(hours: 23));
      final restarted = TemporaryMediaHost(
        journal: journal,
        backend: backend,
        clock: () => clock,
      );
      await restarted.reconcile([
        _record('ambiguous', status: submissionUnknownStatus),
      ]);
      expect(journal.leases.single.operationId, 'ambiguous');
      clock = _now.add(const Duration(hours: 24));
      await restarted.reconcile([
        _record('ambiguous', status: submissionUnknownStatus),
      ]);
      expect(journal.leases, isEmpty);
    },
  );

  test(
    'deleted-history accepted jobs retain polling metadata and clean up on terminal result',
    () async {
      final journal = _Journal();
      final backend = _Backend(journal);
      final host = TemporaryMediaHost(
        journal: journal,
        backend: backend,
        clock: () => _now,
      );
      await host.prepare(_record('a'), _input());
      await host.beforeSend('a');
      await host.accepted(
        _record(
          'a',
          status: 'Pending',
          requestId: 'task-123',
          pollingUrl: 'https://api.example.com/task-123',
        ),
      );
      final restarted = TemporaryMediaHost(
        journal: journal,
        backend: backend,
        clock: () => _now.add(const Duration(hours: 1)),
      );
      await restarted.reconcile(
        [],
        poll: (lease) async {
          expect(lease.provider, 'apipod');
          expect(lease.requestId, 'task-123');
          expect(lease.pollingUrl, 'https://api.example.com/task-123');
          return _record('a', status: 'Ready');
        },
      );
      expect(backend.publicFiles, isEmpty);
      expect(journal.leases, isEmpty);
    },
  );

  test(
    'known active jobs survive orphan deadline, confirmed failures revoke, cleanup joins once',
    () async {
      final journal = _Journal();
      final backend = _Backend(journal);
      final host = TemporaryMediaHost(
        journal: journal,
        backend: backend,
        clock: () => _now,
      );
      await host.prepare(_record('a'), _input());
      await host.beforeSend('a');
      final restarted = TemporaryMediaHost(
        journal: journal,
        backend: backend,
        clock: () => _now.add(const Duration(days: 2)),
      );
      await restarted.reconcile([
        _record(
          'a',
          status: 'Pending',
          pollingUrl: 'https://api.example.com/task',
        ),
      ]);
      expect(journal.leases, hasLength(1));
      backend.releaseGate = Completer<void>();
      final first = restarted.release('a');
      final second = restarted.release('a');
      await backend.releaseStarted.future;
      backend.releaseGate!.complete();
      await Future.wait([first, second]);
      expect(backend.released, 1);
      expect(journal.leases, isEmpty);
      await restarted.prepare(_record('failed'), _input());
      await restarted.reconcile([_record('failed', status: 'Failed')]);
      expect(journal.leases, isEmpty);
    },
  );

  test(
    'file journal is atomic, mode0600, rejects corruption without replacing it',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'temporary-media-journal.',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/leases.json');
      final journal = FileTemporaryMediaLeaseJournal(() async => file);
      final lease = TemporaryMediaLease(
        id: 'lease',
        operationId: 'operation',
        scopeId: 'library',
        provider: 'apipod',
        model: 'seedance',
        createdAt: _now,
        updatedAt: _now,
      );
      await journal.write([lease]);
      expect((await journal.read()).single.toJson(), lease.toJson());
      if (!Platform.isWindows) expect((await file.stat()).mode & 511, 384);
      expect((await directory.list().toList()).map((entry) => entry.path), [
        file.path,
      ]);
      await file.writeAsString('{"version":99,"leases":[]}');
      await expectLater(journal.read(), throwsFormatException);
      expect(await file.readAsString(), contains('99'));
    },
  );
}

class _Journal implements TemporaryMediaLeaseJournal {
  List<TemporaryMediaLease> leases = [];
  int reads = 0;
  bool failWrite = false;
  Completer<void>? submittingGate;
  final submittingStarted = Completer<void>();
  @override
  Future<List<TemporaryMediaLease>> read() async {
    reads++;
    return List.of(leases);
  }

  @override
  Future<void> write(List<TemporaryMediaLease> next) async {
    if (failWrite) throw StateError('Journal unavailable');
    if (submittingGate != null &&
        next.any((item) => item.state == TemporaryMediaLeaseState.submitting)) {
      if (!submittingStarted.isCompleted) submittingStarted.complete();
      await submittingGate!.future;
    }
    leases = next
        .map((item) => TemporaryMediaLease.fromJson(item.toJson()))
        .toList();
  }
}

class _Backend implements TemporaryMediaBackend {
  _Backend(this.journal);
  final _Journal journal;
  @override
  String? scopeId = 'library-one';
  String? failure;
  int created = 0;
  int released = 0;
  final copies = <String, String>{};
  final publicFiles = <String>{};
  final sources = <TemporaryMediaSource>[];
  Completer<void>? releaseGate;
  final releaseStarted = Completer<void>();
  Completer<void>? createGate;
  final createStarted = Completer<void>();
  @override
  Future<List<TemporaryMediaCopy>> findCopies(
    TemporaryMediaLease lease,
  ) async => [
    for (final entry in copies.entries)
      if (entry.value == lease.id) TemporaryMediaCopy(fileId: entry.key),
  ];
  @override
  Future<TemporaryMediaCopy> createCopy(
    TemporaryMediaLease lease,
    TemporaryMediaSource source,
  ) async {
    expect(
      journal.leases.any((item) => item.id == lease.id),
      isTrue,
      reason: 'intent precedes upload',
    );
    expect(lease.scopeId, scopeId);
    sources.add(source);
    final id = 'copy-${++created}';
    copies[id] = lease.id;
    if (!createStarted.isCompleted) createStarted.complete();
    await createGate?.future;
    if (failure == 'upload') throw StateError('Upload response lost');
    return TemporaryMediaCopy(fileId: id);
  }

  @override
  Future<TemporaryMediaShare> shareCopy(
    TemporaryMediaLease lease,
    TemporaryMediaCopy copy,
  ) async {
    expect(
      journal.leases.firstWhere((item) => item.id == lease.id).fileId,
      copy.fileId,
      reason: 'copy identifier precedes permission creation',
    );
    publicFiles.add(copy.fileId);
    if (failure == 'share') throw StateError('Permission response lost');
    return TemporaryMediaShare(
      permissionId: 'anyone',
      url: 'https://media.example.com/${copy.fileId}',
    );
  }

  @override
  Future<void> releaseCopy(
    TemporaryMediaLease lease,
    TemporaryMediaCopy copy,
  ) async {
    expect(lease.scopeId, scopeId);
    expect(
      journal.leases.firstWhere((item) => item.id == lease.id).state,
      TemporaryMediaLeaseState.cleanupPending,
    );
    if (!releaseStarted.isCompleted) releaseStarted.complete();
    await releaseGate?.future;
    if (failure == 'release') throw StateError('Offline');
    released++;
    publicFiles.remove(copy.fileId);
    copies.remove(copy.fileId);
  }
}

class _SnapshotBackend extends _Backend
    implements TemporaryMediaBackendCapabilities, TemporaryMediaConsentBackend {
  _SnapshotBackend(super.journal);

  @override
  String get backendId => 'iCloudDrive';
  String? account = 'apple-one';
  TemporaryMediaReadiness readiness = TemporaryMediaReadiness.ready;
  int readinessChecks = 0;
  final consentedAccounts = <String>{};
  DateTime? expiry = _now.add(const Duration(days: 30));
  bool loseCreateResponse = false;
  final snapshots = <String, TemporaryMediaCopy>{};

  @override
  Future<TemporaryMediaBackendAvailability> refreshAvailability() async {
    readinessChecks++;
    scopeId = account;
    return TemporaryMediaBackendAvailability(
      backendId: backendId,
      readiness: readiness,
      accountScope: account,
      message: readiness == TemporaryMediaReadiness.signedOut
          ? 'Sign in to your Apple Account and enable iCloud Drive.'
          : null,
      cleanupSemantics: TemporaryMediaCleanupSemantics.deferredExpiry,
    );
  }

  @override
  Future<bool> isSharingAccepted() async => consentedAccounts.contains(account);

  @override
  Future<void> acceptSharing() async => consentedAccounts.add(account!);

  @override
  Future<TemporaryMediaCopy> createCopy(
    TemporaryMediaLease lease,
    TemporaryMediaSource source,
  ) async {
    expect(
      journal.leases
          .singleWhere((item) => item.id == lease.id)
          .publicationAttemptedAt,
      isNotNull,
    );
    final copy = await super.createCopy(lease, source);
    final published = TemporaryMediaCopy(
      fileId: copy.fileId,
      publishedAt: _now,
      expiresAt: expiry,
    );
    snapshots[copy.fileId] = published;
    if (loseCreateResponse) {
      throw StateError('Native publication response lost');
    }
    return published;
  }

  @override
  Future<List<TemporaryMediaCopy>> findCopies(
    TemporaryMediaLease lease,
  ) async => [
    for (final copy in await super.findCopies(lease))
      snapshots[copy.fileId] ?? copy,
  ];

  @override
  Future<TemporaryMediaShare> shareCopy(
    TemporaryMediaLease lease,
    TemporaryMediaCopy copy,
  ) async => TemporaryMediaShare(
    url: 'https://media.example.com/${copy.fileId}',
    publishedAt: _now,
    expiresAt: expiry,
    cleanupSemantics: TemporaryMediaCleanupSemantics.deferredExpiry,
  );
}

class _UnavailableMetadataBackend extends _Backend
    implements TemporaryMediaBackendCapabilities {
  _UnavailableMetadataBackend(super.journal);
  int readinessChecks = 0;
  @override
  String get backendId => 'iCloudDrive';
  @override
  Future<TemporaryMediaBackendAvailability> refreshAvailability() async {
    readinessChecks++;
    throw StateError('Native hosting must not be consulted for redaction.');
  }
}

class _UnpublishedSnapshotBackend extends _SnapshotBackend {
  _UnpublishedSnapshotBackend(super.journal);

  @override
  Future<TemporaryMediaCopy> createCopy(
    TemporaryMediaLease lease,
    TemporaryMediaSource source,
  ) async => throw StateError('Source was rejected before native publication.');

  @override
  Future<List<TemporaryMediaCopy>> findCopies(
    TemporaryMediaLease lease,
  ) async => lease.state == TemporaryMediaLeaseState.cleanupPending
      ? [TemporaryMediaCopy(fileId: lease.id, publicationAttempted: false)]
      : const [];

  @override
  Future<void> releaseCopy(
    TemporaryMediaLease lease,
    TemporaryMediaCopy copy,
  ) async {
    released++;
  }
}
