import 'dart:typed_data';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/provider_catalog.dart';
import 'package:clawnsole/ui/create_screen.dart';
import 'package:clawnsole/ui/common_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('hosted keyframes survive request preparation unchanged', () {
    final controller = _controller('seedance-2.5-i2v');
    addTearDown(controller.dispose);
    controller.form.keyframes = <KeyframeDraft>[
      KeyframeDraft(
        id: 'first',
        label: 'First',
        role: KeyframeRole.start,
        seconds: 0,
        source: 'https://cdn.example.com/first.png',
      ),
    ];

    expect(controller.validate(), isNull);
    expect(controller.buildInputForTesting()['keyframes'], <String>[
      'https://cdn.example.com/first.png',
    ]);
  });

  test('restored local frames and data URLs fail before submission', () {
    final controller = _controller('seedance-2.5-i2v');
    addTearDown(controller.dispose);
    for (final source in <String>[
      'data:image/png;base64,AAAA',
      'file:///tmp/frame.png',
      'https://localhost/frame.png',
      'https://127.0.0.1/frame.png',
      'https://user:secret@cdn.example.com/frame.png',
    ]) {
      controller.form.keyframes = <KeyframeDraft>[
        KeyframeDraft(
          id: 'first',
          label: 'First',
          role: KeyframeRole.start,
          seconds: 0,
          source: source,
        ),
      ];
      expect(controller.validate(), contains('public HTTPS media URLs'));
    }
    controller.form.keyframes = <KeyframeDraft>[
      KeyframeDraft(
        id: 'first',
        label: 'First',
        role: KeyframeRole.start,
        seconds: 0,
        source: 'https://cdn.example.com/original.png',
        asset: _localImage(),
      ),
    ];
    expect(controller.validate(), contains('public HTTPS media URLs'));
  });

  test('positional frame routes reject an end frame without a first frame', () {
    final controller = _controller('seedance-2.5-i2v');
    addTearDown(controller.dispose);
    controller.form.keyframes = <KeyframeDraft>[
      const KeyframeDraft(
        id: 'last',
        label: 'Last',
        role: KeyframeRole.end,
        seconds: 4,
        source: 'https://cdn.example.com/last.png',
      ),
    ];
    expect(controller.validate(), contains('needs a first frame'));
    controller.form.keyframes.add(
      const KeyframeDraft(
        id: 'first',
        label: 'First',
        role: KeyframeRole.start,
        seconds: 0,
        source: 'https://cdn.example.com/first.png',
      ),
    );
    expect(controller.validate(), isNull);
    expect(controller.buildInputForTesting()['keyframes'], <String>[
      'https://cdn.example.com/first.png',
      'https://cdn.example.com/last.png',
    ]);
  });

  test(
    'references accept hosted URLs and reject picked or saved files',
    () async {
      final controller = _controller('seedance-2.5-r2v');
      addTearDown(controller.dispose);
      await controller.attachPickedReferences(MediaReferenceKind.image, [
        _localImage(),
      ]);
      expect(controller.form.references, isEmpty);
      expect(controller.notice, contains('public HTTPS media URLs'));

      await controller.addReferenceCandidates(MediaReferenceKind.image, [
        ReferenceCandidate(
          id: 'local',
          name: 'Local image',
          kind: MediaReferenceKind.image,
          asset: const AssetReference(
            kind: 'local',
            value: 'images/local.png',
            label: 'Local image',
          ),
          createdAt: DateTime.utc(2026, 11, 5),
        ),
      ]);
      expect(controller.form.references, isEmpty);

      controller.addUrlReference(MediaReferenceKind.image);
      controller.updateReference(
        controller.form.references.single.id,
        'https://cdn.example.com/reference.png',
      );
      expect(controller.validate(), isNull);
      expect(controller.buildInputForTesting()['reference_images'], <String>[
        'https://cdn.example.com/reference.png',
      ]);
      controller.updateReference(
        controller.form.references.single.id,
        'data:image/png;base64,AAAA',
      );
      expect(controller.validate(), contains('public HTTPS media URLs'));
    },
  );

  test(
    'known reference video and audio durations obey the two-second minimum',
    () {
      final controller = _controller('seedance-2.5-r2v');
      addTearDown(controller.dispose);
      for (final kind in [MediaReferenceKind.video, MediaReferenceKind.audio]) {
        controller.form.references = [
          const MediaReferenceDraft(
            id: 'image',
            label: 'Image',
            kind: MediaReferenceKind.image,
            source: 'https://cdn.example.com/image.png',
          ),
          MediaReferenceDraft(
            id: 'clip',
            label: 'Clip',
            kind: kind,
            source:
                'https://cdn.example.com/clip.${kind == MediaReferenceKind.video ? 'mp4' : 'mp3'}',
            durationSeconds: 1,
          ),
        ];
        expect(
          controller.validate(),
          contains('reference ${kind.name} clip to be at least 2 s'),
        );
        expect(
          controller.checkReferenceBudget(kind, durationSeconds: 1).allowed,
          isFalse,
        );
        controller.rememberReferenceDuration('clip', 2);
        expect(controller.validate(), isNull);
        expect(
          controller.checkReferenceBudget(kind, durationSeconds: 2).allowed,
          isTrue,
        );
      }
      final model = controller.selectedModel;
      final constrained = model.constrainedForMobileTest(
        model.resolutions.first,
      );
      expect(constrained.minReferenceVideoSeconds, 2);
      expect(constrained.minReferenceAudioSeconds, 2);
    },
  );

  test('mobile review constraints preserve the public URL contract', () {
    final model = modelById('apipod', 'seedance-2.5-i2v');
    expect(model.requiresPublicMediaUrls, isTrue);
    expect(
      model
          .constrainedForMobileTest(model.resolutions.first)
          .requiresPublicMediaUrls,
      isTrue,
    );
    expect(
      modelById('artcraft', 'seedance_2p5').requiresPublicMediaUrls,
      isFalse,
    );
  });

  testWidgets('reference picker explains URL requirement and disables upload', (
    tester,
  ) async {
    final controller = _controller('seedance-2.5-r2v');
    addTearDown(controller.dispose);
    await _mount(tester, controller);
    expect(find.byKey(const ValueKey('public-media-url-hint')), findsOneWidget);
    expect(
      tester.widget<ReferenceDropZone>(find.byType(ReferenceDropZone)).enabled,
      isFalse,
    );
    await tester.tap(find.byKey(const ValueKey('references-accordion-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-image-reference')));
    await tester.pumpAndSettle();
    final upload = tester.widget<PopupMenuItem<String>>(
      find.ancestor(
        of: find.text('Upload images'),
        matching: find.byType(PopupMenuItem<String>),
      ),
    );
    final paste = tester.widget<PopupMenuItem<String>>(
      find.ancestor(
        of: find.text('Paste image URL'),
        matching: find.byType(PopupMenuItem<String>),
      ),
    );
    expect(upload.enabled, isFalse);
    expect(paste.enabled, isTrue);
  });

  testWidgets('frame picker disables upload and keeps pasted URLs available', (
    tester,
  ) async {
    final controller = _controller('seedance-2.5-i2v');
    addTearDown(controller.dispose);
    await _mount(tester, controller);
    await tester.tap(find.byKey(const ValueKey('keyframes-accordion-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('First'));
    await tester.pumpAndSettle();
    final upload = tester.widget<PopupMenuItem<String>>(
      find.ancestor(
        of: find.text('Upload an image'),
        matching: find.byType(PopupMenuItem<String>),
      ),
    );
    final paste = tester.widget<PopupMenuItem<String>>(
      find.ancestor(
        of: find.text('Paste an image URL'),
        matching: find.byType(PopupMenuItem<String>),
      ),
    );
    expect(upload.enabled, isFalse);
    expect(paste.enabled, isTrue);
  });
}

PickedAsset _localImage() => PickedAsset(
  name: 'local.png',
  bytes: Uint8List.fromList(<int>[1, 2, 3]),
  mimeType: 'image/png',
);

AppController _controller(String model) {
  final controller = AppController(gateway: _MemoryGateway())
    ..snapshot = const LocalSnapshot(
      generations: <Generation>[],
      preferences: AppPreferences(provider: 'apipod'),
      hasApiKey: true,
      connectedProviders: <String>{'apipod'},
      availableProviders: <String>{'apipod'},
      storage: StorageStats(path: 'memory', bytes: 0, records: 0),
    )
    ..loading = false
    ..selectedProviderId = 'apipod'
    ..selectedModelId = model;
  controller.form
    ..prompt = 'Follow the subject.'
    ..autoDuration = false
    ..durationSeconds = 4;
  return controller;
}

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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
