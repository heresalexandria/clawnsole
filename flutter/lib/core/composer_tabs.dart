/// Persisted composer workspaces ("tabs") on the Create screen.
///
/// A tab is one independent draft of the Direction prompt plus every
/// generation setting. Records stay compact on purpose: they carry text,
/// scalars, and ids only. Retained media is referenced by compact asset/library ids. Older tabs
/// re-hydrate media through [ComposerTabRecord.sourceGenerationId].
library;

import 'dart:convert';
import 'aesthetic_reference.dart';

/// The maximum number of characters a derived tab title keeps.
const int composerTabTitleLength = 28;

/// The label for a tab whose prompt is still empty and has no custom title.
const String composerTabUntitled = 'Untitled';

/// The label shown for a tab: the custom [title] when set, else the first
/// words of [prompt], else [composerTabUntitled].
String composerTabTitle(String? title, String prompt) {
  final custom = title?.trim() ?? '';
  if (custom.isNotEmpty) return custom;
  final firstLine = prompt
      .trim()
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => '');
  final collapsed = firstLine.replaceAll(RegExp(r'\s+'), ' ');
  if (collapsed.isEmpty) return composerTabUntitled;
  if (collapsed.length <= composerTabTitleLength) return collapsed;
  final cut = collapsed.substring(0, composerTabTitleLength);
  // Cut at a word boundary unless that would drop most of the label.
  final endsOnWord = collapsed[composerTabTitleLength] == ' ';
  final lastSpace = cut.lastIndexOf(' ');
  final trimmed = !endsOnWord && lastSpace >= composerTabTitleLength ~/ 2
      ? cut.substring(0, lastSpace)
      : cut;
  return '${trimmed.trimRight()}…';
}

/// One persisted composer tab.
class ComposerTabRecord {
  const ComposerTabRecord({
    required this.id,
    this.title,
    this.prompt = '',
    this.screenplayMode = false,
    this.aestheticReferenceId,
    this.mediaConfig,
    this.mode,
    this.screenplayLinkedCharacters = const [],
    this.screenplayReferenceNames = const {},
    this.screenplayCharacterAliases = const {},
    this.characterMappings = const {},
    this.providerId,
    this.modelId,
    this.aspectRatio = '16:9',
    this.autoDuration = false,
    this.durationSeconds = 8,
    this.frameRate = 2,
    this.resolution = 'hd',
    this.generateAudio = true,
    this.safetyTolerance = 2,
    this.draft = false,
    this.exactTiming = false,
    this.referenceTask = 'reference',
    this.upscale = false,
    this.upscaleFactor = 2,
    this.upscaleCreativity = 1,
    this.seed,
    this.videoUrl = '',
    this.draftUrl = '',
    this.sourceGenerationId,
    this.rewriteSummary,
    this.localFolderId,
    this.driveFolderId,
    this.createdAt,
    this.updatedAt,
  });

  final String id;

  /// A custom name typed by the director; null derives the label from the
  /// prompt via [composerTabTitle].
  final String? title;
  final String prompt;
  final bool screenplayMode;
  final String? aestheticReferenceId;
  final Map<String, Object?>? mediaConfig;
  final String? mode;
  final List<String> screenplayLinkedCharacters;

  /// Saved reference ids and their authoring names, never media or secrets.
  final Map<String, String> screenplayReferenceNames;
  final Map<String, String> screenplayCharacterAliases;

  /// Cast lines kept out of the editable prompt: cast name to the prompt
  /// names of the media references playing that character. Appended to the
  /// prompt at submission (schema 6).
  final Map<String, List<String>> characterMappings;
  final String? providerId;
  final String? modelId;
  final String aspectRatio;
  final bool autoDuration;
  final int durationSeconds;
  final int frameRate;
  final String resolution;
  final bool generateAudio;
  final int safetyTolerance;
  final bool draft;
  final bool exactTiming;

  /// `MediaReferenceTask.name` — kept as text so this module stays free of
  /// the app model imports.
  final String referenceTask;
  final bool upscale;
  final double upscaleFactor;
  final int upscaleCreativity;
  final int? seed;

