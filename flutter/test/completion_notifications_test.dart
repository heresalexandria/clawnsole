import 'dart:io';

import 'package:clawnsole/core/completion_notifications.dart';
import 'package:clawnsole/core/local_data_store.dart';
import 'package:clawnsole/core/media_share.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/native_gateway.dart';
import 'package:clawnsole/core/provider_catalog.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const MethodChannel _notifications = MethodChannel(
  'ai.clawnsole/notifications',
);
const MethodChannel _share = MethodChannel('ai.clawnsole/share');
const MethodChannel _appleLocal = MethodChannel('ai.clawnsole/apple_local');
const MethodChannel _pathProvider = MethodChannel(
  'plugins.flutter.io/path_provider',
);

void _mock(
  MethodChannel channel,
  Future<Object?> Function(MethodCall call)? handler,
) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, handler);
}

Generation _generation({
  String localId = 'share-1',
  String prompt = 'A crab paints a sunset',
  GenerationOutputKind outputKind = GenerationOutputKind.video,
  AssetReference? resultAsset,
  String? resultUrl,
}) {
  final now = DateTime.utc(2026, 8, 26, 12);
  return Generation(
    localId: localId,
    provider: 'bfl',
    model: 'flux-3-video',
    status: 'Ready',
    prompt: prompt,
    mode: VideoMode.t2v,
    outputKind: outputKind,
    config: const GenerationConfig(
      aspectRatio: '16:9',
      duration: 5,
      resolution: 'hd',
      generateAudio: false,
      safetyTolerance: 2,
      draft: false,
    ),
    resultAsset: resultAsset,
    resultUrl: resultUrl,
    createdAt: now,
    updatedAt: now,
  );
}

/// A data store that keeps retained assets as real files under [directory],
/// so the gateway resolves the `file:` URI that sharing copies from. The
/// conditional `LocalDataStore` export analyses as its browser stub, so the
/// real store's directory override is not visible here.
class _FileAssetStore extends LocalDataStore {
  _FileAssetStore(this.directory);

  final Directory directory;

  File _file(String name) =>
      File('${directory.path}${Platform.pathSeparator}$name');

  @override
  Future<AssetReference> writeAsset(
    Uint8List bytes, {
    required String label,
    required String contentType,
    LibraryStorage storage = LibraryStorage.local,
  }) async {
    await _file(label).writeAsBytes(bytes, flush: true);
    return AssetReference(
      kind: 'local',
      value: label,
      label: label,
      contentType: contentType,
      bytes: bytes.length,
    );
  }

  @override
  Future<Uri> assetUri(AssetReference reference) async =>
      _file(reference.value).uri;

