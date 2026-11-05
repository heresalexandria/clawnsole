import 'dart:convert';
import 'dart:io';

import 'package:clawnsole/core/apipod_api.dart';
import 'package:clawnsole/core/apipod_pricing.dart';
import 'package:clawnsole/core/bfl_api.dart';
import 'package:clawnsole/core/generation_status.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/public_media_http.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

// Resolved from https://picsum.photos/id/10/768/512 and checked with GET.
// This is a public landscape image; its URL contains no account credential.
const _imageUrl =
    'https://fastly.picsum.photos/id/10/768/512.jpg'
    '?hmac=ymRW7CNzICp4_62XcWFzB5IVh7-fEldiC9iZqxRR4MU';

// The expanded suite uses the cheapest documented text inputs across eight
// families. At the audited prices this totals $1.328, below its $3 ceiling.
const _catalogCases = <String, Map<String, Object?>>{
  'seedance-2.0-mini-t2v': {'duration': 4, 'resolution': 'sd'},
  'veo3-1-lite': {'duration': 8, 'resolution': 'hd'},
  'grok-imagine-1.5-fast': {'duration': 6, 'resolution': 'sd'},
  'wan3.0-t2v': {'duration': 2, 'resolution': 'sd'},
  'minimax-h3-lite-t2v': {'duration': 5, 'resolution': 'qhd'},
  'muse-video-t2v': {'duration': 5, 'resolution': 'hd'},
  'kling-3.0-t2v': {'duration': 3, 'resolution': 'hd'},
  'gemini-omni-t2v': {'duration': 10, 'resolution': 'hd'},
};

