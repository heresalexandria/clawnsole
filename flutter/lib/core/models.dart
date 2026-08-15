import 'dart:convert';

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

class GenerationConfig {
  const GenerationConfig({
    required this.aspectRatio,
    required this.duration,
    required this.resolution,
    required this.generateAudio,
    required this.safetyTolerance,
    required this.draft,
    this.keyframes,
    this.sourceLabel,
  });

  final String aspectRatio;
  final Object duration;
  final String resolution;
  final bool generateAudio;
  final int safetyTolerance;
  final bool draft;
  final List<KeyframeLabel>? keyframes;
  final String? sourceLabel;

  Map<String, Object?> toJson() => <String, Object?>{
    'aspectRatio': aspectRatio,
    'duration': duration,
    'resolution': resolution,
    'generateAudio': generateAudio,
    'safetyTolerance': safetyTolerance,
    'draft': draft,
    if (keyframes != null)
      'keyframes': keyframes!.map((frame) => frame.toJson()).toList(),
    if (sourceLabel != null) 'sourceLabel': sourceLabel,
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
      keyframes: (json['keyframes'] as List<Object?>?)
          ?.whereType<Map<Object?, Object?>>()
          .map(
            (item) => KeyframeLabel.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .toList(),
      sourceLabel: json['sourceLabel'] as String?,
    );
  }
}

class KeyframeLabel {
  const KeyframeLabel({required this.label, this.seconds});

  final String label;
  final double? seconds;

  Map<String, Object?> toJson() => <String, Object?>{
    'label': label,
    if (seconds != null) 'seconds': seconds,
  };

  factory KeyframeLabel.fromJson(Map<String, Object?> json) => KeyframeLabel(
    label: json['label'] as String? ?? 'Reference frame',
    seconds: (json['seconds'] as num?)?.toDouble(),
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

  bool get isWorking => status == 'submitting' || status == 'Pending';
  bool get isReady => status == 'Ready';
  bool get isFailed => const <String>{
    'Error',
    'Failed',
    'Request Moderated',
    'Content Moderated',
  }.contains(status);

  Generation copyWith({
    String? requestId,
    String? pollingUrl,
    String? status,
    double? progress,
    bool clearProgress = false,
    DateTime? updatedAt,
    String? resultUrl,
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
    config: config,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    resultUrl: resultUrl ?? this.resultUrl,
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
    'schemaVersion': 1,
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
    this.lastUpdated,
  });

  final String path;
  final int bytes;
  final int records;
  final DateTime? lastUpdated;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'bytes': bytes,
    'records': records,
    if (lastUpdated != null)
      'lastUpdated': lastUpdated!.toUtc().toIso8601String(),
  };

  factory StorageStats.fromJson(Map<String, Object?> json) => StorageStats(
    path: json['path'] as String? ?? '',
    bytes: (json['bytes'] as num?)?.toInt() ?? 0,
    records: (json['records'] as num?)?.toInt() ?? 0,
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
