import 'dart:convert';
import 'dart:io';

import 'package:clawnsole/core/api_transcript.dart';
import 'package:clawnsole/core/api_transcript_store_io.dart';
import 'package:clawnsole/core/local_data_store_io.dart';
import 'package:clawnsole/core/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('recorder', () {
    test('redacts every credential-bearing header', () async {
      final record = await _record(
        request: http.Request('GET', Uri.parse('https://api.test/v1/jobs'))
          ..headers.addAll(<String, String>{
            'Authorization': 'Bearer sk-live-1234',
            'x-api-key': 'secret-key-value',
            'api-key': 'another-secret',
            'Cookie': 'session=abc',
            'X-Krea-Token': 'tok-99',
            'X-Client-Secret': 'shh',
            'Accept': 'application/json',
          }),
        response: http.Response(
          '{}',
          200,
          headers: <String, String>{
            'content-type': 'application/json',
            'set-cookie': 'session=abc',
            'x-request-id': 'req-1',
          },
        ),
      );
      for (final name in <String>[
        'Authorization',
        'x-api-key',
        'api-key',
        'Cookie',
        'X-Krea-Token',
        'X-Client-Secret',
      ]) {
        expect(
          record.requestHeaders[name],
          redactedValue,
          reason: '$name must never reach a transcript',
        );
      }
      expect(record.requestHeaders['Accept'], 'application/json');
      expect(record.responseHeaders['set-cookie'], redactedValue);
      expect(record.responseHeaders['x-request-id'], 'req-1');
      expect(record.toTranscriptText(), isNot(contains('sk-live-1234')));
      expect(record.toTranscriptText(), isNot(contains('tok-99')));
    });

    test('redacts credential query parameters but keeps the rest', () async {
      final record = await _record(
        request: http.Request(
          'GET',
          Uri.parse(
            'https://api.test/v1/jobs?key=sk-live-1234&access_token=t0k'
            '&id=job-7&pretty=true',
          ),
        ),
        response: http.Response('{}', 200),
      );
      expect(record.url, contains('key=«redacted»'));
      expect(record.url, contains('access_token=«redacted»'));
      // The marker is written as-is, never re-encoded, so rows and copies
      // read it as a word.
      expect(record.url, isNot(contains('%C2%AB')));
      expect(record.url, contains('id=job-7'));
      expect(record.url, contains('pretty=true'));
      expect(record.url, isNot(contains('sk-live-1234')));
      expect(record.url, isNot(contains('t0k')));
    });

    test(
      'replaces base64 and data-URI payloads with size placeholders',
      () async {
        final frame = base64Encode(List<int>.filled(48 * 1024, 7));
        final record = await _record(
          request: http.Request('POST', Uri.parse('https://api.test/v1/submit'))
            ..headers['content-type'] = 'application/json'
            ..body = jsonEncode(<String, Object?>{
              'prompt': 'A slow dolly past a warm lantern.',
              'image': frame,
              'reference': 'data:image/png;base64,$frame',
              'api_key': 'sk-live-1234',
            }),
          response: http.Response('{}', 200),
        );
        final body = record.requestBody!;
        expect(body, contains('A slow dolly past a warm lantern.'));
        expect(body, isNot(contains(frame.substring(0, 64))));
        expect(body, contains('«base64 '));
        expect(body, contains('«image/png '));
        expect(body, contains(redactedValue));
        expect(body, isNot(contains('sk-live-1234')));
      },
    );

    test('describes multipart parts instead of carrying their bytes', () async {
      final request =
          http.MultipartRequest('POST', Uri.parse('https://api.test/v1/upload'))
            ..fields['prompt'] = 'A quiet street.'
            ..fields['api_key'] = 'sk-live-1234'
            ..files.add(
              http.MultipartFile.fromBytes(
                'image',
                List<int>.filled(1300 * 1024, 3),
                filename: 'frame.png',
              ),
            );
      final record = await _record(
        request: request,
        response: http.Response('{"id":"1"}', 200),
      );
      final body = record.requestBody!;
      expect(body, contains('«multipart/form-data»'));
      expect(body, contains('field prompt = A quiet street.'));
      expect(body, contains('field api_key = $redactedValue'));
      expect(
        body,
        contains('file image = frame.png «application/octet-stream 1.3 MB»'),
      );
      expect(body, isNot(contains('sk-live-1234')));
    });

    test('pretty-prints JSON responses and describes media ones', () async {
      final json = await _record(
        request: http.Request('GET', Uri.parse('https://api.test/v1/jobs/1')),
        response: http.Response(
          '{"status":"Ready","result":{"url":"https://cdn.test/a.mp4"}}',
          200,
          headers: <String, String>{'content-type': 'application/json'},
        ),
      );
      expect(
        json.responseBody,
        '{\n'
        '  "status": "Ready",\n'
        '  "result": {\n'
        '    "url": "https://cdn.test/a.mp4"\n'
        '  }\n'
        '}',
      );

      final media = await _record(
        request: http.Request('GET', Uri.parse('https://cdn.test/a.mp4')),
        response: http.Response.bytes(
          List<int>.filled(2048, 1),
          200,
          headers: <String, String>{'content-type': 'video/mp4'},
        ),
      );
      expect(media.responseBody, '«video/mp4 2 KB»');
      expect(
        _lastBytes,
        hasLength(2048),
        reason: 'the film itself must still reach its caller untouched',
      );
    });

    test('caps a long body and says how much was dropped', () async {
      // Prose, not an alphanumeric run: a bare base64 body is deliberately
      // replaced by a placeholder rather than capped.
      final long =
          ('A slow dolly past a warm lantern. ' *
                  (maxRecordedResponseBodyBytes ~/ 33 + 200))
              .substring(0, maxRecordedResponseBodyBytes + 5000);
      final record = await _record(
        request: http.Request('GET', Uri.parse('https://api.test/v1/jobs/1')),
        response: http.Response(
          long,
          200,
          headers: <String, String>{'content-type': 'text/plain'},
        ),
      );
      expect(record.responseBody!.length, maxRecordedResponseBodyBytes);
      expect(record.responseTruncatedBytes, 5000);
      expect(record.toTranscriptText(), contains('truncated'));
      expect(record.toTranscriptText(), contains('5 KB more was not kept'));
    });

    test('records a transport failure with no response', () async {
      Object? thrown;
      try {
        await _record(
          request: http.Request('GET', Uri.parse('https://api.test/v1/jobs')),
          failure: const SocketException('Connection refused'),
        );
      } on Object catch (error) {
        thrown = error;
      }
      expect(thrown, isA<SocketException>());
      final record = _lastRecord!;
      expect(record.statusCode, isNull);
      expect(record.error, contains('Connection refused'));
      expect(record.statusLabel, 'failed');
      expect(record.toTranscriptText(), contains('transport error'));
    });

    test('records only the calls made inside an operation scope', () async {
      final sink = _Sink();
      final client = recordingProviderClient(
        MockClient((request) async => http.Response('{"ok":true}', 200)),
      );
      // A key verification or a model listing belongs to no film.
      await client.get(Uri.parse('https://api.test/v1/credits'));
      expect(sink.records, isEmpty);
      expect(ApiTranscriptScope.current, isNull);

      await ApiTranscriptScope.run(
        () => client.get(Uri.parse('https://api.test/v1/jobs/1')),
        sink: sink,
        operationId: 'film-b',
        provider: 'artcraft',
        purpose: ApiRequestPurpose.poll,
      );
      expect(sink.records, hasLength(1));
      expect(sink.records.single.operationId, 'film-b');
      expect(sink.records.single.purpose, ApiRequestPurpose.poll);

      // An operation with no id — a film that has none — records nothing.
      await ApiTranscriptScope.run(
        () => client.get(Uri.parse('https://api.test/v1/jobs/2')),
        sink: sink,
        operationId: '',
        provider: 'artcraft',
        purpose: ApiRequestPurpose.poll,
      );
      expect(sink.records, hasLength(1));
    });

    test('overlapping operations never take each other\'s records', () async {
      final sink = _Sink();
      final client = recordingProviderClient(
        MockClient((request) async {
          // Let the other operation's call start before this one answers.
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return http.Response('{"ok":true}', 200);
        }),
      );
      Future<void> call(String film) => ApiTranscriptScope.run(
        () => client.get(Uri.parse('https://api.test/v1/jobs/$film')),
        sink: sink,
        operationId: film,
        provider: 'artcraft',
        purpose: ApiRequestPurpose.poll,
      );
      await Future.wait(<Future<void>>[call('film-a'), call('film-b')]);
      expect(
        <String, String>{
          for (final record in sink.records) record.operationId: record.url,
        },
        <String, String>{
          'film-a': 'https://api.test/v1/jobs/film-a',
          'film-b': 'https://api.test/v1/jobs/film-b',
        },
      );
    });

    test('renderTranscript names the film and what it withholds', () async {
      final record = await _record(
        request: http.Request('GET', Uri.parse('https://api.test/v1/jobs/1'))
          ..headers['authorization'] = 'Bearer sk-live-1234',
        response: http.Response(
          '{"status":"Ready"}',
          200,
          headers: <String, String>{'content-type': 'application/json'},
        ),
        purpose: ApiRequestPurpose.poll,
      );
      final text = renderTranscript(<ApiRequestRecord>[
        record.copyWith(sequence: 4),
      ], film: _film());
      expect(text, startsWith('Clawnsole API transcript'));
      expect(text, contains('film      film-b'));
      expect(text, contains('provider  artcraft · seedance_2p5'));
      expect(text, contains('status    Ready'));
      expect(text, contains('requestId req-90210'));
      expect(text, contains('requests  1'));
      expect(text, contains('Credentials are redacted'));
      expect(text, contains('── #4 · poll · artcraft'));
      expect(text, contains('GET https://api.test/v1/jobs/1'));
      expect(text, contains('authorization: $redactedValue'));
      expect(text, contains('"status": "Ready"'));
      expect(text, isNot(contains('sk-live-1234')));
    });

    test('a record survives a JSON round trip', () async {
      final record = await _record(
        request: http.Request('POST', Uri.parse('https://api.test/v1/submit'))
          ..body = '{"prompt":"hi"}',
        response: http.Response('{"id":"1"}', 200),
      );
      final restored = ApiRequestRecord.fromJson(
        jsonDecode(jsonEncode(record.copyWith(sequence: 3).toJson()))
            as Map<String, Object?>,
      );
      expect(restored.sequence, 3);
      expect(restored.purpose, record.purpose);
      expect(restored.method, 'POST');
      expect(restored.statusCode, 200);
      expect(restored.requestBody, record.requestBody);
      expect(restored.at, record.at);
    });
  });

  group('store', () {
    test('appends, numbers, reads back, and deletes one film', () async {
      final store = await _fileStore();
      await store.appendApiRequest(_stub('film-a', 'https://api.test/1'));
      await store.appendApiRequest(_stub('film-a', 'https://api.test/2'));
      await store.appendApiRequest(_stub('film-b', 'https://api.test/3'));

      final first = await store.readApiRequests('film-a');
      expect(first.map((record) => record.sequence), <int>[1, 2]);
      expect(first.map((record) => record.url), <String>[
        'https://api.test/1',
        'https://api.test/2',
      ]);
      expect(await store.readApiRequests('film-b'), hasLength(1));
      expect(await store.readApiRequests('film-missing'), isEmpty);

      await store.deleteApiRequests('film-a');
      expect(await store.readApiRequests('film-a'), isEmpty);
      expect(await store.readApiRequests('film-b'), hasLength(1));
    });

    test('keeps the newest records once the per-film cap is passed', () async {
      final store = await _fileStore();
      for (var index = 0; index < maxApiRequestsPerFilm + 12; index += 1) {
        await store.appendApiRequest(
          _stub('film-a', 'https://api.test/$index'),
        );
      }
      final records = await store.readApiRequests('film-a');
      expect(records, hasLength(maxApiRequestsPerFilm));
      expect(records.first.sequence, 13);
      expect(records.last.sequence, maxApiRequestsPerFilm + 12);
      expect(records.last.url, 'https://api.test/211');
    });

    test('an unusable operation id still gets its own file', () async {
      final store = await _fileStore();
      await store.appendApiRequest(_stub('../escape', 'https://api.test/1'));
      await store.appendApiRequest(_stub('..', 'https://api.test/2'));
      expect(await store.readApiRequests('../escape'), hasLength(1));
      expect(await store.readApiRequests('..'), hasLength(1));
      expect(ApiTranscriptFileStore.fileStem('../escape'), startsWith('op-'));
      expect(
        ApiTranscriptFileStore.fileStem('a1b2-c3'),
        'a1b2-c3',
        reason: 'ordinary local ids stay readable on disk',
      );
    });

    test(
      'prune drops orphans and spares transcripts still being written',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'clawnsole-transcript-prune.',
        );
        addTearDown(() => directory.delete(recursive: true));
        final store = ApiTranscriptFileStore(() async => directory);
        await store.appendApiRequest(_stub('film-kept', 'https://api.test/1'));
        await store.appendApiRequest(_stub('film-old', 'https://api.test/2'));
        await store.appendApiRequest(_stub('film-new', 'https://api.test/3'));
        // A submission still in flight has an id no snapshot knows yet.
        File(
          '${directory.path}/${ApiTranscriptFileStore.fileStem('film-old')}'
          '.jsonl',
        ).setLastModifiedSync(
          DateTime.now().subtract(const Duration(hours: 3)),
        );

        await store.pruneApiTranscripts(<String>{'film-kept'});
        expect(await store.readApiRequests('film-kept'), hasLength(1));
        expect(await store.readApiRequests('film-old'), isEmpty);
        expect(
          await store.readApiRequests('film-new'),
          hasLength(1),
          reason:
              'a transcript written moments ago is still in its grace window',
        );
      },
    );

    test('the local library keeps transcripts out of its JSON and drops '
        'them with the film', () async {
      final directory = await Directory.systemTemp.createTemp(
        'clawnsole-transcript-store.',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = LocalDataStore(documentsDirectory: directory);
      final kept = _film(localId: 'film-kept');
      final removed = _film(localId: 'film-gone');
      await store.write(StoredData(generations: <Generation>[kept, removed]));
      await store.appendApiRequest(_stub('film-kept', 'https://api.test/1'));
      await store.appendApiRequest(_stub('film-gone', 'https://api.test/2'));
      expect(await store.readApiRequests('film-gone'), hasLength(1));

      // The transcript is a sidecar: never inside clawnsole.json.
      final data = await File(
        '${directory.path}${Platform.pathSeparator}Clawnsole'
        '${Platform.pathSeparator}${LocalDataStore.dataFileName}',
      ).readAsString();
      expect(data, isNot(contains('api.test')));

      await store.write(StoredData(generations: <Generation>[kept]));
      await store.deleteApiRequests('film-gone');
      expect(await store.readApiRequests('film-gone'), isEmpty);
      expect(await store.readApiRequests('film-kept'), hasLength(1));

      await store.delete();
      expect(await store.readApiRequests('film-kept'), isEmpty);
    });
  });
}

