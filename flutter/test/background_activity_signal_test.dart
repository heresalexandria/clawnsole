import 'dart:typed_data';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/core/background_activity.dart';
import 'package:clawnsole/core/bfl_api.dart';
import 'package:clawnsole/core/direct_gateway.dart';
import 'package:clawnsole/core/durable_data_store.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/provider_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _RecordingCoordinator implements BackgroundActivityCoordinator {
  final List<bool> received = <bool>[];

  @override
  Future<void> setPendingWork(bool pending) async => received.add(pending);
}

class _PendingBflApi extends BflApi {
  int pollCalls = 0;

  @override
  Future<double> getCredits(String apiKey) async => 10;

  @override
  Future<Map<String, Object?>> poll(String apiKey, String pollingUrl) async {
    pollCalls += 1;
    return <String, Object?>{'status': 'Pending'};
  }
}

class _MemoryStore implements DurableDataStore {
  _MemoryStore(this.data);

  StoredData data;

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
  }) async => AssetReference(kind: 'local', value: label, label: label);
}

Generation _working({
  required DateTime lastCheckedAt,
  int consecutiveCheckFailures = 0,
}) {
  final created = lastCheckedAt.subtract(const Duration(minutes: 1));
  return Generation(
    localId: 'work-1',
    provider: 'bfl',
    model: 'flux-3-video',
    status: 'Pending',
    prompt: 'A crab conducts an orchestra',
    mode: VideoMode.t2v,
    config: const GenerationConfig(
      aspectRatio: '16:9',
      duration: 5,
      resolution: 'hd',
      generateAudio: false,
      safetyTolerance: 2,
      draft: false,
    ),
    pollingUrl: 'https://api.bfl.ai/v1/get_result?id=abc',
    lastCheckedAt: lastCheckedAt,
    consecutiveCheckFailures: consecutiveCheckFailures,
    createdAt: created,
    updatedAt: created,
  );
}

void main() {
  test('pending provider work is signalled to the platform shell', () {
    final coordinator = _RecordingCoordinator();
    final controller = AppController(
      gateway: DirectGateway(store: _MemoryStore(const StoredData())),
      backgroundActivity: coordinator,
    );
    const stats = StorageStats(path: 'memory', bytes: 0, records: 1);

    controller.snapshot = LocalSnapshot(
      generations: <Generation>[
        _working(lastCheckedAt: DateTime.now().toUtc()),
      ],
      preferences: const AppPreferences(),
      hasApiKey: true,
      connectedProviders: const <String>{'bfl'},
      storage: stats,
    );
    controller.showNotice('working');
    expect(coordinator.received, isNotEmpty);
    expect(coordinator.received.last, isTrue);

    controller.snapshot = LocalSnapshot(
      generations: <Generation>[
        _working(lastCheckedAt: DateTime.now().toUtc()).copyWith(
          status: 'Ready',
          resultAsset: const AssetReference(
            kind: 'local',
            value: 'film.mp4',
            label: 'f',
          ),
        ),
      ],
      preferences: const AppPreferences(),
      hasApiKey: true,
      connectedProviders: const <String>{'bfl'},
      storage: stats,
    );
    controller.showNotice('done');
    expect(coordinator.received.last, isFalse);

    controller.dispose();
    expect(coordinator.received.last, isFalse);
  });

  test(
    'foreground reconcile polls records that backoff would postpone',
    () async {
      final api = _PendingBflApi();
      final store = _MemoryStore(
        StoredData(
          apiKeys: const <String, String>{'bfl': 'secret'},
          generations: <Generation>[
            // Five consecutive failures put the next automatic check a minute
            // out, which a periodic tick honors but a foreground return must
            // not.
            _working(
              lastCheckedAt: DateTime.now().toUtc(),
              consecutiveCheckFailures: 5,
            ),
          ],
        ),
      );
      final controller = AppController(
        gateway: DirectGateway(
          store: store,
          providerRouter: ProviderApiRouter(bfl: api),
          client: MockClient((request) async => http.Response('missing', 404)),
        ),
        backgroundActivity: _RecordingCoordinator(),
      );

      // The first reconcile loads the snapshot; polling needs the loaded keys.
      await controller.reconcileGenerationWork();
      await controller.pollWorking();
      expect(api.pollCalls, 0, reason: 'backoff still applies to timer ticks');

      await controller.reconcileGenerationWork();
      expect(api.pollCalls, 1, reason: 'foreground return ignores backoff');

      controller.dispose();
    },
  );
}
