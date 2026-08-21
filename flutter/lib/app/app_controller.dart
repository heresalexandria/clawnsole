import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';

import '../core/bfl_api.dart';
import '../core/gateway.dart';
import '../core/google_drive.dart';
import '../core/models.dart';
import '../core/pricing.dart';
import '../core/provider_catalog.dart';
import '../core/reference_prompts.dart';
import '../core/settings_vault_gateway.dart';

class PickedAsset {
  const PickedAsset({
    required this.name,
    required this.bytes,
    required this.mimeType,
    this.path,
    this.retained,
    this.thumbnailAsset,
    this.thumbnailBytes,
  });

  final String name;
  final Uint8List bytes;
  final String mimeType;
  final String? path;
  final AssetReference? retained;
  final AssetReference? thumbnailAsset;
  final Uint8List? thumbnailBytes;

  String get dataUrl => 'data:$mimeType;base64,${base64Encode(bytes)}';

  PickedAsset copyWithThumbnail({
    AssetReference? thumbnailAsset,
    Uint8List? thumbnailBytes,
  }) => PickedAsset(
    name: name,
    bytes: bytes,
    mimeType: mimeType,
    path: path,
    retained: retained,
    thumbnailAsset: thumbnailAsset ?? this.thumbnailAsset,
    thumbnailBytes: thumbnailBytes ?? this.thumbnailBytes,
  );
}

class KeyframeDraft {
  const KeyframeDraft({
    required this.id,
    required this.label,
    required this.role,
    required this.source,
    required this.seconds,
    this.asset,
    this.retained,
  });

  final String id;
  final String label;
  final KeyframeRole role;
  final String source;
  final double seconds;
  final PickedAsset? asset;
  final AssetReference? retained;

  String get requestSource => asset?.dataUrl ?? source.trim();

  KeyframeDraft copyWith({String? label, String? source, double? seconds}) =>
      KeyframeDraft(
        id: id,
        label: label ?? this.label,
        role: role,
        source: source ?? this.source,
        seconds: seconds ?? this.seconds,
        asset: asset,
        retained: source == null ? retained : null,
      );
}

class MediaReferenceDraft {
  const MediaReferenceDraft({
    required this.id,
    required this.label,
    required this.kind,
    required this.source,
    this.asset,
    this.retained,
    this.thumbnailAsset,
    this.thumbnailBytes,
    this.savedReferenceId,
  });

  final String id;
  final String label;
  final MediaReferenceKind kind;
  final String source;
  final PickedAsset? asset;
  final AssetReference? retained;
  final AssetReference? thumbnailAsset;
  final Uint8List? thumbnailBytes;
  final String? savedReferenceId;

  String get requestSource => asset?.dataUrl ?? source.trim();

  MediaReferenceDraft copyWith({
    String? label,
    String? source,
    AssetReference? thumbnailAsset,
    bool clearThumbnailAsset = false,
    Uint8List? thumbnailBytes,
    bool clearThumbnailBytes = false,
    String? savedReferenceId,
  }) => MediaReferenceDraft(
    id: id,
    label: label ?? this.label,
    kind: kind,
    source: source ?? this.source,
    asset: asset,
    retained: source == null ? retained : null,
    thumbnailAsset: clearThumbnailAsset
        ? null
        : thumbnailAsset ?? this.thumbnailAsset,
    thumbnailBytes: clearThumbnailBytes
        ? null
        : thumbnailBytes ?? this.thumbnailBytes,
    savedReferenceId: savedReferenceId ?? this.savedReferenceId,
  );
}

class ReferenceCandidate {
  const ReferenceCandidate({
    required this.id,
    required this.name,
    required this.kind,
    required this.asset,
    required this.createdAt,
    this.thumbnailAsset,
    this.folderId,
    this.tags = const <String>[],
    this.generated = false,
    this.storage = LibraryStorage.local,
  });

  final String id;
  final String name;
  final MediaReferenceKind kind;
  final AssetReference asset;
  final AssetReference? thumbnailAsset;
  final DateTime createdAt;
  final String? folderId;
  final List<String> tags;
  final bool generated;
  final LibraryStorage storage;
}

class GenerationFormState {
  String prompt = '';
  String aspectRatio = '16:9';
  bool autoDuration = false;
  int durationSeconds = 8;
  int frameRate = 2;
  String resolution = 'hd';
  bool generateAudio = true;
  int safetyTolerance = 2;
  bool draft = false;
  bool exactTiming = false;
  List<KeyframeDraft> keyframes = <KeyframeDraft>[];
  List<MediaReferenceDraft> references = <MediaReferenceDraft>[];
  MediaReferenceTask referenceTask = MediaReferenceTask.reference;
  PickedAsset? videoAsset;
  String videoUrl = '';
  Uint8List? videoThumbnailBytes;
  VideoSourceMetadata? videoMetadata;
  PickedAsset? draftAsset;
  String draftUrl = '';
  bool upscale = false;
  double upscaleFactor = 2;
  int upscaleCreativity = 1;

  /// Reproducible seed for models that accept one; null means random.
  int? seed;

  /// The operation selected by the model or implied by what is attached.
  /// Upscale is a dedicated model; generation modes otherwise need no picker:
  /// a draft cache wins, then a starting video, then frames/references, then
  /// plain text.
  VideoMode get mode {
    if (upscale) return VideoMode.upscale;
    if (draftAsset != null || draftUrl.trim().isNotEmpty) {
      return VideoMode.draftEnhance;
    }
    if (videoAsset != null || videoUrl.trim().isNotEmpty) return VideoMode.v2v;
    if (keyframes.isNotEmpty || references.isNotEmpty) return VideoMode.i2v;
    return VideoMode.t2v;
  }

  Object get duration => autoDuration ? 'auto' : durationSeconds;

  bool get hasStartFrame =>
      keyframes.any((frame) => frame.role == KeyframeRole.start);
  bool get hasEndFrame =>
      keyframes.any((frame) => frame.role == KeyframeRole.end);

  bool get hasPlainKeyframeLayout {
    if (keyframes.length == 1) {
      return keyframes.single.role == KeyframeRole.start;
    }
    return keyframes.length >= 2 && hasStartFrame && hasEndFrame;
  }

  bool get requiresTimedKeyframes =>
      mode == VideoMode.i2v && keyframes.isNotEmpty && !hasPlainKeyframeLayout;
  bool get usesTimedKeyframes => exactTiming || requiresTimedKeyframes;
  bool get requiresFixedDuration =>
      mode == VideoMode.i2v && (usesTimedKeyframes || keyframes.length > 2);

  int referenceCount(MediaReferenceKind kind) =>
      references.where((item) => item.kind == kind).length;
}

class AppController extends ChangeNotifier {
  AppController({AppGateway? gateway}) : gateway = gateway ?? createGateway();

  final AppGateway gateway;
  final GenerationFormState form = GenerationFormState();

  LocalSnapshot? snapshot;
  AppSection section = AppSection.create;
  LibraryFilter libraryFilter = LibraryFilter.all;
  GenerationViewMode recentWorkViewMode = GenerationViewMode.full;
  GenerationViewMode libraryViewMode = GenerationViewMode.full;
  LibraryStorageFilter libraryStorageFilter = LibraryStorageFilter.all;
  LibraryStorageFilter referenceStorageFilter = LibraryStorageFilter.all;
  FavoriteFilter libraryFavoriteFilter = FavoriteFilter.all;
  FavoriteFilter referenceFavoriteFilter = FavoriteFilter.all;
  VisibilityFilter libraryVisibilityFilter = VisibilityFilter.visible;
  VisibilityFilter referenceVisibilityFilter = VisibilityFilter.visible;
  LibraryStorage defaultStorage = LibraryStorage.local;
  GenerationPlaceholderStyle generationPlaceholderStyle =
      GenerationPlaceholderStyle.broadcastStatic;
  String? lastLocalGenerationFolderId;
  String? lastDriveGenerationFolderId;
  String librarySearch = '';
  String libraryFolderView = libraryFolderAll;
  String? libraryTag;
  String referenceSearch = '';
  String referenceFolderView = libraryFolderAll;
  String? referenceTag;
  MediaReferenceKind? referenceKind;
  ReferenceSort referenceSort = ReferenceSort.newest;
  String selectedProviderId = 'bfl';
  String selectedModelId = 'flux-3-video';
  double? credits;
  final Map<String, ProviderAccountStatus> providerAccounts =
      <String, ProviderAccountStatus>{};
  final Map<String, List<ProviderModelPrice>> providerPrices =
      <String, List<ProviderModelPrice>>{
        for (final provider in videoProviders)
          provider.id: publishedProviderPrices(provider.id),
      };
  bool loading = true;
  bool submitting = false;
  bool refreshingCredits = false;
  int formRevision = 0;
  String? loadError;
  String? creditError;
  String? notice;

  Timer? _pollTimer;
  Timer? _creditTimer;
  Future<void> _preferenceWrites = Future<void>.value();
  Future<bool>? _creditRefreshFuture;
  Timer? _estimateTimer;
  String? _estimateSignature;
  int _estimateRevision = 0;
  int? _liveEstimateRevision;
  CostEstimate? _liveEstimate;
  Timer? _noticeTimer;
  bool _polling = false;
  final Set<String> _retentionAttempts = <String>{};
  final Set<String> _statusChecks = <String>{};
  final Set<String> _referencePreviewWrites = <String>{};
  final Set<String> _generationInputPreviewWrites = <String>{};
  int _idCounter = 0;
  int _libraryMutationRevision = 0;
  final Map<String, int> _generationFavoriteRevisions = <String, int>{};
  final Map<String, int> _referenceFavoriteRevisions = <String, int>{};
  final Map<String, int> _generationVisibilityRevisions = <String, int>{};
  final Map<String, int> _referenceVisibilityRevisions = <String, int>{};

  static const String libraryFolderAll = 'all';
  static const String libraryFolderUnfiled = 'unfiled';

  List<Generation> get generations => snapshot?.generations ?? const [];
  List<Generation> get visibleGenerations =>
      generations.where((item) => !item.hidden).toList();
  List<SavedReference> get savedReferences =>
      snapshot?.savedReferences ?? const <SavedReference>[];
  List<VideoProviderDefinition> get providers {
    final available = snapshot?.availableProviders ?? const <String>{};
    if (available.isEmpty) {
      return videoProviders.where((provider) => !provider.isLocal).toList();
    }
    return videoProviders
        .where((provider) => available.contains(provider.id))
        .toList();
  }

  List<LibraryFolder> foldersFor(
    LibraryCollection collection, {
    LibraryStorage? storage,
  }) {
    final values = List<LibraryFolder>.from(
      (snapshot?.folders ?? const <LibraryFolder>[]).where(
        (folder) =>
            folder.collection == collection &&
            (storage == null || folder.storage == storage),
      ),
    );
    values.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return values;
  }

  List<LibraryFolder> get folders => foldersFor(LibraryCollection.generated);
  List<LibraryFolder> get referenceFolders =>
      foldersFor(LibraryCollection.references);

  VideoProviderDefinition get selectedProvider =>
      providerById(selectedProviderId);
  VideoModelDefinition get selectedModel =>
      modelById(selectedProviderId, selectedModelId);
  VideoModelDefinition get referenceModel => selectedModel;
  bool get hasApiKey => hasApiKeyFor(selectedProviderId);
  bool hasApiKeyFor(String provider) =>
      snapshot?.hasApiKeyFor(provider) ?? false;
  bool get hasAnyApiKey =>
      snapshot?.connectedProviders.isNotEmpty == true ||
      snapshot?.hasApiKey == true;
  bool get supportsPhotoLibrarySave => gateway.supportsPhotoLibrarySave;
  StorageStats get storage =>
      snapshot?.storage ?? const StorageStats(path: '', bytes: 0, records: 0);
  bool get supportsGoogleDrive => gateway is GoogleDriveGateway;
  bool get supportsLocalLibrary =>
      gateway is! GoogleDriveGateway ||
      (gateway as GoogleDriveGateway).supportsLocalLibrary;
  bool get googleDriveConnected =>
      googleDriveConnection.state == GoogleDriveConnectionState.connected;
  LibraryStorage get effectiveStorage =>
      supportsLocalLibrary ? defaultStorage : LibraryStorage.drive;
  bool get canUseDefaultStorage =>
      effectiveStorage == LibraryStorage.local || googleDriveConnected;
  GoogleDriveConnection get googleDriveConnection =>
      gateway is GoogleDriveGateway
      ? (gateway as GoogleDriveGateway).googleDriveConnection
      : const GoogleDriveConnection(
          state: GoogleDriveConnectionState.unavailable,
        );
  bool get supportsSettingsVault => gateway is SettingsVaultGateway;
  SettingsVaultStatus get settingsVaultStatus =>
      snapshot?.settingsVault ?? const SettingsVaultStatus.unavailable();
  bool googleDriveBusy = false;
  bool settingsVaultBusy = false;
  final Set<String> copyingGenerationIds = <String>{};
  final Set<String> copyingReferenceIds = <String>{};
  Future<void> _driveCopyQueue = Future<void>.value();
  int get workingCount => generations.where((item) => item.isWorking).length;
  int get readyCount => generations.where((item) => item.isReady).length;
  double get spentCredits => generations
      .where((item) => item.billingUnit == 'credits')
      .fold(0, (total, item) => total + (item.cost ?? 0));
  double get spentUsd => generations.fold(
    0,
    (total, item) => total + (recordedRealizedCostUsd(item) ?? 0),
  );
  bool isCheckingStatus(String localId) => _statusChecks.contains(localId);
  bool isCopyingGeneration(String localId) =>
      copyingGenerationIds.contains(localId);
  bool isCopyingReference(String referenceId) =>
      copyingReferenceIds.contains(referenceId);
  bool canReuse(Generation item) => item.provider != 'apple-local';

  LibraryFolder? folderById(
    String? folderId, {
    LibraryCollection collection = LibraryCollection.generated,
  }) {
    if (folderId == null) return null;
    for (final folder in foldersFor(collection)) {
      if (folder.id == folderId) return folder;
    }
    return null;
  }

  List<LibraryFolder> childFolders(
    String? parentId, {
    LibraryCollection collection = LibraryCollection.generated,
  }) => foldersFor(
    collection,
  ).where((folder) => folder.parentId == parentId).toList();

  List<LibraryFolder> folderTreeFor(LibraryCollection collection) {
    final ordered = <LibraryFolder>[];
    final visited = <String>{};

    void addChildren(String? parentId) {
      for (final folder in childFolders(parentId, collection: collection)) {
        if (!visited.add(folder.id)) continue;
        ordered.add(folder);
        addChildren(folder.id);
      }
    }

    addChildren(null);
    for (final folder in foldersFor(collection)) {
      if (visited.add(folder.id)) ordered.add(folder);
    }
    return ordered;
  }

  List<LibraryFolder> get folderTree =>
      folderTreeFor(LibraryCollection.generated);
  List<LibraryFolder> get referenceFolderTree =>
      folderTreeFor(LibraryCollection.references);

  int folderDepth(
    String folderId, {
    LibraryCollection collection = LibraryCollection.generated,
  }) {
    var depth = 0;
    var current = folderById(folderId, collection: collection);
    final visited = <String>{folderId};
    while (current?.parentId != null &&
        visited.add(current!.parentId!) &&
        depth < 8) {
      depth += 1;
      current = folderById(current.parentId, collection: collection);
    }
    return depth;
  }

