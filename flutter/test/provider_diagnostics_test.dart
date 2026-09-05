import 'dart:convert';

import 'package:clawnsole/core/generation_status.dart';
import 'package:clawnsole/core/generation_timing.dart';
import 'package:clawnsole/core/google_drive.dart';
import 'package:clawnsole/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final raw = <String, Object?>{
    'id': 'task-123',
    'status': 'Error',
    'progress_percentage': 42,
    'state': {
      'created_at': '2026-09-05T12:00:00Z',
      'maybe_result': {
        'maybe_successfully_completed_at': '2026-09-05T12:01:00Z',
        'url': 'https://example.com/result?X-Amz-Signature=FAKE_SIGNATURE',
      },
      'authorization': 'Bearer FAKE_AUTHORIZATION',
      'input': 'data:video/mp4;base64,RkFLRV9JTlBVVF9CWVRFUw==',
      'new_unknown_field': {'private': 'FAKE_UNKNOWN_SECRET'},
    },
    'details': [
      {'message': 'Retry https://example.com/private?token=FAKE_QUERY_TOKEN'},
      {'error': 'Authorization: Bearer FAKE_BEARER_TOKEN'},
      {'message': 'api_key="FAKE_API_KEY"'},
      {'message': 'data:image/png;base64,RkFLRV9NRURJQV9CWVRFUw=='},
      {
        'detail': jsonEncode({
          'status': 'Failed',
          'access_token': 'FAKE_NESTED_TOKEN',
        }),
      },
    ],
    'billing': {'actual_cost': .25, 'currency': 'USD'},
  };
  final markers = [
    'FAKE_SIGNATURE',
    'FAKE_AUTHORIZATION',
    'RkFLRV9JTlBVVF9CWVRFUw==',
    'FAKE_UNKNOWN_SECRET',
    'FAKE_QUERY_TOKEN',
    'FAKE_BEARER_TOKEN',
    'FAKE_API_KEY',
    'RkFLRV9NRURJQV9CWVRFUw==',
    'FAKE_NESTED_TOKEN',
  ];

  void expectSafe(String value) {
    for (final marker in markers) {
      expect(value, isNot(contains(marker)), reason: marker);
    }
    expect(value, contains('task-123'));
    expect(value, contains('progress_percentage'));
    expect(value, contains('actual_cost'));
  }

  test(
    'new and JSON-encoded diagnostics omit private payloads and retain useful metadata',
    () {
      for (final payload in [raw, jsonEncode(raw)]) {
        final safe = compactProviderResponse(payload);
        expectSafe(safe);
        expect(jsonDecode(safe), isA<Map<String, Object?>>());
        expect(compactProviderResponse(safe), safe);
      }
    },
  );

  test(
    'legacy diagnostics sanitize on read and on portable history serialization',
    () {
      final generation = Generation.fromJson({
        'localId': 'diagnostic-fixture',
        'status': 'Ready',
        'prompt': 'fixture',
        'mode': 't2v',
        'config': <String, Object?>{},
        'createdAt': '2026-09-05T11:00:00Z',
        'updatedAt': '2026-09-05T13:00:00Z',
        'lastProviderResponse': jsonEncode(raw),
        'error': 'failure token=FAKE_ERROR_TOKEN',
        'lastCheckError': 'Check failed Bearer FAKE_CHECK_TOKEN',
        'resultRetentionError':
            'Download https://example.com/file?sig=FAKE_RETAIN_TOKEN',
      });
      expectSafe(generation.lastProviderResponse!);
      expect(generation.error, isNot(contains('FAKE_')));
      expect(generation.lastCheckError, isNot(contains('FAKE_')));
      expect(generation.resultRetentionError, isNot(contains('FAKE_')));
      expect(
        observedGenerationDuration(generation),
        const Duration(minutes: 1),
      );
      // A directly constructed or copied record must be safe at write time too.
      final unsanitized = generation.copyWith(
        lastProviderResponse: jsonEncode(raw),
        error: 'failure token=FAKE_ERROR_TOKEN',
        lastCheckError: 'Check failed Bearer FAKE_CHECK_TOKEN',
        resultRetentionError:
            'Download https://example.com/file?sig=FAKE_RETAIN_TOKEN',
      );
      final portable = googleDrivePortableData(
        StoredData(generations: [unsanitized]),
      ).encode();
      expectSafe(portable);
      expect(portable, isNot(contains('FAKE_')));
    },
  );

  test(
    'malformed legacy JSON fails closed instead of exposing truncated inputs',
    () {
      final safe = compactProviderResponse('{"input":"FAKE_PRIVATE_FRAGMENT');
      expect(safe, isNot(contains('FAKE_PRIVATE_FRAGMENT')));
      expect(safe, contains('omitted'));
    },
  );

  test('ordinary safe historical JSON retains its spelling and formatting', () {
    const safe = '{"detail":"try again"}';
    expect(compactProviderResponse(safe), safe);
  });

  test('plain-text diagnostics redact URLs, credentials and inline media', () {
    final safe = compactProviderResponse(
      'failure token=FAKE_TOKEN Authorization: Bearer FAKE_BEARER https://example.com/a?sig=FAKE_SIGNATURE data:video/mp4;base64,RkFLRV9JTlBVVF9CWVRFUw==',
    );
    expect(safe, isNot(contains('FAKE_')));
    expect(safe, isNot(contains('RkFLRV')));
    expect(safe, contains('failure'));
  });

  test('standalone redactions remain stable on repeated reads and writes', () {
    for (final raw in [
      'https://example.com/file?signature=FAKE_SIGNED_QUERY',
      'Bearer FAKE_CREDENTIAL',
      'data:image/png;base64,RkFLRV9NRURJQV9CWVRFUw==',
    ]) {
      final safe = compactProviderResponse(raw);
      expect(compactProviderResponse(safe), safe);
    }
  });
}
