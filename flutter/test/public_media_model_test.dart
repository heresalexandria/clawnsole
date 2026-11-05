import 'dart:convert';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/google_drive.dart';
import 'package:clawnsole/core/temporary_media_host.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/provider_catalog.dart';
import 'package:clawnsole/ui/create_screen.dart';
import 'package:clawnsole/ui/common_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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

  test('local media requires Drive and unsafe URLs remain invalid', () {
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
      expect(controller.validate(), contains('public HTTPS'));
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
    expect(controller.validate(), contains('public HTTPS'));
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
    'local picks and saved references attach before Drive connection',
    () async {
      final controller = _controller('seedance-2.5-r2v');
      addTearDown(controller.dispose);
      await controller.attachPickedReferences(MediaReferenceKind.image, [
        _localImage(),
      ]);
      expect(controller.form.references, hasLength(1));
      expect(controller.validate(), contains('Connect Google Drive'));
      await controller.addReferenceCandidates(MediaReferenceKind.image, [
        ReferenceCandidate(
          id: 'local',
          name: 'Local image',
          kind: MediaReferenceKind.image,
          asset: const AssetReference(
            kind: 'local',
            value: 'local.png',
            label: 'Local image',
          ),
          createdAt: DateTime.utc(2026),
        ),
      ]);
      expect(controller.form.references, hasLength(2));
      expect(
        controller.form.references.every((item) => item.asset != null),
        isTrue,
      );
      expect(controller.validate(), contains('Connect Google Drive'));
      controller.form.references = [];
      controller.addUrlReference(MediaReferenceKind.image);
      controller.updateReference(
        controller.form.references.single.id,
        'https://cdn.example.com/reference.png',
      );
      expect(controller.validate(), isNull);
      expect(controller.needsTemporaryMediaHosting, isFalse);
    },
  );

  for (final companion in [false, true]) {
    test(
      '${companion ? 'companion' : 'native'} prepares every local media kind when Drive is connected',
      () async {
        final gateway = _MemoryGateway(connected: true, companion: companion);
        final controller = _controller('seedance-2.5-r2v', gateway: gateway);
        addTearDown(controller.dispose);
        for (final kind in MediaReferenceKind.values) {
          await controller.attachPickedReferences(kind, [
            PickedAsset(
              name: '${kind.name}.bin',
              bytes: Uint8List.fromList([1, 2, 3]),
              mimeType: switch (kind) {
                MediaReferenceKind.image => 'image/png',
                MediaReferenceKind.video => 'video/mp4',
                MediaReferenceKind.audio => 'audio/mpeg',
              },
            ),
          ]);
        }
        expect(controller.form.references, hasLength(3));
        expect(controller.canTemporarilyHostMedia, isTrue);
        expect(controller.needsTemporaryMediaHosting, isTrue);
        expect(controller.validate(), isNull);
        final input = controller.buildInputForTesting();
        expect(
          input['reference_images'],
          everyElement(startsWith('data:image/')),
        );
        expect(
          input['reference_videos'],
          everyElement(startsWith('data:video/')),
        );
        expect(
          input['reference_audios'],
          everyElement(startsWith('data:audio/')),
        );
        controller.form.references = [];
        controller.form.keyframes = [
          KeyframeDraft(
            id: 'first',
            label: 'First',
            role: KeyframeRole.start,
            source: '',
            seconds: 0,
            asset: _localImage(),
          ),
        ];
        controller.selectedModelId = 'seedance-2.5-i2v';
        expect(controller.validate(), isNull);
        expect(
          controller.buildInputForTesting()['keyframes'],
          everyElement(startsWith('data:image/')),
        );
        controller.form.keyframes = [];
        controller.selectedModelId = 'seedance-2.5-edit';
        controller.form.videoAsset = PickedAsset(
          name: 'source.mp4',
          bytes: Uint8List.fromList([1, 2, 3]),
          mimeType: 'video/mp4',
        );
        expect(controller.validate(), isNull);
        expect(
          controller.buildInputForTesting()['start_video'],
          startsWith('data:video/'),
        );
        gateway.connected = false;
        expect(controller.validate(), contains('Connect Google Drive'));
        await controller.submit(providerRetentionRiskAcknowledged: true);
        expect(controller.section, AppSection.settings);
        expect(controller.settingsTab, SettingsTab.sync);
      },
    );
  }

  test(
    'task-ID finalization never requires Drive for hidden preview media',
    () {
      final controller = _controller('seedance-2.5-draft');
      addTearDown(controller.dispose);
      controller.form.draftUrl = 'preview-task';
      controller.form.resolution = 'fhd';
      controller.form.references = [
        MediaReferenceDraft(
          id: 'hidden',
          label: 'Hidden',
          kind: MediaReferenceKind.image,
          source: '',
          asset: _localImage(),
        ),
      ];
      expect(controller.needsTemporaryMediaHosting, isFalse);
      expect(controller.validate(), isNull);
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

  testWidgets('reference picker explains Drive and permits local upload', (
    tester,
  ) async {
    final controller = _controller('seedance-2.5-r2v');
    addTearDown(controller.dispose);
    await _mount(tester, controller);
    expect(find.byKey(const ValueKey('public-media-url-hint')), findsOneWidget);
    expect(
      tester.widget<ReferenceDropZone>(find.byType(ReferenceDropZone)).enabled,
      isTrue,
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
    expect(upload.enabled, isTrue);
    expect(paste.enabled, isTrue);
  });

  testWidgets('frame picker permits upload and keeps pasted URLs available', (
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
    expect(upload.enabled, isTrue);
    expect(paste.enabled, isTrue);
  });
  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.android,
    TargetPlatform.windows,
    TargetPlatform.macOS,
  ]) {
    testWidgets(
      '${platform.name} shows temporary-sharing disclosure before Generate and a Drive CTA when disconnected',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          final gateway = _MemoryGateway(connected: true);
          final controller = _controller('seedance-2.5-i2v', gateway: gateway);
          addTearDown(controller.dispose);
          controller.form.keyframes = [
            KeyframeDraft(
              id: 'first',
              label: 'First',
              role: KeyframeRole.start,
              source: '',
              seconds: 0,
              asset: _localImage(),
            ),
          ];
          await _mount(
            tester,
            controller,
            size:
                platform == TargetPlatform.iOS ||
                    platform == TargetPlatform.android
                ? const Size(430, 932)
                : const Size(1400, 1000),
          );
          expect(
            find.text(AppController.temporaryMediaSharingDisclosure),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('connect-drive-for-media')),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
          gateway.connected = false;
          controller.notifyListeners();
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('connect-drive-for-media')),
            findsOneWidget,
          );
          await tester.ensureVisible(
            find.byKey(const ValueKey('connect-drive-for-media')),
          );
          await tester.tap(
            find.byKey(const ValueKey('connect-drive-for-media')),
          );
          await tester.pumpAndSettle();
          expect(controller.settingsTab, SettingsTab.sync);
          expect(controller.section, AppSection.settings);
          expect(find.byType(AlertDialog), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }

  testWidgets(
    'pending cleanup remains visible independently of selected model',
    (tester) async {
      final gateway = _MemoryGateway()
        ..status = const TemporaryMediaHostStatus(
          available: false,
          activeLeases: 0,
          pendingCleanup: 2,
          lastCleanupError: 'Reconnect',
        );
      final controller = _controller('seedance-2.5-t2v', gateway: gateway);
      addTearDown(controller.dispose);
      await controller.refreshTemporaryMediaHostingStatus();
      await _mount(tester, controller);
      expect(
        find.byKey(const ValueKey('temporary-media-cleanup-notice')),
        findsOneWidget,
      );
      expect(find.textContaining('2 temporary media copies'), findsOneWidget);
      expect(find.text('Reconnect Google Drive'), findsOneWidget);
      gateway.status = const TemporaryMediaHostStatus(
        available: true,
        activeLeases: 0,
        pendingCleanup: 0,
      );
      await controller.refreshTemporaryMediaHostingStatus();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('temporary-media-cleanup-notice')),
        findsNothing,
      );
    },
  );
}