  @override
  Future<Uint8List> readAsset(AssetReference reference) =>
      _file(reference.value).readAsBytes();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    _mock(_notifications, null);
    _mock(_share, null);
    _mock(_appleLocal, null);
    _mock(_pathProvider, null);
  });

  group('MethodChannelGenerationNotifier', () {
    test('requestPermission relays the platform answer', () async {
      final calls = <MethodCall>[];
      _mock(_notifications, (call) async {
        calls.add(call);
        return true;
      });

      expect(
        await MethodChannelGenerationNotifier().requestPermission(),
        isTrue,
      );

      expect(calls.single.method, 'requestPermission');
      expect(calls.single.arguments, isNull);
    });

    test('notify sends the title, body, and thread', () async {
      final calls = <MethodCall>[];
      _mock(_notifications, (call) async {
        calls.add(call);
        return false;
      });

      final posted = await MethodChannelGenerationNotifier().notify(
        title: 'Your film is ready',
        body: 'A crab · BFL',
        threadId: 'gen-1',
      );

      expect(posted, isFalse, reason: 'the shell said the app was active');
      expect(calls.single.method, 'notify');
      expect(calls.single.arguments, <String, Object?>{
        'title': 'Your film is ready',
        'body': 'A crab · BFL',
        'threadId': 'gen-1',
      });
    });

    test('a shell without the handler answers false from then on', () async {
      final notifier = MethodChannelGenerationNotifier();

      expect(await notifier.requestPermission(), isFalse);

      var calls = 0;
      _mock(_notifications, (call) async {
        calls += 1;
        return true;
      });
      expect(await notifier.notify(title: 't', body: 'b'), isFalse);
      expect(calls, 0, reason: 'a missing plugin is remembered');
    });

    test('a platform failure answers false without latching', () async {
      var calls = 0;
      _mock(_notifications, (call) async {
        calls += 1;
        if (calls == 1) throw PlatformException(code: 'denied');
        return true;
      });
      final notifier = MethodChannelGenerationNotifier();

      expect(await notifier.notify(title: 't', body: 'b'), isFalse);
      expect(await notifier.notify(title: 't', body: 'b'), isTrue);
    });
  });

  group('generationReadyNotice', () {
    test('pairs the prompt opening with the provider name', () {
      final notice = generationReadyNotice(_generation());

      expect(notice.title, 'Your film is ready');
      expect(
        notice.body,
        'A crab paints a sunset · ${providerNameForHistory('bfl')}',
      );
    });

    test('trims long prompts to their first 80 characters', () {
      final notice = generationReadyNotice(
        _generation(prompt: '${'word ' * 30}end'),
      );

      final excerpt = notice.body.split(' · ').first;
      expect(excerpt, endsWith('…'));
      expect(excerpt.length, lessThanOrEqualTo(81));
      expect(excerpt, isNot(contains('end')));
    });

    test('names images as images and flattens prompt whitespace', () {
      final notice = generationReadyNotice(
        _generation(
          prompt: '  a\nbrass\tradio  ',
          outputKind: GenerationOutputKind.image,
        ),
      );

      expect(notice.title, 'Your image is ready');
      expect(notice.body, startsWith('a brass radio · '));
    });
  });

  group('MethodChannelMediaShareSheet', () {
    test('share sends the staged path and subject', () async {
      final calls = <MethodCall>[];
      _mock(_share, (call) async {
        calls.add(call);
        return true;
      });

      final shared = await MethodChannelMediaShareSheet().share(
        path: '/tmp/film.mp4',
        subject: 'Clawnsole video',
      );

      expect(shared, isTrue);
      expect(calls.single.method, 'share');
      expect(calls.single.arguments, <String, Object?>{
        'path': '/tmp/film.mp4',
        'subject': 'Clawnsole video',
      });
    });

    test('a shell without the handler answers false', () async {
      expect(
        await MethodChannelMediaShareSheet().share(path: '/x', subject: 's'),
        isFalse,
      );
    });

    test('a platform failure surfaces as a readable error', () async {
      _mock(_share, (call) async {
        throw PlatformException(code: 'invalid', message: 'File missing.');
      });

      expect(
        () => MethodChannelMediaShareSheet().share(path: '/x', subject: 's'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'File missing.',
          ),
        ),
      );
    });
  });

  group('NativeGateway', () {
    late Directory root;
    late LocalDataStore store;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('clawnsole-share-');
      await Directory('${root.path}/tmp').create();
      final assets = await Directory('${root.path}/assets').create();
      store = _FileAssetStore(assets);
      _mock(
        _pathProvider,
        (call) async =>
            call.method == 'getTemporaryDirectory' ? '${root.path}/tmp' : null,
      );
    });

    tearDown(() async {
      await root.delete(recursive: true);
    });

    NativeGateway gateway({required bool isIos}) {
      final gateway = NativeGateway(store: store, isIos: isIos);
      addTearDown(gateway.dispose);
      return gateway;
    }

    test('notifyGenerationReady posts the notice on iOS', () async {
      MethodCall? received;
      _mock(_notifications, (call) async {
        received = call;
        return true;
      });

      final posted = await gateway(
        isIos: true,
      ).notifyGenerationReady(_generation());

      expect(posted, isTrue);
      expect(received?.method, 'notify');
      expect(received?.arguments, <String, Object?>{
        'title': 'Your film is ready',
        'body': 'A crab paints a sunset · ${providerNameForHistory('bfl')}',
        'threadId': 'share-1',
      });
    });

    test('requestGenerationNotifications relays the platform answer', () async {
      _mock(_notifications, (call) async => call.method == 'requestPermission');

      expect(
        await gateway(isIos: true).requestGenerationNotifications(),
        isTrue,
      );
    });

    test('notification wrappers are no-ops off iOS', () async {
      var calls = 0;
      _mock(_notifications, (call) async {
        calls += 1;
        return true;
      });
      final native = gateway(isIos: false);

      expect(await native.requestGenerationNotifications(), isFalse);
      expect(await native.notifyGenerationReady(_generation()), isFalse);
      expect(calls, 0);
    });

    test(
      'localGenerationAvailable asks the Apple runtime only on iOS',
      () async {
        var calls = 0;
        _mock(_appleLocal, (call) async {
          calls += 1;
          return true;
        });

        expect(await gateway(isIos: false).localGenerationAvailable(), isFalse);
        expect(calls, 0);

        final native = gateway(isIos: true);
        expect(await native.localGenerationAvailable(), isTrue);
        expect(calls, 1);

        _mock(_appleLocal, (call) async {
          throw PlatformException(code: 'unavailable');
        });
        expect(await native.localGenerationAvailable(), isFalse);
      },
    );

    test('shareMedia stages the retained file under its save name', () async {
      final asset = await store.writeAsset(
        Uint8List.fromList(<int>[1, 2, 3]),
        label: 'clawnsole-share-1.mp4',
        contentType: 'video/mp4',
      );
      String? sharedPath;
      String? subject;
      List<int>? sharedBytes;
      _mock(_share, (call) async {
        final arguments = call.arguments as Map<Object?, Object?>;
        sharedPath = arguments['path'] as String;
        subject = arguments['subject'] as String;
        sharedBytes = await File(sharedPath!).readAsBytes();
        return true;
      });

      final shared = await gateway(
        isIos: true,
      ).shareMedia(_generation(resultAsset: asset));

      expect(shared, isTrue);
      expect(
        sharedPath,
        '${root.path}/tmp/clawnsole-share/clawnsole-2026-08-26-share-.mp4',
      );
      expect(sharedBytes, <int>[1, 2, 3]);
      expect(subject, 'Clawnsole video: A crab paints a sunset');
      expect(
        File(sharedPath!).existsSync(),
        isFalse,
        reason: 'the staged copy is removed once the sheet closes',
      );
    });

    test('shareMedia is a no-op off iOS', () async {
      var calls = 0;
      _mock(_share, (call) async {
        calls += 1;
        return true;
      });

      final asset = await store.writeAsset(
        Uint8List.fromList(<int>[1]),
        label: 'clawnsole-share-1.mp4',
        contentType: 'video/mp4',
      );
      expect(
        await gateway(isIos: false).shareMedia(_generation(resultAsset: asset)),
        isFalse,
      );
      expect(calls, 0);
    });

    test('shareMedia rejects a generation without media', () async {
      expect(
        () => gateway(isIos: true).shareMedia(_generation()),
        throwsStateError,
      );
    });
  });
}
