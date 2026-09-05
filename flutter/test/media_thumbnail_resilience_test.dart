import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/ui/media_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _frame = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);
const _metadata = VideoSourceMetadata(
  width: 1920,
  height: 1080,
  durationSeconds: 8,
);

Widget _host(MediaThumbnail child) => MaterialApp(
  home: Center(child: SizedBox(width: 160, height: 90, child: child)),
);

void main() {
  testWidgets('recycled video widgets ignore old thumbnails and metadata', (
    tester,
  ) async {
    final gateway = _Gateway();
    final frames = <String, Completer<Uint8List?>>{};
    final metadata = <String, Completer<VideoSourceMetadata?>>{};
    final savedFrames = <String>[];
    final savedMetadata = <String>[];
    Future<Uint8List?> frameLoader(Uri uri, Duration _) =>
        (frames[uri.path] = Completer<Uint8List?>()).future;
    Future<VideoSourceMetadata?> metadataLoader(Uri uri) =>
        (metadata[uri.path] = Completer<VideoSourceMetadata?>()).future;
    Widget tile(String name) => _host(
      MediaThumbnail(
        gateway: gateway,
        kind: MediaReferenceKind.video,
        source: 'https://media.test/$name',
        frameLoader: frameLoader,
        metadataLoader: metadataLoader,
        onThumbnail: (_) => savedFrames.add(name),
        onVideoMetadata: (_) => savedMetadata.add(name),
      ),
    );
    await tester.pumpWidget(tile('old'));
    await tester.pump();
    await tester.pumpWidget(tile('new'));
    await tester.pump();
    frames['/old']!.complete(_frame);
    metadata['/old']!.complete(_metadata);
    await tester.pump();
    expect(savedFrames, isEmpty);
    expect(savedMetadata, isEmpty);
    frames['/new']!.complete(_frame);
    metadata['/new']!.complete(_metadata);
    await tester.pumpAndSettle();
    expect(savedFrames, ['new']);
    expect(savedMetadata, ['new']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('delayed URI lookup keeps its original frame loader', (
    tester,
  ) async {
    final gateway = _Gateway();
    final oldUri = Completer<Uri?>();
    final requests = <String>[];
    final saved = <String>[];
    await tester.pumpWidget(
      _host(
        MediaThumbnail(
          gateway: gateway,
          kind: MediaReferenceKind.video,
          source: 'https://media.test/old-uri',
          mediaUriLoader: () => oldUri.future,
          frameLoader: (uri, _) async {
            requests.add('old:${uri.path}');
            return _frame;
          },
          onThumbnail: (_) => saved.add('old'),
        ),
      ),
    );
    await tester.pumpWidget(
      _host(
        MediaThumbnail(
          gateway: gateway,
          kind: MediaReferenceKind.video,
          source: 'https://media.test/new-uri',
          frameLoader: (uri, _) async {
            requests.add('new:${uri.path}');
            return _frame;
          },
          onThumbnail: (_) => saved.add('new'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    oldUri.complete(Uri.parse('https://media.test/old-uri'));
    await tester.pumpAndSettle();
    expect(requests, ['new:/new-uri', 'old:/old-uri']);
    expect(saved, ['new']);
  });

  testWidgets('recycled audio widgets ignore old duration results', (
    tester,
  ) async {
    final gateway = _Gateway();
    final durations = <String, Completer<double?>>{};
    final saved = <(String, double)>[];
    Future<double?> loader(Uri uri) =>
        (durations[uri.path] = Completer<double?>()).future;
    Widget tile(String name) => _host(
      MediaThumbnail(
        gateway: gateway,
        kind: MediaReferenceKind.audio,
        source: 'https://media.test/$name',
        durationLoader: loader,
        onMediaDuration: (value) => saved.add((name, value)),
      ),
    );
    await tester.pumpWidget(tile('old-audio'));
    await tester.pumpWidget(tile('new-audio'));
    durations['/old-audio']!.complete(3);
    durations['/new-audio']!.complete(8);
    await tester.pumpAndSettle();
    expect(saved, [('new-audio', 8.0)]);
  });

  testWidgets('disposed video widgets never publish late results', (
    tester,
  ) async {
    final gateway = _Gateway();
    final frame = Completer<Uint8List?>();
    final metadata = Completer<VideoSourceMetadata?>();
    var callbacks = 0;
    await tester.pumpWidget(
      _host(
        MediaThumbnail(
          gateway: gateway,
          kind: MediaReferenceKind.video,
          source: 'https://media.test/dispose',
          frameLoader: (_, _) => frame.future,
          metadataLoader: (_) => metadata.future,
          onThumbnail: (_) => callbacks += 1,
          onVideoMetadata: (_) => callbacks += 1,
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    frame.complete(_frame);
    metadata.complete(_metadata);
    await tester.pumpAndSettle();
    expect(callbacks, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('local cache respects gateway and memory-pressure boundaries', (
    tester,
  ) async {
    final first = _Gateway();
    final second = _Gateway();
    Widget tile(_Gateway gateway) => _host(
      MediaThumbnail(
        gateway: gateway,
        kind: MediaReferenceKind.image,
        reference: const AssetReference(
          kind: 'local',
          value: 'shared.png',
          label: 'shared.png',
        ),
      ),
    );
    await tester.pumpWidget(tile(first));
    await tester.pumpAndSettle();
    expect(first.reads, 1);
    await tester.pumpWidget(tile(second));
    await tester.pumpAndSettle();
    expect(second.reads, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(tile(first));
    await tester.pumpAndSettle();
    expect(first.reads, 1);
    tester.binding.handleMemoryPressure();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(tile(first));
    await tester.pumpAndSettle();
    expect(first.reads, 2);
  });

  testWidgets('synchronous probe failures stay within best-effort previews', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        MediaThumbnail(
          gateway: _Gateway(),
          kind: MediaReferenceKind.video,
          source: 'https://media.test/failure',
          frameLoader: (_, _) => throw StateError('frame unavailable'),
          metadataLoader: (_) => throw StateError('metadata unavailable'),
          onVideoMetadata: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

class _Gateway implements AppGateway {
  int reads = 0;

  @override
  Uri mediaUri(String source) => Uri.parse(source);

  @override
  Future<Uint8List> readAsset(AssetReference reference) async {
    reads += 1;
    return Uint8List.fromList(_frame);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
