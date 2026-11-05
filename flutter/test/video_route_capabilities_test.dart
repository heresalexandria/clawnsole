import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/apipod_model_contracts.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/provider_catalog.dart';
import 'package:clawnsole/ui/create_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(resetProviderCatalog);

  test(
    'source video requests preserve named references and source offsets',
    () {
      final controller = AppController(gateway: _MemoryGateway())
        ..snapshot = const LocalSnapshot(
          generations: [],
          preferences: AppPreferences(provider: 'apipod'),
          hasApiKey: true,
          connectedProviders: {'apipod'},
          availableProviders: {'apipod'},
          storage: StorageStats(path: 'memory', bytes: 0, records: 0),
        )
        ..selectedProviderId = 'apipod'
        ..selectedModelId = 'seedance-2.5-edit';
      addTearDown(controller.dispose);
      controller.form
        ..prompt = 'Use @actor and @motion.'
        ..aspectRatio = 'auto'
        ..videoUrl = 'https://cdn.example.com/source.mp4'
        ..references = const [
          MediaReferenceDraft(
            id: 'actor',
            label: 'Actor',
            kind: MediaReferenceKind.image,
            promptName: 'actor',
            source: 'https://cdn.example.com/actor.png',
          ),
          MediaReferenceDraft(
            id: 'motion',
            label: 'Motion',
            kind: MediaReferenceKind.video,
            promptName: 'motion',
            source: 'https://cdn.example.com/motion.mp4',
            durationSeconds: 4,
          ),
        ];
      expect(controller.validate(), isNull);
      final payload = apipodGenerationPayload(
        'seedance-2.5-edit',
        controller.buildInputForTesting(),
      );
      expect(payload['prompt'], 'Use @image1 and @video2.');
      expect(payload['video_urls'], [
        'https://cdn.example.com/source.mp4',
        'https://cdn.example.com/motion.mp4',
      ]);
    },
  );

  test('ordered middle frames retain roles and never invent timestamps', () {
    final controller = _controller('ordered');
    addTearDown(controller.dispose);
    controller.form.keyframes = [
      _frame('first', KeyframeRole.start),
      _frame('middle', KeyframeRole.middle),
    ];
    expect(controller.validate(), isNull);
    expect(controller.usesTimedKeyframes, isFalse);
    expect(controller.currentConfig.exactTiming, isFalse);
    expect(
      controller.currentConfig.keyframes!.map((frame) => frame.seconds),
      everyElement(isNull),
    );
    final input = controller.buildInputForTesting();
    expect(input['keyframes'], [
      'https://cdn.example.com/first.png',
      'https://cdn.example.com/middle.png',
    ]);
    expect(input['_clawnsole_keyframe_roles'], ['start', 'middle']);
  });

  test(
    'ordered frame capacity respects duration and the middle-frame limit',
    () {
      final controller = _controller('ordered');
      addTearDown(controller.dispose);
      controller.form.durationSeconds = 3;
      controller.form.keyframes = [
        _frame('first', KeyframeRole.start),
        for (var index = 0; index < 3; index++)
          _frame('middle$index', KeyframeRole.middle),
      ];
      expect(controller.keyframeLimit, 4);
      expect(controller.validate(), isNull);
      expect(controller.canAddFrame(KeyframeRole.middle), isFalse);
      controller.form.keyframes.add(_frame('extra', KeyframeRole.middle));
      expect(controller.validate(), contains('up to 4 keyframes'));
      controller.form.durationSeconds = 30;
      controller.form.keyframes = [
        _frame('first', KeyframeRole.start),
        for (var index = 0; index < 8; index++)
          _frame('middle$index', KeyframeRole.middle),
      ];
      expect(controller.validate(), isNull);
      expect(controller.canAddFrame(KeyframeRole.middle), isFalse);
      expect(controller.canAddFrame(KeyframeRole.end), isTrue);
      controller.form.keyframes.add(_frame('extra', KeyframeRole.middle));
      expect(controller.validate(), contains('up to 8 middle frames'));
    },
  );

  testWidgets(
    'ordered frame controls show chronological slots without timing',
    (tester) async {
      final controller = _controller('ordered');
      addTearDown(controller.dispose);
      controller.form.keyframes = [
        _frame('first', KeyframeRole.start),
        _frame('middle', KeyframeRole.middle),
      ];
      await _mount(tester, controller);
      await tester.tap(
        find.byKey(const ValueKey('keyframes-accordion-toggle')),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('middle frames follow attachment order'),
        findsOneWidget,
      );
      expect(find.text('Custom timing'), findsNothing);
      expect(find.byKey(const ValueKey('frame-time-middle')), findsNothing);
      expect(find.text('Middle'), findsOneWidget);
    },
  );

  test('motion transfer requires a target frame alongside its source', () {
    final controller = _controller('motion');
    addTearDown(controller.dispose);
    controller.form.videoUrl = 'https://cdn.example.com/motion.mp4';
    expect(controller.validate(), contains('first frame as well as'));
    controller.form.keyframes = [
      const KeyframeDraft(
        id: 'target',
        label: 'Target',
        role: KeyframeRole.start,
        seconds: 0,
        source: 'https://cdn.example.com/target.png',
      ),
    ];
    expect(controller.validate(), isNull);
    expect(controller.buildInputForTesting()['keyframes'], [
      'https://cdn.example.com/target.png',
    ]);
  });

  test(
    'irregular durations normalize and reject unsupported restored values',
    () {
      final controller = _controller('irregular');
      addTearDown(controller.dispose);
      expect(controller.selectedDurationRange.allowedSeconds, [
        5,
        10,
        20,
        30,
        40,
        50,
        60,
      ]);
      controller.setDurationSeconds(15);
      expect(controller.form.durationSeconds, 10);
      controller.form.durationSeconds = 15;
      expect(controller.validate(), contains('5, 10, 20, 30, 40, 50, 60'));
      controller.setDurationSeconds(20);
      expect(controller.validate(), isNull);
    },
  );

  test(
    'draft final uses a task ID and mode-specific resolution without media',
    () {
      final controller = _controller('draft');
      addTearDown(controller.dispose);
      expect(controller.availableResolutions.map((item) => item.id), ['sd']);
      controller.updateForm((form) => form.draftUrl = 'vid_task_123');
      expect(controller.form.mode, VideoMode.draftEnhance);
      expect(controller.availableResolutions.map((item) => item.id), ['fhd']);
      expect(controller.form.resolution, 'fhd');
      expect(controller.validate(), isNull);
      expect(controller.buildInputForTesting(), {
        'mode': 'draft_enhance',
        'draft_task_id': 'vid_task_123',
        'resolution': 'fhd',
      });
      final saved = GenerationConfig.fromJson(
        controller.currentConfig.toJson(),
      );
      expect(saved.source, isNull);
      expect(saved.sourceLabel, 'vid_task_123');
      controller.form.draftUrl = 'https://cdn.example.com/preview.mp4';
      expect(controller.validate(), contains('not a file or URL'));
      controller.updateForm((form) => form.draftUrl = '');
      expect(controller.form.resolution, 'sd');
    },
  );

  test(
    'ready previews enhance with their provider request ID and retain it on reuse',
    () async {
      final controller = _controller('draft');
      addTearDown(controller.dispose);
      final preview = _generation(controller.currentConfig, VideoMode.t2v);
      expect(controller.canEnhance(preview), isTrue);
      controller.enhance(preview);
      expect(controller.selectedProviderId, 'fixture');
      expect(controller.selectedModelId, 'draft');
      expect(controller.form.draftUrl, 'provider-preview-123');
      final finalRender = _generation(
        controller.currentConfig,
        VideoMode.draftEnhance,
      );
      expect(controller.canEnhance(finalRender), isFalse);
      expect(
        controller.canEnhance(preview.copyWith(status: 'Pending')),
        isFalse,
      );
      await controller.reuse(Generation.fromJson(finalRender.toJson()));
      expect(controller.form.draftUrl, 'provider-preview-123');
      expect(
        controller.buildInputForTesting()['draft_task_id'],
        'provider-preview-123',
      );
    },
  );

  testWidgets('irregular duration picker offers exactly the supported values', (
    tester,
  ) async {
    final controller = _controller('irregular');
    addTearDown(controller.dispose);
    await _mount(tester, controller);
    expect(find.byKey(const ValueKey('duration-slider')), findsNothing);
    final picker = tester.widget<DropdownButtonFormField<int>>(
      find.byType(DropdownButtonFormField<int>),
    );
    // The explicit choices are rendered by the field rather than invented
    // slider steps such as 15, 25, or 35 seconds.
    expect(picker.initialValue, 5);
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    expect(find.text('20 seconds'), findsWidgets);
    expect(find.text('15 seconds'), findsNothing);
  });

  testWidgets('task draft editor hides media upload and inherited settings', (
    tester,
  ) async {
    final controller = _controller('draft');
    addTearDown(controller.dispose);
    controller.updateForm((form) => form.draftUrl = 'provider-preview-123');
    await _mount(tester, controller);
    expect(find.text('Render a completed draft'), findsOneWidget);
    expect(find.text('Completed draft task ID'), findsOneWidget);
    expect(find.text('Choose file'), findsNothing);
    expect(find.byKey(const ValueKey('duration-input')), findsNothing);
    expect(find.text('Synchronized audio'), findsNothing);
    expect(find.text('Frame'), findsNothing);
  });

  test(
    'public source video routes reject local picking before file access',
    () async {
      final controller = _controller('draft');
      addTearDown(controller.dispose);
      await controller.pickVideo();
      expect(controller.notice, contains('public HTTPS media URLs'));
      expect(controller.form.videoAsset, isNull);
    },
  );
}

