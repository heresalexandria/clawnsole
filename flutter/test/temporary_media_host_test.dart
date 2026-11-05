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
      expect((await host.status()).lastCleanupError, contains('still shared'));
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
