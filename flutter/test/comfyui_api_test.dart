import 'dart:convert';

import 'package:clawnsole/core/bfl_api.dart';
import 'package:clawnsole/core/comfyui_api.dart';
import 'package:clawnsole/core/comfyui_settings.dart';
import 'package:clawnsole/core/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const workflowJson = '''{
  "6": {"class_type":"CLIPTextEncode", "inputs":{"text":"{{prompt}}"}},
  "3": {"class_type":"KSampler", "inputs":{"seed":"{{seed}}","positive":["6",0]}},
  "5": {"class_type":"EmptyLatentVideo", "inputs":{"width":"{{width}}","height":"{{height}}","length":"{{frames}}"}},
  "9": {"class_type":"SaveVideo", "inputs":{"images":["5",0],"fps":"{{fps}}","filename_prefix":"clawnsole"}}
}''';

const settings = ComfyUiSettings(
  serverUrl: 'http://100.90.0.2:8188/comfy/',
  workflows: {
    'comfyui-video': ComfyUiWorkflow(json: workflowJson, outputNodeId: '9'),
  },
);
const polling =
    'http://100.90.0.2:8188/comfy/history/job-1?clawnsole_output=9&clawnsole_kind=video';

http.Response jsonResponse(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  test(
    'settings roundtrip preserves existing preferences and validates API graph',
    () {
      settings.validate();
      final preferences = AppPreferences(
        favoriteProviders: const ['bfl'],
        providerConfigurations: {'comfyui': settings.toJson()},
      );
      final restored = AppPreferences.fromJson(preferences.toJson());
      expect(restored.favoriteProviders, ['bfl']);
      expect(
        ComfyUiSettings.fromJson(
          restored.providerConfigurations['comfyui'],
        ).toJson(),
        settings.toJson(),
      );
      expect(
        const AppPreferences().toJson(),
        isNot(contains('providerConfigurations')),
      );
      expect(
        ComfyUiSettings.fromJson({'schemaVersion': 99}).isConfigured,
        isFalse,
      );
      for (final invalid in [
        'file:///tmp/server',
        'http://user:password@host',
        'http://host?token=secret',
        'http://host#fragment',
      ]) {
        expect(() => comfyUiServerUri(invalid), throwsFormatException);
      }
      for (final invalid in [
        '{"nodes":[],"links":[]}',
        workflowJson.replaceAll('{{prompt}}', 'hardcoded'),
        workflowJson.replaceAll('{{seed}}', '{{unknown}}'),
        workflowJson.replaceAll('{{seed}}', 'prefix {{seed}}'),
        workflowJson.replaceAll('clawnsole', 'data:image/png;base64,AAAA'),
      ]) {
        expect(
          () => ComfyUiWorkflow(json: invalid, outputNodeId: '9').validate(),
          throwsFormatException,
        );
      }
      expect(
        () => const ComfyUiWorkflow(
          json: workflowJson,
          outputNodeId: 'missing',
        ).validate(),
        throwsFormatException,
      );
    },
  );

  test(
    'submit substitutes typed values without interpreting the user prompt',
    () async {
      final events = <String>[];
      final api = ComfyUiApi(
        client: MockClient((request) async {
          events.add('post');
          expect(request.url.toString(), 'http://100.90.0.2:8188/comfy/prompt');
          expect(request.followRedirects, isFalse);
          final graph = (jsonDecode(request.body) as Map)['prompt'] as Map;
          expect(graph['6']['inputs']['text'], 'A fox says "{{seed}}"');
          expect(graph['3']['inputs']['seed'], 42);
          expect(graph['3']['inputs']['positive'], ['6', 0]);
          expect(graph['5']['inputs'], {
            'width': 768,
            'height': 448,
            'length': 121,
          });
          expect(graph['9']['inputs']['fps'], 24);
          return jsonResponse({'prompt_id': 'job-1', 'number': 1});
        }),
      );
      final receipt = await api.submit(settings, 'comfyui-video', {
        'prompt': 'A fox says "{{seed}}"',
        'seed': 42,
        'duration': 5,
        'aspect_ratio': '16:9',
        'resolution': 'hd',
        'frame_rate': 2,
      }, beforeSend: () async => events.add('persist'));
      expect(events, ['persist', 'post']);
      expect(receipt['polling_url'], polling);
      expect(jsonEncode(receipt), isNot(contains('class_type')));
    },
  );

  for (final field in ['images', 'gifs', 'videos']) {
    test(
      'poll selects configured video output in $field and ignores preview node',
      () async {
        final api = ComfyUiApi(
          client: MockClient((request) async {
            expect(
              request.url.toString(),
              'http://100.90.0.2:8188/comfy/history/job-1',
            );
            return jsonResponse({
              'job-1': {
                'status': {'status_str': 'success', 'completed': true},
                'outputs': {
                  '8': {
                    'images': [
                      {'filename': 'preview.png', 'type': 'output'},
                    ],
                  },
                  '9': {
                    field: [
                      {
                        'filename': 'film.mp4',
                        'subfolder': 'videos',
                        'type': 'output',
                      },
                    ],
                  },
                },
              },
            });
          }),
        );
        final result = await api.poll(polling);
        expect(result['status'], 'Ready');
        expect(
          (result['result'] as Map)['sample'],
          'http://100.90.0.2:8188/comfy/view?filename=film.mp4&subfolder=videos&type=output',
        );
      },
    );
  }

  test(
    'poll distinguishes queue, completion race, execution errors, and lost job',
    () async {
      var queue = 'queue_pending';
      var historyCalls = 0;
      var race = false;
      final api = ComfyUiApi(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/queue')) {
            return jsonResponse({
              queue: [
                [0, 'job-1'],
              ],
            });
          }
          historyCalls++;
          if (race && historyCalls > 1) {
            return jsonResponse({
              'job-1': {
                'status': {
                  'status_str': 'error',
                  'completed': false,
                  'messages': [
                    [
                      'execution_error',
                      {'exception_message': 'Missing model weights'},
                    ],
                  ],
                },
              },
            });
          }
          return jsonResponse({});
        }),
      );
      expect((await api.poll(polling))['status'], 'Pending');
      queue = 'queue_running';
      expect((await api.poll(polling))['status'], 'Running');
      queue = 'unrelated';
      expect((await api.poll(polling))['status'], 'Task not found');
      race = true;
      historyCalls = 0;
      final failed = await api.poll(polling);
      expect(failed['status'], 'Failed');
      expect(failed['error'], 'Missing model weights');
    },
  );

  test(
    'a missing final video output fails instead of retaining a preview',
    () async {
      final api = ComfyUiApi(
        client: MockClient(
          (_) async => jsonResponse({
            'job-1': {
              'status': {'status_str': 'success', 'completed': true},
              'outputs': {
                '9': {
                  'images': [
                    {'filename': 'preview.png', 'type': 'temp'},
                  ],
                },
              },
            },
          }),
        ),
      );
      expect((await api.poll(polling))['status'], 'Failed');
    },
  );

  test(
    'result download is limited to original server view route without redirects',
    () async {
      var calls = 0;
      final api = ComfyUiApi(
        client: MockClient((request) async {
          calls++;
          expect(request.followRedirects, isFalse);
          return http.Response.bytes(
            [1, 2, 3],
            200,
            headers: {'content-type': 'video/mp4'},
          );
        }),
      );
      for (final invalid in [
        'http://other-server:8188/comfy/view?filename=film.mp4&type=output',
        'http://100.90.0.2:8188/comfy/queue?filename=film.mp4&type=output',
        'http://100.90.0.2:8188/comfy/view?filename=film.mp4&type=input',
      ]) {
        await expectLater(
          api.downloadResult(invalid, polling),
          throwsA(isA<ProviderException>()),
        );
      }
      expect(calls, 0);
      final response = await api.downloadResult(
        'http://100.90.0.2:8188/comfy/view?filename=film.mp4&type=output',
        polling,
      );
      expect(await response.stream.toBytes(), [1, 2, 3]);
      expect(calls, 1);
    },
  );
}
