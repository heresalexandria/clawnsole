import 'dart:convert';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/web_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Reuse restores the aesthetic as a choice. The words it appends never land
/// in the prompt box again — they go back to the Aesthetic key, or, when the
/// library has moved on since the render, to a Custom definition.
void main() {
  test('reuse selects the aesthetic and leaves the prompt clean', () async {
    final controller = _controller();
    addTearDown(controller.dispose);
    final id = controller.saveAestheticReference(
      title: 'Golden hour',
      text: 'Warm amber light.',
      icon: 'sun',
      color: 0xffaf853c,
    );

    await controller.reuse(
      _film(
        prompt: 'A sloth reads.\n\nWarm amber light.',
        aestheticReferenceId: id,
        aestheticTitle: 'Golden hour',
        aestheticText: 'Warm amber light.',
      ),
    );

    expect(controller.form.prompt, 'A sloth reads.');
    expect(controller.selectedAestheticReference?.id, id);
    expect(controller.hasCustomAestheticText, isFalse);
    expect(controller.generationPrompt, 'A sloth reads.\n\nWarm amber light.');
  });

  test('an aesthetic edited since the render comes back as Custom', () async {
    final controller = _controller();
    addTearDown(controller.dispose);
    final id = controller.saveAestheticReference(
      title: 'Golden hour',
      text: 'Cool moonlight now.',
      icon: 'sun',
      color: 0xffaf853c,
    );

    await controller.reuse(
      _film(
        prompt: 'A sloth reads.\n\nWarm amber light.',
        aestheticReferenceId: id,
        aestheticTitle: 'Golden hour',
        aestheticText: 'Warm amber light.',
      ),
    );

    expect(controller.form.prompt, 'A sloth reads.');
    expect(controller.selectedAestheticReference?.id, id);
    expect(controller.form.aestheticCustomText, 'Warm amber light.');
    expect(controller.aestheticDefinitionLabel, 'Custom');
    expect(controller.generationPrompt, 'A sloth reads.\n\nWarm amber light.');
    // The library keeps its own words.
    expect(controller.aestheticReferences.single.text, 'Cool moonlight now.');
  });

  test('an aesthetic deleted since the render survives as Custom', () async {
    final controller = _controller();
    addTearDown(controller.dispose);

    await controller.reuse(
      _film(
        prompt: 'A sloth reads.\n\nWarm amber light.',
        aestheticReferenceId: 'gone',
        aestheticTitle: 'Golden hour',
        aestheticText: 'Warm amber light.',
      ),
    );

    expect(controller.form.prompt, 'A sloth reads.');
    expect(controller.selectedAestheticReference, isNull);
    expect(controller.form.aestheticCustomText, 'Warm amber light.');
    expect(controller.hasAestheticDefinition, isTrue);
    expect(controller.generationPrompt, 'A sloth reads.\n\nWarm amber light.');
  });

  test('the same words under a different aesthetic still select it', () async {
    final controller = _controller();
    addTearDown(controller.dispose);
    final id = controller.saveAestheticReference(
      title: 'Amber',
      text: 'Warm amber light.',
      icon: 'sun',
      color: 0xffaf853c,
    );

    await controller.reuse(
      _film(
        prompt: 'A sloth reads.\n\nWarm amber light.',
        aestheticReferenceId: 'a-copy-that-is-gone',
        aestheticTitle: 'Golden hour',
        aestheticText: 'Warm amber light.',
      ),
    );

    expect(controller.selectedAestheticReference?.id, id);
    expect(controller.hasCustomAestheticText, isFalse);
    expect(controller.form.prompt, 'A sloth reads.');
  });

  test('a film from before the record carried its aesthetic', () async {
    final controller = _controller();
    addTearDown(controller.dispose);
    final id = controller.saveAestheticReference(
      title: 'Golden hour',
      text: 'Warm amber light.',
      icon: 'sun',
      color: 0xffaf853c,
    );

    await controller.reuse(
      _film(prompt: 'A sloth reads.\n\nWarm amber light.'),
    );

    expect(controller.selectedAestheticReference?.id, id);
    expect(controller.form.prompt, 'A sloth reads.');
  });

  test('an unrecognized trailing paragraph stays in the prompt', () async {
    final controller = _controller();
    addTearDown(controller.dispose);
    controller.saveAestheticReference(
      title: 'Golden hour',
      text: 'Warm amber light.',
      icon: 'sun',
      color: 0xffaf853c,
    );

    await controller.reuse(
      _film(prompt: 'A sloth reads.\n\nThe lamp buzzes faintly.'),
    );

    expect(
      controller.form.prompt,
      'A sloth reads.\n\nThe lamp buzzes faintly.',
    );
    expect(controller.selectedAestheticReference, isNull);
    expect(controller.hasCustomAestheticText, isFalse);
  });

  test(
    'legacy casting lines stay in the direction when reusing a film',
    () async {
      final controller = _controller();
      addTearDown(controller.dispose);
      final id = controller.saveAestheticReference(
        title: 'Golden hour',
        text: 'Warm amber light.',
        icon: 'sun',
        color: 0xffaf853c,
      );

      await controller.reuse(
        _film(
          prompt: 'A sloth reads.\n\nHERO: @Sloth\n\nWarm amber light.',
          aestheticReferenceId: id,
          aestheticTitle: 'Golden hour',
          aestheticText: 'Warm amber light.',
          references: const <MediaReferenceLabel>[
            MediaReferenceLabel(
              label: 'sloth.png',
              kind: MediaReferenceKind.image,
              promptName: 'Sloth',
              source: AssetReference(
                kind: 'remote',
                value: 'https://example.invalid/sloth.png',
                label: 'sloth.png',
              ),
            ),
          ],
        ),
      );

      expect(controller.form.prompt, 'A sloth reads.\n\nHERO: @Sloth');
      expect(controller.form.characterMappings, isEmpty);
      expect(controller.selectedAestheticReference?.id, id);
      expect(
        controller.generationPrompt,
        'A sloth reads.\n\nHERO: @Sloth\n\nWarm amber light.',
      );
    },
  );

  test('reuse into a busy studio opens a tab with the same choice', () async {
    final controller = _controller();
    addTearDown(controller.dispose);
    final id = controller.saveAestheticReference(
      title: 'Golden hour',
      text: 'Warm amber light.',
      icon: 'sun',
      color: 0xffaf853c,
    );
    controller.updateForm((form) => form.prompt = 'Something else entirely.');

    await controller.reuse(
      _film(
        prompt: 'A sloth reads.\n\nWarm amber light.',
        aestheticReferenceId: id,
        aestheticTitle: 'Golden hour',
        aestheticText: 'Warm amber light.',
      ),
    );

    expect(controller.composerTabs, hasLength(2));
    expect(controller.form.prompt, 'A sloth reads.');
    expect(controller.selectedAestheticReference?.id, id);
    expect(controller.composerTabs.first.form.aestheticReferenceId, isNull);
  });
  test('a rewrite that keeps the aesthetic block keeps the choice', () async {
    final controller = _controller();
    addTearDown(controller.dispose);
    final id = controller.saveAestheticReference(
      title: 'Golden hour',
      text: 'Warm amber light.',
      icon: 'sun',
      color: 0xffaf853c,
    );
    final film = _film(
      prompt: 'A sloth reads.\n\nWarm amber light.',
      aestheticReferenceId: id,
      aestheticTitle: 'Golden hour',
      aestheticText: 'Warm amber light.',
    );

    await controller.openGenerationInNewTab(
      film,
      prompt: 'A sloth turns a page.\n\nWarm amber light.',
      rewriteSummary: 'Gave the sloth something to do.',
    );

    expect(controller.form.prompt, 'A sloth turns a page.');
    expect(controller.selectedAestheticReference?.id, id);
    expect(
      controller.generationPrompt,
      'A sloth turns a page.\n\nWarm amber light.',
    );
  });

  test('a rewrite that reworks the aesthetic words owns them', () async {
    final controller = _controller();
    addTearDown(controller.dispose);
    final id = controller.saveAestheticReference(
      title: 'Golden hour',
      text: 'Warm amber light.',
      icon: 'sun',
      color: 0xffaf853c,
    );
    final film = _film(
      prompt: 'A sloth reads.\n\nWarm amber light.',
      aestheticReferenceId: id,
      aestheticTitle: 'Golden hour',
      aestheticText: 'Warm amber light.',
    );

    await controller.openGenerationInNewTab(
      film,
      prompt: 'A sloth turns a page in warm amber light with long shadows.',
      rewriteSummary: 'Folded the light into the action.',
    );

    // Nothing is appended twice: the rewritten prompt is the whole direction.
    expect(controller.selectedAestheticReference, isNull);
    expect(controller.hasCustomAestheticText, isFalse);
    expect(
      controller.generationPrompt,
      'A sloth turns a page in warm amber light with long shadows.',
    );
  });

  test('what a render records is what reuse reads back', () async {
    const snapshot = LocalSnapshot(
      generations: [],
      preferences: AppPreferences(),
      hasApiKey: false,
      connectedProviders: {'runway'},
      storage: StorageStats(path: 'memory', bytes: 0, records: 0),
    );
    final submissions = <Map<String, dynamic>>[];
    final gateway = WebGateway(
      baseUrl: Uri.parse('http://127.0.0.1:8787'),
      client: MockClient((request) async {
        switch (request.url.path) {
          case '/account':
            return http.Response(jsonEncode({'provider': 'runway'}), 200);
          case '/generations':
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            submissions.add(body);
            return http.Response(
              jsonEncode({'generation': body['record']}),
              201,
            );
          case '/composer-tabs':
            return http.Response('{}', 200);
          case '/action':
            return http.Response(jsonEncode(snapshot.toJson()), 200);
          default:
            throw StateError('Unexpected request: \${request.url}');
        }
      }),
    );
    final controller = AppController(gateway: gateway)
      ..snapshot = snapshot
      ..loading = false
      ..selectedProviderId = 'runway'
      ..selectedModelId = 'seedance2_5';
    addTearDown(controller.dispose);
    final id = controller.saveAestheticReference(
      title: 'Golden hour',
      text: 'Warm amber light.',
      icon: 'sun',
      color: 0xffaf853c,
    );
    controller
      ..updateForm((form) => form.prompt = 'A sloth reads.')
      ..selectAestheticReference(id)
      ..updateAestheticCustomText('Warm amber light, long shadows.');

    await controller.submit(providerRetentionRiskAcknowledged: true);

    expect(submissions, hasLength(1), reason: controller.notice);
    final record = Generation.fromJson(
      Map<String, Object?>.from(
        submissions.single['record']! as Map<String, dynamic>,
      ),
    );
    expect(record.prompt, 'A sloth reads.\n\nWarm amber light, long shadows.');
    expect(record.aestheticReferenceId, id);
    expect(record.aestheticTitle, 'Golden hour');
    expect(record.aestheticText, 'Warm amber light, long shadows.');

    controller.addComposerTab();
    await controller.reuse(record);

    expect(controller.form.prompt, 'A sloth reads.');
    expect(controller.selectedAestheticReference?.id, id);
    expect(
      controller.form.aestheticCustomText,
      'Warm amber light, long shadows.',
    );
  });
}

