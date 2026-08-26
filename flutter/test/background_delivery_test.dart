import 'dart:async';
import 'dart:typed_data';

import 'package:clawnsole/core/background_delivery.dart';
import 'package:clawnsole/core/bfl_api.dart';
import 'package:clawnsole/core/direct_gateway.dart';
import 'package:clawnsole/core/durable_data_store.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/provider_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const String _pollingUrl = 'https://api.bfl.ai/v1/get_result?id=abc';
const String _storedResultUrl = 'https://cdn.example.com/results/film.mp4';

Generation _generation({
  String localId = 'delivery-1',
  String status = 'Ready',
  String? resultUrl,
  AssetReference? resultAsset,
}) {
  final now = DateTime.utc(2026, 8, 26, 12);
  return Generation(
    localId: localId,
    provider: 'bfl',
    model: 'flux-3-video',
    status: status,
    prompt: 'A crab paints a sunset',
    mode: VideoMode.t2v,
    config: const GenerationConfig(
      aspectRatio: '16:9',
      duration: 5,
      resolution: 'hd',
      generateAudio: false,
      safetyTolerance: 2,
      draft: false,
    ),
    pollingUrl: _pollingUrl,
    resultUrl: resultUrl,
    resultAsset: resultAsset,
    createdAt: now,
    updatedAt: now,
  );
}

class _PollBflApi extends BflApi {
  _PollBflApi(this.onPoll);

  final Future<Map<String, Object?>> Function() onPoll;

  @override
  Future<double> getCredits(String apiKey) async => 10;

  @override
  Future<Map<String, Object?>> poll(String apiKey, String pollingUrl) =>
      onPoll();
}

class _FakeDelivery implements BackgroundResultDelivery {
  _FakeDelivery({
    this.downloads = const <String, DeliveredResult>{},
    Map<String, DeliveredResult>? retained,
    this.downloadError,
    this.supported = true,
  }) : retained = Map<String, DeliveredResult>.of(
         retained ?? const <String, DeliveredResult>{},
       );

  final Map<String, DeliveredResult> downloads;
  final Map<String, DeliveredResult> retained;
  final Object? downloadError;
  final bool supported;
  final List<String> completed = <String>[];
  int downloadCalls = 0;

  @override
  Future<DeliveredResult?> download({
    required String id,
    required String url,
  }) async {
    downloadCalls += 1;
    if (!supported) return null;
    final error = downloadError;
    if (error != null) throw error;
    return downloads[id];
  }

  @override
  Future<List<String>> pendingResultIds() async =>
      retained.keys.toList(growable: false);

  @override
  Future<DeliveredResult?> readPendingResult(String id) async => retained[id];

  @override
  Future<void> completeResult(String id) async {
    completed.add(id);
    retained.remove(id);
  }
}

class _MemoryStore implements DurableDataStore {
  _MemoryStore(this.data);

  StoredData data;
  final List<Uint8List> writtenAssets = <Uint8List>[];

  @override
  Future<StoredData> read() async => data;

  @override
  Future<void> write(StoredData data) async => this.data = data;

  @override
  Future<void> delete() async => data = const StoredData();

  @override
  Future<AssetReference?> persistSource(
    String source, {
    required String label,
    AssetReference? retained,
    LibraryStorage storage = LibraryStorage.local,
  }) async =>
      retained ?? AssetReference(kind: 'local', value: source, label: label);

  @override
  Future<void> pruneAssets(
    List<Generation> generations, [
    List<SavedReference> savedReferences = const <SavedReference>[],
  ]) async {}

  @override
  Future<Uint8List> readAsset(AssetReference reference) async => Uint8List(0);

  @override
  Future<Uri> assetUri(AssetReference reference) async => Uri();

  @override
  Future<StorageStats> stats(int records) async =>
      StorageStats(path: 'memory', bytes: 0, records: records);

  @override
  Future<AssetReference> writeAsset(
    Uint8List bytes, {
    required String label,
    required String contentType,
    LibraryStorage storage = LibraryStorage.local,
  }) async {
    writtenAssets.add(bytes);
    return AssetReference(kind: 'local', value: label, label: label);
  }
}

DirectGateway _gateway({
  required _MemoryStore store,
  required _FakeDelivery delivery,
  Future<Map<String, Object?>> Function()? onPoll,
}) => DirectGateway(
  store: store,
  providerRouter: ProviderApiRouter(
    bfl: _PollBflApi(
      onPoll ?? () async => <String, Object?>{'status': 'Ready'},
    ),
  ),
  backgroundDelivery: delivery,
  client: MockClient((request) async {
    if (request.url.toString() == _storedResultUrl) {
      return http.Response.bytes(
        <int>[1, 2, 3],
        200,
        headers: <String, String>{'content-type': 'video/mp4'},
      );
    }
    return http.Response('missing', 404);
  }),
);

StoredData _dataWith(Generation record) => StoredData(
  apiKeys: const <String, String>{'bfl': 'secret'},
  generations: <Generation>[record],
);

