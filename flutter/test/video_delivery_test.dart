import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/google_drive.dart';
import 'package:clawnsole/core/google_drive_asset_presenter_io.dart';
import 'package:clawnsole/core/google_drive_store.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/video_cache.dart';
import 'package:clawnsole/core/video_cache_gateway.dart';
import 'package:clawnsole/ui/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'clawnsole-video-delivery.',
    );
  });

  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test('preferences round-trip the video cache cap tolerantly', () {
    const preferences = AppPreferences(localVideoCacheMb: 250);
    final decoded = AppPreferences.fromJson(
      jsonDecode(jsonEncode(preferences.toJson())) as Map<String, Object?>,
    );
    expect(decoded.localVideoCacheMb, 250);
    expect(
      AppPreferences.fromJson(const <String, Object?>{}).localVideoCacheMb,
      AppPreferences.defaultLocalVideoCacheMb,
    );
    expect(
      AppPreferences.fromJson(const <String, Object?>{
        'localVideoCacheMb': 'junk',
      }).localVideoCacheMb,
      AppPreferences.defaultLocalVideoCacheMb,
    );
    expect(
      AppPreferences.fromJson(const <String, Object?>{
        'localVideoCacheMb': -5,
      }).localVideoCacheMb,
      0,
    );
  });

  test('a cached Drive film plays with zero network calls', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests += 1;
      return http.Response('{}', 200);
    });
    final cache = VideoCache(directory: () async => temporary);
    final store = GoogleDriveStore(
      client: client,
      apiFactory: (token) => GoogleDriveApi(accessToken: token, client: client),
      presenter: IoGoogleDriveAssetPresenter(cache: cache),
    );
    await cache.put(
      'drive-file-0001',
      '.mp4',
      Stream<List<int>>.value(const <int>[1, 2, 3]),
    );

    // The store is not even connected: the cached film must still play.
    final uri = await store.assetUri(
      const AssetReference(
        kind: 'drive',
        value: 'drive-file-0001',
        label: 'clip.mp4',
        contentType: 'video/mp4',
      ),
    );
    expect(uri.scheme, 'file');
    expect(await File.fromUri(uri).readAsBytes(), const <int>[1, 2, 3]);
    expect(requests, 0);

    await expectLater(
      store.assetUri(
        const AssetReference(
          kind: 'drive',
          value: 'drive-file-0002',
          label: 'cold.mp4',
          contentType: 'video/mp4',
        ),
      ),
      throwsStateError,
    );
    expect(requests, 0);
  });

  test('Drive media streams into the cache with byte progress', () async {
    final media = Uint8List.fromList(List<int>.generate(8, (index) => index));
    final api = GoogleDriveApi(
      accessToken: 'token',
      apiBase: Uri.parse('https://drive.test/drive/v3/'),
      client: MockClient((request) async {
        expect(request.url.queryParameters['alt'], 'media');
        return http.Response.bytes(media, 200);
      }),
    );
    final cache = VideoCache(directory: () async => temporary);
    final presenter = IoGoogleDriveAssetPresenter(cache: cache);
    final events = <(int, int?, bool)>[];
    cache.addProgressListener(
      'drive-file-0003',
      (received, total, done) => events.add((received, total, done)),
    );

    final download = await api.readFileStream('drive-file-0003');
    expect(download.contentLength, media.length);
    final uri = await presenter.present(
      const AssetReference(
        kind: 'drive',
        value: 'drive-file-0003',
        label: 'clip.mp4',
        contentType: 'video/mp4',
      ),
      download.stream,
      expectedLength: download.contentLength,
    );

    expect(await File.fromUri(uri).readAsBytes(), media);
    expect(events.last, (media.length, media.length, true));
    expect(await cache.lookup('drive-file-0003'), isNotNull);
  });

  test('a newly uploaded Drive film seeds the local presenter cache', () async {
    final cache = VideoCache(directory: () async => temporary);
    final api = _UploadDriveApi();
    final store = GoogleDriveStore(
      apiFactory: (_) => api,
      presenter: IoGoogleDriveAssetPresenter(cache: cache),
    );
    await store.connect('token', 'Shared Studio');

    final film = await store.writeAsset(
      Uint8List.fromList(<int>[7, 8, 9]),
      label: 'film.mp4',
      contentType: 'video/mp4',
    );
    expect(
      await File.fromUri((await cache.lookup(film.value))!.uri).readAsBytes(),
      <int>[7, 8, 9],
    );

    final image = await store.writeAsset(
      Uint8List.fromList(<int>[1, 2]),
      label: 'poster.png',
      contentType: 'image/png',
    );
    expect(await cache.lookup(image.value), isNull);
  });

  test('readFileRange requests a byte window and slices 200s', () async {
    final media = Uint8List.fromList(List<int>.generate(10, (index) => index));
    String? observedRange;
    final honoring = GoogleDriveApi(
      accessToken: 'token',
      apiBase: Uri.parse('https://drive.test/drive/v3/'),
      client: MockClient((request) async {
        observedRange = request.headers['Range'];
        return http.Response.bytes(media.sublist(2, 6), 206);
      }),
    );
    expect(
      await honoring.readFileRange('drive-file-0004', 2, 5),
      media.sublist(2, 6),
    );
    expect(observedRange, 'bytes=2-5');

    final ignoring = GoogleDriveApi(
      accessToken: 'token',
      apiBase: Uri.parse('https://drive.test/drive/v3/'),
      client: MockClient((request) async => http.Response.bytes(media, 200)),
    );
    expect(
      await ignoring.readFileRange('drive-file-0004', 2, 5),
      media.sublist(2, 6),
    );
  });

  test(
    'generationMediaDelivery reports progress and completes at one',
    () async {
      final gateway = _CacheGateway(_snapshot());
      final controller = AppController(gateway: gateway);
      final item = _generation(
        'one',
        status: 'Ready',
        resultAsset: const AssetReference(
          kind: 'drive',
          value: 'film-asset-0001',
          label: 'clip.mp4',
          contentType: 'video/mp4',
        ),
      );

      final delivery = controller.generationMediaDelivery(item);
      final seen = <double?>[];
      delivery.progress.addListener(() => seen.add(delivery.progress.value));
      final uri = await delivery.uri;

      expect(uri, Uri.parse('file:///cache/film-asset-0001.mp4'));
      expect(seen, <double?>[.25, .75, 1]);
      expect(gateway.listenerCount('film-asset-0001'), 0);
      expect(controller.videoPreviewSourceRevision, 1);

      // A provider-URL film has no observable byte progress.
      final remote = controller.generationMediaDelivery(
        _generation(
          'two',
          status: 'Ready',
          resultUrl: 'https://cdn.test/x.mp4',
        ),
      );
      expect(await remote.uri, Uri.parse('https://cdn.test/x.mp4'));
      controller.dispose();
    },
  );

  test('a film that turns ready is prefetched into the cache', () async {
    final working = _generation(
      'one',
      status: 'Queued',
      pollingUrl: 'https://provider.test/poll/one',
      storage: LibraryStorage.drive,
    );
    final gateway = _CacheGateway(_snapshot(generations: <Generation>[working]))
      ..onPoll = (generation) => generation.copyWith(
        status: 'Ready',
        resultAsset: const AssetReference(
          kind: 'drive',
          value: 'film-asset-0009',
          label: 'clip.mp4',
          contentType: 'video/mp4',
        ),
      );
    final controller = AppController(gateway: gateway);
    await controller.initialize();

    await controller.pollWorking();
    await Future<void>.delayed(Duration.zero);

    expect(gateway.prefetched, <String>['film-asset-0009']);
    expect(controller.videoPreviewSourceRevision, 1);
    controller.dispose();
  });

  testWidgets('the cache setting persists, shows usage, and clears', (
    tester,
  ) async {
    final gateway = _CacheGateway(_snapshot());
    final controller = AppController(gateway: gateway);
    await controller.initialize();
    await tester.binding.setSurfaceSize(const Size(850, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildClawnsoleTheme(Brightness.light),
        home: Scaffold(
          body: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => SettingsScreen(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dropdown = find.byKey(const ValueKey('local-video-cache-cap'));
    await tester.ensureVisible(dropdown);
    await tester.pumpAndSettle();
    expect(find.text('Local video player cache'), findsOneWidget);
    expect(find.text('Cached now: 5.00 MB'), findsOneWidget);

    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('250 MB').last);
    await tester.pumpAndSettle();
    expect(controller.localVideoCacheMb, 250);
    expect(gateway.savedPreferences.last.localVideoCacheMb, 250);
    expect(gateway.clears, 0);

    await tester.tap(find.byKey(const ValueKey('local-video-cache-clear')));
    await tester.pumpAndSettle();
    expect(gateway.clears, 1);

    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Off').last);
    await tester.pumpAndSettle();
    expect(controller.localVideoCacheMb, 0);
    expect(gateway.savedPreferences.last.localVideoCacheMb, 0);
    expect(gateway.clears, 2, reason: 'Off clears the cache');

    controller.dispose();
  });
}

LocalSnapshot _snapshot({
  List<Generation> generations = const <Generation>[],
}) => LocalSnapshot(
  generations: generations,
  preferences: const AppPreferences(),
  hasApiKey: true,
  storage: const StorageStats(path: 'memory', bytes: 0, records: 0),
);

Generation _generation(
  String id, {
  required String status,
  AssetReference? resultAsset,
  String? resultUrl,
  String? pollingUrl,
  LibraryStorage storage = LibraryStorage.drive,
}) => Generation(
  localId: id,
  status: status,
  prompt: 'a film',
  mode: VideoMode.t2v,
  config: const GenerationConfig(
    aspectRatio: '16:9',
    duration: 8,
    resolution: 'hd',
    generateAudio: true,
    safetyTolerance: 2,
    draft: false,
  ),
  createdAt: DateTime.utc(2026, 8, 21),
  updatedAt: DateTime.utc(2026, 8, 21),
  resultAsset: resultAsset,
  resultUrl: resultUrl,
  pollingUrl: pollingUrl,
  storage: storage,
);

class _CacheGateway implements AppGateway, VideoCacheGateway {
  _CacheGateway(this.snapshot);

  LocalSnapshot snapshot;
  final List<AppPreferences> savedPreferences = <AppPreferences>[];
  final List<String> prefetched = <String>[];
  final Map<String, List<VideoDeliveryProgressListener>> _listeners =
      <String, List<VideoDeliveryProgressListener>>{};
  int clears = 0;
  Generation Function(Generation generation)? onPoll;

  int listenerCount(String assetId) => _listeners[assetId]?.length ?? 0;

  @override
  bool get usesCompanion => false;

  @override
  bool get supportsPhotoLibrarySave => false;

  @override
  String get persistenceDescription => 'Memory';

  @override
  Future<LocalSnapshot> load() async => snapshot;

  @override
  Future<LocalSnapshot> setPreferences(AppPreferences preferences) async {
    savedPreferences.add(preferences);
    snapshot = snapshot.copyWith(preferences: preferences);
    return snapshot;
  }

  @override
  Future<LocalSnapshot> setApiKey(String value) async => snapshot;

  @override
  Future<double> verifyKey([String? candidate]) async => 0;

  @override
  Future<double> getCredits() async => 0;

  @override
  Future<Generation> submit(GenerationSubmission submission) async =>
      submission.record;

  @override
  Future<Generation> poll(Generation generation) async =>
      onPoll?.call(generation) ?? generation;

  @override
  Future<LocalSnapshot> deleteGeneration(String localId) async => snapshot;

  @override
  Future<LocalSnapshot> clearHistory() async => snapshot;

  @override
  Future<LocalSnapshot> clearPreferences() async => snapshot;

  @override
  Future<LocalSnapshot> clearApiKey() async => snapshot;

  @override
  Future<LocalSnapshot> clearAll() async => snapshot;

  @override
  Future<Uri> assetUri(AssetReference reference) async {
    if (reference.kind == 'drive') {
      // Emit like a real download: after the caller had a chance to listen.
      await Future<void>.delayed(Duration.zero);
      for (final listener in List<VideoDeliveryProgressListener>.of(
        _listeners[reference.value] ?? const <VideoDeliveryProgressListener>[],
      )) {
        listener(.25);
        listener(.75);
      }
      return Uri.parse('file:///cache/${reference.value}.mp4');
    }
    return Uri.parse(reference.value);
  }

  @override
  Future<Uint8List> readAsset(AssetReference reference) async => Uint8List(0);

  @override
  Uri mediaUri(String source) => Uri.parse(source);

  @override
  Future<Uint8List> downloadMedia(String source) async => Uint8List(0);

  @override
  Future<void> saveMediaToPhotoLibrary(
    Uint8List bytes,
    String fileName,
    String contentType,
  ) async {}

  @override
  Future<int> videoCacheUsedBytes() async => 5 * 1024 * 1024;

  @override
  Future<void> clearVideoCache() async {
    clears += 1;
  }

  @override
  Future<Uri?> cachedVideoAssetUri(AssetReference reference) async => null;

  @override
  Future<void> prefetchVideoAsset(AssetReference reference) async {
    prefetched.add(reference.value);
  }

  @override
  void addVideoProgressListener(
    String assetId,
    VideoDeliveryProgressListener listener,
  ) {
    _listeners
        .putIfAbsent(assetId, () => <VideoDeliveryProgressListener>[])
        .add(listener);
  }

  @override
  void removeVideoProgressListener(
    String assetId,
    VideoDeliveryProgressListener listener,
  ) {
    _listeners[assetId]?.remove(listener);
    if (_listeners[assetId]?.isEmpty ?? false) _listeners.remove(assetId);
  }
}

class _UploadDriveApi extends GoogleDriveApi {
  _UploadDriveApi() : super(accessToken: 'token');

  int _fileCount = 0;

  @override
  Future<GoogleDriveFile?> findRootFolder(String name) async =>
      const GoogleDriveFile(
        id: 'root-folder-0001',
        name: 'Shared Studio',
        mimeType: 'application/vnd.google-apps.folder',
      );

  @override
  Future<GoogleDriveFile?> findChild(
    String parentId,
    String name, {
    String? appPropertyKey,
    String? appPropertyValue,
  }) async => name == clawnsoleDriveAssetsFolder
      ? const GoogleDriveFile(
          id: 'assets-folder-0001',
          name: clawnsoleDriveAssetsFolder,
          mimeType: 'application/vnd.google-apps.folder',
        )
      : null;

  @override
  Future<GoogleDriveFile> createFile({
    required String parentId,
    required String name,
    required Uint8List bytes,
    required String contentType,
    Map<String, String> appProperties = const <String, String>{},
  }) async {
    _fileCount += 1;
    return GoogleDriveFile(
      id: 'uploaded-file-${_fileCount.toString().padLeft(4, '0')}',
      name: name,
      mimeType: contentType,
      size: bytes.length,
    );
  }
}
