import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clawnsole/core/anthropic_rewrite_api.dart';
import 'package:clawnsole/core/openai_rewrite_api.dart';
import 'package:clawnsole/core/prompt_rewrite.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('OpenAI', () {
    test(
      'posts labeled frames, a strict schema, and reasoning effort',
      () async {
        final request = rewriteRequest(
          providerId: RewriteProvider.openai.id,
          modelId: 'gpt-5.5',
          effort: 'high',
        );
        late http.Request sent;
        final api = OpenAiRewriteApi(
          baseUrl: vendorBase,
          client: MockClient((call) async {
            sent = call;
            return ok(
              openAiCompleted(
                '{"prompt":"A colder courtroom.","summary":"Cooled the room."}',
              ),
            );
          }),
        );

        final result = await api.rewrite(request, 'sk-openai-secret');

        expect(sent.method, 'POST');
        expect(sent.url, Uri.parse('https://vendor.test/v1/responses'));
        expect(sent.headers['authorization'], 'Bearer sk-openai-secret');
        expect(sent.headers['accept'], 'application/json');
        expect(sent.headers['content-type'], startsWith('application/json'));
        expect(
          sent.body,
          isNot(contains('sk-openai-secret')),
          reason: 'the key rides in the header, never in the payload',
        );

        final body = jsonBody(sent);
        expect(body['model'], 'gpt-5.5');
        expect(body['instructions'], buildRewriteInstructions(request));
        expect(body['max_output_tokens'], 4096);
        expect(body['store'], false);
        expect(body['reasoning'], <String, Object?>{'effort': 'high'});
        expect(body['text'], <String, Object?>{
          'format': <String, Object?>{
            'type': 'json_schema',
            'name': rewriteOutputSchemaName,
            'schema': rewriteOutputSchema,
            'strict': true,
          },
        });

        final input = body['input']! as List<Object?>;
        expect(input, hasLength(1));
        final message = input.single! as Map<String, Object?>;
        expect(message['role'], 'user');
        final content = (message['content']! as List<Object?>)
            .cast<Map<String, Object?>>();
        expect(content, hasLength(5));
        expect(content[0], <String, Object?>{
          'type': 'input_text',
          'text': 'Frame 1 of 2 at 0 s',
        });
        expect(content[1], <String, Object?>{
          'type': 'input_image',
          'image_url': 'data:image/jpeg;base64,AQID',
          'detail': 'auto',
        });
        expect(content[2], <String, Object?>{
          'type': 'input_text',
          'text': 'Frame 2 of 2 at 2.5 s',
        });
        expect(content[3], <String, Object?>{
          'type': 'input_image',
          'image_url': 'data:image/png;base64,BAUG',
          'detail': 'auto',
        });
        expect(content[4], <String, Object?>{
          'type': 'input_text',
          'text': buildRewriteBrief(request),
        });

        expect(result.prompt, 'A colder courtroom.');
        expect(result.summary, 'Cooled the room.');
        expect(result.providerId, 'openai');
        expect(result.modelId, 'gpt-5.5');
      },
    );

    test('sends reasoning only for reasoning models', () {
      final api = OpenAiRewriteApi(baseUrl: vendorBase, client: silentClient());
      const reasoning = <String, bool>{
        'gpt-5.5': true,
        'gpt-5.6-sol': true,
        'gpt-5': true,
        'o3': true,
        'o4-mini': true,
        'gpt-4.1': false,
        'gpt-4o': false,
        'chatgpt-4o-latest': false,
      };
      for (final entry in reasoning.entries) {
        expect(openAiReasoningModel(entry.key), entry.value, reason: entry.key);
        final payload = api.rewritePayload(
          rewriteRequest(
            providerId: RewriteProvider.openai.id,
            modelId: entry.key,
            effort: 'high',
          ),
        );
        expect(
          payload.containsKey('reasoning'),
          entry.value,
          reason: 'reasoning for ${entry.key}',
        );
      }
      expect(
        api
            .rewritePayload(
              rewriteRequest(
                providerId: RewriteProvider.openai.id,
                modelId: 'gpt-5.5',
              ),
            )
            .containsKey('reasoning'),
        isFalse,
        reason: 'no effort chosen means no reasoning block',
      );
    });

    test('reads the model the response says answered', () async {
      final api = OpenAiRewriteApi(
        baseUrl: vendorBase,
        client: MockClient(
          (call) async => ok(
            openAiCompleted(
              '{"prompt":"P","summary":"S"}',
              model: 'gpt-5.5-2026-03-01',
            ),
          ),
        ),
      );

      final result = await api.rewrite(
        rewriteRequest(
          providerId: RewriteProvider.openai.id,
          modelId: 'gpt-5.5',
        ),
        'sk-openai',
      );
      expect(result.modelId, 'gpt-5.5-2026-03-01');
    });

    test('reports a refusal', () async {
      final api = OpenAiRewriteApi(
        baseUrl: vendorBase,
        client: MockClient(
          (call) async => ok(<String, Object?>{
            'model': 'gpt-5.5',
            'status': 'completed',
            'output': <Object?>[
              <String, Object?>{
                'type': 'message',
                'content': <Object?>[
                  <String, Object?>{
                    'type': 'refusal',
                    'refusal': 'I cannot help with that request.',
                  },
                ],
              },
            ],
          }),
        ),
      );

      final failure = await rewriteFailure(
        api,
        rewriteRequest(
          providerId: RewriteProvider.openai.id,
          modelId: 'gpt-5.5',
        ),
      );
      expect(failure.failure, PromptRewriteFailure.refused);
      expect(failure.message, 'I cannot help with that request.');
    });

    test('reports an incomplete answer with its reason', () async {
      final api = OpenAiRewriteApi(
        baseUrl: vendorBase,
        client: MockClient(
          (call) async => ok(<String, Object?>{
            'model': 'gpt-5.5',
            'status': 'incomplete',
            'incomplete_details': <String, Object?>{
              'reason': 'max_output_tokens',
            },
            'output': <Object?>[],
          }),
        ),
      );

      final failure = await rewriteFailure(
        api,
        rewriteRequest(
          providerId: RewriteProvider.openai.id,
          modelId: 'gpt-5.5',
        ),
      );
      expect(failure.failure, PromptRewriteFailure.invalidResponse);
      expect(failure.message, contains('max_output_tokens'));
    });

    test('reports an error object and an unfinished status', () async {
      final errored = OpenAiRewriteApi(
        baseUrl: vendorBase,
        client: MockClient(
          (call) async => ok(<String, Object?>{
            'status': 'failed',
            'error': <String, Object?>{
              'code': 'server_error',
              'message': 'The model is overloaded.',
            },
            'output': <Object?>[],
          }),
        ),
      );
      final errorFailure = await rewriteFailure(
        errored,
        rewriteRequest(
          providerId: RewriteProvider.openai.id,
          modelId: 'gpt-5.5',
        ),
      );
      expect(errorFailure.failure, PromptRewriteFailure.other);
      expect(errorFailure.message, 'The model is overloaded.');

      final stalled = OpenAiRewriteApi(
        baseUrl: vendorBase,
        client: MockClient(
          (call) async =>
              ok(<String, Object?>{'status': 'failed', 'output': <Object?>[]}),
        ),
      );
      final stalledFailure = await rewriteFailure(
        stalled,
        rewriteRequest(
          providerId: RewriteProvider.openai.id,
          modelId: 'gpt-5.5',
        ),
      );
      expect(stalledFailure.failure, PromptRewriteFailure.other);
      expect(stalledFailure.message, contains('failed'));
    });

    test('rejects an answer that is not JSON', () async {
      final api = OpenAiRewriteApi(
        baseUrl: vendorBase,
        client: MockClient(
          (call) async =>
              ok(openAiCompleted('I would rather describe my feelings.')),
        ),
      );

      final failure = await rewriteFailure(
        api,
        rewriteRequest(
          providerId: RewriteProvider.openai.id,
          modelId: 'gpt-5.5',
        ),
      );
      expect(failure.failure, PromptRewriteFailure.invalidResponse);
    });

    test('maps HTTP statuses onto rewrite failures', () async {
      const expected = <int, PromptRewriteFailure>{
        400: PromptRewriteFailure.badRequest,
        401: PromptRewriteFailure.unauthorized,
        402: PromptRewriteFailure.rateLimited,
        403: PromptRewriteFailure.unauthorized,
        404: PromptRewriteFailure.badRequest,
        422: PromptRewriteFailure.badRequest,
        429: PromptRewriteFailure.rateLimited,
        500: PromptRewriteFailure.other,
        503: PromptRewriteFailure.other,
      };
      for (final entry in expected.entries) {
        final api = OpenAiRewriteApi(
          baseUrl: vendorBase,
          client: MockClient(
            (call) async => response(<String, Object?>{
              'error': <String, Object?>{
                'type': 'invalid_request_error',
                'message': 'Unsupported effort "xhigh" for this model.',
              },
            }, entry.key),
          ),
        );
        final failure = await rewriteFailure(
          api,
          rewriteRequest(
            providerId: RewriteProvider.openai.id,
            modelId: 'gpt-5.5',
          ),
        );
        expect(failure.failure, entry.value, reason: 'HTTP ${entry.key}');
        expect(failure.status, entry.key, reason: 'HTTP ${entry.key}');
        if (entry.value != PromptRewriteFailure.unauthorized) {
          expect(
            failure.message,
            'Unsupported effort "xhigh" for this model.',
            reason: 'the vendor sentence explains the rejection',
          );
        }
      }
    });

    test('never repeats the key a 401 quotes back', () async {
      final api = OpenAiRewriteApi(
        baseUrl: vendorBase,
        client: MockClient(
          (call) async => response(<String, Object?>{
            'error': <String, Object?>{
              'message': 'Incorrect API key provided: sk-live-9f2c.',
            },
          }, 401),
        ),
      );

      final failure = await rewriteFailure(
        api,
        rewriteRequest(
          providerId: RewriteProvider.openai.id,
          modelId: 'gpt-5.5',
        ),
      );
      expect(failure.failure, PromptRewriteFailure.unauthorized);
      expect(failure.message, 'OpenAI rejected this API key.');
      expect(failure.message, isNot(contains('sk-live-9f2c')));
    });

    test('turns transport trouble into a network failure', () async {
      for (final thrown in <Object>[
        TimeoutException('too slow'),
        const SocketException('No route to host'),
        http.ClientException('Connection closed before full header'),
      ]) {
        final api = OpenAiRewriteApi(
          baseUrl: vendorBase,
          client: MockClient((call) async => throw thrown),
        );
        final failure = await rewriteFailure(
          api,
          rewriteRequest(
            providerId: RewriteProvider.openai.id,
            modelId: 'gpt-5.5',
          ),
        );
        expect(
          failure.failure,
          PromptRewriteFailure.network,
          reason: thrown.runtimeType.toString(),
        );
      }
    });

    test('lists models over the documented route', () async {
      late http.Request sent;
      final api = OpenAiRewriteApi(
        baseUrl: vendorBase,
        client: MockClient((call) async {
          sent = call;
          return ok(<String, Object?>{
            'object': 'list',
            'data': <Object?>[
              <String, Object?>{'id': 'gpt-5.5', 'created': 1800000000},
              <String, Object?>{'id': 'gpt-image-1', 'created': 1900000000},
            ],
          });
        }),
      );

      final models = await api.listModels('sk-openai-secret');

      expect(sent.method, 'GET');
      expect(sent.url, Uri.parse('https://vendor.test/v1/models'));
      expect(sent.headers['authorization'], 'Bearer sk-openai-secret');
      expect(models.map((model) => model.id), <String>['gpt-5.5']);
    });

    test('rejects an unauthorized listing', () async {
      final api = OpenAiRewriteApi(
        baseUrl: vendorBase,
        client: MockClient((call) async => response(<String, Object?>{}, 401)),
      );

      PromptRewriteException? failure;
      try {
        await api.listModels('sk-openai-secret');
      } on PromptRewriteException catch (error) {
        failure = error;
      }
      expect(failure?.failure, PromptRewriteFailure.unauthorized);
      expect(failure?.status, 401);
    });

    test('keeps chat models, drops the rest, newest first', () {
      final models = openAiRewriteModelsFromListing(<Map<String, Object?>>[
        <String, Object?>{'id': 'gpt-4.1', 'created': 1700000000},
        <String, Object?>{'id': 'gpt-5.5', 'created': 1800000000},
        <String, Object?>{'id': 'o4-mini', 'created': 1750000000},
        <String, Object?>{'id': 'gpt-5.6-terra', 'created': 1850000000},
        for (final junk in <String>[
          'gpt-5.4-2026-04-11',
          'gpt-4o-realtime-preview',
          'gpt-4o-transcribe',
          'gpt-4o-mini-tts',
          'gpt-4o-audio-preview',
          'gpt-4o-whisper',
          'gpt-image-1',
          'gpt-4o-search-preview',
          'gpt-5-codex',
          'o3-deep-research',
          'gpt-4o-translate',
          'gpt-3.5-turbo-instruct',
          'gpt-4o-moderation',
          'gpt-4-embedding',
          'gpt-5-chat-latest',
          'gpt-5-pro',
          'gpt-5-computer-use',
          'chatgpt-4o-latest',
          'text-embedding-3-large',
          'dall-e-3',
          'omni-moderation-latest',
        ])
          <String, Object?>{'id': junk, 'created': 1900000000},
      ]);

      expect(models.map((model) => model.id), <String>[
        'gpt-5.6-terra',
        'gpt-5.5',
        'o4-mini',
        'gpt-4.1',
      ]);
      expect(models.map((model) => model.label), <String>[
        'GPT-5.6 Terra',
        'GPT-5.5',
        'o4-mini',
        'GPT-4.1',
      ]);
      expect(models.map((model) => model.supportsEffort), <bool>[
        true,
        true,
        true,
        false,
      ]);
      expect(models.map((model) => model.supportsThinking), <bool>[
        true,
        true,
        true,
        false,
      ]);
      expect(
        models[1].createdAt,
        DateTime.fromMillisecondsSinceEpoch(1800000000000, isUtc: true),
      );
    });

    test('falls back to the curated list when nothing survives', () {
      expect(
        openAiRewriteModelsFromListing(const <Map<String, Object?>>[
          <String, Object?>{'id': 'dall-e-3'},
          <String, Object?>{'id': 'gpt-image-1'},
        ]),
        RewriteProvider.openai.curatedModels,
      );
      expect(
        openAiRewriteModelsFromListing(const <Map<String, Object?>>[]),
        RewriteProvider.openai.curatedModels,
      );
    });
  });

  group('Anthropic', () {
    test('posts frames, a schema, effort, thinking, and a fallback', () async {
      final request = rewriteRequest(
        providerId: RewriteProvider.anthropic.id,
        modelId: 'claude-opus-5',
        effort: 'xhigh',
      );
      late http.Request sent;
      final api = AnthropicRewriteApi(
        baseUrl: vendorBase,
        client: MockClient((call) async {
          sent = call;
          return ok(
            anthropicMessage(
              '{"prompt":"A colder courtroom.","summary":"Cooled the room."}',
            ),
          );
        }),
      );

      final result = await api.rewrite(request, 'sk-ant-secret');

      expect(sent.method, 'POST');
      expect(sent.url, Uri.parse('https://vendor.test/v1/messages'));
      expect(sent.headers['x-api-key'], 'sk-ant-secret');
      expect(sent.headers['anthropic-version'], '2023-06-01');
      expect(sent.headers['content-type'], startsWith('application/json'));
      expect(
        sent.headers['anthropic-beta'],
        'server-side-fallback-2026-07-01',
        reason: 'the beta header rides with the fallbacks body',
      );
      expect(sent.body, isNot(contains('sk-ant-secret')));

      final body = jsonBody(sent);
      expect(body['model'], 'claude-opus-5');
      expect(body['max_tokens'], 16000);
      expect(body['system'], buildRewriteInstructions(request));
      expect(body['thinking'], <String, Object?>{'type': 'adaptive'});
      expect(body['fallbacks'], 'default');
      expect(body.containsKey('temperature'), isFalse);
      expect(body.containsKey('top_p'), isFalse);
      expect(body['output_config'], <String, Object?>{
        'format': <String, Object?>{
          'type': 'json_schema',
          'schema': rewriteOutputSchema,
        },
        'effort': 'xhigh',
      });
      expect(
        (body['output_config']! as Map<String, Object?>)['format'],
        isNot(contains('budget_tokens')),
      );

      final messages = body['messages']! as List<Object?>;
      expect(messages, hasLength(1));
      final message = messages.single! as Map<String, Object?>;
      expect(message['role'], 'user');
      final content = (message['content']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(content, hasLength(5));
      expect(content[0], <String, Object?>{
        'type': 'text',
        'text': 'Frame 1 of 2 at 0 s',
      });
      expect(content[1], <String, Object?>{
        'type': 'image',
        'source': <String, Object?>{
          'type': 'base64',
          'media_type': 'image/jpeg',
          'data': 'AQID',
        },
      });
      expect(content[2], <String, Object?>{
        'type': 'text',
        'text': 'Frame 2 of 2 at 2.5 s',
      });
      expect(content[3], <String, Object?>{
        'type': 'image',
        'source': <String, Object?>{
          'type': 'base64',
          'media_type': 'image/png',
          'data': 'BAUG',
        },
      });
      expect(content[4], <String, Object?>{
        'type': 'text',
        'text': buildRewriteBrief(request),
      });

      expect(result.prompt, 'A colder courtroom.');
      expect(result.summary, 'Cooled the room.');
      expect(result.providerId, 'anthropic');
      expect(result.modelId, 'claude-opus-5');
    });

    test('omits effort, thinking, and fallbacks a model cannot take', () async {
      late http.Request sent;
      final api = AnthropicRewriteApi(
        baseUrl: vendorBase,
        client: MockClient((call) async {
          sent = call;
          return ok(anthropicMessage('{"prompt":"P","summary":"S"}'));
        }),
      );

      await api.rewrite(
        rewriteRequest(
          providerId: RewriteProvider.anthropic.id,
          modelId: 'claude-haiku-4-5',
          effort: 'high',
        ),
        'sk-ant-secret',
      );

      final body = jsonBody(sent);
      expect(body.containsKey('thinking'), isFalse);
      expect(body.containsKey('fallbacks'), isFalse);
      expect(sent.headers.containsKey('anthropic-beta'), isFalse);
      expect(body['output_config'], <String, Object?>{
        'format': <String, Object?>{
          'type': 'json_schema',
          'schema': rewriteOutputSchema,
        },
      });
    });

    test('asks for a fallback only for the served families', () {
      final api = AnthropicRewriteApi(
        baseUrl: vendorBase,
        client: silentClient(),
      );
      const fallbacks = <String, bool>{
        'claude-opus-5': true,
        'claude-opus-5-2': true,
        'claude-fable-5-1': true,
        'claude-mythos-1': true,
        'claude-sonnet-5': false,
        'claude-opus-4-8': false,
        'claude-haiku-4-5': false,
      };
      for (final entry in fallbacks.entries) {
        expect(
          anthropicModelTraits(entry.key).wantsFallback,
          entry.value,
          reason: entry.key,
        );
        final payload = api.rewritePayload(
          rewriteRequest(
            providerId: RewriteProvider.anthropic.id,
            modelId: entry.key,
          ),
        );
        expect(
          payload.containsKey('fallbacks'),
          entry.value,
          reason: 'fallbacks for ${entry.key}',
        );
      }
    });

    test('reads effort and thinking support per model family', () {
      const effortAndThinking = <String, bool>{
        'claude-opus-5': true,
        'claude-fable-5-1': true,
        'claude-sonnet-5': true,
        'claude-opus-4-8': true,
        'claude-opus-4-6': true,
        'claude-sonnet-4-6': true,
        'claude-mythos-2': true,
        'claude-opus-5-2': true,
        'claude-sonnet-5-1': true,
        'claude-haiku-4-5': false,
        'claude-haiku-5': false,
        'claude-opus-4-5': false,
        'claude-sonnet-4-5': false,
        'claude-unknown-9': false,
      };
      for (final entry in effortAndThinking.entries) {
        final traits = anthropicModelTraits(entry.key);
        expect(traits.supportsEffort, entry.value, reason: entry.key);
        expect(traits.supportsAdaptiveThinking, entry.value, reason: entry.key);
      }
    });

    test('retries without the schema when the API blames it', () async {
      final bodies = <Map<String, Object?>>[];
      final api = AnthropicRewriteApi(
        baseUrl: vendorBase,
        client: MockClient((call) async {
          bodies.add(jsonBody(call));
          if (bodies.length == 1) {
            return response(<String, Object?>{
              'type': 'error',
              'error': <String, Object?>{
                'type': 'invalid_request_error',
                'message': 'output_config.format is not supported here.',
              },
            }, 400);
          }
          return ok(
            anthropicMessage(
              'Here you go:\n'
              '```json\n{"prompt":"P","summary":"S"}\n```',
            ),
          );
        }),
      );

      final result = await api.rewrite(
        rewriteRequest(
          providerId: RewriteProvider.anthropic.id,
          modelId: 'claude-opus-5',
          effort: 'high',
        ),
        'sk-ant-secret',
      );

      expect(bodies, hasLength(2));
      expect(
        (bodies.first['output_config']! as Map<String, Object?>).keys,
        containsAll(<String>['format', 'effort']),
      );
      expect(bodies.last['output_config'], <String, Object?>{
        'effort': 'high',
      }, reason: 'the retry drops the format but keeps the effort');
      expect(result.prompt, 'P');
      expect(result.summary, 'S');
    });

    test('does not retry a 400 about something else', () async {
      var calls = 0;
      final api = AnthropicRewriteApi(
        baseUrl: vendorBase,
        client: MockClient((call) async {
          calls++;
          return response(<String, Object?>{
            'type': 'error',
            'error': <String, Object?>{
              'type': 'invalid_request_error',
              'message': 'max_tokens: must be less than 200000',
            },
          }, 400);
        }),
      );

      final failure = await rewriteFailure(
        api,
        rewriteRequest(
          providerId: RewriteProvider.anthropic.id,
          modelId: 'claude-opus-5',
        ),
      );
      expect(calls, 1);
      expect(failure.failure, PromptRewriteFailure.badRequest);
      expect(failure.message, 'max_tokens: must be less than 200000');
    });

    test('reports a refusal, with the vendor explanation when given', () async {
      final explained = AnthropicRewriteApi(
        baseUrl: vendorBase,
        client: MockClient(
          (call) async => ok(<String, Object?>{
            'model': 'claude-opus-5',
            'stop_reason': 'refusal',
            'stop_details': <String, Object?>{
              'explanation': 'This asks for a real person likeness.',
            },
            'content': <Object?>[],
          }),
        ),
      );
      final explainedFailure = await rewriteFailure(
        explained,
        rewriteRequest(
          providerId: RewriteProvider.anthropic.id,
          modelId: 'claude-opus-5',
        ),
      );
      expect(explainedFailure.failure, PromptRewriteFailure.refused);
      expect(explainedFailure.message, 'This asks for a real person likeness.');

      final bare = AnthropicRewriteApi(
        baseUrl: vendorBase,
        client: MockClient(
          (call) async => ok(<String, Object?>{
            'model': 'claude-opus-5',
            'stop_reason': 'refusal',
            'content': <Object?>[],
          }),
        ),
      );
      final bareFailure = await rewriteFailure(
        bare,
        rewriteRequest(
          providerId: RewriteProvider.anthropic.id,
          modelId: 'claude-opus-5',
        ),
      );
      expect(bareFailure.failure, PromptRewriteFailure.refused);
      expect(bareFailure.message, 'The model declined to rewrite this prompt.');
    });

    test('reports a truncated answer', () async {
      final api = AnthropicRewriteApi(
        baseUrl: vendorBase,
        client: MockClient(
          (call) async => ok(<String, Object?>{
            'model': 'claude-opus-5',
            'stop_reason': 'max_tokens',
            'content': <Object?>[
              <String, Object?>{'type': 'text', 'text': '{"prompt":"half of'},
            ],
          }),
        ),
      );

      final failure = await rewriteFailure(
        api,
        rewriteRequest(
          providerId: RewriteProvider.anthropic.id,
          modelId: 'claude-opus-5',
        ),
      );
      expect(failure.failure, PromptRewriteFailure.invalidResponse);
    });

    test('ignores thinking blocks and trusts the served model id', () async {
      final api = AnthropicRewriteApi(
        baseUrl: vendorBase,
        client: MockClient(
          (call) async => ok(<String, Object?>{
            'model': 'claude-opus-4-8',
            'stop_reason': 'end_turn',
            'content': <Object?>[
              <String, Object?>{
                'type': 'thinking',
                'thinking': 'The courtroom reads warm because of the lamps.',
              },
              <String, Object?>{
                'type': 'text',
                'text': '{"prompt":"P","summary":"S"}',
              },
            ],
          }),
        ),
      );

      final result = await api.rewrite(
        rewriteRequest(
          providerId: RewriteProvider.anthropic.id,
          modelId: 'claude-opus-5',
        ),
        'sk-ant-secret',
      );
      expect(result.prompt, 'P');
      expect(
        result.modelId,
        'claude-opus-4-8',
        reason: 'a fallback answered, and the receipt should say so',
      );
    });

    test('rejects an answer that is not JSON', () async {
      final api = AnthropicRewriteApi(
        baseUrl: vendorBase,
        client: MockClient(
          (call) async =>
              ok(anthropicMessage('I would rather describe my feelings.')),
        ),
      );

      final failure = await rewriteFailure(
        api,
        rewriteRequest(
          providerId: RewriteProvider.anthropic.id,
          modelId: 'claude-opus-5',
        ),
      );
      expect(failure.failure, PromptRewriteFailure.invalidResponse);
    });

    test('maps HTTP statuses onto rewrite failures', () async {
      const expected = <int, PromptRewriteFailure>{
        400: PromptRewriteFailure.badRequest,
        401: PromptRewriteFailure.unauthorized,
        402: PromptRewriteFailure.rateLimited,
        403: PromptRewriteFailure.unauthorized,
        422: PromptRewriteFailure.badRequest,
        429: PromptRewriteFailure.rateLimited,
        500: PromptRewriteFailure.other,
        529: PromptRewriteFailure.other,
      };
      for (final entry in expected.entries) {
        final api = AnthropicRewriteApi(
          baseUrl: vendorBase,
          client: MockClient(
            (call) async => response(<String, Object?>{
              'type': 'error',
              'error': <String, Object?>{
                'type': 'invalid_request_error',
                'message': 'Effort "xhigh" is not available on this model.',
              },
            }, entry.key),
          ),
        );
        final failure = await rewriteFailure(
          api,
          rewriteRequest(
            providerId: RewriteProvider.anthropic.id,
            modelId: 'claude-opus-5',
          ),
        );
        expect(failure.failure, entry.value, reason: 'HTTP ${entry.key}');
        expect(failure.status, entry.key, reason: 'HTTP ${entry.key}');
        if (entry.value == PromptRewriteFailure.unauthorized) {
          expect(failure.message, 'Anthropic rejected this API key.');
        } else {
          expect(
            failure.message,
            'Effort "xhigh" is not available on this model.',
          );
        }
      }
    });

    test('says a 404 means the model id is wrong', () async {
      final api = AnthropicRewriteApi(
        baseUrl: vendorBase,
        client: MockClient(
          (call) async => response(<String, Object?>{
            'type': 'error',
            'error': <String, Object?>{
              'type': 'not_found_error',
              'message': 'model: claude-nope-9',
            },
          }, 404),
        ),
      );

      final failure = await rewriteFailure(
        api,
        rewriteRequest(
          providerId: RewriteProvider.anthropic.id,
          modelId: 'claude-nope-9',
        ),
      );
      expect(failure.failure, PromptRewriteFailure.badRequest);
      expect(failure.status, 404);
      expect(failure.message, contains('claude-nope-9'));
      expect(failure.message, contains('model'));
    });

    test('turns transport trouble into a network failure', () async {
      for (final thrown in <Object>[
        TimeoutException('too slow'),
        const SocketException('No route to host'),
        http.ClientException('Connection closed before full header'),
      ]) {
        final api = AnthropicRewriteApi(
          baseUrl: vendorBase,
          client: MockClient((call) async => throw thrown),
        );
        final failure = await rewriteFailure(
          api,
          rewriteRequest(
            providerId: RewriteProvider.anthropic.id,
            modelId: 'claude-opus-5',
          ),
        );
        expect(
          failure.failure,
          PromptRewriteFailure.network,
          reason: thrown.runtimeType.toString(),
        );
      }
    });

    test('lists models over the documented route', () async {
      late http.Request sent;
      final api = AnthropicRewriteApi(
        baseUrl: vendorBase,
        client: MockClient((call) async {
          sent = call;
          return ok(<String, Object?>{
            'data': <Object?>[
              <String, Object?>{
                'id': 'claude-opus-5',
                'display_name': 'Claude Opus 5',
                'created_at': '2026-05-01T00:00:00Z',
              },
            ],
          });
        }),
      );

      final models = await api.listModels('sk-ant-secret');

      expect(sent.method, 'GET');
      expect(sent.url.path, '/v1/models');
      expect(sent.url.queryParameters['limit'], '100');
      expect(sent.headers['x-api-key'], 'sk-ant-secret');
      expect(sent.headers['anthropic-version'], '2023-06-01');
      expect(
        sent.headers.containsKey('anthropic-beta'),
        isFalse,
        reason: 'no fallbacks body, no beta header',
      );
      expect(models.single.id, 'claude-opus-5');
    });

    test('filters the listing on capabilities and orders it newest first', () {
      final models = anthropicRewriteModelsFromListing(<Map<String, Object?>>[
        <String, Object?>{
          'id': 'claude-opus-5',
          'display_name': 'Claude Opus 5',
          'created_at': '2026-05-01T00:00:00Z',
          'capabilities': <String, Object?>{
            'image_input': <String, Object?>{'supported': true},
            'effort': <String, Object?>{
              'supported': true,
              'low': <String, Object?>{'supported': true},
              'medium': <String, Object?>{'supported': true},
              'high': <String, Object?>{'supported': true},
              'max': <String, Object?>{'supported': true},
            },
            'thinking': <String, Object?>{
              'types': <String, Object?>{
                'adaptive': <String, Object?>{'supported': true},
              },
            },
          },
        },
        <String, Object?>{
          'id': 'claude-haiku-4-5',
          'display_name': 'Claude Haiku 4.5',
          'created_at': '2025-10-01T00:00:00Z',
          'capabilities': <String, Object?>{
            'image_input': <String, Object?>{'supported': true},
            'effort': <String, Object?>{'supported': false},
            'thinking': <String, Object?>{
              'types': <String, Object?>{
                'adaptive': <String, Object?>{'supported': false},
              },
            },
          },
        },
        <String, Object?>{
          'id': 'claude-mythos-1',
          'created_at': '2026-08-01T00:00:00Z',
          'capabilities': <String, Object?>{
            'effort': <String, Object?>{
              'supported': true,
              'low': true,
              'high': false,
              'max': true,
            },
          },
        },
        <String, Object?>{
          'id': 'claude-sonnet-4-6',
          'created_at': '2026-02-01T00:00:00Z',
        },
        <String, Object?>{
          'id': 'claude-text-only-1',
          'created_at': '2026-09-01T00:00:00Z',
          'capabilities': <String, Object?>{
            'image_input': <String, Object?>{'supported': false},
          },
        },
        <String, Object?>{
          'id': 'gpt-5.5',
          'created_at': '2026-09-01T00:00:00Z',
        },
      ]);

      expect(models.map((model) => model.id), <String>[
        'claude-mythos-1',
        'claude-opus-5',
        'claude-sonnet-4-6',
        'claude-haiku-4-5',
      ]);
      expect(models.map((model) => model.label), <String>[
        'Claude Mythos 1',
        'Claude Opus 5',
        'Claude Sonnet 4.6',
        'Claude Haiku 4.5',
      ]);
      expect(models.map((model) => model.supportsEffort), <bool>[
        true,
        true,
        true,
        false,
      ]);
      expect(models.map((model) => model.supportsThinking), <bool>[
        true,
        true,
        true,
        false,
      ]);
      expect(models[0].effortLevels, <String>['low', 'max']);
      expect(models[1].effortLevels, <String>['low', 'medium', 'high', 'max']);
      expect(
        models[2].effortLevels,
        isNull,
        reason: 'a listing that says nothing leaves the vocabulary alone',
      );
      expect(models[3].effortLevels, isNull);
      expect(models[1].createdAt, DateTime.utc(2026, 5));
    });

    test('falls back to the curated list when nothing survives', () {
      expect(
        anthropicRewriteModelsFromListing(const <Map<String, Object?>>[
          <String, Object?>{'id': 'gpt-5.5'},
        ]),
        RewriteProvider.anthropic.curatedModels,
      );
      expect(
        anthropicRewriteModelsFromListing(const <Map<String, Object?>>[]),
        RewriteProvider.anthropic.curatedModels,
      );
    });
  });

  test('both clients bound listings and rewrites separately', () {
    expect(OpenAiRewriteApi.listTimeout, const Duration(seconds: 20));
    expect(OpenAiRewriteApi.rewriteTimeout, const Duration(seconds: 90));
    expect(AnthropicRewriteApi.listTimeout, const Duration(seconds: 20));
    expect(AnthropicRewriteApi.rewriteTimeout, const Duration(seconds: 90));
  });
}

