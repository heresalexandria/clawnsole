import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'apple_local_runtime.dart';
import 'bfl_api.dart';
import 'generation_status.dart';
import 'gateway.dart';
import 'local_data_store.dart';
import 'models.dart';
import 'pricing.dart';
import 'provider_api.dart';
import 'provider_catalog.dart';

const _configuredIosReviewApiKey = String.fromEnvironment(
  'CLAWNSOLE_IOS_REVIEW_BFL_API_KEY',
);
const _configuredIosReviewApiKeyId = String.fromEnvironment(
  'CLAWNSOLE_IOS_REVIEW_BFL_API_KEY_ID',
);
const _configuredIosReviewLtxApiKey = String.fromEnvironment(
  'CLAWNSOLE_IOS_REVIEW_LTX_API_KEY',
);
const _configuredIosReviewLtxApiKeyId = String.fromEnvironment(
  'CLAWNSOLE_IOS_REVIEW_LTX_API_KEY_ID',
);
const _configuredIosReviewAtlasApiKey = String.fromEnvironment(
  'CLAWNSOLE_IOS_REVIEW_ATLAS_API_KEY',
);
const _configuredIosReviewAtlasApiKeyId = String.fromEnvironment(
  'CLAWNSOLE_IOS_REVIEW_ATLAS_API_KEY_ID',
);
const _configuredIosReviewArtCraftApiKey = String.fromEnvironment(
  'CLAWNSOLE_IOS_REVIEW_ARTCRAFT_API_KEY',
);
const _configuredIosReviewArtCraftApiKeyId = String.fromEnvironment(
  'CLAWNSOLE_IOS_REVIEW_ARTCRAFT_API_KEY_ID',
);

List<String> _cleanLibraryTags(Iterable<String> input) {
  final tags = <String>[];
  final seen = <String>{};
  for (final value in input) {
    final clean = value.trim().replaceFirst(RegExp(r'^#+'), '').trim();
    final key = clean.toLowerCase();
    if (clean.isEmpty || clean.length > 28 || seen.contains(key)) continue;
    seen.add(key);
    tags.add(clean);
    if (tags.length == 12) break;
  }
  return tags;
}

enum _ApiKeySource { saved, iosReview }

class _ActiveApiKey {
  const _ActiveApiKey(this.value, this.source);

  final String value;
  final _ApiKeySource source;
}

