import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'bfl_api.dart';
import 'generation_status.dart';
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
      var next = item.recoverInterruptedSubmission(now);
      if (!identical(next, item)) changed = true;
      if (next.deliveryExpiresAt == null ||
          next.deliveryExpiresAt!.isAfter(now) ||
          (next.resultUrl == null && next.draftCacheUrl == null)) {
        return next;
      }
      changed = true;
      next = Generation.fromJson(<String, Object?>{
        ...next.toJson(),
        'resultUrl': null,
        'draftCacheUrl': null,
        'deliveryExpired':
            next.resultAsset == null || next.draftCacheUrl != null,
      });
      return next;
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

  String _keyframeSource(Object? value) {
    if (value is String) return value;
    if (value is List<Object?> && value.length > 1 && value[1] is String) {
      return value[1]! as String;
    }
    return '';
  }

  Future<GenerationConfig> _persistInputs(
    GenerationConfig config,
    Map<String, Object?> input,
  ) async {
    final mode = input['mode'];
    if (mode == 'i2v') {
      final rawFrames = input['keyframes'] as List<Object?>? ?? const [];
      final frames = <KeyframeLabel>[];
      for (var index = 0; index < (config.keyframes?.length ?? 0); index += 1) {
        final frame = config.keyframes![index];
        frames.add(
          KeyframeLabel(
            label: frame.label,
            role: frame.role,
            seconds: frame.seconds,
            source: await _store.persistSource(
              index < rawFrames.length ? _keyframeSource(rawFrames[index]) : '',
              label: frame.label,
              retained: frame.source,
            ),
          ),
        );
      }
      return config.copyWith(keyframes: frames);
    }
    if (mode == 'v2v' || mode == 'draft_enhance') {
      final source = input[mode == 'v2v' ? 'start_video' : 'draft_cache'];
      return config.copyWith(
        source: await _store.persistSource(
          source?.toString() ?? '',
          label: config.sourceLabel ?? 'Clawnsole source',
          retained: config.source,
        ),
      );
    }
    return config;
  }

  @override
  Future<Generation> submit(GenerationSubmission submission) async {
    var record = submission.record;
    final data = await _readFresh();
    final key = data.apiKey.trim();
    if (key.isEmpty) throw StateError('Add a BFL API key before generating.');
    record = record.copyWith(
      config: await _persistInputs(record.config, submission.input),
    );
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
        lastProviderStatusCode: 200,
        lastProviderResponse: compactProviderResponse(response),
        lastProviderResponseAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      await _replaceGeneration(record);
      return record;
    } on Object catch (error) {
      record = record.copyWith(
        status: 'Error',
        error: generationExceptionMessage(error),
        lastProviderStatusCode: providerHttpStatus(error),
        lastProviderResponse: providerErrorResponse(error),
        lastProviderResponseAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      await _replaceGeneration(record);
      rethrow;
    }
  }

  @override
  Future<Generation> poll(Generation generation) async {
    final checkedAt = DateTime.now().toUtc();
    late Generation next;
    try {
      final key = (await _store.read()).apiKey.trim();
      if (key.isEmpty) throw StateError('The saved BFL API key is missing.');
      if (!generation.canCheckStatus) {
        throw StateError('This generation has no polling URL.');
      }
      final payload = await _api.poll(key, generation.pollingUrl!);
      var status = normalizeGenerationStatus(payload['status']);
      final resultUrl = status == 'Ready'
          ? findResultUrl(payload['result'], draft: false)
          : null;
      final draftUrl = status == 'Ready'
          ? findResultUrl(payload['result'], draft: true)
          : null;
      var failureMessage = isGenerationFailureStatus(status)
          ? providerFailureMessage(payload, fallback: status)
          : null;
      if (status == 'Ready' && resultUrl == null) {
        status = 'Error';
        failureMessage =
            'BFL reported that the generation was ready but did not include a video URL.';
      }
      AssetReference? resultAsset = generation.resultAsset;
      if (resultUrl != null && resultAsset == null) {
        try {
          final response = await _client.get(validatedBflUrl(resultUrl));
          if (response.statusCode >= 200 && response.statusCode < 300) {
            resultAsset = await _store.writeAsset(
              response.bodyBytes,
              label: 'clawnsole-${generation.localId}.mp4',
              contentType: response.headers['content-type'] ?? 'video/mp4',
            );
          }
        } on Object {
          // The temporary provider URL remains available if local retention fails.
        }
      }
      final failed = isGenerationFailureStatus(status);
      next = generation.copyWith(
        status: status,
        progress: status == 'Ready'
            ? 100
            : normalizedProgress(payload['progress']),
        resultUrl: resultUrl,
        resultAsset: resultAsset,
        deliveryExpired: status == 'Ready' ? false : generation.deliveryExpired,
        draftCacheUrl: draftUrl,
        deliveryExpiresAt: status == 'Ready'
            ? checkedAt.add(const Duration(minutes: 10))
            : null,
        error: failureMessage,
        clearError: !failed,
        lastCheckedAt: checkedAt,
        statusCheckCount: generation.statusCheckCount + 1,
        consecutiveCheckFailures: 0,
        clearLastCheckError: true,
        lastProviderStatusCode: 200,
        lastProviderResponse: compactProviderResponse(payload),
        lastProviderResponseAt: checkedAt,
        updatedAt: checkedAt,
      );
    } on Object catch (error) {
      final payload = providerErrorPayload(error);
      final providerStatus = normalizeGenerationStatus(payload?['status']);
      if (payload != null && isGenerationFailureStatus(providerStatus)) {
        next = generation.copyWith(
          status: providerStatus,
          progress: normalizedProgress(payload['progress']),
          error: providerFailureMessage(payload, fallback: providerStatus),
          lastCheckedAt: checkedAt,
          statusCheckCount: generation.statusCheckCount + 1,
          consecutiveCheckFailures: 0,
          clearLastCheckError: true,
          lastProviderStatusCode: providerHttpStatus(error),
          lastProviderResponse: providerErrorResponse(error),
          lastProviderResponseAt: checkedAt,
          updatedAt: checkedAt,
        );
      } else {
        next = generation.copyWith(
          lastCheckedAt: checkedAt,
          statusCheckCount: generation.statusCheckCount + 1,
          consecutiveCheckFailures: generation.consecutiveCheckFailures + 1,
          lastCheckError: generationExceptionMessage(error),
          lastProviderStatusCode: providerHttpStatus(error),
          lastProviderResponse: providerErrorResponse(error),
          lastProviderResponseAt: checkedAt,
          updatedAt: checkedAt,
        );
      }
    }
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
    await _store.pruneAssets(next.generations);
    return _snapshot(next);
  }

  @override
  Future<LocalSnapshot> clearHistory() async {
    final next = (await _store.read()).copyWith(generations: <Generation>[]);
    await _store.write(next);
    await _store.clearAssets();
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
  Future<Uri> assetUri(AssetReference reference) => _store.assetUri(reference);

  @override
  Future<Uint8List> readAsset(AssetReference reference) async {
    if (reference.isLocal) return _store.readAsset(reference);
    final response = await _client.get(Uri.parse(reference.value));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('The retained remote input is unavailable.');
    }
    return response.bodyBytes;
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
