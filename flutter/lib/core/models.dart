import 'dart:convert';

import 'generation_status.dart';

enum AppSection { create, library, references, providers, settings }

enum LibraryFilter { all, working, ready, failed }

enum GenerationViewMode { compact, mini, full }

enum VideoMode { t2v, i2v, v2v, draftEnhance, upscale }

enum GenerationOutputKind { video, image }

enum GenerationPlaceholderStyle { broadcastStatic, cyclone }

extension GenerationPlaceholderStyleValue on GenerationPlaceholderStyle {
  String get label => switch (this) {
    GenerationPlaceholderStyle.broadcastStatic => 'Static',
    GenerationPlaceholderStyle.cyclone => 'Cyclone',
  };

  static GenerationPlaceholderStyle parse(Object? value) =>
      GenerationPlaceholderStyle.values.firstWhere(
        (style) => style.name == value,
        orElse: () => GenerationPlaceholderStyle.broadcastStatic,
      );
}

enum KeyframeRole { start, middle, end }

enum MediaReferenceKind { image, video, audio }

enum MediaReferenceTask { reference, edit, extend }

enum LibraryCollection { generated, references }

enum LibraryStorage { local, drive }

enum LibraryStorageFilter { all, local, drive }

enum FavoriteFilter { all, starred, unstarred }

extension FavoriteFilterValue on FavoriteFilter {
  bool matches(bool favorite) => switch (this) {
    FavoriteFilter.all => true,
    FavoriteFilter.starred => favorite,
    FavoriteFilter.unstarred => !favorite,
  };

  String get label => switch (this) {
    FavoriteFilter.all => 'All',
    FavoriteFilter.starred => 'Starred',
    FavoriteFilter.unstarred => 'Unstarred',
  };
}

extension LibraryStorageValue on LibraryStorage {
  String get label => switch (this) {
    LibraryStorage.local => 'On this device',
    LibraryStorage.drive => 'Google Drive',
  };

  String get shortLabel => switch (this) {
    LibraryStorage.local => 'Local',
    LibraryStorage.drive => 'Drive',
  };
}

extension LibraryStorageFilterValue on LibraryStorageFilter {
  bool matches(LibraryStorage storage) => switch (this) {
    LibraryStorageFilter.all => true,
    LibraryStorageFilter.local => storage == LibraryStorage.local,
    LibraryStorageFilter.drive => storage == LibraryStorage.drive,
  };
}

enum ReferenceSort { newest, oldest, name, kind }

extension MediaReferenceTaskValue on MediaReferenceTask {
  String get label => switch (this) {
    MediaReferenceTask.reference => 'New video',
    MediaReferenceTask.edit => 'Edit video',
    MediaReferenceTask.extend => 'Extend video',
  };

  static MediaReferenceTask parse(Object? value) =>
      MediaReferenceTask.values.firstWhere(
        (task) => task.name == value,
        orElse: () => MediaReferenceTask.reference,
      );
}

extension MediaReferenceKindValue on MediaReferenceKind {
  String get label => switch (this) {
    MediaReferenceKind.image => 'Image',
    MediaReferenceKind.video => 'Video',
    MediaReferenceKind.audio => 'Audio',
  };

  String get pluralLabel => switch (this) {
    MediaReferenceKind.image => 'images',
    MediaReferenceKind.video => 'videos',
    MediaReferenceKind.audio => 'audio clips',
  };

  static MediaReferenceKind parse(Object? value) =>
      MediaReferenceKind.values.firstWhere(
        (kind) => kind.name == value,
        orElse: () => MediaReferenceKind.image,
      );
}

extension KeyframeRoleValue on KeyframeRole {
  String get label => switch (this) {
    KeyframeRole.start => 'First frame',
    KeyframeRole.middle => 'Middle frame',
    KeyframeRole.end => 'Last frame',
  };

  static KeyframeRole? tryParse(Object? value) {
    for (final role in KeyframeRole.values) {
      if (role.name == value) return role;
    }
    return null;
  }
}

extension VideoModeValue on VideoMode {
  String get wireValue => switch (this) {
    VideoMode.t2v => 't2v',
    VideoMode.i2v => 'i2v',
    VideoMode.v2v => 'v2v',
    VideoMode.draftEnhance => 'draft_enhance',
    VideoMode.upscale => 'upscale',
  };

  String get label => switch (this) {
    VideoMode.t2v => 'Text to video',
    VideoMode.i2v => 'Image to video',
    VideoMode.v2v => 'Video continuation',
    VideoMode.draftEnhance => 'Draft enhance',
    VideoMode.upscale => 'Video upscale',
  };

  String get shortLabel => switch (this) {
    VideoMode.t2v => 'Text',
    VideoMode.i2v => 'Frames',
    VideoMode.v2v => 'Continue',
    VideoMode.draftEnhance => 'Enhance',
    VideoMode.upscale => 'Upscale',
  };

  static VideoMode parse(Object? value) => VideoMode.values.firstWhere(
    (mode) => mode.wireValue == value,
    orElse: () => VideoMode.t2v,
  );
}

class AssetReference {
  const AssetReference({
    required this.kind,
    required this.value,
    required this.label,
    this.contentType,
    this.bytes,
  });

  final String kind;
  final String value;
  final String label;
  final String? contentType;
  final int? bytes;

  /// The asset is retained by the active Clawnsole data store rather than a
  /// short-lived provider URL. Google Drive assets use the `drive` kind.
  bool get isLocal => kind == 'local' || kind == 'drive';

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'value': value,
    'label': label,
    if (contentType != null) 'contentType': contentType,
    if (bytes != null) 'bytes': bytes,
  };

  factory AssetReference.fromJson(Map<String, Object?> json) => AssetReference(
    kind: switch (json['kind']) {
      'local' => 'local',
      'drive' => 'drive',
      _ => 'remote',
    },
    value: json['value'] as String? ?? '',
    label: json['label'] as String? ?? 'Clawnsole asset',
    contentType: json['contentType'] as String?,
    bytes: (json['bytes'] as num?)?.toInt(),
  );
}

class GenerationConfig {
  const GenerationConfig({
    required this.aspectRatio,
    required this.duration,
    required this.resolution,
    required this.generateAudio,
    required this.safetyTolerance,
    required this.draft,
    this.frameRate = 24,
    this.exactTiming = false,
    this.keyframes,
    this.references,
    this.referenceTask = MediaReferenceTask.reference,
    this.sourceLabel,
    this.source,
    this.sourceThumbnailAsset,
    this.upscaleFactor = 2,
    this.upscaleCreativity = 1,
  });

  final String aspectRatio;
  final Object duration;
  final String resolution;
  final bool generateAudio;
  final int safetyTolerance;
  final bool draft;
  final int frameRate;
  final bool exactTiming;
  final List<KeyframeLabel>? keyframes;
  final List<MediaReferenceLabel>? references;
  final MediaReferenceTask referenceTask;
  final String? sourceLabel;
  final AssetReference? source;
  final AssetReference? sourceThumbnailAsset;
  final double upscaleFactor;
  final int upscaleCreativity;