class NativeGateway
    implements AppGateway, ProviderGateway, LibraryOrganizationGateway {
  NativeGateway({
    LocalDataStore? store,
    BflApi? api,
    http.Client? client,
    String? iosReviewApiKey,
    String? iosReviewApiKeyId,
    String? iosReviewLtxApiKey,
    String? iosReviewLtxApiKeyId,
    String? iosReviewAtlasApiKey,
    String? iosReviewAtlasApiKeyId,
    String? iosReviewArtCraftApiKey,
    String? iosReviewArtCraftApiKeyId,
    ProviderApiRouter? providerRouter,
    AppleLocalRuntime? appleLocalRuntime,
    bool? isIos,
  }) : _store = store ?? LocalDataStore(),
       _providers = providerRouter ?? ProviderApiRouter(bfl: api),
       _client = client ?? http.Client(),
       _iosReviewApiKey = (iosReviewApiKey ?? _configuredIosReviewApiKey)
           .trim(),
       _iosReviewApiKeyId = (iosReviewApiKeyId ?? _configuredIosReviewApiKeyId)
           .trim(),
       _iosReviewKeys = <String, String>{
         'ltx': (iosReviewLtxApiKey ?? _configuredIosReviewLtxApiKey).trim(),
         'atlas': (iosReviewAtlasApiKey ?? _configuredIosReviewAtlasApiKey)
             .trim(),
         'artcraft':
             (iosReviewArtCraftApiKey ?? _configuredIosReviewArtCraftApiKey)
                 .trim(),
       },
       _iosReviewKeyIds = <String, String>{
         'ltx': (iosReviewLtxApiKeyId ?? _configuredIosReviewLtxApiKeyId)
             .trim(),
         'atlas': (iosReviewAtlasApiKeyId ?? _configuredIosReviewAtlasApiKeyId)
             .trim(),
         'artcraft':
             (iosReviewArtCraftApiKeyId ?? _configuredIosReviewArtCraftApiKeyId)
                 .trim(),
       },
       _appleLocal =
           appleLocalRuntime ?? const MethodChannelAppleLocalRuntime(),
       _isIos = isIos ?? Platform.isIOS;

  final LocalDataStore _store;
  final ProviderApiRouter _providers;
  final http.Client _client;
  final String _iosReviewApiKey;
  final String _iosReviewApiKeyId;
  final Map<String, String> _iosReviewKeys;
  final Map<String, String> _iosReviewKeyIds;
  final AppleLocalRuntime _appleLocal;
  final bool _isIos;
  Future<bool>? _appleLocalAvailability;

  Future<bool> _isAppleLocalAvailable() => !_isIos
      ? Future<bool>.value(false)
      : _appleLocalAvailability ??= _appleLocal.isAvailable();

  String _reviewKey(String provider) =>
      provider == 'bfl' ? _iosReviewApiKey : _iosReviewKeys[provider] ?? '';

  String _reviewKeyId(String provider) =>
      provider == 'bfl' ? _iosReviewApiKeyId : _iosReviewKeyIds[provider] ?? '';

  _ActiveApiKey? _activeApiKey(String provider, StoredData data) {
    final saved = data.apiKeyFor(provider).trim();
    if (saved.isNotEmpty) return _ActiveApiKey(saved, _ApiKeySource.saved);
    final reviewKey = _reviewKey(provider);
    final reviewKeyId = _reviewKeyId(provider);
    if (_isIos &&
        reviewKey.isNotEmpty &&
        reviewKeyId.isNotEmpty &&
        data.rejectedReviewKeyIdFor(provider) != reviewKeyId) {
      return _ActiveApiKey(reviewKey, _ApiKeySource.iosReview);
    }
    return null;
  }

  @override
  bool get usesCompanion => false;

  @override
  bool get supportsPhotoLibrarySave => Platform.isIOS || Platform.isAndroid;

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
    var data = input ?? await _readFresh();
    final appleLocalAvailable = await _isAppleLocalAvailable();
    if (appleLocalAvailable && !await _store.exists()) {
      data = data.copyWith(
        preferences: const AppPreferences(
          provider: 'apple-local',
          model: 'apple-local-image',
        ),
      );
      await _store.write(data);
    }
    final connected = videoProviders
        .where((provider) => _activeApiKey(provider.id, data) != null)
        .map((provider) => provider.id)
        .toSet();
    if (appleLocalAvailable) connected.add('apple-local');
    return LocalSnapshot(
      generations: data.generations,
      folders: data.folders,
      preferences: data.preferences,
      hasApiKey: connected.contains('bfl'),
      connectedProviders: connected,
      availableProviders: <String>{
        'bfl',
        'ltx',
        'artcraft',
        'atlas',
        if (appleLocalAvailable) 'apple-local',
      },
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
    return setProviderApiKey('bfl', value);
  }

  @override
  Future<LocalSnapshot> setProviderApiKey(String provider, String value) async {
    final clean = value.trim();
    if (clean.length > 2000) {
      throw StateError('The provider API key is unexpectedly long.');
    }
    final next = (await _store.read()).withApiKey(provider, clean);
    await _store.write(next);
    return _snapshot(next);
  }

  Future<void> _invalidateCredential(
    String provider,
    _ActiveApiKey rejected,
  ) async {
    final current = await _store.read();
    final active = _activeApiKey(provider, current);
    if (active == null ||
        active.source != rejected.source ||
        active.value != rejected.value) {
      return;
    }
    final next = switch (rejected.source) {
      _ApiKeySource.saved => current.withApiKey(provider, ''),
      _ApiKeySource.iosReview => current.withRejectedReviewKeyId(
        provider,
        _reviewKeyId(provider),
      ),
    };
    await _store.write(next);
  }

  @override
  Future<double> verifyKey([String? candidate]) async {
    final account = await verifyProviderKey('bfl', candidate);
    return account.balance ?? 0;
  }

  @override
  Future<ProviderAccountStatus> verifyProviderKey(
    String provider, [
    String? candidate,
  ]) async {
    final supplied = candidate?.trim().isNotEmpty == true;
    final active = supplied
        ? null
        : _activeApiKey(provider, await _store.read());
    final key = supplied ? candidate!.trim() : active?.value ?? '';
    if (key.isEmpty) throw StateError('An API key is required.');
    try {
      return await _providers.verify(provider, key);
    } on Object catch (error) {
      if (active != null &&
          (providerHttpStatus(error) == 401 ||
              providerHttpStatus(error) == 403)) {
        await _invalidateCredential(provider, active);
      }
      rethrow;
    }
  }

  @override
  Future<double> getCredits() => verifyKey();

  @override
  Future<ProviderAccountStatus> getProviderAccount(String provider) =>
      verifyProviderKey(provider);

  @override
  Future<List<ProviderModelPrice>> listProviderModels(String provider) async {
    final credential = _activeApiKey(provider, await _store.read());
    return _providers.listModels(provider, credential?.value);
  }

  @override
  Future<LocalSnapshot> setPreferences(AppPreferences preferences) async {
    final next = (await _store.read()).copyWith(preferences: preferences);
    await _store.write(next);
    return _snapshot(next);
  }

  @override
  Future<LocalSnapshot> saveLibraryFolder(LibraryFolder folder) async {
    final name = folder.name.trim();
    if (folder.id.trim().isEmpty || name.isEmpty || name.length > 48) {
      throw StateError('Folder names must be between 1 and 48 characters.');
    }
    final current = await _store.read();
    final parentId = folder.parentId?.trim().isEmpty == true
        ? null
        : folder.parentId;
    if (parentId != null &&
        !current.folders.any((item) => item.id == parentId)) {
      throw StateError('The parent folder no longer exists.');
    }
    var ancestorId = parentId;
    while (ancestorId != null) {
      if (ancestorId == folder.id) {
        throw StateError('A folder cannot live inside itself.');
      }
      ancestorId = current.folders
          .where((item) => item.id == ancestorId)
          .firstOrNull
          ?.parentId;
    }
    if (current.folders.any(
      (item) =>
          item.id != folder.id &&
          item.parentId == parentId &&
          item.name.toLowerCase() == name.toLowerCase(),
    )) {
      throw StateError('A folder named “$name” already exists here.');
    }
    final folders = List<LibraryFolder>.from(current.folders);
    final index = folders.indexWhere((item) => item.id == folder.id);
    final clean = LibraryFolder(
      id: folder.id,
      name: name,
      createdAt: folder.createdAt,
      parentId: parentId,
    );
    if (index < 0) {
      folders.add(clean);
    } else {
      folders[index] = clean;
    }
    final next = current.copyWith(folders: folders);
    await _store.write(next);
    return _snapshot(next);
  }

  @override
  Future<LocalSnapshot> deleteLibraryFolder(String folderId) async {
    final current = await _store.read();
    final removed = current.folders
        .where((folder) => folder.id == folderId)
        .firstOrNull;
    final next = current.copyWith(
      folders: current.folders
          .where((folder) => folder.id != folderId)
          .map(
            (folder) => folder.parentId == folderId
                ? folder.copyWith(
                    parentId: removed?.parentId,
                    clearParent: removed?.parentId == null,
                  )
                : folder,
          )
          .toList(),
      generations: current.generations
          .map(
            (item) => item.folderId == folderId
                ? item.copyWith(clearFolder: true)
                : item,
          )
          .toList(),
    );
    await _store.write(next);
    return _snapshot(next);
  }

  @override
  Future<LocalSnapshot> setGenerationOrganization(
    String localId, {
    String? folderId,
    required List<String> tags,
  }) async {
    final current = await _store.read();
    if (folderId != null &&
        !current.folders.any((folder) => folder.id == folderId)) {
      throw StateError('That folder no longer exists.');
    }
    final cleanTags = _cleanLibraryTags(tags);
    var found = false;
    final generations = current.generations.map((item) {
      if (item.localId != localId) return item;
      found = true;
      return item.copyWith(
        folderId: folderId,
        clearFolder: folderId == null,
        tags: cleanTags,
      );
    }).toList();
    if (!found) throw StateError('That generation no longer exists.');
    final next = current.copyWith(generations: generations);
    await _store.write(next);
    return _snapshot(next);
  }

  Future<double?> _balanceSafely(String provider, String key) async {
    try {
      return (await _providers.verify(provider, key)).balance;
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
      final rawReferences = <MediaReferenceKind, List<Object?>>{
        MediaReferenceKind.image:
            input['reference_images'] as List<Object?>? ?? const [],
        MediaReferenceKind.video:
            input['reference_videos'] as List<Object?>? ?? const [],
        MediaReferenceKind.audio:
            input['reference_audios'] as List<Object?>? ?? const [],
      };
      final offsets = <MediaReferenceKind, int>{
        for (final kind in MediaReferenceKind.values) kind: 0,
      };
      final references = <MediaReferenceLabel>[];
      for (final media in config.references ?? const <MediaReferenceLabel>[]) {
        final index = offsets[media.kind]!;
        final sources = rawReferences[media.kind]!;
        offsets[media.kind] = index + 1;
        references.add(
          MediaReferenceLabel(
            label: media.label,
            kind: media.kind,
            source: await _store.persistSource(
              index < sources.length ? sources[index]?.toString() ?? '' : '',
              label: media.label,
              retained: media.source,
            ),
          ),
        );
      }
      return config.copyWith(keyframes: frames, references: references);
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
    final provider = record.provider;
    if (provider == 'apple-local') {
      return _submitAppleLocal(record, submission.input);
    }
    final credential = _activeApiKey(provider, data);
    final key = credential?.value ?? '';
    if (key.isEmpty) {
      throw StateError(
        'Add a ${providerById(provider).name} API key before generating.',
      );
    }
    record = record.copyWith(
      config: await _persistInputs(record.config, submission.input),
    );
    final estimate = estimateCost(
      provider,
      record.model,
      record.mode,
      record.config,
      data.generations,
    );
    record = record.copyWith(
      estimatedCreditsMin:
          record.estimatedCreditsMin ??
          estimate.providerUnitsMinimum ??
          estimate.minimumUsd,
      estimatedCreditsMax:
          record.estimatedCreditsMax ??
          estimate.providerUnitsMaximum ??
          estimate.maximumUsd,
      estimateBasis: record.estimateBasis ?? estimate.basis,
      updatedAt: DateTime.now().toUtc(),
    );
    await _replaceGeneration(record);

    try {
      final creditsBefore = await _balanceSafely(provider, key);
      if (creditsBefore != null) {
        record = record.copyWith(creditsBefore: creditsBefore);
        await _replaceGeneration(record);
      }
      final response = await _providers.submit(
        provider,
        key,
        record.model,
        submission.input,
      );
      final requestId = response['id'];
      final pollingUrl = response['polling_url'];
      if (requestId is! String || pollingUrl is! String) {
        throw const ProviderException(
          'The provider returned an invalid generation receipt.',
          status: 502,
        );
      }
      final cost = (response['cost'] as num?)?.toDouble();
      final liveAfter = await _balanceSafely(provider, key);
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
      if (credential != null &&
          (providerHttpStatus(error) == 401 ||
              providerHttpStatus(error) == 403)) {
        await _invalidateCredential(provider, credential);
      }
      rethrow;
    }
  }

  Future<Generation> _submitAppleLocal(
    Generation record,
    Map<String, Object?> input,
  ) async {
    if (!record.isImage || record.model != 'apple-local-image') {
      throw StateError(
        'Apple Local animation is no longer available. Choose another video provider.',
      );
    }
    if (!await _isAppleLocalAvailable()) {
      throw StateError(
        'Apple Local generation is unavailable on this device or simulator.',
      );
    }
    record = record.copyWith(
      config: await _persistInputs(record.config, input),
      updatedAt: DateTime.now().toUtc(),
    );
    await _replaceGeneration(record);
    try {
      String? referenceImagePath;
      final frames = record.config.keyframes;
      final reference = frames == null || frames.isEmpty
          ? null
          : frames.first.source;
      if (reference != null) {
        if (!reference.isLocal) {
          throw StateError(
            'Apple Local reference images must be uploaded from this device.',
          );
        }
        referenceImagePath = (await _store.assetUri(reference)).toFilePath();
      }
      final duration = record.config.duration is num
          ? (record.config.duration as num).toInt()
          : 1;
      final receipt = await _appleLocal.submit(<String, Object?>{
        'requestId': record.localId,
        'mode': 'image',
        'prompt': record.prompt,
        'aspectRatio': record.config.aspectRatio,
        'resolution': record.config.resolution,
        'durationSeconds': duration,
        'frameRate': record.config.frameRate,
        if (referenceImagePath != null)
          'referenceImagePath': referenceImagePath,
      });
      final jobId = receipt['jobId']?.toString();
      if (jobId == null || jobId.isEmpty) {
        throw StateError('Apple Local returned an invalid generation receipt.');
      }
      record = record.copyWith(
        requestId: jobId,
        pollingUrl: 'apple-local://$jobId',
        status: 'Pending',
        progress: 0,
        lastProviderStatusCode: 200,
        lastProviderResponse: jsonEncode(receipt),
        lastProviderResponseAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      await _replaceGeneration(record);
      return record;
    } on Object catch (error) {
      record = record.copyWith(
        status: 'Error',
        error: generationExceptionMessage(error),
        updatedAt: DateTime.now().toUtc(),
      );
      await _replaceGeneration(record);
      rethrow;
    }
  }

  @override
  Future<Generation> poll(Generation generation) async {
    if (generation.provider == 'apple-local') {
      return _pollAppleLocal(generation);
    }
    final checkedAt = DateTime.now().toUtc();
    late Generation next;
    _ActiveApiKey? credential;
    try {
      credential = _activeApiKey(generation.provider, await _store.read());
      final key = credential?.value ?? '';
      if (key.isEmpty) {
        throw StateError(
          'The saved ${providerById(generation.provider).name} API key is missing.',
        );
      }
      if (!generation.canCheckStatus) {
        throw StateError('This generation has no polling URL.');
      }
      final payload = await _providers.poll(
        generation.provider,
        key,
        generation.pollingUrl!,
      );
      var status = normalizeGenerationStatus(payload['status']);
      final result = payload['result'] ?? payload['outputs'] ?? payload;
      final resultUrl = status == 'Ready'
          ? findResultUrl(result, draft: false)
          : null;
      final draftUrl = status == 'Ready'
          ? findResultUrl(result, draft: true)
          : null;
      var failureMessage = isGenerationFailureStatus(status)
          ? providerNamedFailureMessage(
              providerById(generation.provider).name,
              payload,
              fallback: status,
            )
          : null;
      if (status == 'Ready' && resultUrl == null) {
        status = 'Error';
        failureMessage =
            '${providerById(generation.provider).name} reported that the generation was ready but did not include a video URL.';
      }
      AssetReference? resultAsset = generation.resultAsset;
      if (resultUrl != null && resultAsset == null) {
        try {
          final response = await _client.get(validatedProviderUrl(resultUrl));
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
      if (credential != null &&
          (providerHttpStatus(error) == 401 ||
              providerHttpStatus(error) == 403)) {
        await _invalidateCredential(generation.provider, credential);
      }
      final payload = providerErrorPayload(error);
      final providerStatus = normalizeGenerationStatus(payload?['status']);
      if (payload != null && isGenerationFailureStatus(providerStatus)) {
        next = generation.copyWith(
          status: providerStatus,
          progress: normalizedProgress(payload['progress']),
          error: providerNamedFailureMessage(
            providerById(generation.provider).name,
            payload,
            fallback: providerStatus,
          ),
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

  Future<Generation> _pollAppleLocal(Generation generation) async {
    final checkedAt = DateTime.now().toUtc();
    try {
      final jobId = generation.requestId;
      if (jobId == null || jobId.isEmpty) {
        throw StateError('This Apple Local generation has no job id.');
      }
      final payload = await _appleLocal.poll(jobId);
      final status = payload['status']?.toString() ?? 'Pending';
      final normalized = normalizeGenerationStatus(status);
      AssetReference? resultAsset = generation.resultAsset;
      if (normalized == 'Ready' && resultAsset == null) {
        final resultPath = payload['resultPath']?.toString();
        final contentType =
            payload['contentType']?.toString() ??
            (generation.isImage ? 'image/png' : 'video/mp4');
        if (resultPath == null || resultPath.isEmpty) {
          throw StateError(
            'Apple Local finished without returning a media file.',
          );
        }
        final resultFile = File(resultPath);
        final bytes = await resultFile.readAsBytes();
        final extension = generation.isImage ? 'png' : 'mp4';
        resultAsset = await _store.writeAsset(
          bytes,
          label: 'clawnsole-${generation.localId}.$extension',
          contentType: contentType,
        );
        try {
          await resultFile.delete();
        } on FileSystemException {
          // The OS clears Apple Local's temporary job directory as needed.
        }
      }
      final failed = isGenerationFailureStatus(normalized);
      final next = generation.copyWith(
        status: normalized,
        progress: normalized == 'Ready'
            ? 100
            : normalizedProgress(payload['progress']),
        resultAsset: resultAsset,
        error: failed ? payload['error']?.toString() ?? status : null,
        clearError: !failed,
        lastCheckedAt: checkedAt,
        statusCheckCount: generation.statusCheckCount + 1,
        consecutiveCheckFailures: 0,
        clearLastCheckError: true,
        lastProviderStatusCode: 200,
        lastProviderResponse: compactProviderResponse(<String, Object?>{
          'status': status,
          'progress': payload['progress'],
          if (payload['message'] != null) 'message': payload['message'],
          if (payload['error'] != null) 'error': payload['error'],
        }),
        lastProviderResponseAt: checkedAt,
        updatedAt: checkedAt,
      );
      await _replaceGeneration(next);
      return next;
    } on Object catch (error) {
      final next = generation.copyWith(
        lastCheckedAt: checkedAt,
        statusCheckCount: generation.statusCheckCount + 1,
        consecutiveCheckFailures: generation.consecutiveCheckFailures + 1,
        lastCheckError: generationExceptionMessage(error),
        updatedAt: checkedAt,
      );
      await _replaceGeneration(next);
      return next;
    }
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
    final localDefault = await _isAppleLocalAvailable();
    final next = (await _store.read()).copyWith(
      preferences: localDefault
          ? const AppPreferences(
              provider: 'apple-local',
              model: 'apple-local-image',
            )
          : const AppPreferences(),
    );
    await _store.write(next);
    return _snapshot(next);
  }

  @override
  Future<LocalSnapshot> clearApiKey() => clearProviderApiKey('bfl');

  @override
  Future<LocalSnapshot> clearProviderApiKey(String provider) async {
    final current = await _store.read();
    var next = current.withApiKey(provider, '');
    final reviewId = _reviewKeyId(provider);
    if (_isIos && reviewId.isNotEmpty) {
      next = next.withRejectedReviewKeyId(provider, reviewId);
    }
    await _store.write(next);
    return _snapshot(next);
  }

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
  Uri mediaUri(String source) => validatedProviderUrl(source);

  @override
  Future<Uint8List> downloadMedia(String source) async {
    final response = await _client.get(validatedProviderUrl(source));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ProviderException(
        'This provider delivery link is no longer available.',
        status: response.statusCode,
      );
    }
    return response.bodyBytes;
  }

  @override
  Future<void> saveMediaToPhotoLibrary(
    Uint8List bytes,
    String fileName,
    String contentType,
  ) async {
    if (!supportsPhotoLibrarySave) {
      throw UnsupportedError(
        'Saving directly to Photos is available in the iOS and Android apps.',
      );
    }

    final hasAccess = await Gal.hasAccess();
    if (!hasAccess && !await Gal.requestAccess()) {
      throw StateError(
        'Photos access was not granted. Allow Clawnsole to add videos in system settings and try again.',
      );
    }

    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/$fileName');
    try {
      await file.writeAsBytes(bytes, flush: true);
      if (contentType.startsWith('image/')) {
        await Gal.putImage(file.path);
      } else {
        await Gal.putVideo(file.path);
      }
    } on GalException catch (error) {
      throw StateError(error.type.message);
    } finally {
      try {
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        // The operating system also cleans this temporary directory.
      }
    }
  }
}
