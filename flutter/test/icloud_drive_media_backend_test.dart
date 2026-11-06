import 'dart:io';

import 'package:clawnsole/core/asset_stream.dart';
import 'package:clawnsole/core/icloud_drive_media_backend.dart';
import 'package:clawnsole/core/icloud_reference_transport.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/secure_value_store.dart';
import 'package:clawnsole/core/temporary_media_host.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _now = DateTime.utc(2026, 11, 6);
final _scope = 'a' * 64;
final _otherScope = 'b' * 64;
final _id = 'tm_${'c' * 64}';
final _bytes = <int>[
  0,
  0,
  0,
  24,
  ...'ftypmp42'.codeUnits,
  ...List<int>.generate(244, (i) => i),
];
final _checksum = sha256.convert(_bytes).toString();
final _lease = TemporaryMediaLease(
  id: _id,
  operationId: 'test-operation',
  scopeId: _scope,
  backendId: 'iCloudDrive',
  cleanupSemantics: TemporaryMediaCleanupSemantics.deferredExpiry,
  provider: 'apipod',
  model: 'seedance-2.5',
  createdAt: _now,
  updatedAt: _now,
);
const _source = TemporaryMediaSource(
  source: 'file:///synthetic/reference.mp4',
  label: 'reference.mp4',
  kind: MediaReferenceKind.video,
  contentType: 'video/mp4',
);

String _publication(int count) {
  const template =
      r'https://cvws.icloud-content.com/B/synthetic/${f}?o=test&k=${uk}&s=signature';
  return 'https://www.icloud.com/attachment/?u=${Uri.encodeComponent(template)}'
      '&uk=synthetic%2Bbearer&f=reference.mp4&sz=$count';
}

Matcher _failure(String code) => throwsA(
  isA<ICloudReferenceException>().having((e) => e.code, 'code', code),
);
Matcher get _redactedDownloadFailure => throwsA(
  isA<ICloudReferenceException>()
      .having((e) => e.code, 'code', 'downloadUnavailable')
      .having(
        (e) => e.toString(),
        'no bearer value',
        isNot(contains('synthetic+bearer')),
      )
      .having((e) => e.toString(), 'no URL', isNot(contains('https://'))),
);

