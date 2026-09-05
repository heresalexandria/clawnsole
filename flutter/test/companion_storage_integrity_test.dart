import 'dart:io';
import 'dart:typed_data';

import 'package:clawnsole/core/composer_tabs.dart';
import 'package:clawnsole/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/clawnsole_companion.dart';

void main() {
  late Directory directory;
  late CompanionStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'clawnsole-storage-integrity-',
    );
    store = CompanionStore(File('${directory.path}/history.json'));
  });
  tearDown(() async => directory.delete(recursive: true));

  test(
    'full companion wipe clears previous metadata and recovery siblings',
    () async {
      await store.write(
        const StoredData(
          composerTabs: ComposerTabsState(
            tabs: [ComposerTabRecord(id: 'original', prompt: 'Earlier work')],
          ),
        ),
      );
      await store.write(const StoredData());
      expect(await File('${store.file.path}.bak').exists(), isTrue);
      await File(
        '${store.file.path}.corrupt-123',
      ).writeAsString('synthetic corrupt copy');
      await store.delete();
      expect((await store.read()).composerTabs, isNull);
      expect(await File('${store.file.path}.bak').exists(), isFalse);
      expect(await File('${store.file.path}.corrupt-123').exists(), isFalse);
    },
  );

  test(
    'companion prune keeps active and recoverable draft media only',
    () async {
      Future<AssetReference> asset(int byte) => store.writeAsset(
        Uint8List.fromList([byte]),
        label: '$byte.png',
        contentType: 'image/png',
      );
      final active = await asset(1);
      final closed = await asset(2);
      final orphan = await asset(3);
      await store.write(
        StoredData(
          composerTabs: ComposerTabsState(
            tabs: [
              ComposerTabRecord(
                id: 'active',
                mediaConfig: {'source': active.toJson()},
              ),
            ],
            closedTabs: [
              ComposerTabRecord(
                id: 'closed',
                mediaConfig: {'source': closed.toJson()},
              ),
            ],
          ),
        ),
      );
      await store.pruneAssets([]);
      expect(await store.readAsset(active), [1]);
      expect(await store.readAsset(closed), [2]);
      expect(() => store.readAsset(orphan), throwsA(isA<StateError>()));
    },
  );
}