/// The record the last [_record] call produced, so a thrown request can be
/// inspected after its exception is caught.
ApiRequestRecord? _lastRecord;

/// The bytes the caller actually received, so a pass-through media stream
/// can be proven intact.
List<int> _lastBytes = const <int>[];

class _Sink implements ApiTranscriptSink {
  final List<ApiRequestRecord> records = <ApiRequestRecord>[];

  @override
  void addApiRequest(ApiRequestRecord record) => records.add(record);
}

/// Drives one request through the recording client inside a scope, the way
/// a provider adapter's call does.
Future<ApiRequestRecord> _record({
  required http.BaseRequest request,
  http.Response? response,
  Object? failure,
  ApiRequestPurpose purpose = ApiRequestPurpose.submit,
}) async {
  final sink = _Sink();
  final client = recordingProviderClient(
    MockClient((_) async {
      if (failure != null) throw failure;
      return response!;
    }),
  );
  _lastRecord = null;
  try {
    await ApiTranscriptScope.run(
      () async {
        final streamed = await client.send(request);
        _lastBytes = await streamed.stream.toBytes();
      },
      sink: sink,
      operationId: 'film-b',
      provider: 'artcraft',
      purpose: purpose,
    );
  } finally {
    if (sink.records.isNotEmpty) _lastRecord = sink.records.single;
  }
  return sink.records.single;
}

Future<ApiTranscriptFileStore> _fileStore() async {
  final directory = await Directory.systemTemp.createTemp(
    'clawnsole-transcripts.',
  );
  addTearDown(() => directory.delete(recursive: true));
  return ApiTranscriptFileStore(() async => directory);
}

ApiRequestRecord _stub(String operationId, String url) => ApiRequestRecord(
  id: url,
  operationId: operationId,
  at: DateTime.utc(2026, 9, 7, 18, 22, 41),
  provider: 'artcraft',
  purpose: ApiRequestPurpose.poll,
  method: 'GET',
  url: url,
  statusCode: 200,
);

Generation _film({String localId = 'film-b'}) {
  final now = DateTime.utc(2026, 9, 1, 21);
  return Generation(
    localId: localId,
    provider: 'artcraft',
    model: 'seedance_2p5',
    status: 'Ready',
    prompt: 'A slow dolly past a warm lantern.',
    mode: VideoMode.t2v,
    config: const GenerationConfig(
      aspectRatio: '16:9',
      duration: 8,
      resolution: 'hd',
      generateAudio: true,
      safetyTolerance: 2,
      draft: false,
    ),
    requestId: 'req-90210',
    createdAt: now,
    updatedAt: now,
  );
}
