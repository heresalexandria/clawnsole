import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/core/bfl_api.dart';
import 'package:clawnsole/core/direct_gateway.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/generation_status.dart';
import 'package:clawnsole/core/google_drive_auth_base.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/web_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../tool/clawnsole_companion.dart';

/// A submission is a single operation that spans one long provider request.
/// Everything that reads the library while that request is open — the Recent
/// work refresh button, the periodic cross-device pass, a preference write —
/// must show the card as what it is: submitting. The durable record is
/// deliberately pessimistic in that window (it carries the pre-send crash
/// marker) and for part of it does not exist at all, so these tests pin both
/// the visible card and the bytes recovery depends on.
void main() {
  group('controller', () {
    test(
      'the Recent work refresh keeps an unwritten submission on screen',
      () async {
        final fixture = _ControllerFixture();
        addTearDown(fixture.dispose);

        final submission = fixture.submit();
        await fixture.untilCardAppears();
        expect(
          fixture.controller.visibleGenerations.single.status,
          'submitting',
        );

        // The gateway is still persisting references and inputs, so the store
        // it reads back does not know about this record yet.
        expect(fixture.stored, isEmpty);
        await fixture.controller.refreshGoogleDrive();

        final card = fixture.controller.visibleGenerations.single;
        expect(
          card.localId,
          fixture.submittedLocalId,
          reason:
              'the optimistic card survives a library read that predates it',
        );
        expect(card.status, 'submitting');

        fixture.release();
        await submission;
        expect(fixture.controller.visibleGenerations.single.status, 'Pending');
      },
    );

    test(
      'the Recent work refresh never shows a live submission as unknown',
      () async {
        final fixture = _ControllerFixture(persistPreSendMarker: true);
        addTearDown(fixture.dispose);

        final submission = fixture.submit();
        await fixture.untilCardAppears();
        // The provider POST is open; the durable record carries the marker a
        // crash mid-request would be recovered from.
        expect(fixture.stored.single.isSubmissionUnknown, isTrue);

        await fixture.controller.refreshGoogleDrive();

        final card = fixture.controller.visibleGenerations.single;
        expect(card.isSubmissionUnknown, isFalse);
        expect(card.status, 'submitting');
        expect(card.error, isNull);

        fixture.release();
        await submission;
        expect(fixture.controller.visibleGenerations.single.status, 'Pending');
      },
    );

    test('a failed submission still reports its durable outcome', () async {
      final fixture = _ControllerFixture(
        persistPreSendMarker: true,
        failSubmission: true,
      );
      addTearDown(fixture.dispose);

      final submission = fixture.submit();
      await fixture.untilCardAppears();
      fixture.release();
      await submission;

      // The claim is released with the call: the overlay must not outlive it
      // and paint a finished operation as still submitting.
      final card = fixture.controller.visibleGenerations.single;
      expect(card.isSubmissionUnknown, isTrue);
      expect(card.error, submissionUnknownMessage);
    });
  });

  for (final companion in [false, true]) {
    final surface = companion ? 'companion' : 'native';

    test('$surface serves a live submission as submitting', () async {
      final fixture = await _GatewayFixture.create(companion: companion);
      addTearDown(fixture.dispose);

      late LocalSnapshot duringPost;
      late List<Generation> onDisk;
      late LocalSnapshot fromAnotherProcess;
      fixture.onPost = () async {
        onDisk = await fixture.readDisk();
        duringPost = await fixture.gateway.load();
        fromAnotherProcess = await fixture.reopened().load();
        return http.Response(
          '{"id":"receipt","polling_url":"https://api.bfl.ai/v1/get_result?id=receipt"}',
          200,
        );
      };

      final accepted = await fixture.gateway.submit(_submission('operation'));

      expect(
        onDisk.single.isSubmissionUnknown,
        isTrue,
        reason: 'the pessimistic pre-send marker still reaches the disk',
      );
      expect(
        duringPost.generations.single.status,
        'submitting',
        reason: 'the process holding the request open knows better',
      );
      expect(duringPost.generations.single.error, isNull);
      expect(duringPost.generations.single.isSubmissionUnknown, isFalse);
      expect(
        fromAnotherProcess.generations.single.isSubmissionUnknown,
        isTrue,
        reason: 'only the writer un-masks its own live submission',
      );
      expect(accepted.status, 'Pending');
      expect(
        (await fixture.gateway.load()).generations.single.status,
        'Pending',
      );
    });

    test('$surface recovers a submission interrupted mid-POST', () async {
      final fixture = await _GatewayFixture.create(companion: companion);
      addTearDown(fixture.dispose);

      fixture.onPost = () async => throw const SocketException('FAKE offline');
      final result = await fixture.gateway.submit(_submission('operation'));
      expect(result.isSubmissionUnknown, isTrue);

      // Relaunch: a gateway that never held the request reads the marker back
      // exactly as a crash mid-POST would leave it.
      final relaunched = fixture.reopened();
      final recovered = (await relaunched.load()).generations.single;
      expect(recovered.isSubmissionUnknown, isTrue);
      expect(recovered.error, submissionUnknownMessage);
      expect(recovered.isWorking, isFalse);
    });
  }
}

GenerationSubmission _submission(String id) => GenerationSubmission(
  record: Generation(
    localId: id,
    status: 'submitting',
    prompt: 'a long quiet take',
    mode: VideoMode.t2v,
    config: const GenerationConfig(
      aspectRatio: '16:9',
      duration: 5,
      resolution: 'hd',
      generateAudio: true,
      safetyTolerance: 2,
      draft: false,
    ),
    createdAt: DateTime.utc(2026, 9, 6),
    updatedAt: DateTime.now().toUtc(),
  ),
  input: const {
    'prompt': 'a long quiet take',
    'duration': 5,
    'resolution': 'hd',
    'aspect_ratio': '16:9',
  },
  autoFixReferenceVideos: false,
);

