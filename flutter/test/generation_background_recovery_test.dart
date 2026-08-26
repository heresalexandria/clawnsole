import 'dart:async';
import 'dart:typed_data';

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
  String status = 'Ready',
  String? resultUrl,
  AssetReference? resultAsset,
  DateTime? lastCheckedAt,
  int consecutiveCheckFailures = 0,
}) {
  final now = DateTime.utc(2026, 8, 25, 12);
  return Generation(
    localId: 'recovery-1',
    provider: 'bfl',
    model: 'flux-3-video',
    status: status,
    prompt: 'A crab walks the beach',
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
    lastCheckedAt: lastCheckedAt,
    consecutiveCheckFailures: consecutiveCheckFailures,
    createdAt: now,
    updatedAt: now,
  );
}

class _PollBflApi extends BflApi {
  _PollBflApi(this.onPoll);

  final Future<Map<String, Object?>> Function() onPoll;
  int pollCalls = 0;

  @override
  Future<double> getCredits(String apiKey) async => 10;

  @override
  Future<Map<String, Object?>> poll(String apiKey, String pollingUrl) {
    pollCalls += 1;
    return onPoll();
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
  required _PollBflApi api,
  MockClient? client,
}) => DirectGateway(
  store: store,
  providerRouter: ProviderApiRouter(bfl: api),
  client:
      client ??
      MockClient((request) async {
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

void main() {
  final storedData = StoredData(
    apiKeys: const <String, String>{'bfl': 'secret'},
  );

  test('ready poll without a fresh link retains via the stored link', () async {
    final record = _generation(resultUrl: _storedResultUrl);
    final store = _MemoryStore(_dataWith(record));
    final api = _PollBflApi(() async => <String, Object?>{'status': 'Ready'});
    final gateway = _gateway(store: store, api: api);

    final updated = await gateway.poll(record);

    expect(updated.isReady, isTrue);
    expect(updated.resultAsset, isNotNull);
    expect(updated.resultRetentionFailures, 0);
    expect(updated.resultRetentionError, isNull);
    expect(store.writtenAssets.single, <int>[1, 2, 3]);
  });

  test(
    'expired task reported as a 2xx payload still rescues the film',
    () async {
      final record = _generation(resultUrl: _storedResultUrl);
      final store = _MemoryStore(_dataWith(record));
      final api = _PollBflApi(
        () async => <String, Object?>{'status': 'Task not found'},
      );
      final gateway = _gateway(store: store, api: api);

      final updated = await gateway.poll(record);

      expect(updated.isReady, isTrue);
      expect(updated.isFailed, isFalse);
      expect(updated.resultAsset, isNotNull);
      expect(updated.error, isNull);
    },
  );

  test(
    'expired task with a dead stored link stays ready for later retries',
    () async {
      // The held delivery link is ground truth; the terminal flip waits for
      // the delivery-window purge to release the link first.
      final record = _generation(resultUrl: _storedResultUrl);
      final store = _MemoryStore(_dataWith(record));
      final api = _PollBflApi(
        () async => <String, Object?>{'status': 'Task not found'},
      );
      final gateway = _gateway(
        store: store,
        api: api,
        client: MockClient((request) async => http.Response('gone', 404)),
      );

      final updated = await gateway.poll(record);

      expect(updated.isReady, isTrue);
      expect(updated.isFailed, isFalse);
      expect(updated.resultAsset, isNull);
      expect(updated.resultRetentionError, isNotNull);
    },
  );

  test('a thrown status check falls back to the stored link', () async {
    final record = _generation(resultUrl: _storedResultUrl);
    final store = _MemoryStore(_dataWith(record));
    final api = _PollBflApi(
      () async => throw const ProviderException(
        'The provider status endpoint is unavailable.',
        status: 404,
      ),
    );
    final gateway = _gateway(store: store, api: api);

    final updated = await gateway.poll(record);

    expect(updated.isReady, isTrue);
    expect(updated.resultAsset, isNotNull);
    expect(updated.consecutiveCheckFailures, 0);
  });

  test('a terminal payload never overwrites a delivered generation', () async {
    const asset = AssetReference(kind: 'local', value: 'film.mp4', label: 'f');
    final record = _generation(resultUrl: _storedResultUrl, resultAsset: asset);
    final store = _MemoryStore(_dataWith(record));
    final api = _PollBflApi(
      () async => throw const ProviderException(
        'Task not found',
        status: 404,
        details: <String, Object?>{'status': 'Task not found'},
      ),
    );
    final gateway = _gateway(store: store, api: api);

    final updated = await gateway.poll(record);

    expect(updated.isReady, isTrue);
    expect(updated.isFailed, isFalse);
    expect(updated.resultAsset, asset);
  });

  test('a stalled rescue download keeps an expired task retryable', () async {
    final store = _MemoryStore(
      _dataWith(_generation(resultUrl: _storedResultUrl)),
    );
    final api = _PollBflApi(
      () async => throw const ProviderException(
        'Task not found',
        status: 404,
        details: <String, Object?>{'status': 'Task not found'},
      ),
    );
    final gateway = _gateway(
      store: store,
      api: api,
      client: MockClient((request) async => throw TimeoutException('stalled')),
    );

    final updated = await gateway.poll(
      _generation(resultUrl: _storedResultUrl),
    );

    expect(
      updated.isReady,
      isTrue,
      reason: 'a stall says nothing about the link',
    );
    expect(updated.isFailed, isFalse);
    expect(updated.resultAsset, isNull);
    expect(updated.resultUrl, _storedResultUrl);
  });

  test(
    'a 2xx terminal payload never overwrites a delivered generation',
    () async {
      final store = _MemoryStore(
        _dataWith(
          _generation(
            resultUrl: _storedResultUrl,
            resultAsset: const AssetReference(
              kind: 'local',
              value: 'film.mp4',
              label: 'f',
            ),
          ),
        ),
      );
      final api = _PollBflApi(
        () async => <String, Object?>{'status': 'Task not found'},
      );
      final gateway = _gateway(store: store, api: api);
      const asset = AssetReference(
        kind: 'local',
        value: 'film.mp4',
        label: 'f',
      );

      final updated = await gateway.poll(
        _generation(resultUrl: _storedResultUrl, resultAsset: asset),
      );

      expect(updated.isReady, isTrue);
      expect(updated.isFailed, isFalse);
      expect(updated.resultAsset, asset);
    },
  );

  test(
    'a poll outcome from a stale baseline never overwrites newer state',
    () async {
      final delivered = _generation(resultUrl: _storedResultUrl).copyWith(
        resultAsset: const AssetReference(
          kind: 'local',
          value: 'film.mp4',
          label: 'f',
        ),
        statusCheckCount: 3,
      );
      final store = _MemoryStore(
        StoredData(
          apiKeys: const <String, String>{'bfl': 'secret'},
          generations: <Generation>[delivered],
        ),
      );
      final api = _PollBflApi(
        () async => <String, Object?>{'status': 'Pending'},
      );
      final gateway = _gateway(store: store, api: api);

      // A zombie poll abandoned by its caller's timeout completes late with a
      // stale pre-download baseline.
      final stale = _generation(status: 'Pending');
      final updated = await gateway.poll(stale);

      final persisted = store.data.generations.single;
      expect(persisted.statusCheckCount, 3, reason: 'stale write rejected');
      expect(persisted.resultAsset, isNotNull);
      expect(updated.resultAsset, isNotNull, reason: 'winner returned');
    },
  );

  test('a poll outcome never resurrects a deleted generation', () async {
    final store = _MemoryStore(storedData);
    final api = _PollBflApi(() async => <String, Object?>{'status': 'Pending'});
    final gateway = _gateway(store: store, api: api);

    await gateway.poll(_generation(status: 'Pending'));

    expect(store.data.generations, isEmpty);
  });

  test(
    'the delivery purge waits for one post-expiry recovery attempt',
    () async {
      final now = DateTime.now().toUtc();
      final base = _generation(
        resultUrl: _storedResultUrl,
      ).copyWith(deliveryExpiresAt: now.subtract(const Duration(minutes: 5)));
      final unattempted = base.copyWith(
        lastCheckedAt: now.subtract(const Duration(minutes: 20)),
      );
      final attempted = base.copyWith(
        lastCheckedAt: now.subtract(const Duration(minutes: 1)),
      );
      final api = _PollBflApi(() async => <String, Object?>{'status': 'Ready'});

      final keptStore = _MemoryStore(
        StoredData(generations: <Generation>[unattempted]),
      );
      final kept = await _gateway(store: keptStore, api: api).load();
      expect(kept.generations.single.resultUrl, _storedResultUrl);
      expect(kept.generations.single.deliveryExpired, isFalse);

      final purgedStore = _MemoryStore(
        StoredData(generations: <Generation>[attempted]),
      );
      final purged = await _gateway(store: purgedStore, api: api).load();
      expect(purged.generations.single.resultUrl, isNull);
      expect(purged.generations.single.deliveryExpired, isTrue);
    },
  );

  test('ready status and delivery link persist before the download', () async {
    final store = _MemoryStore(
      StoredData(
        apiKeys: const <String, String>{'bfl': 'secret'},
        generations: <Generation>[_generation(status: 'Pending')],
      ),
    );
    const freshUrl = 'https://cdn.example.com/results/fresh.mp4';
    final api = _PollBflApi(
      () async => <String, Object?>{
        'status': 'Ready',
        'result': <String, Object?>{'sample': freshUrl},
      },
    );
    final gateway = _gateway(
      store: store,
      api: api,
      // The download never completes, standing in for a suspension or crash
      // in the middle of result retention.
      client: MockClient((request) => Completer<http.Response>().future),
    );

    unawaited(gateway.poll(_generation(status: 'Pending')));
    for (var i = 0; i < 20; i += 1) {
      await Future<void>.delayed(Duration.zero);
    }

    final persisted = store.data.generations.single;
    expect(persisted.isReady, isTrue);
    expect(persisted.resultUrl, freshUrl);
    expect(persisted.resultAsset, isNull);
  });
}
