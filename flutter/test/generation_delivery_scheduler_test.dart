import 'dart:async';
import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

Generation _film(String id, {bool ready = false, DateTime? expires}) {
  final now = DateTime.now().toUtc();
  return Generation(
    localId: id,
    provider: 'bfl',
    model: 'flux-3-video',
    status: ready ? 'Ready' : 'Pending',
    prompt: 'Same inputs, independent takes.',
    mode: VideoMode.t2v,
    config: const GenerationConfig(
      aspectRatio: '16:9',
      duration: 5,
      resolution: 'hd',
      generateAudio: false,
      safetyTolerance: 2,
      draft: false,
    ),
    pollingUrl: 'https://api.bfl.ai/v1/get_result?id=$id',
    resultUrl: ready ? 'https://cdn.example.com/$id.mp4' : null,
    deliveryExpiresAt: expires,
    createdAt: now,
    updatedAt: now,
  );
}

LocalSnapshot _snapshot(List<Generation> films, {bool hasKey = true}) =>
    LocalSnapshot(
      generations: films,
      preferences: const AppPreferences(),
      hasApiKey: hasKey,
      connectedProviders: hasKey ? const {'bfl'} : const {},
      storage: StorageStats(path: 'memory', bytes: 0, records: films.length),
    );

class _StagedGateway implements AppGateway, GenerationDeliveryGateway {
  final statuses = <String>[];
  final downloads = <String>[];
  final pending = <String, Completer<Generation>>{};
  bool failStatus = false;
  bool rejectKey = false;
  Completer<LocalSnapshot>? loading;
  @override
  Future<LocalSnapshot> load() => loading!.future;
  @override
  Future<Generation> pollStatus(Generation film) async {
    statuses.add(film.localId);
    if (failStatus) throw StateError('Temporary status transport failure');
    return film.copyWith(
      status: 'Ready',
      resultUrl: 'https://cdn.example.com/${film.localId}.mp4',
      statusCheckCount: film.statusCheckCount + 1,
      lastProviderStatusCode: rejectKey ? 401 : 200,
      lastCheckedAt: DateTime.now().toUtc(),
      clearLastCheckError: true,
    );
  }

  @override
  Future<Generation> retainResult(Generation film) {
    downloads.add(film.localId);
    return (pending[film.localId] = Completer<Generation>()).future;
  }