/// Drives a real [AppController] over a real [WebGateway] whose submission
/// call blocks until the test releases it.
class _ControllerFixture {
  _ControllerFixture({
    this.persistPreSendMarker = false,
    this.failSubmission = false,
  }) {
    final gateway = WebGateway(
      baseUrl: Uri.parse('http://127.0.0.1:8787'),
      driveAuthorizer: _FixtureAuthorizer(),
      client: MockClient(_handle),
    );
    controller = AppController(gateway: gateway)
      ..snapshot = _snapshot(const <Generation>[])
      ..loading = false
      ..selectedProviderId = 'runway'
      ..selectedModelId = 'seedance2_5';
    controller.updateForm((form) => form.prompt = 'A quiet beach.');
  }

  final bool persistPreSendMarker;
  final bool failSubmission;
  late final AppController controller;
  final Completer<void> _gate = Completer<void>();
  List<Generation> stored = const <Generation>[];
  String? submittedLocalId;

  Future<void> submit() =>
      controller.submit(providerRetentionRiskAcknowledged: true);

  void release() => _gate.complete();

  void dispose() {
    if (!_gate.isCompleted) _gate.complete();
    controller.dispose();
  }

  /// Waits for the optimistic card the studio inserts before the gateway call.
  Future<void> untilCardAppears() async {
    for (var attempt = 0; attempt < 400; attempt += 1) {
      if (controller.generations.isNotEmpty && _gateReached) return;
      await Future<void>.delayed(Duration.zero);
    }
    fail('The submission never reached the gateway.');
  }

  bool _gateReached = false;

  Future<http.Response> _handle(http.Request request) async {
    switch (request.url.path) {
      case '/account':
        return http.Response(jsonEncode({'provider': 'runway'}), 200);
      case '/composer-tabs':
        return http.Response('{}', 200);
      case '/generations':
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final record = Generation.fromJson(
          body['record'] as Map<String, dynamic>,
        );
        submittedLocalId = record.localId;
        if (persistPreSendMarker) {
          stored = <Generation>[
            record.copyWith(
              status: submissionUnknownStatus,
              error: submissionUnknownMessage,
              updatedAt: DateTime.now().toUtc(),
            ),
          ];
        }
        _gateReached = true;
        await _gate.future;
        final settled = failSubmission
            ? stored.single
            : record.copyWith(
                status: 'Pending',
                requestId: 'receipt',
                pollingUrl: 'https://example.com/jobs/receipt',
                clearError: true,
              );
        stored = <Generation>[settled];
        return http.Response(jsonEncode({'generation': settled.toJson()}), 201);
      case '/state':
      case '/drive/refresh':
      case '/action':
        return http.Response(
          jsonEncode(<String, Object?>{..._snapshot(stored).toJson()}),
          200,
        );
      default:
        throw StateError('Unexpected request: ${request.url}');
    }
  }

  static LocalSnapshot _snapshot(List<Generation> generations) => LocalSnapshot(
    generations: generations,
    preferences: const AppPreferences(),
    hasApiKey: false,
    connectedProviders: const {'runway'},
    storage: StorageStats(
      path: 'memory',
      bytes: 0,
      records: generations.length,
    ),
  );
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

/// A native [DirectGateway] or a companion-backed [WebGateway] over one
/// history file, whose provider POST the test controls.
class _GatewayFixture {
  _GatewayFixture._(this._directory, this.file, this.gateway, this._api);

  static Future<_GatewayFixture> create({required bool companion}) async {
    final directory = await Directory.systemTemp.createTemp(
      'clawnsole-in-flight.',
    );
    final file = File('${directory.path}/history.json');
    late _GatewayFixture fixture;
    final api = BflApi(
      client: MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response('{"credits":100}', 200);
        }
        return fixture.onPost();
      }),
    );
    late AppGateway gateway;
    HttpServer? server;
    StreamSubscription<HttpRequest>? subscription;
    if (companion) {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      subscription = server.listen(
        CompanionApp(
          store: CompanionStore(file),
          api: api,
          fallbackApiKeys: {'bfl': 'FAKE_PROVIDER_KEY'},
        ).handle,
      );
      gateway = WebGateway(
        baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
      );
    } else {
      gateway = _FixtureGateway(CompanionStore(file), api);
    }
    fixture = _GatewayFixture._(directory, file, gateway, api)
      .._server = server
      .._subscription = subscription;
    return fixture;
  }

  final Directory _directory;
  final File file;
  final AppGateway gateway;
  final BflApi _api;
  HttpServer? _server;
  StreamSubscription<HttpRequest>? _subscription;

  Future<http.Response> Function() onPost = () async =>
      http.Response('{"id":"receipt","polling_url":"https://x/1"}', 200);

  /// A gateway that never held the in-flight request — the next launch, or a
  /// second device — reading the same durable bytes.
  AppGateway reopened() => _FixtureGateway(CompanionStore(file), _api);

  Future<List<Generation>> readDisk() async =>
      StoredData.decode(await file.readAsString()).generations;

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _server?.close(force: true);
    await _directory.delete(recursive: true);
  }
}

class _FixtureGateway extends DirectGateway {
  _FixtureGateway(CompanionStore store, BflApi api)
    : super(store: store, api: api);

  @override
  ActiveApiKey? activeApiKey(String provider, StoredData data) =>
      const ActiveApiKey('FAKE_PROVIDER_KEY', ApiKeySource.saved);
}
