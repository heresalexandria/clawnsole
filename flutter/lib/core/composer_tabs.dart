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

/// Every persisted tab plus which one was open.
class ComposerTabsState {
  const ComposerTabsState({
    this.tabs = const <ComposerTabRecord>[],
    this.activeTabId,
    this.closedTabIds = const {},
    this.aestheticReferences = const [],
    this.deletedAestheticIds = const {},
  });

  // Version 1 migrates additively to prose mode with no character links.
  static const int schemaVersion = 4;

  final List<ComposerTabRecord> tabs;
  final String? activeTabId;
  final Set<String> closedTabIds;
  final List<AestheticReference> aestheticReferences;
  final Set<String> deletedAestheticIds;

  bool get isEmpty => tabs.isEmpty;

  ComposerTabRecord? get activeTab =>
      tabs.where((tab) => tab.id == activeTabId).firstOrNull ??
      tabs.firstOrNull;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'closedTabIds': closedTabIds.toList()..sort(),
    'aestheticReferences': aestheticReferences
        .map((item) => item.toJson())
        .toList(),
    'deletedAestheticIds': deletedAestheticIds.toList()..sort(),
    if (activeTabId != null) 'activeTabId': activeTabId,
    'tabs': tabs.map((tab) => tab.toJson()).toList(),
  };

  /// Drops records without an id and later duplicates of the same id.
  factory ComposerTabsState.fromJson(Map<String, Object?> json) {
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
    );
  }
}

/// A union of independently edited records. Explicit tombstones keep an offline
/// device from reopening closed tabs or resurrecting deleted aesthetics.
ComposerTabsState? mergeComposerWorkspaces(
  ComposerTabsState? local,
  ComposerTabsState? remote,
) {
  if (local == null) return remote;
  if (remote == null) return local;
  final closed = {...local.closedTabIds, ...remote.closedTabIds};
  final deleted = {...local.deletedAestheticIds, ...remote.deletedAestheticIds};
  final tabs = <String, ComposerTabRecord>{};
  for (final tab in [...remote.tabs, ...local.tabs]) {
    final previous = tabs[tab.id];
    if (!closed.contains(tab.id) &&
        (previous == null ||
            _newer(
              tab.updatedAt,
              previous.updatedAt,
              tab.toJson(),
              previous.toJson(),
            ))) {
      tabs[tab.id] = tab;
    }
  }
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
  final ordered = tabs.values.toList()
    ..sort((a, b) {
      final comparison = (a.createdAt ?? DateTime.utc(1970)).compareTo(
        b.createdAt ?? DateTime.utc(1970),
      );
      return comparison == 0 ? a.id.compareTo(b.id) : comparison;
    });
  return ComposerTabsState(
    tabs: ordered,
    activeTabId: tabs.containsKey(local.activeTabId)
        ? local.activeTabId
        : tabs.containsKey(remote.activeTabId)
        ? remote.activeTabId
        : ordered.firstOrNull?.id,
    closedTabIds: closed,
    aestheticReferences: aesthetics.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id)),
    deletedAestheticIds: deleted,
  );
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
  Future<void> writeComposerWorkspace(ComposerTabsState state);
}
