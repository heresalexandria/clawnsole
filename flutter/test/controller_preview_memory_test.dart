import 'dart:async';
import 'dart:typed_data';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

AssetReference _asset(String id) =>
    AssetReference(kind: 'local', value: id, label: id);

class _Gateway implements AppGateway {
  Future<Uint8List> Function(AssetReference)? read;
  int reads = 0;

  @override
  Future<Uint8List> readAsset(AssetReference reference) {
    reads += 1;
    return read!(reference);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'browsing stills evicts bytes and completed read futures together',
    () async {
      final gateway = _Gateway()
        ..read = (_) async => Uint8List(9 * 1024 * 1024);
      final controller = AppController(gateway: gateway);
      addTearDown(controller.dispose);

      for (var index = 0; index < 4; index++) {
        await controller.readPreviewAsset(_asset('$index'));
      }
      expect(controller.cachedAssetBytes(_asset('0')), isNull);
      expect(controller.cachedAssetBytes(_asset('3')), isNotNull);
      await controller.readPreviewAsset(_asset('0'));
      expect(
        gateway.reads,
        5,
        reason: 'an evicted future cannot retain its bytes',
      );
    },
  );

  test('oversized backing buffers display without being memoized', () async {
    final gateway = _Gateway()
      ..read = (_) async =>
          Uint8List.view(Uint8List(33 * 1024 * 1024).buffer, 0, 1);
    final controller = AppController(gateway: gateway);
    addTearDown(controller.dispose);
    expect(await controller.readPreviewAsset(_asset('large')), hasLength(1));
    expect(controller.cachedAssetBytes(_asset('large')), isNull);
  });

  test(
    'pressure clears bytes but shared reads still finish for consumers',
    () async {
      final pending = Completer<Uint8List>();
      final gateway = _Gateway()..read = (_) => pending.future;
      final controller = AppController(gateway: gateway);
      addTearDown(controller.dispose);
      final first = controller.readPreviewAsset(_asset('one'));
      final second = controller.readPreviewAsset(_asset('one'));
      expect(identical(first, second), isTrue);
      expect(gateway.reads, 1);
      controller.clearPreviewMemory();
      pending.complete(Uint8List.fromList([1, 2, 3]));
      expect(await first, [1, 2, 3]);
      expect(await second, [1, 2, 3]);
      expect(controller.cachedAssetBytes(_asset('one')), isNull);
      gateway.read = (_) async => Uint8List.fromList([4]);
      expect(await controller.readPreviewAsset(_asset('one')), [4]);
      expect(gateway.reads, 2);
    },
  );

  test(
    'disposal prevents in-flight reads from refilling preview memory',
    () async {
      final pending = Completer<Uint8List>();
      final controller = AppController(
        gateway: _Gateway()..read = (_) => pending.future,
      );
      final result = controller.readPreviewAsset(_asset('one'));
      controller.dispose();
      pending.complete(Uint8List.fromList([1]));
      expect(await result, [1]);
      expect(controller.cachedAssetBytes(_asset('one')), isNull);
    },
  );

  test(
    'generated reference previews have an independent byte budget',
    () async {
      final controller = AppController(gateway: _Gateway());
      addTearDown(controller.dispose);
      SavedReference reference(String id) => SavedReference(
        id: id,
        name: id,
        kind: MediaReferenceKind.video,
        asset: _asset(id),
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      await controller.cacheReferencePreview(
        reference('first'),
        Uint8List(5 * 1024 * 1024),
      );
      await controller.cacheReferencePreview(
        reference('second'),
        Uint8List(5 * 1024 * 1024),
      );
      expect(controller.cachedReferencePreview(reference('first')), isNull);
      expect(controller.cachedReferencePreview(reference('second')), isNotNull);
      controller.clearPreviewMemory();
      expect(controller.cachedReferencePreview(reference('second')), isNull);
    },
  );
}
