import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'bfl_api.dart';
import 'gateway.dart';
import 'local_data_store.dart';
import 'models.dart';
import 'pricing.dart';

class NativeGateway implements AppGateway {
  NativeGateway({LocalDataStore? store, BflApi? api, http.Client? client})
    : _store = store ?? LocalDataStore(),
      _api = api ?? BflApi(),
      _client = client ?? http.Client();

  final LocalDataStore _store;
  final BflApi _api;
  final http.Client _client;

  @override
  bool get usesCompanion => false;

  @override
  String get persistenceDescription =>
      'Private JSON in this app’s documents directory';

  Future<StoredData> _readFresh() async {
    final current = await _store.read();
    final now = DateTime.now().toUtc();
    var changed = false;
    final generations = current.generations.map((item) {
      if (item.deliveryExpiresAt == null ||
          item.deliveryExpiresAt!.isAfter(now) ||
          (item.resultUrl == null && item.draftCacheUrl == null)) {
        return item;
      }
      changed = true;
      return Generation.fromJson(<String, Object?>{
        ...item.toJson(),
        'resultUrl': null,
        'draftCacheUrl': null,
        'deliveryExpired': true,
      });
    }).toList();
    if (!changed) return current;
    final next = current.copyWith(generations: generations);
    await _store.write(next);
    return next;
  }

  Future<LocalSnapshot> _snapshot([StoredData? input]) async {
    final data = input ?? await _readFresh();
    return LocalSnapshot(
      generations: data.generations,
      preferences: data.preferences,
      hasApiKey: data.apiKey.trim().isNotEmpty,
      storage: await _store.stats(data.generations.length),
    );
  }

  Future<StoredData> _replaceGeneration(Generation generation) async {
    final current = await _store.read();
    final generations = List<Generation>.from(current.generations);
    final index = generations.indexWhere(
      (item) => item.localId == generation.localId,
    );
    if (index >= 0) {
      generations[index] = generation;
    } else {
      generations.insert(0, generation);
    }
    final next = current.copyWith(generations: generations);
    await _store.write(next);
    return next;
  }

  @override
  Future<LocalSnapshot> load() => _snapshot();

  @override
  Future<LocalSnapshot> setApiKey(String value) async {
    final clean = value.trim();
    if (clean.length > 2000) {
      throw StateError('The BFL API key is unexpectedly long.');
    }
    final next = (await _store.read()).copyWith(apiKey: clean);
    await _store.write(next);
    return _snapshot(next);
  }

  @override
  Future<double> verifyKey([String? candidate]) async {
    final key = candidate?.trim().isNotEmpty == true
        ? candidate!.trim()
        : (await _store.read()).apiKey.trim();
    if (key.isEmpty) throw StateError('An API key is required.');
    return _api.getCredits(key);
  }

  @override
  Future<double> getCredits() => verifyKey();

  @override
  Future<LocalSnapshot> setPreferences(AppPreferences preferences) async {
    final next = (await _store.read()).copyWith(preferences: preferences);
    await _store.write(next);
    return _snapshot(next);
  }

  Future<double?> _creditsSafely(String key) async {
    try {
      return await _api.getCredits(key);
    } on Object {
      return null;
    }
  }

