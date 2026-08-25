import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'bfl_api.dart';
import 'durable_data_store.dart';
import 'generation_status.dart';
import 'generation_timing.dart';
import 'gateway.dart';
import 'models.dart';
import 'pricing.dart';
import 'provider_api.dart';
import 'provider_catalog.dart';
import 'reference_video_normalizer.dart';
import 'settings_vault_gateway.dart';

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

enum ApiKeySource { saved, configured }

class ActiveApiKey {
  const ActiveApiKey(this.value, this.source);

  final String value;
  final ApiKeySource source;
}

class DirectGateway
    implements
        AppGateway,
        ProviderGateway,
        ProviderCatalogCacheGateway,
        LibraryOrganizationGateway,
        ReferenceLibraryGateway,
        ReferenceVideoEditingGateway,
        FavoriteGateway,
        VisibilityGateway,
        GenerationPreviewGateway,
        MediaPreviewGateway {
  DirectGateway({
    required DurableDataStore store,
    BflApi? api,
    http.Client? client,
    ProviderApiRouter? providerRouter,
    ReferenceVideoNormalizationService referenceVideoNormalizer =
        const DisabledReferenceVideoNormalizationService(),
    this.persistenceDescription = 'Durable Clawnsole data store',
    this.availableProviders = const <String>{
      'bfl',
      'ltx',
      'artcraft',
      'atlas',
      'runway',
    },
  }) : _store = store,
       _providers = providerRouter ?? ProviderApiRouter(bfl: api),
       _client = client ?? http.Client(),
       _referenceVideoNormalizer = referenceVideoNormalizer,
       _referenceVideoEditingService =
           referenceVideoNormalizer is ReferenceVideoEditingService
           ? referenceVideoNormalizer as ReferenceVideoEditingService
           : null;

  final DurableDataStore _store;
  final ProviderApiRouter _providers;
  final http.Client _client;
  final ReferenceVideoNormalizationService _referenceVideoNormalizer;
  final ReferenceVideoEditingService? _referenceVideoEditingService;
  @override
  final String persistenceDescription;
  final Set<String> availableProviders;

  ActiveApiKey? activeApiKey(String provider, StoredData data) {
    final saved = data.apiKeyFor(provider).trim();
    return saved.isEmpty ? null : ActiveApiKey(saved, ApiKeySource.saved);
  }

  StoredData clearCredential(String provider, StoredData data) =>
      data.withApiKey(provider, '');

  StoredData rejectConfiguredCredential(String provider, StoredData data) =>
      data;

  Future<void> invalidateCredential(
    String provider,
    ActiveApiKey rejected,
  ) async {
    final current = await _store.read();
    final active = activeApiKey(provider, current);
    if (active == null ||
        active.source != rejected.source ||
        active.value != rejected.value) {
      return;
    }
    final next = switch (rejected.source) {
      ApiKeySource.saved => current.withApiKey(provider, ''),
      ApiKeySource.configured => rejectConfiguredCredential(provider, current),
    };
    await _store.write(next);
  }

  @override
  bool get usesCompanion => false;

  @override
  bool get supportsPhotoLibrarySave => false;

  Future<StoredData> _readFresh() async {
    final current = await _store.read();
    final now = DateTime.now().toUtc();
    var changed = false;
    final generations = current.generations.map((item) {
      var next = item.recoverInterruptedSubmission(now);
      if (!identical(next, item)) changed = true;
      if (next.isReady && next.resultAsset == null) {
        final availability = providerById(
          next.provider,
        ).resultDelivery.availability;
        final expectedExpiry = availability == null
            ? null
            : next.lastProviderResponseAt?.add(availability);
        if (availability == null && next.deliveryExpiresAt != null) {
          changed = true;
          next = next.copyWith(clearDeliveryExpiresAt: true);
        } else if (expectedExpiry != null &&
            (next.deliveryExpiresAt == null ||
                next.deliveryExpiresAt!.isBefore(expectedExpiry))) {
          changed = true;
          next = next.copyWith(deliveryExpiresAt: expectedExpiry);
        }
      }
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
    final connected = videoProviders
        .where(
          (provider) =>
              (availableProviders.contains(provider.id) ||
                  availableProviders.contains(provider.adapter)) &&
              (!provider.requiresApiKey ||
                  activeApiKey(provider.id, data) != null),
        )
        .map((provider) => provider.id)
        .toSet();
    return LocalSnapshot(
      generations: data.generations,
      folders: data.folders,
      savedReferences: data.savedReferences,
      preferences: data.preferences,
      hasApiKey: connected.contains('bfl'),
      connectedProviders: connected,
      availableProviders: availableProviders,
      storage: await _store.stats(
        data.generations.length + data.savedReferences.length,
      ),
      settingsVault: _store is SettingsVaultStatusSource
          ? (_store as SettingsVaultStatusSource).settingsVaultStatus
          : const SettingsVaultStatus.unavailable(),
    );
  }

  Future<Generation> _replaceGeneration(Generation generation) async {
    final current = await _store.read();
    final generations = List<Generation>.from(current.generations);
    final index = generations.indexWhere(
      (item) => item.localId == generation.localId,
    );
    var persisted = generation;
    if (index >= 0) {
      final existing = generations[index];
      persisted = generation.copyWith(
        folderId: existing.folderId,
        clearFolder: existing.folderId == null,
        tags: existing.tags,
        favorite: existing.favorite,
        hidden: existing.hidden,
        storage: existing.storage,
      );
      generations[index] = persisted;
    } else {
      generations.insert(0, persisted);
    }
    final next = current.copyWith(generations: generations);
    await _store.write(next);
    return persisted;
  }

  @override
  Future<LocalSnapshot> load() => _snapshot();

  @override
  Future<Map<String, Object?>?> loadProviderCatalogCache() async =>
      (await _store.read()).providerCatalogCache;

  @override
  Future<void> saveProviderCatalogCache(Map<String, Object?> cache) async {
    final current = await _store.read();
    await _store.write(current.copyWith(providerCatalogCache: cache));
  }

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
        : activeApiKey(provider, await _store.read());
    final key = supplied ? candidate!.trim() : active?.value ?? '';
    if (key.isEmpty) throw StateError('An API key is required.');
    try {
      return await _providers.verify(provider, key);
    } on Object catch (error) {
      if (active != null &&
          (providerHttpStatus(error) == 401 ||
              providerHttpStatus(error) == 403)) {
        await invalidateCredential(provider, active);
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
    final credential = activeApiKey(provider, await _store.read());
    return _providers.listModels(provider, credential?.value);
  }

  @override
  Future<CostEstimate?> quoteProviderCost(
    String provider,
    String model,
    Map<String, Object?> input,
  ) => _providers.quote(provider, model, input);

  @override
  Future<LocalSnapshot> setPreferences(AppPreferences preferences) async {
    final next = (await _store.read()).copyWith(
      preferences: preferences,
      preferencesUpdatedAt: DateTime.now().toUtc(),
    );
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
        !current.folders.any(
          (item) =>
              item.id == parentId &&
              item.collection == folder.collection &&
              item.storage == folder.storage,
        )) {
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
          item.collection == folder.collection &&
          item.storage == folder.storage &&
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
      updatedAt: folder.updatedAt,
      parentId: parentId,
      collection: folder.collection,
      storage: folder.storage,
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
      savedReferences: current.savedReferences
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
    final target = current.generations
        .where((item) => item.localId == localId)
        .firstOrNull;
    if (target == null) throw StateError('That generation no longer exists.');
    if (folderId != null &&
        !current.folders.any(
          (folder) =>
              folder.id == folderId &&
              folder.collection == LibraryCollection.generated &&
              folder.storage == target.storage,
        )) {
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

  @override
  Future<LocalSnapshot> saveReference(
    SavedReference reference, {
    String? source,
  }) async {
    final name = reference.name.trim();
    if (reference.id.trim().isEmpty || name.isEmpty || name.length > 80) {
      throw StateError('Reference names must be between 1 and 80 characters.');
    }
    final current = await _store.read();
    if (reference.folderId != null &&
        !current.folders.any(
          (folder) =>
              folder.id == reference.folderId &&
              folder.collection == LibraryCollection.references &&
              folder.storage == reference.storage,
        )) {
      throw StateError('That reference folder no longer exists.');
    }
    final existing = current.savedReferences
        .where((item) => item.id == reference.id)
        .firstOrNull;
    var asset = existing?.asset ?? reference.asset;
    if (source != null) {
      asset =
          await _store.persistSource(
            source,
            label: name,
            retained: reference.asset.value.isEmpty ? null : reference.asset,
            storage: reference.storage,
          ) ??
          asset;
    }
    if (asset.value.isEmpty) {
      throw StateError('Choose reference media before saving.');
    }
    final clean = SavedReference(
      id: reference.id,
      name: name,
      kind: reference.kind,
      asset: asset,
      thumbnailAsset: existing?.thumbnailAsset ?? reference.thumbnailAsset,
      createdAt: existing?.createdAt ?? reference.createdAt,
      updatedAt: reference.updatedAt,
      folderId: reference.folderId,
      tags: _cleanLibraryTags(reference.tags),
      favorite: reference.favorite,
      hidden: reference.hidden,
      storage: reference.storage,
      contentDigest: reference.contentDigest ?? existing?.contentDigest,
      durationSeconds: reference.durationSeconds ?? existing?.durationSeconds,
    );
    final references = List<SavedReference>.from(current.savedReferences);
    final index = references.indexWhere((item) => item.id == clean.id);
    if (index < 0) {
      references.insert(0, clean);
    } else {
      references[index] = clean;
    }
    final next = current.copyWith(savedReferences: references);
    await _store.write(next);
    return _snapshot(next);
  }

  @override
  Future<LocalSnapshot> trimReferenceVideo({
    required String sourceReferenceId,
    required SavedReference output,
    required double startSeconds,
    required double endSeconds,
  }) async {
    final editor = _referenceVideoEditingService;
    if (editor == null) {
      throw StateError('Video trimming is unavailable on this build.');
    }
    final current = await _store.read();
    final source = current.savedReferences
        .where((item) => item.id == sourceReferenceId)
        .firstOrNull;
    if (source == null || source.kind != MediaReferenceKind.video) {
      throw StateError('That reference video no longer exists.');
    }
    final sourceDuration = source.durationSeconds;
    if (sourceDuration == null ||
        !startSeconds.isFinite ||
        !endSeconds.isFinite ||
        startSeconds < 0 ||
        endSeconds > sourceDuration + .001 ||
        endSeconds - startSeconds < .1) {
      throw StateError('Choose a valid range within the reference video.');
    }
    final name = output.name.trim();
    if (output.id.trim().isEmpty || name.isEmpty || name.length > 80) {
      throw StateError('Reference names must be between 1 and 80 characters.');
    }
    if (current.savedReferences.any((item) => item.id == output.id)) {
      throw StateError('That reference already exists.');
    }
    if (output.storage != source.storage ||
        (output.folderId != null &&
            !current.folders.any(
              (folder) =>
                  folder.id == output.folderId &&
                  folder.collection == LibraryCollection.references &&
                  folder.storage == source.storage,
            ))) {
      throw StateError('That reference folder no longer exists.');
    }
    final original = await _referenceVideoBytes(source.asset);
    final trimmed = await editor.trimVideo(
      original,
      startSeconds: startSeconds,
      endSeconds: endSeconds,
    );
    final asset = await _store.writeAsset(
      trimmed,
      label: name.toLowerCase().endsWith('.mp4') ? name : '$name.mp4',
      contentType: 'video/mp4',
      storage: source.storage,
    );
    final now = DateTime.now().toUtc();
    final saved = SavedReference(
      id: output.id,
      name: name,
      kind: MediaReferenceKind.video,
      asset: asset,
      createdAt: now,
      updatedAt: now,
      folderId: output.folderId,
      tags: _cleanLibraryTags(output.tags),
      favorite: output.favorite,
      hidden: output.hidden,
      storage: source.storage,
      durationSeconds: endSeconds - startSeconds,
    );
    final next = current.copyWith(
      savedReferences: <SavedReference>[saved, ...current.savedReferences],
    );
    await _store.write(next);
    return _snapshot(next);
  }

  Future<Uint8List> _referenceVideoBytes(AssetReference asset) async {
    if (asset.isLocal) return _store.readAsset(asset);
    final uri = Uri.tryParse(asset.value);
    if (uri == null || uri.scheme != 'https') {
      throw StateError('The reference video is not available for trimming.');
    }
    final response = await _client.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('The reference video could not be downloaded.');
    }
    const maximumBytes = 512 * 1024 * 1024;
    if (response.bodyBytes.isEmpty ||
        response.bodyBytes.length > maximumBytes) {
      throw StateError('Reference videos must be 512 MB or smaller.');
    }
    return response.bodyBytes;
  }

  @override
  Future<LocalSnapshot> deleteReference(String referenceId) async {
    final current = await _store.read();
    final next = current.copyWith(
      savedReferences: current.savedReferences
          .where((item) => item.id != referenceId)
          .toList(),
    );
    await _store.write(next);
    await _store.pruneAssets(next.generations, next.savedReferences);
    return _snapshot(next);
  }

  @override
  Future<LocalSnapshot> setGenerationFavorite(
    String localId,
    bool favorite,
  ) async {
    final current = await _store.read();
    if (!current.generations.any((item) => item.localId == localId)) {
      throw StateError('That generation no longer exists.');
    }
    final next = current.copyWith(
      generations: current.generations
          .map(
            (item) => item.localId == localId
                ? item.copyWith(favorite: favorite)
                : item,
          )
          .toList(),
    );
    await _store.write(next);
    return _snapshot(next);
  }

  @override
  Future<LocalSnapshot> setReferenceFavorite(
    String referenceId,
    bool favorite,
  ) async {
    final current = await _store.read();
    if (!current.savedReferences.any((item) => item.id == referenceId)) {
      throw StateError('That reference no longer exists.');
    }
    final next = current.copyWith(
      savedReferences: current.savedReferences
          .map(
            (item) => item.id == referenceId
                ? item.copyWith(
                    favorite: favorite,
                    updatedAt: DateTime.now().toUtc(),
                  )
                : item,
          )
          .toList(),
    );
    await _store.write(next);
    return _snapshot(next);
  }

  @override
  Future<LocalSnapshot> setGenerationsHidden(
    List<String> localIds,
    bool hidden,
  ) async {
    final ids = localIds.toSet();
    final current = await _store.read();
    if (!ids.every(current.generations.map((item) => item.localId).contains)) {
      throw StateError('One or more generations no longer exist.');
    }
    final next = current.copyWith(
      generations: current.generations
          .map(
            (item) => ids.contains(item.localId)
                ? item.copyWith(hidden: hidden)
                : item,
          )
          .toList(),
    );
    await _store.write(next);
    return _snapshot(next);
  }

  @override
  Future<LocalSnapshot> setReferencesHidden(
    List<String> referenceIds,
    bool hidden,
  ) async {
    final ids = referenceIds.toSet();
    final current = await _store.read();
    if (!ids.every(current.savedReferences.map((item) => item.id).contains)) {
      throw StateError('One or more references no longer exist.');
    }
    final now = DateTime.now().toUtc();
    final next = current.copyWith(
      savedReferences: current.savedReferences
          .map(
            (item) => ids.contains(item.id)
                ? item.copyWith(hidden: hidden, updatedAt: now)
                : item,
          )
          .toList(),
    );
    await _store.write(next);
    return _snapshot(next);
  }

  @override
  Future<LocalSnapshot> saveGenerationPreviews(
    String localId, {
    Uint8List? thumbnailBytes,
    Uint8List? timelineBytes,
  }) async {
    if (thumbnailBytes == null && timelineBytes == null) return _snapshot();
    final current = await _store.read();
    final target = current.generations
        .where((item) => item.localId == localId)
        .firstOrNull;
    if (target == null) throw StateError('That generation no longer exists.');
    final thumbnail = thumbnailBytes == null
        ? target.thumbnailAsset
        : await _store.writeAsset(
            thumbnailBytes,
            label: 'clawnsole-$localId-thumbnail.jpg',
            contentType: 'image/jpeg',
            storage: target.storage,
          );
    final timeline = timelineBytes == null
        ? target.timelineThumbnailAsset
        : await _store.writeAsset(
            timelineBytes,
            label: 'clawnsole-$localId-timeline.png',
            contentType: 'image/png',
            storage: target.storage,
          );
    // Asset creation can involve a Drive round trip. Re-read before attaching
    // the references so a star/folder edit made while images upload survives.
    final latest = await _store.read();
    final latestTarget = latest.generations
        .where((item) => item.localId == localId)
        .firstOrNull;
    if (latestTarget == null) {
      throw StateError('That generation no longer exists.');
    }
    final next = latest.copyWith(
      generations: latest.generations
          .map(
            (item) => item.localId == localId
                ? item.copyWith(
                    thumbnailAsset: thumbnail ?? item.thumbnailAsset,
                    timelineThumbnailAsset:
                        timeline ?? item.timelineThumbnailAsset,
                  )
                : item,
          )
          .toList(),
    );
    await _store.write(next);
    await _store.pruneAssets(next.generations, next.savedReferences);
    return _snapshot(next);
  }

  @override
  Future<LocalSnapshot> saveReferencePreview(
    String referenceId,
    Uint8List thumbnailBytes,
  ) async {
    if (thumbnailBytes.isEmpty) return _snapshot();
    final current = await _store.read();
    final target = current.savedReferences
        .where((item) => item.id == referenceId)
        .firstOrNull;
    if (target == null) throw StateError('That reference no longer exists.');
    final thumbnail = await _store.writeAsset(
      thumbnailBytes,
      label: 'clawnsole-$referenceId-thumbnail.jpg',
      contentType: 'image/jpeg',
      storage: target.storage,
    );
    final latest = await _store.read();
    if (!latest.savedReferences.any((item) => item.id == referenceId)) {
      throw StateError('That reference no longer exists.');
    }
    final next = latest.copyWith(
      savedReferences: latest.savedReferences
          .map(
            (item) => item.id == referenceId
                ? item.copyWith(thumbnailAsset: thumbnail)
                : item,
          )
          .toList(),
    );
    await _store.write(next);
    await _store.pruneAssets(next.generations, next.savedReferences);
    return _snapshot(next);
  }

  @override
  Future<LocalSnapshot> saveGenerationInputPreview(
    String localId,
    String sourceAssetValue,
    Uint8List thumbnailBytes,
  ) async {
    if (sourceAssetValue.isEmpty || thumbnailBytes.isEmpty) return _snapshot();
    final current = await _store.read();
    final target = current.generations
        .where((item) => item.localId == localId)
        .firstOrNull;
    if (target == null) throw StateError('That generation no longer exists.');
    final matchesSource = target.config.source?.value == sourceAssetValue;
    final matchesReference =
        target.config.references?.any(
          (item) => item.source?.value == sourceAssetValue,
        ) ==
        true;
    if (!matchesSource && !matchesReference) {
      throw StateError('That generation input no longer exists.');
    }
    final thumbnail = await _store.writeAsset(
      thumbnailBytes,
      label: 'clawnsole-$localId-input-thumbnail.jpg',
      contentType: 'image/jpeg',
      storage: target.storage,
    );
    final latest = await _store.read();
    final latestTarget = latest.generations
        .where((item) => item.localId == localId)
        .firstOrNull;
    if (latestTarget == null) {
      throw StateError('That generation no longer exists.');
    }
    final references = latestTarget.config.references
        ?.map(
          (item) => item.source?.value == sourceAssetValue
              ? item.copyWith(thumbnailAsset: thumbnail)
              : item,
        )
        .toList();
    final config = latestTarget.config.copyWith(
      references: references,
      sourceThumbnailAsset:
          latestTarget.config.source?.value == sourceAssetValue
          ? thumbnail
          : latestTarget.config.sourceThumbnailAsset,
    );
    final next = latest.copyWith(
      generations: latest.generations
          .map(
            (item) =>
                item.localId == localId ? item.copyWith(config: config) : item,
          )
          .toList(),
    );
    await _store.write(next);
    await _store.pruneAssets(next.generations, next.savedReferences);
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
    LibraryStorage storage,
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
            referenceId: frame.referenceId,
            source: await _store.persistSource(
              index < rawFrames.length ? _keyframeSource(rawFrames[index]) : '',
              label: frame.label,
              retained: frame.source,
              storage: storage,
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
            promptName: media.promptName,
            referenceId: media.referenceId,
            thumbnailAsset: media.thumbnailAsset,
            source: await _store.persistSource(
              index < sources.length ? sources[index]?.toString() ?? '' : '',
              label: media.label,
              retained: media.source,
              storage: storage,
            ),
          ),
        );
      }
      return config.copyWith(keyframes: frames, references: references);
    }
    if (mode == 'v2v' ||
        mode == 'draft_enhance' ||
        input.containsKey('input_video')) {
      final source = input.containsKey('input_video')
          ? input['input_video']
          : input[mode == 'v2v' ? 'start_video' : 'draft_cache'];
      return config.copyWith(
        source: await _store.persistSource(
          source?.toString() ?? '',
          label: config.sourceLabel ?? 'Clawnsole source',
          retained: config.source,
          storage: storage,
        ),
        sourceThumbnailAsset: config.sourceThumbnailAsset,
      );
    }
    return config;
  }

  @override
  Future<Generation> submit(GenerationSubmission submission) async {
    var record = submission.record;
    var input = submission.input;
    final data = await _readFresh();
    final provider = record.provider;
    final providerDefinition = providerByIdOrNull(provider);
    final modelDefinition = providerDefinition?.models
        .where((model) => model.id == record.model)
        .firstOrNull;
    if (providerDefinition == null || modelDefinition == null) {
      throw StateError(
        'That provider or model is not available for this Clawnsole version.',
      );
    }
    if (activeProviderCatalogIsMobileTest) {
      final requestedResolution =
          input['resolution']?.toString() ?? record.config.resolution;
      final requestedDuration = input['duration'] ?? record.config.duration;
      final exactDuration =
          requestedDuration is num &&
          requestedDuration.toDouble() == mobileTestDurationSeconds;
      if (record.config.resolution != mobileTestResolutionId ||
          record.config.duration != mobileTestDurationSeconds ||
          requestedResolution != mobileTestResolutionId ||
          !exactDuration) {
        throw StateError(
          'Mobile test generations are limited to 480p and 5 seconds.',
        );
      }
    }
    final credential = activeApiKey(provider, data);
    final key = credential?.value ?? '';
    if (key.isEmpty) {
      throw StateError(
        'Add a ${providerById(provider).name} API key before generating.',
      );
    }
    final model = modelById(provider, record.model);
    final referenceVideoProfile = model.referenceVideoCompatibilityProfile;
    final referenceImageProfile = model.referenceImageCompatibilityProfile;
    if (submission.autoFixReferenceVideos ??
        data.preferences.autoFixReferenceVideos) {
      final ReferenceImageNormalizationService imageNormalizer =
          _referenceVideoNormalizer is ReferenceImageNormalizationService
          ? _referenceVideoNormalizer as ReferenceImageNormalizationService
          : const DisabledReferenceVideoNormalizationService();
      final prepared = await prepareGenerationReferences(
        input: input,
        config: record.config,
        videoNormalizer: _referenceVideoNormalizer,
        imageNormalizer: imageNormalizer,
        videoProfile: referenceVideoProfile,
        imageProfile: referenceImageProfile,
      );
      input = prepared.input;
      record = record.copyWith(config: prepared.config);
    }
    record = record.copyWith(
      config: await _persistInputs(record.config, input, record.storage),
    );
    final estimate = estimateCost(
      provider,
      record.model,
      record.mode,
      record.config,
      data.generations,
    );
    record = record.copyWith(
      canonicalModelId:
          record.canonicalModelId ??
          canonicalModelIdFor(provider, record.model),
      estimatedCreditsMin:
          record.estimatedCreditsMin ??
          estimate.providerUnitsMinimum ??
          estimate.minimumUsd,
      estimatedCreditsMax:
          record.estimatedCreditsMax ??
          estimate.providerUnitsMaximum ??
          estimate.maximumUsd,
      estimateBasis: record.estimateBasis ?? estimate.basis,
      quotedCostUsdMin: record.quotedCostUsdMin ?? estimate.minimumUsd,
      quotedCostUsdMax: record.quotedCostUsdMax ?? estimate.maximumUsd,
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
        input,
      );
      final requestId = response['id'];
      final pollingUrl = response['polling_url'];
      if (requestId is! String || pollingUrl is! String) {
        throw const ProviderException(
          'The provider returned an invalid generation receipt.',
          status: 502,
        );
      }
      final acceptedAt = DateTime.now().toUtc();
      final receiptEstimate = (response['estimated_credits'] as num?)
          ?.toDouble();
      record = record.copyWith(
        requestId: requestId,
        pollingUrl: pollingUrl,
        status: 'Pending',
        clearProgress: true,
        providerAcceptedAt: acceptedAt,
        estimatedCreditsMax: receiptEstimate,
        estimateBasis: receiptEstimate == null
            ? null
            : 'provider submission receipt · maximum charge',
        quotedCostUsdMax: receiptEstimate == null
            ? null
            : creditsToUsd(receiptEstimate),
        lastProviderStatusCode: 200,
        lastProviderResponse: compactProviderResponse(response),
        lastProviderResponseAt: acceptedAt,
        updatedAt: acceptedAt,
      );
      // The provider receipt is the irreplaceable part of the transaction.
      // Persist it before optional balance/cost bookkeeping makes another
      // network request or the app has another opportunity to be suspended.
      record = await _replaceGeneration(record);
      final liveAfter = await _balanceSafely(provider, key);
      final realized = resolveProviderCost(
        record,
        response,
        balanceAfter: liveAfter,
      );
      final cost = realized.providerUnits;
      final creditsAfter =
          liveAfter ??
          (creditsBefore != null && cost != null
              ? (creditsBefore - cost).clamp(0, double.infinity)
              : null);
      record = record.copyWith(
        cost: cost,
        clearCost: cost == null,
        realizedCostUsd: realized.usd,
        realizedCostSource: realized.source,
        creditsBefore: creditsBefore,
        creditsAfter: creditsAfter,
        updatedAt: DateTime.now().toUtc(),
      );
      await _replaceGeneration(record);
      return record;
    } on Object catch (error) {
      if (record.canCheckStatus) {
        // Submission succeeded and the durable receipt is already present.
        // A later accounting/storage refresh must never turn a live provider
        // task into a terminal local error.
        return record;
      }
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
        await invalidateCredential(provider, credential);
      }
      rethrow;
    }
  }

  @override
  Future<Generation> poll(Generation generation) async {
    final checkedAt = DateTime.now().toUtc();
    late Generation next;
    ActiveApiKey? credential;
    try {
      credential = activeApiKey(generation.provider, await _store.read());
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
      AssetReference? resultAsset = generation.resultAsset;
      var retentionFailures = generation.resultRetentionFailures;
      String? retentionError;
      var attemptedRetention = false;
      if (status == 'Ready' && resultAsset == null && resultUrl == null) {
        attemptedRetention = true;
        retentionFailures += 1;
        retentionError =
            '${providerById(generation.provider).name} reports that the generation is ready, but has not supplied a downloadable result yet. Clawnsole will keep retrying.';
      } else if (resultUrl != null && resultAsset == null) {
        attemptedRetention = true;
        try {
          final request = http.Request('GET', validatedProviderUrl(resultUrl));
          final response = await _client
              .send(request)
              .timeout(const Duration(seconds: 30));
          if (response.statusCode < 200 || response.statusCode >= 300) {
            throw ProviderException(
              'The provider result download returned HTTP ${response.statusCode}.',
              status: response.statusCode,
            );
          }
          final bytes = BytesBuilder(copy: false);
          await for (final chunk in response.stream.timeout(
            const Duration(seconds: 30),
          )) {
            bytes.add(chunk);
          }
          resultAsset = await _store.writeAsset(
            bytes.takeBytes(),
            label: 'clawnsole-${generation.localId}.mp4',
            contentType: response.headers['content-type'] ?? 'video/mp4',
            storage: generation.storage,
          );
          retentionFailures = 0;
        } on TimeoutException {
          retentionFailures += 1;
          retentionError =
              'The provider result download stalled. Clawnsole will retry it.';
        } on Object catch (error) {
          retentionFailures += 1;
          retentionError = generationExceptionMessage(error);
        }
      }
      final failed = isGenerationFailureStatus(status);
      final terminal = status == 'Ready' || failed;
      final balanceAfter = terminal
          ? await _balanceSafely(generation.provider, key)
          : null;
      final realized = resolveProviderCost(
        generation,
        payload,
        balanceAfter: balanceAfter,
        allowDeterministicQuote: status == 'Ready',
        terminal: terminal,
      );
      final provider = providerById(generation.provider);
      final reportedProgress =
          progressReportingFor(generation.provider, generation.model) ==
              ProviderProgressReporting.reported
          ? findProviderProgress(payload)
          : null;
      final deliveryAvailability = provider.resultDelivery.availability;
      next = generation.copyWith(
        status: status,
        progress: reportedProgress,
        clearProgress: reportedProgress == null,
        providerCompletedAt: status == 'Ready' && !generation.isReady
            ? providerGenerationCompletedAt(payload) ?? checkedAt
            : null,
        resultUrl: resultUrl,
        resultAsset: resultAsset,
        deliveryExpired: status == 'Ready' ? false : generation.deliveryExpired,
        draftCacheUrl: draftUrl,
        deliveryExpiresAt: status == 'Ready' && deliveryAvailability != null
            ? generation.deliveryExpiresAt ??
                  checkedAt.add(deliveryAvailability)
            : null,
        clearDeliveryExpiresAt:
            status == 'Ready' && deliveryAvailability == null,
        lastResultRetentionAttemptAt: attemptedRetention ? checkedAt : null,
        resultRetentionFailures: resultAsset != null ? 0 : retentionFailures,
        resultRetentionError: retentionError,
        clearResultRetentionError:
            resultAsset != null || status != 'Ready' || retentionError == null,
        error: failureMessage,
        clearError: !failed,
        cost: realized.providerUnits,
        realizedCostUsd: realized.usd,
        realizedCostSource: realized.source,
        creditsAfter: balanceAfter,
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
        await invalidateCredential(generation.provider, credential);
      }
      final payload = providerErrorPayload(error);
      final providerStatus = normalizeGenerationStatus(payload?['status']);
      if (payload != null && isGenerationFailureStatus(providerStatus)) {
        final reportedProgress =
            progressReportingFor(generation.provider, generation.model) ==
                ProviderProgressReporting.reported
            ? findProviderProgress(payload)
            : null;
        next = generation.copyWith(
          status: providerStatus,
          progress: reportedProgress,
          clearProgress: reportedProgress == null,
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
          lastResultRetentionAttemptAt: generation.isReady ? checkedAt : null,
          resultRetentionFailures: generation.isReady
              ? generation.resultRetentionFailures + 1
              : generation.resultRetentionFailures,
          resultRetentionError: generation.isReady
              ? generationExceptionMessage(error)
              : null,
          lastProviderStatusCode: providerHttpStatus(error),
          lastProviderResponse: providerErrorResponse(error),
          lastProviderResponseAt: checkedAt,
          updatedAt: checkedAt,
        );
      }
    }
    return _replaceGeneration(next);
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
    await _store.pruneAssets(next.generations, next.savedReferences);
    return _snapshot(next);
  }

  @override
  Future<LocalSnapshot> clearHistory() async {
    final next = (await _store.read()).copyWith(generations: <Generation>[]);
    await _store.write(next);
    await _store.pruneAssets(next.generations, next.savedReferences);
    return _snapshot(next);
  }

  @override
  Future<LocalSnapshot> clearPreferences() async {
    final next = (await _store.read()).copyWith(
      preferences: const AppPreferences(),
      preferencesUpdatedAt: DateTime.now().toUtc(),
    );
    await _store.write(next);
    return _snapshot(next);
  }

  @override
  Future<LocalSnapshot> clearApiKey() => clearProviderApiKey('bfl');

  @override
  Future<LocalSnapshot> clearProviderApiKey(String provider) async {
    final current = await _store.read();
    final next = clearCredential(provider, current);
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
  ) => throw UnsupportedError(
    'Saving directly to Photos is available in the iOS and Android apps.',
  );
}
