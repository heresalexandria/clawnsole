import 'dart:typed_data';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/google_drive.dart';
import 'package:clawnsole/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// The background upload pass turns a Drive-tagged record's staged `local`
/// assets into `drive` ones for the very same bytes. A card whose preview
/// was already on screen must keep it across that swap instead of dropping
/// to a loading placeholder and fetching the thumbnail back from Drive.

final _now = DateTime.utc(2026, 9, 6, 12);

const _stagedThumbnail = AssetReference(
  kind: 'local',
  value: 'staged-thumb-0001',
  label: 'thumbnail.jpg',
  contentType: 'image/jpeg',
  bytes: 3,
);

const _publishedThumbnail = AssetReference(
  kind: 'drive',
  value: 'drive-thumb-0001',
  label: 'thumbnail.jpg',
  contentType: 'image/jpeg',
  bytes: 3,
);

const _regeneratedThumbnail = AssetReference(
  kind: 'local',
  value: 'staged-thumb-0002',
  label: 'thumbnail.jpg',
  contentType: 'image/jpeg',
  bytes: 3,
);

Generation _film({
  AssetReference? thumbnail,
  AssetReference? result,
  String id = 'made-here',
}) => Generation(
  localId: id,
  provider: 'krea',
  model: 'bytedance/seedance-2-5',
  status: 'Ready',
  prompt: 'A lighthouse at dusk.',
  mode: VideoMode.t2v,
  config: const GenerationConfig(
    aspectRatio: '16:9',
    duration: 5,
    resolution: 'hd',
    generateAudio: false,
    safetyTolerance: 2,
    draft: false,
  ),
  resultAsset: result,
  thumbnailAsset: thumbnail,
  createdAt: _now,
  updatedAt: _now,
  storage: LibraryStorage.drive,
);

LocalSnapshot _snapshot(List<Generation> films) => LocalSnapshot(
  generations: films,
  preferences: const AppPreferences(),
  hasApiKey: true,
  connectedProviders: const <String>{'krea'},
  storage: StorageStats(path: 'memory', bytes: 0, records: films.length),
);

class _Gateway implements AppGateway, GoogleDriveGateway {
  _Gateway(this.assets);

  final Map<String, Uint8List> assets;
  LocalSnapshot? loadResult;
  int reads = 0;

  @override
  Future<LocalSnapshot> load() async => loadResult!;

  @override
  Future<Uint8List> readAsset(AssetReference reference) async {
    reads += 1;
    final bytes = assets['${reference.kind}:${reference.value}'];
    if (bytes == null) throw StateError('Missing ${reference.value}.');
    return bytes;
  }

  @override
  GoogleDriveConnection get googleDriveConnection =>
      const GoogleDriveConnection(
        state: GoogleDriveConnectionState.connected,
        folderName: 'Studio',
        folderId: 'folder-1',
      );

  @override
  bool get supportsLocalLibrary => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'a batch publish transfers previews without double-counting buffers',
    () async {
      final local = <AssetReference>[
        for (var index = 0; index < 3; index++)
          AssetReference(
            kind: 'local',
            value: 'staged-$index',
            label: 'thumbnail',
          ),
      ];
      final drive = <AssetReference>[
        for (var index = 0; index < 3; index++)
          AssetReference(
            kind: 'drive',
            value: 'published-$index',
            label: 'thumbnail',
          ),
      ];
      final gateway = _Gateway({
        for (final asset in local)
          'local:${asset.value}': Uint8List(10 * 1024 * 1024),
      });
      final controller = AppController(gateway: gateway)
        ..snapshot = _snapshot([
          for (var index = 0; index < 3; index++)
            _film(thumbnail: local[index], id: 'film-$index'),
        ]);
      addTearDown(controller.dispose);
      for (final asset in local) {
        await controller.readPreviewAsset(asset);
      }
      gateway.loadResult = _snapshot([
        for (var index = 0; index < 3; index++)
          _film(thumbnail: drive[index], id: 'film-$index'),
      ]);
      await controller.refreshDriveLibraryForTesting();
      for (final asset in drive) {
        expect(controller.cachedAssetBytes(asset), isNotNull);
        await controller.readPreviewAsset(asset);
      }
      expect(gateway.reads, 3, reason: 'published previews never redownload');
    },
  );
  test(
    'a restored preview survives the publish swap without a refetch',
    () async {
      final bytes = Uint8List.fromList(<int>[7, 7, 7]);
      final gateway = _Gateway(<String, Uint8List>{
        'local:${_stagedThumbnail.value}': bytes,
      });
      final controller = AppController(
        gateway: gateway,
      )..snapshot = _snapshot(<Generation>[_film(thumbnail: _stagedThumbnail)]);
      addTearDown(controller.dispose);

      expect(await controller.readPreviewAsset(_stagedThumbnail), bytes);
      expect(gateway.reads, 1);
      expect(controller.cachedAssetBytes(_publishedThumbnail), isNull);

      // The upload pass published the thumbnail; the next library read brings
      // the record back naming the Drive id.
      gateway.loadResult = _snapshot(<Generation>[
        _film(thumbnail: _publishedThumbnail),
      ]);
      await controller.refreshDriveLibraryForTesting();

      expect(
        controller.generations.single.thumbnailAsset,
        _publishedThumbnail,
        reason: 'the swapped record is adopted',
      );
      expect(
        controller.cachedAssetBytes(_publishedThumbnail),
        bytes,
        reason: 'the card can paint the Drive-id thumbnail synchronously',
      );
      expect(await controller.readPreviewAsset(_publishedThumbnail), bytes);
      expect(gateway.reads, 1, reason: 'nothing is fetched back from Drive');
    },
  );

  test('a regenerated preview is new media and is not carried over', () async {
    final bytes = Uint8List.fromList(<int>[7, 7, 7]);
    final gateway = _Gateway(<String, Uint8List>{
      'local:${_stagedThumbnail.value}': bytes,
    });
    final controller = AppController(gateway: gateway)
      ..snapshot = _snapshot(<Generation>[_film(thumbnail: _stagedThumbnail)]);
    addTearDown(controller.dispose);
    await controller.readPreviewAsset(_stagedThumbnail);

    gateway.loadResult = _snapshot(<Generation>[
      _film(thumbnail: _regeneratedThumbnail),
    ]);
    await controller.refreshDriveLibraryForTesting();

    expect(controller.cachedAssetBytes(_regeneratedThumbnail), isNull);
  });
}