  /// Hosted source URLs survive a restart; picked assets do not.
  final String videoUrl;
  final String draftUrl;

  /// The generation this tab was seeded from (Reuse, AI Rewrite, or the
  /// startup carry-over). Its retained keyframes, references, and source
  /// video are re-hydrated from the generation record on launch.
  final String? sourceGenerationId;

  /// The one-sentence change summary returned by AI Rewrite, when this tab
  /// was created by it.
  final String? rewriteSummary;
  final String? localFolderId;
  final String? driveFolderId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get label => composerTabTitle(title, prompt);

  /// Nothing worth showing on another device: no text, no name, and no
  /// retained media. Such tabs stay out of the "on other devices" list.
  bool get isBlankDraft =>
      (title?.trim().isEmpty ?? true) &&
      prompt.trim().isEmpty &&
      videoUrl.trim().isEmpty &&
      draftUrl.trim().isEmpty &&
      !_holdsRetainedAssets(mediaConfig);

  ComposerTabRecord copyWith({
    String? id,
    String? title,
    bool clearTitle = false,
    String? prompt,
    bool? screenplayMode,
    String? aestheticReferenceId,
    Map<String, Object?>? mediaConfig,
    String? mode,
    bool clearAestheticReferenceId = false,
    List<String>? screenplayLinkedCharacters,
    Map<String, String>? screenplayReferenceNames,
    Map<String, String>? screenplayCharacterAliases,
    Map<String, List<String>>? characterMappings,
    String? providerId,
    String? modelId,
    String? aspectRatio,
    bool? autoDuration,
    int? durationSeconds,
    int? frameRate,
    String? resolution,
    bool? generateAudio,
    int? safetyTolerance,
    bool? draft,
    bool? exactTiming,
    String? referenceTask,
    bool? upscale,
    double? upscaleFactor,
    int? upscaleCreativity,
    int? seed,
    bool clearSeed = false,
    String? videoUrl,
    String? draftUrl,
    String? sourceGenerationId,
    bool clearSourceGenerationId = false,
    String? rewriteSummary,
    bool clearRewriteSummary = false,
    String? localFolderId,
    bool clearLocalFolderId = false,
    String? driveFolderId,
    bool clearDriveFolderId = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => ComposerTabRecord(
    id: id ?? this.id,
    mediaConfig: mediaConfig ?? this.mediaConfig,
    mode: mode ?? this.mode,
    title: clearTitle ? null : title ?? this.title,
    prompt: prompt ?? this.prompt,
    screenplayMode: screenplayMode ?? this.screenplayMode,
    aestheticReferenceId: clearAestheticReferenceId
        ? null
        : aestheticReferenceId ?? this.aestheticReferenceId,
    screenplayLinkedCharacters:
        screenplayLinkedCharacters ?? this.screenplayLinkedCharacters,
    screenplayReferenceNames:
        screenplayReferenceNames ?? this.screenplayReferenceNames,
    screenplayCharacterAliases:
        screenplayCharacterAliases ?? this.screenplayCharacterAliases,
    characterMappings: characterMappings ?? this.characterMappings,
    providerId: providerId ?? this.providerId,
    modelId: modelId ?? this.modelId,
    aspectRatio: aspectRatio ?? this.aspectRatio,
    autoDuration: autoDuration ?? this.autoDuration,
    durationSeconds: durationSeconds ?? this.durationSeconds,
    frameRate: frameRate ?? this.frameRate,
    resolution: resolution ?? this.resolution,
    generateAudio: generateAudio ?? this.generateAudio,
    safetyTolerance: safetyTolerance ?? this.safetyTolerance,
    draft: draft ?? this.draft,
    exactTiming: exactTiming ?? this.exactTiming,
    referenceTask: referenceTask ?? this.referenceTask,
    upscale: upscale ?? this.upscale,
    upscaleFactor: upscaleFactor ?? this.upscaleFactor,
    upscaleCreativity: upscaleCreativity ?? this.upscaleCreativity,
    seed: clearSeed ? null : seed ?? this.seed,
    videoUrl: videoUrl ?? this.videoUrl,
    draftUrl: draftUrl ?? this.draftUrl,
    sourceGenerationId: clearSourceGenerationId
        ? null
        : sourceGenerationId ?? this.sourceGenerationId,
    rewriteSummary: clearRewriteSummary
        ? null
        : rewriteSummary ?? this.rewriteSummary,
    localFolderId: clearLocalFolderId
        ? null
        : localFolderId ?? this.localFolderId,
    driveFolderId: clearDriveFolderId
        ? null
        : driveFolderId ?? this.driveFolderId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    if (mediaConfig != null) 'mediaConfig': mediaConfig,
    if (mode != null) 'mode': mode,
    if (title != null && title!.trim().isNotEmpty) 'title': title,
    'prompt': prompt,
    'screenplayMode': screenplayMode,
    if (aestheticReferenceId != null)
      'aestheticReferenceId': aestheticReferenceId,
    if (screenplayLinkedCharacters.isNotEmpty)
      'screenplayLinkedCharacters': screenplayLinkedCharacters,
    if (screenplayReferenceNames.isNotEmpty)
      'screenplayReferenceNames': screenplayReferenceNames,
    if (screenplayCharacterAliases.isNotEmpty)
      'screenplayCharacterAliases': screenplayCharacterAliases,
    if (characterMappings.isNotEmpty)
      'characterMappings': <String, Object?>{
        for (final entry in characterMappings.entries)
          if (entry.value.isNotEmpty) entry.key: entry.value,
      },
    if (providerId != null) 'provider': providerId,
    if (modelId != null) 'model': modelId,
    'aspectRatio': aspectRatio,
    'autoDuration': autoDuration,
    'durationSeconds': durationSeconds,
    'frameRate': frameRate,
    'resolution': resolution,
    'generateAudio': generateAudio,
    'safetyTolerance': safetyTolerance,
    'draft': draft,
    'exactTiming': exactTiming,
    'referenceTask': referenceTask,
    'upscale': upscale,
    'upscaleFactor': upscaleFactor,
    'upscaleCreativity': upscaleCreativity,
    if (seed != null) 'seed': seed,
    if (videoUrl.isNotEmpty) 'videoUrl': videoUrl,
    if (draftUrl.isNotEmpty) 'draftUrl': draftUrl,
    if (sourceGenerationId != null) 'sourceGenerationId': sourceGenerationId,
    if (rewriteSummary != null && rewriteSummary!.trim().isNotEmpty)
      'rewriteSummary': rewriteSummary,
    if (localFolderId != null) 'localFolderId': localFolderId,
    if (driveFolderId != null) 'driveFolderId': driveFolderId,
    if (createdAt != null) 'createdAt': createdAt!.toUtc().toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toUtc().toIso8601String(),
  };

  /// Tolerant decoding: unknown or malformed values fall back to defaults so
  /// a record written by a newer build never blanks the whole tab strip.
  factory ComposerTabRecord.fromJson(Map<String, Object?> json) {
    String? text(Object? value) {
      if (value is! String) return null;
      final clean = value.trim();
      return clean.isEmpty ? null : clean;
    }

    int integer(Object? value, int fallback) =>
        value is num ? value.toInt() : fallback;
    bool flag(Object? value, bool fallback) => value is bool ? value : fallback;
    DateTime? stamp(Object? value) =>
        value is String ? DateTime.tryParse(value)?.toUtc() : null;

    return ComposerTabRecord(
      id: json['id']?.toString() ?? '',
      mediaConfig: json['mediaConfig'] is Map
          ? Map<String, Object?>.from(json['mediaConfig'] as Map)
          : null,
      mode: text(json['mode']),
      title: text(json['title']),
      prompt: json['prompt'] is String ? json['prompt']! as String : '',
      screenplayMode: flag(json['screenplayMode'], false),
      aestheticReferenceId: text(json['aestheticReferenceId']),
      screenplayLinkedCharacters:
          (json['screenplayLinkedCharacters'] is List
                  ? json['screenplayLinkedCharacters']! as List
                  : const [])
              .whereType<String>()
              .toList(),
      screenplayReferenceNames: json['screenplayReferenceNames'] is Map
          ? {
              for (final entry
                  in (json['screenplayReferenceNames']! as Map).entries)
                if (entry.key is String && entry.value is String)
                  entry.key as String: entry.value as String,
            }
          : const {},
      screenplayCharacterAliases: json['screenplayCharacterAliases'] is Map
          ? {
              for (final entry
                  in (json['screenplayCharacterAliases']! as Map).entries)
                if (entry.key is String && entry.value is String)
                  entry.key as String: entry.value as String,
            }
          : const {},
      characterMappings: json['characterMappings'] is Map
          ? {
              for (final entry in (json['characterMappings']! as Map).entries)
                if (entry.key is String &&
                    entry.value is List &&
                    (entry.value as List).whereType<String>().isNotEmpty)
                  entry.key as String: (entry.value as List)
                      .whereType<String>()
                      .toList(),
            }
          : const {},
      providerId: text(json['provider']),
      modelId: text(json['model']),
      aspectRatio: text(json['aspectRatio']) ?? '16:9',
      autoDuration: flag(json['autoDuration'], false),
      durationSeconds: integer(json['durationSeconds'], 8),
      frameRate: integer(json['frameRate'], 2),
      resolution: text(json['resolution']) ?? 'hd',
      generateAudio: flag(json['generateAudio'], true),
      safetyTolerance: integer(json['safetyTolerance'], 2),
      draft: flag(json['draft'], false),
      exactTiming: flag(json['exactTiming'], false),
      referenceTask: text(json['referenceTask']) ?? 'reference',
      upscale: flag(json['upscale'], false),
      upscaleFactor: json['upscaleFactor'] is num
          ? (json['upscaleFactor']! as num).toDouble()
          : 2,
      upscaleCreativity: integer(json['upscaleCreativity'], 1),
      seed: json['seed'] is num ? (json['seed']! as num).toInt() : null,
      videoUrl: text(json['videoUrl']) ?? '',
      draftUrl: text(json['draftUrl']) ?? '',
      sourceGenerationId: text(json['sourceGenerationId']),
      rewriteSummary: text(json['rewriteSummary']),
      localFolderId: text(json['localFolderId']),
      driveFolderId: text(json['driveFolderId']),
      createdAt: stamp(json['createdAt']),
      updatedAt: stamp(json['updatedAt']),
    );
  }
}

/// The synthetic device that carries tabs published by builds from before
/// per-device drafts, which wrote one merged strip at the top level.
const String composerLegacyDeviceId = 'legacy';
const String composerLegacyDeviceName = 'Another device (older version)';

/// How long a device's published drafts outlive its last save before other
/// devices stop listing them. Measured against the newest device record, so
/// the rule needs no wall clock and a lone device never drops itself.
const Duration composerDeviceDraftsRetention = Duration(days: 30);

/// One device's published strip: the tabs it had open the last time it
/// saved. Other devices only ever read these — opening one makes a copy —
/// so a device's own tabs are never rewritten by a sync.
class ComposerDeviceDrafts {
  const ComposerDeviceDrafts({
    required this.deviceId,
    required this.deviceName,
    required this.updatedAt,
    this.platform = '',
    this.activeTabId,
    this.tabs = const <ComposerTabRecord>[],
  });

  final String deviceId;
  final String deviceName;

  /// `Platform.operatingSystem` on native stores, `web` in a browser, or
  /// [composerLegacyDeviceId] for tabs folded in from an older build.
  final String platform;
  final DateTime updatedAt;
  final String? activeTabId;
  final List<ComposerTabRecord> tabs;

  /// Drafts worth offering elsewhere: the one that was in front first, then
  /// the most recently edited, blank tabs left out.
  List<ComposerTabRecord> get drafts {
    final list = tabs.where((tab) => !tab.isBlankDraft).toList()
      ..sort((a, b) {
        if (a.id == activeTabId) return -1;
        if (b.id == activeTabId) return 1;
        return (b.updatedAt ?? DateTime.utc(1970)).compareTo(
          a.updatedAt ?? DateTime.utc(1970),
        );
      });
    return list;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'deviceId': deviceId,
    'deviceName': deviceName,
    if (platform.isNotEmpty) 'platform': platform,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    if (activeTabId != null) 'activeTabId': activeTabId,
    'tabs': tabs.map((tab) => tab.toJson()).toList(),
  };

  static ComposerDeviceDrafts? fromJson(Map<String, Object?> json) {
    final id = json['deviceId'];
    if (id is! String || id.trim().isEmpty) return null;
    final name = json['deviceName'];
    final stamp = json['updatedAt'] is String
        ? DateTime.tryParse(json['updatedAt']! as String)?.toUtc()
        : null;
    final seen = <String>{};
    final tabs = (json['tabs'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) => ComposerTabRecord.fromJson(Map<String, Object?>.from(item)),
        )
        .where((tab) => tab.id.isNotEmpty && seen.add(tab.id))
        .toList();
    final active = json['activeTabId'];
    return ComposerDeviceDrafts(
      deviceId: id.trim(),
      deviceName: name is String && name.trim().isNotEmpty
          ? name.trim()
          : 'Another device',
      platform: json['platform'] is String ? json['platform']! as String : '',
      updatedAt: stamp ?? DateTime.utc(1970),
      activeTabId: active is String && tabs.any((tab) => tab.id == active)
          ? active
          : null,
      tabs: tabs,
    );
  }
}

/// Every persisted tab plus which one was open.
///
/// [tabs], [activeTabId], [closedTabs] and [closedTabIds] belong to the device
/// that wrote them and never merge with another device's. What crosses devices
/// is [devices] — each device's published strip, read-only elsewhere — and the
/// text-only aesthetic library with its deletion tombstones.
class ComposerTabsState {
  const ComposerTabsState({
    this.tabs = const <ComposerTabRecord>[],
    this.activeTabId,
    this.closedTabIds = const {},
    this.closedTabs = const [],
    this.aestheticReferences = const [],
    this.deletedAestheticIds = const {},
    this.deviceId,
    this.deviceName,
    this.devicePlatform,
    this.updatedAt,
    this.devices = const <ComposerDeviceDrafts>[],
  });

  // Version 1 migrates additively to prose mode with no character links.
  // Version 6 moves cast lines out of the prompt into characterMappings;
  // older builds refuse the workspace rather than silently dropping casts.
  // Per-device drafts (deviceId, devices) are additive on 6: an older build
  // ignores them, keeps its own strip, and its top-level tabs are folded in
  // as the legacy device by [foldLegacyTabs].
  static const int schemaVersion = 6;

  final List<ComposerTabRecord> tabs;
  final String? activeTabId;
  final Set<String> closedTabIds;

  /// Bounded recovery snapshots. Reopening creates a new id so a tombstone
  /// still wins against stale copies of the original tab on another device.
  final List<ComposerTabRecord> closedTabs;

  /// This device's identity, minted by its store on the first save and
  /// carried in the local file only. Never set on the Drive copy.
  final String? deviceId;
  final String? deviceName;
  final String? devicePlatform;

  /// When this device last saved its strip. Stamped by the store; it dates
  /// the device's published record so the newest copy wins elsewhere.
  final DateTime? updatedAt;

  /// Every device's published strip, this one's included once it has
  /// published, newest first.
  final List<ComposerDeviceDrafts> devices;

  Iterable<Map<String, Object?>> get retainedAssetJson sync* {
    Iterable<Map<String, Object?>> visit(Object? value) sync* {
      if (value is Map) {
        if (value['kind'] is String && value['value'] is String) {
          yield Map<String, Object?>.from(value);
        } else {
          for (final child in value.values) {
            yield* visit(child);
          }
        }
      } else if (value is List) {
        for (final child in value) {
          yield* visit(child);
        }
      }
    }

    for (final tab in [
      ...tabs,
      ...closedTabs,
      for (final device in devices) ...device.tabs,
    ]) {
      yield* visit(tab.mediaConfig);
    }
  }

  final List<AestheticReference> aestheticReferences;
  final Set<String> deletedAestheticIds;

  bool get isEmpty => tabs.isEmpty;

  ComposerTabRecord? get activeTab =>
      tabs.where((tab) => tab.id == activeTabId).firstOrNull ??
      tabs.firstOrNull;

  ComposerDeviceDrafts? deviceById(String id) =>
      devices.where((device) => device.deviceId == id).firstOrNull;

  ComposerTabsState copyWith({
    List<ComposerTabRecord>? tabs,
    String? activeTabId,
    bool clearActiveTabId = false,
    Set<String>? closedTabIds,
    List<ComposerTabRecord>? closedTabs,
    List<AestheticReference>? aestheticReferences,
    Set<String>? deletedAestheticIds,
    String? deviceId,
    String? deviceName,
    String? devicePlatform,
    bool clearDevice = false,
    DateTime? updatedAt,
    bool clearUpdatedAt = false,
    List<ComposerDeviceDrafts>? devices,
  }) => ComposerTabsState(
    tabs: tabs ?? this.tabs,
    activeTabId: clearActiveTabId ? null : activeTabId ?? this.activeTabId,
    closedTabIds: closedTabIds ?? this.closedTabIds,
    closedTabs: closedTabs ?? this.closedTabs,
    aestheticReferences: aestheticReferences ?? this.aestheticReferences,
    deletedAestheticIds: deletedAestheticIds ?? this.deletedAestheticIds,
    deviceId: clearDevice ? null : deviceId ?? this.deviceId,
    deviceName: clearDevice ? null : deviceName ?? this.deviceName,
    devicePlatform: clearDevice ? null : devicePlatform ?? this.devicePlatform,
    updatedAt: clearUpdatedAt ? null : updatedAt ?? this.updatedAt,
    devices: devices ?? this.devices,
  );

  /// This device's strip as one published record, when it has an identity.
  ComposerDeviceDrafts? get ownDevice {
    final id = deviceId;
    if (id == null) return null;
    return ComposerDeviceDrafts(
      deviceId: id,
      deviceName: deviceName ?? 'Another device',
      platform: devicePlatform ?? '',
      updatedAt:
          updatedAt ??
          tabs
              .map((tab) => tab.updatedAt)
              .whereType<DateTime>()
              .fold<DateTime?>(
                null,
                (newest, stamp) =>
                    newest == null || stamp.isAfter(newest) ? stamp : newest,
              ) ??
          DateTime.utc(1970),
      activeTabId: activeTabId,
      tabs: tabs,
    );
  }

  /// The shape that travels to Google Drive: no strip of its own, no
  /// identity, only every device's published record (this device's refreshed
  /// from its strip) and the shared aesthetic library. Idempotent, so the
  /// change detection that compares a stored base with a new write sees the
  /// same bytes for the same state.
  ComposerTabsState asDrivePortable() {
    final own = ownDevice;
    return ComposerTabsState(
      aestheticReferences: aestheticReferences,
      deletedAestheticIds: deletedAestheticIds,
      devices: mergeComposerDevices(
        devices,
        own == null
            ? const <ComposerDeviceDrafts>[]
            : <ComposerDeviceDrafts>[own],
      ),
    );
  }

  /// A Drive file written by an older build holds one merged strip at the
  /// top level. Read it as the legacy device so its drafts stay reachable
  /// without ever landing in this device's own strip.
  ComposerTabsState foldLegacyTabs() {
    if (tabs.isEmpty) return this;
    final newest = tabs
        .map((tab) => tab.updatedAt)
        .whereType<DateTime>()
        .fold<DateTime?>(
          null,
          (newest, stamp) =>
              newest == null || stamp.isAfter(newest) ? stamp : newest,
        );
    return ComposerTabsState(
      aestheticReferences: aestheticReferences,
      deletedAestheticIds: deletedAestheticIds,
      devices: mergeComposerDevices(devices, <ComposerDeviceDrafts>[
        ComposerDeviceDrafts(
          deviceId: composerLegacyDeviceId,
          deviceName: composerLegacyDeviceName,
          platform: composerLegacyDeviceId,
          updatedAt: newest ?? DateTime.utc(1970),
          activeTabId: activeTabId,
          tabs: tabs,
        ),
      ]),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'closedTabIds': closedTabIds.toList()..sort(),
    if (closedTabs.isNotEmpty)
      'closedTabs': closedTabs.map((tab) => tab.toJson()).toList(),
    'aestheticReferences': aestheticReferences
        .map((item) => item.toJson())
        .toList(),
    'deletedAestheticIds': deletedAestheticIds.toList()..sort(),
    if (activeTabId != null) 'activeTabId': activeTabId,
    'tabs': tabs.map((tab) => tab.toJson()).toList(),
    if (deviceId != null) 'deviceId': deviceId,
    if (deviceName != null) 'deviceName': deviceName,
    if (devicePlatform != null) 'devicePlatform': devicePlatform,
    if (updatedAt != null) 'updatedAt': updatedAt!.toUtc().toIso8601String(),
    if (devices.isNotEmpty)
      'devices': devices.map((device) => device.toJson()).toList(),
  };

  /// Drops records without an id and later duplicates of the same id.
  factory ComposerTabsState.fromJson(Map<String, Object?> json) {
    final version = json['schemaVersion'];
    if (version != null && (version is! int || version < 1)) {
      throw const FormatException('Invalid composer workspace schema version.');
    }
    if (version is int && version > schemaVersion) {
      throw UnsupportedError(
        'This workspace needs a newer version of Clawnsole (schema $version).',
      );
    }
    String? text(Object? value) {
      if (value is! String) return null;
      final clean = value.trim();
      return clean.isEmpty ? null : clean;
    }

    final seen = <String>{};
    final tabs = (json['tabs'] as List<Object?>? ?? const <Object?>[])
        .whereType<Map<Object?, Object?>>()
        .map(
          (item) => ComposerTabRecord.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .where((tab) => tab.id.isNotEmpty && seen.add(tab.id))
        .toList();
    final active = json['activeTabId'];
    return ComposerTabsState(
      tabs: tabs,
      closedTabs: (json['closedTabs'] as List? ?? [])
          .whereType<Map>()
          .map(
            (item) =>
                ComposerTabRecord.fromJson(Map<String, Object?>.from(item)),
          )
          .where((tab) => tab.id.isNotEmpty)
          .take(10)
          .toList(),
      closedTabIds: (json['closedTabIds'] as List? ?? [])
          .whereType<String>()
          .toSet(),
      aestheticReferences: (json['aestheticReferences'] as List? ?? [])
          .whereType<Map>()
          .map(
            (item) =>
                AestheticReference.fromJson(Map<String, Object?>.from(item)),
          )
          .toList(),
      deletedAestheticIds: (json['deletedAestheticIds'] as List? ?? [])
          .whereType<String>()
          .toSet(),
      activeTabId: active is String && tabs.any((tab) => tab.id == active)
          ? active
          : tabs.firstOrNull?.id,
      deviceId: text(json['deviceId']),
      deviceName: text(json['deviceName']),
      devicePlatform: text(json['devicePlatform']),
      updatedAt: json['updatedAt'] is String
          ? DateTime.tryParse(json['updatedAt']! as String)?.toUtc()
          : null,
      devices: mergeComposerDevices(
        const <ComposerDeviceDrafts>[],
        (json['devices'] as List? ?? [])
            .whereType<Map>()
            .map(
              (item) => ComposerDeviceDrafts.fromJson(
                Map<String, Object?>.from(item),
              ),
            )
            .whereType<ComposerDeviceDrafts>()
            .toList(),
      ),
    );
  }
}

/// Lays [local] over [remote]. The strip (open tabs, selection, closed
/// drafts) is [local]'s alone — a sync never rewrites the tabs a device is
/// typing in. Device records unite by id with the newest copy winning, the
/// aesthetic library unites by id with the newest edit winning, and explicit
/// tombstones keep an offline device from resurrecting a deleted aesthetic.
ComposerTabsState? mergeComposerWorkspaces(
  ComposerTabsState? local,
  ComposerTabsState? remote,
) {
  if (local == null) return remote;
  if (remote == null) return local;
  final deleted = {...local.deletedAestheticIds, ...remote.deletedAestheticIds};
  final aesthetics = <String, AestheticReference>{};
  for (final item in [
    ...remote.aestheticReferences,
    ...local.aestheticReferences,
  ]) {
    final previous = aesthetics[item.id];
    if (!deleted.contains(item.id) &&
        (previous == null ||
            _newer(
              item.updatedAt,
              previous.updatedAt,
              item.toJson(),
              previous.toJson(),
            ))) {
      aesthetics[item.id] = item;
    }
  }
  return ComposerTabsState(
    tabs: local.tabs,
    activeTabId: local.activeTabId,
    closedTabIds: local.closedTabIds,
    closedTabs: local.closedTabs,
    deviceId: local.deviceId ?? remote.deviceId,
    deviceName: local.deviceName ?? remote.deviceName,
    devicePlatform: local.devicePlatform ?? remote.devicePlatform,
    updatedAt: local.updatedAt ?? remote.updatedAt,
    devices: mergeComposerDevices(remote.devices, local.devices),
    aestheticReferences: aesthetics.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id)),
    deletedAestheticIds: deleted,
  );
}

/// Unites device records by id, the newest copy of each winning, newest
/// device first, and forgets devices that have not saved within
/// [composerDeviceDraftsRetention] of the newest one.
List<ComposerDeviceDrafts> mergeComposerDevices(
  List<ComposerDeviceDrafts> older,
  List<ComposerDeviceDrafts> newer,
) {
  final byId = <String, ComposerDeviceDrafts>{};
  for (final device in [...older, ...newer]) {
    final previous = byId[device.deviceId];
    if (previous == null ||
        _newer(
          device.updatedAt,
          previous.updatedAt,
          device.toJson(),
          previous.toJson(),
        )) {
      byId[device.deviceId] = device;
    }
  }
  final devices = byId.values.toList()
    ..sort((a, b) {
      final comparison = b.updatedAt.compareTo(a.updatedAt);
      return comparison == 0 ? a.deviceId.compareTo(b.deviceId) : comparison;
    });
  if (devices.isEmpty) return devices;
  final cutoff = devices.first.updatedAt.subtract(
    composerDeviceDraftsRetention,
  );
  return devices.where((device) => !device.updatedAt.isBefore(cutoff)).toList();
}

/// Gives [state] the identity and save stamp its store owns before it is
/// written: the id [previous] already carries (or a fresh one from [newId]),
/// the store's current [deviceName]/[platform], and [now] as the strip's save
/// time. The controller never learns these except by reading them back.
ComposerTabsState stampComposerWorkspace(
  ComposerTabsState state, {
  required ComposerTabsState? previous,
  required DateTime now,
  required String deviceName,
  required String platform,
  required String Function() newId,
}) => state.copyWith(
  deviceId: state.deviceId ?? previous?.deviceId ?? newId(),
  deviceName: deviceName,
  devicePlatform: platform,
  updatedAt: now.toUtc(),
  devices: mergeComposerDevices(
    previous?.devices ?? const <ComposerDeviceDrafts>[],
    state.devices,
  ),
);

bool _holdsRetainedAssets(Object? value) {
  if (value is Map) {
    if (value['kind'] is String && value['value'] is String) return true;
    return value.values.any(_holdsRetainedAssets);
  }
  if (value is List) return value.any(_holdsRetainedAssets);
  return false;
}

bool _newer(
  DateTime? a,
  DateTime? b,
  Map<String, Object?> left,
  Map<String, Object?> right,
) {
  final comparison = (a ?? DateTime.utc(1970)).compareTo(
    b ?? DateTime.utc(1970),
  );
  return comparison > 0 ||
      (comparison == 0 && jsonEncode(left).compareTo(jsonEncode(right)) >= 0);
}

/// Workspace persistence can complete locally without waiting for Drive or the
/// encrypted settings vault. Sync failures retry on the next reconciliation.
abstract interface class ComposerWorkspaceStore {
  Future<ComposerTabsState?> readComposerWorkspace();

  /// Writes the strip locally at once. Publication of this device's record
  /// to Drive is throttled in the background unless [publishNow] asks for it
  /// (the app leaving the foreground, a submission).
  Future<void> writeComposerWorkspace(
    ComposerTabsState state, {
    bool publishNow = false,
  });

  /// Publishes whatever local saves have not reached Drive yet. A no-op when
  /// nothing is pending or Drive is not connected.
  Future<void> publishComposerWorkspace();
}