final Uri vendorBase = Uri.parse('https://vendor.test');

/// Two frames whose base64 is short enough to assert literally: `AQID` and
/// `BAUG`, with different media types so the encoding is pinned per frame.
List<RewriteFrame> testFrames() => <RewriteFrame>[
  RewriteFrame(bytes: Uint8List.fromList(<int>[1, 2, 3]), seconds: 0),
  RewriteFrame(
    bytes: Uint8List.fromList(<int>[4, 5, 6]),
    seconds: 2.5,
    mimeType: 'image/png',
  ),
];

PromptRewriteRequest rewriteRequest({
  required String providerId,
  required String modelId,
  String? effort,
}) => PromptRewriteRequest(
  providerId: providerId,
  modelId: modelId,
  effort: effort,
  originalPrompt: 'A three-toed sloth files a motion in a warm courtroom.',
  direction: 'Make the courtroom colder and the sloth slower.',
  frames: testFrames(),
  targetProviderName: 'Runway',
  targetModelName: 'gen4_turbo',
  maxPromptCharacters: 900,
  durationSeconds: 5,
  aspectRatio: '16:9',
  mode: 't2v',
  referenceMentions: const <String>['@Image 1'],
);

http.Response response(Object body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: const <String, String>{
    'content-type': 'application/json; charset=utf-8',
  },
);