void main() {
  final key = Platform.environment['APIPOD_API_KEY']?.trim() ?? '';
  final enabled = Platform.environment['RUN_APIPOD_LIVE_TESTS'] == 'true';
  final reportPath = Platform.environment['APIPOD_LIVE_REPORT'];
  final resume = Platform.environment['APIPOD_LIVE_RESUME'] == 'true';
  final outputDirectory = Platform.environment['APIPOD_LIVE_OUTPUT_DIR'];
  final suite = Platform.environment['APIPOD_LIVE_SUITE'] ?? 'seedance-2.5';
  final expanded = suite == 'catalog';

  test(
    expanded
        ? 'live APIPod expanded video catalog delivery'
        : 'live APIPod Seedance 2.5 text, frames, and video reference delivery',
    () async {
      expect(suite, isIn(const ['seedance-2.5', 'catalog']));
      if (expanded) {
        expect(
          reportPath?.isNotEmpty,
          isTrue,
          reason: 'APIPOD_LIVE_REPORT is required to resume paid catalog jobs.',
        );
      }
      if (!resume && reportPath != null && reportPath.isNotEmpty) {
        expect(
          await File(reportPath).exists(),
          isFalse,
          reason:
              'An existing report must be resumed with APIPOD_LIVE_RESUME=true, '
              'not overwritten with duplicate submissions.',
        );
      }
      final client = http.Client();
      final mediaClient = PublicMediaClient();
      addTearDown(client.close);
      addTearDown(mediaClient.close);
      final api = ApipodApi(client: client);
      final report = resume && reportPath != null
          ? Map<String, Object?>.from(
              jsonDecode(await File(reportPath).readAsString()) as Map,
            )
          : <String, Object?>{
              'suite': suite,
              'started_at': DateTime.now().toUtc().toIso8601String(),
              'jobs': <Map<String, Object?>>[],
            };
      expect(report['suite'] ?? 'seedance-2.5', suite);
      final jobs = (report['jobs']! as List)
          .map((job) => Map<String, Object?>.from(job as Map))
          .toList();
      report['jobs'] = jobs;
      var reportWrites = Future<void>.value();
      Future<void> saveReport() => reportWrites = reportWrites.then((_) async {
        if (reportPath != null && reportPath.isNotEmpty) {
          final temporary = File('$reportPath.tmp');
          await temporary.writeAsString(
            const JsonEncoder.withIndent('  ').convert(report),
            flush: true,
          );
          await temporary.rename(reportPath);
        }
      });

      final account = await api.verify(key);
      expect(account.provider, 'apipod');
      report['account_verified'] = true;
      await saveReport();
      // ignore: avoid_print
      print('APIPod live account verified.');

      if (!expanded) {
        final image = await mediaClient
            .get(Uri.parse(_imageUrl))
            .timeout(const Duration(seconds: 45));
        expect(image.statusCode, 200);
        expect(image.headers['content-type'], startsWith('image/'));
        expect(image.bodyBytes.length, greaterThan(1024));
      }

      Map<String, Object?> inputFor(String model, Map<String, Object?> extra) =>
          <String, Object?>{
            'mode': expanded || model.endsWith('-t2v') ? 't2v' : 'i2v',
            'prompt':
                'A quiet cinematic forest landscape in soft morning light, '
                'leaves moving gently in a breeze, one continuous slow camera '
                'push, natural realistic motion, no people, no text.',
            'duration': 4,
            'resolution': 'sd',
            'aspect_ratio': model.endsWith('-i2v') ? 'auto' : '16:9',
            'generate_audio': false,
            ...extra,
          };

      if (expanded) {
        var estimatedMaximum = 0.0;
        for (final entry in _catalogCases.entries) {
          // Validate every route before the first paid submission.
          api.generationPayload(entry.key, inputFor(entry.key, entry.value));
          final estimate = apipodEstimate(
            entry.key,
            VideoMode.t2v,
            GenerationConfig(
              aspectRatio: '16:9',
              duration: entry.value['duration']! as int,
              resolution: entry.value['resolution']! as String,
              generateAudio: false,
              safetyTolerance: 2,
              draft: false,
            ),
          );
          expect(estimate.isAvailable, isTrue);
          estimatedMaximum += estimate.maximumUsd;
        }
        expect(estimatedMaximum, greaterThan(0));
        expect(estimatedMaximum, lessThanOrEqualTo(3));
        report['estimated_maximum_usd'] = estimatedMaximum;
        await saveReport();
      }

      Future<String> generate(String model, Map<String, Object?> extra) async {
        final previous = jobs.where((job) => job['model'] == model).firstOrNull;
        if (expanded && previous?['status'] == 'verified') return '';
        final job =
            previous ??
            <String, Object?>{'model': model, 'status': 'submitting'};
        late final String id;
        late final String pollingUrl;
        if (previous != null) {
          // Resuming a report only polls its accepted task. A report written
          // before an interrupted submit is deliberately not resubmitted.
          final savedId = previous['task_id'];
          expect(
            savedId is String &&
                RegExp(r'^[A-Za-z0-9_-]{1,256}$').hasMatch(savedId),
            isTrue,
            reason:
                'The previous submission has no confirmed task ID; check APIPod before trying again.',
          );
          id = savedId! as String;
          pollingUrl = 'https://api.apipod.ai/v1/videos/status/$id';
        } else {
          final input = inputFor(model, extra);
          job['input'] = api.generationPayload(model, input);
          jobs.add(job);
          await saveReport();
          // A single submit per logical job. Ambiguous responses must never
          // trigger a blind retry or another paid generation in this test.
          late final Map<String, Object?> receipt;
          try {
            receipt = await api.submit(
              key,
              model,
              input,
              operationId:
                  'apipod-live-${DateTime.now().microsecondsSinceEpoch}-$model',
            );
          } on ProviderException catch (error) {
            job['submission_error'] = error.message;
            job['submission_http_status'] = error.status;
            await saveReport();
            rethrow;
          }
          id = receipt['id']! as String;
          pollingUrl = receipt['polling_url']! as String;
        }
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
          if (isGenerationFailureStatus(state)) {
            job['error'] = status['error'];
          }
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
        final cost = status['cost'];
        if (cost != null) {
          expect(cost is num && cost.isFinite && cost >= 0, isTrue);
          job['cost_usd'] = cost;
        }
        await saveReport();
        late http.Response response;
        for (var attempt = 1; attempt <= 3; attempt++) {
          final deliveryClient = PublicMediaClient();
          try {
            job['download_attempts'] = attempt;
            response = await deliveryClient
                .get(Uri.parse(outputUrl))
                .timeout(const Duration(minutes: 2));
            job['media_http_status'] = response.statusCode;
            await saveReport();
            if (response.statusCode == 200 || attempt == 3) break;
          } catch (error) {
            job['download_error_type'] = error.runtimeType.toString();
            await saveReport();
            if (attempt == 3) rethrow;
          } finally {
            deliveryClient.close();
          }
          // Newly completed upstream CDN objects can be briefly unavailable.
          // Retry only the existing media GET, never the paid generation.
          // ignore: avoid_print
          print('APIPod live $model task=$id retrying media download');
          await Future<void>.delayed(const Duration(seconds: 8));
        }
        expect(response.statusCode, 200);
        expect(response.bodyBytes.length, greaterThan(1024));
        // Default MP4 delivery must contain an ISO BMFF file-type box. This
        // rejects an HTML error page even if a CDN incorrectly returned 200.
        final prefix = latin1.decode(response.bodyBytes.take(64).toList());
        expect(prefix.contains('ftyp'), isTrue);
        job['download_bytes'] = response.bodyBytes.length;
        if (outputDirectory != null && outputDirectory.isNotEmpty) {
          final directory = await Directory(
            outputDirectory,
          ).create(recursive: true);
          await File(
            '${directory.path}/$model.mp4',
          ).writeAsBytes(response.bodyBytes, flush: true);
        }
        job['status'] = 'verified';
        await saveReport();
        // ignore: avoid_print
        print(
          'APIPod live $model task=$id verified cost_usd=${cost ?? 'unreported'}',
        );
        return outputUrl;
      }

      if (expanded) {
        final cases = _catalogCases.entries.iterator;
        final failures = <String>[];
        report.remove('failures');
        Future<void> check(MapEntry<String, Map<String, Object?>> entry) async {
          try {
            await generate(entry.key, entry.value);
          } catch (error) {
            failures.add('${entry.key}: $error');
            report['failures'] = failures;
            await saveReport();
            // ignore: avoid_print
            print('APIPod live ${entry.key} failed: $error');
          }
        }

        // Three simultaneous jobs keep the smoke run useful without an
        // account-wide burst. A rejected or ambiguous submit is never retried.
        Future<void> worker() async {
          while (cases.moveNext()) {
            await check(cases.current);
          }
        }

        await Future.wait(List.generate(3, (_) => worker()));
        expect(failures, isEmpty, reason: failures.join('\n'));
      } else {
        final textOutput = await generate('seedance-2.5-t2v', const {});
        await Future.wait([
          generate('seedance-2.5-i2v', const {
            'keyframes': [_imageUrl],
          }),
          generate('seedance-2.5-r2v', {
            'reference_videos': [textOutput],
            'aspect_ratio': 'auto',
            'prompt':
                'Use @Video 1 only as a visual style reference. Create a new '
                'daytime scene of a quiet mountain lake with still water and a '
                'distant pine forest. Static camera, realistic morning light.',
          }),
        ]);
      }
      report['completed_at'] = DateTime.now().toUtc().toIso8601String();
      await saveReport();
    },
    skip: !enabled || key.isEmpty
        ? 'Set RUN_APIPOD_LIVE_TESTS=true and APIPOD_API_KEY for paid live tests.'
        : false,
    timeout: const Timeout(Duration(minutes: 65)),
  );
}
