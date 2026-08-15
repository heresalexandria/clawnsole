import 'dart:convert';

import 'generation_status.dart';

enum AppSection { create, library, settings }

enum LibraryFilter { all, working, ready, failed }

enum VideoMode { t2v, i2v, v2v, draftEnhance }

extension VideoModeValue on VideoMode {
  String get wireValue => switch (this) {
    VideoMode.t2v => 't2v',
    VideoMode.i2v => 'i2v',
    VideoMode.v2v => 'v2v',
    VideoMode.draftEnhance => 'draft_enhance',
  };

  String get label => switch (this) {
    VideoMode.t2v => 'Text to video',
    VideoMode.i2v => 'Image to video',
    VideoMode.v2v => 'Video continuation',
    VideoMode.draftEnhance => 'Draft enhance',
  };

  String get shortLabel => switch (this) {
    VideoMode.t2v => 'Text',
    VideoMode.i2v => 'Frames',
    VideoMode.v2v => 'Continue',
    VideoMode.draftEnhance => 'Enhance',
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

  bool get isLocal => kind == 'local';

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'value': value,
    'label': label,
    if (contentType != null) 'contentType': contentType,
    if (bytes != null) 'bytes': bytes,
  };

  factory AssetReference.fromJson(Map<String, Object?> json) => AssetReference(
    kind: json['kind'] == 'local' ? 'local' : 'remote',
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
    this.exactTiming = false,
    this.keyframes,
    this.sourceLabel,
    this.source,
  });

  final String aspectRatio;
  final Object duration;
  final String resolution;
  final bool generateAudio;
  final int safetyTolerance;
  final bool draft;
  final bool exactTiming;
  final List<KeyframeLabel>? keyframes;
  final String? sourceLabel;
  final AssetReference? source;

  GenerationConfig copyWith({
    List<KeyframeLabel>? keyframes,
    AssetReference? source,
  }) => GenerationConfig(
    aspectRatio: aspectRatio,
    duration: duration,
    resolution: resolution,
    generateAudio: generateAudio,
    safetyTolerance: safetyTolerance,
    draft: draft,
    exactTiming: exactTiming,
    keyframes: keyframes ?? this.keyframes,
    sourceLabel: sourceLabel,
    source: source ?? this.source,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'aspectRatio': aspectRatio,
    'duration': duration,
    'resolution': resolution,
    'generateAudio': generateAudio,
    'safetyTolerance': safetyTolerance,
    'draft': draft,
    if (exactTiming) 'exactTiming': true,
    if (keyframes != null)
      'keyframes': keyframes!.map((frame) => frame.toJson()).toList(),
    if (sourceLabel != null) 'sourceLabel': sourceLabel,
    if (source != null) 'source': source!.toJson(),
  };

  factory GenerationConfig.fromJson(Map<String, Object?> json) {
    final rawDuration = json['duration'];
    return GenerationConfig(
      aspectRatio: json['aspectRatio'] is String
          ? json['aspectRatio']! as String
          : '16:9',
      duration: rawDuration is num ? rawDuration.toInt() : 'auto',
      resolution: json['resolution'] == 'fhd' ? 'fhd' : 'hd',
      generateAudio: json['generateAudio'] != false,
      safetyTolerance: (json['safetyTolerance'] as num?)?.toInt() ?? 2,
      draft: json['draft'] == true,
      exactTiming: json['exactTiming'] == true,
      keyframes: (json['keyframes'] as List<Object?>?)
          ?.whereType<Map<Object?, Object?>>()
          .map(
            (item) => KeyframeLabel.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .toList(),
      sourceLabel: json['sourceLabel'] as String?,
      source: json['source'] is Map<Object?, Object?>
          ? AssetReference.fromJson(
              (json['source']! as Map<Object?, Object?>).map(
                (key, value) => MapEntry(key.toString(), value),
              ),
            )
          : null,
    );
  }
}

class KeyframeLabel {
  const KeyframeLabel({required this.label, this.seconds, this.source});

  final String label;
  final double? seconds;
  final AssetReference? source;

  Map<String, Object?> toJson() => <String, Object?>{
    'label': label,
    if (seconds != null) 'seconds': seconds,
    if (source != null) 'source': source!.toJson(),
  };

