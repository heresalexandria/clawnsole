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

class PickedAsset {
  const PickedAsset({
    required this.name,
    required this.bytes,
    required this.mimeType,
    this.retained,
  });

  final String name;
  final Uint8List bytes;
  final String mimeType;
  final AssetReference? retained;

  String get dataUrl => 'data:$mimeType;base64,${base64Encode(bytes)}';
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
    this.savedReferenceId,
  });

  final String id;
  final String label;
  final MediaReferenceKind kind;
  final String source;
  final PickedAsset? asset;
  final AssetReference? retained;
  final String? savedReferenceId;

  String get requestSource => asset?.dataUrl ?? source.trim();

  MediaReferenceDraft copyWith({
    String? label,
    String? source,
    String? savedReferenceId,
  }) => MediaReferenceDraft(
    id: id,
    label: label ?? this.label,
    kind: kind,
    source: source ?? this.source,
    asset: asset,
    retained: source == null ? retained : null,
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
    this.folderId,
    this.tags = const <String>[],
    this.generated = false,
  });

  final String id;
  final String name;
  final MediaReferenceKind kind;
  final AssetReference asset;
  final DateTime createdAt;
  final String? folderId;
  final List<String> tags;
  final bool generated;
}

class GenerationFormState {
  String prompt = '';
  String aspectRatio = '16:9';
  bool autoDuration = true;
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
  PickedAsset? draftAsset;
  String draftUrl = '';