void main() {
  test(
    'status handles unsupported, unavailable identity, Drive disabled, and invalid scope',
    () async {
      for (final (state, readiness) in [
        ('unsupported', TemporaryMediaReadiness.unsupported),
        ('noAccount', TemporaryMediaReadiness.signedOut),
        ('driveUnavailable', TemporaryMediaReadiness.driveDisabled),
        ('unavailable', TemporaryMediaReadiness.unavailable),
      ]) {
        final fixture = await _Fixture.create();
        addTearDown(fixture.dispose);
        fixture.transport.state = state;
        final result = await fixture.backend.refreshAvailability();
        expect(result.readiness, readiness);
        expect(result.available, isFalse);
        expect(fixture.backend.scopeId, isNull);
      }
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      fixture.transport.scope = 'not-an-opaque-account-scope';
      expect(
        (await fixture.backend.refreshAvailability()).readiness,
        TemporaryMediaReadiness.unavailable,
      );
      final unavailable = ICloudDriveMediaBackend(
        transport: const UnavailableICloudReferenceTransport(),
        consentStore: MemorySecureValueStore(),
        stageSource: (_) => throw StateError('must not stage'),
      );
      expect(
        (await unavailable.refreshAvailability()).readiness,
        TemporaryMediaReadiness.unsupported,
      );
    },
  );

  test(
    'native error boundary removes bearer links and status failure clears scope',
    () async {
      expect(
        () => checkedICloudReferenceReply({
          'ok': false,
          'error': {
            'code': 'uploadFailed',
            'message':
                'Failed https://cvws.icloud-content.com/file?k=synthetic-bearer',
          },
        }),
        throwsA(
          isA<ICloudReferenceException>()
              .having(
                (e) => e.toString(),
                'no bearer',
                isNot(contains('synthetic-bearer')),
              )
              .having(
                (e) => e.toString(),
                'no URL',
                isNot(contains('https://')),
              ),
        ),
      );
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.backend.refreshAvailability();
      expect(f.backend.scopeId, _scope);
      f.transport.statusFailure = StateError(
        'https://cvws.icloud-content.com/file?k=synthetic-bearer',
      );
      final unavailable = await f.backend.refreshAvailability();
      expect(unavailable.readiness, TemporaryMediaReadiness.unavailable);
      expect(unavailable.message, isNot(contains('synthetic-bearer')));
      expect(f.backend.scopeId, isNull);
    },
  );

  test(
    'per-account consent blocks staging and is not inherited by another account',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.backend.refreshAvailability();
      await expectLater(
        f.backend.createCopy(_lease, _source),
        _failure('consentRequired'),
      );
      expect(f.stages, 0);
      expect(f.transport.count('prepare'), 0);
      await f.backend.acceptSharing();
      expect(await f.backend.isSharingAccepted(), isTrue);
      f.transport.scope = _otherScope;
      await f.backend.refreshAvailability();
      expect(await f.backend.isSharingAccepted(), isFalse);
      await expectLater(
        f.backend.createCopy(_lease, _source),
        _failure('accountChanged'),
      );
      expect(f.stages, 0);
      f.transport.scope = _scope;
      await f.backend.refreshAvailability();
      expect(await f.backend.isSharingAccepted(), isTrue);
    },
  );

  test(
    'account change while accepting consent does not authorize either account',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.backend.refreshAvailability();
      f.transport.scope = _otherScope;
      await expectLater(f.backend.acceptSharing(), _failure('accountChanged'));
      expect(f.store.values, isEmpty);
    },
  );

  test(
    'publishes staged bytes, disposes them, and verifies full anonymous GET before sharing',
    () async {
      final requests = <http.Request>[];
      final f = await _Fixture.create(
        client: MockClient((request) async {
          requests.add(request);
          return http.Response.bytes(
            _bytes,
            200,
            headers: {'content-type': 'video/mp4'},
          );
        }),
      );
      addTearDown(f.dispose);
      await f.accept();
      final copy = await f.backend.createCopy(_lease, _source);
      expect(f.stages, 1);
      expect(await File(f.lastStagePath!).exists(), isFalse);
      final prepare = f.transport.calls
          .lastWhere((item) => item.$1 == 'prepare')
          .$2;
      expect(prepare['leaseId'], _id);
      expect(prepare['expectedAccountScope'], _scope);
      expect(prepare['sha256'], _checksum);
      expect(prepare['bytes'], _bytes.length);
      expect(prepare['filename'], 'reference.mp4');
      final share = await f.backend.shareCopy(_lease, copy);
      expect(requests.single.method, 'GET');
      expect(requests.single.followRedirects, isFalse);
      expect(
        requests.single.headers.keys.map((key) => key.toLowerCase()),
        isNot(anyOf(contains('authorization'), contains('cookie'))),
      );
      expect(share.url, contains('k=synthetic+bearer'));
      expect(
        share.cleanupSemantics,
        TemporaryMediaCleanupSemantics.deferredExpiry,
      );
      expect(share.expiresAt, _now.add(const Duration(days: 30)));
      expect(_lease.toJson().toString(), isNot(contains('synthetic')));
      await f.backend.releaseCopy(_lease, copy);
      expect(f.transport.count('cleanup'), 1);
      expect(f.transport.receipt['sourceCleanup'], 'removedLocally');
      expect(
        f.transport.receipt['expiresAt'],
        _now.add(const Duration(days: 30)).toIso8601String(),
      );
      expect(f.transport.receipt['urlRevocation'], 'notGuaranteed');
    },
  );

  test(
    'stage is disposed after account change and preparation failure',
    () async {
      for (final changeAccount in [true, false]) {
        final f = await _Fixture.create();
        addTearDown(f.dispose);
        await f.accept();
        if (changeAccount) {
          f.afterStage = () {
            f.transport.scope = _otherScope;
          };
        } else {
          f.transport.prepareFailure = const ICloudReferenceException(
            'uploadFailed',
            'Safe failure.',
          );
        }
        await expectLater(
          f.backend.createCopy(_lease, _source),
          _failure(changeAccount ? 'accountChanged' : 'uploadFailed'),
        );
        expect(await File(f.lastStagePath!).exists(), isFalse);
        if (changeAccount) {
          expect(f.transport.count('prepare'), 0);
        }
      }
    },
  );

  test(
    'rejects media of a different class before native publication',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.accept();
      const audioSource = TemporaryMediaSource(
        source: 'synthetic',
        label: 'reference.mp4',
        kind: MediaReferenceKind.audio,
        contentType: 'video/mp4',
      );
      await expectLater(
        f.backend.createCopy(_lease, audioSource),
        _failure('unsupportedMedia'),
      );
      expect(f.transport.count('prepare'), 0);
      expect(await File(f.lastStagePath!).exists(), isFalse);
    },
  );

  test(
    'bad HTTP status, HTML, corrupt, truncated and excess bytes cannot become references',
    () async {
      final scenarios = <(List<int>, int, String)>[
        (_bytes, 302, 'video/mp4'),
        (_bytes, 200, 'text/html'),
        ([..._bytes.take(_bytes.length - 1), 255], 200, 'video/mp4'),
        (_bytes.take(_bytes.length - 1).toList(), 200, 'video/mp4'),
        ([..._bytes, 0], 200, 'video/mp4'),
      ];
      for (final (bytes, status, type) in scenarios) {
        final f = await _Fixture.create(
          client: MockClient(
            (_) async => http.Response.bytes(
              bytes,
              status,
              headers: {
                'content-type': type,
                'location': 'https://attacker.example/leak',
              },
            ),
          ),
        );
        addTearDown(f.dispose);
        await f.accept();
        final copy = await f.backend.createCopy(_lease, _source);
        await expectLater(
          f.backend.shareCopy(_lease, copy),
          _redactedDownloadFailure,
        );
      }
    },
  );

  test(
    'changed final host and exceptions containing bearer URL are rejected and redacted',
    () async {
      for (final throwURL in [false, true]) {
        final f = await _Fixture.create(
          client: MockClient((request) async {
            if (throwURL) {
              throw http.ClientException('failed ${request.url}', request.url);
            }
            return http.Response.bytes(
              _bytes,
              200,
              headers: {'content-type': 'video/mp4'},
              request: http.Request(
                'GET',
                Uri.parse('https://attacker.example/leak'),
              ),
            );
          }),
        );
        addTearDown(f.dispose);
        await f.accept();
        final copy = await f.backend.createCopy(_lease, _source);
        await expectLater(
          f.backend.shareCopy(_lease, copy),
          _redactedDownloadFailure,
        );
      }
    },
  );

  test(
    'account change during GET prevents returning a provider reference',
    () async {
      late _Fixture f;
      f = await _Fixture.create(
        client: MockClient((_) async {
          f.transport.scope = _otherScope;
          return http.Response.bytes(
            _bytes,
            200,
            headers: {'content-type': 'video/mp4'},
          );
        }),
      );
      addTearDown(f.dispose);
      await f.accept();
      final copy = await f.backend.createCopy(_lease, _source);
      await expectLater(
        f.backend.shareCopy(_lease, copy),
        _failure('accountChanged'),
      );
      await expectLater(
        f.backend.releaseCopy(_lease, copy),
        _failure('accountChanged'),
      );
      expect(f.transport.count('cleanup'), 0);
    },
  );

  test(
    'unpublished recovery resumes prepare but remains visible for cleanup',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.accept();
      f.transport.exists = true;
      f.transport.receipt['state'] = 'uploading';
      f.transport.receipt.remove('publishedUrl');
      f.transport.receipt.remove('expiresAt');
      expect(await f.backend.findCopies(_lease), isEmpty);
      final cleanupLease = _lease.copyWith(
        state: TemporaryMediaLeaseState.cleanupPending,
        updatedAt: _now,
      );
      final pending = await f.backend.findCopies(cleanupLease);
      expect(pending.single.fileId, _lease.id);
      await f.backend.createCopy(_lease, _source);
      expect(f.transport.count('prepare'), 1);
      await f.backend.releaseCopy(cleanupLease, pending.single);
      expect(f.transport.count('cleanup'), 1);
    },
  );

  test(
    'expired, mismatched, or missing publication refuses GET and cleanup IDs',
    () async {
      var gets = 0;
      final f = await _Fixture.create(
        client: MockClient((_) async {
          gets++;
          return http.Response.bytes(
            _bytes,
            200,
            headers: {'content-type': 'video/mp4'},
          );
        }),
      );
      addTearDown(f.dispose);
      await f.accept();
      final copy = await f.backend.createCopy(_lease, _source);
      f.transport.receipt['expiresAt'] = _now
          .add(const Duration(minutes: 4))
          .toIso8601String();
      await expectLater(
        f.backend.shareCopy(_lease, copy),
        _failure('publicationUnavailable'),
      );
      expect(gets, 0);
      await expectLater(
        f.backend.releaseCopy(
          _lease,
          const TemporaryMediaCopy(fileId: 'other'),
        ),
        _failure('invalidLease'),
      );
      expect(f.transport.count('cleanup'), 0);
      f.transport.exists = false;
      expect(await f.backend.findCopies(_lease), isEmpty);
    },
  );
}