  String folderPath(
    String folderId, {
    LibraryCollection collection = LibraryCollection.generated,
  }) {
    final names = <String>[];
    var current = folderById(folderId, collection: collection);
    final visited = <String>{};
    while (current != null && visited.add(current.id)) {
      names.insert(0, current.name);
      current = folderById(current.parentId, collection: collection);
    }
    return names.join(' / ');
  }

  Set<String> folderBranch(
    String folderId, {
    LibraryCollection collection = LibraryCollection.generated,
  }) {
    final ids = <String>{folderId};
    void addChildren(String parentId) {
      for (final folder in childFolders(parentId, collection: collection)) {
        if (ids.add(folder.id)) addChildren(folder.id);
      }
    }

    addChildren(folderId);
    return ids;
  }

  String get activeFolderLabel => switch (libraryFolderView) {
    libraryFolderAll => 'All films',
    libraryFolderUnfiled => 'Unfiled',
    _ =>
      folderById(libraryFolderView) == null
          ? 'All films'
          : folderPath(libraryFolderView),
  };

  int folderCount(String folderView) => switch (folderView) {
    libraryFolderAll =>
      generations
          .where(
            (item) =>
                libraryStorageFilter.matches(item.storage) &&
                libraryVisibilityFilter.matches(item.hidden),
          )
          .length,
    libraryFolderUnfiled =>
      generations
          .where(
            (item) =>
                libraryStorageFilter.matches(item.storage) &&
                libraryVisibilityFilter.matches(item.hidden) &&
                folderById(item.folderId) == null,
          )
          .length,
    _ =>
      generations
          .where(
            (item) =>
                libraryStorageFilter.matches(item.storage) &&
                libraryVisibilityFilter.matches(item.hidden) &&
                folderBranch(folderView).contains(item.folderId),
          )
          .length,
  };

  List<String> get libraryTags {
    final names = <String, String>{};
    for (final item in generations) {
      for (final tag in item.tags) {
        names.putIfAbsent(tag.toLowerCase(), () => tag);
      }
    }
    final tags = names.values.toList();
    tags.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return tags;
  }

  int tagCount(String tag) => generations
      .where(
        (item) =>
            item.tags.any((value) => value.toLowerCase() == tag.toLowerCase()),
      )
      .length;

  List<Generation> get filteredGenerations {
    final query = librarySearch.trim().toLowerCase();
    final selectedBranch =
        libraryFolderView != libraryFolderAll &&
            libraryFolderView != libraryFolderUnfiled
        ? folderBranch(libraryFolderView)
        : const <String>{};
    return generations.where((item) {
      if (!libraryStorageFilter.matches(item.storage)) return false;
      if (!libraryFavoriteFilter.matches(item.favorite)) return false;
      if (!libraryVisibilityFilter.matches(item.hidden)) return false;
      final folderName = item.folderId == null
          ? ''
          : folderPath(item.folderId!).toLowerCase();
      if (query.isNotEmpty &&
          !item.displayPrompt.toLowerCase().contains(query) &&
          !folderName.contains(query) &&
          !item.tags.any((tag) => tag.toLowerCase().contains(query))) {
        return false;
      }
      if (libraryFolderView == libraryFolderUnfiled &&
          folderById(item.folderId) != null) {
        return false;
      }
      if (libraryFolderView != libraryFolderAll &&
          libraryFolderView != libraryFolderUnfiled &&
          !selectedBranch.contains(item.folderId)) {
        return false;
      }
      if (libraryTag != null &&
          !item.tags.any(
            (tag) => tag.toLowerCase() == libraryTag!.toLowerCase(),
          )) {
        return false;
      }
      return switch (libraryFilter) {
        LibraryFilter.all => true,
        LibraryFilter.working => item.isWorking,
        LibraryFilter.ready => item.isReady,
        LibraryFilter.failed => item.isFailed,
      };
    }).toList();
  }

  String get activeReferenceFolderLabel => switch (referenceFolderView) {
    libraryFolderAll => 'All references',
    libraryFolderUnfiled => 'Unfiled',
    _ =>
      folderById(
                referenceFolderView,
                collection: LibraryCollection.references,
              ) ==
              null
          ? 'All references'
          : folderPath(
              referenceFolderView,
              collection: LibraryCollection.references,
            ),
  };

  int referenceFolderCount(String folderView) => switch (folderView) {
    libraryFolderAll =>
      savedReferences
          .where(
            (item) =>
                referenceStorageFilter.matches(item.storage) &&
                referenceVisibilityFilter.matches(item.hidden),
          )
          .length,
    libraryFolderUnfiled =>
      savedReferences
          .where(
            (item) =>
                referenceStorageFilter.matches(item.storage) &&
                referenceVisibilityFilter.matches(item.hidden) &&
                folderById(
                      item.folderId,
                      collection: LibraryCollection.references,
                    ) ==
                    null,
          )
          .length,
    _ =>
      savedReferences
          .where(
            (item) =>
                referenceStorageFilter.matches(item.storage) &&
                referenceVisibilityFilter.matches(item.hidden) &&
                folderBranch(
                  folderView,
                  collection: LibraryCollection.references,
                ).contains(item.folderId),
          )
          .length,
  };

  List<String> get referenceTags {
    final names = <String, String>{};
    for (final item in savedReferences) {
      for (final tag in item.tags) {
        names.putIfAbsent(tag.toLowerCase(), () => tag);
      }
    }
    final tags = names.values.toList();
    tags.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return tags;
  }

  int referenceTagCount(String tag) => savedReferences
      .where(
        (item) =>
            item.tags.any((value) => value.toLowerCase() == tag.toLowerCase()),
      )
      .length;

  List<SavedReference> get filteredSavedReferences {
    final query = referenceSearch.trim().toLowerCase();
    final selectedBranch =
        referenceFolderView != libraryFolderAll &&
            referenceFolderView != libraryFolderUnfiled
        ? folderBranch(
            referenceFolderView,
            collection: LibraryCollection.references,
          )
        : const <String>{};
    final values = savedReferences.where((item) {
      if (!referenceStorageFilter.matches(item.storage)) return false;
      if (!referenceFavoriteFilter.matches(item.favorite)) return false;
      if (!referenceVisibilityFilter.matches(item.hidden)) return false;
      final folderName = item.folderId == null
          ? ''
          : folderPath(
              item.folderId!,
              collection: LibraryCollection.references,
            ).toLowerCase();
      if (query.isNotEmpty &&
          !item.name.toLowerCase().contains(query) &&
          !folderName.contains(query) &&
          !item.tags.any((tag) => tag.toLowerCase().contains(query))) {
        return false;
      }
      if (referenceFolderView == libraryFolderUnfiled &&
          folderById(item.folderId, collection: LibraryCollection.references) !=
              null) {
        return false;
      }
      if (referenceFolderView != libraryFolderAll &&
          referenceFolderView != libraryFolderUnfiled &&
          !selectedBranch.contains(item.folderId)) {
        return false;
      }
      if (referenceTag != null &&
          !item.tags.any(
            (tag) => tag.toLowerCase() == referenceTag!.toLowerCase(),
          )) {
        return false;
      }
      return referenceKind == null || item.kind == referenceKind;
    }).toList();
    values.sort(switch (referenceSort) {
      ReferenceSort.newest => (a, b) => b.updatedAt.compareTo(a.updatedAt),
      ReferenceSort.oldest => (a, b) => a.updatedAt.compareTo(b.updatedAt),
      ReferenceSort.name => (a, b) => a.name.toLowerCase().compareTo(
        b.name.toLowerCase(),
      ),
      ReferenceSort.kind => (a, b) {
        final kind = a.kind.index.compareTo(b.kind.index);
        return kind != 0
            ? kind
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      },
    });
    return values;
  }

  AssetReference? _reference(PickedAsset? asset, String url, String label) {
    if (asset?.retained != null) return asset!.retained;
    final remote = Uri.tryParse(url.trim());
    return remote?.scheme == 'https'
        ? AssetReference(kind: 'remote', value: url.trim(), label: label)
        : null;
  }

  AssetReference? _previewForStorage(
    AssetReference? preview,
    LibraryStorage storage,
  ) {
    if (preview == null) return null;
    return switch (storage) {
      LibraryStorage.local when preview.kind == 'local' => preview,
      LibraryStorage.drive when preview.kind == 'drive' => preview,
      _ => null,
    };
  }

  GenerationConfig get currentConfig {
    final orderedFrames = _orderedFrames();
    final upscaling = form.mode == VideoMode.upscale;
    return GenerationConfig(
      aspectRatio: upscaling ? 'auto' : form.aspectRatio,
      duration: upscaling ? 'source' : form.duration,
      resolution: upscaling ? 'source' : form.resolution,
      generateAudio: upscaling ? false : form.generateAudio,
      safetyTolerance: form.safetyTolerance,
      draft: upscaling ? false : form.draft,
      frameRate: form.frameRate,
      exactTiming: form.usesTimedKeyframes,
      keyframes: form.mode == VideoMode.i2v
          ? orderedFrames
                .map(
                  (frame) => KeyframeLabel(
                    label: frame.label,
                    role: frame.role,
                    seconds: form.usesTimedKeyframes ? frame.seconds : null,
                    source:
                        frame.asset?.retained ??
                        frame.retained ??
                        _reference(null, frame.source, frame.label),
                  ),
                )
                .toList()
          : null,
      references: form.mode == VideoMode.i2v
          ? form.references
                .map(
                  (item) => MediaReferenceLabel(
                    label: item.label,
                    kind: item.kind,
                    source:
                        item.asset?.retained ??
                        item.retained ??
                        _reference(null, item.source, item.label),
                    thumbnailAsset: _previewForStorage(
                      item.thumbnailAsset ?? item.asset?.thumbnailAsset,
                      effectiveStorage,
                    ),
                  ),
                )
                .toList()
          : null,
      referenceTask: form.referenceTask,
      sourceLabel: switch (form.mode) {
        VideoMode.v2v =>
          form.videoAsset?.name ??
              (form.videoUrl.trim().isEmpty ? null : form.videoUrl.trim()),
        VideoMode.draftEnhance =>
          form.draftAsset?.name ??
              (form.draftUrl.trim().isEmpty ? null : form.draftUrl.trim()),
        VideoMode.upscale =>
          form.videoAsset?.name ??
              (form.videoUrl.trim().isEmpty ? null : form.videoUrl.trim()),
        _ => null,
      },
      source: switch (form.mode) {
        VideoMode.v2v => _reference(
          form.videoAsset,
          form.videoUrl,
          form.videoAsset?.name ?? 'Starting video',
        ),
        VideoMode.draftEnhance => _reference(
          form.draftAsset,
          form.draftUrl,
          form.draftAsset?.name ?? 'FLUX 3 draft cache',
        ),
        VideoMode.upscale => _reference(
          form.videoAsset,
          form.videoUrl,
          form.videoAsset?.name ?? 'Video to upscale',
        ),
        _ => null,
      },
      sourceThumbnailAsset:
          form.mode == VideoMode.v2v || form.mode == VideoMode.upscale
          ? _previewForStorage(
              form.videoAsset?.thumbnailAsset,
              effectiveStorage,
            )
          : null,
      upscaleFactor: form.upscaleFactor,
      upscaleCreativity: form.upscaleCreativity,
      seed: selectedModel.supportsSeed ? form.seed : null,
    );
  }

  CostEstimate get currentEstimate {
    final fallback = estimateCost(
      selectedProviderId,
      selectedModel.id,
      form.mode,
      currentConfig,
      generations,
      providerPrices[selectedProviderId] ?? const <ProviderModelPrice>[],
      form.videoMetadata,
    );
    if (_liveEstimateRevision == _estimateRevision && _liveEstimate != null) {
      return _liveEstimate!.withPricingContext(fallback);
    }
    return fallback;
  }

