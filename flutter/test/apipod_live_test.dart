import 'dart:convert';
import 'dart:io';

import 'package:clawnsole/core/apipod_api.dart';
import 'package:clawnsole/core/bfl_api.dart';
import 'package:clawnsole/core/generation_status.dart';
import 'package:clawnsole/core/public_media_http.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

// Resolved from https://picsum.photos/id/10/768/512 and checked with GET.
// This is a public landscape image; its URL contains no account credential.
const _imageUrl =
    'https://fastly.picsum.photos/id/10/768/512.jpg'
    '?hmac=ymRW7CNzICp4_62XcWFzB5IVh7-fEldiC9iZqxRR4MU';

void main() {
  final key = Platform.environment['APIPOD_API_KEY']?.trim() ?? '';
  final enabled = Platform.environment['RUN_APIPOD_LIVE_TESTS'] == 'true';
  final reportPath = Platform.environment['APIPOD_LIVE_REPORT'];

  test(
    'live APIPod Seedance 2.5 text, frames, and video reference delivery',
    () async {
      final client = http.Client();
      final mediaClient = PublicMediaClient();
      addTearDown(client.close);
      addTearDown(mediaClient.close);
      final api = ApipodApi(client: client);
      final report = <String, Object?>{
        'started_at': DateTime.now().toUtc().toIso8601String(),
        'jobs': <Map<String, Object?>>[],
      };
      final jobs = report['jobs']! as List<Map<String, Object?>>;
      Future<void> saveReport() async {
        if (reportPath != null && reportPath.isNotEmpty) {
          await File(reportPath).writeAsString(
            const JsonEncoder.withIndent('  ').convert(report),
            flush: true,
          );
        }
      }

      final account = await api.verify(key);
      expect(account.provider, 'apipod');
      report['account_verified'] = true;
      await saveReport();
      // ignore: avoid_print
      print('APIPod live account verified.');

      final image = await mediaClient
          .get(Uri.parse(_imageUrl))
          .timeout(const Duration(seconds: 45));
      expect(image.statusCode, 200);
      expect(image.headers['content-type'], startsWith('image/'));
      expect(image.bodyBytes.length, greaterThan(1024));

      Future<String> generate(String model, Map<String, Object?> extra) async {
        final job = <String, Object?>{'model': model, 'status': 'submitting'};
        jobs.add(job);
        await saveReport();
        // A single submit per logical job. Ambiguous responses must never
        // trigger a blind retry or another paid generation in this test.
        final receipt = await api.submit(
          key,
          model,
          <String, Object?>{
            'mode': model.endsWith('-t2v') ? 't2v' : 'i2v',
            'prompt':
                'A quiet cinematic forest landscape in soft morning light, '
                'leaves moving gently in a breeze, one continuous slow camera '
                'push, natural realistic motion, no people, no text.',
            'duration': 4,
            'resolution': 'sd',
            'aspect_ratio': model.endsWith('-i2v') ? 'auto' : '16:9',
            'generate_audio': false,
            ...extra,
          },
          operationId:
              'apipod-live-${DateTime.now().microsecondsSinceEpoch}-$model',
        );
        final id = receipt['id']! as String;
        final pollingUrl = receipt['polling_url']! as String;
        job['task_id'] = id;
        job['status'] = 'pending';
        await saveReport();
        // ignore: avoid_print
        print('APIPod live $model task=$id accepted.');
        final deadline = DateTime.now().add(const Duration(minutes: 15));
        Map<String, Object?> status = const {};
        var lastState = '';
        while (DateTime.now().isBefore(deadline)) {
          try {
            status = await api.poll(key, pollingUrl);
          } on ProviderException catch (error) {
            if (error.status != null &&
                error.status != 429 &&
                error.status! < 500) {
              rethrow;
            }
            await Future<void>.delayed(const Duration(seconds: 8));
            continue;
          }
          final state = normalizeGenerationStatus(status['status']);
          job['status'] = state;
          await saveReport();
          if (state != lastState) {
            // ignore: avoid_print
            print('APIPod live $model task=$id status=$state');
            lastState = state;
          }
          if (state == 'Ready' || isGenerationFailureStatus(state)) break;
          await Future<void>.delayed(const Duration(seconds: 8));
        }
        expect(normalizeGenerationStatus(status['status']), 'Ready');
        final outputs = status['outputs'];
        expect(outputs is List && outputs.isNotEmpty, isTrue);
        final outputUrl = (outputs! as List).first as String;
        final response = await mediaClient
            .get(Uri.parse(outputUrl))
            .timeout(const Duration(minutes: 2));
        expect(response.statusCode, 200);
        expect(response.bodyBytes.length, greaterThan(1024));
        // Default MP4 delivery must contain an ISO BMFF file-type box. This
        // rejects an HTML error page even if a CDN incorrectly returned 200.
        final prefix = latin1.decode(response.bodyBytes.take(64).toList());
        expect(prefix.contains('ftyp'), isTrue);
        job['download_bytes'] = response.bodyBytes.length;
        final cost = status['cost'];
        if (cost != null) {
          expect(cost is num && cost.isFinite && cost >= 0, isTrue);
          job['cost_usd'] = cost;
        }
        job['status'] = 'verified';
        await saveReport();
        // ignore: avoid_print
        print(
          'APIPod live $model task=$id verified cost_usd=${cost ?? 'unreported'}',
        );
        return outputUrl;
      }

      final textOutput = await generate('seedance-2.5-t2v', const {});
      await generate('seedance-2.5-i2v', const {
        'keyframes': [_imageUrl],
      });
      await generate('seedance-2.5-r2v', {
        'reference_videos': [textOutput],
        'prompt':
            'Continue the quiet forest atmosphere and gentle camera motion '
            'shown in @Video 1. Natural realistic leaves and morning light.',
      });
      report['completed_at'] = DateTime.now().toUtc().toIso8601String();
      await saveReport();
    },
    skip: !enabled || key.isEmpty
        ? 'Set RUN_APIPOD_LIVE_TESTS=true and APIPOD_API_KEY for paid live tests.'
        : false,
    timeout: const Timeout(Duration(minutes: 50)),
  );
}