class _FakeTransport implements ICloudReferenceTransport {
  String state = 'ready';
  String scope = _scope;
  bool exists = false;
  ICloudReferenceException? prepareFailure;
  Object? statusFailure;
  final calls = <(String, Map<String, Object?>)>[];
  final receipt = <String, Object?>{
    'ok': true,
    'leaseId': _id,
    'state': 'published',
    'accountScope': _scope,
    'publishedUrl': _publication(_bytes.length),
    'sha256': _checksum,
    'bytes': _bytes.length,
    'updatedAt': _now.toIso8601String(),
    'expiresAt': _now.add(const Duration(days: 30)).toIso8601String(),
    'sourceCleanup': 'pending',
    'urlRevocation': 'notGuaranteed',
  };
  int count(String method) => calls.where((item) => item.$1 == method).length;
  @override
  Future<Map<String, Object?>> call(
    String method, [
    Map<String, Object?> arguments = const {},
  ]) async {
    calls.add((method, Map.of(arguments)));
    switch (method) {
      case 'status':
        if (statusFailure != null) {
          throw statusFailure!;
        }
        return {
          'ok': true,
          'supported': state != 'unsupported',
          'state': state,
          'accountScope': scope,
          'message': 'Synthetic status',
        };
      case 'prepare':
        if (prepareFailure != null) {
          throw prepareFailure!;
        }
        exists = true;
        return Map.of(receipt);
      case 'lease':
        if (!exists) {
          throw const ICloudReferenceException('leaseNotFound', 'Missing');
        }
        return Map.of(receipt);
      case 'cleanup':
        receipt.remove('publishedUrl');
        receipt['sourceCleanup'] = 'removedLocally';
        return Map.of(receipt);
      default:
        throw StateError('Unexpected test transport method');
    }
  }