DeliveredResult _film(List<int> bytes) =>
    DeliveredResult(bytes: Uint8List.fromList(bytes), contentType: 'video/mp4');

void main() {
  test('retention downloads go through the platform service', () async {
    final record = _generation(resultUrl: _storedResultUrl);
    final store = _MemoryStore(_dataWith(record));
    final delivery = _FakeDelivery(
      downloads: <String, DeliveredResult>{
        record.localId: _film(<int>[9, 9]),
      },
    );
    final gateway = _gateway(store: store, delivery: delivery);

    final updated = await gateway.poll(record);

    expect(updated.resultAsset, isNotNull);
    expect(store.writtenAssets.single, <int>[9, 9]);
    expect(
      delivery.completed,
      isEmpty,
      reason:
          'the retained copy is released by the recovery pass only after '
          'the record referencing the asset has been persisted',
    );
  });

  test(
    'an unsupported platform service falls back to in-process HTTP',
    () async {
      final record = _generation(resultUrl: _storedResultUrl);
      final store = _MemoryStore(_dataWith(record));
      final delivery = _FakeDelivery(supported: false);
      final gateway = _gateway(store: store, delivery: delivery);

      final updated = await gateway.poll(record);

      expect(delivery.downloadCalls, 1);
      expect(updated.resultAsset, isNotNull);
      expect(store.writtenAssets.single, <int>[1, 2, 3]);
      expect(delivery.completed, isEmpty);
    },
  );

  test('a platform transfer stall keeps an expired task retryable', () async {
    final record = _generation(resultUrl: _storedResultUrl);
    final store = _MemoryStore(_dataWith(record));
    final delivery = _FakeDelivery(
      downloadError: TimeoutException('The provider result download stalled.'),
    );
    final gateway = _gateway(
      store: store,
      delivery: delivery,
      onPoll: () async => <String, Object?>{'status': 'Task not found'},
    );

    final updated = await gateway.poll(record);

    expect(updated.isReady, isTrue);
    expect(updated.isFailed, isFalse);
    expect(updated.resultAsset, isNull);
  });

  test(
    'recovery imports a film the OS finished while the app was gone',
    () async {
      // The provider expired the task while the OS was still downloading, so
      // the record was flipped to a terminal failure — the arriving film must
      // still complete it.
      final record = _generation(
        status: 'Task not found',
        resultUrl: _storedResultUrl,
      ).copyWith(deliveryExpired: true);
      final store = _MemoryStore(_dataWith(record));
      final delivery = _FakeDelivery(
        retained: <String, DeliveredResult>{
          record.localId: _film(<int>[7, 7]),
        },
      );
      final gateway = _gateway(store: store, delivery: delivery);

      final recovered = await gateway.recoverBackgroundDeliveries();

      expect(recovered, 1);
      final persisted = store.data.generations.single;
      expect(persisted.isReady, isTrue);
      expect(persisted.resultAsset, isNotNull);
      expect(persisted.error, isNull);
      expect(persisted.deliveryExpired, isFalse);
      expect(
        persisted.statusCheckCount,
        record.statusCheckCount + 1,
        reason:
            'the import must advance the CAS write version so an '
            'in-flight poll against the old baseline cannot clobber it',
      );
      expect(store.writtenAssets.single, <int>[7, 7]);
      expect(delivery.completed, <String>[record.localId]);
    },
  );

  test('recovery discards films for moderated or cancelled records', () async {
    final record = _generation(
      status: 'Content Moderated',
      resultUrl: _storedResultUrl,
    );
    final store = _MemoryStore(_dataWith(record));
    final delivery = _FakeDelivery(
      retained: <String, DeliveredResult>{
        record.localId: _film(<int>[3]),
      },
    );
    final gateway = _gateway(store: store, delivery: delivery);

    final recovered = await gateway.recoverBackgroundDeliveries();

    expect(recovered, 0);
    expect(store.writtenAssets, isEmpty);
    expect(store.data.generations.single.isFailed, isTrue);
    expect(delivery.completed, <String>[record.localId]);
  });

  test(
    'recovery releases retained films that no longer match a record',
    () async {
      final delivered = _generation(
        localId: 'already-delivered',
        resultAsset: const AssetReference(
          kind: 'local',
          value: 'film.mp4',
          label: 'f',
        ),
      );
      final store = _MemoryStore(_dataWith(delivered));
      final delivery = _FakeDelivery(
        retained: <String, DeliveredResult>{
          'already-delivered': _film(<int>[1]),
          'deleted-generation': _film(<int>[2]),
        },
      );
      final gateway = _gateway(store: store, delivery: delivery);

      final recovered = await gateway.recoverBackgroundDeliveries();

      expect(recovered, 0);
      expect(store.writtenAssets, isEmpty);
      expect(delivery.completed.toSet(), <String>{
        'already-delivered',
        'deleted-generation',
      });
    },
  );
}