Generation _film({
  required String prompt,
  String? aestheticReferenceId,
  String? aestheticTitle,
  String? aestheticText,
  List<MediaReferenceLabel> references = const <MediaReferenceLabel>[],
}) {
  final now = DateTime.utc(2026, 9, 1);
  return Generation(
    localId: 'film-1',
    status: 'Ready',
    prompt: prompt,
    mode: VideoMode.t2v,
    provider: 'artcraft',
    model: 'seedance_2p5',
    config: GenerationConfig(
      aspectRatio: '16:9',
      duration: 8,
      resolution: 'hd',
      generateAudio: true,
      safetyTolerance: 2,
      draft: false,
      references: references.isEmpty ? null : references,
    ),
    aestheticReferenceId: aestheticReferenceId,
    aestheticTitle: aestheticTitle,
    aestheticText: aestheticText,
    resultUrl: 'https://example.invalid/film-1.mp4',
    createdAt: now,
    updatedAt: now,
  );
}

AppController _controller() => AppController(gateway: _ReuseGateway())
  ..selectedProviderId = 'artcraft'
  ..selectedModelId = 'seedance_2p5'
  ..loading = false
  ..snapshot = const LocalSnapshot(
    generations: [],
    preferences: AppPreferences(),
    hasApiKey: false,
    storage: StorageStats(path: 'memory', bytes: 0, records: 0),
  );

class _ReuseGateway implements AppGateway {
  @override
  bool get usesCompanion => false;

  @override
  bool get supportsPhotoLibrarySave => false;

  @override
  String get persistenceDescription => 'Memory';

  @override
  Future<LocalSnapshot> load() async => const LocalSnapshot(
    generations: [],
    preferences: AppPreferences(),
    hasApiKey: false,
    storage: StorageStats(path: 'memory', bytes: 0, records: 0),
  );

  @override
  Future<LocalSnapshot> setPreferences(AppPreferences preferences) async =>
      LocalSnapshot(
        generations: const [],
        preferences: preferences,
        hasApiKey: false,
        storage: const StorageStats(path: 'memory', bytes: 0, records: 0),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