  void finish(Generation film) {
    pending
        .remove(film.localId)!
        .complete(
          film.copyWith(
            resultAsset: AssetReference(
              kind: 'local',
              value: '${film.localId}.mp4',
              label: 'film.mp4',
            ),
            statusCheckCount: film.statusCheckCount + 1,
          ),
        );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);
void main() {
  test('stalled media slots do not hold later provider receipts', () async {
    final gateway = _StagedGateway();
    final controller = AppController(gateway: gateway)
      ..snapshot = _snapshot(List.generate(5, (index) => _film('$index')));
    addTearDown(controller.dispose);
    await controller.pollWorking();
    await _flush();
    expect(gateway.statuses, ['0', '1', '2', '3', '4']);
    expect(
      controller.generations.every(
        (film) => film.isReady && film.resultUrl != null,
      ),
      isTrue,
    );
    expect(gateway.downloads, ['0', '1']);
    await controller.pollWorking(ignoreSchedule: true);
    await controller.checkStatus(controller.generations.first);
    expect(gateway.downloads, ['0', '1']);
    expect(gateway.statuses.length, 5);
    gateway.finish(controller.generations.first);
    await _flush();
    expect(gateway.downloads, ['0', '1', '2']);
    expect(controller.generations.first.resultAsset, isNotNull);
  });
  test('queued delivery links with the nearest expiry run first', () async {
    final gateway = _StagedGateway();
    final now = DateTime.now().toUtc();
    final controller = AppController(gateway: gateway)
      ..snapshot = _snapshot([
        _film('no-expiry', ready: true),
        _film('later', ready: true, expires: now.add(const Duration(hours: 1))),
        _film(
          'soon',
          ready: true,
          expires: now.add(const Duration(minutes: 1)),
        ),
        _film(
          'expired',
          ready: true,
          expires: now.subtract(const Duration(seconds: 1)),
        ),
      ]);
    addTearDown(controller.dispose);
    await controller.pollWorking();
    await _flush();
    expect(gateway.downloads, ['expired', 'soon']);
    expect(gateway.statuses, isEmpty);
  });
  test(
    'a saved delivery link can be retained without a provider key',
    () async {
      final gateway = _StagedGateway();
      final controller = AppController(gateway: gateway)
        ..snapshot = _snapshot([_film('receipt', ready: true)], hasKey: false);
      addTearDown(controller.dispose);
      await controller.pollWorking();
      await _flush();
      expect(gateway.statuses, isEmpty);
      expect(gateway.downloads, ['receipt']);
      expect(controller.hasPendingProviderWork, isTrue);
    },
  );
  test('a late download cannot resurrect a deleted card', () async {
    final gateway = _StagedGateway();
    final controller = AppController(gateway: gateway)
      ..snapshot = _snapshot([_film('deleted', ready: true)]);
    addTearDown(controller.dispose);
    await controller.pollWorking();
    await _flush();
    final film = controller.generations.single;
    controller.snapshot = _snapshot([]);
    gateway.finish(film);
    await _flush();
    expect(controller.generations, isEmpty);
  });
  test(
    'outer status failures do not invent a persisted write version',
    () async {
      final gateway = _StagedGateway()..failStatus = true;
      final controller = AppController(gateway: gateway)
        ..snapshot = _snapshot([_film('retry')]);
      addTearDown(controller.dispose);
      await controller.pollWorking();
      expect(controller.generations.single.statusCheckCount, 0);
      expect(
        controller.generations.single.lastCheckError,
        contains('Temporary'),
      );
      gateway.failStatus = false;
      await controller.pollWorking(ignoreSchedule: true);
      expect(controller.generations.single.statusCheckCount, 1);
      expect(controller.generations.single.isReady, isTrue);
    },
  );
  test(
    'failed retention asks the provider for a fresh link on retry',
    () async {
      final gateway = _StagedGateway();
      final film = _film('refresh-link', ready: true).copyWith(
        resultRetentionFailures: 1,
        resultRetentionError: 'The old signed link expired.',
      );
      final controller = AppController(gateway: gateway)
        ..snapshot = _snapshot([film]);
      addTearDown(controller.dispose);
      await controller.pollWorking(ignoreSchedule: true);
      await _flush();
      expect(gateway.statuses, ['refresh-link']);
      expect(gateway.downloads, ['refresh-link']);
    },
  );
  test(
    'disposing drops queued work without starting extra transfers',
    () async {
      final gateway = _StagedGateway();
      final controller = AppController(gateway: gateway)
        ..snapshot = _snapshot(
          List.generate(3, (index) => _film('$index', ready: true)),
        );
      await controller.pollWorking();
      await _flush();
      final film = controller.generations.first;
      controller.dispose();
      gateway.finish(film);
      await _flush();
      expect(gateway.downloads.length, 2);
    },
  );
  test(
    'status ticks honor retention backoff after repeated download failures',
    () async {
      final gateway = _StagedGateway();
      final now = DateTime.now().toUtc();
      final film = _film('backoff', ready: true).copyWith(
        resultRetentionFailures: 4,
        lastResultRetentionAttemptAt: now,
        lastCheckedAt: now.subtract(const Duration(minutes: 10)),
      );
      final controller = AppController(gateway: gateway)
        ..snapshot = _snapshot([film]);
      addTearDown(controller.dispose);
      await controller.pollWorking();
      await _flush();
      expect(gateway.statuses, isEmpty);
      expect(gateway.downloads, isEmpty);
      await controller.pollWorking(ignoreSchedule: true);
      expect(gateway.statuses, ['backoff']);
    },
  );

  test(
    'auth reconciliation never notifies after controller disposal',
    () async {
      final gateway = _StagedGateway()
        ..rejectKey = true
        ..loading = Completer<LocalSnapshot>();
      final controller = AppController(gateway: gateway)
        ..snapshot = _snapshot([_film('auth')]);
      final checking = controller.pollWorking();
      await _flush();
      controller.dispose();
      gateway.loading!.complete(_snapshot([_film('auth')], hasKey: false));
      await checking;
    },
  );
}