PickedAsset _localImage() => PickedAsset(
  name: 'local.png',
  bytes: base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
  ),
  mimeType: 'image/png',
);

AppController _controller(String model, {_MemoryGateway? gateway}) {
  final controller = AppController(gateway: gateway ?? _MemoryGateway())
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

Future<void> _mount(
  WidgetTester tester,
  AppController controller, {
  Size size = const Size(1400, 1400),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: buildClawnsoleTheme(Brightness.light),
      home: AnimatedBuilder(
        animation: controller,
        builder: (context, _) =>
            Scaffold(body: CreateScreen(controller: controller)),
      ),
    ),
  );
}

class _MemoryGateway
    implements AppGateway, GoogleDriveGateway, TemporaryMediaHostingGateway {
  _MemoryGateway({this.connected = false, this.companion = false});
  bool connected;
  final bool companion;
  @override
  bool get supportsTemporaryMediaHosting => true;
  @override
  bool get supportsLocalLibrary => true;
  @override
  GoogleDriveConnection get googleDriveConnection => GoogleDriveConnection(
    state: connected
        ? GoogleDriveConnectionState.connected
        : GoogleDriveConnectionState.disconnected,
  );
  TemporaryMediaHostStatus? status;
  @override
  Future<TemporaryMediaHostStatus> temporaryMediaHostStatus() async =>
      status ??
      TemporaryMediaHostStatus(
        available: connected,
        activeLeases: 0,
        pendingCleanup: 0,
      );
  @override
  Future<Uint8List> readAsset(AssetReference reference) async =>
      Uint8List.fromList([1, 2, 3]);
  @override
  Future<LocalSnapshot> setPreferences(AppPreferences preferences) async =>
      LocalSnapshot(
        generations: [],
        preferences: preferences,
        hasApiKey: true,
        connectedProviders: const {'apipod'},
        availableProviders: const {'apipod'},
        storage: const StorageStats(path: 'memory', bytes: 0, records: 0),
      );

  @override
  bool get usesCompanion => companion;

  @override
  bool get supportsPhotoLibrarySave => false;

  @override
  String get persistenceDescription => 'Memory';

  @override
  Uri mediaUri(String source) => Uri.parse(source);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