  GenerationConfig copyWith({
    List<KeyframeLabel>? keyframes,
    List<MediaReferenceLabel>? references,
    MediaReferenceTask? referenceTask,
    AssetReference? source,
    AssetReference? sourceThumbnailAsset,
    int? frameRate,
    double? upscaleFactor,
    int? upscaleCreativity,
  }) => GenerationConfig(
    aspectRatio: aspectRatio,
    duration: duration,
    resolution: resolution,
    generateAudio: generateAudio,
    safetyTolerance: safetyTolerance,
    draft: draft,
    frameRate: frameRate ?? this.frameRate,
    exactTiming: exactTiming,
    keyframes: keyframes ?? this.keyframes,
    references: references ?? this.references,
    referenceTask: referenceTask ?? this.referenceTask,
    sourceLabel: sourceLabel,
    source: source ?? this.source,
    sourceThumbnailAsset: sourceThumbnailAsset ?? this.sourceThumbnailAsset,
    upscaleFactor: upscaleFactor ?? this.upscaleFactor,
    upscaleCreativity: upscaleCreativity ?? this.upscaleCreativity,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'aspectRatio': aspectRatio,
    'duration': duration,
    'resolution': resolution,
    'generateAudio': generateAudio,
    'safetyTolerance': safetyTolerance,
    'draft': draft,
    if (frameRate != 24) 'frameRate': frameRate,
    if (exactTiming) 'exactTiming': true,
    if (keyframes != null)
      'keyframes': keyframes!.map((frame) => frame.toJson()).toList(),
    if (references != null)
      'references': references!.map((item) => item.toJson()).toList(),
    if (referenceTask != MediaReferenceTask.reference)
      'referenceTask': referenceTask.name,
    if (sourceLabel != null) 'sourceLabel': sourceLabel,
    if (source != null) 'source': source!.toJson(),
    if (sourceThumbnailAsset != null)
      'sourceThumbnailAsset': sourceThumbnailAsset!.toJson(),
    if (upscaleFactor != 2) 'upscaleFactor': upscaleFactor,
    if (upscaleCreativity != 1) 'upscaleCreativity': upscaleCreativity,
  };

  factory GenerationConfig.fromJson(Map<String, Object?> json) {
    final rawDuration = json['duration'];
    final rawKeyframes = (json['keyframes'] as List<Object?>?)
        ?.whereType<Map<Object?, Object?>>()
        .toList();
    final keyframes = rawKeyframes?.asMap().entries.map((entry) {
      final item = entry.value.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final legacyRole = entry.key == 0
          ? KeyframeRole.start
          : entry.key == rawKeyframes.length - 1
          ? KeyframeRole.end
          : KeyframeRole.middle;
      return KeyframeLabel.fromJson(item, fallbackRole: legacyRole);
    }).toList();
    final references = (json['references'] as List<Object?>?)
        ?.whereType<Map<Object?, Object?>>()
        .map(
          (item) => MediaReferenceLabel.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList();
    return GenerationConfig(
      aspectRatio: json['aspectRatio'] is String
          ? json['aspectRatio']! as String
          : '16:9',
      duration: rawDuration is num
          ? rawDuration.toInt()
          : rawDuration == 'source'
          ? 'source'
          : 'auto',
      resolution: switch (json['resolution']) {
        'sd' ||
        'fhd' ||
        'qhd' ||
        '4k' ||
        'source' => json['resolution']! as String,
        _ => 'hd',
      },
      generateAudio: json['generateAudio'] != false,
      safetyTolerance: (json['safetyTolerance'] as num?)?.toInt() ?? 2,
      draft: json['draft'] == true,
      frameRate: (json['frameRate'] as num?)?.toInt() ?? 24,
      exactTiming: json['exactTiming'] == true,
      keyframes: keyframes,
      references: references,
      referenceTask: MediaReferenceTaskValue.parse(json['referenceTask']),
      sourceLabel: json['sourceLabel'] as String?,
      source: json['source'] is Map<Object?, Object?>
          ? AssetReference.fromJson(
              (json['source']! as Map<Object?, Object?>).map(
                (key, value) => MapEntry(key.toString(), value),
              ),
            )
          : null,
      sourceThumbnailAsset:
          json['sourceThumbnailAsset'] is Map<Object?, Object?>
          ? AssetReference.fromJson(
              (json['sourceThumbnailAsset']! as Map<Object?, Object?>).map(
                (key, value) => MapEntry(key.toString(), value),
              ),
            )
          : null,
      upscaleFactor: (json['upscaleFactor'] as num?)?.toDouble() ?? 2,
      upscaleCreativity: (json['upscaleCreativity'] as num?)?.toInt() == 0
          ? 0
          : 1,
    );
  }
}

class MediaReferenceLabel {
  const MediaReferenceLabel({
    required this.label,
    required this.kind,
    this.source,
    this.thumbnailAsset,
  });

  final String label;
  final MediaReferenceKind kind;
  final AssetReference? source;
  final AssetReference? thumbnailAsset;

  MediaReferenceLabel copyWith({
    AssetReference? source,
    AssetReference? thumbnailAsset,
  }) => MediaReferenceLabel(
    label: label,
    kind: kind,
    source: source ?? this.source,
    thumbnailAsset: thumbnailAsset ?? this.thumbnailAsset,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'label': label,
    'kind': kind.name,
    if (source != null) 'source': source!.toJson(),
    if (thumbnailAsset != null) 'thumbnailAsset': thumbnailAsset!.toJson(),
  };

  factory MediaReferenceLabel.fromJson(Map<String, Object?> json) =>
      MediaReferenceLabel(
        label: json['label'] as String? ?? 'Reference media',
        kind: MediaReferenceKindValue.parse(json['kind']),
        source: json['source'] is Map<Object?, Object?>
            ? AssetReference.fromJson(
                (json['source']! as Map<Object?, Object?>).map(
                  (key, value) => MapEntry(key.toString(), value),
                ),
              )
            : null,
        thumbnailAsset: json['thumbnailAsset'] is Map<Object?, Object?>
            ? AssetReference.fromJson(
                (json['thumbnailAsset']! as Map<Object?, Object?>).map(
                  (key, value) => MapEntry(key.toString(), value),
                ),
              )
            : null,
      );
}

class KeyframeLabel {
  const KeyframeLabel({
    required this.label,
    this.role = KeyframeRole.middle,
    this.seconds,
    this.source,
  });

  final String label;
  final KeyframeRole role;
  final double? seconds;
  final AssetReference? source;

  Map<String, Object?> toJson() => <String, Object?>{
    'label': label,
    'role': role.name,
    if (seconds != null) 'seconds': seconds,
    if (source != null) 'source': source!.toJson(),
  };