const _provider = VideoProviderDefinition(
  id: 'fixture',
  name: 'Fixture',
  description: '',
  consoleUrl: 'https://example.com/',
  docsUrl: 'https://example.com/',
  pricingUrl: 'https://example.com/',
  requiresApiKey: false,
  models: [
    VideoModelDefinition(
      id: 'ordered',
      label: 'Ordered frames',
      description: '',
      modes: [VideoMode.i2v],
      aspectRatios: ['auto'],
      resolutions: [VideoResolutionDefinition('hd', 'HD', '')],
      minDuration: 3,
      maxDuration: 30,
      durationStep: 1,
      maxKeyframes: 10,
      maxMiddleFrames: 8,
      maxKeyframesPerSecond: 1,
      supportsOrderedMiddleFrames: true,
      supportsStartFrame: true,
      supportsEndFrame: true,
      requiresStartFrameWhenUsingFrames: true,
      requiresPublicMediaUrls: true,
      usdPerSecond: 0,
    ),
    VideoModelDefinition(
      id: 'motion',
      label: 'Motion transfer',
      description: '',
      modes: [VideoMode.v2v],
      aspectRatios: ['auto'],
      resolutions: [VideoResolutionDefinition('hd', 'HD', '')],
      minDuration: 3,
      maxDuration: 10,
      durationStep: 1,
      maxKeyframes: 1,
      usdPerSecond: 0,
      supportsStartFrame: true,
      requiresStartFrameWithSource: true,
      supportsGuidanceWithSource: true,
      requiresPublicMediaUrls: true,
    ),
    VideoModelDefinition(
      id: 'irregular',
      label: 'Irregular duration',
      description: '',
      modes: [VideoMode.t2v],
      aspectRatios: ['16:9'],
      resolutions: [VideoResolutionDefinition('hd', 'HD', '')],
      minDuration: 5,
      maxDuration: 60,
      durationStep: 5,
      durationOptions: [5, 10, 20, 30, 40, 50, 60],
      maxKeyframes: 0,
      usdPerSecond: 0,
    ),
    VideoModelDefinition(
      id: 'draft',
      label: 'Draft workflow',
      description: '',
      modes: [VideoMode.t2v, VideoMode.i2v, VideoMode.draftEnhance],
      aspectRatios: ['auto', '16:9'],
      resolutions: [
        VideoResolutionDefinition('sd', 'Preview', ''),
        VideoResolutionDefinition('fhd', 'Final', ''),
      ],
      resolutionsByMode: {
        VideoMode.t2v: ['sd'],
        VideoMode.i2v: ['sd'],
        VideoMode.draftEnhance: ['fhd'],
      },
      minDuration: 4,
      maxDuration: 30,
      durationStep: 1,
      maxKeyframes: 0,
      maxImageReferences: 30,
      usdPerSecond: 0,
      requiresPublicMediaUrls: true,
      draftSourceIsTaskId: true,
    ),
  ],
);