  @override
  Future<Generation> submit(GenerationSubmission submission) async {
    var record = submission.record;
    final data = await _readFresh();
    final key = data.apiKey.trim();
    if (key.isEmpty) throw StateError('Add a BFL API key before generating.');
    final estimate = estimateCredits(
      record.mode,
      record.config,
      data.generations,
    );
    record = record.copyWith(
      estimatedCreditsMin: estimate.minimum,
      estimatedCreditsMax: estimate.maximum,
      estimateBasis: estimate.basis,
      updatedAt: DateTime.now().toUtc(),
    );
    await _replaceGeneration(record);

    try {
      final creditsBefore = await _creditsSafely(key);
      if (creditsBefore != null) {
        record = record.copyWith(creditsBefore: creditsBefore);
        await _replaceGeneration(record);
      }
      final response = await _api.submit(key, submission.input);
      final requestId = response['id'];
      final pollingUrl = response['polling_url'];
      if (requestId is! String || pollingUrl is! String) {
        throw const ProviderException(
          'BFL returned an invalid generation receipt.',
          status: 502,
        );
      }
      final cost = (response['cost'] as num?)?.toDouble();
      final liveAfter = await _creditsSafely(key);
      final creditsAfter =
          liveAfter ??
          (creditsBefore != null && cost != null
              ? (creditsBefore - cost).clamp(0, double.infinity)
              : null);
      record = record.copyWith(
        requestId: requestId,
        pollingUrl: pollingUrl,
        status: 'Pending',
        clearProgress: true,
        cost: cost,
        clearCost: cost == null,
        creditsBefore: creditsBefore,
        creditsAfter: creditsAfter,
        updatedAt: DateTime.now().toUtc(),
      );
      await _replaceGeneration(record);
      return record;
    } on Object catch (error) {
      record = record.copyWith(
        status: 'Error',
        error: error.toString(),
        updatedAt: DateTime.now().toUtc(),
      );
      await _replaceGeneration(record);
      rethrow;
    }
  }

  @override
  Future<Generation> poll(Generation generation) async {
    final key = (await _store.read()).apiKey.trim();
    if (key.isEmpty) throw StateError('The saved BFL API key is missing.');
    if (generation.pollingUrl == null) {
      throw StateError('This generation has no polling URL.');
    }
    final payload = await _api.poll(key, generation.pollingUrl!);
    final rawStatus = payload['status'] as String? ?? 'Pending';
    final status =
        rawStatus == 'Ready' ||
            const <String>{
              'Error',
              'Failed',
              'Request Moderated',
              'Content Moderated',
            }.contains(rawStatus)
        ? rawStatus
        : 'Pending';
    final resultUrl = status == 'Ready'
        ? findResultUrl(payload['result'], draft: false)
        : null;
    final draftUrl = status == 'Ready'
        ? findResultUrl(payload['result'], draft: true)
        : null;
    final failed = const <String>{
      'Error',
      'Failed',
      'Request Moderated',
      'Content Moderated',
    }.contains(status);
    final next = generation.copyWith(
      status: status,
      progress: status == 'Ready'
          ? 100
          : normalizedProgress(payload['progress']),
      resultUrl: resultUrl,
      draftCacheUrl: draftUrl,
      deliveryExpiresAt: status == 'Ready'
          ? DateTime.now().toUtc().add(const Duration(minutes: 10))
          : null,
      error: failed
          ? jsonEncode(payload['details'] ?? payload['result'] ?? status)
          : null,
      clearError: !failed,
      updatedAt: DateTime.now().toUtc(),
    );
    await _replaceGeneration(next);
    return next;
  }

  @override
  Future<LocalSnapshot> deleteGeneration(String localId) async {
    final current = await _store.read();
    final next = current.copyWith(
      generations: current.generations
          .where((item) => item.localId != localId)
          .toList(),
    );
    await _store.write(next);
    return _snapshot(next);
  }

  @override
  Future<LocalSnapshot> clearHistory() async {
    final next = (await _store.read()).copyWith(generations: <Generation>[]);
    await _store.write(next);
    return _snapshot(next);
  }

  @override
  Future<LocalSnapshot> clearPreferences() async {
    final next = (await _store.read()).copyWith(
      preferences: const AppPreferences(),
    );
    await _store.write(next);
    return _snapshot(next);
  }

  @override
  Future<LocalSnapshot> clearApiKey() => setApiKey('');

  @override
  Future<LocalSnapshot> clearAll() async {
    await _store.delete();
    return _snapshot(const StoredData());
  }

  @override
  Uri mediaUri(String source) => validatedBflUrl(source);

  @override
  Future<Uint8List> downloadMedia(String source) async {
    final response = await _client.get(validatedBflUrl(source));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ProviderException(
        'This BFL delivery link is no longer available.',
        status: response.statusCode,
      );
    }
    return response.bodyBytes;
  }
}