  factory KeyframeLabel.fromJson(
    Map<String, Object?> json, {
    KeyframeRole fallbackRole = KeyframeRole.middle,
  }) => KeyframeLabel(
    label: json['label'] as String? ?? 'Reference frame',
    role: KeyframeRoleValue.tryParse(json['role']) ?? fallbackRole,
    seconds: (json['seconds'] as num?)?.toDouble(),
    source: json['source'] is Map<Object?, Object?>
        ? AssetReference.fromJson(
            (json['source']! as Map<Object?, Object?>).map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          )
        : null,
  );
}

class LibraryFolder {
  const LibraryFolder({
    required this.id,
    required this.name,
    required this.createdAt,
    this.parentId,
    this.collection = LibraryCollection.generated,
    this.storage = LibraryStorage.local,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final String? parentId;
  final LibraryCollection collection;
  final LibraryStorage storage;

  LibraryFolder copyWith({
    String? name,
    String? parentId,
    bool clearParent = false,
    LibraryCollection? collection,
    LibraryStorage? storage,
  }) => LibraryFolder(
    id: id,
    name: name ?? this.name,
    createdAt: createdAt,
    parentId: clearParent ? null : parentId ?? this.parentId,
    collection: collection ?? this.collection,
    storage: storage ?? this.storage,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    if (parentId != null) 'parentId': parentId,
    if (collection != LibraryCollection.generated)
      'collection': collection.name,
    if (storage != LibraryStorage.local) 'storage': storage.name,
  };

  factory LibraryFolder.fromJson(Map<String, Object?> json) => LibraryFolder(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ??
        DateTime.now().toUtc(),
    parentId:
        json['parentId'] is String &&
            (json['parentId']! as String).trim().isNotEmpty
        ? (json['parentId']! as String).trim()
        : null,
    collection: LibraryCollection.values.firstWhere(
      (value) => value.name == json['collection'],
      orElse: () => LibraryCollection.generated,
    ),
    storage: LibraryStorage.values.firstWhere(
      (value) => value.name == json['storage'],
      orElse: () => LibraryStorage.local,
    ),
  );
}

class SavedReference {
  const SavedReference({
    required this.id,
    required this.name,
    required this.kind,
    required this.asset,
    this.thumbnailAsset,
    required this.createdAt,
    required this.updatedAt,
    this.folderId,
    this.tags = const <String>[],
    this.favorite = false,
    this.storage = LibraryStorage.local,
  });

  final String id;
  final String name;
  final MediaReferenceKind kind;
  final AssetReference asset;
  final AssetReference? thumbnailAsset;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? folderId;
  final List<String> tags;
  final bool favorite;
  final LibraryStorage storage;

  SavedReference copyWith({
    String? name,
    AssetReference? asset,
    AssetReference? thumbnailAsset,
    DateTime? updatedAt,
    String? folderId,
    bool clearFolder = false,
    List<String>? tags,
    bool? favorite,
    LibraryStorage? storage,
  }) => SavedReference(
    id: id,
    name: name ?? this.name,
    kind: kind,
    asset: asset ?? this.asset,
    thumbnailAsset: thumbnailAsset ?? this.thumbnailAsset,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    folderId: clearFolder ? null : folderId ?? this.folderId,
    tags: tags ?? this.tags,
    favorite: favorite ?? this.favorite,
    storage: storage ?? this.storage,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'kind': kind.name,
    'asset': asset.toJson(),
    if (thumbnailAsset != null) 'thumbnailAsset': thumbnailAsset!.toJson(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    if (folderId != null) 'folderId': folderId,
    if (tags.isNotEmpty) 'tags': tags,
    if (favorite) 'favorite': true,
    if (storage != LibraryStorage.local) 'storage': storage.name,
  };

  factory SavedReference.fromJson(Map<String, Object?> json) {
    final rawAsset = json['asset'];
    return SavedReference(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Saved reference',
      kind: MediaReferenceKindValue.parse(json['kind']),
      asset: AssetReference.fromJson(
        rawAsset is Map<Object?, Object?>
            ? rawAsset.map((key, value) => MapEntry(key.toString(), value))
            : const <String, Object?>{},
      ),
      thumbnailAsset: json['thumbnailAsset'] is Map<Object?, Object?>
          ? AssetReference.fromJson(
              (json['thumbnailAsset']! as Map<Object?, Object?>).map(
                (key, value) => MapEntry(key.toString(), value),
              ),
            )
          : null,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now().toUtc(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now().toUtc(),
      folderId: json['folderId'] as String?,
      tags: (json['tags'] as List<Object?>? ?? const <Object?>[])
          .whereType<String>()
          .where((tag) => tag.trim().isNotEmpty)
          .toList(),
      favorite: json['favorite'] == true,
      storage: LibraryStorage.values.firstWhere(
        (value) => value.name == json['storage'],
        orElse: () => LibraryStorage.local,
      ),
    );
  }
}

class Generation {
  const Generation({
    required this.localId,
    required this.status,
    required this.prompt,
    required this.mode,
    required this.config,
    required this.createdAt,
    required this.updatedAt,
    this.provider = 'bfl',
    this.model = 'flux-3-video',
    this.canonicalModelId,
    this.billingUnit = 'credits',
    this.outputKind = GenerationOutputKind.video,
    this.requestId,
    this.pollingUrl,
    this.progress,
    this.resultUrl,
    this.resultAsset,
    this.thumbnailAsset,
    this.timelineThumbnailAsset,
    this.draftCacheUrl,
    this.deliveryExpiresAt,
    this.deliveryExpired = false,
    this.estimatedCreditsMin,
    this.estimatedCreditsMax,
    this.estimateBasis,
    this.creditsBefore,
    this.creditsAfter,
    this.cost,
    this.quotedCostUsdMin,
    this.quotedCostUsdMax,
    this.realizedCostUsd,
    this.realizedCostSource,
    this.error,
    this.lastCheckedAt,
    this.statusCheckCount = 0,
    this.consecutiveCheckFailures = 0,
    this.lastCheckError,
    this.lastProviderStatusCode,
    this.lastProviderResponse,
    this.lastProviderResponseAt,
    this.folderId,
    this.tags = const <String>[],
    this.favorite = false,
    this.storage = LibraryStorage.local,
  });

  final String localId;
  final String provider;
  final String model;
  final String? canonicalModelId;
  final String billingUnit;
  final GenerationOutputKind outputKind;
  final String? requestId;
  final String? pollingUrl;
  final String status;
  final double? progress;
  final String prompt;
  final VideoMode mode;
  final GenerationConfig config;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? resultUrl;
  final AssetReference? resultAsset;
  final AssetReference? thumbnailAsset;
  final AssetReference? timelineThumbnailAsset;
  final String? draftCacheUrl;
  final DateTime? deliveryExpiresAt;
  final bool deliveryExpired;
  final double? estimatedCreditsMin;
  final double? estimatedCreditsMax;
  final String? estimateBasis;
  final double? creditsBefore;
  final double? creditsAfter;
  final double? cost;
  final double? quotedCostUsdMin;
  final double? quotedCostUsdMax;
  final double? realizedCostUsd;
  final String? realizedCostSource;
  final String? error;
  final DateTime? lastCheckedAt;
  final int statusCheckCount;
  final int consecutiveCheckFailures;
  final String? lastCheckError;
  final int? lastProviderStatusCode;
  final String? lastProviderResponse;
  final DateTime? lastProviderResponseAt;
  final String? folderId;
  final List<String> tags;
  final bool favorite;
  final LibraryStorage storage;

  bool get canCheckStatus => pollingUrl?.trim().isNotEmpty == true;
  bool get isWorking =>
      isGenerationWorkingStatus(status, canPoll: canCheckStatus);
  bool get isReady => normalizeGenerationStatus(status) == 'Ready';
  bool get isImage => outputKind == GenerationOutputKind.image;
  String get displayPrompt {
    if (mode != VideoMode.upscale || prompt.trim().isNotEmpty) return prompt;
    final source = config.sourceLabel?.trim() ?? '';
    final uri = Uri.tryParse(source);
    final label = uri != null && uri.pathSegments.isNotEmpty
        ? uri.pathSegments.last
        : source;
    return 'Upscale ${label.isEmpty ? 'source video' : label}';
  }

  bool get isFailed => isGenerationFailureStatus(status);
  bool get isStatusUnavailable =>
      isWorking && lastCheckError?.trim().isNotEmpty == true;
  bool get hasProviderDetails =>
      error?.trim().isNotEmpty == true ||
      lastCheckError?.trim().isNotEmpty == true ||
      lastProviderResponse?.trim().isNotEmpty == true;
  bool get isLongRunning =>
      isWorking &&
      DateTime.now().toUtc().difference(createdAt) >
          const Duration(minutes: 30);
  String get statusLabel => isStatusUnavailable
      ? 'Status unavailable'
      : generationStatusLabel(status);

  bool isStatusCheckDue(DateTime now) =>
      lastCheckedAt == null ||
      !now.isBefore(
        lastCheckedAt!.add(automaticPollDelay(consecutiveCheckFailures)),
      );

  Generation recoverInterruptedSubmission(DateTime now) {
    if (normalizeGenerationStatus(status) != 'submitting' ||
        canCheckStatus ||
        now.difference(updatedAt) < const Duration(minutes: 2)) {
      return this;
    }
    return copyWith(
      status: 'Error',
      error:
          'Clawnsole was interrupted before it received a provider status URL. Check the provider console before submitting again.',
      updatedAt: now,
    );
  }

  Generation copyWith({
    GenerationConfig? config,
    String? canonicalModelId,
    String? requestId,
    String? pollingUrl,
    String? status,
    double? progress,
    bool clearProgress = false,
    DateTime? updatedAt,
    String? resultUrl,
    AssetReference? resultAsset,
    AssetReference? thumbnailAsset,
    AssetReference? timelineThumbnailAsset,
    String? draftCacheUrl,
    DateTime? deliveryExpiresAt,
    bool? deliveryExpired,
    double? estimatedCreditsMin,
    double? estimatedCreditsMax,
    String? estimateBasis,
    double? creditsBefore,
    double? creditsAfter,
    double? cost,
    bool clearCost = false,
    double? quotedCostUsdMin,
    double? quotedCostUsdMax,
    double? realizedCostUsd,
    String? realizedCostSource,
    String? error,
    bool clearError = false,
    DateTime? lastCheckedAt,
    int? statusCheckCount,
    int? consecutiveCheckFailures,
    String? lastCheckError,
    bool clearLastCheckError = false,
    int? lastProviderStatusCode,
    String? lastProviderResponse,
    DateTime? lastProviderResponseAt,
    String? folderId,
    bool clearFolder = false,
    List<String>? tags,
    bool? favorite,
    LibraryStorage? storage,
  }) => Generation(
    localId: localId,
    provider: provider,
    model: model,
    canonicalModelId: canonicalModelId ?? this.canonicalModelId,
    billingUnit: billingUnit,
    outputKind: outputKind,
    requestId: requestId ?? this.requestId,
    pollingUrl: pollingUrl ?? this.pollingUrl,
    status: status ?? this.status,
    progress: clearProgress ? null : progress ?? this.progress,
    prompt: prompt,
    mode: mode,
    config: config ?? this.config,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    resultUrl: resultUrl ?? this.resultUrl,
    resultAsset: resultAsset ?? this.resultAsset,
    thumbnailAsset: thumbnailAsset ?? this.thumbnailAsset,
    timelineThumbnailAsset:
        timelineThumbnailAsset ?? this.timelineThumbnailAsset,
    draftCacheUrl: draftCacheUrl ?? this.draftCacheUrl,
    deliveryExpiresAt: deliveryExpiresAt ?? this.deliveryExpiresAt,
    deliveryExpired: deliveryExpired ?? this.deliveryExpired,
    estimatedCreditsMin: estimatedCreditsMin ?? this.estimatedCreditsMin,
    estimatedCreditsMax: estimatedCreditsMax ?? this.estimatedCreditsMax,
    estimateBasis: estimateBasis ?? this.estimateBasis,
    creditsBefore: creditsBefore ?? this.creditsBefore,
    creditsAfter: creditsAfter ?? this.creditsAfter,
    cost: clearCost ? null : cost ?? this.cost,
    quotedCostUsdMin: quotedCostUsdMin ?? this.quotedCostUsdMin,
    quotedCostUsdMax: quotedCostUsdMax ?? this.quotedCostUsdMax,
    realizedCostUsd: realizedCostUsd ?? this.realizedCostUsd,
    realizedCostSource: realizedCostSource ?? this.realizedCostSource,
    error: clearError ? null : error ?? this.error,
    lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
    statusCheckCount: statusCheckCount ?? this.statusCheckCount,
    consecutiveCheckFailures:
        consecutiveCheckFailures ?? this.consecutiveCheckFailures,
    lastCheckError: clearLastCheckError
        ? null
        : lastCheckError ?? this.lastCheckError,
    lastProviderStatusCode:
        lastProviderStatusCode ?? this.lastProviderStatusCode,
    lastProviderResponse: lastProviderResponse ?? this.lastProviderResponse,
    lastProviderResponseAt:
        lastProviderResponseAt ?? this.lastProviderResponseAt,
    folderId: clearFolder ? null : folderId ?? this.folderId,
    tags: tags ?? this.tags,
    favorite: favorite ?? this.favorite,
    storage: storage ?? this.storage,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'localId': localId,
    'provider': provider,
    'model': model,
    if (canonicalModelId != null) 'canonicalModelId': canonicalModelId,
    if (billingUnit != 'credits') 'billingUnit': billingUnit,
    if (outputKind != GenerationOutputKind.video) 'outputKind': outputKind.name,
    if (requestId != null) 'requestId': requestId,
    if (pollingUrl != null) 'pollingUrl': pollingUrl,
    'status': status,
    if (progress != null) 'progress': progress,
    'prompt': prompt,
    'mode': mode.wireValue,
    'config': config.toJson(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    if (resultUrl != null) 'resultUrl': resultUrl,
    if (resultAsset != null) 'resultAsset': resultAsset!.toJson(),
    if (thumbnailAsset != null) 'thumbnailAsset': thumbnailAsset!.toJson(),
    if (timelineThumbnailAsset != null)
      'timelineThumbnailAsset': timelineThumbnailAsset!.toJson(),
    if (draftCacheUrl != null) 'draftCacheUrl': draftCacheUrl,
    if (deliveryExpiresAt != null)
      'deliveryExpiresAt': deliveryExpiresAt!.toUtc().toIso8601String(),
    if (deliveryExpired) 'deliveryExpired': true,
    if (estimatedCreditsMin != null) 'estimatedCreditsMin': estimatedCreditsMin,
    if (estimatedCreditsMax != null) 'estimatedCreditsMax': estimatedCreditsMax,
    if (estimateBasis != null) 'estimateBasis': estimateBasis,
    if (creditsBefore != null) 'creditsBefore': creditsBefore,
    if (creditsAfter != null) 'creditsAfter': creditsAfter,
    if (cost != null) 'cost': cost,
    if (quotedCostUsdMin != null) 'quotedCostUsdMin': quotedCostUsdMin,
    if (quotedCostUsdMax != null) 'quotedCostUsdMax': quotedCostUsdMax,
    if (realizedCostUsd != null) 'realizedCostUsd': realizedCostUsd,
    if (realizedCostSource != null) 'realizedCostSource': realizedCostSource,
    if (error != null) 'error': error,
    if (lastCheckedAt != null)
      'lastCheckedAt': lastCheckedAt!.toUtc().toIso8601String(),
    if (statusCheckCount > 0) 'statusCheckCount': statusCheckCount,
    if (consecutiveCheckFailures > 0)
      'consecutiveCheckFailures': consecutiveCheckFailures,
    if (lastCheckError != null) 'lastCheckError': lastCheckError,
    if (lastProviderStatusCode != null)
      'lastProviderStatusCode': lastProviderStatusCode,
    if (lastProviderResponse != null)
      'lastProviderResponse': lastProviderResponse,
    if (lastProviderResponseAt != null)
      'lastProviderResponseAt': lastProviderResponseAt!
          .toUtc()
          .toIso8601String(),
    if (folderId != null) 'folderId': folderId,
    if (tags.isNotEmpty) 'tags': tags,
    if (favorite) 'favorite': true,
    if (storage != LibraryStorage.local) 'storage': storage.name,
  };

  factory Generation.fromJson(Map<String, Object?> json) => Generation(
    localId: json['localId'] as String? ?? '',
    provider: json['provider'] as String? ?? 'bfl',
    model: json['model'] as String? ?? 'flux-3-video',
    canonicalModelId: json['canonicalModelId'] as String?,
    billingUnit: json['billingUnit'] as String? ?? 'credits',
    outputKind: json['outputKind'] == GenerationOutputKind.image.name
        ? GenerationOutputKind.image
        : GenerationOutputKind.video,
    requestId: json['requestId'] as String?,
    pollingUrl: json['pollingUrl'] as String?,
    status: json['status'] as String? ?? 'Error',
    progress: (json['progress'] as num?)?.toDouble(),
    prompt: json['prompt'] as String? ?? '',
    mode: VideoModeValue.parse(json['mode']),
    config: GenerationConfig.fromJson(
      (json['config'] as Map<Object?, Object?>? ?? const {}).map(
        (key, value) => MapEntry(key.toString(), value),
      ),
    ),
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ??
        DateTime.now().toUtc(),
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
        DateTime.now().toUtc(),
    resultUrl: json['resultUrl'] as String?,
    resultAsset: json['resultAsset'] is Map<Object?, Object?>
        ? AssetReference.fromJson(
            (json['resultAsset']! as Map<Object?, Object?>).map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          )
        : null,
    thumbnailAsset: json['thumbnailAsset'] is Map<Object?, Object?>
        ? AssetReference.fromJson(
            (json['thumbnailAsset']! as Map<Object?, Object?>).map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          )
        : null,
    timelineThumbnailAsset:
        json['timelineThumbnailAsset'] is Map<Object?, Object?>
        ? AssetReference.fromJson(
            (json['timelineThumbnailAsset']! as Map<Object?, Object?>).map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          )
        : null,
    draftCacheUrl: json['draftCacheUrl'] as String?,
    deliveryExpiresAt: DateTime.tryParse(
      json['deliveryExpiresAt'] as String? ?? '',
    ),
    deliveryExpired: json['deliveryExpired'] == true,
    estimatedCreditsMin: (json['estimatedCreditsMin'] as num?)?.toDouble(),
    estimatedCreditsMax: (json['estimatedCreditsMax'] as num?)?.toDouble(),
    estimateBasis: json['estimateBasis'] as String?,
    creditsBefore: (json['creditsBefore'] as num?)?.toDouble(),
    creditsAfter: (json['creditsAfter'] as num?)?.toDouble(),
    cost: (json['cost'] as num?)?.toDouble(),
    quotedCostUsdMin: (json['quotedCostUsdMin'] as num?)?.toDouble(),
    quotedCostUsdMax: (json['quotedCostUsdMax'] as num?)?.toDouble(),
    realizedCostUsd: (json['realizedCostUsd'] as num?)?.toDouble(),
    realizedCostSource: json['realizedCostSource'] as String?,
    error: json['error'] as String?,
    lastCheckedAt: DateTime.tryParse(json['lastCheckedAt'] as String? ?? ''),
    statusCheckCount: (json['statusCheckCount'] as num?)?.toInt() ?? 0,
    consecutiveCheckFailures:
        (json['consecutiveCheckFailures'] as num?)?.toInt() ?? 0,
    lastCheckError: json['lastCheckError'] as String?,
    lastProviderStatusCode: (json['lastProviderStatusCode'] as num?)?.toInt(),
    lastProviderResponse: json['lastProviderResponse'] as String?,
    lastProviderResponseAt: DateTime.tryParse(
      json['lastProviderResponseAt'] as String? ?? '',
    ),
    folderId: json['folderId'] as String?,
    tags: (json['tags'] as List<Object?>? ?? const <Object?>[])
        .whereType<String>()
        .where((tag) => tag.trim().isNotEmpty)
        .toList(),
    favorite: json['favorite'] == true,
    storage: LibraryStorage.values.firstWhere(
      (value) => value.name == json['storage'],
      orElse: () => LibraryStorage.local,
    ),
  );
}

class AppPreferences {
  const AppPreferences({
    this.activeSection = AppSection.create,
    this.libraryFilter = LibraryFilter.all,
    this.recentWorkViewMode = GenerationViewMode.full,
    this.libraryViewMode = GenerationViewMode.full,
    this.provider = 'bfl',
    this.model = 'flux-3-video',
    this.defaultStorage = LibraryStorage.local,
    this.libraryStorageFilter = LibraryStorageFilter.all,
    this.referenceStorageFilter = LibraryStorageFilter.all,
    this.generationPlaceholderStyle =
        GenerationPlaceholderStyle.broadcastStatic,
    this.lastLocalGenerationFolderId,
    this.lastDriveGenerationFolderId,
  });

  final AppSection activeSection;
  final LibraryFilter libraryFilter;
  final GenerationViewMode recentWorkViewMode;
  final GenerationViewMode libraryViewMode;
  final String provider;
  final String model;
  final LibraryStorage defaultStorage;
  final LibraryStorageFilter libraryStorageFilter;
  final LibraryStorageFilter referenceStorageFilter;
  final GenerationPlaceholderStyle generationPlaceholderStyle;
  final String? lastLocalGenerationFolderId;
  final String? lastDriveGenerationFolderId;

  AppPreferences copyWith({
    AppSection? activeSection,
    LibraryFilter? libraryFilter,
    GenerationViewMode? recentWorkViewMode,
    GenerationViewMode? libraryViewMode,
    String? provider,
    String? model,
    LibraryStorage? defaultStorage,
    LibraryStorageFilter? libraryStorageFilter,
    LibraryStorageFilter? referenceStorageFilter,
    GenerationPlaceholderStyle? generationPlaceholderStyle,
    String? lastLocalGenerationFolderId,
    bool clearLastLocalGenerationFolder = false,
    String? lastDriveGenerationFolderId,
    bool clearLastDriveGenerationFolder = false,
  }) => AppPreferences(
    activeSection: activeSection ?? this.activeSection,
    libraryFilter: libraryFilter ?? this.libraryFilter,
    recentWorkViewMode: recentWorkViewMode ?? this.recentWorkViewMode,
    libraryViewMode: libraryViewMode ?? this.libraryViewMode,
    provider: provider ?? this.provider,
    model: model ?? this.model,
    defaultStorage: defaultStorage ?? this.defaultStorage,
    libraryStorageFilter: libraryStorageFilter ?? this.libraryStorageFilter,
    referenceStorageFilter:
        referenceStorageFilter ?? this.referenceStorageFilter,
    generationPlaceholderStyle:
        generationPlaceholderStyle ?? this.generationPlaceholderStyle,
    lastLocalGenerationFolderId: clearLastLocalGenerationFolder
        ? null
        : lastLocalGenerationFolderId ?? this.lastLocalGenerationFolderId,
    lastDriveGenerationFolderId: clearLastDriveGenerationFolder
        ? null
        : lastDriveGenerationFolderId ?? this.lastDriveGenerationFolderId,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'activeSection': activeSection.name,
    'libraryFilter': libraryFilter.name,
    'recentWorkViewMode': recentWorkViewMode.name,
    'libraryViewMode': libraryViewMode.name,
    'provider': provider,
    'model': model,
    'defaultStorage': defaultStorage.name,
    'libraryStorageFilter': libraryStorageFilter.name,
    'referenceStorageFilter': referenceStorageFilter.name,
    'generationPlaceholderStyle': generationPlaceholderStyle.name,
    if (lastLocalGenerationFolderId != null)
      'lastLocalGenerationFolderId': lastLocalGenerationFolderId,
    if (lastDriveGenerationFolderId != null)
      'lastDriveGenerationFolderId': lastDriveGenerationFolderId,
  };

  factory AppPreferences.fromJson(Map<String, Object?> json) => AppPreferences(
    activeSection: AppSection.values.firstWhere(
      (value) => value.name == json['activeSection'],
      orElse: () => AppSection.create,
    ),
    libraryFilter: LibraryFilter.values.firstWhere(
      (value) => value.name == json['libraryFilter'],
      orElse: () => LibraryFilter.all,
    ),
    recentWorkViewMode: GenerationViewMode.values.firstWhere(
      (value) => value.name == json['recentWorkViewMode'],
      orElse: () => GenerationViewMode.full,
    ),
    libraryViewMode: GenerationViewMode.values.firstWhere(
      (value) => value.name == json['libraryViewMode'],
      orElse: () => GenerationViewMode.full,
    ),
    provider: json['provider'] as String? ?? 'bfl',
    model: json['model'] as String? ?? 'flux-3-video',
    defaultStorage: LibraryStorage.values.firstWhere(
      (value) => value.name == json['defaultStorage'],
      orElse: () => LibraryStorage.local,
    ),
    libraryStorageFilter: LibraryStorageFilter.values.firstWhere(
      (value) => value.name == json['libraryStorageFilter'],
      orElse: () => LibraryStorageFilter.all,
    ),
    referenceStorageFilter: LibraryStorageFilter.values.firstWhere(
      (value) => value.name == json['referenceStorageFilter'],
      orElse: () => LibraryStorageFilter.all,
    ),
    generationPlaceholderStyle: GenerationPlaceholderStyleValue.parse(
      json['generationPlaceholderStyle'],
    ),
    lastLocalGenerationFolderId: json['lastLocalGenerationFolderId'] as String?,
    lastDriveGenerationFolderId: json['lastDriveGenerationFolderId'] as String?,
  );
}

class StoredData {
  const StoredData({
    this.apiKey = '',
    this.apiKeys = const <String, String>{},
    this.rejectedIosReviewApiKeyId = '',
    this.rejectedIosReviewApiKeyIds = const <String, String>{},
    this.preferences = const AppPreferences(),
    this.generations = const <Generation>[],
    this.folders = const <LibraryFolder>[],
    this.savedReferences = const <SavedReference>[],
    this.preferencesUpdatedAt,
    this.driveFolderName = '',
    this.driveFolderId = '',
  });

  final String apiKey;
  final Map<String, String> apiKeys;
  final String rejectedIosReviewApiKeyId;
  final Map<String, String> rejectedIosReviewApiKeyIds;
  final AppPreferences preferences;
  final List<Generation> generations;
  final List<LibraryFolder> folders;
  final List<SavedReference> savedReferences;
  final DateTime? preferencesUpdatedAt;
  final String driveFolderName;
  final String driveFolderId;

  StoredData copyWith({
    String? apiKey,
    Map<String, String>? apiKeys,
    String? rejectedIosReviewApiKeyId,
    Map<String, String>? rejectedIosReviewApiKeyIds,
    AppPreferences? preferences,
    List<Generation>? generations,
    List<LibraryFolder>? folders,
    List<SavedReference>? savedReferences,
    DateTime? preferencesUpdatedAt,
    bool clearPreferencesUpdatedAt = false,
    String? driveFolderName,
    String? driveFolderId,
  }) => StoredData(
    apiKey: apiKey ?? this.apiKey,
    apiKeys: apiKeys ?? this.apiKeys,
    rejectedIosReviewApiKeyId:
        rejectedIosReviewApiKeyId ?? this.rejectedIosReviewApiKeyId,
    rejectedIosReviewApiKeyIds:
        rejectedIosReviewApiKeyIds ?? this.rejectedIosReviewApiKeyIds,
    preferences: preferences ?? this.preferences,
    generations: generations ?? this.generations,
    folders: folders ?? this.folders,
    savedReferences: savedReferences ?? this.savedReferences,
    preferencesUpdatedAt: clearPreferencesUpdatedAt
        ? null
        : preferencesUpdatedAt ?? this.preferencesUpdatedAt,
    driveFolderName: driveFolderName ?? this.driveFolderName,
    driveFolderId: driveFolderId ?? this.driveFolderId,
  );

  String apiKeyFor(String provider) =>
      apiKeys[provider] ?? (provider == 'bfl' ? apiKey : '');

  String rejectedReviewKeyIdFor(String provider) =>
      rejectedIosReviewApiKeyIds[provider] ??
      (provider == 'bfl' ? rejectedIosReviewApiKeyId : '');

  StoredData withApiKey(String provider, String value) {
    final next = Map<String, String>.from(apiKeys);
    if (value.trim().isEmpty) {
      next.remove(provider);
    } else {
      next[provider] = value.trim();
    }
    return copyWith(
      apiKey: provider == 'bfl' ? value.trim() : apiKey,
      apiKeys: next,
    );
  }

  StoredData withRejectedReviewKeyId(String provider, String value) {
    final next = Map<String, String>.from(rejectedIosReviewApiKeyIds);
    if (value.isEmpty) {
      next.remove(provider);
    } else {
      next[provider] = value;
    }
    return copyWith(
      rejectedIosReviewApiKeyId: provider == 'bfl'
          ? value
          : rejectedIosReviewApiKeyId,
      rejectedIosReviewApiKeyIds: next,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 16,
    'apiKeys': <String, Object?>{
      if (apiKey.isNotEmpty) 'bfl': apiKey,
      ...apiKeys,
    },
    if (rejectedIosReviewApiKeyId.isNotEmpty)
      'rejectedIosReviewApiKeyId': rejectedIosReviewApiKeyId,
    if (rejectedIosReviewApiKeyIds.isNotEmpty)
      'rejectedIosReviewApiKeyIds': rejectedIosReviewApiKeyIds,
    'preferences': preferences.toJson(),
    if (preferencesUpdatedAt != null)
      'preferencesUpdatedAt': preferencesUpdatedAt!.toUtc().toIso8601String(),
    if (driveFolderName.isNotEmpty) 'driveFolderName': driveFolderName,
    if (driveFolderId.isNotEmpty) 'driveFolderId': driveFolderId,
    if (folders.isNotEmpty)
      'folders': folders.map((folder) => folder.toJson()).toList(),
    if (savedReferences.isNotEmpty)
      'savedReferences': savedReferences.map((item) => item.toJson()).toList(),
    'generations': generations.map((item) => item.toJson()).toList(),
  };

  String encode() =>
      '${const JsonEncoder.withIndent('  ').convert(toJson())}\n';

  factory StoredData.fromJson(Map<String, Object?> json) {
    final apiKeys = (json['apiKeys'] as Map<Object?, Object?>? ?? const {}).map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final preferences =
        (json['preferences'] as Map<Object?, Object?>? ?? const {}).map(
          (key, value) => MapEntry(key.toString(), value),
        );
    final rejectedIds =
        (json['rejectedIosReviewApiKeyIds'] as Map<Object?, Object?>? ??
                const {})
            .map((key, value) => MapEntry(key.toString(), value.toString()));
    return StoredData(
      apiKey: apiKeys['bfl'] as String? ?? '',
      apiKeys: apiKeys.map(
        (key, value) => MapEntry(key, value is String ? value : ''),
      )..removeWhere((key, value) => value.isEmpty),
      rejectedIosReviewApiKeyId:
          json['rejectedIosReviewApiKeyId'] as String? ?? '',
      rejectedIosReviewApiKeyIds: rejectedIds,
      preferences: AppPreferences.fromJson(preferences),
      preferencesUpdatedAt: DateTime.tryParse(
        json['preferencesUpdatedAt'] as String? ?? '',
      ),
      driveFolderName: json['driveFolderName'] as String? ?? '',
      driveFolderId: json['driveFolderId'] as String? ?? '',
      folders: (json['folders'] as List<Object?>? ?? const <Object?>[])
          .whereType<Map<Object?, Object?>>()
          .map(
            (item) => LibraryFolder.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .where((folder) => folder.id.isNotEmpty && folder.name.isNotEmpty)
          .toList(),
      savedReferences:
          (json['savedReferences'] as List<Object?>? ?? const <Object?>[])
              .whereType<Map<Object?, Object?>>()
              .map(
                (item) => SavedReference.fromJson(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ),
              )
              .where(
                (item) =>
                    item.id.isNotEmpty &&
                    item.name.isNotEmpty &&
                    item.asset.value.isNotEmpty,
              )
              .toList(),
      generations: (json['generations'] as List<Object?>? ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map(
            (item) => Generation.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .where((item) => item.localId.isNotEmpty)
          .toList(),
    );
  }

  factory StoredData.decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<Object?, Object?>) return const StoredData();
    return StoredData.fromJson(
      decoded.map((key, value) => MapEntry(key.toString(), value)),
    );
  }
}

class StorageStats {
  const StorageStats({
    required this.path,
    required this.bytes,
    required this.records,
    this.assetBytes = 0,
    this.assets = 0,
    this.lastUpdated,
  });

  final String path;
  final int bytes;
  final int records;
  final int assetBytes;
  final int assets;
  final DateTime? lastUpdated;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'bytes': bytes,
    'records': records,
    'assetBytes': assetBytes,
    'assets': assets,
    if (lastUpdated != null)
      'lastUpdated': lastUpdated!.toUtc().toIso8601String(),
  };

  factory StorageStats.fromJson(Map<String, Object?> json) => StorageStats(
    path: json['path'] as String? ?? '',
    bytes: (json['bytes'] as num?)?.toInt() ?? 0,
    records: (json['records'] as num?)?.toInt() ?? 0,
    assetBytes: (json['assetBytes'] as num?)?.toInt() ?? 0,
    assets: (json['assets'] as num?)?.toInt() ?? 0,
    lastUpdated: DateTime.tryParse(json['lastUpdated'] as String? ?? ''),
  );
}

class LocalSnapshot {
  const LocalSnapshot({
    required this.generations,
    required this.preferences,
    required this.hasApiKey,
    required this.storage,
    this.connectedProviders = const <String>{},
    this.availableProviders = const <String>{},
    this.folders = const <LibraryFolder>[],
    this.savedReferences = const <SavedReference>[],
  });

  final List<Generation> generations;
  final AppPreferences preferences;
  final bool hasApiKey;
  final StorageStats storage;
  final Set<String> connectedProviders;
  final Set<String> availableProviders;
  final List<LibraryFolder> folders;
  final List<SavedReference> savedReferences;

  bool hasApiKeyFor(String provider) =>
      connectedProviders.contains(provider) || (provider == 'bfl' && hasApiKey);

  Map<String, Object?> toJson() => <String, Object?>{
    'generations': generations.map((item) => item.toJson()).toList(),
    'preferences': preferences.toJson(),
    'hasBflApiKey': hasApiKey,
    'connectedProviders': connectedProviders.toList()..sort(),
    'availableProviders': availableProviders.toList()..sort(),
    'folders': folders.map((folder) => folder.toJson()).toList(),
    'savedReferences': savedReferences.map((item) => item.toJson()).toList(),
    'storage': storage.toJson(),
  };

  factory LocalSnapshot.fromJson(Map<String, Object?> json) => LocalSnapshot(
    generations: (json['generations'] as List<Object?>? ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map(
          (item) => Generation.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList(),
    preferences: AppPreferences.fromJson(
      (json['preferences'] as Map<Object?, Object?>? ?? const {}).map(
        (key, value) => MapEntry(key.toString(), value),
      ),
    ),
    hasApiKey: json['hasBflApiKey'] == true,
    connectedProviders:
        (json['connectedProviders'] as List<Object?>? ?? const <Object?>[])
            .whereType<String>()
            .toSet(),
    availableProviders:
        (json['availableProviders'] as List<Object?>? ?? const <Object?>[])
            .whereType<String>()
            .toSet(),
    folders: (json['folders'] as List<Object?>? ?? const <Object?>[])
        .whereType<Map<Object?, Object?>>()
        .map(
          (item) => LibraryFolder.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList(),
    savedReferences:
        (json['savedReferences'] as List<Object?>? ?? const <Object?>[])
            .whereType<Map<Object?, Object?>>()
            .map(
              (item) => SavedReference.fromJson(
                item.map((key, value) => MapEntry(key.toString(), value)),
              ),
            )
            .toList(),
    storage: StorageStats.fromJson(
      (json['storage'] as Map<Object?, Object?>? ?? const {}).map(
        (key, value) => MapEntry(key.toString(), value),
      ),
    ),
  );
}

class CreditEstimate {
  const CreditEstimate({
    required this.minimum,
    required this.maximum,
    required this.basis,
  });

  final double minimum;
  final double maximum;
  final String basis;
}

class VideoSourceMetadata {
  const VideoSourceMetadata({
    required this.width,
    required this.height,
    required this.durationSeconds,
  });

  final int width;
  final int height;
  final double durationSeconds;

  bool get isUsable => width > 0 && height > 0 && durationSeconds > 0;

  String get signature =>
      '$width×$height@${durationSeconds.toStringAsFixed(3)}';
}

class ProviderAccountStatus {
  const ProviderAccountStatus({
    required this.provider,
    this.balance,
    this.currency = 'USD',
    this.balanceLabel,
  });

  final String provider;
  final double? balance;
  final String currency;
  final String? balanceLabel;

  Map<String, Object?> toJson() => <String, Object?>{
    'provider': provider,
    if (balance != null) 'balance': balance,
    'currency': currency,
    if (balanceLabel != null) 'balanceLabel': balanceLabel,
  };

  factory ProviderAccountStatus.fromJson(Map<String, Object?> json) =>
      ProviderAccountStatus(
        provider: json['provider'] as String? ?? 'bfl',
        balance: (json['balance'] as num?)?.toDouble(),
        currency: json['currency'] as String? ?? 'USD',
        balanceLabel: json['balanceLabel'] as String?,
      );
}

class ProviderModelPrice {
  const ProviderModelPrice({
    required this.provider,
    required this.model,
    required this.label,
    required this.usdPerSecond,
    required this.modes,
    this.canonicalModelId,
    this.referenceUsdPerSecond,
    this.source = 'published',
    this.createReady = true,
    this.minDuration,
    this.maxDuration,
    this.durationStep = 1,
    this.durationPrices = const <int, double>{},
    this.reference10SecondUsd,
    this.pricingUnit = 'per-second',
  });

  final String provider;
  final String model;
  final String label;
  final String? canonicalModelId;
  final double usdPerSecond;
  final double? referenceUsdPerSecond;
  final List<VideoMode> modes;
  final String source;
  final bool createReady;
  final int? minDuration;
  final int? maxDuration;
  final int durationStep;
  final Map<int, double> durationPrices;
  final double? reference10SecondUsd;
  final String pricingUnit;

  String get canonicalId => canonicalModelId ?? model;

  bool supportsDuration(int seconds) {
    if (minDuration == null || maxDuration == null) return true;
    return seconds >= minDuration! &&
        seconds <= maxDuration! &&
        (seconds - minDuration!) % durationStep == 0;
  }

  bool hasPriceFor(int seconds) =>
      supportsDuration(seconds) &&
      (durationPrices.containsKey(seconds) || pricingUnit == 'per-second');

  double priceFor(int seconds, {bool withReferences = false}) {
    if (withReferences && seconds == 10 && reference10SecondUsd != null) {
      return reference10SecondUsd!;
    }
    final exact = durationPrices[seconds];
    if (exact != null) return exact;
    return (withReferences
            ? referenceUsdPerSecond ?? usdPerSecond
            : usdPerSecond) *
        seconds;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'provider': provider,
    'model': model,
    'label': label,
    if (canonicalModelId != null) 'canonicalModelId': canonicalModelId,
    'usdPerSecond': usdPerSecond,
    if (referenceUsdPerSecond != null)
      'referenceUsdPerSecond': referenceUsdPerSecond,
    'modes': modes.map((mode) => mode.wireValue).toList(),
    'source': source,
    'createReady': createReady,
    if (minDuration != null) 'minDuration': minDuration,
    if (maxDuration != null) 'maxDuration': maxDuration,
    'durationStep': durationStep,
    if (durationPrices.isNotEmpty)
      'durationPrices': durationPrices.map(
        (seconds, price) => MapEntry(seconds.toString(), price),
      ),
    if (reference10SecondUsd != null)
      'reference10SecondUsd': reference10SecondUsd,
    'pricingUnit': pricingUnit,
  };

  factory ProviderModelPrice.fromJson(
    Map<String, Object?> json,
  ) => ProviderModelPrice(
    provider: json['provider'] as String? ?? '',
    model: json['model'] as String? ?? '',
    label: json['label'] as String? ?? json['model'] as String? ?? '',
    canonicalModelId: json['canonicalModelId'] as String?,
    usdPerSecond: (json['usdPerSecond'] as num?)?.toDouble() ?? 0,
    referenceUsdPerSecond: (json['referenceUsdPerSecond'] as num?)?.toDouble(),
    modes: (json['modes'] as List<Object?>? ?? const <Object?>[])
        .map(VideoModeValue.parse)
        .toList(),
    source: json['source'] as String? ?? 'published',
    createReady: json['createReady'] != false,
    minDuration: (json['minDuration'] as num?)?.toInt(),
    maxDuration: (json['maxDuration'] as num?)?.toInt(),
    durationStep: (json['durationStep'] as num?)?.toInt() ?? 1,
    durationPrices:
        (json['durationPrices'] as Map<Object?, Object?>? ?? const {}).map(
          (seconds, price) => MapEntry(
            int.tryParse(seconds.toString()) ?? 0,
            (price as num).toDouble(),
          ),
        )..remove(0),
    reference10SecondUsd: (json['reference10SecondUsd'] as num?)?.toDouble(),
    pricingUnit: json['pricingUnit'] as String? ?? 'per-second',
  );
}

class CostEstimate {
  const CostEstimate({
    required this.minimumUsd,
    required this.maximumUsd,
    required this.basis,
    this.providerUnitsMinimum,
    this.providerUnitsMaximum,
    this.providerUnitLabel,
    this.rateUsd,
    this.rateUnit,
    this.calculation,
  });

  final double minimumUsd;
  final double maximumUsd;
  final String basis;
  final double? providerUnitsMinimum;
  final double? providerUnitsMaximum;
  final String? providerUnitLabel;
  final double? rateUsd;
  final String? rateUnit;
  final String? calculation;

  CostEstimate withPricingContext(CostEstimate fallback) => CostEstimate(
    minimumUsd: minimumUsd,
    maximumUsd: maximumUsd,
    basis: basis,
    providerUnitsMinimum: providerUnitsMinimum,
    providerUnitsMaximum: providerUnitsMaximum,
    providerUnitLabel: providerUnitLabel,
    rateUsd: rateUsd ?? fallback.rateUsd,
    rateUnit: rateUnit ?? fallback.rateUnit,
    calculation: calculation ?? fallback.calculation,
  );
}

class GenerationSubmission {
  const GenerationSubmission({required this.record, required this.input});

  final Generation record;
  final Map<String, Object?> input;
}