KeyframeDraft _frame(String id, KeyframeRole role) => KeyframeDraft(
  id: id,
  label: id,
  role: role,
  seconds: 0,
  source: 'https://cdn.example.com/$id.png',
);

AppController _controller(String model) {
  final controller = AppController(gateway: _MemoryGateway());
  installProviderCatalog([_provider]);
  controller
    ..snapshot = _snapshot
    ..loading = false
    ..selectedProviderId = 'fixture'
    ..selectedModelId = model;
  controller.form
    ..prompt = 'A quiet forest.'
    ..durationSeconds = 5
    ..resolution = model == 'draft' ? 'sd' : 'hd';
  return controller;
}

Generation _generation(GenerationConfig config, VideoMode mode) => Generation(
  localId: 'local-${mode.name}',
  provider: 'fixture',
  model: 'draft',
  requestId: 'provider-preview-123',
  status: 'Ready',
  prompt: 'A forest.',
  mode: mode,
  config: config,
  createdAt: DateTime.utc(2026, 11, 5),
  updatedAt: DateTime.utc(2026, 11, 5),
);

const _snapshot = LocalSnapshot(
  generations: [],
  preferences: AppPreferences(provider: 'fixture'),
  hasApiKey: false,
  availableProviders: {'fixture'},
  storage: StorageStats(path: 'memory', bytes: 0, records: 0),
);

Future<void> _mount(WidgetTester tester, AppController controller) async {
  await tester.binding.setSurfaceSize(const Size(1400, 1400));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: buildClawnsoleTheme(Brightness.light),
      home: Scaffold(body: CreateScreen(controller: controller)),
    ),
  );
}

class _MemoryGateway implements AppGateway {
  @override
  bool get usesCompanion => false;
  @override
  bool get supportsPhotoLibrarySave => false;
  @override
  String get persistenceDescription => 'Memory';
  @override
  Uri mediaUri(String source) => Uri.parse(source);
  @override
  Future<LocalSnapshot> setPreferences(AppPreferences preferences) async =>
      _snapshot;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