  @override
  Future<void> close() async {}
}

class _Fixture {
  _Fixture(this.root, this.transport, this.store);
  final Directory root;
  final _FakeTransport transport;
  final MemorySecureValueStore store;
  late final ICloudDriveMediaBackend backend;
  int stages = 0;
  String? lastStagePath;
  void Function()? afterStage;
  static Future<_Fixture> create({http.Client? client}) async {
    final root = await Directory.systemTemp.createTemp(
      'clawnsole-icloud-backend-test-',
    );
    final fixture = _Fixture(root, _FakeTransport(), MemorySecureValueStore());
    fixture.backend = ICloudDriveMediaBackend(
      transport: fixture.transport,
      consentStore: fixture.store,
      stageSource: (_) async {
        fixture.stages++;
        final stage = await stageAssetStream(
          Stream.value(_bytes),
          directory: root.path,
          expectedLength: _bytes.length,
          expectedSha256: _checksum,
        );
        fixture.lastStagePath = stage.path;
        fixture.afterStage?.call();
        return stage;
      },
      publicClient:
          client ??
          MockClient(
            (_) async => http.Response.bytes(
              _bytes,
              200,
              headers: {'content-type': 'video/mp4'},
            ),
          ),
      clock: () => _now,
    );
    return fixture;
  }

  Future<void> accept() async {
    await backend.refreshAvailability();
    await backend.acceptSharing();
  }

  Future<void> dispose() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  }
}