http.Response ok(Object body) => response(body, 200);

/// A client that answers every call with a valid rewrite, for tests that only
/// read the payload the client would have sent.
MockClient silentClient() => MockClient(
  (call) async => ok(anthropicMessage('{"prompt":"P","summary":"S"}')),
);

Map<String, Object?> openAiCompleted(String text, {String model = 'gpt-5.5'}) =>
    <String, Object?>{
      'id': 'resp_1',
      'model': model,
      'status': 'completed',
      'output': <Object?>[
        <String, Object?>{'type': 'reasoning', 'summary': <Object?>[]},
        <String, Object?>{
          'type': 'message',
          'role': 'assistant',
          'content': <Object?>[
            <String, Object?>{'type': 'output_text', 'text': text},
          ],
        },
      ],
    };

Map<String, Object?> anthropicMessage(
  String text, {
  String model = 'claude-opus-5',
}) => <String, Object?>{
  'id': 'msg_1',
  'model': model,
  'stop_reason': 'end_turn',
  'content': <Object?>[
    <String, Object?>{'type': 'text', 'text': text},
  ],
};

Map<String, Object?> jsonBody(http.Request request) =>
    (jsonDecode(request.body) as Map<Object?, Object?>).map(
      (key, value) => MapEntry(key.toString(), value),
    );

Future<PromptRewriteException> rewriteFailure(
  PromptRewriteApi api,
  PromptRewriteRequest request,
) async {
  try {
    await api.rewrite(request, 'sk-test-key');
  } on PromptRewriteException catch (error) {
    return error;
  }
  fail('expected a PromptRewriteException for ${request.modelId}');
}
