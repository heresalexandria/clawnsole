import 'dart:convert';
import 'dart:io';

import 'package:clawnsole/core/api_transcript.dart';
import 'package:clawnsole/core/bfl_api.dart';
import 'package:clawnsole/core/direct_gateway.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/hybrid_data_store.dart';
import 'package:clawnsole/core/krea_api.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/provider_api.dart';
import 'package:clawnsole/core/secure_value_store.dart';
import 'package:clawnsole/core/settings_vault_data_store.dart';
import 'package:clawnsole/core/web_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../tool/clawnsole_companion.dart';

void main() {
  for (final companion in <bool>[false, true]) {
    final surface = companion ? 'the companion' : 'the native gateway';
    test('$surface records a submit and its polls for the film', () async {
      final harness = await _Harness.create(companion: companion);
      final film = await harness.gateway.submit(_submission());
      expect(film.requestId, 'job-1');
      await harness.gateway.poll(film);
      await harness.gateway.poll(film);
      await harness.settle();

      final records = await (harness.gateway as ApiTranscriptGateway)
          .readApiRequests('film-b');
      expect(
        records.map((record) => record.sequence),
        List<int>.generate(records.length, (index) => index + 1),
        reason: 'sequences are 1-based and contiguous',
      );
      expect(records.every((record) => record.provider == 'krea'), isTrue);

      final submits = records.where(
        (record) => record.purpose == ApiRequestPurpose.submit,
      );
      final polls = records.where(
        (record) => record.purpose == ApiRequestPurpose.poll,
      );
      expect(submits, hasLength(1));
      expect(polls, hasLength(2));
      expect(submits.single.method, 'POST');
      expect(submits.single.statusCode, 200);
      expect(
        submits.single.requestBody,
        contains('"prompt": "A slow dolly past a warm lantern."'),
      );
      expect(submits.single.requestHeaders['Authorization'], redactedValue);
      expect(submits.single.responseBody, contains('"job_id": "job-1"'));
      expect(polls.first.method, 'GET');
      expect(polls.last.responseBody, contains('"status"'));

      // Balance readings taken around a submit ride along under their own
      // label, so a wrong realized cost can be explained.
      expect(
        records.where((record) => record.purpose == ApiRequestPurpose.balance),
        isNotEmpty,
      );

      // Nothing recorded may carry a credential or a frame's bytes.
      final transcript = renderTranscript(records, film: film);
      expect(transcript, isNot(contains('test-key')));
      expect(transcript, contains('film      film-b'));
      expect(transcript, contains('#1 · balance · krea'));

      // A film nobody submitted has an honest, empty transcript.
      expect(
        await (harness.gateway as ApiTranscriptGateway).readApiRequests(
          'film-never-sent',
        ),
        isEmpty,
      );

      await harness.gateway.deleteGeneration('film-b');
      expect(
        await (harness.gateway as ApiTranscriptGateway).readApiRequests(
          'film-b',
        ),
        isEmpty,
        reason: 'the transcript is deleted with its film',
      );
      await harness.dispose();
    });
  }

  test('the companion route serves what the renderer asks for', () async {
    final harness = await _Harness.create(companion: true);
    await harness.gateway.submit(_submission());
    await harness.settle();

    final direct = await http.Client().get(
      Uri.parse('${harness.baseUrl}/generations/film-b/api-requests'),
    );
    expect(direct.statusCode, 200);
    final payload = jsonDecode(direct.body) as Map<String, Object?>;
    final raw = payload['requests']! as List<Object?>;
    expect(raw, isNotEmpty);
    expect((raw.first! as Map<Object?, Object?>)['operationId'], 'film-b');

    final missing = await http.Client().get(
      Uri.parse('${harness.baseUrl}/generations/film-nope/api-requests'),
    );
    expect(missing.statusCode, 200);
    expect(
      (jsonDecode(missing.body) as Map<String, Object?>)['requests'],
      isEmpty,
    );
    await harness.dispose();
  });
}

/// A gateway wired to a fake Krea, on either surface.
class _Harness {
  _Harness({
    required this.gateway,
    required this.directory,
    required this.baseUrl,
    required this.close,
  });

  static Future<_Harness> create({required bool companion}) async {
    final directory = await Directory.systemTemp.createTemp(
      'clawnsole-transcript-gateway.',
    );
    // The production chain: the vault holds the credential, the hybrid
    // store owns the library, and the local file store keeps both the
    // library and its transcript sidecar.
    final local = CompanionStore(File('${directory.path}/clawnsole.json'));
    final hybrid = HybridDataStore(local: local);
    final store = SettingsVaultDataStore(
      delegate: hybrid,
      secureStore: MemorySecureValueStore(),
    );
    await store.write(
      const StoredData(apiKeys: <String, String>{'krea': 'test-key'}),
    );
    var polls = 0;
    final router = ProviderApiRouter(
      krea: KreaApi(
        client: MockClient((request) async {
          if (request.method == 'POST') {
            return http.Response('{"job_id":"job-1"}', 200);
          }
          if (request.url.path.contains('/jobs/')) {
            polls += 1;
            return http.Response(
              jsonEncode(<String, Object?>{
                'id': 'job-1',
                'status': polls > 1 ? 'processing' : 'queued',
              }),
              200,
            );
          }
          // The account reading taken around a submit.
          return http.Response('{"jobs":[]}', 200);
        }),
      ),
    );
    if (!companion) {
      return _Harness(
        gateway: DirectGateway(store: store, providerRouter: router),
        directory: directory,
        baseUrl: '',
        close: () async {},
      );
    }
    final application = CompanionApp.hybrid(
      store: CompanionHybridStore(hybrid, vault: store),
      api: BflApi(),
      providerRouter: router,
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen(application.handle);
    final baseUrl = 'http://127.0.0.1:${server.port}';
    return _Harness(
      gateway: WebGateway(baseUrl: Uri.parse(baseUrl)),
      directory: directory,
      baseUrl: baseUrl,
      close: () async {
        await subscription.cancel();
        await server.close(force: true);
      },
    );
  }

  final AppGateway gateway;
  final Directory directory;
  final String baseUrl;
  final Future<void> Function() close;

  /// Records are appended behind the provider call, so a reader waits a beat.
  Future<void> settle() async {
    for (var attempt = 0; attempt < 20; attempt += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<void> dispose() async {
    await close();
    await directory.delete(recursive: true);
  }
}

GenerationSubmission _submission() {
  final now = DateTime.utc(2026, 9, 7);
  return GenerationSubmission(
    record: Generation(
      localId: 'film-b',
      provider: 'krea',
      model: 'bytedance/seedance-2-5',
      status: 'submitting',
      prompt: 'A slow dolly past a warm lantern.',
      mode: VideoMode.t2v,
      config: const GenerationConfig(
        aspectRatio: '16:9',
        duration: 5,
        resolution: 'sd',
        generateAudio: false,
        safetyTolerance: 2,
        draft: false,
      ),
      createdAt: now,
      updatedAt: now,
    ),
    input: const <String, Object?>{
      'mode': 't2v',
      'prompt': 'A slow dolly past a warm lantern.',
      'duration': 5,
      'resolution': 'sd',
      'aspect_ratio': '16:9',
    },
    autoFixReferenceVideos: false,
  );
}
