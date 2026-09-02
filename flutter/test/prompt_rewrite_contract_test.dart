import 'dart:convert';
import 'dart:typed_data';

import 'package:clawnsole/core/prompt_rewrite.dart';
import 'package:clawnsole/core/prompt_rewrite_router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rewrite providers expose ids, consoles, and effort vocabularies', () {
    expect(rewriteProviderIds, <String>['openai', 'anthropic']);
    expect(RewriteProvider.byId('openai'), RewriteProvider.openai);
    expect(RewriteProvider.byId('anthropic'), RewriteProvider.anthropic);
    expect(RewriteProvider.byId('bfl'), isNull);
    expect(RewriteProvider.byId(null), isNull);
    for (final provider in RewriteProvider.values) {
      expect(provider.consoleUrl, startsWith('https://'));
      expect(provider.effortLevels, contains(provider.defaultEffort));
      expect(
        provider.curatedModels.map((model) => model.id),
        contains(provider.defaultModelId),
      );
      expect(
        provider.curatedModels.map((model) => model.id).toSet().length,
        provider.curatedModels.length,
        reason: 'curated ids are unique',
      );
    }
  });

  test('effort levels narrow per model but never widen', () {
    const anthropic = RewriteProvider.anthropic;
    expect(anthropic.effortLevelsFor('claude-opus-5'), <String>[
      'low',
      'medium',
      'high',
      'xhigh',
      'max',
    ]);
    expect(anthropic.effortLevelsFor('claude-opus-4-6'), <String>[
      'low',
      'medium',
      'high',
      'max',
    ]);
    expect(anthropic.effortLevelsFor('claude-haiku-4-5'), isEmpty);
    expect(
      anthropic.effortLevelsFor('claude-unknown-9'),
      anthropic.effortLevels,
      reason: 'unknown ids get the provider vocabulary',
    );
    expect(
      anthropic.effortLevelsFor(
        'listed',
        model: const RewriteModel(
          id: 'listed',
          label: 'Listed',
          effortLevels: <String>['low', 'ultra'],
        ),
      ),
      <String>['low'],
    );
    expect(RewriteProvider.openai.effortLevelsFor('gpt-4.1'), isEmpty);
    expect(RewriteProvider.openai.effortLevelsFor('gpt-5.5'), <String>[
      'low',
      'medium',
      'high',
      'xhigh',
    ]);
  });

  test('model labels derive from ids', () {
    expect(rewriteModelLabel('gpt-5.5'), 'GPT-5.5');
    expect(rewriteModelLabel('gpt-5.4-mini'), 'GPT-5.4 mini');
    expect(rewriteModelLabel('o4-mini'), 'o4-mini');
    expect(rewriteModelLabel('claude-opus-5'), 'Claude Opus 5');
    expect(rewriteModelLabel('claude-sonnet-4-6'), 'Claude Sonnet 4 6');
    expect(rewriteModelLabel(''), '');
  });

  test('rewrite models round-trip through JSON', () {
    final model = RewriteModel(
      id: 'gpt-5.5',
      label: 'GPT-5.5',
      supportsEffort: true,
      supportsThinking: false,
      effortLevels: const <String>['low', 'high'],
      createdAt: DateTime.utc(2026, 4, 22),
    );
    final decoded = RewriteModel.fromJson(
      jsonDecode(jsonEncode(model.toJson())) as Map<String, Object?>,
    );
    expect(decoded.id, 'gpt-5.5');
    expect(decoded.label, 'GPT-5.5');
    expect(decoded.supportsEffort, isTrue);
    expect(decoded.supportsThinking, isFalse);
    expect(decoded.effortLevels, <String>['low', 'high']);
    expect(decoded.createdAt, DateTime.utc(2026, 4, 22));
    final sparse = RewriteModel.fromJson(<String, Object?>{'id': 'x'});
    expect(sparse.label, 'x');
    expect(sparse.supportsEffort, isTrue);
    expect(sparse.effortLevels, isNull);
  });

  test('rewrite requests and results round-trip through JSON', () {
    final request = PromptRewriteRequest(
      providerId: 'anthropic',
      modelId: 'claude-opus-5',
      effort: 'max',
      originalPrompt: 'A red kite over dunes',
      direction: 'Make the kite blue and slow the pan',
      frames: <RewriteFrame>[
        RewriteFrame(bytes: Uint8List.fromList(<int>[1, 2, 3]), seconds: 0),
        RewriteFrame(
          bytes: Uint8List.fromList(<int>[4, 5]),
          seconds: 3.5,
          mimeType: 'image/png',
        ),
      ],
      targetProviderName: 'ArtCraft',
      targetModelName: 'Seedance 2.5',
      maxPromptCharacters: 10000,
      durationSeconds: 8,
      aspectRatio: '16:9',
      mode: 'i2v',
      referenceMentions: const <String>['@Image 1'],
    );
    final json =
        jsonDecode(jsonEncode(request.toJson())) as Map<String, Object?>;
    final decoded = PromptRewriteRequest.fromJson(json);
    expect(decoded.providerId, 'anthropic');
    expect(decoded.modelId, 'claude-opus-5');
    expect(decoded.effort, 'max');
    expect(decoded.originalPrompt, request.originalPrompt);
    expect(decoded.direction, request.direction);
    expect(decoded.frames, hasLength(2));
    expect(decoded.frames.first.bytes, <int>[1, 2, 3]);
    expect(decoded.frames.last.seconds, 3.5);
    expect(decoded.frames.last.mimeType, 'image/png');
    expect(decoded.targetProviderName, 'ArtCraft');
    expect(decoded.targetModelName, 'Seedance 2.5');
    expect(decoded.maxPromptCharacters, 10000);
    expect(decoded.durationSeconds, 8);
    expect(decoded.aspectRatio, '16:9');
    expect(decoded.mode, 'i2v');
    expect(decoded.referenceMentions, <String>['@Image 1']);

    final result = PromptRewriteResult.fromJson(
      const PromptRewriteResult(
        prompt: 'A blue kite',
        summary: 'Kite recolored',
        providerId: 'anthropic',
        modelId: 'claude-opus-5',
      ).toJson(),
    );
    expect(result.prompt, 'A blue kite');
    expect(result.summary, 'Kite recolored');
    expect(result.modelId, 'claude-opus-5');
    expect(
      PromptRewriteRequest.fromJson(<String, Object?>{
        'frames': <Object?>[
          <String, Object?>{'data': ''},
        ],
      }).frames,
      isEmpty,
      reason: 'empty frames are dropped',
    );
  });

  test('instructions carry the target, limit, mentions, and JSON contract', () {
    final request = PromptRewriteRequest(
      providerId: 'openai',
      modelId: 'gpt-5.5',
      originalPrompt: 'Original',
      direction: 'Direction',
      targetProviderName: 'Runway',
      targetModelName: 'Gen-5',
      maxPromptCharacters: 1500,
      referenceMentions: const <String>['@Image 1', '@Hero'],
    );
    final instructions = buildRewriteInstructions(request);
    expect(instructions, contains('using Runway Gen-5'));
    expect(instructions, contains('under 1500 characters'));
    expect(instructions, contains('@Image 1, @Hero'));
    expect(instructions, contains('"prompt"'));
    expect(instructions, contains('"summary"'));

    final bare = buildRewriteInstructions(
      const PromptRewriteRequest(
        providerId: 'openai',
        modelId: 'gpt-5.5',
        originalPrompt: 'o',
        direction: 'd',
      ),
    );
    expect(bare, isNot(contains('using ')));
    expect(bare, isNot(contains('characters in total')));
    expect(bare, isNot(contains('reference mentions')));
  });

  test('the brief states facts, the prompt, and the change request', () {
    final brief = buildRewriteBrief(
      PromptRewriteRequest(
        providerId: 'openai',
        modelId: 'gpt-5.5',
        originalPrompt: '  Original prompt  ',
        direction: ' Change it ',
        durationSeconds: 8,
        aspectRatio: '9:16',
        mode: 't2v',
        frames: <RewriteFrame>[
          RewriteFrame(bytes: Uint8List.fromList(<int>[1]), seconds: 0),
          RewriteFrame(bytes: Uint8List.fromList(<int>[1]), seconds: 7.96),
        ],
      ),
    );
    expect(brief, contains('Mode: text to video'));
    expect(brief, contains('Duration: 8 s'));
    expect(brief, contains('Aspect ratio: 9:16'));
    expect(brief, contains('Frames attached: 2 (0 s, 8 s)'));
    expect(brief, contains('ORIGINAL PROMPT:\nOriginal prompt\n'));
    expect(brief, endsWith('CHANGE REQUEST:\nChange it'));
    expect(rewriteFrameLabel(0, 8, 2.5), 'Frame 1 of 8 at 2.5 s');
  });

  test('output schema is strict-mode compatible', () {
    expect(rewriteOutputSchema['type'], 'object');
    expect(rewriteOutputSchema['additionalProperties'], isFalse);
    expect(rewriteOutputSchema['required'], <String>['prompt', 'summary']);
    final properties =
        rewriteOutputSchema['properties'] as Map<String, Object?>;
    expect(properties.keys, <String>['prompt', 'summary']);
    expect(rewriteOutputSchemaName, 'prompt_rewrite');
    expect(jsonEncode(rewriteOutputSchema), isNotEmpty);
  });

  test('parseRewriteOutput accepts plain, fenced, and wrapped JSON', () {
    const json = '{"prompt": "  New prompt ", "summary": "Changed"}';
    final plain = parseRewriteOutput(json, providerId: 'openai', modelId: 'm');
    expect(plain.prompt, 'New prompt');
    expect(plain.summary, 'Changed');
    expect(plain.providerId, 'openai');
    expect(plain.modelId, 'm');

    final fenced = parseRewriteOutput(
      'Here you go:\n```json\n$json\n```\nDone.',
      providerId: 'anthropic',
      modelId: 'm',
    );
    expect(fenced.prompt, 'New prompt');

    final wrapped = parseRewriteOutput(
      'Sure! $json Anything else?',
      providerId: 'anthropic',
      modelId: 'm',
    );
    expect(wrapped.summary, 'Changed');

    final noSummary = parseRewriteOutput(
      '{"prompt": "Only prompt"}',
      providerId: 'openai',
      modelId: 'm',
    );
    expect(noSummary.summary, '');

    for (final bad in <String>[
      '',
      '   ',
      'not json',
      '{"summary": "x"}',
      '[]',
    ]) {
      expect(
        () => parseRewriteOutput(bad, providerId: 'openai', modelId: 'm'),
        throwsA(
          isA<PromptRewriteException>().having(
            (error) => error.failure,
            'failure',
            PromptRewriteFailure.invalidResponse,
          ),
        ),
        reason: 'input: "$bad"',
      );
    }
  });

  test(
    'the router dispatches by provider id and rejects unknown ones',
    () async {
      final openai = _FakeRewriteApi('openai');
      final anthropic = _FakeRewriteApi('anthropic');
      final router = PromptRewriteRouter(
        apis: <String, PromptRewriteApi>{
          'openai': openai,
          'anthropic': anthropic,
        },
      );
      final models = await router.listModels(
        providerId: 'anthropic',
        apiKey: 'sk-ant-test',
      );
      expect(models.single.id, 'anthropic-model');
      expect(anthropic.keys, <String>['sk-ant-test']);

      final result = await router.rewrite(
        const PromptRewriteRequest(
          providerId: 'openai',
          modelId: 'gpt-5.5',
          originalPrompt: 'o',
          direction: 'd',
        ),
        apiKey: 'sk-test',
      );
      expect(result.providerId, 'openai');
      expect(openai.keys, <String>['sk-test']);
      expect(
        () => router.listModels(providerId: 'bfl', apiKey: 'k'),
        throwsA(
          isA<PromptRewriteException>().having(
            (error) => error.failure,
            'failure',
            PromptRewriteFailure.badRequest,
          ),
        ),
      );
      expect(
        PromptRewriteRouter().apiFor('openai').runtimeType.toString(),
        'OpenAiRewriteApi',
      );
      expect(
        PromptRewriteRouter().apiFor('anthropic').runtimeType.toString(),
        'AnthropicRewriteApi',
      );
    },
  );
}

class _FakeRewriteApi implements PromptRewriteApi {
  _FakeRewriteApi(this.providerId);

  final String providerId;
  final List<String> keys = <String>[];

  @override
  Future<List<RewriteModel>> listModels(String apiKey) async {
    keys.add(apiKey);
    return <RewriteModel>[
      RewriteModel(id: '$providerId-model', label: '$providerId model'),
    ];
  }

  @override
  Future<PromptRewriteResult> rewrite(
    PromptRewriteRequest request,
    String apiKey,
  ) async {
    keys.add(apiKey);
    return PromptRewriteResult(
      prompt: 'rewritten ${request.originalPrompt}',
      summary: 'ok',
      providerId: providerId,
      modelId: request.modelId,
    );
  }
}