  Future<void> initialize() async {
    try {
      _apply(await gateway.load(), restorePreferences: true);
      unawaited(resumeGoogleDrive());
      if (generations.isNotEmpty) {
        await _restoreGenerationSettings(generations.first);
      }
      if (selectedProvider.requiresApiKey && hasApiKey) {
        unawaited(refreshCredits());
      }
      if (hasAnyApiKey) unawaited(pollWorking());
      for (final provider in providers.where((item) => item.requiresApiKey)) {
        unawaited(refreshProviderModels(provider.id));
      }
      _invalidateProviderEstimate();
    } on Object catch (error) {
      loadError = _message(error);
    } finally {
      loading = false;
      notifyListeners();
    }
    _pollTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => unawaited(pollWorking()),
    );
    _creditTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (selectedProvider.requiresApiKey && hasApiKey) {
        unawaited(refreshCredits());
      }
    });
  }

  void _apply(LocalSnapshot value, {bool restorePreferences = false}) {
    snapshot = restorePreferences
        ? value
        : LocalSnapshot(
            generations: value.generations,
            folders: value.folders,
            savedReferences: value.savedReferences,
            preferences: _preferences(),
            hasApiKey: value.hasApiKey,
            connectedProviders: value.connectedProviders,
            availableProviders: value.availableProviders,
            storage: value.storage,
            settingsVault: value.settingsVault,
          );
    if (restorePreferences) {
      section = value.preferences.activeSection;
      libraryFilter = value.preferences.libraryFilter;
      recentWorkViewMode = value.preferences.recentWorkViewMode;
      libraryViewMode = value.preferences.libraryViewMode;
      libraryStorageFilter = value.preferences.libraryStorageFilter;
      referenceStorageFilter = value.preferences.referenceStorageFilter;
      generationPlaceholderStyle = value.preferences.generationPlaceholderStyle;
      defaultStorage = supportsLocalLibrary
          ? value.preferences.defaultStorage
          : LibraryStorage.drive;
      lastLocalGenerationFolderId =
          value.preferences.lastLocalGenerationFolderId;
      lastDriveGenerationFolderId =
          value.preferences.lastDriveGenerationFolderId;
      if (folderById(lastLocalGenerationFolderId)?.storage !=
          LibraryStorage.local) {
        lastLocalGenerationFolderId = null;
      }
      if (folderById(lastDriveGenerationFolderId)?.storage !=
          LibraryStorage.drive) {
        lastDriveGenerationFolderId = null;
      }
      final preferredProvider = providerById(value.preferences.provider);
      final available = providers;
      final previousModelId = selectedModelId;
      selectedProviderId =
          available.any((provider) => provider.id == preferredProvider.id)
          ? preferredProvider.id
          : available.firstOrNull?.id ?? 'bfl';
      selectedModelId = modelById(
        selectedProviderId,
        value.preferences.model,
      ).id;
      // A restored model must constrain the form exactly like a selected one,
      // or a session can reopen with settings the model does not support
      // (for example Auto duration on a fixed-duration model).
      if (selectedModelId != previousModelId) _normalizeFormForModel();
    }
    if (libraryFolderView != libraryFolderAll &&
        libraryFolderView != libraryFolderUnfiled &&
        !value.folders.any((folder) => folder.id == libraryFolderView)) {
      libraryFolderView = libraryFolderAll;
    }
    if (referenceFolderView != libraryFolderAll &&
        referenceFolderView != libraryFolderUnfiled &&
        !value.folders.any(
          (folder) =>
              folder.id == referenceFolderView &&
              folder.collection == LibraryCollection.references,
        )) {
      referenceFolderView = libraryFolderAll;
    }
    loadError = null;
    notifyListeners();
  }

  void showNotice(String message) {
    notice = message;
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(seconds: 4), () {
      notice = null;
      notifyListeners();
    });
    notifyListeners();
  }

  String _message(Object error) => error
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('ProviderException: ', '')
      .replaceFirst('Exception: ', '');

  Future<void> _savePreferences(AppPreferences preferences) {
    final operation = _preferenceWrites.then((_) async {
      _apply(await gateway.setPreferences(preferences));
    });
    _preferenceWrites = operation.then<void>((_) {}, onError: (_) {});
    return operation;
  }

  Future<void> navigate(AppSection value) async {
    section = value;
    notifyListeners();
    try {
      await _savePreferences(_preferences(activeSection: value));
    } on Object catch (error) {
      showNotice(_message(error));
    }
  }

  Future<void> setLibraryFilter(LibraryFilter value) async {
    libraryFilter = value;
    notifyListeners();
    try {
      await _savePreferences(_preferences(libraryFilter: value));
    } on Object catch (error) {
      showNotice(_message(error));
    }
  }

  Future<void> setRecentWorkViewMode(GenerationViewMode value) async {
    recentWorkViewMode = value;
    notifyListeners();
    try {
      await _savePreferences(_preferences(recentWorkViewMode: value));
    } on Object catch (error) {
      showNotice(_message(error));
    }
  }

  Future<void> setLibraryViewMode(GenerationViewMode value) async {
    libraryViewMode = value;
    notifyListeners();
    try {
      await _savePreferences(_preferences(libraryViewMode: value));
    } on Object catch (error) {
      showNotice(_message(error));
    }
  }

  Future<void> setLibraryStorageFilter(LibraryStorageFilter value) async {
    libraryStorageFilter = value;
    notifyListeners();
    try {
      await _savePreferences(_preferences(libraryStorageFilter: value));
    } on Object catch (error) {
      showNotice(_message(error));
    }
  }

  Future<void> setReferenceStorageFilter(LibraryStorageFilter value) async {
    referenceStorageFilter = value;
    notifyListeners();
    try {
      await _savePreferences(_preferences(referenceStorageFilter: value));
    } on Object catch (error) {
      showNotice(_message(error));
    }
  }

  Future<void> setDefaultStorage(LibraryStorage value) async {
    if (value == LibraryStorage.local && !supportsLocalLibrary) {
      showNotice('This web build stores its library in Google Drive.');
      return;
    }
    if (value == LibraryStorage.drive && !googleDriveConnected) {
      showNotice('Connect Google Drive before choosing it for new items.');
      return;
    }
    defaultStorage = value;
    notifyListeners();
    try {
      await _savePreferences(_preferences(defaultStorage: value));
    } on Object catch (error) {
      showNotice(_message(error));
    }
  }

  Future<void> setGenerationPlaceholderStyle(
    GenerationPlaceholderStyle value,
  ) async {
    generationPlaceholderStyle = value;
    notifyListeners();
    try {
      await _savePreferences(_preferences());
    } on Object catch (error) {
      showNotice(_message(error));
    }
  }

  String? get selectedGenerationFolderId =>
      effectiveStorage == LibraryStorage.drive
      ? lastDriveGenerationFolderId
      : lastLocalGenerationFolderId;

  Future<void> setGenerationFolder(String? folderId) async {
    final folder = folderById(folderId);
    if (folderId != null &&
        (folder == null || folder.storage != effectiveStorage)) {
      showNotice('That destination folder is no longer available.');
      return;
    }
    if (effectiveStorage == LibraryStorage.drive) {
      lastDriveGenerationFolderId = folderId;
    } else {
      lastLocalGenerationFolderId = folderId;
    }
    notifyListeners();
    try {
      await _savePreferences(
        _preferences(
          lastLocalGenerationFolderId: lastLocalGenerationFolderId,
          clearLastLocalGenerationFolder: lastLocalGenerationFolderId == null,
          lastDriveGenerationFolderId: lastDriveGenerationFolderId,
          clearLastDriveGenerationFolder: lastDriveGenerationFolderId == null,
        ),
      );
    } on Object catch (error) {
      showNotice(_message(error));
    }
  }

  void setLibraryFavoriteFilter(FavoriteFilter value) {
    libraryFavoriteFilter = value;
    notifyListeners();
  }

  void setReferenceFavoriteFilter(FavoriteFilter value) {
    referenceFavoriteFilter = value;
    notifyListeners();
  }

  void setLibraryVisibilityFilter(VisibilityFilter value) {
    libraryVisibilityFilter = value;
    notifyListeners();
  }

  void setReferenceVisibilityFilter(VisibilityFilter value) {
    referenceVisibilityFilter = value;
    notifyListeners();
  }

  Future<void> toggleGenerationFavorite(Generation item) async {
    if (gateway is! FavoriteGateway) return;
    final current = generations
        .where((candidate) => candidate.localId == item.localId)
        .firstOrNull;
    if (current == null || snapshot == null) return;
    final favorite = !current.favorite;
    final revision = ++_libraryMutationRevision;
    _generationFavoriteRevisions[item.localId] = revision;
    snapshot = snapshot!.copyWith(
      generations: generations
          .map(
            (candidate) => candidate.localId == item.localId
                ? candidate.copyWith(favorite: favorite)
                : candidate,
          )
          .toList(),
    );
    notifyListeners();
    try {
      await (gateway as FavoriteGateway).setGenerationFavorite(
        item.localId,
        favorite,
      );
    } on Object catch (error) {
      if (_generationFavoriteRevisions[item.localId] == revision &&
          snapshot != null) {
        snapshot = snapshot!.copyWith(
          generations: generations
              .map(
                (candidate) => candidate.localId == item.localId
                    ? candidate.copyWith(favorite: current.favorite)
                    : candidate,
              )
              .toList(),
        );
        notifyListeners();
      }
      showNotice(_message(error));
    } finally {
      if (_generationFavoriteRevisions[item.localId] == revision) {
        _generationFavoriteRevisions.remove(item.localId);
      }
    }
  }

  Future<void> toggleReferenceFavorite(SavedReference item) async {
    if (gateway is! FavoriteGateway) return;
    final current = savedReferences
        .where((candidate) => candidate.id == item.id)
        .firstOrNull;
    if (current == null || snapshot == null) return;
    final favorite = !current.favorite;
    final revision = ++_libraryMutationRevision;
    _referenceFavoriteRevisions[item.id] = revision;
    snapshot = snapshot!.copyWith(
      savedReferences: savedReferences
          .map(
            (candidate) => candidate.id == item.id
                ? candidate.copyWith(favorite: favorite)
                : candidate,
          )
          .toList(),
    );
    notifyListeners();
    try {
      await (gateway as FavoriteGateway).setReferenceFavorite(
        item.id,
        favorite,
      );
    } on Object catch (error) {
      if (_referenceFavoriteRevisions[item.id] == revision &&
          snapshot != null) {
        snapshot = snapshot!.copyWith(
          savedReferences: savedReferences
              .map(
                (candidate) => candidate.id == item.id
                    ? candidate.copyWith(favorite: current.favorite)
                    : candidate,
              )
              .toList(),
        );
        notifyListeners();
      }
      showNotice(_message(error));
    } finally {
      if (_referenceFavoriteRevisions[item.id] == revision) {
        _referenceFavoriteRevisions.remove(item.id);
      }
    }
  }

  Future<bool> setGenerationsHidden(
    Iterable<String> localIds,
    bool hidden,
  ) async {
    if (gateway is! VisibilityGateway || snapshot == null) return false;
    final ids = localIds.toSet();
    if (ids.isEmpty) return true;
    final previous = <String, bool>{
      for (final item in generations.where(
        (item) => ids.contains(item.localId),
      ))
        item.localId: item.hidden,
    };
    if (previous.length != ids.length) {
      showNotice('One or more generations are no longer available.');
      return false;
    }
    final revision = ++_libraryMutationRevision;
    for (final id in ids) {
      _generationVisibilityRevisions[id] = revision;
    }
    snapshot = snapshot!.copyWith(
      generations: generations
          .map(
            (item) => ids.contains(item.localId)
                ? item.copyWith(hidden: hidden)
                : item,
          )
          .toList(),
    );
    notifyListeners();
    try {
      await (gateway as VisibilityGateway).setGenerationsHidden(
        ids.toList(),
        hidden,
      );
      showNotice(hidden ? 'Moved to Hidden.' : 'Restored from Hidden.');
      return true;
    } on Object catch (error) {
      if (snapshot != null) {
        snapshot = snapshot!.copyWith(
          generations: generations.map((item) {
            if (_generationVisibilityRevisions[item.localId] != revision) {
              return item;
            }
            return item.copyWith(hidden: previous[item.localId]);
          }).toList(),
        );
        notifyListeners();
      }
      showNotice(_message(error));
      return false;
    } finally {
      for (final id in ids) {
        if (_generationVisibilityRevisions[id] == revision) {
          _generationVisibilityRevisions.remove(id);
        }
      }
    }
  }

  Future<bool> setReferencesHidden(
    Iterable<String> referenceIds,
    bool hidden,
  ) async {
    if (gateway is! VisibilityGateway || snapshot == null) return false;
    final ids = referenceIds.toSet();
    if (ids.isEmpty) return true;
    final previous = <String, bool>{
      for (final item in savedReferences.where((item) => ids.contains(item.id)))
        item.id: item.hidden,
    };
    if (previous.length != ids.length) {
      showNotice('One or more references are no longer available.');
      return false;
    }
    final revision = ++_libraryMutationRevision;
    for (final id in ids) {
      _referenceVisibilityRevisions[id] = revision;
    }
    snapshot = snapshot!.copyWith(
      savedReferences: savedReferences
          .map(
            (item) =>
                ids.contains(item.id) ? item.copyWith(hidden: hidden) : item,
          )
          .toList(),
    );
    notifyListeners();
    try {
      await (gateway as VisibilityGateway).setReferencesHidden(
        ids.toList(),
        hidden,
      );
      showNotice(hidden ? 'Moved to Hidden.' : 'Restored from Hidden.');
      return true;
    } on Object catch (error) {
      if (snapshot != null) {
        snapshot = snapshot!.copyWith(
          savedReferences: savedReferences.map((item) {
            if (_referenceVisibilityRevisions[item.id] != revision) return item;
            return item.copyWith(hidden: previous[item.id]);
          }).toList(),
        );
        notifyListeners();
      }
      showNotice(_message(error));
      return false;
    } finally {
      for (final id in ids) {
        if (_referenceVisibilityRevisions[id] == revision) {
          _referenceVisibilityRevisions.remove(id);
        }
      }
    }
  }

  void setSearch(String value) {
    librarySearch = value;
    notifyListeners();
  }

  void setLibraryFolderView(String value) {
    final folder = folderById(value);
    if (folder != null && !libraryStorageFilter.matches(folder.storage)) {
      unawaited(
        setLibraryStorageFilter(
          folder.storage == LibraryStorage.local
              ? LibraryStorageFilter.local
              : LibraryStorageFilter.drive,
        ),
      );
    }
    libraryFolderView = value;
    notifyListeners();
  }

  void setLibraryTag(String? value) {
    libraryTag = value;
    notifyListeners();
  }

  void setReferenceSearch(String value) {
    referenceSearch = value;
    notifyListeners();
  }

  void setReferenceFolderView(String value) {
    final folder = folderById(value, collection: LibraryCollection.references);
    if (folder != null && !referenceStorageFilter.matches(folder.storage)) {
      unawaited(
        setReferenceStorageFilter(
          folder.storage == LibraryStorage.local
              ? LibraryStorageFilter.local
              : LibraryStorageFilter.drive,
        ),
      );
    }
    referenceFolderView = value;
    notifyListeners();
  }

  void setReferenceTag(String? value) {
    referenceTag = value;
    notifyListeners();
  }

  void setReferenceKind(MediaReferenceKind? value) {
    referenceKind = value;
    notifyListeners();
  }

  void setReferenceSort(ReferenceSort value) {
    referenceSort = value;
    notifyListeners();
  }

  List<String> cleanLibraryTags(Iterable<String> input) {
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

  Future<bool> saveLibraryFolder(
    String name, {
    LibraryFolder? existing,
    String? parentId,
    LibraryCollection collection = LibraryCollection.generated,
    LibraryStorage? storage,
  }) async {
    final clean = name.trim();
    if (clean.isEmpty || clean.length > 48) {
      showNotice('Folder names must be between 1 and 48 characters.');
      return false;
    }
    if (gateway is! LibraryOrganizationGateway) {
      showNotice('Folder organization is unavailable on this build.');
      return false;
    }
    final organization = gateway as LibraryOrganizationGateway;
    final now = DateTime.now().toUtc();
    final destination =
        existing?.storage ??
        folderById(parentId, collection: collection)?.storage ??
        storage ??
        effectiveStorage;
    if (destination == LibraryStorage.drive && !googleDriveConnected) {
      showNotice('Connect Google Drive before creating a Drive folder.');
      return false;
    }
    final folder = LibraryFolder(
      id:
          existing?.id ??
          'folder-${now.microsecondsSinceEpoch.toRadixString(36)}-${_idCounter++}',
      name: clean,
      createdAt: existing?.createdAt ?? now,
      parentId: parentId,
      collection: existing?.collection ?? collection,
      storage: destination,
    );
    try {
      _apply(await organization.saveLibraryFolder(folder));
      showNotice(existing == null ? 'Folder created.' : 'Folder updated.');
      return true;
    } on Object catch (error) {
      showNotice(_message(error));
      return false;
    }
  }

  Future<bool> deleteLibraryFolder(String folderId) async {
    if (gateway is! LibraryOrganizationGateway) return false;
    final organization = gateway as LibraryOrganizationGateway;
    try {
      _apply(await organization.deleteLibraryFolder(folderId));
      if (libraryFolderView == folderId) {
        libraryFolderView = libraryFolderAll;
      }
      if (referenceFolderView == folderId) {
        referenceFolderView = libraryFolderAll;
      }
      showNotice('Folder removed. Its items are unfiled and subfolders kept.');
      return true;
    } on Object catch (error) {
      showNotice(_message(error));
      return false;
    }
  }

  Future<bool> organizeGeneration(
    String localId, {
    String? folderId,
    required Iterable<String> tags,
  }) async {
    if (gateway is! LibraryOrganizationGateway) {
      showNotice('Library organization is unavailable on this build.');
      return false;
    }
    final organization = gateway as LibraryOrganizationGateway;
    try {
      _apply(
        await organization.setGenerationOrganization(
          localId,
          folderId: folderId,
          tags: cleanLibraryTags(tags),
        ),
      );
      showNotice('Library organization saved.');
      return true;
    } on Object catch (error) {
      showNotice(_message(error));
      return false;
    }
  }

  Future<bool> moveGenerations(
    Iterable<String> localIds, {
    String? folderId,
  }) async {
    if (gateway is! LibraryOrganizationGateway) return false;
    final ids = localIds.toSet();
    final targets = generations
        .where((item) => ids.contains(item.localId))
        .toList();
    if (targets.length != ids.length) {
      showNotice('One or more generations are no longer available.');
      return false;
    }
    final folder = folderById(folderId);
    if (folderId != null &&
        (folder == null ||
            targets.any((item) => item.storage != folder.storage))) {
      showNotice('Choose a folder in the same storage as the selected items.');
      return false;
    }
    try {
      final organization = gateway as LibraryOrganizationGateway;
      for (final item in targets) {
        _apply(
          await organization.setGenerationOrganization(
            item.localId,
            folderId: folderId,
            tags: item.tags,
          ),
        );
      }
      showNotice(
        '${targets.length == 1 ? 'Generation' : '${targets.length} generations'} moved.',
      );
      return true;
    } on Object catch (error) {
      showNotice(_message(error));
      return false;
    }
  }

  Future<bool> tagGeneration(String localId, Iterable<String> tags) async {
    final item = generations
        .where((candidate) => candidate.localId == localId)
        .firstOrNull;
    if (item == null) return false;
    final saved = await organizeGeneration(
      localId,
      folderId: item.folderId,
      tags: tags,
    );
    if (saved) showNotice('Tags saved.');
    return saved;
  }

  Future<bool> moveReferences(
    Iterable<String> referenceIds, {
    String? folderId,
  }) async {
    if (gateway is! ReferenceLibraryGateway) return false;
    final ids = referenceIds.toSet();
    final targets = savedReferences
        .where((item) => ids.contains(item.id))
        .toList();
    if (targets.length != ids.length) {
      showNotice('One or more references are no longer available.');
      return false;
    }
    final folder = folderById(
      folderId,
      collection: LibraryCollection.references,
    );
    if (folderId != null &&
        (folder == null ||
            targets.any((item) => item.storage != folder.storage))) {
      showNotice('Choose a folder in the same storage as the selected items.');
      return false;
    }
    try {
      final library = gateway as ReferenceLibraryGateway;
      for (final item in targets) {
        _apply(
          await library.saveReference(
            item.copyWith(
              folderId: folderId,
              clearFolder: folderId == null,
              updatedAt: DateTime.now().toUtc(),
            ),
          ),
        );
      }
      showNotice(
        '${targets.length == 1 ? 'Reference' : '${targets.length} references'} moved.',
      );
      return true;
    } on Object catch (error) {
      showNotice(_message(error));
      return false;
    }
  }

  Future<bool> tagReference(String referenceId, Iterable<String> tags) async {
    final item = savedReferences
        .where((candidate) => candidate.id == referenceId)
        .firstOrNull;
    if (item == null) return false;
    return updateSavedReference(
      item,
      name: item.name,
      folderId: item.folderId,
      tags: tags,
    );
  }

  Future<SavedReference?> saveDraftReference(
    MediaReferenceDraft draft, {
    required String name,
    String? folderId,
    required Iterable<String> tags,
    LibraryStorage? storage,
  }) async {
    if (gateway is! ReferenceLibraryGateway) {
      showNotice('Saved references are unavailable on this build.');
      return null;
    }
    final clean = name.trim();
    if (clean.isEmpty || clean.length > 80) {
      showNotice('Reference names must be between 1 and 80 characters.');
      return null;
    }
    final now = DateTime.now().toUtc();
    final id =
        draft.savedReferenceId ??
        'reference-${now.microsecondsSinceEpoch.toRadixString(36)}-${_idCounter++}';
    final retained =
        draft.asset?.retained ??
        draft.retained ??
        _reference(null, draft.source, draft.label);
    final existing = savedReferences
        .where((item) => item.id == draft.savedReferenceId)
        .firstOrNull;
    final destination =
        existing?.storage ??
        folderById(
          folderId,
          collection: LibraryCollection.references,
        )?.storage ??
        storage ??
        effectiveStorage;
    if (destination == LibraryStorage.drive && !googleDriveConnected) {
      showNotice('Connect Google Drive before saving a Drive reference.');
      return null;
    }
    final reference = SavedReference(
      id: id,
      name: clean,
      kind: draft.kind,
      asset:
          retained ??
          AssetReference(kind: 'remote', value: '', label: draft.label),
      thumbnailAsset: _previewForStorage(
        draft.thumbnailAsset ?? draft.asset?.thumbnailAsset,
        destination,
      ),
      createdAt: now,
      updatedAt: now,
      folderId: folderId,
      tags: cleanLibraryTags(tags),
      storage: destination,
    );
    try {
      _apply(
        await (gateway as ReferenceLibraryGateway).saveReference(
          reference,
          source: draft.requestSource.isEmpty ? null : draft.requestSource,
        ),
      );
      var saved = savedReferences.where((item) => item.id == id).firstOrNull;
      if (saved == null) throw StateError('The saved reference was not found.');
      final thumbnailBytes =
          draft.thumbnailBytes ?? draft.asset?.thumbnailBytes;
      if (saved.thumbnailAsset == null && thumbnailBytes != null) {
        await cacheReferencePreview(saved, thumbnailBytes);
        saved = savedReferences.where((item) => item.id == id).firstOrNull;
        if (saved == null) {
          throw StateError('The saved reference was not found.');
        }
      }
      final savedReference = saved;
      form.references = form.references.map((item) {
        if (item.id != draft.id) return item;
        final asset = item.asset;
        return MediaReferenceDraft(
          id: item.id,
          label: item.label,
          kind: item.kind,
          source: savedReference.asset.isLocal
              ? ''
              : savedReference.asset.value,
          asset: asset == null
              ? null
              : PickedAsset(
                  name: asset.name,
                  bytes: asset.bytes,
                  mimeType: asset.mimeType,
                  retained: savedReference.asset,
                  thumbnailAsset: savedReference.thumbnailAsset,
                  thumbnailBytes: asset.thumbnailBytes,
                ),
          retained: savedReference.asset,
          thumbnailAsset: savedReference.thumbnailAsset,
          thumbnailBytes: item.thumbnailBytes,
          savedReferenceId: savedReference.id,
        );
      }).toList();
      notifyListeners();
      showNotice('“${savedReference.name}” saved to References.');
      return savedReference;
    } on Object catch (error) {
      showNotice(_message(error));
      return null;
    }
  }

  Future<bool> updateSavedReference(
    SavedReference reference, {
    required String name,
    String? folderId,
    required Iterable<String> tags,
  }) async {
    if (gateway is! ReferenceLibraryGateway) return false;
    final clean = name.trim();
    if (clean.isEmpty || clean.length > 80) {
      showNotice('Reference names must be between 1 and 80 characters.');
      return false;
    }
    try {
      _apply(
        await (gateway as ReferenceLibraryGateway).saveReference(
          reference.copyWith(
            name: clean,
            folderId: folderId,
            clearFolder: folderId == null,
            tags: cleanLibraryTags(tags),
            updatedAt: DateTime.now().toUtc(),
          ),
        ),
      );
      showNotice('Reference updated.');
      return true;
    } on Object catch (error) {
      showNotice(_message(error));
      return false;
    }
  }

  Future<void> importSavedReferences(
    MediaReferenceKind kind, {
    String? folderId,
    LibraryStorage? storage,
  }) async {
    if (gateway is! ReferenceLibraryGateway) return;
    try {
      final picked = await _pickMany(switch (kind) {
        MediaReferenceKind.image => FileType.image,
        MediaReferenceKind.video => FileType.video,
        MediaReferenceKind.audio => FileType.audio,
      });
      var saved = 0;
      for (final asset in picked) {
        final now = DateTime.now().toUtc();
        final destination =
            folderById(
              folderId,
              collection: LibraryCollection.references,
            )?.storage ??
            storage ??
            effectiveStorage;
        if (destination == LibraryStorage.drive && !googleDriveConnected) {
          throw StateError(
            'Connect Google Drive before importing Drive references.',
          );
        }
        final reference = SavedReference(
          id: 'reference-${now.microsecondsSinceEpoch.toRadixString(36)}-${_idCounter++}',
          name: asset.name,
          kind: kind,
          asset: AssetReference(
            kind: 'remote',
            value: '',
            label: asset.name,
            contentType: asset.mimeType,
            bytes: asset.bytes.length,
          ),
          thumbnailAsset: asset.thumbnailAsset,
          createdAt: now,
          updatedAt: now,
          folderId: folderId,
          storage: destination,
        );
        _apply(
          await (gateway as ReferenceLibraryGateway).saveReference(
            reference,
            source: asset.dataUrl,
          ),
        );
        saved += 1;
      }
      if (saved > 0) {
        showNotice('$saved ${kind.pluralLabel} saved to References.');
      }
    } on Object catch (error) {
      showNotice(_message(error));
    }
  }

  Future<bool> deleteSavedReference(String referenceId) async {
    if (gateway is! ReferenceLibraryGateway) return false;
    try {
      _apply(
        await (gateway as ReferenceLibraryGateway).deleteReference(referenceId),
      );
      showNotice('Saved reference deleted.');
      return true;
    } on Object catch (error) {
      showNotice(_message(error));
      return false;
    }
  }

  List<ReferenceCandidate> generatedReferenceCandidates(
    MediaReferenceKind kind,
  ) {
    if (kind == MediaReferenceKind.audio) return const <ReferenceCandidate>[];
    return generations
        .where(
          (item) =>
              !item.hidden &&
              item.isReady &&
              (item.resultAsset != null || item.resultUrl != null) &&
              (kind == MediaReferenceKind.image ? item.isImage : !item.isImage),
        )
        .map((item) {
          final asset =
              item.resultAsset ??
              AssetReference(
                kind: 'remote',
                value: item.resultUrl!,
                label: item.displayPrompt.trim().isEmpty
                    ? 'Generated ${kind.label.toLowerCase()}'
                    : item.displayPrompt.trim(),
                contentType: item.isImage ? 'image/png' : 'video/mp4',
              );
          return ReferenceCandidate(
            id: item.localId,
            name: item.displayPrompt.trim().isEmpty
                ? 'Generated ${kind.label.toLowerCase()}'
                : item.displayPrompt.trim(),
            kind: kind,
            asset: asset,
            thumbnailAsset: item.isImage ? null : item.thumbnailAsset,
            createdAt: item.createdAt,
            folderId: item.folderId,
            tags: item.tags,
            generated: true,
            storage: item.storage,
          );
        })
        .toList();
  }

  Future<void> addReferenceCandidates(
    MediaReferenceKind kind,
    Iterable<ReferenceCandidate> candidates,
  ) async {
    final available = referenceLimit(kind) - form.referenceCount(kind);
    final selected = candidates
        .where((item) => item.kind == kind)
        .take(available);
    try {
      for (final candidate in selected) {
        PickedAsset? picked;
        Uint8List? thumbnailBytes;
        var source = candidate.asset.isLocal ? '' : candidate.asset.value;
        if (candidate.thumbnailAsset != null) {
          try {
            thumbnailBytes = await gateway.readAsset(candidate.thumbnailAsset!);
          } on Object {
            // The original media can still be selected and make a new frame.
          }
        }
        if (candidate.asset.isLocal) {
          final bytes = await gateway.readAsset(candidate.asset);
          picked = PickedAsset(
            name: candidate.name,
            bytes: bytes,
            mimeType:
                candidate.asset.contentType ??
                _fallbackMimeType(candidate.kind),
            retained: candidate.asset,
            thumbnailAsset: candidate.thumbnailAsset,
            thumbnailBytes: thumbnailBytes,
          );
        }
        form.references = <MediaReferenceDraft>[
          ...form.references,
          MediaReferenceDraft(
            id: _uid(),
            label: candidate.name,
            kind: kind,
            source: source,
            asset: picked,
            retained: candidate.asset,
            thumbnailAsset: _previewForStorage(
              candidate.thumbnailAsset,
              effectiveStorage,
            ),
            thumbnailBytes: thumbnailBytes,
            savedReferenceId: candidate.generated ? null : candidate.id,
          ),
        ];
      }
      _selectCompatibleModel();
      _normalizeFormForModel();
      _invalidateProviderEstimate();
      notifyListeners();
    } on Object catch (error) {
      showNotice(_message(error));
    }
  }

  String _fallbackMimeType(MediaReferenceKind kind) => switch (kind) {
    MediaReferenceKind.image => 'image/png',
    MediaReferenceKind.video => 'video/mp4',
    MediaReferenceKind.audio => 'audio/mpeg',
  };

  void updateForm(void Function(GenerationFormState value) update) {
    update(form);
    _selectCompatibleModel();
    if (form.draft && selectedModel.supportsDraft) form.resolution = 'hd';
    final resolutions = availableResolutions;
    if (!resolutions.any((item) => item.id == form.resolution)) {
      form.resolution = resolutions.first.id;
    }
    final ratios = availableAspectRatios;
    if (!ratios.contains(form.aspectRatio)) {
      form.aspectRatio = ratios.contains('16:9') ? '16:9' : ratios.first;
    }
    if (!selectedModel.supportsAutoDuration) form.autoDuration = false;
    if (form.requiresFixedDuration) form.autoDuration = false;
    form.durationSeconds = _validDuration(form.durationSeconds);
    _invalidateProviderEstimate();
    notifyListeners();
  }

  AppPreferences _preferences({
    AppSection? activeSection,
    LibraryFilter? libraryFilter,
    GenerationViewMode? recentWorkViewMode,
    GenerationViewMode? libraryViewMode,
    LibraryStorage? defaultStorage,
    LibraryStorageFilter? libraryStorageFilter,
    LibraryStorageFilter? referenceStorageFilter,
    String? lastLocalGenerationFolderId,
    bool clearLastLocalGenerationFolder = false,
    String? lastDriveGenerationFolderId,
    bool clearLastDriveGenerationFolder = false,
  }) => AppPreferences(
    activeSection: activeSection ?? section,
    libraryFilter: libraryFilter ?? this.libraryFilter,
    recentWorkViewMode: recentWorkViewMode ?? this.recentWorkViewMode,
    libraryViewMode: libraryViewMode ?? this.libraryViewMode,
    provider: selectedProviderId,
    model: selectedModelId,
    defaultStorage: defaultStorage ?? this.defaultStorage,
    libraryStorageFilter: libraryStorageFilter ?? this.libraryStorageFilter,
    referenceStorageFilter:
        referenceStorageFilter ?? this.referenceStorageFilter,
    generationPlaceholderStyle: generationPlaceholderStyle,
    lastLocalGenerationFolderId: clearLastLocalGenerationFolder
        ? null
        : lastLocalGenerationFolderId ?? this.lastLocalGenerationFolderId,
    lastDriveGenerationFolderId: clearLastDriveGenerationFolder
        ? null
        : lastDriveGenerationFolderId ?? this.lastDriveGenerationFolderId,
  );

  int _validDuration(int value) {
    return selectedDurationRange.normalize(value);
  }

  bool get hasImageGuidance =>
      form.keyframes.isNotEmpty ||
      form.referenceCount(MediaReferenceKind.image) > 0;

  VideoDurationRange get selectedDurationRange => selectedModel
      .durationRangeFor(form.resolution, withImageGuidance: hasImageGuidance);

  List<VideoResolutionDefinition> get availableResolutions {
    final referenceKinds = MediaReferenceKind.values.where(
      (kind) => form.referenceCount(kind) > 0,
    );
    return selectedModel.resolutions
        .where(
          (item) => selectedModel.supportsResolutionForReferences(
            item.id,
            referenceKinds,
          ),
        )
        .toList();
  }

  List<String> get availableAspectRatios =>
      form.referenceTask != MediaReferenceTask.reference &&
          selectedModel.referenceTasks.length > 1
      ? const <String>['auto']
      : selectedModel.aspectRatiosFor(
          form.resolution,
          withFrames: form.keyframes.isNotEmpty,
        );

  void _selectCompatibleModel() {
    bool accepts(VideoModelDefinition model) {
      if (form.mode == VideoMode.t2v &&
          form.keyframes.isEmpty &&
          form.references.isEmpty &&
          (model.maxKeyframes > 0 || model.supportsMediaReferences)) {
        return true;
      }
      if (!model.modes.contains(form.mode)) return false;
      if (!model.referenceTasks.contains(form.referenceTask)) return false;
      if (form.keyframes.length > model.maxKeyframes) return false;
      for (final kind in MediaReferenceKind.values) {
        if (form.referenceCount(kind) > model.maxReferences(kind)) return false;
      }
      return true;
    }

    if (accepts(selectedModel)) return;
    final compatible = selectedProvider.models.where(accepts).firstOrNull;
    if (compatible != null) selectedModelId = compatible.id;
  }

  Future<void> selectProvider(String providerId) async {
    final provider = providerById(providerId);
    if (!providers.any((item) => item.id == provider.id)) return;
    selectedProviderId = provider.id;
    selectedModelId = provider.defaultModel.id;
    _selectCompatibleModel();
    _normalizeFormForModel();
    _invalidateProviderEstimate();
    credits = providerAccounts[provider.id]?.balance;
    notifyListeners();
    try {
      await _savePreferences(_preferences());
      if (provider.requiresApiKey && hasApiKey) unawaited(refreshCredits());
    } on Object catch (error) {
      showNotice(_message(error));
    }
  }

  Future<void> selectModel(String modelId) async {
    selectedModelId = modelById(selectedProviderId, modelId).id;
    _normalizeFormForModel();
    _invalidateProviderEstimate();
    notifyListeners();
    try {
      await _savePreferences(_preferences());
    } on Object catch (error) {
      showNotice(_message(error));
    }
  }

  void _normalizeFormForModel() {
    final model = selectedModel;
    form.upscale = model.isUpscaler;
    if (!model.supportsAutoDuration) form.autoDuration = false;
    if (!model.supportsAudio) form.generateAudio = false;
    if (!model.supportsDraft) form.draft = false;
    if (!model.supportsTimedKeyframes) form.exactTiming = false;
    if (!model.referenceTasks.contains(form.referenceTask)) {
      form.referenceTask = MediaReferenceTask.reference;
    }
    if (!model.supportsSeed) form.seed = null;
    if (model.supportsFrameRate) form.frameRate = form.frameRate.clamp(1, 6);
    final resolutions = availableResolutions;
    if (!resolutions.any((item) => item.id == form.resolution)) {
      form.resolution = resolutions.first.id;
    }
    form.durationSeconds = _validDuration(form.durationSeconds);
    final ratios = availableAspectRatios;
    if (!ratios.contains(form.aspectRatio)) {
      form.aspectRatio = ratios.contains('16:9') ? '16:9' : ratios.first;
    }
  }

  Future<PickedAsset?> _pick({
    required FileType type,
    List<String>? extensions,
  }) async {
    final result = await FilePicker.pickFiles(
      type: type,
      allowedExtensions: extensions,
      withData: true,
    );
    final file = result?.files.firstOrNull;
    if (file == null) return null;
    final bytes = file.bytes;
    if (bytes == null) throw StateError('The selected file could not be read.');
    return PickedAsset(
      name: file.name,
      bytes: bytes,
      mimeType:
          lookupMimeType(file.name, headerBytes: bytes) ??
          'application/octet-stream',
      path: file.path,
    );
  }

  Future<List<PickedAsset>> _pickMany(FileType type) async {
    final result = await FilePicker.pickFiles(
      type: type,
      allowMultiple: true,
      withData: true,
    );
    final assets = <PickedAsset>[];
    for (final file in result?.files ?? const <PlatformFile>[]) {
      final bytes = file.bytes;
      if (bytes == null) {
        throw StateError('A selected file could not be read.');
      }
      assets.add(
        PickedAsset(
          name: file.name,
          bytes: bytes,
          mimeType:
              lookupMimeType(file.name, headerBytes: bytes) ??
              'application/octet-stream',
          path: file.path,
        ),
      );
    }
    return assets;
  }

  /// Pinned frames are unavailable because this model takes frames or media
  /// references, never both, and references are already attached.
  bool get framesBlockedByReferences =>
      referenceModel.framesExclusiveWithReferences &&
      form.references.isNotEmpty;

  /// Media references are unavailable because this model takes frames or
  /// references, never both, and frames are already pinned.
  bool get referencesBlockedByFrames =>
      referenceModel.framesExclusiveWithReferences && form.keyframes.isNotEmpty;

  bool canAddFrame(KeyframeRole role) =>
      !framesBlockedByReferences &&
      form.keyframes.length < referenceModel.maxKeyframes &&
      switch (role) {
        KeyframeRole.start => referenceModel.supportsStartFrame,
        KeyframeRole.middle => referenceModel.supportsTimedKeyframes,
        KeyframeRole.end => referenceModel.supportsEndFrame,
      } &&
      (role == KeyframeRole.middle ||
          !form.keyframes.any((frame) => frame.role == role));

  bool canAddReference(MediaReferenceKind kind) =>
      !referencesBlockedByFrames &&
      form.referenceCount(kind) < referenceLimit(kind) &&
      (selectedModel.maxTotalReferences == null ||
          form.references.length < selectedModel.maxTotalReferences!);

  int referenceLimit(MediaReferenceKind kind) =>
      kind == MediaReferenceKind.video &&
          form.referenceTask != MediaReferenceTask.reference
      ? selectedModel.maxVideoReferences.clamp(0, 1)
      : selectedModel.maxReferences(kind);

  void setReferenceTask(MediaReferenceTask task) {
    if (!selectedModel.referenceTasks.contains(task)) return;
    form.referenceTask = task;
    if (task != MediaReferenceTask.reference) form.aspectRatio = 'auto';
    if (task == MediaReferenceTask.edit) form.autoDuration = true;
    _invalidateProviderEstimate();
    notifyListeners();
  }

  double _suggestedFrameTime(KeyframeRole role) => switch (role) {
    KeyframeRole.start => 0,
    KeyframeRole.end => form.durationSeconds.toDouble(),
    KeyframeRole.middle =>
      form.durationSeconds *
          (form.keyframes
                  .where((frame) => frame.role == KeyframeRole.middle)
                  .length +
              1) /
          (form.keyframes
                  .where((frame) => frame.role == KeyframeRole.middle)
                  .length +
              2),
  };

  void _appendFrame(
    KeyframeRole role, {
    required String label,
    PickedAsset? asset,
  }) {
    if (!canAddFrame(role)) return;
    form.keyframes = <KeyframeDraft>[
      ...form.keyframes,
      KeyframeDraft(
        id: _uid(),
        label: label,
        role: role,
        source: '',
        seconds: _suggestedFrameTime(role),
        asset: asset,
      ),
    ];
    _selectCompatibleModel();
    _normalizeFormForModel();
    if (form.requiresFixedDuration) form.autoDuration = false;
    if (selectedModel.supportsFrameRate) {
      form.frameRate = form.frameRate.clamp(1, 6);
    }
    _invalidateProviderEstimate();
    notifyListeners();
  }

  Future<void> addImageFrame(KeyframeRole role) async {
    if (!canAddFrame(role)) return;
    try {
      final asset = await _pick(type: FileType.image);
      if (asset != null) _appendFrame(role, label: asset.name, asset: asset);
    } on Object catch (error) {
      showNotice(_message(error));
    }
  }

  void addUrlFrame(KeyframeRole role) =>
      _appendFrame(role, label: '${role.label} URL');

  void _appendReference(
    MediaReferenceKind kind, {
    required String label,
    PickedAsset? asset,
  }) {
    if (!canAddReference(kind)) return;
    form.references = <MediaReferenceDraft>[
      ...form.references,
      MediaReferenceDraft(
        id: _uid(),
        label: label,
        kind: kind,
        source: '',
        asset: asset,
      ),
    ];
    _selectCompatibleModel();
    _normalizeFormForModel();
    _invalidateProviderEstimate();
    notifyListeners();
  }

  Future<void> addMediaReferences(MediaReferenceKind kind) async {
    if (!canAddReference(kind)) return;
    try {
      final picked = await _pickMany(switch (kind) {
        MediaReferenceKind.image => FileType.image,
        MediaReferenceKind.video => FileType.video,
        MediaReferenceKind.audio => FileType.audio,
      });
      final available = referenceLimit(kind) - form.referenceCount(kind);
      final totalAvailable = selectedModel.maxTotalReferences == null
          ? available
          : selectedModel.maxTotalReferences! - form.references.length;
      final accepted = available < totalAvailable ? available : totalAvailable;
      for (final asset in picked.take(accepted)) {
        _appendReference(kind, label: asset.name, asset: asset);
      }
      if (picked.length > accepted) {
        final totalLimit = selectedModel.maxTotalReferences;
        showNotice(
          totalLimit != null && totalAvailable <= available
              ? '${selectedModel.label} accepts up to $totalLimit creative references total.'
              : '${selectedModel.label} accepts up to '
                    '${referenceLimit(kind)} ${kind.pluralLabel}.',
        );
      }
    } on Object catch (error) {
      showNotice(_message(error));
    }
  }

  void addUrlReference(MediaReferenceKind kind) =>
      _appendReference(kind, label: '${kind.label} URL');

  void updateReference(String id, String source) {
    form.references = form.references.map((item) {
      if (item.id != id) return item;
      return item.copyWith(
        source: source,
        label: source.trim().isNotEmpty ? source : null,
        clearThumbnailAsset: true,
        clearThumbnailBytes: true,
      );
    }).toList();
    _invalidateProviderEstimate();
    notifyListeners();
  }

  void rememberReferenceThumbnail(String id, Uint8List bytes) {
    form.references = form.references.map((item) {
      if (item.id != id || item.thumbnailBytes != null) return item;
      return item.copyWith(thumbnailBytes: bytes);
    }).toList();
  }

  void rememberVideoSourceThumbnail(Uint8List bytes) {
    final asset = form.videoAsset;
    if (asset != null) {
      if (asset.thumbnailBytes != null) return;
      form.videoAsset = asset.copyWithThumbnail(thumbnailBytes: bytes);
      return;
    }
    form.videoThumbnailBytes ??= bytes;
  }

  void rememberVideoSourceMetadata(VideoSourceMetadata metadata) {
    if (!metadata.isUsable ||
        form.videoMetadata?.signature == metadata.signature) {
      return;
    }
    form.videoMetadata = metadata;
    _invalidateProviderEstimate();
    notifyListeners();
  }

  void updateVideoSourceUrl(String source) {
    updateForm((value) {
      if (value.videoUrl != source) {
        value.videoThumbnailBytes = null;
        value.videoMetadata = null;
      }
      value.videoUrl = source;
    });
  }

  void removeReference(String id) {
    final removed = form.references
        .where((reference) => reference.id == id)
        .firstOrNull;
    if (removed == null) return;
    final number =
        form.references
            .takeWhile((reference) => reference.id != id)
            .where((reference) => reference.kind == removed.kind)
            .length +
        1;
    form.prompt = detachReferenceFromPrompt(
      form.prompt,
      kind: removed.kind,
      number: number,
      label: removed.label,
    );
    form.references = form.references.where((item) => item.id != id).toList();
    _selectCompatibleModel();
    _normalizeFormForModel();
    _invalidateProviderEstimate();
    notifyListeners();
  }

  void setExactTiming(bool value) {
    form.exactTiming = value;
    if (value) {
      form.autoDuration = false;
      form.keyframes = form.keyframes.map((frame) {
        if (frame.role == KeyframeRole.start) {
          return frame.copyWith(seconds: 0);
        }
        if (frame.role == KeyframeRole.end) {
          return frame.copyWith(seconds: form.durationSeconds.toDouble());
        }
        return frame;
      }).toList();
    }
    _invalidateProviderEstimate();
    notifyListeners();
  }

  void setDurationSeconds(int value) {
    form.durationSeconds = _validDuration(value);
    form.keyframes = form.keyframes.map((frame) {
      return frame.role == KeyframeRole.end
          ? frame.copyWith(seconds: form.durationSeconds.toDouble())
          : frame;
    }).toList();
    _invalidateProviderEstimate();
    notifyListeners();
  }

  void setAutoDuration(bool value) {
    final model = selectedModel;
    if (value && (!model.supportsAutoDuration || form.requiresFixedDuration)) {
      return;
    }
    if (!value && form.referenceTask == MediaReferenceTask.edit) return;
    if (form.autoDuration == value) return;
    form.autoDuration = value;
    _invalidateProviderEstimate();
    notifyListeners();
  }

  void setFrameRate(int value) {
    form.frameRate = value.clamp(1, 6);
    notifyListeners();
  }

  void setSeed(int? value) {
    form.seed = value;
    notifyListeners();
  }

  List<KeyframeDraft> _orderedFrames() {
    final frames = List<KeyframeDraft>.from(form.keyframes);
    if (form.usesTimedKeyframes) {
      frames.sort((a, b) => a.seconds.compareTo(b.seconds));
      return frames;
    }
    final indexed = frames.asMap().entries.toList();
    int rank(KeyframeRole role) => switch (role) {
      KeyframeRole.start => 0,
      KeyframeRole.middle => 1,
      KeyframeRole.end => 2,
    };
    indexed.sort((a, b) {
      final roleOrder = rank(a.value.role).compareTo(rank(b.value.role));
      return roleOrder == 0 ? a.key.compareTo(b.key) : roleOrder;
    });
    return indexed.map((entry) => entry.value).toList();
  }

  void updateFrame(String id, {String? source, double? seconds}) {
    form.keyframes = form.keyframes.map((frame) {
      if (frame.id != id) return frame;
      return frame.copyWith(
        source: source,
        label: source?.trim().isNotEmpty == true ? source : null,
        seconds: seconds,
      );
    }).toList();
    _invalidateProviderEstimate();
    notifyListeners();
  }

  void removeFrame(String id) {
    form.keyframes = form.keyframes.where((frame) => frame.id != id).toList();
    _selectCompatibleModel();
    _normalizeFormForModel();
    _invalidateProviderEstimate();
    notifyListeners();
  }

  Future<void> pickVideo() async {
    try {
      final asset = await _pick(type: FileType.video);
      if (asset != null) {
        updateForm((value) {
          value.videoAsset = asset;
          value.videoThumbnailBytes = null;
          value.videoMetadata = null;
        });
      }
    } on Object catch (error) {
      showNotice(_message(error));
    }
  }

  Future<void> pickDraft() async {
    try {
      final asset = await _pick(type: FileType.any);
      if (asset != null) updateForm((value) => value.draftAsset = asset);
    } on Object catch (error) {
      showNotice(_message(error));
    }
  }

  String? validate() {
    final provider = selectedProvider;
    final model = selectedModel;
    if (provider.requiresApiKey && !hasApiKey) {
      return 'Add your ${provider.name} API key before generating.';
    }
    if (form.mode == VideoMode.t2v && !model.modes.contains(VideoMode.t2v)) {
      if (model.supportsMediaReferences) {
        return 'Add at least one image, video, or audio reference for ${model.label}.';
      }
      if (model.maxKeyframes > 0) {
        return 'Add a first frame for ${model.label}.';
      }
    }
    if (!model.modes.contains(form.mode)) {
      return '${model.label} does not support ${form.mode.label.toLowerCase()}. Choose a compatible model or remove the attached source.';
    }
    if (form.mode != VideoMode.draftEnhance &&
        form.mode != VideoMode.upscale &&
        form.prompt.trim().isEmpty) {
      return model.outputKind == GenerationOutputKind.image
          ? 'Describe the image you want to make.'
          : 'Describe the animation you want to make.';
    }
    if (form.mode == VideoMode.i2v) {
      if (form.keyframes.isEmpty && form.references.isEmpty) {
        return 'Add at least one supported frame or reference.';
      }
      if (model.framesExclusiveWithReferences &&
          form.keyframes.isNotEmpty &&
          form.references.isNotEmpty) {
        return '${model.label} takes pinned frames or creative references, '
            'not both. Remove one side before generating.';
      }
      if (form.keyframes.length > model.maxKeyframes) {
        return model.maxKeyframes == 0
            ? '${model.label} uses media references instead of keyframes.'
            : '${model.label} accepts up to ${model.maxKeyframes} keyframes.';
      }
      if (form.keyframes.any((frame) => frame.requestSource.isEmpty)) {
        return 'Every keyframe needs an image or URL.';
      }
      if (form.keyframes.any(
        (frame) => switch (frame.role) {
          KeyframeRole.start => !model.supportsStartFrame,
          KeyframeRole.middle => !model.supportsTimedKeyframes,
          KeyframeRole.end => !model.supportsEndFrame,
        },
      )) {
        return '${model.label} does not support this keyframe layout.';
      }
      for (final kind in MediaReferenceKind.values) {
        final count = form.referenceCount(kind);
        final maximum = referenceLimit(kind);
        if (count > maximum) {
          return maximum == 0
              ? '${model.label} does not accept reference ${kind.pluralLabel}.'
              : '${model.label} accepts up to $maximum ${kind.pluralLabel}.';
        }
      }
      final totalLimit = model.maxTotalReferences;
      if (totalLimit != null && form.references.length > totalLimit) {
        return '${model.label} accepts up to $totalLimit creative references total.';
      }
      if (form.references.any((item) => item.requestSource.isEmpty)) {
        return 'Every reference needs an upload or HTTPS URL.';
      }
      if (form.referenceTask != MediaReferenceTask.reference) {
        if (form.referenceCount(MediaReferenceKind.video) != 1) {
          return '${form.referenceTask.label} needs exactly one reference video.';
        }
        if (form.aspectRatio != 'auto') {
          return '${form.referenceTask.label} preserves the reference video’s aspect ratio.';
        }
        if (form.referenceTask == MediaReferenceTask.edit &&
            !form.autoDuration) {
          return 'Video editing must leave duration on Auto.';
        }
      }
      if (model.requiresVisualReferenceForAudio &&
          form.referenceCount(MediaReferenceKind.audio) > 0 &&
          form.keyframes.isEmpty &&
          form.referenceCount(MediaReferenceKind.image) == 0 &&
          form.referenceCount(MediaReferenceKind.video) == 0) {
        return '${model.label} needs an image or video when audio references are attached.';
      }
      if (provider.isLocal &&
          form.keyframes.any(
            (frame) => frame.asset == null && frame.retained?.isLocal != true,
          )) {
        return 'On-device reference images must be uploaded from this device.';
      }
      if (form.requiresFixedDuration && form.autoDuration) {
        return 'Choose a fixed duration for this keyframe layout.';
      }
      if (form.usesTimedKeyframes) {
        final maximumDuration = model.maxDurationFor(
          form.resolution,
          withImageGuidance: hasImageGuidance,
        );
        final seconds = form.keyframes.map((frame) => frame.seconds).toList();
        if (seconds.any((value) => value < 0 || value > maximumDuration)) {
          return 'Keyframe timing must stay between 0 and $maximumDuration seconds.';
        }
        if (seconds.toSet().length != seconds.length) {
          return 'Each timed keyframe needs a unique time.';
        }
      }
    }
    if (form.mode == VideoMode.v2v &&
        form.videoAsset == null &&
        form.videoUrl.trim().isEmpty) {
      return 'Add the video you want ${model.label} to continue.';
    }
    if (form.mode == VideoMode.upscale) {
      if (form.videoAsset == null && form.videoUrl.trim().isEmpty) {
        return 'Add the video you want to upscale.';
      }
      final asset = form.videoAsset;
      if (asset != null) {
        final mp4 =
            asset.name.toLowerCase().endsWith('.mp4') ||
            asset.mimeType.toLowerCase().contains('mp4');
        if (!mp4) {
          return 'FLUX Video Upscale accepts local uploads as MP4 files.';
        }
        if (asset.bytes.length > 50 * 1024 * 1024) {
          return 'FLUX Video Upscale accepts source files up to 50 MB.';
        }
      }
      if (asset == null) {
        final source = Uri.tryParse(form.videoUrl.trim());
        if (source == null ||
            (source.scheme != 'http' && source.scheme != 'https')) {
          return 'Use an HTTP(S) URL for the video you want to upscale.';
        }
      }
      final metadata = form.videoMetadata;
      if (metadata != null) {
        if (metadata.durationSeconds > 20.001) {
          return 'FLUX Video Upscale accepts source clips up to 20 seconds.';
        }
        final longest = metadata.width > metadata.height
            ? metadata.width
            : metadata.height;
        final shortest = metadata.width < metadata.height
            ? metadata.width
            : metadata.height;
        if (longest > 2560 || shortest > 1440) {
          return 'FLUX Video Upscale accepts source resolution up to 2560×1440.';
        }
      }
      if (form.upscaleFactor < 1.5 || form.upscaleFactor > 3) {
        return 'Choose an upscale factor between 1.5× and 3×.';
      }
    }
    if (form.mode == VideoMode.draftEnhance &&
        form.draftAsset == null &&
        form.draftUrl.trim().isEmpty) {
      return 'Add a draft cache bundle or URL.';
    }
    if (form.autoDuration && !model.supportsAutoDuration) {
      return '${model.label} needs a fixed duration.';
    }
    return null;
  }

  Map<String, Object?> _buildInput() {
    if (form.mode == VideoMode.upscale) {
      final prompt = form.prompt.trim();
      return <String, Object?>{
        'input_video': form.videoAsset?.dataUrl ?? form.videoUrl.trim(),
        'upscale_factor': form.upscaleFactor,
        'creativity': form.upscaleCreativity,
        if (prompt.isNotEmpty) 'prompt': prompt,
        'safety_tolerance': form.safetyTolerance,
      };
    }
    if (form.mode == VideoMode.draftEnhance) {
      return <String, Object?>{
        'mode': 'draft_enhance',
        'draft_cache': form.draftAsset?.dataUrl ?? form.draftUrl.trim(),
        'resolution': form.resolution,
        'safety_tolerance': form.safetyTolerance,
      };
    }
    final common = <String, Object?>{
      'prompt': form.prompt.trim(),
      'aspect_ratio': form.aspectRatio,
      'duration': form.duration,
      'resolution': form.resolution,
      'version': 'latest',
      'generate_audio': form.generateAudio,
      'safety_tolerance': form.safetyTolerance,
      'draft': form.draft,
      if (selectedModel.supportsFrameRate) 'frame_rate': form.frameRate,
      if (selectedModel.supportsSeed && form.seed != null) 'seed': form.seed,
    };
    if (form.mode == VideoMode.i2v) {
      final frames = form.usesTimedKeyframes
          ? _orderedFrames()
                .map<Object?>(
                  (frame) => <Object?>[frame.seconds, frame.requestSource],
                )
                .toList()
          : _orderedFrames()
                .map<Object?>((frame) => frame.requestSource)
                .toList();
      final references = <MediaReferenceKind, List<String>>{
        for (final kind in MediaReferenceKind.values)
          kind: form.references
              .where((item) => item.kind == kind)
              .map((item) => item.requestSource)
              .toList(),
      };
      return <String, Object?>{
        ...common,
        'mode': 'i2v',
        if (selectedModel.referenceTasks.length > 1)
          'reference_task': form.referenceTask.name,
        if (frames.isNotEmpty) 'keyframes': frames,
        if (references[MediaReferenceKind.image]!.isNotEmpty)
          'reference_images': references[MediaReferenceKind.image]!,
        if (references[MediaReferenceKind.video]!.isNotEmpty)
          'reference_videos': references[MediaReferenceKind.video]!,
        if (references[MediaReferenceKind.audio]!.isNotEmpty)
          'reference_audios': references[MediaReferenceKind.audio]!,
      };
    }
    if (form.mode == VideoMode.v2v) {
      return <String, Object?>{
        ...common,
        'mode': 'v2v',
        'start_video': form.videoAsset?.dataUrl ?? form.videoUrl.trim(),
      };
    }
    return <String, Object?>{...common, 'mode': 't2v'};
  }

  @visibleForTesting
  Map<String, Object?> buildInputForTesting() => _buildInput();

  String _uid() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}-${(_idCounter++).toRadixString(16)}';

  Future<void> submit() async {
    final problem = validate();
    if (problem != null) {
      showNotice(problem);
      if (selectedProvider.requiresApiKey && !hasApiKey) {
        unawaited(navigate(AppSection.providers));
      }
      return;
    }
    if (!canUseDefaultStorage) {
      showNotice(
        'Connect Google Drive before generating to your Drive library.',
      );
      unawaited(navigate(AppSection.settings));
      return;
    }
    if (selectedProvider.requiresApiKey && !await refreshCredits()) return;
    await refreshProviderEstimate();
    final now = DateTime.now().toUtc();
    final estimate = currentEstimate;
    final referenceThumbnailBytes = form.references
        .map((item) => item.thumbnailBytes ?? item.asset?.thumbnailBytes)
        .toList(growable: false);
    final sourceThumbnailBytes =
        form.videoAsset?.thumbnailBytes ?? form.videoThumbnailBytes;
    var pending = Generation(
      localId: _uid(),
      provider: selectedProviderId,
      model: selectedModel.id,
      canonicalModelId: selectedModel.canonicalId,
      billingUnit: selectedProvider.isLocal
          ? 'local'
          : selectedProviderId == 'bfl' || selectedProviderId == 'artcraft'
          ? 'credits'
          : 'usd',
      outputKind: selectedModel.outputKind,
      status: 'submitting',
      progress: 0,
      prompt: form.mode == VideoMode.draftEnhance
          ? 'Enhance saved FLUX 3 draft'
          : form.prompt.trim(),
      mode: form.mode,
      config: currentConfig,
      createdAt: now,
      updatedAt: now,
      estimatedCreditsMin: estimate.providerUnitsMinimum ?? estimate.minimumUsd,
      estimatedCreditsMax: estimate.providerUnitsMaximum ?? estimate.maximumUsd,
      estimateBasis: estimate.basis,
      quotedCostUsdMin: estimate.minimumUsd,
      quotedCostUsdMax: estimate.maximumUsd,
      folderId: selectedGenerationFolderId,
      storage: effectiveStorage,
    );
    final current = snapshot;
    if (current != null) {
      snapshot = LocalSnapshot(
        generations: <Generation>[pending, ...current.generations],
        preferences: current.preferences,
        hasApiKey: current.hasApiKey,
        connectedProviders: current.connectedProviders,
        availableProviders: current.availableProviders,
        folders: current.folders,
        savedReferences: current.savedReferences,
        storage: current.storage,
        settingsVault: current.settingsVault,
      );
    }
    submitting = true;
    notifyListeners();
    showNotice(
      form.mode == VideoMode.upscale
          ? 'Upscale sent. Clawnsole will keep an eye on it.'
          : 'Generation sent. Clawnsole will keep an eye on it.',
    );
    try {
      pending = await gateway.submit(
        GenerationSubmission(record: pending, input: _buildInput()),
      );
      _replaceInMemory(pending);
      final retainedReferences =
          pending.config.references ?? const <MediaReferenceLabel>[];
      for (
        var index = 0;
        index < retainedReferences.length &&
            index < referenceThumbnailBytes.length;
        index += 1
      ) {
        final source = retainedReferences[index].source;
        final thumbnail = referenceThumbnailBytes[index];
        if (source != null && thumbnail != null) {
          await cacheGenerationInputPreview(pending, source, thumbnail);
        }
      }
      if (pending.config.source != null && sourceThumbnailBytes != null) {
        await cacheGenerationInputPreview(
          pending,
          pending.config.source!,
          sourceThumbnailBytes,
        );
      }
      if (pending.creditsAfter != null) credits = pending.creditsAfter;
    } on Object catch (error) {
      await _invalidateRejectedApiKey(error, showNoticeOnFailure: true);
      try {
        _apply(await gateway.load());
      } on Object {
        pending = pending.copyWith(
          status: 'Error',
          error: _message(error),
          updatedAt: DateTime.now().toUtc(),
        );
        _replaceInMemory(pending);
      }
      showNotice(_message(error));
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  void _replaceInMemory(Generation generation) {
    final current = snapshot;
    if (current == null) return;
    final items = List<Generation>.from(current.generations);
    final index = items.indexWhere(
      (item) => item.localId == generation.localId,
    );
    if (index >= 0) {
      final existing = items[index];
      items[index] = generation.copyWith(
        folderId: existing.folderId,
        clearFolder: existing.folderId == null,
        tags: existing.tags,
        favorite: existing.favorite,
        hidden: existing.hidden,
        storage: existing.storage,
      );
    } else {
      items.insert(0, generation);
    }
    snapshot = LocalSnapshot(
      generations: items,
      preferences: current.preferences,
      hasApiKey: current.hasApiKey,
      connectedProviders: current.connectedProviders,
      availableProviders: current.availableProviders,
      folders: current.folders,
      savedReferences: current.savedReferences,
      storage: current.storage,
      settingsVault: current.settingsVault,
    );
    notifyListeners();
  }

  Future<void> pollWorking() async {
    if (_polling || !hasAnyApiKey) return;
    final now = DateTime.now().toUtc();
    final working = generations.where((item) {
      if (!item.canCheckStatus || _statusChecks.contains(item.localId)) {
        return false;
      }
      if (!hasApiKeyFor(item.provider)) return false;
      final needsRetention =
          item.isReady &&
          item.resultAsset == null &&
          !_retentionAttempts.contains(item.localId);
      return needsRetention || (item.isWorking && item.isStatusCheckDue(now));
    }).toList();
    if (working.isEmpty) return;
    _polling = true;
    try {
      for (final item in working) {
        if (item.isReady) _retentionAttempts.add(item.localId);
        try {
          final updated = await gateway.poll(item);
          _replaceInMemory(updated);
          if (await _invalidateRejectedApiKey(
            updated.lastProviderStatusCode,
            showNoticeOnFailure: true,
          )) {
            break;
          }
          if (updated.isReady) {
            showNotice('Your film is ready to watch and save.');
          } else if (!item.isFailed && updated.isFailed) {
            showNotice(
              'Generation needs attention: ${updated.error ?? updated.statusLabel}',
            );
          }
        } on Object catch (error) {
          if (await _invalidateRejectedApiKey(
            error,
            showNoticeOnFailure: true,
          )) {
            break;
          }
          final message = _message(error);
          if (!RegExp(
            '429|active request',
            caseSensitive: false,
          ).hasMatch(message)) {
            _replaceInMemory(
              item.copyWith(
                lastCheckedAt: DateTime.now().toUtc(),
                statusCheckCount: item.statusCheckCount + 1,
                consecutiveCheckFailures: item.consecutiveCheckFailures + 1,
                lastCheckError: message,
                updatedAt: DateTime.now().toUtc(),
              ),
            );
          }
        }
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> checkStatus(Generation item) async {
    if (!item.canCheckStatus) {
      showNotice('This generation has no provider status URL to check.');
      return;
    }
    if (!_statusChecks.add(item.localId)) return;
    notifyListeners();
    try {
      final updated = await gateway.poll(item);
      _replaceInMemory(updated);
      if (await _invalidateRejectedApiKey(
        updated.lastProviderStatusCode,
        showNoticeOnFailure: true,
      )) {
        return;
      }
      if (updated.lastCheckError != null) {
        showNotice('Status check failed: ${updated.lastCheckError}');
      } else if (updated.isReady) {
        showNotice(
          '${providerNameForHistory(item.provider)} reports that this film is ready.',
        );
      } else if (updated.isFailed) {
        showNotice(
          updated.error ??
              '${providerNameForHistory(item.provider)} reports ${updated.statusLabel}.',
        );
      } else {
        showNotice(
          '${providerNameForHistory(item.provider)} reports ${updated.statusLabel.toLowerCase()}.',
        );
      }
    } on Object catch (error) {
      if (await _invalidateRejectedApiKey(error, showNoticeOnFailure: true)) {
        return;
      }
      showNotice('Status check failed: ${_message(error)}');
    } finally {
      _statusChecks.remove(item.localId);
      notifyListeners();
    }
  }

  bool _isApiKeyRejection(Object? error) {
    final status = error is int
        ? error
        : error == null
        ? null
        : providerHttpStatus(error);
    return status == 401 || status == 403;
  }

  Future<bool> _invalidateRejectedApiKey(
    Object? error, {
    required bool showNoticeOnFailure,
  }) async {
    if (!_isApiKeyRejection(error)) return false;
    _apply(await gateway.load());
    credits = null;
    if (!hasApiKey) {
      creditError =
          '${selectedProvider.name} rejected the active API key. Add another key.';
      if (showNoticeOnFailure) {
        showNotice(creditError!);
        unawaited(navigate(AppSection.providers));
      }
    }
    return true;
  }

  Future<bool> refreshCredits() {
    final running = _creditRefreshFuture;
    if (running != null) return running;
    late Future<bool> tracked;
    tracked = _refreshCredits().whenComplete(() {
      if (identical(_creditRefreshFuture, tracked)) {
        _creditRefreshFuture = null;
      }
    });
    _creditRefreshFuture = tracked;
    return tracked;
  }

  Future<bool> _refreshCredits() async {
    if (!selectedProvider.requiresApiKey) return true;
    if (!hasApiKey) return false;
    refreshingCredits = true;
    creditError = null;
    notifyListeners();
    try {
      for (var attempt = 0; attempt < 2 && hasApiKey; attempt += 1) {
        try {
          final providerGateway = gateway is ProviderGateway
              ? gateway as ProviderGateway
              : null;
          final account = providerGateway == null
              ? ProviderAccountStatus(
                  provider: 'bfl',
                  balance: await gateway.getCredits(),
                  currency: 'credits',
                )
              : await providerGateway.getProviderAccount(selectedProviderId);
          providerAccounts[selectedProviderId] = account;
          credits = account.balance;
          creditError = null;
          return true;
        } on Object catch (error) {
          if (!_isApiKeyRejection(error)) {
            creditError = _message(error);
            return true;
          }
          await _invalidateRejectedApiKey(error, showNoticeOnFailure: false);
        }
      }
      creditError =
          '${selectedProvider.name} rejected the active API key. Add another key.';
      showNotice(creditError!);
      unawaited(navigate(AppSection.providers));
      return false;
    } finally {
      refreshingCredits = false;
      notifyListeners();
    }
  }

  Future<double> verifyKey(String candidate) async {
    final account = await verifyProviderKey('bfl', candidate);
    return account.balance ?? 0;
  }

  Future<ProviderAccountStatus> verifyProviderKey(
    String provider,
    String candidate,
  ) async {
    final clean = candidate.trim();
    try {
      if (gateway is ProviderGateway) {
        return await (gateway as ProviderGateway).verifyProviderKey(
          provider,
          clean.isEmpty ? null : clean,
        );
      }
      if (provider != 'bfl') {
        throw StateError('This gateway does not support $provider.');
      }
      return ProviderAccountStatus(
        provider: 'bfl',
        balance: await gateway.verifyKey(clean.isEmpty ? null : clean),
        currency: 'credits',
      );
    } on Object catch (error) {
      if (clean.isEmpty) {
        await _invalidateRejectedApiKey(error, showNoticeOnFailure: true);
      }
      rethrow;
    }
  }

  Future<void> saveKey(String value) async {
    await saveProviderKey('bfl', value);
  }

  Future<void> saveProviderKey(String provider, String value) async {
    final clean = value.trim();
    if (clean.isEmpty) throw StateError('An API key is required.');
    final account = await verifyProviderKey(provider, clean);
    providerAccounts[provider] = account;
    if (provider == selectedProviderId) credits = account.balance;
    if (gateway is ProviderGateway) {
      _apply(
        await (gateway as ProviderGateway).setProviderApiKey(provider, clean),
      );
    } else {
      if (provider != 'bfl') {
        throw StateError('This gateway does not support $provider.');
      }
      _apply(await gateway.setApiKey(clean));
    }
    creditError = null;
    showNotice(
      '${providerById(provider).name} key verified and saved locally.',
    );
  }

  Future<void> removeKey() async {
    await removeProviderKey('bfl');
  }

  Future<void> removeProviderKey(String provider) async {
    if (gateway is ProviderGateway) {
      _apply(await (gateway as ProviderGateway).clearProviderApiKey(provider));
    } else {
      if (provider != 'bfl') {
        throw StateError('This gateway does not support $provider.');
      }
      _apply(await gateway.clearApiKey());
    }
    providerAccounts.remove(provider);
    if (provider == selectedProviderId) credits = null;
    showNotice(
      '${providerById(provider).name} access removed from this device.',
    );
  }

  Future<void> refreshProviderModels(String provider) async {
    try {
      final models = gateway is ProviderGateway
          ? await (gateway as ProviderGateway).listProviderModels(provider)
          : publishedProviderPrices(provider);
      if (models.isNotEmpty) providerPrices[provider] = models;
      _invalidateProviderEstimate();
      notifyListeners();
    } on Object {
      // Published prices remain visible if a live catalog is unavailable.
    }
  }

  void _invalidateProviderEstimate() {
    final signature = jsonEncode(<String, Object?>{
      'provider': selectedProviderId,
      'model': selectedModel.id,
      'mode': form.mode.wireValue,
      'prompt': form.prompt.trim(),
      'aspectRatio': form.aspectRatio,
      'duration': form.duration,
      'resolution': form.resolution,
      'generateAudio': form.generateAudio,
      'safetyTolerance': form.safetyTolerance,
      'draft': form.draft,
      'exactTiming': form.exactTiming,
      'referenceTask': form.referenceTask.name,
      'references': form.references
          .map((reference) => reference.kind.name)
          .toList(),
      'keyframes': form.keyframes
          .map(
            (frame) => <String, Object?>{
              'role': frame.role.name,
              if (form.usesTimedKeyframes) 'seconds': frame.seconds,
            },
          )
          .toList(),
      'frameRate': form.frameRate,
      'upscaleFactor': form.upscaleFactor,
      'upscaleCreativity': form.upscaleCreativity,
      'hasVideoSource':
          form.videoAsset != null || form.videoUrl.trim().isNotEmpty,
      'videoMetadata': form.videoMetadata?.signature,
    });
    if (_estimateSignature == signature) return;
    _estimateSignature = signature;
    _estimateTimer?.cancel();
    _estimateRevision += 1;
    _liveEstimate = null;
    _liveEstimateRevision = null;
    if (selectedProviderId != 'artcraft' || gateway is! ProviderGateway) return;
    _estimateTimer = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(refreshProviderEstimate()),
    );
  }

  Future<void> refreshProviderEstimate() async {
    _estimateTimer?.cancel();
    if (selectedProviderId != 'artcraft' || gateway is! ProviderGateway) return;
    final revision = _estimateRevision;
    final input = <String, Object?>{
      'prompt': form.prompt.trim(),
      'aspect_ratio': form.aspectRatio,
      'duration': form.duration,
      'resolution': form.resolution,
      'generate_audio': form.generateAudio,
      'safety_tolerance': form.safetyTolerance,
      'mode': form.mode.wireValue,
      'draft': form.draft,
      'exact_timing': form.exactTiming,
      'frame_rate': form.frameRate,
      'reference_task': form.referenceTask.name,
      'reference_count': form.references.length,
      'reference_types': form.references
          .map((reference) => reference.kind.name)
          .toList(),
      'keyframe_count': form.keyframes.length,
      'keyframes': form.keyframes
          .map(
            (frame) => <String, Object?>{
              'role': frame.role.name,
              if (form.usesTimedKeyframes) 'seconds': frame.seconds,
            },
          )
          .toList(),
      'upscale_factor': form.upscaleFactor,
      'creativity': form.upscaleCreativity,
      if (form.videoMetadata != null) ...<String, Object?>{
        'source_width': form.videoMetadata!.width,
        'source_height': form.videoMetadata!.height,
        'source_duration': form.videoMetadata!.durationSeconds,
      },
    };
    try {
      final estimate = await (gateway as ProviderGateway).quoteProviderCost(
        selectedProviderId,
        selectedModel.id,
        input,
      );
      if (revision != _estimateRevision || estimate == null) return;
      _liveEstimate = estimate;
      _liveEstimateRevision = revision;
      notifyListeners();
    } on Object {
      // The published provider-unit estimate remains available if a live
      // quote is temporarily unavailable.
    }
  }

  Future<void> deleteGeneration(String localId) async {
    _apply(await gateway.deleteGeneration(localId));
    showNotice('Generation record removed.');
  }

  Future<void> clearHistory() async {
    _apply(await gateway.clearHistory());
    showNotice('Generation history cleared.');
  }

  Future<void> clearPreferences() async {
    _apply(await gateway.clearPreferences(), restorePreferences: true);
    showNotice('Saved preferences reset.');
  }

  Future<void> clearAll() async {
    _apply(await gateway.clearAll(), restorePreferences: true);
    credits = null;
    showNotice(
      supportsGoogleDrive
          ? supportsLocalLibrary
                ? 'Clawnsole’s Local and Drive data plus device keys were removed.'
                : 'Clawnsole’s Drive data plus device keys were removed.'
          : 'Clawnsole’s local data was removed.',
    );
  }

  Future<void> connectGoogleDrive(String folderName) async {
    if (gateway is! GoogleDriveGateway || googleDriveBusy) return;
    googleDriveBusy = true;
    notifyListeners();
    try {
      _apply(
        await (gateway as GoogleDriveGateway).connectGoogleDrive(folderName),
        restorePreferences: true,
      );
      showNotice('Google Drive connected and synced.');
    } on Object catch (error) {
      showNotice(_message(error));
    } finally {
      googleDriveBusy = false;
      notifyListeners();
    }
  }

  Future<void> disconnectGoogleDrive() async {
    if (gateway is! GoogleDriveGateway || googleDriveBusy) return;
    googleDriveBusy = true;
    notifyListeners();
    try {
      _apply(
        await (gateway as GoogleDriveGateway).disconnectGoogleDrive(),
        restorePreferences: true,
      );
      showNotice('Drive disconnected on this device. Cloud files were kept.');
    } on Object catch (error) {
      showNotice(_message(error));
    } finally {
      googleDriveBusy = false;
      notifyListeners();
    }
  }

  /// Quietly reattaches a previously connected Drive library, typically at
  /// startup: the companion and shell hold Drive sessions per process, so
  /// without this every launch would hide Drive work until a manual refresh.
  /// Failures stay silent — Settings still offers the interactive refresh.
  Future<void> resumeGoogleDrive() async {
    if (gateway is! GoogleDriveGateway || googleDriveBusy) return;
    if (googleDriveConnected || !googleDriveConnection.isConfigured) return;
    googleDriveBusy = true;
    notifyListeners();
    try {
      final value = await (gateway as GoogleDriveGateway).resumeGoogleDrive();
      if (value != null) _apply(value);
    } on Object {
      // The resume contract never throws, but a quiet startup must survive
      // an unexpected error without surfacing a notice.
    } finally {
      googleDriveBusy = false;
      notifyListeners();
    }
  }

  Future<void> refreshGoogleDrive() async {
    if (gateway is! GoogleDriveGateway || googleDriveBusy) return;
    googleDriveBusy = true;
    notifyListeners();
    try {
      _apply(
        await (gateway as GoogleDriveGateway).refreshGoogleDrive(),
        restorePreferences: true,
      );
      showNotice('Google Drive data refreshed.');
    } on Object catch (error) {
      showNotice(_message(error));
    } finally {
      googleDriveBusy = false;
      notifyListeners();
    }
  }

  Future<String?> setupSettingsVault(String passphrase) async {
    if (gateway is! SettingsVaultGateway || settingsVaultBusy) return null;
    settingsVaultBusy = true;
    notifyListeners();
    try {
      final result = await (gateway as SettingsVaultGateway).setupSettingsVault(
        passphrase,
      );
      _apply(result.snapshot, restorePreferences: true);
      showNotice('Encrypted settings sync is ready.');
      return result.recoveryCode;
    } on Object catch (error) {
      showNotice(_message(error));
      return null;
    } finally {
      settingsVaultBusy = false;
      notifyListeners();
    }
  }

  Future<bool> unlockSettingsVault(String passphrase) async =>
      _runSettingsVaultAction(
        () => (gateway as SettingsVaultGateway).unlockSettingsVault(passphrase),
        'Encrypted settings unlocked and synced.',
      );

  Future<bool> recoverSettingsVault(String recoveryCode) async =>
      _runSettingsVaultAction(
        () => (gateway as SettingsVaultGateway).recoverSettingsVault(
          recoveryCode,
        ),
        'Recovery code accepted. Encrypted settings are synced.',
      );

  Future<bool> syncSettingsVault() async => _runSettingsVaultAction(
    () => (gateway as SettingsVaultGateway).syncSettingsVault(),
    'Encrypted settings synced.',
  );

  Future<bool> changeSettingsVaultPassphrase(String passphrase) async =>
      _runSettingsVaultAction(
        () => (gateway as SettingsVaultGateway).changeSettingsVaultPassphrase(
          passphrase,
        ),
        'Sync passphrase changed.',
      );

  Future<bool> forgetSettingsVaultUnlock() async => _runSettingsVaultAction(
    () => (gateway as SettingsVaultGateway).forgetSettingsVaultUnlock(),
    'This device forgot the vault unlock. Local provider keys were kept.',
  );

  Future<bool> _runSettingsVaultAction(
    Future<LocalSnapshot> Function() action,
    String success,
  ) async {
    if (gateway is! SettingsVaultGateway || settingsVaultBusy) return false;
    settingsVaultBusy = true;
    notifyListeners();
    try {
      _apply(await action(), restorePreferences: true);
      showNotice(success);
      return true;
    } on Object catch (error) {
      showNotice(_message(error));
      return false;
    } finally {
      settingsVaultBusy = false;
      notifyListeners();
    }
  }

  Future<void> copyLocalLibraryToGoogleDrive({
    Set<String> generationIds = const <String>{},
    Set<String> referenceIds = const <String>{},
  }) async {
    if (gateway is! GoogleDriveGateway) return;
    if (!googleDriveConnected) {
      showNotice('Connect Google Drive before copying local items.');
      return;
    }
    final bulk = generationIds.isEmpty && referenceIds.isEmpty;
    if (bulk && googleDriveBusy) return;
    if (generationIds.any(copyingGenerationIds.contains) ||
        referenceIds.any(copyingReferenceIds.contains)) {
      return;
    }
    if (bulk) googleDriveBusy = true;
    copyingGenerationIds.addAll(generationIds);
    copyingReferenceIds.addAll(referenceIds);
    notifyListeners();
    try {
      late GoogleDriveCopyResult copied;
      final operation = _driveCopyQueue.then((_) async {
        copied = await (gateway as GoogleDriveGateway)
            .copyLocalLibraryToGoogleDrive(
              generationIds: generationIds,
              referenceIds: referenceIds,
            );
      });
      _driveCopyQueue = operation.then<void>((_) {}, onError: (_) {});
      await operation;
      _apply(copied.snapshot);
      final total = copied.generations + copied.references;
      showNotice(
        total == 0
            ? 'Everything selected is already in Google Drive.'
            : 'Copied ${copied.generations} generation${copied.generations == 1 ? '' : 's'} and ${copied.references} reference${copied.references == 1 ? '' : 's'} to Drive. Local originals were kept.',
      );
    } on Object catch (error) {
      showNotice(_message(error));
    } finally {
      if (bulk) googleDriveBusy = false;
      copyingGenerationIds.removeAll(generationIds);
      copyingReferenceIds.removeAll(referenceIds);
      notifyListeners();
    }
  }

  Future<void> cacheGenerationPreviews(
    Generation item, {
    Uint8List? thumbnailBytes,
    Uint8List? timelineBytes,
  }) async {
    if (gateway is! GenerationPreviewGateway ||
        (thumbnailBytes == null && timelineBytes == null)) {
      return;
    }
    try {
      _apply(
        await (gateway as GenerationPreviewGateway).saveGenerationPreviews(
          item.localId,
          thumbnailBytes: thumbnailBytes,
          timelineBytes: timelineBytes,
        ),
      );
    } on Object {
      // Playback remains available if a best-effort preview backfill fails.
    }
  }

  Future<void> cacheReferencePreview(
    SavedReference reference,
    Uint8List thumbnailBytes,
  ) async {
    if (gateway is! MediaPreviewGateway ||
        thumbnailBytes.isEmpty ||
        !_referencePreviewWrites.add(reference.id)) {
      return;
    }
    try {
      _apply(
        await (gateway as MediaPreviewGateway).saveReferencePreview(
          reference.id,
          thumbnailBytes,
        ),
      );
    } on Object {
      // The original reference remains usable if a thumbnail write fails.
    } finally {
      _referencePreviewWrites.remove(reference.id);
    }
  }

  Future<void> cacheGenerationInputPreview(
    Generation item,
    AssetReference source,
    Uint8List thumbnailBytes,
  ) async {
    final key = '${item.localId}:${source.value}';
    if (gateway is! MediaPreviewGateway ||
        source.value.isEmpty ||
        thumbnailBytes.isEmpty ||
        !_generationInputPreviewWrites.add(key)) {
      return;
    }
    try {
      _apply(
        await (gateway as MediaPreviewGateway).saveGenerationInputPreview(
          item.localId,
          source.value,
          thumbnailBytes,
        ),
      );
    } on Object {
      // The retained input remains usable if preview backfill fails.
    } finally {
      _generationInputPreviewWrites.remove(key);
    }
  }

  Future<PickedAsset> _retainedAsset(
    AssetReference reference, {
    AssetReference? thumbnailAsset,
  }) async {
    Uint8List? thumbnailBytes;
    if (thumbnailAsset != null) {
      try {
        thumbnailBytes = await gateway.readAsset(thumbnailAsset);
      } on Object {
        // The original media remains reusable without its cached preview.
      }
    }
    return PickedAsset(
      name: reference.label,
      bytes: await gateway.readAsset(reference),
      mimeType: reference.contentType ?? 'application/octet-stream',
      retained: reference,
      thumbnailAsset: thumbnailAsset,
      thumbnailBytes: thumbnailBytes,
    );
  }

  Future<void> _restoreGenerationSettings(
    Generation item, {
    bool includePrompt = false,
  }) async {
    if (includePrompt &&
        providers.any((provider) => provider.id == item.provider)) {
      selectedProviderId = item.provider;
      selectedModelId = modelById(item.provider, item.model).id;
    }
    final retainedFrames = <KeyframeDraft>[];
    for (final frame in item.config.keyframes ?? const <KeyframeLabel>[]) {
      final reference = frame.source;
      PickedAsset? asset;
      if (reference?.isLocal == true) {
        try {
          asset = await _retainedAsset(reference!);
        } on Object {
          // Keep the saved role and timing even if its retained file moved.
        }
      }
      retainedFrames.add(
        KeyframeDraft(
          id: _uid(),
          label: frame.label,
          role: frame.role,
          source: reference?.kind == 'remote' ? reference!.value : '',
          seconds:
              frame.seconds ??
              switch (frame.role) {
                KeyframeRole.start => 0,
                KeyframeRole.middle =>
                  item.config.duration is num
                      ? (item.config.duration as num).toDouble() / 2
                      : 4,
                KeyframeRole.end =>
                  item.config.duration is num
                      ? (item.config.duration as num).toDouble()
                      : 8,
              },
          asset: asset,
          retained: reference,
        ),
      );
    }
    final retainedReferences = <MediaReferenceDraft>[];
    for (final media
        in item.config.references ?? const <MediaReferenceLabel>[]) {
      final reference = media.source;
      PickedAsset? asset;
      Uint8List? thumbnailBytes;
      if (media.thumbnailAsset != null) {
        try {
          thumbnailBytes = await gateway.readAsset(media.thumbnailAsset!);
        } on Object {
          // The original reference can regenerate its preview.
        }
      }
      if (reference?.isLocal == true) {
        try {
          asset = await _retainedAsset(
            reference!,
            thumbnailAsset: media.thumbnailAsset,
          );
        } on Object {
          // Keep the saved reference label if its retained file moved.
        }
      }
      retainedReferences.add(
        MediaReferenceDraft(
          id: _uid(),
          label: media.label,
          kind: media.kind,
          source: reference?.kind == 'remote' ? reference!.value : '',
          asset: asset,
          retained: reference,
          thumbnailAsset: media.thumbnailAsset,
          thumbnailBytes: asset?.thumbnailBytes ?? thumbnailBytes,
        ),
      );
    }
    PickedAsset? retainedSource;
    if ((item.mode == VideoMode.v2v ||
            item.mode == VideoMode.draftEnhance ||
            item.mode == VideoMode.upscale) &&
        item.config.source?.isLocal == true) {
      try {
        retainedSource = await _retainedAsset(
          item.config.source!,
          thumbnailAsset: item.config.sourceThumbnailAsset,
        );
      } on Object {
        // Preserve the rest of the last-used settings when an asset is gone.
        showNotice(
          item.mode == VideoMode.upscale
              ? 'The retained source video is no longer available. Attach a video to upscale.'
              : item.mode == VideoMode.v2v
              ? 'The retained starting video is no longer available. Attach a video to continue one.'
              : 'The retained draft cache is no longer available. Attach a draft to enhance it.',
        );
      }
    }
    Uint8List? sourceThumbnailBytes = retainedSource?.thumbnailBytes;
    if (sourceThumbnailBytes == null &&
        item.config.sourceThumbnailAsset != null) {
      try {
        sourceThumbnailBytes = await gateway.readAsset(
          item.config.sourceThumbnailAsset!,
        );
      } on Object {
        // Reused source media can regenerate its preview in the Create panel.
      }
    }
    final restoredTask =
        selectedModel.referenceTasks.contains(item.config.referenceTask)
        ? item.config.referenceTask
        : MediaReferenceTask.reference;
    form
      ..prompt = includePrompt && item.mode != VideoMode.draftEnhance
          ? item.prompt
          : form.prompt
      ..aspectRatio = item.config.aspectRatio
      ..autoDuration = item.config.duration == 'auto'
      ..durationSeconds = item.config.duration is num
          ? (item.config.duration as num).toInt()
          : form.durationSeconds
      ..frameRate = item.config.frameRate
      ..resolution = item.config.resolution
      ..generateAudio = item.config.generateAudio
      ..safetyTolerance = item.config.safetyTolerance
      ..draft = item.config.draft
      ..upscale = item.mode == VideoMode.upscale
      ..upscaleFactor = item.config.upscaleFactor
      ..upscaleCreativity = item.config.upscaleCreativity
      // _normalizeFormForModel clears this when the model lacks seed support.
      ..seed = item.config.seed
      ..exactTiming = item.config.exactTiming
      ..keyframes = retainedFrames
      ..references = retainedReferences
      ..referenceTask = restoredTask
      ..videoAsset =
          item.mode == VideoMode.v2v || item.mode == VideoMode.upscale
          ? retainedSource
          : null
      ..videoUrl =
          (item.mode == VideoMode.v2v || item.mode == VideoMode.upscale) &&
              item.config.source?.kind == 'remote'
          ? item.config.source!.value
          : ''
      ..videoThumbnailBytes = sourceThumbnailBytes
      ..videoMetadata = null
      ..draftAsset = item.mode == VideoMode.draftEnhance ? retainedSource : null
      ..draftUrl =
          item.mode == VideoMode.draftEnhance &&
              item.config.source?.kind == 'remote'
          ? item.config.source!.value
          : '';
    _selectCompatibleModel();
    _normalizeFormForModel();
    _invalidateProviderEstimate();
    formRevision += 1;
    notifyListeners();
  }

  Future<void> reuse(Generation item) async {
    if (!canReuse(item)) {
      showNotice('Apple Local has been retired. Choose another provider.');
      return;
    }
    try {
      await _restoreGenerationSettings(item, includePrompt: true);
    } on Object catch (error) {
      showNotice(_message(error));
    }
    await navigate(AppSection.create);
    showNotice('Prompt, settings, and retained references copied.');
  }

  void enhance(Generation item) {
    if (item.draftCacheUrl == null) return;
    form
      ..autoDuration = item.config.duration == 'auto'
      ..durationSeconds = item.config.duration is num
          ? (item.config.duration as num).toInt()
          : form.durationSeconds
      ..resolution = 'fhd'
      ..generateAudio = item.config.generateAudio
      ..draft = false
      ..draftAsset = null
      ..draftUrl = item.draftCacheUrl!;
    _invalidateProviderEstimate();
    formRevision += 1;
    notifyListeners();
    unawaited(navigate(AppSection.create));
  }

  Future<String?> saveMedia(
    Generation item, {
    VideoSaveDestination destination = VideoSaveDestination.files,
  }) async {
    if (item.resultAsset == null && item.resultUrl == null) {
      throw StateError('This media is not available.');
    }
    final bytes = item.resultAsset != null
        ? await gateway.readAsset(item.resultAsset!)
        : await gateway.downloadMedia(item.resultUrl!);
    final baseName =
        'clawnsole-${item.createdAt.toIso8601String().substring(0, 10)}-'
        '${item.localId.substring(0, item.localId.length.clamp(0, 6))}';
    final contentType =
        item.resultAsset?.contentType ??
        (item.isImage ? 'image/png' : 'video/mp4');
    final extension = item.isImage ? 'png' : 'mp4';
    final noun = item.isImage ? 'Image' : 'Video';
    if (destination == VideoSaveDestination.photos) {
      await gateway.saveMediaToPhotoLibrary(
        bytes,
        '$baseName.$extension',
        contentType,
      );
      showNotice('$noun saved to Photos.');
      return null;
    }
    final location = await FilePicker.saveFile(
      dialogTitle: 'Save Clawnsole ${noun.toLowerCase()}',
      fileName: '$baseName.$extension',
      bytes: bytes,
      type: item.isImage ? FileType.image : FileType.custom,
      allowedExtensions: item.isImage ? null : const <String>['mp4'],
    );
    if (location == null) {
      showNotice(
        kIsWeb
            ? 'Download started. Choose a location when your browser or desktop app asks.'
            : 'Save canceled.',
      );
      return null;
    }
    showNotice('$noun saved to $location');
    return location;
  }

  Future<String?> saveVideo(
    Generation item, {
    VideoSaveDestination destination = VideoSaveDestination.files,
  }) => saveMedia(item, destination: destination);

  Future<Uri?> generationMediaUri(Generation item) async {
    if (item.resultAsset != null) return gateway.assetUri(item.resultAsset!);
    return item.resultUrl == null ? null : gateway.mediaUri(item.resultUrl!);
  }

  Future<void> saveReferenceImage(AssetReference reference) async {
    final bytes = await gateway.readAsset(reference);
    final cleaned = reference.label.replaceAll(RegExp(r'[\\/:]'), '-').trim();
    final subtype = reference.contentType?.split('/').lastOrNull;
    final extension =
        subtype != null && subtype.isNotEmpty && subtype.length <= 5
        ? '.$subtype'
        : '.png';
    final fileName = cleaned.contains('.') ? cleaned : '$cleaned$extension';
    final location = await FilePicker.saveFile(
      dialogTitle: 'Save reference frame',
      fileName: fileName.isEmpty ? 'clawnsole-frame.png' : fileName,
      bytes: bytes,
      type: FileType.image,
    );
    if (location == null) {
      showNotice(
        kIsWeb
            ? 'Download started. Choose a location when your browser or desktop app asks.'
            : 'Save canceled.',
      );
      return;
    }
    showNotice('Reference frame saved to $location');
  }

  Future<Uri?> referenceMediaUri(SavedReference reference) async {
    final asset = reference.asset;
    if (asset.isLocal) return gateway.assetUri(asset);
    if (Uri.tryParse(asset.value)?.scheme == 'https') {
      return gateway.mediaUri(asset.value);
    }
    return null;
  }

  Future<void> saveReferenceVideo(
    SavedReference reference, {
    VideoSaveDestination destination = VideoSaveDestination.files,
  }) async {
    final asset = reference.asset;
    final bytes = asset.isLocal
        ? await gateway.readAsset(asset)
        : await gateway.downloadMedia(asset.value);
    final cleaned = reference.name.replaceAll(RegExp(r'[\\/:]'), '-').trim();
    final base = cleaned.isEmpty ? 'clawnsole-reference' : cleaned;
    final dotIndex = base.lastIndexOf('.');
    final extensionLength = base.length - dotIndex - 1;
    final hasExtension =
        dotIndex > 0 && extensionLength >= 1 && extensionLength <= 5;
    final fileName = hasExtension ? base : '$base.mp4';
    final contentType = asset.contentType ?? 'video/mp4';
    if (destination == VideoSaveDestination.photos) {
      await gateway.saveMediaToPhotoLibrary(bytes, fileName, contentType);
      showNotice('Video saved to Photos.');
      return;
    }
    final isMp4 = fileName.endsWith('.mp4');
    final location = await FilePicker.saveFile(
      dialogTitle: 'Save reference video',
      fileName: fileName,
      bytes: bytes,
      type: isMp4 ? FileType.custom : FileType.any,
      allowedExtensions: isMp4 ? const <String>['mp4'] : null,
    );
    if (location == null) {
      showNotice(
        kIsWeb
            ? 'Download started. Choose a location when your browser or desktop app asks.'
            : 'Save canceled.',
      );
      return;
    }
    showNotice('Video saved to $location');
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _creditTimer?.cancel();
    _estimateTimer?.cancel();
    _noticeTimer?.cancel();
    super.dispose();
  }
}

enum VideoSaveDestination { photos, files }

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