  factory KeyframeLabel.fromJson(Map<String, Object?> json) => KeyframeLabel(
    label: json['label'] as String? ?? 'Reference frame',
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
    this.requestId,
    this.pollingUrl,
    this.progress,
    this.resultUrl,
    this.resultAsset,
    this.draftCacheUrl,
    this.deliveryExpiresAt,
    this.deliveryExpired = false,
    this.estimatedCreditsMin,
    this.estimatedCreditsMax,
    this.estimateBasis,
    this.creditsBefore,
    this.creditsAfter,
    this.cost,
    this.error,
    this.lastCheckedAt,
    this.statusCheckCount = 0,
    this.consecutiveCheckFailures = 0,
    this.lastCheckError,
  });

  final String localId;
  final String provider;
  final String model;
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
  final String? draftCacheUrl;
  final DateTime? deliveryExpiresAt;
  final bool deliveryExpired;
  final double? estimatedCreditsMin;
  final double? estimatedCreditsMax;
  final String? estimateBasis;
  final double? creditsBefore;
  final double? creditsAfter;
  final double? cost;
  final String? error;
  final DateTime? lastCheckedAt;
  final int statusCheckCount;
  final int consecutiveCheckFailures;
  final String? lastCheckError;

  bool get canCheckStatus => pollingUrl?.trim().isNotEmpty == true;
  bool get isWorking =>
      isGenerationWorkingStatus(status, canPoll: canCheckStatus);
  bool get isReady => normalizeGenerationStatus(status) == 'Ready';
  bool get isFailed => isGenerationFailureStatus(status);
  bool get isLongRunning =>
      isWorking &&
      DateTime.now().toUtc().difference(createdAt) >
          const Duration(minutes: 30);
  String get statusLabel => generationStatusLabel(status);

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
          'Clawnsole was interrupted before it received a provider status URL. Check the BFL dashboard before submitting again.',
      updatedAt: now,
    );
  }

  Generation copyWith({
    GenerationConfig? config,
    String? requestId,
    String? pollingUrl,
    String? status,
    double? progress,
    bool clearProgress = false,
    DateTime? updatedAt,
    String? resultUrl,
    AssetReference? resultAsset,
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
    String? error,
    bool clearError = false,
    DateTime? lastCheckedAt,
    int? statusCheckCount,
    int? consecutiveCheckFailures,
    String? lastCheckError,
    bool clearLastCheckError = false,
  }) => Generation(
    localId: localId,
    provider: provider,
    model: model,
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
    draftCacheUrl: draftCacheUrl ?? this.draftCacheUrl,
    deliveryExpiresAt: deliveryExpiresAt ?? this.deliveryExpiresAt,
    deliveryExpired: deliveryExpired ?? this.deliveryExpired,
    estimatedCreditsMin: estimatedCreditsMin ?? this.estimatedCreditsMin,
    estimatedCreditsMax: estimatedCreditsMax ?? this.estimatedCreditsMax,
    estimateBasis: estimateBasis ?? this.estimateBasis,
    creditsBefore: creditsBefore ?? this.creditsBefore,
    creditsAfter: creditsAfter ?? this.creditsAfter,
    cost: clearCost ? null : cost ?? this.cost,
    error: clearError ? null : error ?? this.error,
    lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
    statusCheckCount: statusCheckCount ?? this.statusCheckCount,
    consecutiveCheckFailures:
        consecutiveCheckFailures ?? this.consecutiveCheckFailures,
    lastCheckError: clearLastCheckError
        ? null
        : lastCheckError ?? this.lastCheckError,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'localId': localId,
    'provider': provider,
    'model': model,
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
    if (error != null) 'error': error,
    if (lastCheckedAt != null)
      'lastCheckedAt': lastCheckedAt!.toUtc().toIso8601String(),
    if (statusCheckCount > 0) 'statusCheckCount': statusCheckCount,
    if (consecutiveCheckFailures > 0)
      'consecutiveCheckFailures': consecutiveCheckFailures,
    if (lastCheckError != null) 'lastCheckError': lastCheckError,
  };

  factory Generation.fromJson(Map<String, Object?> json) => Generation(
    localId: json['localId'] as String? ?? '',
    provider: json['provider'] as String? ?? 'bfl',
    model: json['model'] as String? ?? 'flux-3-video',
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
    error: json['error'] as String?,
    lastCheckedAt: DateTime.tryParse(json['lastCheckedAt'] as String? ?? ''),
    statusCheckCount: (json['statusCheckCount'] as num?)?.toInt() ?? 0,
    consecutiveCheckFailures:
        (json['consecutiveCheckFailures'] as num?)?.toInt() ?? 0,
    lastCheckError: json['lastCheckError'] as String?,
  );
}

class AppPreferences {
  const AppPreferences({
    this.activeSection = AppSection.create,
    this.libraryFilter = LibraryFilter.all,
  });

  final AppSection activeSection;
  final LibraryFilter libraryFilter;

  Map<String, Object?> toJson() => <String, Object?>{
    'activeSection': activeSection.name,
    'libraryFilter': libraryFilter.name,
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
  );
}

class StoredData {
  const StoredData({
    this.apiKey = '',
    this.preferences = const AppPreferences(),
    this.generations = const <Generation>[],
  });

  final String apiKey;
  final AppPreferences preferences;
  final List<Generation> generations;

  StoredData copyWith({
    String? apiKey,
    AppPreferences? preferences,
    List<Generation>? generations,
  }) => StoredData(
    apiKey: apiKey ?? this.apiKey,
    preferences: preferences ?? this.preferences,
    generations: generations ?? this.generations,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 3,
    'apiKeys': <String, Object?>{if (apiKey.isNotEmpty) 'bfl': apiKey},
    'preferences': preferences.toJson(),
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
    return StoredData(
      apiKey: apiKeys['bfl'] as String? ?? '',
      preferences: AppPreferences.fromJson(preferences),
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
  });

  final List<Generation> generations;
  final AppPreferences preferences;
  final bool hasApiKey;
  final StorageStats storage;

  Map<String, Object?> toJson() => <String, Object?>{
    'generations': generations.map((item) => item.toJson()).toList(),
    'preferences': preferences.toJson(),
    'hasBflApiKey': hasApiKey,
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

class GenerationSubmission {
  const GenerationSubmission({required this.record, required this.input});

  final Generation record;
  final Map<String, Object?> input;
}