  /// The generation mode implied by what is attached. There is no mode
  /// picker: a draft cache wins, then a starting video, then keyframes or
  /// creative references, and plain text otherwise.
  VideoMode get mode {
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
  int _idCounter = 0;

  static const String libraryFolderAll = 'all';
  static const String libraryFolderUnfiled = 'unfiled';

  List<Generation> get generations => snapshot?.generations ?? const [];
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

  List<LibraryFolder> foldersFor(LibraryCollection collection) {
    final values = List<LibraryFolder>.from(
      (snapshot?.folders ?? const <LibraryFolder>[]).where(
        (folder) => folder.collection == collection,
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
  GoogleDriveConnection get googleDriveConnection =>
      gateway is GoogleDriveGateway
      ? (gateway as GoogleDriveGateway).googleDriveConnection
      : const GoogleDriveConnection(
          state: GoogleDriveConnectionState.unavailable,
        );
  bool googleDriveBusy = false;
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
    libraryFolderAll => generations.length,
    libraryFolderUnfiled =>
      generations.where((item) => folderById(item.folderId) == null).length,
    _ =>
      generations
          .where((item) => folderBranch(folderView).contains(item.folderId))
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
      final folderName = item.folderId == null
          ? ''
          : folderPath(item.folderId!).toLowerCase();
      if (query.isNotEmpty &&
          !item.prompt.toLowerCase().contains(query) &&
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
    libraryFolderAll => savedReferences.length,
    libraryFolderUnfiled =>
      savedReferences
          .where(
            (item) =>
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
            (item) => folderBranch(
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

  GenerationConfig get currentConfig {
    final orderedFrames = _orderedFrames();
    return GenerationConfig(
      aspectRatio: form.aspectRatio,
      duration: form.duration,
      resolution: form.resolution,
      generateAudio: form.generateAudio,
      safetyTolerance: form.safetyTolerance,
      draft: form.draft,
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
        _ => null,
      },
    );
  }

  CostEstimate get currentEstimate {
    if (_liveEstimateRevision == _estimateRevision && _liveEstimate != null) {
      return _liveEstimate!;
    }
    return estimateCost(
      selectedProviderId,
      selectedModel.id,
      form.mode,
      currentConfig,
      generations,
      providerPrices[selectedProviderId] ?? const <ProviderModelPrice>[],
    );
  }

  Future<void> initialize() async {
    try {
      _apply(await gateway.load());
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

  void _apply(LocalSnapshot value) {
    snapshot = value;
    section = value.preferences.activeSection;
    libraryFilter = value.preferences.libraryFilter;
    final preferredProvider = providerById(value.preferences.provider);
    final available = providers;
    final previousModelId = selectedModelId;
    selectedProviderId =
        available.any((provider) => provider.id == preferredProvider.id)
        ? preferredProvider.id
        : available.firstOrNull?.id ?? 'bfl';
    selectedModelId = modelById(selectedProviderId, value.preferences.model).id;
    // A restored model must constrain the form exactly like a selected one,
    // or a session can reopen with settings the model does not support
    // (for example Auto duration on a fixed-duration model).
    if (selectedModelId != previousModelId) _normalizeFormForModel();
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

  Future<void> navigate(AppSection value) async {
    section = value;
    notifyListeners();
    try {
      _apply(await gateway.setPreferences(_preferences(activeSection: value)));
    } on Object catch (error) {
      showNotice(_message(error));
    }
  }

  Future<void> setLibraryFilter(LibraryFilter value) async {
    libraryFilter = value;
    notifyListeners();
    try {
      _apply(await gateway.setPreferences(_preferences(libraryFilter: value)));
    } on Object catch (error) {
      showNotice(_message(error));
    }
  }

  void setSearch(String value) {
    librarySearch = value;
    notifyListeners();
  }

  void setLibraryFolderView(String value) {
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
    final folder = LibraryFolder(
      id:
          existing?.id ??
          'folder-${now.microsecondsSinceEpoch.toRadixString(36)}-${_idCounter++}',
      name: clean,
      createdAt: existing?.createdAt ?? now,
      parentId: parentId,
      collection: existing?.collection ?? collection,
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

  Future<SavedReference?> saveDraftReference(
    MediaReferenceDraft draft, {
    required String name,
    String? folderId,
    required Iterable<String> tags,
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
    final reference = SavedReference(
      id: id,
      name: clean,
      kind: draft.kind,
      asset:
          retained ??
          AssetReference(kind: 'remote', value: '', label: draft.label),
      createdAt: now,
      updatedAt: now,
      folderId: folderId,
      tags: cleanLibraryTags(tags),
    );
    try {
      _apply(
        await (gateway as ReferenceLibraryGateway).saveReference(
          reference,
          source: draft.requestSource.isEmpty ? null : draft.requestSource,
        ),
      );
      final saved = savedReferences.where((item) => item.id == id).firstOrNull;
      if (saved == null) throw StateError('The saved reference was not found.');
      form.references = form.references.map((item) {
        if (item.id != draft.id) return item;
        final asset = item.asset;
        return MediaReferenceDraft(
          id: item.id,
          label: item.label,
          kind: item.kind,
          source: saved.asset.isLocal ? '' : saved.asset.value,
          asset: asset == null
              ? null
              : PickedAsset(
                  name: asset.name,
                  bytes: asset.bytes,
                  mimeType: asset.mimeType,
                  retained: saved.asset,
                ),
          retained: saved.asset,
          savedReferenceId: saved.id,
        );
      }).toList();
      notifyListeners();
      showNotice('“${saved.name}” saved to References.');
      return saved;
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
          createdAt: now,
          updatedAt: now,
          folderId: folderId,
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
                label: item.prompt.trim().isEmpty
                    ? 'Generated ${kind.label.toLowerCase()}'
                    : item.prompt.trim(),
                contentType: item.isImage ? 'image/png' : 'video/mp4',
              );
          return ReferenceCandidate(
            id: item.localId,
            name: item.prompt.trim().isEmpty
                ? 'Generated ${kind.label.toLowerCase()}'
                : item.prompt.trim(),
            kind: kind,
            asset: asset,
            createdAt: item.createdAt,
            folderId: item.folderId,
            tags: item.tags,
            generated: true,
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
        var source = candidate.asset.isLocal ? '' : candidate.asset.value;
        if (candidate.asset.isLocal) {
          final bytes = await gateway.readAsset(candidate.asset);
          picked = PickedAsset(
            name: candidate.name,
            bytes: bytes,
            mimeType:
                candidate.asset.contentType ??
                _fallbackMimeType(candidate.kind),
            retained: candidate.asset,
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
            savedReferenceId: candidate.generated ? null : candidate.id,
          ),
        ];
      }
      _selectCompatibleModel();
      _normalizeFormForModel();
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
    if (form.requiresFixedDuration) form.autoDuration = false;
    form.durationSeconds = _validDuration(form.durationSeconds);
    _invalidateProviderEstimate();
    notifyListeners();
  }

  AppPreferences _preferences({
    AppSection? activeSection,
    LibraryFilter? libraryFilter,
  }) => AppPreferences(
    activeSection: activeSection ?? section,
    libraryFilter: libraryFilter ?? this.libraryFilter,
    provider: selectedProviderId,
    model: selectedModelId,
  );

  int _validDuration(int value) {
    final model = selectedModel;
    final maximum = model.maxDurationFor(form.resolution);
    final clamped = value.clamp(model.minDuration, maximum);
    final offset = clamped - model.minDuration;
    return model.minDuration +
        (offset ~/ model.durationStep) * model.durationStep;
  }

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
      : selectedModel.aspectRatiosFor(form.resolution);

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
      _apply(await gateway.setPreferences(_preferences()));
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
      _apply(await gateway.setPreferences(_preferences()));
    } on Object catch (error) {
      showNotice(_message(error));
    }
  }

  void _normalizeFormForModel() {
    final model = selectedModel;
    if (!model.supportsAutoDuration) form.autoDuration = false;
    if (!model.supportsAudio) form.generateAudio = false;
    if (!model.supportsDraft) form.draft = false;
    if (!model.supportsTimedKeyframes) form.exactTiming = false;
    if (!model.referenceTasks.contains(form.referenceTask)) {
      form.referenceTask = MediaReferenceTask.reference;
    }
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
      form.referenceCount(kind) < referenceLimit(kind);

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
      for (final asset in picked.take(available)) {
        _appendReference(kind, label: asset.name, asset: asset);
      }
      if (picked.length > available) {
        showNotice(
          '${selectedModel.label} accepts up to '
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
      );
    }).toList();
    notifyListeners();
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
    notifyListeners();
  }

  void setDurationSeconds(int value) {
    form.durationSeconds = _validDuration(value);
    form.keyframes = form.keyframes.map((frame) {
      return frame.role == KeyframeRole.end
          ? frame.copyWith(seconds: form.durationSeconds.toDouble())
          : frame;
    }).toList();
    notifyListeners();
  }

  void setFrameRate(int value) {
    form.frameRate = value.clamp(1, 6);
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
    notifyListeners();
  }

  void removeFrame(String id) {
    form.keyframes = form.keyframes.where((frame) => frame.id != id).toList();
    _selectCompatibleModel();
    _normalizeFormForModel();
    notifyListeners();
  }

  Future<void> pickVideo() async {
    try {
      final asset = await _pick(type: FileType.video);
      if (asset != null) updateForm((value) => value.videoAsset = asset);
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
    if (form.mode != VideoMode.draftEnhance && form.prompt.trim().isEmpty) {
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
        final maximumDuration = model.maxDurationFor(form.resolution);
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
    if (selectedProvider.requiresApiKey && !await refreshCredits()) return;
    await refreshProviderEstimate();
    final now = DateTime.now().toUtc();
    final estimate = currentEstimate;
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
      );
    }
    submitting = true;
    notifyListeners();
    showNotice('Generation sent. Clawnsole will keep an eye on it.');
    try {
      pending = await gateway.submit(
        GenerationSubmission(record: pending, input: _buildInput()),
      );
      _replaceInMemory(pending);
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
      items[index] = generation;
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
          '${providerShortNameForHistory(item.provider)} reports that this film is ready.',
        );
      } else if (updated.isFailed) {
        showNotice(
          updated.error ??
              '${providerShortNameForHistory(item.provider)} reports ${updated.statusLabel}.',
        );
      } else {
        showNotice(
          '${providerShortNameForHistory(item.provider)} reports ${updated.statusLabel.toLowerCase()}.',
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
      '${providerById(provider).shortName} key verified and saved locally.',
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
      '${providerById(provider).shortName} access removed from this device.',
    );
  }

  Future<void> refreshProviderModels(String provider) async {
    try {
      final models = gateway is ProviderGateway
          ? await (gateway as ProviderGateway).listProviderModels(provider)
          : publishedProviderPrices(provider);
      if (models.isNotEmpty) providerPrices[provider] = models;
      notifyListeners();
    } on Object {
      // Published prices remain visible if a live catalog is unavailable.
    }
  }

  void _invalidateProviderEstimate() {
    final signature = <Object?>[
      selectedProviderId,
      selectedModel.id,
      form.mode,
      form.duration,
      form.resolution,
      form.generateAudio,
    ].join('|');
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
    _apply(await gateway.clearPreferences());
    showNotice('Saved preferences reset.');
  }

  Future<void> clearAll() async {
    _apply(await gateway.clearAll());
    credits = null;
    showNotice(
      supportsGoogleDrive
          ? 'Clawnsole’s Drive data and browser-local keys were removed.'
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
      _apply(await (gateway as GoogleDriveGateway).disconnectGoogleDrive());
      showNotice('Drive disconnected on this device. Cloud files were kept.');
    } on Object catch (error) {
      showNotice(_message(error));
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
      _apply(await (gateway as GoogleDriveGateway).refreshGoogleDrive());
      showNotice('Google Drive data refreshed.');
    } on Object catch (error) {
      showNotice(_message(error));
    } finally {
      googleDriveBusy = false;
      notifyListeners();
    }
  }

  Future<PickedAsset> _retainedAsset(AssetReference reference) async =>
      PickedAsset(
        name: reference.label,
        bytes: await gateway.readAsset(reference),
        mimeType: reference.contentType ?? 'application/octet-stream',
        retained: reference,
      );

  Future<void> _restoreGenerationSettings(
    Generation item, {
    bool includePrompt = false,
  }) async {
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
      if (reference?.isLocal == true) {
        try {
          asset = await _retainedAsset(reference!);
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
        ),
      );
    }
    PickedAsset? retainedSource;
    if ((item.mode == VideoMode.v2v || item.mode == VideoMode.draftEnhance) &&
        item.config.source?.isLocal == true) {
      try {
        retainedSource = await _retainedAsset(item.config.source!);
      } on Object {
        // Preserve the rest of the last-used settings when an asset is gone.
        showNotice(
          item.mode == VideoMode.v2v
              ? 'The retained starting video is no longer available. Attach a video to continue one.'
              : 'The retained draft cache is no longer available. Attach a draft to enhance it.',
        );
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
      ..exactTiming = item.config.exactTiming
      ..keyframes = retainedFrames
      ..references = retainedReferences
      ..referenceTask = restoredTask
      ..videoAsset = item.mode == VideoMode.v2v ? retainedSource : null
      ..videoUrl =
          item.mode == VideoMode.v2v && item.config.source?.kind == 'remote'
          ? item.config.source!.value
          : ''
      ..draftAsset = item.mode == VideoMode.draftEnhance ? retainedSource : null
      ..draftUrl =
          item.mode == VideoMode.draftEnhance &&
              item.config.source?.kind == 'remote'
          ? item.config.source!.value
          : '';
    if (form.requiresFixedDuration) form.autoDuration = false;
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
