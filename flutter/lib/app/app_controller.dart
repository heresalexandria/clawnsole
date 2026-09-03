import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';

import '../core/asset_extensions.dart';
import '../core/background_activity.dart';
import '../core/bfl_api.dart';
import '../core/composer_tabs.dart';
import '../core/data_location.dart';
import '../core/gateway.dart';
import '../core/generation_timing.dart';
import '../core/google_drive.dart';
import '../core/library_rules.dart' as library_rules;
import '../core/media_cache_gateway.dart';
import '../core/models.dart';
import '../core/pricing.dart';
import '../core/prompt_rewrite.dart';
import '../core/provider_catalog.dart';
import '../core/provider_manifest.dart';
import '../core/reference_prompts.dart';
import '../core/settings_vault_gateway.dart';
import '../core/shell_bridge.dart';
import '../core/video_cache_gateway.dart';

part 'app_controller_rewrite.dart';

String _sha256Digest(Uint8List bytes) => sha256.convert(bytes).toString();

String _base64Payload(Uint8List bytes) => base64Encode(bytes);

enum MediaPickerSource { library, files }

enum AppNoticeAction { retryWithVisualNormalization }

typedef FilePickerInvocation =
    Future<FilePickerResult?> Function({
      required FileType type,
      required bool allowMultiple,
      required bool withData,
    });

typedef ReferencePreviewLoader =
    Future<Uint8List?> Function(PickedAsset asset, String source);

Future<FilePickerResult?> _pickFiles({
  required FileType type,
  required bool allowMultiple,
  required bool withData,
}) => FilePicker.pickFiles(
  type: type,
  allowMultiple: allowMultiple,
  withData: withData,
);

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

/// One local file dropped onto a reference surface, before classification.
class DroppedFile {
  const DroppedFile({required this.name, required this.bytes, this.path});

  final String name;
  final Uint8List bytes;
  final String? path;
}

enum ReferenceImportStage { queued, preparing, uploading }

/// Lightweight presentation state for a file selected from References.
///
/// The durable [SavedReference] is still created only after its media and
/// metadata have been retained successfully. Keeping this separate lets the
/// library render every selected file immediately without polluting persisted
/// history with partial records.
class ReferenceImportProgress {
  const ReferenceImportProgress({
    required this.id,
    required this.name,
    required this.kind,
    required this.storage,
    required this.stage,
    required this.position,
    required this.total,
    this.folderId,
  });

  final String id;
  final String name;
  final MediaReferenceKind kind;
  final LibraryStorage storage;
  final ReferenceImportStage stage;
  final int position;
  final int total;
  final String? folderId;

  String get statusLabel => switch (stage) {
    ReferenceImportStage.queued => 'Waiting to upload',
    ReferenceImportStage.preparing => 'Preparing upload',
    ReferenceImportStage.uploading => 'Uploading $position of $total',
  };

  ReferenceImportProgress copyWith({ReferenceImportStage? stage}) =>
      ReferenceImportProgress(
        id: id,
        name: name,
        kind: kind,
        storage: storage,
        stage: stage ?? this.stage,
        position: position,
        total: total,
        folderId: folderId,
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
    this.savedReferenceId,
  });

  final String id;
  final String label;
  final KeyframeRole role;
  final String source;
  final double seconds;
  final PickedAsset? asset;
  final AssetReference? retained;
  final String? savedReferenceId;

  String get requestSource => asset?.dataUrl ?? source.trim();

  KeyframeDraft copyWith({
    String? label,
    String? source,
    double? seconds,
    String? savedReferenceId,
    bool clearSavedReferenceId = false,
  }) => KeyframeDraft(
    id: id,
    label: label ?? this.label,
    role: role,
    source: source ?? this.source,
    seconds: seconds ?? this.seconds,
    asset: asset,
    retained: source == null ? retained : null,
    savedReferenceId: clearSavedReferenceId
        ? null
        : savedReferenceId ?? this.savedReferenceId,
  );
}

class MediaReferenceDraft {
  const MediaReferenceDraft({
    required this.id,
    required this.label,
    required this.kind,
    required this.source,
    this.promptName,
    this.asset,
    this.retained,
    this.thumbnailAsset,
    this.thumbnailBytes,
    this.savedReferenceId,
    this.durationSeconds,
  });

  final String id;
  final String label;
  final MediaReferenceKind kind;
  final String source;
  final String? promptName;
  final PickedAsset? asset;
  final AssetReference? retained;
  final AssetReference? thumbnailAsset;
  final Uint8List? thumbnailBytes;
  final String? savedReferenceId;
  final double? durationSeconds;

  String get requestSource => asset?.dataUrl ?? source.trim();

  MediaReferenceDraft copyWith({
    String? label,
    String? promptName,
    String? source,
    AssetReference? thumbnailAsset,
    bool clearThumbnailAsset = false,
    Uint8List? thumbnailBytes,
    bool clearThumbnailBytes = false,
    String? savedReferenceId,
    bool clearSavedReferenceId = false,
    double? durationSeconds,
    bool clearDurationSeconds = false,
  }) => MediaReferenceDraft(
    id: id,
    label: label ?? this.label,
    kind: kind,
    source: source ?? this.source,
    promptName: promptName ?? this.promptName,
    asset: asset,
    retained: source == null ? retained : null,
    thumbnailAsset: clearThumbnailAsset
        ? null
        : thumbnailAsset ?? this.thumbnailAsset,
    thumbnailBytes: clearThumbnailBytes
        ? null
        : thumbnailBytes ?? this.thumbnailBytes,
    savedReferenceId: clearSavedReferenceId
        ? null
        : savedReferenceId ?? this.savedReferenceId,
    durationSeconds: clearDurationSeconds
        ? null
        : durationSeconds ?? this.durationSeconds,
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
    this.durationSeconds,
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
  final double? durationSeconds;
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
  String? videoSavedReferenceId;
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

/// One composer workspace on the Create screen: an independent Direction
/// prompt plus every generation setting that goes with it.
///
/// Everything the composer treats as "the draft" lives here rather than on
/// [AppController], so several films can be written side by side. The
/// controller's `form`, `selectedProviderId`, `formRevision` and friends are
/// views onto whichever tab is in front.
class ComposerTab {
  ComposerTab({
    required this.id,
    required this.providerId,
    required this.modelId,
    this.title,
    this.generateAudioExplicitlyDisabled = false,
    this.formRevision = 0,
    this.sourceGenerationId,
    this.rewriteSummary,
    this.localFolderId,
    this.driveFolderId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now().toUtc(),
       updatedAt = updatedAt ?? createdAt ?? DateTime.now().toUtc();

  final String id;

  /// A name typed by the director; null derives the label from the prompt.
  String? title;

  final GenerationFormState form = GenerationFormState();
  String providerId;
  String modelId;

  /// Whether the director turned audio off by hand, so a model switch does
  /// not silently turn it back on.
  bool generateAudioExplicitlyDisabled;

  /// References set aside because this tab's model cannot take them.
  final List<MediaReferenceDraft> disabledReferences = <MediaReferenceDraft>[];

  /// Bumped whenever the whole draft is replaced, so text fields and the
  /// disclosure panels rebuild from the new contents.
  int formRevision;

  /// The generation this tab was seeded from (startup carry-over, Reuse, or
  /// AI Rewrite). Retained media is re-hydrated from it on the next launch.
  String? sourceGenerationId;

  /// The one-sentence change summary from AI Rewrite, when it made this tab.
  String? rewriteSummary;

  /// Save-to folders, one per storage, seeded from the last-used defaults.
  String? localFolderId;
  String? driveFolderId;
  final DateTime createdAt;
  DateTime updatedAt;

  /// Media expected to appear in this tab but not yet attached. Async picks
  /// keep counting against the tab they started in.
  int pendingPickerReferenceAdds = 0;
  int pendingDropReferenceAdds = 0;
  int pendingFrameAdds = 0;

  String get label => composerTabTitle(title, form.prompt);

  /// Nothing has been directed here yet, so seeding it in place clobbers no
  /// work of the director's.
  bool get isBlank => form.prompt.trim().isEmpty;
}

/// A starred model resolved against the live catalog.
typedef FavoriteModel = ({
  VideoProviderDefinition provider,
  VideoModelDefinition model,
});

class AppController extends ChangeNotifier {
  AppController({
    AppGateway? gateway,
    FilePickerInvocation? filePicker,
    ProviderCatalogClient? providerCatalogClient,
    BackgroundActivityCoordinator? backgroundActivity,
    bool mobileTestBuild = clawnsoleMobileTestBuild,
  }) : gateway = gateway ?? createGateway(),
       _filePicker = filePicker ?? _pickFiles,
       _providerCatalogClient =
           providerCatalogClient ?? ProviderCatalogClient(),
       _backgroundActivity =
           backgroundActivity ?? MethodChannelBackgroundActivity(),
       _mobileTestBuild = mobileTestBuild {
    resetProviderCatalog(mobileTestBuild: mobileTestBuild);
    _resetPublishedProviderPrices();
    final first = ComposerTab(
      id: _uid(),
      providerId: 'bfl',
      modelId: 'flux-3-video',
    );
    _composerTabs.add(first);
    _activeComposerTabId = first.id;
  }

  final AppGateway gateway;
  final FilePickerInvocation _filePicker;
  final ProviderCatalogClient _providerCatalogClient;
  final BackgroundActivityCoordinator _backgroundActivity;
  final bool _mobileTestBuild;

  final List<ComposerTab> _composerTabs = <ComposerTab>[];
  String _activeComposerTabId = '';

  /// Where draft writes land. It is [activeComposerTab] except inside
  /// [_inComposerTab], which async media work uses to keep writing into the
  /// tab it started in after the director has moved on.
  ComposerTab? _composerDraftTarget;
  Timer? _composerTabsSaveTimer;
  Future<void> _composerTabWrites = Future<void>.value();
  bool _restoringComposerTabs = false;

  /// True once startup has read the saved strip (or found none). Writing
  /// before that would file a default tab over the session the director
  /// actually left open.
  bool _composerTabsRestored = false;

  LocalSnapshot? _snapshot;
  int _snapshotRevision = 0;
  LocalSnapshot? get snapshot => _snapshot;
  set snapshot(LocalSnapshot? value) {
    _snapshot = value;
    _snapshotRevision += 1;
  }

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

  /// Size cap in megabytes for cached Drive videos; 0 turns full-film caching
  /// and prefetching off.
  int localVideoCacheMb = AppPreferences.defaultLocalVideoCacheMb;

  /// Independent size cap for Drive previews and thumbnails.
  int localThumbnailCacheMb = AppPreferences.defaultLocalThumbnailCacheMb;

  /// Converts unsupported reference images and repairs incompatible reference
  /// videos before they are uploaded.
  bool autoFixReferenceVideos = AppPreferences.defaultAutoFixReferenceVideos;

  /// Visible cost-desk column ids in display order; null keeps the defaults.
  List<String>? costDeskColumns;
  String? lastLocalGenerationFolderId;
  String? lastDriveGenerationFolderId;
  String librarySearch = '';
  String libraryFolderView = libraryFolderAll;
  String? libraryTag;
  String referenceSearch = '';
  String referenceFolderView = libraryFolderAll;
  String? referenceTag;
  MediaReferenceKind? referenceKind;
  GenerationOutputKind? libraryOutputKind;
  ReferenceSort referenceSort = ReferenceSort.newest;

  /// Starred models ([modelFavoriteKey] values) and provider ids, oldest star
  /// first. Both live in preferences so they follow the user across devices.
  List<String> favoriteModelKeys = <String>[];
  List<String> favoriteProviderIds = <String>[];

  /// Folder ids whose subtrees are folded in the folder rails. Session-only:
  /// a fresh launch opens every branch again.
  final Set<String> collapsedFolderIds = <String>{};

  /// The provider and model of the composer tab in front. Every tab keeps
  /// its own pair, so one draft can wait on Runway while another is set up
  /// for FLUX.
  String get selectedProviderId => _draftTab.providerId;
  set selectedProviderId(String value) => _draftTab.providerId = value;
  String get selectedModelId => _draftTab.modelId;
  set selectedModelId(String value) => _draftTab.modelId = value;
  double? credits;
  final Map<String, ProviderAccountStatus> providerAccounts =
      <String, ProviderAccountStatus>{};
  final Map<String, List<ProviderModelPrice>> providerPrices =
      <String, List<ProviderModelPrice>>{};

  /// AI Rewrite choices, remembered in preferences: the provider used last
  /// and the model and effort per provider.
  String? rewriteProviderId;
  final Map<String, String> rewriteModelIds = <String, String>{};
  final Map<String, String> rewriteEfforts = <String, String>{};

  /// Live model listings per rewrite provider, fetched on demand.
  final Map<String, List<RewriteModel>> rewriteModels =
      <String, List<RewriteModel>>{};
  bool loading = true;
  bool submitting = false;
  bool refreshingCredits = false;
  int _referenceUploadDepth = 0;
  String? referenceUploadStatus;
  int get formRevision => _draftTab.formRevision;
  set formRevision(int value) => _draftTab.formRevision = value;
  String? loadError;
  String? creditError;
  String? notice;

  /// Optional recovery attached to the current notice. Notices without an
  /// action always clear the previous action so stale buttons cannot survive
  /// a later status message.
  AppNoticeAction? noticeAction;

  /// Increments with every [showNotice] call so listeners can surface a
  /// repeated identical message instead of deduplicating it forever.
  int noticeSequence = 0;

  Timer? _pollTimer;
  Timer? _creditTimer;
  Future<void> _preferenceWrites = Future<void>.value();

  /// The appearance chosen from the top bar; persisted with the other
  /// preferences so it survives relaunch.
  AppThemeMode themeMode = AppThemeMode.system;

  /// Whether the keyless on-device provider can render on this device, as
  /// reported by the platform at startup and on resume (never assumed).
  bool localGenerationAvailable = false;

  /// Mirrors the widget lifecycle so finished work can be announced with a
  /// system notification only when nobody is looking at the app.
  bool appInForeground = true;

  bool _notificationsRequested = false;
  int _preferenceRevision = 0;
  Future<bool>? _creditRefreshFuture;
  Timer? _estimateTimer;
  String? _estimateSignature;
  int _estimateRevision = 0;
  int? _liveEstimateRevision;
  CostEstimate? _liveEstimate;
  Timer? _noticeTimer;
  bool _polling = false;
  bool _pollAgainIgnoringSchedule = false;
  Timer? _prefetchDebounce;
  int _prefetchRevision = 0;
  int _videoPreviewSourceRevision = 0;
  Future<void> _prefetchQueue = Future<void>.value();
  final Set<String> _prefetchedVideoAssets = <String>{};
  final Map<String, Uint8List> _restoredAssetBytes = <String, Uint8List>{};
  final Map<String, Future<Uint8List>> _assetReadJobs =
      <String, Future<Uint8List>>{};
  final List<ReferenceImportProgress> _referenceImports =
      <ReferenceImportProgress>[];
  Future<void> _referenceWorkQueue = Future<void>.value();
  final Set<String> _hydratingReferenceDraftIds = <String>{};
  bool _refreshingDriveLibrary = false;
  int _driveRefreshTick = 0;
  bool _reconcilingGenerationWork = false;
  LocalSnapshot? _pendingWorkSnapshot;
  bool _pendingWorkCache = false;
  LocalSnapshot? _pendingDriveUploadSnapshot;
  int _pendingDriveUploadCache = 0;
  final Set<String> _statusChecks = <String>{};
  final Set<String> _referencePreviewWrites = <String>{};
  final Map<String, Uint8List> _referencePreviewBytes = <String, Uint8List>{};
  final Set<String> _referenceDurationWrites = <String>{};
  final Set<String> _generationInputPreviewWrites = <String>{};
  int _idCounter = 0;
  int _libraryMutationRevision = 0;
  final Map<String, int> _generationFavoriteRevisions = <String, int>{};
  final Map<String, int> _referenceFavoriteRevisions = <String, int>{};
  final Map<String, int> _generationVisibilityRevisions = <String, int>{};
  final Map<String, int> _referenceVisibilityRevisions = <String, int>{};
  bool _disposed = false;

  static const String libraryFolderAll = 'all';
  static const String libraryFolderUnfiled = 'unfiled';

  /// Changes whenever a Drive video becomes locally materialized. Preview
  /// widgets use this to retry frame extraction after background prefetching
  /// completes instead of remaining on their initial cold-cache placeholder.
  int get videoPreviewSourceRevision => _videoPreviewSourceRevision;

  bool get referenceUploadInProgress => _referenceUploadDepth > 0;

  int get _pendingPickerReferenceAdds => _draftTab.pendingPickerReferenceAdds;
  set _pendingPickerReferenceAdds(int value) =>
      _draftTab.pendingPickerReferenceAdds = value;
  int get _pendingDropReferenceAdds => _draftTab.pendingDropReferenceAdds;
  set _pendingDropReferenceAdds(int value) =>
      _draftTab.pendingDropReferenceAdds = value;
  int get _pendingFrameAdds => _draftTab.pendingFrameAdds;
  set _pendingFrameAdds(int value) => _draftTab.pendingFrameAdds = value;

  /// Reference cards expected to appear but not yet appended to the form —
  /// a picker still choosing or reading files, or dropped files being read.
  /// The Create screen renders one loading tile per pending add.
  int get pendingReferenceAdds =>
      _pendingPickerReferenceAdds + _pendingDropReferenceAdds;

  /// Keyframe cards expected to appear but not yet appended to the form
  /// (the pick-and-retain pipeline runs before a frame attaches).
  int get pendingFrameAdds => _pendingFrameAdds;

  // ---------------------------------------------------------------------
  // Composer tabs
  // ---------------------------------------------------------------------

  /// Every open composer workspace, in strip order.
  List<ComposerTab> get composerTabs =>
      List<ComposerTab>.unmodifiable(_composerTabs);

  /// The workspace the Create screen is showing. There is always exactly one.
  ComposerTab get activeComposerTab => _composerTabs.firstWhere(
    (tab) => tab.id == _activeComposerTabId,
    orElse: () => _composerTabs.first,
  );

  String get activeComposerTabId => activeComposerTab.id;

  /// The draft every form mutation reads and writes.
  ComposerTab get _draftTab => _composerDraftTarget ?? activeComposerTab;

  /// The Direction prompt and settings of the tab in front.
  GenerationFormState get form => _draftTab.form;

  bool get _generateAudioExplicitlyDisabled =>
      _draftTab.generateAudioExplicitlyDisabled;
  set _generateAudioExplicitlyDisabled(bool value) =>
      _draftTab.generateAudioExplicitlyDisabled = value;

  List<MediaReferenceDraft> get _disabledReferences =>
      _draftTab.disabledReferences;

  /// Runs [action] with draft writes aimed at [tab] rather than the visible
  /// one, so a picker or download that finished after a tab switch still
  /// lands its media in the draft it was started from.
  ///
  /// [action] is deliberately synchronous: the aim is restored the moment it
  /// returns, so no director interaction can ever interleave with it. Never
  /// await inside one of these — capture the tab and open a new scope after
  /// the await instead.
  T _inComposerTab<T>(ComposerTab tab, T Function() action) {
    final previous = _composerDraftTarget;
    _composerDraftTarget = tab;
    try {
      return action();
    } finally {
      _composerDraftTarget = previous;
    }
  }

  ComposerTab? _composerTabById(String id) =>
      _composerTabs.where((tab) => tab.id == id).firstOrNull;

  /// Opens a blank workspace. It inherits only the current tab's provider,
  /// model, and save-to folders; the direction and everything attached start
  /// empty.
  ComposerTab addComposerTab({bool activate = true}) {
    final source = activeComposerTab;
    final tab = ComposerTab(
      id: _uid(),
      providerId: source.providerId,
      modelId: source.modelId,
      localFolderId: source.localFolderId,
      driveFolderId: source.driveFolderId,
    );
    _composerTabs.add(tab);
    if (activate) {
      _activeComposerTabId = tab.id;
      _invalidateProviderEstimate();
    }
    _flushComposerTabsSave();
    notifyListeners();
    return tab;
  }

  /// Brings [id] to the front. Unknown ids are ignored.
  void activateComposerTab(String id) {
    if (id == _activeComposerTabId) return;
    final tab = _composerTabById(id);
    if (tab == null) return;
    _activeComposerTabId = tab.id;
    _invalidateProviderEstimate();
    _ensureProviderModelsLoaded(tab.providerId);
    _flushComposerTabsSave();
    notifyListeners();
  }

  /// Closes [id]. The strip never empties: closing the only tab replaces it
  /// with a blank one that keeps its provider, model, and folders. Closing
  /// the tab in front moves to its right-hand neighbour, else the left.
  void closeComposerTab(String id) {
    final index = _composerTabs.indexWhere((tab) => tab.id == id);
    if (index < 0) return;
    final closed = _composerTabs.removeAt(index);
    final wasActive = closed.id == _activeComposerTabId;
    if (_composerTabs.isEmpty) {
      final replacement = ComposerTab(
        id: _uid(),
        providerId: closed.providerId,
        modelId: closed.modelId,
        localFolderId: closed.localFolderId,
        driveFolderId: closed.driveFolderId,
      );
      _composerTabs.add(replacement);
      _activeComposerTabId = replacement.id;
    } else if (wasActive) {
      final next = index < _composerTabs.length
          ? index
          : _composerTabs.length - 1;
      _activeComposerTabId = _composerTabs[next].id;
    }
    _invalidateProviderEstimate();
    _ensureProviderModelsLoaded(activeComposerTab.providerId);
    _flushComposerTabsSave();
    notifyListeners();
  }

  /// Names [id]. An empty or blank [title] goes back to deriving the label
  /// from the prompt.
  void renameComposerTab(String id, String? title) {
    final tab = _composerTabById(id);
    if (tab == null) return;
    final clean = title?.trim() ?? '';
    tab.title = clean.isEmpty ? null : clean;
    _scheduleComposerTabsSave(touched: tab);
    notifyListeners();
  }

  /// Fetches a newly fronted tab's live model list once, so switching to a
  /// draft set up for another provider does not sit on stale pricing.
  void _ensureProviderModelsLoaded(String providerId) {
    if (providerPrices.containsKey(providerId)) return;
    final provider = providers
        .where((item) => item.id == providerId)
        .firstOrNull;
    if (provider == null || !provider.requiresApiKey) return;
    unawaited(refreshProviderModels(providerId));
  }

  /// How long a draft rests before it is written down. Typing must not put a
  /// file write behind every keystroke.
  static const Duration composerTabsSaveDebounce = Duration(milliseconds: 750);

  bool get _persistsComposerTabs =>
      _composerTabsRestored && gateway is ComposerTabsGateway;

  ComposerTabRecord _composerTabRecord(ComposerTab tab) => ComposerTabRecord(
    id: tab.id,
    title: tab.title,
    prompt: tab.form.prompt,
    providerId: tab.providerId,
    modelId: tab.modelId,
    aspectRatio: tab.form.aspectRatio,
    autoDuration: tab.form.autoDuration,
    durationSeconds: tab.form.durationSeconds,
    frameRate: tab.form.frameRate,
    resolution: tab.form.resolution,
    generateAudio: tab.form.generateAudio,
    safetyTolerance: tab.form.safetyTolerance,
    draft: tab.form.draft,
    exactTiming: tab.form.exactTiming,
    referenceTask: tab.form.referenceTask.name,
    upscale: tab.form.upscale,
    upscaleFactor: tab.form.upscaleFactor,
    upscaleCreativity: tab.form.upscaleCreativity,
    seed: tab.form.seed,
    videoUrl: tab.form.videoUrl,
    draftUrl: tab.form.draftUrl,
    sourceGenerationId: tab.sourceGenerationId,
    rewriteSummary: tab.rewriteSummary,
    localFolderId: tab.localFolderId,
    driveFolderId: tab.driveFolderId,
    createdAt: tab.createdAt,
    updatedAt: tab.updatedAt,
  );

  /// Notes that [touched] (the tab being drafted in, by default) changed and
  /// arms the debounced write.
  void _scheduleComposerTabsSave({ComposerTab? touched}) {
    if (_disposed || _restoringComposerTabs || !_persistsComposerTabs) return;
    (touched ?? _draftTab).updatedAt = DateTime.now().toUtc();
    _composerTabsSaveTimer?.cancel();
    _composerTabsSaveTimer = Timer(
      composerTabsSaveDebounce,
      () => unawaited(_saveComposerTabs()),
    );
  }

  /// Writes the strip now. Tab switches, closes, navigation, and submission
  /// are the moments a half-typed draft must already be on disk.
  /// [onlyIfPending] skips the write when nothing has changed since the last.
  void _flushComposerTabsSave({bool onlyIfPending = false}) {
    final pending = _composerTabsSaveTimer?.isActive ?? false;
    _composerTabsSaveTimer?.cancel();
    _composerTabsSaveTimer = null;
    if (_disposed || _restoringComposerTabs || !_persistsComposerTabs) return;
    if (onlyIfPending && !pending) return;
    unawaited(_saveComposerTabs());
  }

  Future<void> _saveComposerTabs() async {
    if (_disposed) return;
    if (gateway case final ComposerTabsGateway tabsGateway) {
      final state = ComposerTabsState(
        tabs: _composerTabs.map(_composerTabRecord).toList(growable: false),
        activeTabId: _activeComposerTabId,
      );
      // Serialized like the preference writes so two quick changes cannot
      // land out of order, and silent: a draft never raises a notice.
      _composerTabWrites = _composerTabWrites.then((_) async {
        try {
          await tabsGateway.saveComposerTabs(state);
        } on Object {
          // The next change writes the whole strip again.
        }
      });
      await _composerTabWrites;
    }
  }

  /// Rebuilds the strip saved by the last session. Returns false when there
  /// is nothing stored, so startup falls back to seeding one tab from the
  /// most recent generation.
  Future<bool> _restoreComposerTabs() async {
    if (gateway case final ComposerTabsGateway tabsGateway) {
      ComposerTabsState? stored;
      try {
        stored = await tabsGateway.loadComposerTabs();
      } on Object {
        return false;
      }
      if (_disposed || stored == null || stored.tabs.isEmpty) return false;
      final known = <String, Generation>{
        for (final item in generations) item.localId: item,
      };
      final rebuilt = <ComposerTab>[
        for (final record in stored.tabs)
          ComposerTab(
            id: record.id,
            providerId: record.providerId ?? selectedProviderId,
            modelId: record.modelId ?? selectedModelId,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
          ),
      ];
      _restoringComposerTabs = true;
      try {
        _composerTabs
          ..clear()
          ..addAll(rebuilt);
        _activeComposerTabId = stored.activeTab?.id ?? rebuilt.first.id;
        for (var index = 0; index < stored.tabs.length; index += 1) {
          final record = stored.tabs[index];
          final tab = rebuilt[index];
          final source = known[record.sourceGenerationId];
          if (source != null) {
            try {
              // Keyframes, references, and the source clip come back from the
              // generation; the record's own scalars are applied on top.
              await _restoreGenerationSettings(
                source,
                cacheOnly: true,
                tab: tab,
              );
            } on Object {
              // A missing retained file must not cost the whole strip.
            }
            if (_disposed) return true;
          }
          _inComposerTab(tab, () => _applyComposerTabRecord(tab, record));
        }
      } finally {
        _restoringComposerTabs = false;
      }
      _invalidateProviderEstimate();
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Lays a saved record over [tab], overruling anything the source
  /// generation seeded: the record is what the director last had on screen.
  void _applyComposerTabRecord(ComposerTab tab, ComposerTabRecord record) {
    tab.title = record.title;
    tab.sourceGenerationId = record.sourceGenerationId;
    tab.rewriteSummary = record.rewriteSummary;
    tab.localFolderId =
        folderById(record.localFolderId)?.storage == LibraryStorage.local
        ? record.localFolderId
        : null;
    tab.driveFolderId =
        folderById(record.driveFolderId)?.storage == LibraryStorage.drive
        ? record.driveFolderId
        : null;
    final provider = record.providerId;
    if (provider != null && providers.any((item) => item.id == provider)) {
      tab.providerId = provider;
      tab.modelId = modelById(provider, record.modelId ?? '').id;
    }
    tab.form
      ..prompt = record.prompt
      ..aspectRatio = record.aspectRatio
      ..autoDuration = record.autoDuration
      ..durationSeconds = record.durationSeconds
      ..frameRate = record.frameRate
      ..resolution = record.resolution
      ..generateAudio = record.generateAudio
      ..safetyTolerance = record.safetyTolerance
      ..draft = record.draft
      ..exactTiming = record.exactTiming
      ..referenceTask =
          MediaReferenceTask.values
              .where((task) => task.name == record.referenceTask)
              .firstOrNull ??
          MediaReferenceTask.reference
      ..upscale = record.upscale
      ..upscaleFactor = record.upscaleFactor
      ..upscaleCreativity = record.upscaleCreativity
      ..seed = record.seed
      ..videoUrl = record.videoUrl
      ..draftUrl = record.draftUrl;
    // The record has no separate "muted by hand" flag; a saved false is one.
    tab.generateAudioExplicitlyDisabled = !record.generateAudio;
    _selectCompatibleModel();
    _normalizeFormForModel();
    tab.formRevision += 1;
  }

  /// Reserves loading tiles for files just dropped on the references area,
  /// covering the read phase before [addDroppedReferenceFiles] can run.
  void noteIncomingDroppedFiles(int count) {
    if (count <= 0) return;
    _pendingDropReferenceAdds += count;
    notifyListeners();
  }

  List<ReferenceImportProgress> get referenceImports =>
      List<ReferenceImportProgress>.unmodifiable(_referenceImports);

  void _beginReferenceUpload(String status) {
    _referenceUploadDepth += 1;
    referenceUploadStatus = status;
    notifyListeners();
  }

  void _updateReferenceUpload(String status) {
    if (!referenceUploadInProgress || referenceUploadStatus == status) return;
    referenceUploadStatus = status;
    notifyListeners();
  }

  void _finishReferenceUpload() {
    if (_referenceUploadDepth == 0) return;
    _referenceUploadDepth -= 1;
    if (_referenceUploadDepth == 0) referenceUploadStatus = null;
    notifyListeners();
  }

  /// Serializes reference persistence so several adds can be in flight from
  /// the user's point of view without interleaving the gateway's
  /// read-modify-write cycles. Callers still await their own enqueued work;
  /// the add buttons never lock.
  Future<T> _enqueueReferenceWork<T>(Future<T> Function() task) {
    final result = _referenceWorkQueue.then((_) => task());
    _referenceWorkQueue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// True while a draft picked from References is still loading its media
  /// bytes in the background. Such a draft renders normally but cannot enter
  /// a generation until the bytes arrive.
  bool isReferenceDraftHydrating(String draftId) =>
      _hydratingReferenceDraftIds.contains(draftId);

  List<Generation> get generations => snapshot?.generations ?? const [];

  GenerationProgressEstimate generationProgress(Generation generation) =>
      generationProgressEstimate(generation, generations);
  List<Generation> get visibleGenerations =>
      generations.where((item) => !item.hidden).toList();
  List<SavedReference> get savedReferences =>
      snapshot?.savedReferences ?? const <SavedReference>[];

  String referencePromptName(MediaReferenceDraft reference) {
    final assigned = reference.promptName?.trim() ?? '';
    if (assigned.isNotEmpty) return assigned;
    final number =
        form.references
            .takeWhile((candidate) => candidate.id != reference.id)
            .where((candidate) => candidate.kind == reference.kind)
            .length +
        1;
    return '${reference.kind.label} $number';
  }

  List<PromptReferenceMention> get formPromptReferenceMentions {
    final counts = <MediaReferenceKind, int>{};
    return form.references.map((reference) {
      final number = (counts[reference.kind] ?? 0) + 1;
      counts[reference.kind] = number;
      return PromptReferenceMention(
        kind: reference.kind,
        number: number,
        name: referencePromptName(reference),
      );
    }).toList();
  }

  String _nextReferencePromptName(MediaReferenceKind kind) {
    final used = form.references
        .map(referencePromptName)
        .map((name) => name.toLowerCase())
        .toSet();
    var number = 1;
    while (used.contains('${kind.label} $number'.toLowerCase())) {
      number += 1;
    }
    return '${kind.label} $number';
  }

  String? referenceNameProblem(
    String value, {
    String? excludeDraftId,
    String? excludeSavedReferenceId,
    bool allowReserved = false,
  }) {
    final clean = value.trim();
    if (clean.isEmpty || clean.length > 80) {
      return 'Reference names must be between 1 and 80 characters.';
    }
    if (clean.contains('@') || clean.contains('\n') || clean.contains('\r')) {
      return 'Enter a name without @ or line breaks.';
    }
    if (!allowReserved && isReservedReferenceName(clean)) {
      return 'Names like Image 1, Video 1, and Audio 1 are reserved for new uploads.';
    }
    final normalized = clean.toLowerCase();
    final savedCollision = savedReferences.any(
      (reference) =>
          reference.id != excludeSavedReferenceId &&
          reference.name.trim().toLowerCase() == normalized,
    );
    final draftCollision = form.references.any(
      (reference) =>
          reference.id != excludeDraftId &&
          reference.savedReferenceId != excludeSavedReferenceId &&
          referencePromptName(reference).toLowerCase() == normalized,
    );
    if (savedCollision || draftCollision) {
      return 'Reference names must be unique.';
    }
    return null;
  }

  String _uniqueSavedReferenceName(
    String preferred, {
    String? excludeSavedReferenceId,
  }) {
    var base = preferred.trim();
    if (base.isEmpty) base = 'Reference';
    if (base.length > 80) base = base.substring(0, 80).trimRight();
    final used = savedReferences
        .where((reference) => reference.id != excludeSavedReferenceId)
        .map((reference) => reference.name.trim().toLowerCase())
        .toSet();
    var candidate = base;
    var number = 2;
    while (used.contains(candidate.toLowerCase()) ||
        isReservedReferenceName(candidate)) {
      final suffix = ' $number';
      final maximumBaseLength = 80 - suffix.length;
      final shortened = base.length <= maximumBaseLength
          ? base
          : base.substring(0, maximumBaseLength).trimRight();
      candidate = '$shortened$suffix';
      number += 1;
    }
    return candidate;
  }

  SavedReference? _savedReferenceForInput({
    String? referenceId,
    required MediaReferenceKind kind,
    AssetReference? asset,
  }) => savedReferences
      .where(
        (reference) =>
            reference.kind == kind &&
            (reference.id == referenceId ||
                sameAssetReference(reference.asset, asset)),
      )
      .firstOrNull;

  /// Generated videos whose durable input metadata points at [reference].
  /// Asset matching keeps pre-v21 history useful; new records retain the
  /// reference id even when normalization stores a different derivative.
  List<Generation> generationsUsingReference(SavedReference reference) {
    final values = generations.where((generation) {
      if (generation.outputKind != GenerationOutputKind.video) return false;
      if (generation.config.sourceReferenceId == reference.id ||
          sameAssetReference(generation.config.source, reference.asset)) {
        return true;
      }
      if (generation.config.keyframes?.any(
            (frame) =>
                frame.referenceId == reference.id ||
                sameAssetReference(frame.source, reference.asset),
          ) ==
          true) {
        return true;
      }
      return generation.config.references?.any(
            (media) =>
                media.referenceId == reference.id ||
                sameAssetReference(media.source, reference.asset),
          ) ==
          true;
    }).toList();
    values.sort((first, second) => second.createdAt.compareTo(first.createdAt));
    return values;
  }

  List<VideoProviderDefinition> get providers {
    final available = snapshot?.availableProviders ?? const <String>{};
    if (available.isEmpty) {
      return videoProviders.where((provider) => !provider.isLocal).toList();
    }
    return videoProviders
        .where(
          (provider) =>
              available.contains(provider.id) ||
              available.contains(provider.adapter),
        )
        .toList();
  }

  bool isFavoriteModel(String providerId, String modelId) =>
      favoriteModelKeys.contains(modelFavoriteKey(providerId, modelId));

  bool isFavoriteProvider(String providerId) =>
      favoriteProviderIds.contains(providerId);

  /// Starred models that still exist in the live catalog, in catalog order so
  /// the Favorites section reads like the rest of the picker.
  List<FavoriteModel> get favoriteModels => <FavoriteModel>[
    for (final provider in providers)
      for (final model in provider.models)
        if (isFavoriteModel(provider.id, model.id))
          (provider: provider, model: model),
  ];

  /// Starred providers that are available on this build, in catalog order.
  List<VideoProviderDefinition> get favoriteProviders =>
      providers.where((provider) => isFavoriteProvider(provider.id)).toList();

  /// Every available provider with the starred ones first, then the rest in
  /// catalog order — the ordering the model picker and provider desk share.
  List<VideoProviderDefinition> get providersByPreference =>
      <VideoProviderDefinition>[
        ...favoriteProviders,
        ...providers.where((provider) => !isFavoriteProvider(provider.id)),
      ];

  Future<void> toggleFavoriteModel(String providerId, String modelId) async {
    final key = modelFavoriteKey(providerId, modelId);
    final next = List<String>.from(favoriteModelKeys);
    if (!next.remove(key)) next.add(key);
    favoriteModelKeys = List<String>.unmodifiable(next);
    notifyListeners();
    try {
      await _savePreferences(_preferences(favoriteModels: favoriteModelKeys));
    } on Object catch (error) {
      showNotice(_message(error));
    }
  }

  Future<void> toggleFavoriteProvider(String providerId) async {
    final next = List<String>.from(favoriteProviderIds);
    if (!next.remove(providerId)) next.add(providerId);
    favoriteProviderIds = List<String>.unmodifiable(next);
    notifyListeners();
    try {
      await _savePreferences(
        _preferences(favoriteProviders: favoriteProviderIds),
      );
    } on Object catch (error) {
      showNotice(_message(error));
    }
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
  int get keyframeLimit => selectedModel.maxKeyframesFor(
    form.mode == VideoMode.t2v ? VideoMode.i2v : form.mode,
  );
  bool get hasApiKey => hasApiKeyFor(selectedProviderId);
  bool hasApiKeyFor(String provider) =>
      snapshot?.hasApiKeyFor(provider) ?? false;
  bool get requiresProviderRetentionAcknowledgement =>
      selectedProvider.resultDelivery.keepOpenRecommended &&
      hasApiKey &&
      !(snapshot?.providerRetentionAcknowledgements.contains(
            selectedProviderId,
          ) ??
          false);
  bool get hasAnyApiKey =>
      snapshot?.connectedProviders.isNotEmpty == true ||
      snapshot?.hasApiKey == true;

  /// True while any pollable provider work is unfinished: an in-flight
  /// submission, a working generation, or a ready result that has not been
  /// retained locally yet. The platform shell uses this to keep the process
  /// executing briefly after backgrounding so that work can land.
  bool get hasPendingProviderWork {
    final current = snapshot;
    if (current == null) return false;
    if (!identical(current, _pendingWorkSnapshot)) {
      _pendingWorkSnapshot = current;
      _pendingWorkCache = current.generations.any(
        (item) =>
            (item.isWorking || item.needsResultRetention) &&
            hasApiKeyFor(item.provider),
      );
    }
    return _pendingWorkCache;
  }

  /// Media staged on this device that a background pass still needs to
  /// publish to Google Drive: Drive-tagged records whose assets are still
  /// local-kind. Drives the non-blocking "backing up to Drive" indicators.
  int get pendingDriveUploadCount {
    final current = snapshot;
    if (current == null) return 0;
    if (!identical(current, _pendingDriveUploadSnapshot)) {
      _pendingDriveUploadSnapshot = current;
      _pendingDriveUploadCache = pendingDriveUploadAssets(
        current.generations,
        current.savedReferences,
      ).map((reference) => reference.value).toSet().length;
    }
    return _pendingDriveUploadCache;
  }

  @override
  void notifyListeners() {
    // dispose() reports idle to the shell; a straggling poll completion must
    // not re-arm the process-global background hint after that. Pending Drive
    // uploads count as background work so iOS keeps the process running long
    // enough for staged media to publish after an app switch.
    if (!_disposed) {
      unawaited(
        _backgroundActivity.setPendingWork(
          hasPendingProviderWork || pendingDriveUploadCount > 0,
        ),
      );
    }
    super.notifyListeners();
  }

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
  VideoCacheGateway? get _videoCacheGateway =>
      gateway is VideoCacheGateway ? gateway as VideoCacheGateway : null;
  MediaCacheGateway? get _mediaCacheGateway =>
      gateway is MediaCacheGateway ? gateway as MediaCacheGateway : null;
  bool get supportsVideoCache => gateway is VideoCacheGateway;
  SettingsVaultStatus get settingsVaultStatus =>
      snapshot?.settingsVault ?? const SettingsVaultStatus.unavailable();
  DataLocationGateway? get _dataLocation =>
      gateway is DataLocationGateway ? gateway as DataLocationGateway : null;
  bool get supportsRevealDataFolder =>
      _dataLocation?.supportsRevealDataFolder ?? false;
  bool get supportsDataRelocation =>
      _dataLocation?.supportsDataRelocation ?? false;
  bool get shellManagesDataRelocation =>
      _dataLocation?.shellManagesDataRelocation ?? false;
  bool dataRelocationBusy = false;
  bool googleDriveBusy = false;
  bool settingsVaultBusy = false;
  final Set<String> copyingGenerationIds = <String>{};
  final Set<String> copyingReferenceIds = <String>{};
  Future<void> _driveCopyQueue = Future<void>.value();
  int get workingCount => generations.where((item) => item.isWorking).length;
  int get readyCount => generations.where((item) => item.isReady).length;
  double get spentCredits => generations
      .where((item) => item.billingUnit == 'credits' && countsTowardSpend(item))
      .fold(0, (total, item) => total + (item.cost ?? 0));
  double get spentUsd => generations
      .where(countsTowardSpend)
      .fold(0, (total, item) => total + (recordedRealizedCostUsd(item) ?? 0));
  bool isCheckingStatus(String localId) => _statusChecks.contains(localId);
  bool isCopyingGeneration(String localId) =>
      copyingGenerationIds.contains(localId);
  bool isCopyingReference(String referenceId) =>
      copyingReferenceIds.contains(referenceId);
  bool canReuse(Generation item) =>
      providerByIdOrNull(
        item.provider,
      )?.models.any((model) => model.id == item.model) ==
      true;

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

  /// Ancestor ids of [folderId], nearest parent first.
  List<String> folderAncestors(
    String folderId, {
    LibraryCollection collection = LibraryCollection.generated,
  }) {
    final ids = <String>[];
    var current = folderById(folderId, collection: collection);
    final visited = <String>{folderId};
    while (current?.parentId != null && visited.add(current!.parentId!)) {
      ids.add(current.parentId!);
      current = folderById(current.parentId, collection: collection);
    }
    return ids;
  }

  bool isFolderCollapsed(String folderId) =>
      collapsedFolderIds.contains(folderId);

  /// Whether a collapsed ancestor hides [folderId] from the folder rail.
  bool isFolderHidden(
    String folderId, {
    LibraryCollection collection = LibraryCollection.generated,
  }) => folderAncestors(
    folderId,
    collection: collection,
  ).any(collapsedFolderIds.contains);

  void setFolderCollapsed(String folderId, bool collapsed) {
    final changed = collapsed
        ? collapsedFolderIds.add(folderId)
        : collapsedFolderIds.remove(folderId);
    if (changed) notifyListeners();
  }

  /// Opens every branch above [folderId] so a freshly selected or freshly
  /// moved folder is never tucked out of sight.
  void _revealFolder(String folderId, LibraryCollection collection) {
    for (final ancestor in folderAncestors(folderId, collection: collection)) {
      collapsedFolderIds.remove(ancestor);
    }
  }

  /// The live record for [folder], so a caller holding a stale copy never
  /// writes an old parent or name back over a newer one.
  LibraryFolder _currentFolder(LibraryFolder folder) =>
      folderById(folder.id, collection: folder.collection) ?? folder;

  Future<bool> renameFolder(LibraryFolder folder, String name) {
    final current = _currentFolder(folder);
    return saveLibraryFolder(
      name,
      existing: current,
      parentId: current.parentId,
      collection: current.collection,
      successNotice: 'Folder renamed.',
    );
  }

  /// Whether [folder] may be re-parented under [parentId] (null = top level):
  /// same storage, and never inside its own branch.
  bool canMoveFolder(LibraryFolder stale, {required String? parentId}) {
    final folder = _currentFolder(stale);
    if (parentId == null) return true;
    final parent = folderById(parentId, collection: folder.collection);
    return parent != null &&
        parent.storage == folder.storage &&
        !folderBranch(
          folder.id,
          collection: folder.collection,
        ).contains(parentId);
  }

  /// Re-parents [folder] under [parentId] (null = top level), refusing moves
  /// across storages or into the folder's own branch with a plain reason.
  Future<bool> moveFolder(
    LibraryFolder stale, {
    required String? parentId,
  }) async {
    final folder = _currentFolder(stale);
    if (parentId == folder.parentId) return true;
    final collection = folder.collection;
    final parent = folderById(parentId, collection: collection);
    if (parentId != null && parent == null) {
      showNotice('That folder no longer exists.');
      return false;
    }
    if (parent != null && parent.storage != folder.storage) {
      showNotice('Folders can only move within the same storage.');
      return false;
    }
    if (parent != null &&
        folderBranch(folder.id, collection: collection).contains(parent.id)) {
      showNotice('A folder cannot move inside itself.');
      return false;
    }
    final saved = await saveLibraryFolder(
      folder.name,
      existing: folder,
      parentId: parentId,
      collection: collection,
      successNotice: 'Folder moved.',
    );
    if (saved) {
      _revealFolder(folder.id, collection);
      notifyListeners();
    }
    return saved;
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

  List<Generation> get filteredGenerations =>
      generations.where(_libraryPredicate()).toList();

  /// How many films the current view would list under media type [kind]
  /// (null counts every type) with every other filter still applied, so the
  /// type segments read as facet counts for the folder in view.
  int libraryOutputKindCount(GenerationOutputKind? kind) {
    final matches = _libraryPredicate(includeOutputKind: false);
    return generations
        .where(
          (item) => matches(item) && (kind == null || item.outputKind == kind),
        )
        .length;
  }

  bool Function(Generation item) _libraryPredicate({
    bool includeOutputKind = true,
  }) {
    final query = librarySearch.trim().toLowerCase();
    final selectedBranch =
        libraryFolderView != libraryFolderAll &&
            libraryFolderView != libraryFolderUnfiled
        ? folderBranch(libraryFolderView)
        : const <String>{};
    return (item) {
      if (!libraryStorageFilter.matches(item.storage)) return false;
      if (includeOutputKind &&
          libraryOutputKind != null &&
          item.outputKind != libraryOutputKind) {
        return false;
      }
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
    };
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

  /// How many references the current view would list under media [kind]
  /// (null counts every kind) with every other filter still applied.
  int referenceKindCount(MediaReferenceKind? kind) {
    final matches = _referencePredicate(includeKind: false);
    return savedReferences
        .where((item) => matches(item) && (kind == null || item.kind == kind))
        .length;
  }

  bool Function(SavedReference item) _referencePredicate({
    bool includeKind = true,
  }) {
    final query = referenceSearch.trim().toLowerCase();
    final selectedBranch =
        referenceFolderView != libraryFolderAll &&
            referenceFolderView != libraryFolderUnfiled
        ? folderBranch(
            referenceFolderView,
            collection: LibraryCollection.references,
          )
        : const <String>{};
    return (item) {
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
      return !includeKind ||
          referenceKind == null ||
          item.kind == referenceKind;
    };
  }

  List<SavedReference> get filteredSavedReferences {
    final values = savedReferences.where(_referencePredicate()).toList();
    int compareDuration(
      SavedReference first,
      SavedReference second, {
      required bool longestFirst,
    }) {
      final firstDuration = first.durationSeconds;
      final secondDuration = second.durationSeconds;
      if (firstDuration == null && secondDuration == null) {
        return first.name.toLowerCase().compareTo(second.name.toLowerCase());
      }
      if (firstDuration == null) return 1;
      if (secondDuration == null) return -1;
      final duration = longestFirst
          ? secondDuration.compareTo(firstDuration)
          : firstDuration.compareTo(secondDuration);
      return duration != 0
          ? duration
          : first.name.toLowerCase().compareTo(second.name.toLowerCase());
    }

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
      ReferenceSort.durationShortest => (a, b) => compareDuration(
        a,
        b,
        longestFirst: false,
      ),
      ReferenceSort.durationLongest => (a, b) => compareDuration(
        a,
        b,
        longestFirst: true,
      ),
    });
    return values;
  }

  /// In-flight imports follow the same listing filters as durable references
  /// so their placeholder cards appear exactly where the completed items will
  /// land.
  List<ReferenceImportProgress> get filteredReferenceImports {
    final query = referenceSearch.trim().toLowerCase();
    final selectedBranch =
        referenceFolderView != libraryFolderAll &&
            referenceFolderView != libraryFolderUnfiled
        ? folderBranch(
            referenceFolderView,
            collection: LibraryCollection.references,
          )
        : const <String>{};
    return _referenceImports
        .where((item) {
          if (!referenceStorageFilter.matches(item.storage)) return false;
          if (!referenceFavoriteFilter.matches(false) ||
              !referenceVisibilityFilter.matches(false)) {
            return false;
          }
          final folderName = item.folderId == null
              ? ''
              : folderPath(
                  item.folderId!,
                  collection: LibraryCollection.references,
                ).toLowerCase();
          if (query.isNotEmpty &&
              !item.name.toLowerCase().contains(query) &&
              !folderName.contains(query)) {
            return false;
          }
          if (referenceFolderView == libraryFolderUnfiled &&
              folderById(
                    item.folderId,
                    collection: LibraryCollection.references,
                  ) !=
                  null) {
            return false;
          }
          if (referenceFolderView != libraryFolderAll &&
              referenceFolderView != libraryFolderUnfiled &&
              !selectedBranch.contains(item.folderId)) {
            return false;
          }
          if (referenceTag != null) return false;
          return referenceKind == null || item.kind == referenceKind;
        })
        .toList(growable: false);
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

  /// The freshest retained asset for a draft linked to the library: a
  /// background upload pass may have swapped the staged local bytes over to
  /// their published Drive file after the draft captured its pointer.
  AssetReference? _linkedRetainedAsset(
    String? savedReferenceId,
    AssetReference? retained,
  ) {
    final saved = savedReferences
        .where((item) => item.id == savedReferenceId)
        .firstOrNull;
    return saved?.asset ?? retained;
  }

  GenerationConfig get currentConfig {
    final orderedFrames = _orderedFrames();
    final upscaling = form.mode == VideoMode.upscale;
    final retainsGuidance =
        form.mode == VideoMode.i2v ||
        (form.mode == VideoMode.v2v &&
            selectedModel.supportsGuidanceWithSource);
    final timedSourceGuidance =
        form.mode == VideoMode.v2v &&
        selectedModel.sourceGuidanceRequiresTimestamps;
    return GenerationConfig(
      aspectRatio: upscaling ? 'auto' : form.aspectRatio,
      duration: upscaling || selectedModel.durationComesFromSource(form.mode)
          ? 'source'
          : form.duration,
      resolution: upscaling ? 'source' : form.resolution,
      generateAudio: upscaling ? false : form.generateAudio,
      safetyTolerance: form.safetyTolerance,
      draft: upscaling ? false : form.draft,
      frameRate: form.frameRate,
      exactTiming: form.usesTimedKeyframes || timedSourceGuidance,
      keyframes: retainsGuidance && orderedFrames.isNotEmpty
          ? orderedFrames
                .map(
                  (frame) => KeyframeLabel(
                    label: frame.label,
                    role: frame.role,
                    seconds: form.usesTimedKeyframes || timedSourceGuidance
                        ? timedSourceGuidance &&
                                  frame.role == KeyframeRole.end &&
                                  form.videoMetadata != null
                              ? form.videoMetadata!.durationSeconds
                              : frame.seconds
                        : null,
                    referenceId: frame.savedReferenceId,
                    source:
                        _linkedRetainedAsset(
                          frame.savedReferenceId,
                          frame.asset?.retained ?? frame.retained,
                        ) ??
                        _reference(null, frame.source, frame.label),
                  ),
                )
                .toList()
          : null,
      references: retainsGuidance && form.references.isNotEmpty
          ? form.references
                .map(
                  (item) => MediaReferenceLabel(
                    label: item.label,
                    kind: item.kind,
                    promptName: referencePromptName(item),
                    referenceId: item.savedReferenceId,
                    source:
                        _linkedRetainedAsset(
                          item.savedReferenceId,
                          item.asset?.retained ?? item.retained,
                        ) ??
                        _reference(null, item.source, item.label),
                    thumbnailAsset: _previewForStorage(
                      item.thumbnailAsset ?? item.asset?.thumbnailAsset,
                      effectiveStorage,
                    ),
                    durationSeconds: item.durationSeconds,
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
      sourceReferenceId:
          form.mode == VideoMode.v2v || form.mode == VideoMode.upscale
          ? form.videoSavedReferenceId
          : null,
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
    var opened = false;
    try {
      await _restoreProviderCatalogCache();
      _apply(await gateway.load(), restorePreferences: true);
      unawaited(_probeLocalGeneration());
      if (selectedProvider.requiresApiKey && hasApiKey) {
        unawaited(refreshCredits());
      }
      unawaited(_recoverBackgroundDeliveries());
      if (hasAnyApiKey) unawaited(pollWorking());
      for (final provider in providers.where((item) => item.requiresApiKey)) {
        unawaited(refreshProviderModels(provider.id));
      }
      _invalidateProviderEstimate();
      opened = true;
    } on Object catch (error) {
      loadError = _message(error);
    } finally {
      loading = false;
      notifyListeners();
    }
    // Catalog refresh is deliberately background work: cached or bundled
    // definitions make startup immediately usable even when Pages is down.
    unawaited(refreshProviderCatalog());
    if (opened) {
      final preferenceRevision = _preferenceRevision;
      // Neither local cache inspection nor Drive authorization belongs on the
      // splash-screen critical path. The local snapshot is authoritative for
      // first paint; cache restoration and remote reconciliation fold in
      // asynchronously after the studio is interactive.
      unawaited(_restoreLocalStartupPresentation());
      unawaited(_reconcileDriveAfterStartup(preferenceRevision));
    }
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      unawaited(pollWorking());
      unawaited(_refreshDriveLibraryIfDue());
    });
    _creditTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (selectedProvider.requiresApiKey && hasApiKey) {
        unawaited(refreshCredits());
      }
    });
  }

  /// Re-runs startup after a failed open (a locked file, an unmounted
  /// volume, a companion that was still starting) without relaunching.
  Future<void> retryInitialize() async {
    if (loading) return;
    _pollTimer?.cancel();
    _creditTimer?.cancel();
    loadError = null;
    loading = true;
    notifyListeners();
    await initialize();
  }

  Future<void> _probeLocalGeneration() async {
    if (gateway case final LocalGenerationAvailabilityGateway probe) {
      bool available;
      try {
        available = await probe.localGenerationAvailable();
      } on Object {
        available = false;
      }
      if (_disposed || available == localGenerationAvailable) return;
      localGenerationAvailable = available;
      notifyListeners();
    }
  }

  /// Whether the studio has nothing it can render with yet: no provider key
  /// on any provider and no working on-device provider. Drives the one-line
  /// first-run guidance on Create.
  bool get needsProviderSetup => !hasAnyApiKey && !localGenerationAvailable;

  /// Whether any delivered film could be picked as a draft to enhance.
  bool get hasDraftEnhanceCandidates =>
      generations.any((item) => item.draftCacheUrl != null);

  Future<void> setThemeMode(AppThemeMode value) async {
    if (value == themeMode) return;
    themeMode = value;
    notifyListeners();
    try {
      await _savePreferences(_preferences(themeMode: value));
    } on Object catch (error) {
      showNotice(_message(error));
    }
  }

  /// Announces films that became ready while the app was out of view, via
  /// the platform (iOS local notification) or the desktop shell.
  void _announceNewlyReady(Set<String>? previouslyReady) {
    if (previouslyReady == null || appInForeground) return;
    for (final item in generations) {
      if (!item.isReady || !item.hasDeliveredMedia) continue;
      if (previouslyReady.contains(item.localId)) continue;
      if (gateway case final GenerationNotificationGateway notifier) {
        unawaited(
          notifier.notifyGenerationReady(item).catchError((Object _) => false),
        );
      } else {
        unawaited(
          notifyViaShell(
            'Your film is ready',
            item.prompt.trim().isEmpty
                ? '${providerById(item.provider).name} finished a generation.'
                : item.prompt.trim().length > 80
                ? '${item.prompt.trim().substring(0, 80)}…'
                : item.prompt.trim(),
          ).catchError((Object _) => false),
        );
      }
    }
  }

  Future<void> _requestNotificationsOnce() async {
    if (_notificationsRequested) return;
    _notificationsRequested = true;
    if (gateway case final GenerationNotificationGateway notifier) {
      try {
        await notifier.requestGenerationNotifications();
      } on Object {
        // Permission is a courtesy; generation must never wait on it.
      }
    }
  }

  Future<void> _restoreProviderCatalogCache() async {
    if (gateway is! ProviderCatalogCacheGateway) return;
    try {
      final cache = await (gateway as ProviderCatalogCacheGateway)
          .loadProviderCatalogCache();
      if (cache == null) return;
      final bundle = ProviderCatalogBundle.fromCache(
        cache,
        mobileTestBuild: _mobileTestBuild,
      );
      installProviderCatalog(bundle.providers, mobileTest: bundle.isMobileTest);
      _resetPublishedProviderPrices();
    } on Object {
      // A malformed or obsolete cache is equivalent to no cache. The bundled
      // catalog remains active and the remote refresh below can replace it.
    }
  }

  Future<void> refreshProviderCatalog() async {
    try {
      final bundle = await _providerCatalogClient.fetch(
        mobileTestBuild: _mobileTestBuild,
      );
      if (_disposed) return;
      var companionSynchronized = !gateway.usesCompanion;
      if (gateway case final ProviderCatalogCacheGateway cacheGateway) {
        try {
          await cacheGateway.saveProviderCatalogCache(bundle.cache);
          companionSynchronized = true;
        } on Object {
          // The fresh catalog remains valid for this session even if a local
          // cache write fails; the next launch will use its previous fallback.
        }
      }
      // Electron's companion installs the catalog while handling the cache
      // write. Never move its renderer ahead if that synchronization failed.
      if (!companionSynchronized || _disposed) return;
      installProviderCatalog(bundle.providers, mobileTest: bundle.isMobileTest);
      // Test status also gates the compiled mobile credential. Refresh the
      // snapshot now so provider UI cannot retain the key after an unlock.
      try {
        _apply(await gateway.load());
      } on Object {
        // Request routing consults the active catalog directly; foreground
        // reconciliation can repair this best-effort UI snapshot later.
      }
      _resetPublishedProviderPrices();
      _reconcileProviderCatalogSelection();
      notifyListeners();
      for (final provider in providers.where((item) => item.requiresApiKey)) {
        unawaited(refreshProviderModels(provider.id));
      }
    } on Object {
      // Network, schema, and compatibility failures must never displace the
      // last valid cached catalog or the defaults compiled into the app.
    }
  }

  void _resetPublishedProviderPrices() {
    providerPrices
      ..clear()
      ..addEntries(
        videoProviders.map(
          (provider) =>
              MapEntry(provider.id, publishedProviderPrices(provider.id)),
        ),
      );
  }

  void _reconcileProviderCatalogSelection() {
    final available = providers;
    if (available.isEmpty) return;
    final provider = available
        .where((candidate) => candidate.id == selectedProviderId)
        .firstOrNull;
    if (provider == null) {
      selectedProviderId = available.first.id;
      selectedModelId = available.first.defaultModel.id;
    } else if (!provider.models.any((model) => model.id == selectedModelId)) {
      selectedModelId = provider.defaultModel.id;
    }
    _normalizeFormForModel();
    _invalidateProviderEstimate();
  }

  Future<void> _restoreLocalStartupPresentation() async {
    try {
      await _restoreCachedFirstPage();
      if (_disposed) return;
      // Saved composer tabs are the session the director left open; they win
      // over the last-generation carry-over below.
      final reopened = await _restoreComposerTabs();
      if (_disposed) return;
      // From here on the strip may be written back over what was stored.
      _composerTabsRestored = true;
      if (reopened) return;
      if (generations.isNotEmpty) {
        final latest = generations.first;
        await _restoreGenerationSettings(latest, cacheOnly: true);
        activeComposerTab.sourceGenerationId = latest.localId;
      } else {
        notifyListeners();
      }
    } on Object {
      // Local presentation restore is best effort and must never become an
      // unhandled asynchronous startup failure.
    }
  }

  Future<void> _reconcileDriveAfterStartup(int preferenceRevision) async {
    await resumeGoogleDrive(
      restorePreferences: true,
      expectedPreferenceRevision: preferenceRevision,
    );
    if (_disposed) return;
    await _restoreCachedFirstPage();
    if (_disposed) return;
    _scheduleListingPrefetch();
    notifyListeners();
  }

  /// Imports result downloads the platform transfer service finished while
  /// the process was suspended or terminated, then refreshes the snapshot so
  /// the recovered films appear immediately.
  Future<void> _recoverBackgroundDeliveries() async {
    if (gateway is! BackgroundDeliveryGateway) return;
    try {
      // Bounded like gateway.poll: a Drive-backed import can hang on a
      // socket the platform killed during suspension, and an unbounded wait
      // here would wedge foreground reconciliation until relaunch.
      final recovered = await (gateway as BackgroundDeliveryGateway)
          .recoverBackgroundDeliveries()
          .timeout(const Duration(minutes: 10));
      if (recovered > 0 && !_disposed) {
        _apply(await gateway.load());
        showNotice(
          recovered == 1
              ? 'A film finished downloading in the background and is safely saved.'
              : '$recovered films finished downloading in the background and are safely saved.',
        );
      }
    } on Object {
      // Recovery is best effort; the retention poller still retries from the
      // provider's delivery link.
    }
  }

  /// Reloads durable generation receipts and immediately resumes polling.
  ///
  /// The app shell calls this when the process returns to the foreground, so
  /// recovery is independent of whichever product screen is visible and does
  /// not wait for the next periodic timer tick.
  Future<void> reconcileGenerationWork() async {
    unawaited(_probeLocalGeneration());
    if (_reconcilingGenerationWork) return;
    _reconcilingGenerationWork = true;
    try {
      // Films the platform transfer service finished while the app was away
      // import first — they remove records from the working set entirely.
      await _recoverBackgroundDeliveries();
      // The process may have been suspended for minutes with polls frozen or
      // failed mid-flight, so the return to the foreground checks every
      // working record immediately instead of honoring failure backoff. This
      // runs before gateway.load(): loading prunes delivery links whose
      // provider retention estimate lapsed while the app was suspended, and a
      // link just past that estimate deserves one recovery attempt first.
      if (hasAnyApiKey) await pollWorking(ignoreSchedule: true);
      _apply(await gateway.load());
      // Drive reconnection can stall on sockets the platform killed during
      // suspension; a bounded wait keeps this reconcile hook responsive for
      // the next foreground return.
      await resumeGoogleDrive().timeout(const Duration(seconds: 30));
    } on Object {
      // Foreground reconciliation is best effort. The global poll timer keeps
      // retrying, and individual records retain their last provider failure.
    } finally {
      _reconcilingGenerationWork = false;
    }
  }

  void _apply(LocalSnapshot value, {bool restorePreferences = false}) {
    final previouslyReady = snapshot == null
        ? null
        : <String>{
            for (final item in snapshot!.generations)
              if (item.isReady && item.hasDeliveredMedia) item.localId,
          };
    snapshot = restorePreferences
        ? value
        : LocalSnapshot(
            generations: value.generations,
            folders: value.folders,
            savedReferences: value.savedReferences,
            preferences: _preferences(),
            hasApiKey: value.hasApiKey,
            connectedProviders: value.connectedProviders,
            connectedRewriteProviders: value.connectedRewriteProviders,
            availableProviders: value.availableProviders,
            providerRetentionAcknowledgements:
                value.providerRetentionAcknowledgements,
            storage: value.storage,
            settingsVault: value.settingsVault,
          );
    _announceNewlyReady(previouslyReady);
    if (restorePreferences) {
      themeMode = value.preferences.themeMode;
      section = value.preferences.activeSection;
      libraryFilter = value.preferences.libraryFilter;
      recentWorkViewMode = value.preferences.recentWorkViewMode;
      libraryViewMode = value.preferences.libraryViewMode;
      libraryStorageFilter = value.preferences.libraryStorageFilter;
      referenceStorageFilter = value.preferences.referenceStorageFilter;
      generationPlaceholderStyle = value.preferences.generationPlaceholderStyle;
      localVideoCacheMb = value.preferences.localVideoCacheMb;
      localThumbnailCacheMb = value.preferences.localThumbnailCacheMb;
      autoFixReferenceVideos = value.preferences.autoFixReferenceVideos;
      costDeskColumns = value.preferences.costDeskColumns;
      rewriteProviderId = value.preferences.rewriteProvider;
      rewriteModelIds
        ..clear()
        ..addAll(value.preferences.rewriteModels);
      rewriteEfforts
        ..clear()
        ..addAll(value.preferences.rewriteEfforts);
      favoriteModelKeys = List<String>.unmodifiable(
        value.preferences.favoriteModels,
      );
      favoriteProviderIds = List<String>.unmodifiable(
        value.preferences.favoriteProviders,
      );
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
      for (final tab in _composerTabs) {
        if (!_composerTabsRestored) {
          // Before the saved strip is read back, the tab in front simply
          // follows the restored studio defaults.
          tab
            ..localFolderId = lastLocalGenerationFolderId
            ..driveFolderId = lastDriveGenerationFolderId;
          continue;
        }
        // Afterwards each tab keeps its own destination, minus any folder
        // that has since gone.
        if (folderById(tab.localFolderId)?.storage != LibraryStorage.local) {
          tab.localFolderId = null;
        }
        if (folderById(tab.driveFolderId)?.storage != LibraryStorage.drive) {
          tab.driveFolderId = null;
        }
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
    _scheduleListingPrefetch();
    notifyListeners();
  }

  void _setSnapshot(LocalSnapshot value) => snapshot = value;

  /// Applies an asynchronous library read only if no newer in-memory state
  /// appeared while it was in flight. When requested, a superseded response
  /// is re-read after the competing write finishes so an explicit refresh can
  /// still complete without erasing a newly submitted generation card.
  Future<bool> _applySnapshotRead(
    LocalSnapshot value, {
    required int startedAtRevision,
    bool restorePreferences = false,
    bool reloadIfSuperseded = false,
  }) async {
    if (_snapshotRevision != startedAtRevision) {
      if (!reloadIfSuperseded) return false;
      final reloadRevision = _snapshotRevision;
      value = await gateway.load();
      if (_disposed || _snapshotRevision != reloadRevision) return false;
    }
    if (_disposed) return false;
    _apply(value, restorePreferences: restorePreferences);
    return true;
  }

  void showNotice(String message, {AppNoticeAction? action}) {
    notice = message;
    noticeAction = action;
    noticeSequence += 1;
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(seconds: 4), () {
      notice = null;
      noticeAction = null;
      notifyListeners();
    });
    notifyListeners();
  }

  String? get noticeActionLabel => switch (noticeAction) {
    AppNoticeAction.retryWithVisualNormalization => 'Normalize & retry',
    null => null,
  };

  Future<void> performNoticeAction() async {
    final action = noticeAction;
    if (action == null || submitting) return;
    noticeAction = null;
    notifyListeners();
    switch (action) {
      case AppNoticeAction.retryWithVisualNormalization:
        await setAutoFixReferenceVideos(true);
        await submit();
    }
  }

  /// Surfaces [error] as a cleaned human notice while keeping the raw details
  /// in the debug log.
  void showErrorNotice(Object error) {
    debugPrint('Clawnsole notice for error: $error');
    showNotice(_message(error));
  }

  String _message(Object error) => error
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('ProviderException: ', '')
      .replaceFirst('Exception: ', '');

  bool _isVisualReferenceCompatibilityError(String message) {
    if (autoFixReferenceVideos ||
        (form.keyframes.isEmpty &&
            form.referenceCount(MediaReferenceKind.image) == 0 &&
            form.referenceCount(MediaReferenceKind.video) == 0)) {
      return false;
    }
    final normalized = message.toLowerCase();
    final mentionsVisualMedia = const <String>[
      'reference',
      'keyframe',
      'start frame',
      'end frame',
      'image',
      'video',
      'media',
      'mime',
      'codec',
      'heic',
      'heif',
    ].any(normalized.contains);
    final describesCompatibilityFailure = const <String>[
      'unsupported',
      'unpermitted',
      'not permitted',
      'not allowed',
      'incompatible',
      'invalid mime',
      'invalid image',
      'invalid video',
      'could not decode',
      'failed to decode',
      'cannot decode',
    ].any(normalized.contains);
    return mentionsVisualMedia && describesCompatibilityFailure;
  }

  Future<void> _savePreferences(AppPreferences preferences) {
    _preferenceRevision += 1;
    final operation = _preferenceWrites.then((_) async {
      try {
        _apply(await gateway.setPreferences(preferences));
      } on Object {
        // Mobile and companion Drive tokens are short-lived. The client can
        // still look connected when a preference write (tab selection is one)
        // is the first request to discover expiration. Silently replace the
        // session and retry the idempotent preference write once.
        if (!await resumeGoogleDrive(force: true)) rethrow;
        _apply(await gateway.setPreferences(preferences));
      }
    });
    _preferenceWrites = operation.then<void>((_) {}, onError: (_) {});
    return operation;
  }

  Future<void> navigate(AppSection value) async {
    section = value;
    // Leaving the composer is a natural save point for a half-typed draft.
    _flushComposerTabsSave(onlyIfPending: true);
    _scheduleListingPrefetch();
    notifyListeners();
    // A cache warm-up must never sit between a navigation tap and the first
    // frame of the destination screen. Cards already render their own loading
    // state, so fold retained preview bytes in after the tab is visible.
    unawaited(_restoreCachedPageAfterNavigation(value));
    try {
      await _savePreferences(_preferences(activeSection: value));
    } on Object catch (error) {
      showNotice(_message(error));
    }
  }

  Future<void> _restoreCachedPageAfterNavigation(AppSection value) async {
    await _restoreCachedFirstPage(targetSection: value);
    if (_disposed || section != value) return;
    notifyListeners();
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

  Future<void> setCostDeskColumns(List<String>? value) async {
    costDeskColumns = value == null ? null : List<String>.of(value);
    notifyListeners();
    try {
      await _savePreferences(
        value == null
            ? _preferences(clearCostDeskColumns: true)
            : _preferences(costDeskColumns: costDeskColumns),
      );
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

  Future<void> setAutoFixReferenceVideos(bool value) async {
    autoFixReferenceVideos = value;
    notifyListeners();
    try {
      await _savePreferences(_preferences(autoFixReferenceVideos: value));
    } on Object catch (error) {
      showNotice(_message(error));
    }
  }

  Future<void> setLocalVideoCacheMb(int value) async {
    final clamped = value.clamp(0, 1 << 20);
    localVideoCacheMb = clamped;
    notifyListeners();
    try {
      // The gateway applies the new cap (native sweeps its cache directly;
      // the companion reads the synced preference on its next request).
      await _savePreferences(_preferences(localVideoCacheMb: clamped));
      if (clamped == 0) {
        _prefetchDebounce?.cancel();
        _prefetchedVideoAssets.clear();
        await _videoCacheGateway?.clearVideoCache();
      } else {
        _scheduleListingPrefetch();
      }
      notifyListeners();
    } on Object catch (error) {
      showNotice(_message(error));
    }
  }

  Future<int> videoCacheUsedBytes() async =>
      await _videoCacheGateway?.videoCacheUsedBytes() ?? 0;

  Future<void> setLocalThumbnailCacheMb(int value) async {
    final clamped = value.clamp(0, 1 << 20);
    localThumbnailCacheMb = clamped;
    notifyListeners();
    try {
      await _savePreferences(_preferences(localThumbnailCacheMb: clamped));
      if (clamped == 0) {
        _restoredAssetBytes.clear();
        _assetReadJobs.clear();
        _referencePreviewBytes.clear();
        await _videoCacheGateway?.clearThumbnailCache();
      } else {
        unawaited(_restoreCachedFirstPage().then((_) => notifyListeners()));
      }
      notifyListeners();
    } on Object catch (error) {
      showNotice(_message(error));
    }
  }

  Future<int> thumbnailCacheUsedBytes() async =>
      await _videoCacheGateway?.thumbnailCacheUsedBytes() ?? 0;

  Future<void> clearVideoCache() async {
    try {
      _prefetchedVideoAssets.clear();
      await _videoCacheGateway?.clearVideoCache();
      notifyListeners();
    } on Object catch (error) {
      showNotice(_message(error));
    }
  }

  Future<void> clearThumbnailCache() async {
    try {
      _restoredAssetBytes.clear();
      _assetReadJobs.clear();
      _referencePreviewBytes.clear();
      await _videoCacheGateway?.clearThumbnailCache();
      notifyListeners();
    } on Object catch (error) {
      showNotice(_message(error));
    }
  }

  static const int _listingPrefetchCount = 6;

  /// Queues a background cache fill for the first few Drive-stored films of
  /// the current listing, so tapping a visible card plays instantly. Runs
  /// debounced off the controller's listing state — never from widget
  /// initState — and is superseded when the listing changes again.
  void _scheduleListingPrefetch() {
    if (_videoCacheGateway == null || localVideoCacheMb <= 0) return;
    _prefetchRevision += 1;
    final revision = _prefetchRevision;
    _prefetchDebounce?.cancel();
    if (section != AppSection.create &&
        section != AppSection.library &&
        section != AppSection.references) {
      return;
    }
    _prefetchDebounce = Timer(const Duration(milliseconds: 900), () {
      if (revision != _prefetchRevision) return;
      final assets = section == AppSection.references
          ? filteredSavedReferences
                .where(
                  (item) =>
                      item.kind == MediaReferenceKind.video &&
                      item.storage == LibraryStorage.drive &&
                      item.thumbnailAsset == null,
                )
                .map((item) => item.asset)
          : (section == AppSection.library
                    ? filteredGenerations
                    : visibleGenerations)
                .where(
                  (item) =>
                      item.isReady &&
                      !item.isImage &&
                      item.storage == LibraryStorage.drive,
                )
                .map((item) => item.resultAsset);
      for (final asset in assets.take(_listingPrefetchCount)) {
        _enqueueVideoPrefetch(asset, revision: revision);
      }
    });
  }

  /// Warms full Drive videos newly revealed by a progressive listing page.
  /// Thumbnail reads happen naturally as those cards are built; limiting the
  /// full-film work prevents one scroll from consuming the entire cache.
  void prefetchListedVideos(Iterable<AssetReference?> assets) {
    for (final asset
        in assets
            .whereType<AssetReference>()
            .where((asset) => asset.kind == 'drive')
            .take(_listingPrefetchCount)) {
      _enqueueVideoPrefetch(asset);
    }
  }

  String _assetCacheKey(AssetReference reference) =>
      '${reference.kind}:${reference.value}';

  /// Synchronously available retained bytes restored before first paint.
  Uint8List? cachedAssetBytes(AssetReference? reference) =>
      reference == null ? null : _restoredAssetBytes[_assetCacheKey(reference)];

  /// Returns a reference preview immediately, including a newly generated
  /// frame whose durable thumbnail write is still in flight.
  Uint8List? cachedReferencePreview(SavedReference reference) =>
      cachedAssetBytes(reference.thumbnailAsset) ??
      _referencePreviewBytes[reference.id];

  /// Reads retained preview bytes once per process and remembers them for
  /// synchronous reuse by every card that references the same immutable id.
  Future<Uint8List> readPreviewAsset(AssetReference reference) {
    final key = _assetCacheKey(reference);
    final restored = _restoredAssetBytes[key];
    if (restored != null) return Future<Uint8List>.value(restored);
    final existing = _assetReadJobs[key];
    if (existing != null) return existing;
    late final Future<Uint8List> job;
    job = gateway
        .readAsset(reference)
        .then((bytes) {
          _restoredAssetBytes[key] = bytes;
          return bytes;
        })
        .catchError((Object error) {
          if (identical(_assetReadJobs[key], job)) _assetReadJobs.remove(key);
          throw error;
        });
    _assetReadJobs[key] = job;
    return job;
  }

  /// Restores only the first page and only from local storage. Cache misses
  /// remain misses until a card is actually viewed, at which point its normal
  /// read path downloads and persists the Drive asset.
  Future<void> _restoreCachedFirstPage({AppSection? targetSection}) async {
    final cache = _mediaCacheGateway;
    if (cache == null) return;
    final listingSection = targetSection ?? section;
    final references = <String, AssetReference>{};
    void add(AssetReference? reference) {
      if (reference != null) {
        references[_assetCacheKey(reference)] = reference;
      }
    }

    if (listingSection == AppSection.create ||
        listingSection == AppSection.library) {
      final generationPage = listingSection == AppSection.library
          ? filteredGenerations
          : visibleGenerations;
      for (final item in generationPage.take(20)) {
        if (item.isImage) {
          add(item.resultAsset);
        } else {
          add(item.thumbnailAsset);
        }
      }
    } else if (listingSection == AppSection.references) {
      for (final item in filteredSavedReferences.take(20)) {
        if (item.kind == MediaReferenceKind.image) {
          add(item.asset);
        } else if (item.kind == MediaReferenceKind.video) {
          add(item.thumbnailAsset);
        }
      }
    } else {
      return;
    }
    await Future.wait(
      references.entries.map((entry) async {
        if (_restoredAssetBytes.containsKey(entry.key)) return;
        try {
          final bytes = await cache.cachedAssetBytes(entry.value);
          if (bytes == null || bytes.isEmpty) return;
          _restoredAssetBytes[entry.key] = bytes;
        } on Object {
          // Cache inspection is best effort and must not delay app recovery.
        }
      }),
    );
  }

  /// Serially fills the video cache in the background. [revision] cancels a
  /// listing pass that was superseded before its turn came up; ready-film
  /// prefetches pass none and always run.
  void _enqueueVideoPrefetch(AssetReference? asset, {int? revision}) {
    final cacheGateway = _videoCacheGateway;
    if (cacheGateway == null || localVideoCacheMb <= 0) return;
    if (asset == null || asset.kind != 'drive') return;
    if (!_prefetchedVideoAssets.add(asset.value)) return;
    _prefetchQueue = _prefetchQueue.then((_) async {
      if (localVideoCacheMb <= 0 ||
          (revision != null && revision != _prefetchRevision)) {
        _prefetchedVideoAssets.remove(asset.value);
        return;
      }
      try {
        await cacheGateway.prefetchVideoAsset(asset);
        _markVideoPreviewSourceAvailable();
      } on Object {
        // A failed prefetch (offline, Drive expired) may retry on the next
        // listing pass; playback itself still downloads on demand.
        _prefetchedVideoAssets.remove(asset.value);
      }
    });
  }

  void _markVideoPreviewSourceAvailable() {
    if (_disposed) return;
    _videoPreviewSourceRevision += 1;
    notifyListeners();
  }

  /// The destination folder of the tab in front. The `last…` fields stay the
  /// studio-wide defaults a new tab starts from.
  String? get selectedGenerationFolderId =>
      effectiveStorage == LibraryStorage.drive
      ? activeComposerTab.driveFolderId
      : activeComposerTab.localFolderId;

  Future<void> setGenerationFolder(String? folderId) async {
    final folder = folderById(folderId);
    if (folderId != null &&
        (folder == null || folder.storage != effectiveStorage)) {
      showNotice('That destination folder is no longer available.');
      return;
    }
    final tab = activeComposerTab;
    if (effectiveStorage == LibraryStorage.drive) {
      tab.driveFolderId = folderId;
      lastDriveGenerationFolderId = folderId;
    } else {
      tab.localFolderId = folderId;
      lastLocalGenerationFolderId = folderId;
    }
    _scheduleComposerTabsSave(touched: tab);
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
    _scheduleListingPrefetch();
    notifyListeners();
  }

  void setReferenceFavoriteFilter(FavoriteFilter value) {
    referenceFavoriteFilter = value;
    notifyListeners();
  }

  void setLibraryVisibilityFilter(VisibilityFilter value) {
    libraryVisibilityFilter = value;
    _scheduleListingPrefetch();
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
    _setSnapshot(
      snapshot!.copyWith(
        generations: generations
            .map(
              (candidate) => candidate.localId == item.localId
                  ? candidate.copyWith(favorite: favorite)
                  : candidate,
            )
            .toList(),
      ),
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
        _setSnapshot(
          snapshot!.copyWith(
            generations: generations
                .map(
                  (candidate) => candidate.localId == item.localId
                      ? candidate.copyWith(favorite: current.favorite)
                      : candidate,
                )
                .toList(),
          ),
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
    _setSnapshot(
      snapshot!.copyWith(
        savedReferences: savedReferences
            .map(
              (candidate) => candidate.id == item.id
                  ? candidate.copyWith(favorite: favorite)
                  : candidate,
            )
            .toList(),
      ),
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
        _setSnapshot(
          snapshot!.copyWith(
            savedReferences: savedReferences
                .map(
                  (candidate) => candidate.id == item.id
                      ? candidate.copyWith(favorite: current.favorite)
                      : candidate,
                )
                .toList(),
          ),
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
    _setSnapshot(
      snapshot!.copyWith(
        generations: generations
            .map(
              (item) => ids.contains(item.localId)
                  ? item.copyWith(hidden: hidden)
                  : item,
            )
            .toList(),
      ),
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
        _setSnapshot(
          snapshot!.copyWith(
            generations: generations.map((item) {
              if (_generationVisibilityRevisions[item.localId] != revision) {
                return item;
              }
              return item.copyWith(hidden: previous[item.localId]);
            }).toList(),
          ),
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
    _setSnapshot(
      snapshot!.copyWith(
        savedReferences: savedReferences
            .map(
              (item) =>
                  ids.contains(item.id) ? item.copyWith(hidden: hidden) : item,
            )
            .toList(),
      ),
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
        _setSnapshot(
          snapshot!.copyWith(
            savedReferences: savedReferences.map((item) {
              if (_referenceVisibilityRevisions[item.id] != revision) {
                return item;
              }
              return item.copyWith(hidden: previous[item.id]);
            }).toList(),
          ),
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
    _scheduleListingPrefetch();
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
    _revealFolder(value, LibraryCollection.generated);
    _scheduleListingPrefetch();
    notifyListeners();
  }

  void setLibraryTag(String? value) {
    libraryTag = value;
    _scheduleListingPrefetch();
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
    _revealFolder(value, LibraryCollection.references);
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

  void setLibraryOutputKind(GenerationOutputKind? value) {
    libraryOutputKind = value;
    _scheduleListingPrefetch();
    notifyListeners();
  }

  void setReferenceSort(ReferenceSort value) {
    referenceSort = value;
    notifyListeners();
  }

  List<String> cleanLibraryTags(Iterable<String> input) =>
      library_rules.cleanLibraryTags(input);

  Future<bool> saveLibraryFolder(
    String name, {
    LibraryFolder? existing,
    String? parentId,
    LibraryCollection collection = LibraryCollection.generated,
    LibraryStorage? storage,
    String? successNotice,
  }) async {
    final clean = name.trim();
    if (!library_rules.isValidLibraryFolderName(clean)) {
      showNotice(library_rules.libraryFolderNameRule);
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
      updatedAt: now,
      parentId: parentId,
      collection: existing?.collection ?? collection,
      storage: destination,
    );
    try {
      _apply(await organization.saveLibraryFolder(folder));
      if (parentId != null) collapsedFolderIds.remove(parentId);
      showNotice(
        successNotice ??
            (existing == null ? 'Folder created.' : 'Folder updated.'),
      );
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
    final requestedName = name.trim();
    final usesUploadFilename =
        requestedName == draft.label.trim() &&
        isReservedReferenceName(referencePromptName(draft));
    final problem = usesUploadFilename
        ? null
        : referenceNameProblem(
            requestedName,
            excludeDraftId: draft.id,
            excludeSavedReferenceId: draft.savedReferenceId,
          );
    if (problem != null) {
      showNotice(problem);
      return null;
    }
    final clean = usesUploadFilename
        ? _uniqueSavedReferenceName(
            requestedName,
            excludeSavedReferenceId: draft.savedReferenceId,
          )
        : requestedName;
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
      durationSeconds: draft.durationSeconds,
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
          promptName: item.promptName,
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
          durationSeconds:
              savedReference.durationSeconds ?? item.durationSeconds,
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
    final problem = referenceNameProblem(
      clean,
      excludeSavedReferenceId: reference.id,
    );
    if (problem != null) {
      showNotice(problem);
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
      if (reference.name != clean) {
        form.prompt = renameReferenceInPrompt(
          form.prompt,
          oldName: reference.name,
          newName: clean,
        );
        form.references = form.references.map((draft) {
          if (draft.savedReferenceId != reference.id) return draft;
          final oldPromptName = referencePromptName(draft);
          form.prompt = renameReferenceInPrompt(
            form.prompt,
            oldName: oldPromptName,
            newName: clean,
          );
          return draft.copyWith(promptName: clean);
        }).toList();
      }
      notifyListeners();
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
    MediaPickerSource source = MediaPickerSource.library,
    ReferencePreviewLoader? previewLoader,
  }) async {
    if (gateway is! ReferenceLibraryGateway) return;
    _beginReferenceUpload('Waiting for ${kind.label.toLowerCase()} selection…');
    List<PickedAsset> picked;
    try {
      picked = await _pickMany(switch (kind) {
        MediaReferenceKind.image => FileType.image,
        MediaReferenceKind.video => FileType.video,
        MediaReferenceKind.audio => FileType.audio,
      }, source: source);
    } on Object catch (error) {
      showNotice(_message(error));
      return;
    } finally {
      _finishReferenceUpload();
    }
    await importPickedReferences(
      kind,
      picked,
      folderId: folderId,
      storage: storage,
      previewLoader: previewLoader,
    );
  }

  /// Saves already-picked media into the References library. Progress cards
  /// appear immediately; the saves run on the background work queue so the
  /// add buttons never lock while files process.
  Future<void> importPickedReferences(
    MediaReferenceKind kind,
    List<PickedAsset> picked, {
    String? folderId,
    LibraryStorage? storage,
    ReferencePreviewLoader? previewLoader,
  }) async {
    if (gateway is! ReferenceLibraryGateway || picked.isEmpty) return;
    final destination =
        folderById(
          folderId,
          collection: LibraryCollection.references,
        )?.storage ??
        storage ??
        effectiveStorage;
    if (destination == LibraryStorage.drive && !googleDriveConnected) {
      showNotice('Connect Google Drive before importing Drive references.');
      return;
    }
    final startedAt = DateTime.now().toUtc();
    final imports = <ReferenceImportProgress>[
      for (final entry in picked.indexed)
        ReferenceImportProgress(
          id: 'reference-${startedAt.microsecondsSinceEpoch.toRadixString(36)}-${_idCounter++}',
          name: entry.$2.name,
          kind: kind,
          storage: destination,
          folderId: folderId,
          stage: ReferenceImportStage.queued,
          position: entry.$1 + 1,
          total: picked.length,
        ),
    ];
    final importIds = imports.map((item) => item.id).toList();
    _referenceImports.addAll(imports);
    _beginReferenceUpload('Preparing ${picked.first.name}…');
    try {
      await _enqueueReferenceWork(() async {
        var saved = 0;
        var failed = 0;
        Object? lastError;
        for (final entry in picked.indexed) {
          final asset = entry.$2;
          final now = DateTime.now().toUtc();
          final progress = imports[entry.$1];
          final reference = SavedReference(
            id: progress.id,
            name: _uniqueSavedReferenceName(asset.name),
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
          try {
            _setReferenceImportStage(
              progress.id,
              ReferenceImportStage.preparing,
            );
            _updateReferenceUpload(
              'Preparing ${asset.name} (${entry.$1 + 1} of ${picked.length})…',
            );
            final dataUrl = await _dataUrlForAsset(asset);
            var thumbnailBytes = asset.thumbnailBytes;
            if (kind == MediaReferenceKind.video &&
                thumbnailBytes == null &&
                previewLoader != null) {
              try {
                thumbnailBytes = await previewLoader(asset, dataUrl);
              } on Object {
                // Preview creation is best effort; the retained video can
                // also backfill its frame after the card is rendered.
              }
            }
            _setReferenceImportStage(
              progress.id,
              ReferenceImportStage.uploading,
            );
            _updateReferenceUpload(
              'Uploading ${asset.name} (${entry.$1 + 1} of ${picked.length})…',
            );
            _apply(
              await (gateway as ReferenceLibraryGateway).saveReference(
                reference,
                source: dataUrl,
              ),
            );
            final savedReference = savedReferences
                .where((item) => item.id == reference.id)
                .firstOrNull;
            if (savedReference != null &&
                savedReference.thumbnailAsset == null &&
                thumbnailBytes != null &&
                thumbnailBytes.isNotEmpty) {
              await cacheReferencePreview(savedReference, thumbnailBytes);
            }
            saved += 1;
          } on Object catch (error) {
            failed += 1;
            lastError = error;
          } finally {
            _referenceImports.removeWhere((item) => item.id == progress.id);
            notifyListeners();
          }
        }
        if (failed > 0) {
          showNotice('$saved saved, $failed failed. ${_message(lastError!)}');
        } else if (saved > 0) {
          showNotice('$saved ${kind.pluralLabel} saved to References.');
        }
      });
    } on Object catch (error) {
      showNotice(_message(error));
    } finally {
      _referenceImports.removeWhere((item) => importIds.contains(item.id));
      _finishReferenceUpload();
    }
  }

  void _setReferenceImportStage(String id, ReferenceImportStage stage) {
    final index = _referenceImports.indexWhere((item) => item.id == id);
    if (index < 0 || _referenceImports[index].stage == stage) return;
    _referenceImports[index] = _referenceImports[index].copyWith(stage: stage);
    notifyListeners();
  }

  Future<bool> deleteSavedReference(String referenceId) async {
    if (gateway is! ReferenceLibraryGateway) return false;
    try {
      _apply(
        await (gateway as ReferenceLibraryGateway).deleteReference(referenceId),
      );
      _referencePreviewBytes.remove(referenceId);
      showNotice('Saved reference deleted.');
      return true;
    } on Object catch (error) {
      showNotice(_message(error));
      return false;
    }
  }

  String suggestedTrimmedReferenceName(SavedReference source) =>
      _uniqueSavedReferenceName('${source.name} trim');

  Future<SavedReference?> trimSavedReference(
    SavedReference source, {
    required String name,
    required double startSeconds,
    required double endSeconds,
  }) async {
    if (gateway is! ReferenceVideoEditingGateway) {
      showNotice('Video trimming is unavailable on this build.');
      return null;
    }
    final current = savedReferences
        .where((item) => item.id == source.id)
        .firstOrNull;
    final duration = current?.durationSeconds;
    if (current == null ||
        current.kind != MediaReferenceKind.video ||
        duration == null ||
        !startSeconds.isFinite ||
        !endSeconds.isFinite ||
        startSeconds < 0 ||
        endSeconds > duration + .001 ||
        endSeconds - startSeconds < .1) {
      showNotice('Choose a valid range within the reference video.');
      return null;
    }
    if (startSeconds < .001 && (endSeconds - duration).abs() < .001) {
      showNotice('Move the beginning or ending handle to create a trim.');
      return null;
    }
    final clean = name.trim();
    final problem = referenceNameProblem(clean);
    if (problem != null) {
      showNotice(problem);
      return null;
    }
    final now = DateTime.now().toUtc();
    final id =
        'reference-trim-${now.microsecondsSinceEpoch.toRadixString(36)}-${_idCounter++}';
    final output = SavedReference(
      id: id,
      name: clean,
      kind: MediaReferenceKind.video,
      asset: AssetReference(
        kind: 'remote',
        value: '',
        label: clean,
        contentType: 'video/mp4',
      ),
      createdAt: now,
      updatedAt: now,
      folderId: current.folderId,
      tags: current.tags,
      storage: current.storage,
      durationSeconds: endSeconds - startSeconds,
    );
    _beginReferenceUpload('Trimming ${current.name}…');
    try {
      _apply(
        await _enqueueReferenceWork(
          () => (gateway as ReferenceVideoEditingGateway).trimReferenceVideo(
            sourceReferenceId: current.id,
            output: output,
            startSeconds: startSeconds,
            endSeconds: endSeconds,
          ),
        ),
      );
      final saved = savedReferences
          .where((item) => item.id == output.id)
          .firstOrNull;
      if (saved == null) {
        throw StateError('The trimmed reference was not saved.');
      }
      showNotice('“${saved.name}” saved as a new reference.');
      return saved;
    } on Object catch (error) {
      showNotice(_message(error));
      return null;
    } finally {
      _finishReferenceUpload();
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
            durationSeconds: item.config.duration is num
                ? (item.config.duration as num).toDouble()
                : null,
          );
        })
        .toList();
  }

  Future<void> addReferenceCandidates(
    MediaReferenceKind kind,
    Iterable<ReferenceCandidate> candidates,
  ) async {
    final tab = activeComposerTab;
    final available = referenceLimit(kind) - form.referenceCount(kind);
    final selected = candidates
        .where((item) => item.kind == kind)
        .take(available < 0 ? 0 : available)
        .toList();
    if (selected.isEmpty) return;
    // Drafts appear immediately; media bytes hydrate on the background work
    // queue so choosing saved references never blocks further adds — even
    // when the media has to come down from Google Drive first.
    final hydrating = <(String, ReferenceCandidate)>[];
    _inComposerTab(tab, () {
      for (final candidate in selected) {
        if (!candidate.generated &&
            form.references.any(
              (reference) => reference.savedReferenceId == candidate.id,
            )) {
          showNotice('“${candidate.name}” is already attached.');
          continue;
        }
        final promptName = candidate.generated
            ? _nextReferencePromptName(kind)
            : candidate.name.trim();
        final nameProblem = candidate.generated
            ? null
            : referenceNameProblem(
                promptName,
                excludeSavedReferenceId: candidate.id,
              );
        if (nameProblem != null) {
          showNotice(nameProblem);
          continue;
        }
        final draftId = _uid();
        form.references = <MediaReferenceDraft>[
          ...form.references,
          MediaReferenceDraft(
            id: draftId,
            label: candidate.name,
            kind: kind,
            source: candidate.asset.isLocal ? '' : candidate.asset.value,
            promptName: promptName,
            retained: candidate.asset,
            thumbnailAsset: _previewForStorage(
              candidate.thumbnailAsset,
              effectiveStorage,
            ),
            savedReferenceId: candidate.generated ? null : candidate.id,
            durationSeconds: candidate.durationSeconds,
          ),
        ];
        if (candidate.asset.isLocal) {
          hydrating.add((draftId, candidate));
          _hydratingReferenceDraftIds.add(draftId);
        }
      }
      _selectCompatibleModel();
      _normalizeFormForModel();
      _invalidateProviderEstimate();
      _scheduleComposerTabsSave();
    });
    notifyListeners();
    if (hydrating.isEmpty) return;
    _beginReferenceUpload('Loading ${kind.pluralLabel}…');
    try {
      await _enqueueReferenceWork(() async {
        for (final entry in hydrating.indexed) {
          final (draftId, candidate) = entry.$2;
          if (!tab.form.references.any((item) => item.id == draftId)) {
            _hydratingReferenceDraftIds.remove(draftId);
            continue; // Removed while queued.
          }
          _updateReferenceUpload(
            'Loading ${candidate.name} '
            '(${entry.$1 + 1} of ${hydrating.length})…',
          );
          try {
            Uint8List? thumbnailBytes;
            if (candidate.thumbnailAsset != null) {
              try {
                thumbnailBytes = await gateway.readAsset(
                  candidate.thumbnailAsset!,
                );
              } on Object {
                // The media itself can still make a fresh preview frame.
              }
            }
            final bytes = await gateway.readAsset(candidate.asset);
            _inComposerTab(
              tab,
              () => _hydrateReferenceDraft(
                draftId,
                candidate,
                bytes,
                thumbnailBytes,
              ),
            );
          } on Object catch (error) {
            _inComposerTab(
              tab,
              () =>
                  _dropUnhydratedReferenceDraft(draftId, candidate.name, error),
            );
          } finally {
            _hydratingReferenceDraftIds.remove(draftId);
          }
        }
      });
    } finally {
      _finishReferenceUpload();
    }
  }

  void _hydrateReferenceDraft(
    String draftId,
    ReferenceCandidate candidate,
    Uint8List bytes,
    Uint8List? thumbnailBytes,
  ) {
    final index = form.references.indexWhere((item) => item.id == draftId);
    if (index < 0) return;
    final current = form.references[index];
    final references = List<MediaReferenceDraft>.from(form.references);
    references[index] = MediaReferenceDraft(
      id: current.id,
      label: current.label,
      kind: current.kind,
      source: current.source,
      promptName: current.promptName,
      asset: PickedAsset(
        name: candidate.name,
        bytes: bytes,
        mimeType:
            candidate.asset.contentType ?? _fallbackMimeType(candidate.kind),
        retained: candidate.asset,
        thumbnailAsset: candidate.thumbnailAsset,
        thumbnailBytes: thumbnailBytes,
      ),
      retained: current.retained,
      thumbnailAsset: current.thumbnailAsset,
      thumbnailBytes: thumbnailBytes ?? current.thumbnailBytes,
      savedReferenceId: current.savedReferenceId,
      durationSeconds: current.durationSeconds,
    );
    form.references = references;
    notifyListeners();
  }

  /// Media that cannot be loaded cannot join a generation, so the draft is
  /// withdrawn instead of blocking Generate with an empty source forever.
  void _dropUnhydratedReferenceDraft(
    String draftId,
    String name,
    Object error,
  ) {
    final before = form.references.length;
    form.references = form.references
        .where((item) => item.id != draftId)
        .toList();
    if (form.references.length != before) {
      _invalidateProviderEstimate();
      notifyListeners();
    }
    showNotice('“$name” could not be loaded. ${_message(error)}');
  }

  String _fallbackMimeType(MediaReferenceKind kind) => switch (kind) {
    MediaReferenceKind.image => 'image/png',
    MediaReferenceKind.video => 'video/mp4',
    MediaReferenceKind.audio => 'audio/mpeg',
  };

  PickedAsset _withSavedReference(
    PickedAsset asset,
    SavedReference reference,
  ) => PickedAsset(
    name: asset.name,
    bytes: asset.bytes,
    mimeType: asset.mimeType,
    path: asset.path,
    retained: reference.asset,
    thumbnailAsset: reference.thumbnailAsset ?? asset.thumbnailAsset,
    thumbnailBytes: asset.thumbnailBytes,
  );

  /// Retains Create uploads in References before they enter a generation.
  /// Content hashes make repeated uploads idempotent, while a one-time byte
  /// comparison links legacy saved references that predate those hashes.
  Future<SavedReference?> _autoSaveVisualReference(
    MediaReferenceKind kind,
    PickedAsset asset,
  ) async {
    if (kind == MediaReferenceKind.audio ||
        snapshot == null ||
        gateway is! ReferenceLibraryGateway) {
      return null;
    }
    // Videos can be hundreds of megabytes, so keep content-addressing off the
    // UI isolate on native platforms.
    _updateReferenceUpload('Processing ${asset.name}…');
    final digest = await compute(_sha256Digest, asset.bytes);
    SavedReference? existing = savedReferences
        .where(
          (reference) =>
              reference.kind == kind && reference.contentDigest == digest,
        )
        .firstOrNull;
    if (existing == null) {
      for (final candidate in savedReferences.where(
        (reference) =>
            reference.kind == kind &&
            reference.contentDigest == null &&
            reference.asset.bytes == asset.bytes.length,
      )) {
        try {
          final bytes = await gateway.readAsset(candidate.asset);
          if (await compute(_sha256Digest, bytes) == digest) {
            existing = candidate;
            break;
          }
        } on Object {
          // An unavailable legacy asset cannot be the upload we just read.
        }
      }
    }
    final library = gateway as ReferenceLibraryGateway;
    if (existing != null) {
      if (existing.contentDigest == null) {
        _apply(
          await library.saveReference(existing.copyWith(contentDigest: digest)),
        );
        return savedReferences
            .where((reference) => reference.id == existing!.id)
            .firstOrNull;
      }
      return existing;
    }
    final now = DateTime.now().toUtc();
    final cleanName = asset.name.trim().isEmpty
        ? '${kind.label} reference'
        : asset.name.trim();
    final uniqueName = _uniqueSavedReferenceName(cleanName);
    final reference = SavedReference(
      id: 'reference-${kind.name}-${digest.substring(0, 24)}',
      name: uniqueName,
      kind: kind,
      asset: AssetReference(
        kind: 'remote',
        value: '',
        label: asset.name,
        contentType: asset.mimeType,
        bytes: asset.bytes.length,
      ),
      thumbnailAsset: _previewForStorage(
        asset.thumbnailAsset,
        effectiveStorage,
      ),
      createdAt: now,
      updatedAt: now,
      storage: effectiveStorage,
      contentDigest: digest,
    );
    _updateReferenceUpload('Uploading ${asset.name}…');
    final dataUrl = await _dataUrlForAsset(asset);
    _apply(await library.saveReference(reference, source: dataUrl));
    return savedReferences
        .where((candidate) => candidate.id == reference.id)
        .firstOrNull;
  }

  Future<String> _dataUrlForAsset(PickedAsset asset) async {
    // Spinning up a worker costs more than the encoding for small images and
    // audio snippets. Larger media still stays off the UI isolate.
    final payload = asset.bytes.length < 256 * 1024
        ? _base64Payload(asset.bytes)
        : await compute(_base64Payload, asset.bytes);
    return 'data:${asset.mimeType};base64,$payload';
  }

  Future<SavedReference?> _retainCreateUpload(
    MediaReferenceKind kind,
    PickedAsset asset,
  ) async {
    try {
      return await _autoSaveVisualReference(kind, asset);
    } on Object catch (error) {
      // A library/storage problem should not make an otherwise valid provider
      // reference unusable for the current generation.
      showNotice(
        'Reference added, but it could not be saved to References. '
        '${_message(error)}',
      );
      return null;
    }
  }

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
    _scheduleComposerTabsSave();
    notifyListeners();
  }

  void setGenerateAudio(bool value) {
    _generateAudioExplicitlyDisabled = !value;
    updateForm((form) => form.generateAudio = value);
  }

  bool _generationExplicitlyDisabledAudio(Generation item) {
    final provider = providers
        .where((candidate) => candidate.id == item.provider)
        .firstOrNull;
    final model = provider?.models
        .where((candidate) => candidate.id == item.model)
        .firstOrNull;
    return !item.config.generateAudio && model?.supportsAudio == true;
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
    List<String>? costDeskColumns,
    bool clearCostDeskColumns = false,
    int? localVideoCacheMb,
    int? localThumbnailCacheMb,
    bool? autoFixReferenceVideos,
    AppThemeMode? themeMode,
    List<String>? favoriteModels,
    List<String>? favoriteProviders,
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
    costDeskColumns: clearCostDeskColumns
        ? null
        : costDeskColumns ?? this.costDeskColumns,
    localVideoCacheMb: localVideoCacheMb ?? this.localVideoCacheMb,
    localThumbnailCacheMb: localThumbnailCacheMb ?? this.localThumbnailCacheMb,
    autoFixReferenceVideos:
        autoFixReferenceVideos ?? this.autoFixReferenceVideos,
    themeMode: themeMode ?? this.themeMode,
    rewriteProvider: rewriteProviderId,
    rewriteModels: Map<String, String>.of(rewriteModelIds),
    rewriteEfforts: Map<String, String>.of(rewriteEfforts),
    favoriteModels: favoriteModels ?? favoriteModelKeys,
    favoriteProviders: favoriteProviders ?? favoriteProviderIds,
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
          mode: form.mode,
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
      if (form.keyframes.length > model.maxKeyframesFor(form.mode)) {
        return false;
      }
      for (final kind in MediaReferenceKind.values) {
        if (form.referenceCount(kind) > model.maxReferences(kind, form.mode)) {
          return false;
        }
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
    _scheduleComposerTabsSave();
    notifyListeners();
    _kickProviderRefresh(provider);
    await _persistSelection();
  }

  Future<void> selectModel(String modelId) async {
    selectedModelId = modelById(selectedProviderId, modelId).id;
    _normalizeFormForModel();
    _invalidateProviderEstimate();
    _scheduleComposerTabsSave();
    notifyListeners();
    await _persistSelection();
  }

  /// Applies a provider and model choice in one synchronous pass, so the form
  /// reflects the tapped model immediately instead of showing the provider's
  /// default model until the preference write lands.
  Future<void> selectProviderModel(String providerId, String modelId) async {
    final provider = providerById(providerId);
    if (!providers.any((item) => item.id == provider.id)) return;
    final providerChanged = selectedProviderId != provider.id;
    selectedProviderId = provider.id;
    selectedModelId = modelById(provider.id, modelId).id;
    // An unknown model id falls back to the provider default, which must then
    // defer to whichever model accepts the current form.
    if (selectedModelId != modelId) _selectCompatibleModel();
    _normalizeFormForModel();
    _invalidateProviderEstimate();
    credits = providerAccounts[provider.id]?.balance;
    _scheduleComposerTabsSave();
    notifyListeners();
    if (providerChanged) _kickProviderRefresh(provider);
    await _persistSelection();
  }

  /// Kicks the balance and live catalog refreshes for [provider] without
  /// gating the form; fresh pricing arrives in the background.
  void _kickProviderRefresh(VideoProviderDefinition provider) {
    if (!provider.requiresApiKey) return;
    if (hasApiKey) unawaited(refreshCredits());
    unawaited(refreshProviderModels(provider.id));
  }

  /// Persists preferences after selection state has already been applied and
  /// announced, so a slow store write never delays the next interaction.
  Future<void> _persistSelection() async {
    try {
      await _savePreferences(_preferences());
    } on Object catch (error) {
      showNotice(_message(error));
    }
  }

  void _normalizeFormForModel() {
    final model = selectedModel;
    _reconcileReferencesForModel(model);
    form.upscale = model.isUpscaler;
    if (!model.supportsAutoDuration) form.autoDuration = false;
    if (!model.supportsAudio) {
      form.generateAudio = false;
    } else if (!_generateAudioExplicitlyDisabled) {
      form.generateAudio = true;
    }
    if (!model.supportsDraft) form.draft = false;
    if (!model.supportsTimedKeyframes) form.exactTiming = false;
    if (!model.referenceTasks.contains(form.referenceTask)) {
      form.referenceTask = MediaReferenceTask.reference;
    }
    if (!model.supportsSeed) form.seed = null;
    if (model.upscaleUsesResolutionTargets && form.upscaleCreativity <= 1) {
      form.upscaleCreativity = 50;
    } else if (model.isUpscaler &&
        !model.upscaleUsesResolutionTargets &&
        form.upscaleCreativity > 1) {
      form.upscaleCreativity = 1;
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

  /// Keeps incompatible creative references out of mode inference, request
  /// validation, pricing, and provider payloads while preserving the Create
  /// draft in case the user switches back to a reference-capable model.
  void _reconcileReferencesForModel(VideoModelDefinition model) {
    if (!model.supportsMediaReferences) {
      if (form.references.isEmpty) return;
      final disabledById = <String, MediaReferenceDraft>{
        for (final reference in _disabledReferences) reference.id: reference,
        for (final reference in form.references) reference.id: reference,
      };
      _disabledReferences
        ..clear()
        ..addAll(disabledById.values);
      form.references = <MediaReferenceDraft>[];
      return;
    }
    if (_disabledReferences.isEmpty) return;
    final activeIds = form.references.map((reference) => reference.id).toSet();
    form.references = <MediaReferenceDraft>[
      ..._disabledReferences.where(
        (reference) => !activeIds.contains(reference.id),
      ),
      ...form.references,
    ];
    _disabledReferences.clear();
  }

  Future<PickedAsset?> _pick({
    required FileType type,
    MediaPickerSource source = MediaPickerSource.library,
  }) async {
    final result = await _filePicker(
      type: source == MediaPickerSource.files ? FileType.any : type,
      allowMultiple: false,
      withData: true,
    );
    final file = result?.files.firstOrNull;
    if (file == null) return null;
    final asset = _assetFromFile(file);
    _requireExpectedFileType(asset, type, source);
    return asset;
  }

  Future<List<PickedAsset>> _pickMany(
    FileType type, {
    MediaPickerSource source = MediaPickerSource.library,
  }) async {
    final result = await _filePicker(
      type: source == MediaPickerSource.files ? FileType.any : type,
      allowMultiple: true,
      withData: true,
    );
    final assets = <PickedAsset>[];
    for (final file in result?.files ?? const <PlatformFile>[]) {
      final asset = _assetFromFile(file);
      _requireExpectedFileType(asset, type, source);
      assets.add(asset);
    }
    return assets;
  }

  PickedAsset _assetFromFile(PlatformFile file) {
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

  void _requireExpectedFileType(
    PickedAsset asset,
    FileType expected,
    MediaPickerSource source,
  ) {
    if (source != MediaPickerSource.files || _matchesType(asset, expected)) {
      return;
    }
    final label = switch (expected) {
      FileType.image => 'an image',
      FileType.video => 'a video',
      FileType.audio => 'an audio',
      _ => 'a compatible',
    };
    throw StateError('Choose $label file from Files.');
  }

  bool _matchesType(PickedAsset asset, FileType expected) {
    if (expected == FileType.any || expected == FileType.custom) return true;
    final mimeType = asset.mimeType.toLowerCase();
    if (expected == FileType.media) {
      return mimeType.startsWith('image/') ||
          mimeType.startsWith('video/') ||
          _matchesExtension(asset.name, FileType.image) ||
          _matchesExtension(asset.name, FileType.video);
    }
    final prefix = switch (expected) {
      FileType.image => 'image/',
      FileType.video => 'video/',
      FileType.audio => 'audio/',
      _ => '',
    };
    return mimeType.startsWith(prefix) ||
        _matchesExtension(asset.name, expected);
  }

  bool _matchesExtension(String name, FileType expected) {
    final separator = name.lastIndexOf('.');
    if (separator < 0 || separator == name.length - 1) return false;
    return (_mediaExtensions[expected] ?? const <String>{}).contains(
      name.substring(separator + 1).toLowerCase(),
    );
  }

  static const Map<FileType, Set<String>> _mediaExtensions =
      <FileType, Set<String>>{
        FileType.image: <String>{
          'jpg',
          'jpeg',
          'png',
          'gif',
          'webp',
          'heic',
          'heif',
          'hif',
          'avif',
          'tif',
          'tiff',
          'bmp',
          'dng',
        },
        FileType.video: <String>{
          'mp4',
          'mov',
          'm4v',
          'avi',
          'mkv',
          'webm',
          'mpg',
          'mpeg',
          '3gp',
          '3g2',
          'ts',
          'mts',
          'm2ts',
          'wmv',
          'flv',
          'ogv',
        },
        FileType.audio: <String>{
          'mp3',
          'm4a',
          'aac',
          'wav',
          'aiff',
          'aif',
          'flac',
          'ogg',
          'oga',
          'opus',
          'wma',
          'caf',
          'amr',
        },
      };

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
      form.keyframes.length < keyframeLimit &&
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

  VideoModelDefinition? _modelForReferenceAsFirstFrame(
    MediaReferenceDraft reference,
  ) {
    if (reference.kind != MediaReferenceKind.image || form.hasStartFrame) {
      return null;
    }
    final remainingReferences = form.references
        .where((item) => item.id != reference.id)
        .toList();

    bool accepts(VideoModelDefinition model) {
      if (!model.modes.contains(VideoMode.i2v) ||
          !model.supportsStartFrame ||
          !model.referenceTasks.contains(form.referenceTask) ||
          form.keyframes.length + 1 > model.maxKeyframesFor(VideoMode.i2v)) {
        return false;
      }
      if (form.keyframes.any(
        (frame) => switch (frame.role) {
          KeyframeRole.start => true,
          KeyframeRole.middle => !model.supportsTimedKeyframes,
          KeyframeRole.end => !model.supportsEndFrame,
        },
      )) {
        return false;
      }
      if (model.framesExclusiveWithReferences &&
          remainingReferences.isNotEmpty) {
        return false;
      }
      for (final kind in MediaReferenceKind.values) {
        if (remainingReferences.where((item) => item.kind == kind).length >
            model.maxReferences(kind, VideoMode.i2v)) {
          return false;
        }
      }
      final totalLimit = model.maxTotalReferences;
      return totalLimit == null || remainingReferences.length <= totalLimit;
    }

    if (accepts(selectedModel)) return selectedModel;
    final sameModelFamily = selectedProvider.models
        .where((model) => model.canonicalId == selectedModel.canonicalId)
        .where(accepts)
        .firstOrNull;
    return sameModelFamily ??
        selectedProvider.models.where(accepts).firstOrNull;
  }

  bool canUseReferenceAsFirstFrame(MediaReferenceDraft reference) =>
      _modelForReferenceAsFirstFrame(reference) != null;

  /// Moves an image out of creative references and into the provider's
  /// dedicated opening-frame input, switching to a compatible sibling route
  /// when a provider exposes frames and references as separate models.
  Future<bool> useReferenceAsFirstFrame(String referenceId) async {
    final reference = form.references
        .where((item) => item.id == referenceId)
        .firstOrNull;
    if (reference == null) return false;
    final targetModel = _modelForReferenceAsFirstFrame(reference);
    if (targetModel == null) return false;
    final imageNumber =
        form.references
            .takeWhile((item) => item.id != reference.id)
            .where((item) => item.kind == MediaReferenceKind.image)
            .length +
        1;
    final previousModelId = selectedModelId;
    form
      ..prompt = promoteImageReferenceToFirstFrame(
        form.prompt,
        number: imageNumber,
        authoringName: referencePromptName(reference),
      )
      ..references = form.references
          .where((item) => item.id != reference.id)
          .toList()
      ..keyframes = <KeyframeDraft>[
        ...form.keyframes,
        KeyframeDraft(
          id: _uid(),
          label: reference.label,
          role: KeyframeRole.start,
          source: reference.source,
          seconds: 0,
          asset: reference.asset,
          retained: reference.retained,
          savedReferenceId: reference.savedReferenceId,
        ),
      ];
    selectedModelId = targetModel.id;
    _normalizeFormForModel();
    if (form.requiresFixedDuration) form.autoDuration = false;
    _invalidateProviderEstimate();
    notifyListeners();
    if (selectedModelId != previousModelId) await _persistSelection();
    showNotice('The image will be sent through the pinned first-frame input.');
    return true;
  }

  int referenceLimit(MediaReferenceKind kind) =>
      kind == MediaReferenceKind.video &&
          form.referenceTask != MediaReferenceTask.reference
      ? selectedModel.maxVideoReferences.clamp(0, 1)
      : selectedModel.maxReferences(kind, form.mode);

  void setReferenceTask(MediaReferenceTask task) {
    if (!selectedModel.referenceTasks.contains(task)) return;
    form.referenceTask = task;
    if (task != MediaReferenceTask.reference) form.aspectRatio = 'auto';
    if (task == MediaReferenceTask.edit) form.autoDuration = true;
    _invalidateProviderEstimate();
    _scheduleComposerTabsSave();
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
    AssetReference? retained,
    String? savedReferenceId,
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
        retained: retained,
        savedReferenceId: savedReferenceId,
      ),
    ];
    _selectCompatibleModel();
    _normalizeFormForModel();
    if (form.requiresFixedDuration) form.autoDuration = false;
    if (selectedModel.supportsFrameRate) {
      form.frameRate = form.frameRate.clamp(1, 6);
    }
    _invalidateProviderEstimate();
    _scheduleComposerTabsSave();
    notifyListeners();
  }

  Future<void> addImageFrame(
    KeyframeRole role, {
    MediaPickerSource source = MediaPickerSource.library,
  }) async {
    if (!canAddFrame(role)) return;
    // The pick belongs to the tab it was started from, however long the
    // picker sits open and whatever the director does meanwhile.
    final tab = activeComposerTab;
    // The whole pick-and-retain pipeline runs before the frame attaches, so
    // a loading tile holds the card's spot from the first tap.
    _inComposerTab(tab, () {
      _pendingFrameAdds += 1;
      notifyListeners();
    });
    try {
      final asset = await _pick(type: FileType.image, source: source);
      if (asset != null) {
        final saved = await _retainCreateUpload(
          MediaReferenceKind.image,
          asset,
        );
        _inComposerTab(
          tab,
          () => _appendFrame(
            role,
            label: asset.name,
            asset: saved == null ? asset : _withSavedReference(asset, saved),
            retained: saved?.asset,
            savedReferenceId: saved?.id,
          ),
        );
      }
    } on Object catch (error) {
      showNotice(_message(error));
    } finally {
      _inComposerTab(tab, () {
        _pendingFrameAdds -= 1;
        notifyListeners();
      });
    }
  }

  void addUrlFrame(KeyframeRole role) =>
      _appendFrame(role, label: '${role.label} URL');

  String? _appendReference(
    MediaReferenceKind kind, {
    required String label,
    PickedAsset? asset,
    AssetReference? retained,
    String? savedReferenceId,
  }) {
    if (!canAddReference(kind)) return null;
    final id = _uid();
    form.references = <MediaReferenceDraft>[
      ...form.references,
      MediaReferenceDraft(
        id: id,
        label: label,
        kind: kind,
        source: '',
        promptName: _nextReferencePromptName(kind),
        asset: asset,
        retained: retained,
        savedReferenceId: savedReferenceId,
      ),
    ];
    _selectCompatibleModel();
    _normalizeFormForModel();
    _invalidateProviderEstimate();
    notifyListeners();
    return id;
  }

  Future<void> addMediaReferences(
    MediaReferenceKind kind, {
    MediaPickerSource source = MediaPickerSource.library,
  }) async {
    if (!canAddReference(kind)) return;
    final tab = activeComposerTab;
    _beginReferenceUpload('Waiting for ${kind.label.toLowerCase()} selection…');
    _inComposerTab(tab, () => _pendingPickerReferenceAdds += 1);
    List<PickedAsset> picked;
    try {
      picked = await _pickMany(switch (kind) {
        MediaReferenceKind.image => FileType.image,
        MediaReferenceKind.video => FileType.video,
        MediaReferenceKind.audio => FileType.audio,
      }, source: source);
    } on Object catch (error) {
      showNotice(_message(error));
      return;
    } finally {
      // The decrement and the appends below land in one synchronous stretch,
      // so the loading tile swaps for the real drafts without a gap frame.
      _inComposerTab(tab, () => _pendingPickerReferenceAdds -= 1);
      _finishReferenceUpload();
    }
    await attachPickedReferences(kind, picked, tab: tab);
  }

  /// Attaches [picked] as creative references. Drafts appear immediately and
  /// are usable for the current generation right away; retention into
  /// References (and any Drive publish) continues on the background work
  /// queue without locking the add buttons.
  Future<void> attachPickedReferences(
    MediaReferenceKind kind,
    List<PickedAsset> picked, {
    ComposerTab? tab,
  }) async {
    if (picked.isEmpty) return;
    final target = tab ?? activeComposerTab;
    final attached = _inComposerTab(target, () {
      final available = referenceLimit(kind) - form.referenceCount(kind);
      final totalAvailable = selectedModel.maxTotalReferences == null
          ? available
          : selectedModel.maxTotalReferences! - form.references.length;
      final accepted = available < totalAvailable ? available : totalAvailable;
      final uploads = picked.take(accepted < 0 ? 0 : accepted).toList();
      if (picked.length > uploads.length) {
        final totalLimit = selectedModel.maxTotalReferences;
        showNotice(
          totalLimit != null && totalAvailable <= available
              ? '${selectedModel.label} accepts up to $totalLimit creative references total.'
              : '${selectedModel.label} accepts up to '
                    '${referenceLimit(kind)} ${kind.pluralLabel}.',
        );
      }
      final added = <(String, PickedAsset)>[];
      for (final asset in uploads) {
        final draftId = _appendReference(kind, label: asset.name, asset: asset);
        if (draftId == null) break;
        added.add((draftId, asset));
      }
      return added;
    });
    if (attached.isEmpty) return;
    _beginReferenceUpload('Processing ${attached.first.$2.name}…');
    try {
      await _enqueueReferenceWork(() async {
        for (final entry in attached.indexed) {
          final (draftId, asset) = entry.$2;
          if (!target.form.references.any((item) => item.id == draftId)) {
            continue; // Removed while queued.
          }
          _updateReferenceUpload(
            'Processing ${asset.name} (${entry.$1 + 1} of ${attached.length})…',
          );
          final saved = await _retainCreateUpload(kind, asset);
          if (saved != null) {
            _inComposerTab(
              target,
              () => _linkDraftToSavedReference(draftId, asset, saved),
            );
          }
        }
      });
    } finally {
      _finishReferenceUpload();
    }
  }

  /// The reference kind a dropped file belongs to, by MIME type (sniffed
  /// from the name and leading bytes) with a file-extension fallback.
  /// Returns null for files that cannot serve as reference media.
  MediaReferenceKind? classifyDroppedFile(String name, Uint8List bytes) {
    final mimeType = (lookupMimeType(name, headerBytes: bytes) ?? '')
        .toLowerCase();
    if (mimeType.startsWith('image/') ||
        _matchesExtension(name, FileType.image)) {
      return MediaReferenceKind.image;
    }
    if (mimeType.startsWith('video/') ||
        _matchesExtension(name, FileType.video)) {
      return MediaReferenceKind.video;
    }
    if (mimeType.startsWith('audio/') ||
        _matchesExtension(name, FileType.audio)) {
      return MediaReferenceKind.audio;
    }
    return null;
  }

  Map<MediaReferenceKind, List<PickedAsset>> _classifyDroppedFiles(
    List<DroppedFile> files,
    void Function(int unsupported) onUnsupported,
  ) {
    final grouped = <MediaReferenceKind, List<PickedAsset>>{};
    var unsupported = 0;
    for (final file in files) {
      final kind = classifyDroppedFile(file.name, file.bytes);
      if (kind == null) {
        unsupported += 1;
        continue;
      }
      grouped
          .putIfAbsent(kind, () => <PickedAsset>[])
          .add(
            PickedAsset(
              name: file.name,
              bytes: file.bytes,
              mimeType:
                  lookupMimeType(file.name, headerBytes: file.bytes) ??
                  _fallbackMimeType(kind),
              path: file.path,
            ),
          );
    }
    if (unsupported > 0) onUnsupported(unsupported);
    return grouped;
  }

  /// Attaches files dropped on the Create screen's references area, sorting
  /// each file into its reference kind by MIME type or extension.
  Future<void> addDroppedReferenceFiles(List<DroppedFile> files) async {
    final tab = activeComposerTab;
    // Loading tiles reserved by [noteIncomingDroppedFiles] hand over to the
    // real drafts appended below (or clear outright for unsupported drops).
    _inComposerTab(tab, () {
      if (_pendingDropReferenceAdds != 0) _pendingDropReferenceAdds = 0;
    });
    if (files.isEmpty) {
      notifyListeners();
      return;
    }
    final grouped = _classifyDroppedFiles(files, (unsupported) {
      showNotice(
        unsupported == files.length
            ? 'Drop images, videos, or audio files to add references.'
            : '$unsupported dropped '
                  '${unsupported == 1 ? 'file is' : 'files are'} not '
                  'supported reference media.',
      );
    });
    for (final entry in grouped.entries) {
      final blocked = _inComposerTab(
        tab,
        () => referenceLimit(entry.key) <= 0
            ? '${selectedModel.label} does not accept reference '
                  '${entry.key.pluralLabel}.'
            : null,
      );
      if (blocked != null) {
        showNotice(blocked);
        continue;
      }
      await attachPickedReferences(entry.key, entry.value, tab: tab);
    }
  }

  /// Imports files dropped on the References library, sorting each file into
  /// its reference kind by MIME type or extension.
  Future<void> importDroppedReferenceFiles(
    List<DroppedFile> files, {
    String? folderId,
    ReferencePreviewLoader? videoPreviewLoader,
  }) async {
    if (files.isEmpty) return;
    final grouped = _classifyDroppedFiles(files, (unsupported) {
      showNotice(
        unsupported == files.length
            ? 'Drop images, videos, or audio files to save references.'
            : '$unsupported dropped '
                  '${unsupported == 1 ? 'file is' : 'files are'} not '
                  'supported reference media.',
      );
    });
    for (final entry in grouped.entries) {
      await importPickedReferences(
        entry.key,
        entry.value,
        folderId: folderId,
        previewLoader: entry.key == MediaReferenceKind.video
            ? videoPreviewLoader
            : null,
      );
    }
  }

  /// Back-fills a draft once its media has been retained in References. The
  /// draft may have been removed (or the form cleared) while retention ran.
  void _linkDraftToSavedReference(
    String draftId,
    PickedAsset asset,
    SavedReference saved,
  ) {
    final index = form.references.indexWhere((item) => item.id == draftId);
    if (index < 0) return;
    final current = form.references[index];
    final references = List<MediaReferenceDraft>.from(form.references);
    references[index] = MediaReferenceDraft(
      id: current.id,
      label: current.label,
      kind: current.kind,
      source: current.source,
      promptName: current.promptName,
      asset: _withSavedReference(asset, saved),
      retained: saved.asset,
      thumbnailAsset: current.thumbnailAsset ?? saved.thumbnailAsset,
      thumbnailBytes: current.thumbnailBytes,
      savedReferenceId: saved.id,
      durationSeconds: current.durationSeconds ?? saved.durationSeconds,
    );
    form.references = references;
    notifyListeners();
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
        clearSavedReferenceId: true,
        clearDurationSeconds: true,
      );
    }).toList();
    _invalidateProviderEstimate();
    notifyListeners();
  }

  void rememberReferenceThumbnail(String id, Uint8List bytes) {
    String? savedReferenceId;
    form.references = form.references.map((item) {
      if (item.id != id || item.thumbnailBytes != null) return item;
      savedReferenceId = item.savedReferenceId;
      return item.copyWith(thumbnailBytes: bytes);
    }).toList();
    final saved = savedReferences
        .where((reference) => reference.id == savedReferenceId)
        .firstOrNull;
    if (saved != null && saved.thumbnailAsset == null) {
      unawaited(cacheReferencePreview(saved, bytes));
    }
  }

  void rememberReferenceVideoMetadata(String id, VideoSourceMetadata value) {
    rememberReferenceDuration(id, value.durationSeconds);
  }

  void rememberReferenceDuration(String id, double seconds) {
    if (!seconds.isFinite || seconds <= 0) return;
    final index = form.references.indexWhere((item) => item.id == id);
    if (index < 0 || form.references[index].durationSeconds == seconds) {
      return;
    }
    form.references = form.references
        .map(
          (item) =>
              item.id == id ? item.copyWith(durationSeconds: seconds) : item,
        )
        .toList();
    final savedReferenceId = form.references[index].savedReferenceId;
    final saved = savedReferences
        .where((item) => item.id == savedReferenceId)
        .firstOrNull;
    if (saved != null) {
      unawaited(rememberSavedReferenceDuration(saved, seconds));
    }
    notifyListeners();
  }

  Future<void> rememberSavedReferenceDuration(
    SavedReference reference,
    double seconds,
  ) async {
    if (!seconds.isFinite ||
        seconds <= 0 ||
        gateway is! ReferenceLibraryGateway ||
        _referenceDurationWrites.contains(reference.id)) {
      return;
    }
    final current = savedReferences
        .where((item) => item.id == reference.id)
        .firstOrNull;
    if (current == null ||
        (current.durationSeconds != null &&
            (current.durationSeconds! - seconds).abs() < .01)) {
      return;
    }
    _referenceDurationWrites.add(reference.id);
    try {
      _apply(
        await (gateway as ReferenceLibraryGateway).saveReference(
          current.copyWith(durationSeconds: seconds),
        ),
      );
      form.references = form.references.map((draft) {
        return draft.savedReferenceId == reference.id
            ? draft.copyWith(durationSeconds: seconds)
            : draft;
      }).toList();
      notifyListeners();
    } on Object {
      // Duration metadata is an enhancement. The retained media remains
      // usable if a background metadata write fails.
    } finally {
      _referenceDurationWrites.remove(reference.id);
    }
  }

  void rememberVideoSourceThumbnail(Uint8List bytes) {
    final asset = form.videoAsset;
    if (asset != null) {
      if (asset.thumbnailBytes != null) return;
      form.videoAsset = asset.copyWithThumbnail(thumbnailBytes: bytes);
      final saved = savedReferences
          .where((reference) => reference.id == form.videoSavedReferenceId)
          .firstOrNull;
      if (saved != null && saved.thumbnailAsset == null) {
        unawaited(cacheReferencePreview(saved, bytes));
      }
      return;
    }
    form.videoThumbnailBytes ??= bytes;
  }

  void rememberVideoSourceMetadata(VideoSourceMetadata metadata) {
    if (!metadata.isUsable) return;
    final saved = savedReferences
        .where((reference) => reference.id == form.videoSavedReferenceId)
        .firstOrNull;
    if (saved != null) {
      unawaited(
        rememberSavedReferenceDuration(saved, metadata.durationSeconds),
      );
    }
    if (form.videoMetadata?.signature == metadata.signature) return;
    form.videoMetadata = metadata;
    _invalidateProviderEstimate();
    notifyListeners();
  }

  void updateVideoSourceUrl(String source) {
    updateForm((value) {
      if (value.videoUrl != source) {
        value.videoThumbnailBytes = null;
        value.videoMetadata = null;
        value.videoSavedReferenceId = null;
      }
      value.videoUrl = source;
    });
  }

  void removeReference(String id) {
    final removed = form.references
        .where((reference) => reference.id == id)
        .firstOrNull;
    if (removed == null) return;
    form.references = form.references.where((item) => item.id != id).toList();
    _selectCompatibleModel();
    _normalizeFormForModel();
    _invalidateProviderEstimate();
    notifyListeners();
  }

  Future<bool> renameDraftReference(String id, String name) async {
    final draft = form.references
        .where((reference) => reference.id == id)
        .firstOrNull;
    if (draft == null) return false;
    final clean = name.trim();
    final oldName = referencePromptName(draft);
    if (clean == oldName) return true;
    final problem = referenceNameProblem(
      clean,
      excludeDraftId: draft.id,
      excludeSavedReferenceId: draft.savedReferenceId,
    );
    if (problem != null) {
      showNotice(problem);
      return false;
    }
    try {
      final saved = savedReferences
          .where((reference) => reference.id == draft.savedReferenceId)
          .firstOrNull;
      if (saved != null && gateway is ReferenceLibraryGateway) {
        _apply(
          await (gateway as ReferenceLibraryGateway).saveReference(
            saved.copyWith(name: clean, updatedAt: DateTime.now().toUtc()),
          ),
        );
      }
      form.prompt = renameReferenceInPrompt(
        form.prompt,
        oldName: oldName,
        newName: clean,
      );
      form.references = form.references.map((reference) {
        return reference.id == id
            ? reference.copyWith(promptName: clean)
            : reference;
      }).toList();
      formRevision += 1;
      notifyListeners();
      showNotice('Reference renamed to “$clean”.');
      return true;
    } on Object catch (error) {
      showNotice(_message(error));
      return false;
    }
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
    _scheduleComposerTabsSave();
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
    _scheduleComposerTabsSave();
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
    _scheduleComposerTabsSave();
    notifyListeners();
  }

  void setFrameRate(int value) {
    form.frameRate = value.clamp(1, 6);
    _scheduleComposerTabsSave();
    notifyListeners();
  }

  void setSeed(int? value) {
    form.seed = value;
    _scheduleComposerTabsSave();
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
        clearSavedReferenceId: source != null,
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

  Future<void> pickVideo({
    MediaPickerSource source = MediaPickerSource.library,
  }) async {
    final tab = activeComposerTab;
    try {
      final asset = await _pick(type: FileType.video, source: source);
      if (asset != null) {
        final saved = await _retainCreateUpload(
          MediaReferenceKind.video,
          asset,
        );
        _inComposerTab(
          tab,
          () => updateForm((value) {
            value.videoAsset = saved == null
                ? asset
                : _withSavedReference(asset, saved);
            value.videoSavedReferenceId = saved?.id;
            value.videoThumbnailBytes = null;
            value.videoMetadata = null;
          }),
        );
      }
    } on Object catch (error) {
      showNotice(_message(error));
    }
  }

  Future<void> pickDraft() async {
    final tab = activeComposerTab;
    try {
      final asset = await _pick(type: FileType.any);
      if (asset != null) {
        _inComposerTab(
          tab,
          () => updateForm((value) => value.draftAsset = asset),
        );
      }
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
      if (model.maxKeyframesFor(VideoMode.i2v) > 0) {
        return 'Add a first frame for ${model.label}.';
      }
    }
    if (!model.modes.contains(form.mode)) {
      return '${model.label} does not support ${form.mode.label.toLowerCase()}. Choose a compatible model or remove the attached source.';
    }
    final prompt = form.prompt.trim();
    if (form.mode != VideoMode.draftEnhance &&
        form.mode != VideoMode.upscale &&
        prompt.isEmpty &&
        !model.promptIsOptional(
          form.mode,
          hasFrames: form.keyframes.isNotEmpty,
        )) {
      return model.outputKind == GenerationOutputKind.image
          ? 'Describe the image you want to make.'
          : 'Describe the animation you want to make.';
    }
    final promptLimit = model.maxPromptCharacters;
    if (promptLimit != null && prompt.length > promptLimit) {
      return '${model.label} accepts prompts up to $promptLimit characters.';
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
      final maximumKeyframes = model.maxKeyframesFor(VideoMode.i2v);
      if (form.keyframes.length > maximumKeyframes) {
        return maximumKeyframes == 0
            ? '${model.label} uses media references instead of keyframes.'
            : '${model.label} accepts up to $maximumKeyframes keyframes.';
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
      final sourceProblem = _referenceSourceProblem();
      if (sourceProblem != null) return sourceProblem;
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
      final durationProblem = _referenceDurationProblem(model);
      if (durationProblem != null) return durationProblem;
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
      return 'Add the source video for ${model.label}.';
    }
    if (form.mode == VideoMode.v2v && model.supportsGuidanceWithSource) {
      final maximumKeyframes = model.maxKeyframesFor(VideoMode.v2v);
      if (form.keyframes.length > maximumKeyframes) {
        return maximumKeyframes == 0
            ? '${model.label} does not accept guidance keyframes.'
            : '${model.label} accepts up to $maximumKeyframes keyframes.';
      }
      if (form.keyframes.any((frame) => frame.requestSource.isEmpty)) {
        return 'Every keyframe needs an image or URL.';
      }
      for (final kind in MediaReferenceKind.values) {
        final count = form.referenceCount(kind);
        final maximum = referenceLimit(kind);
        if (count > maximum) {
          return maximum == 0
              ? '${model.label} does not accept reference ${kind.pluralLabel} for this operation.'
              : '${model.label} accepts up to $maximum ${kind.pluralLabel}.';
        }
      }
      final totalLimit = model.maxTotalReferences;
      if (totalLimit != null && form.references.length > totalLimit) {
        return '${model.label} accepts up to $totalLimit creative references total.';
      }
      final sourceProblem = _referenceSourceProblem();
      if (sourceProblem != null) return sourceProblem;
      final durationProblem = _referenceDurationProblem(model);
      if (durationProblem != null) return durationProblem;
      if (model.id == 'act_two' && form.references.length != 1) {
        return 'Act-Two needs exactly one character image or video.';
      }
      final metadata = form.videoMetadata;
      if (metadata != null) {
        final minimum = model.minSourceVideoSeconds;
        final maximum = model.maxSourceVideoSeconds;
        if (minimum != null && metadata.durationSeconds + .001 < minimum) {
          return '${model.label} needs a source video at least $minimum seconds long.';
        }
        if (maximum != null && metadata.durationSeconds > maximum + .001) {
          return '${model.label} accepts source videos up to $maximum seconds.';
        }
      }
    }
    if (form.mode == VideoMode.upscale) {
      if (form.videoAsset == null && form.videoUrl.trim().isEmpty) {
        return 'Add the video you want to upscale.';
      }
      final asset = form.videoAsset;
      if (asset != null && !model.upscaleUsesResolutionTargets) {
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
        final sourceLimit = model.maxSourceVideoSeconds ?? 20;
        if (metadata.durationSeconds > sourceLimit + .001) {
          return '${model.label} accepts source clips up to $sourceLimit seconds.';
        }
        if (!model.upscaleUsesResolutionTargets) {
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
      }
      if (!model.upscaleUsesResolutionTargets &&
          (form.upscaleFactor < 1.5 || form.upscaleFactor > 3)) {
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

  String? _referenceSourceProblem() {
    if (!form.references.any((item) => item.requestSource.isEmpty)) {
      return null;
    }
    return form.references.any(
          (item) =>
              item.requestSource.isEmpty && isReferenceDraftHydrating(item.id),
        )
        ? 'References are still loading from your library…'
        : 'Every reference needs an upload or HTTPS URL.';
  }

  String? _referenceDurationProblem(VideoModelDefinition model) {
    for (final kind in const <MediaReferenceKind>[
      MediaReferenceKind.video,
      MediaReferenceKind.audio,
    ]) {
      final knownDurations = form.references
          .where((item) => item.kind == kind)
          .map((item) => item.durationSeconds)
          .whereType<double>()
          .toList();
      final minimum = kind == MediaReferenceKind.audio
          ? model.minReferenceAudioSeconds
          : null;
      if (minimum != null &&
          knownDurations.any((seconds) => seconds + .001 < minimum)) {
        return '${model.label} needs each reference audio clip to be at least $minimum seconds.';
      }
      final maximum = model.maxReferenceSeconds(kind, form.resolution);
      final total = knownDurations.fold<double>(
        0,
        (sum, seconds) => sum + seconds,
      );
      if (maximum != null && total > maximum + .001) {
        final media = kind == MediaReferenceKind.video ? 'video' : 'audio';
        return '${model.label} accepts up to $maximum seconds of reference $media in total.';
      }
    }
    return null;
  }

  Map<String, Object?> _buildInput() {
    if (form.mode == VideoMode.upscale) {
      final prompt = form.prompt.trim();
      return <String, Object?>{
        if (selectedModel.upscaleUsesResolutionTargets) 'mode': 'upscale',
        'input_video': form.videoAsset?.dataUrl ?? form.videoUrl.trim(),
        'upscale_factor': form.upscaleFactor,
        'creativity': form.upscaleCreativity,
        if (selectedModel.upscaleUsesResolutionTargets)
          'resolution': form.resolution,
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
    final orderedFrames = _orderedFrames();
    final providerNeedsTimedSourceGuidance =
        form.mode == VideoMode.v2v &&
        selectedModel.sourceGuidanceRequiresTimestamps;
    final frames = form.usesTimedKeyframes || providerNeedsTimedSourceGuidance
        ? orderedFrames
              .map<Object?>(
                (frame) => <Object?>[
                  providerNeedsTimedSourceGuidance &&
                          frame.role == KeyframeRole.end &&
                          form.videoMetadata != null
                      ? form.videoMetadata!.durationSeconds
                      : frame.seconds,
                  frame.requestSource,
                ],
              )
              .toList()
        : orderedFrames.map<Object?>((frame) => frame.requestSource).toList();
    final references = <MediaReferenceKind, List<String>>{
      for (final kind in MediaReferenceKind.values)
        kind: form.references
            .where((item) => item.kind == kind)
            .map((item) => item.requestSource)
            .toList(),
    };
    final promptNames = <String, List<String>>{
      for (final kind in MediaReferenceKind.values)
        kind.name: form.references
            .where((item) => item.kind == kind)
            .map(referencePromptName)
            .toList(),
    };
    if (form.mode == VideoMode.i2v) {
      return <String, Object?>{
        ...common,
        'mode': 'i2v',
        if (form.references.isNotEmpty)
          referencePromptNamesInputKey: promptNames,
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
        if (selectedModel.supportsGuidanceWithSource && frames.isNotEmpty)
          'keyframes': frames,
        if (selectedModel.supportsGuidanceWithSource &&
            references[MediaReferenceKind.image]!.isNotEmpty)
          'reference_images': references[MediaReferenceKind.image]!,
        if (selectedModel.supportsGuidanceWithSource &&
            references[MediaReferenceKind.video]!.isNotEmpty)
          'reference_videos': references[MediaReferenceKind.video]!,
        if (selectedModel.supportsGuidanceWithSource &&
            references[MediaReferenceKind.audio]!.isNotEmpty)
          'reference_audios': references[MediaReferenceKind.audio]!,
      };
    }
    return <String, Object?>{...common, 'mode': 't2v'};
  }

  @visibleForTesting
  Map<String, Object?> buildInputForTesting() => _buildInput();

  String _uid() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}-${(_idCounter++).toRadixString(16)}';

  Future<void> submit({bool providerRetentionRiskAcknowledged = false}) async {
    final problem = validate();
    if (problem != null) {
      showNotice(problem);
      if (selectedProvider.requiresApiKey && !hasApiKey) {
        unawaited(navigate(AppSection.providers));
      }
      return;
    }
    if (requiresProviderRetentionAcknowledgement &&
        !providerRetentionRiskAcknowledged) {
      showNotice(
        'Review and accept the ${selectedProvider.name} result-retention warning before generating.',
      );
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
    // Whatever is being generated is worth having on disk before the render
    // starts, however it goes.
    _flushComposerTabsSave(onlyIfPending: true);
    // The first real submission is the moment a "your film is ready" alert
    // starts to matter; asking earlier would be noise on a fresh install.
    unawaited(_requestNotificationsOnce());
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
          : selectedProviderId == 'bfl' ||
                selectedProviderId == 'artcraft' ||
                selectedProviderId == 'runway'
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
        connectedRewriteProviders: current.connectedRewriteProviders,
        availableProviders: current.availableProviders,
        providerRetentionAcknowledgements:
            current.providerRetentionAcknowledgements,
        folders: current.folders,
        savedReferences: current.savedReferences,
        storage: current.storage,
        settingsVault: current.settingsVault,
      );
    }
    submitting = true;
    notifyListeners();
    final checksVisualReferences =
        autoFixReferenceVideos &&
        (form.keyframes.isNotEmpty ||
            form.referenceCount(MediaReferenceKind.image) > 0 ||
            (selectedModel.referenceVideoCompatibilityProfile != null &&
                form.referenceCount(MediaReferenceKind.video) > 0));
    showNotice(
      checksVisualReferences
          ? 'Checking visual reference compatibility before sending…'
          : form.mode == VideoMode.upscale
          ? 'Submitting upscale…'
          : 'Submitting generation…',
    );
    try {
      pending = await gateway.submit(
        GenerationSubmission(
          record: pending,
          input: _buildInput(),
          autoFixReferenceVideos: autoFixReferenceVideos,
        ),
      );
      _replaceInMemory(pending);
      final delivery = providerById(pending.provider).resultDelivery;
      showNotice(
        delivery.keepOpenRecommended
            ? '${providerNameForHistory(pending.provider)} accepted the generation. Keep Clawnsole open and online until the result is saved; Clawnsole will retry retrieval if the connection drops.'
            : 'Generation submitted. Clawnsole will keep checking it across the app.',
      );
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
      final message = _message(error);
      try {
        _apply(await gateway.load());
      } on Object {
        pending = pending.copyWith(
          status: 'Error',
          error: message,
          updatedAt: DateTime.now().toUtc(),
        );
        _replaceInMemory(pending);
      }
      if (_isVisualReferenceCompatibilityError(message)) {
        showNotice(
          '$message Turn on Normalize visual references and try again.',
          action: AppNoticeAction.retryWithVisualNormalization,
        );
      } else {
        showNotice(message);
      }
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
      connectedRewriteProviders: current.connectedRewriteProviders,
      availableProviders: current.availableProviders,
      providerRetentionAcknowledgements:
          current.providerRetentionAcknowledgements,
      folders: current.folders,
      savedReferences: current.savedReferences,
      storage: current.storage,
      settingsVault: current.settingsVault,
    );
    notifyListeners();
  }

  /// Cross-device visibility: while Drive is connected, periodically re-read
  /// the library so generations and references created or updated on other
  /// devices appear here without any user action — including in-progress
  /// generations this device can then pick up and poll. Runs faster while
  /// staged uploads are draining so the sync indicators stay current.
  Future<void> _refreshDriveLibraryIfDue() async {
    if (_disposed || _refreshingDriveLibrary || loading || submitting) return;
    if (!googleDriveConnected) return;
    _driveRefreshTick += 1;
    final everyTicks = pendingDriveUploadCount > 0 ? 2 : 7;
    if (_driveRefreshTick % everyTicks != 0) return;
    _refreshingDriveLibrary = true;
    final snapshotRevision = _snapshotRevision;
    try {
      final value = await gateway.load();
      await _applySnapshotRead(value, startedAtRevision: snapshotRevision);
    } on Object {
      // Periodic reconciliation is best-effort; the next tick retries.
    } finally {
      _refreshingDriveLibrary = false;
    }
  }

  Future<void> pollWorking({bool ignoreSchedule = false}) async {
    if (!hasAnyApiKey) return;
    if (_polling) {
      // A pass blocked behind an in-flight poll must not silently drop a
      // foreground-return reconcile: that in-flight request may be a stale
      // pre-suspension call that is about to time out. Queue one follow-up.
      if (ignoreSchedule) _pollAgainIgnoringSchedule = true;
      return;
    }
    // A full pass is starting; it subsumes any queued follow-up request.
    _pollAgainIgnoringSchedule = false;
    final now = DateTime.now().toUtc();
    final working = generations.where((item) {
      if (!item.canCheckStatus || _statusChecks.contains(item.localId)) {
        return false;
      }
      if (!hasApiKeyFor(item.provider)) return false;
      final due = ignoreSchedule || item.isStatusCheckDue(now);
      final needsRetention =
          (ignoreSchedule
              ? item.needsResultRetention
              : item.isResultRetentionDue(now)) &&
          due;
      return needsRetention || (item.isWorking && due);
    }).toList();
    if (working.isEmpty) return;
    _polling = true;
    try {
      for (final item in working) {
        try {
          // Provider requests carry their own timeouts, but Drive-backed
          // record and asset writes inside poll do not, and a socket the
          // platform killed during suspension can otherwise hang this loop —
          // and with it all polling — until relaunch. The ceiling is generous
          // enough for a large result upload on a slow connection.
          final updated = await gateway
              .poll(item)
              .timeout(const Duration(minutes: 10));
          _replaceInMemory(updated);
          if (await _invalidateRejectedApiKey(
            updated.lastProviderStatusCode,
            showNoticeOnFailure: true,
          )) {
            break;
          }
          if (item.resultAsset == null && updated.resultAsset != null) {
            showNotice('Your film is ready and safely saved.');
            if (updated.storage == LibraryStorage.drive) {
              _enqueueVideoPrefetch(updated.resultAsset);
            }
          } else if (!item.isReady && updated.isReady) {
            showNotice(
              updated.resultRetentionError == null
                  ? 'Your film is ready to watch and save.'
                  : 'Your film is ready. Clawnsole will keep retrying its download.',
            );
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
      if (_pollAgainIgnoringSchedule && !_disposed) {
        _pollAgainIgnoringSchedule = false;
        unawaited(pollWorking(ignoreSchedule: true));
      }
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
      // Bounded like pollWorking: a hung poll would otherwise exclude this
      // record from automatic polling for the rest of the process lifetime.
      final updated = await gateway
          .poll(item)
          .timeout(const Duration(minutes: 10));
      _replaceInMemory(updated);
      if (await _invalidateRejectedApiKey(
        updated.lastProviderStatusCode,
        showNoticeOnFailure: true,
      )) {
        return;
      }
      if (updated.resultRetentionError != null) {
        showNotice(
          'Result retrieval failed: ${updated.resultRetentionError} Clawnsole will keep retrying.',
        );
      } else if (updated.lastCheckError != null) {
        showNotice('Status check failed: ${updated.lastCheckError}');
      } else if (updated.isReady) {
        showNotice(
          '${providerNameForHistory(item.provider)} reports that this film is ready.',
        );
        if (updated.storage == LibraryStorage.drive) {
          _enqueueVideoPrefetch(updated.resultAsset);
        }
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

  Future<void> acknowledgeProviderRetentionRisk() async {
    final provider = selectedProvider;
    if (!provider.resultDelivery.keepOpenRecommended) return;
    if (gateway is! ProviderRetentionAcknowledgementGateway) {
      throw StateError(
        'This app build cannot save the ${provider.name} acknowledgement.',
      );
    }
    _apply(
      await (gateway as ProviderRetentionAcknowledgementGateway)
          .acknowledgeProviderRetentionRisk(provider.id),
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
    // The cost desk only ever quotes the tab in front; background work
    // landing in another draft must not repoint it.
    if (!identical(_draftTab, activeComposerTab)) return;
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

  Future<void> revealDataFolder() async {
    final location = _dataLocation;
    if (location == null || !location.supportsRevealDataFolder) return;
    try {
      await location.revealDataFolder();
    } on Object catch (error) {
      showNotice(_message(error));
    }
  }

  /// Whether [directory] already holds a Clawnsole library, or null when the
  /// check itself failed (a notice explains the failure).
  Future<bool?> dataDirectoryHasLibrary(String directory) async {
    final location = _dataLocation;
    if (location == null) return null;
    try {
      return await location.dataDirectoryHasLibrary(directory);
    } on Object catch (error) {
      showNotice(_message(error));
      return null;
    }
  }

  // Relocation swaps the live data directory, so it must never race an
  // in-flight submission, poll retention, or Drive transfer.
  bool get _dataRelocationBlocked =>
      submitting ||
      workingCount > 0 ||
      googleDriveBusy ||
      copyingGenerationIds.isNotEmpty ||
      copyingReferenceIds.isNotEmpty;

  Future<void> relocateDataDirectory(
    String directory, {
    bool useExistingLibrary = false,
  }) async {
    final location = _dataLocation;
    if (location == null ||
        !location.supportsDataRelocation ||
        dataRelocationBusy) {
      return;
    }
    if (_dataRelocationBlocked) {
      showNotice(
        'Wait for active generations and Drive transfers to finish before '
        'moving the library.',
      );
      return;
    }
    dataRelocationBusy = true;
    notifyListeners();
    try {
      _apply(
        await location.relocateDataDirectory(
          directory,
          useExistingLibrary: useExistingLibrary,
        ),
        restorePreferences: true,
      );
      showNotice(
        useExistingLibrary
            ? 'Clawnsole is now using the library in $directory.'
            : 'Clawnsole data now lives in $directory. The previous copy '
                  'stays in the old folder until you delete it.',
      );
    } on Object catch (error) {
      showNotice(_message(error));
    } finally {
      dataRelocationBusy = false;
      notifyListeners();
    }
  }

  Future<void> relocateDataDirectoryViaShell() async {
    final location = _dataLocation;
    if (location == null ||
        !location.shellManagesDataRelocation ||
        dataRelocationBusy) {
      return;
    }
    if (_dataRelocationBlocked) {
      showNotice(
        'Wait for active generations and Drive transfers to finish before '
        'moving the library.',
      );
      return;
    }
    dataRelocationBusy = true;
    notifyListeners();
    try {
      final result = await location.relocateDataDirectoryViaShell();
      if (result.moved) {
        showNotice('Clawnsole is reopening from the new data folder.');
      }
    } on Object catch (error) {
      showNotice(_message(error));
    } finally {
      dataRelocationBusy = false;
      notifyListeners();
    }
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
      if (!_disposed) notifyListeners();
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
      if (!_disposed) notifyListeners();
    }
  }

  /// Quietly reattaches a previously connected Drive library, typically at
  /// startup: the companion and shell hold Drive sessions per process, so
  /// without this every launch would hide Drive work until a manual refresh.
  /// Failures stay silent — Settings still offers the interactive refresh.
  Future<bool> resumeGoogleDrive({
    bool force = false,
    bool restorePreferences = false,
    int? expectedPreferenceRevision,
  }) async {
    if (gateway is! GoogleDriveGateway || googleDriveBusy) return false;
    if ((!force && googleDriveConnected) ||
        !googleDriveConnection.isConfigured) {
      return false;
    }
    googleDriveBusy = true;
    final snapshotRevision = _snapshotRevision;
    notifyListeners();
    try {
      final value = await (gateway as GoogleDriveGateway).resumeGoogleDrive(
        force: force,
      );
      if (value == null) return false;
      if (_disposed) return false;
      return await _applySnapshotRead(
        value,
        startedAtRevision: snapshotRevision,
        reloadIfSuperseded: true,
        restorePreferences:
            restorePreferences &&
            (expectedPreferenceRevision == null ||
                _preferenceRevision == expectedPreferenceRevision),
      );
    } on Object {
      // The resume contract never throws, but a quiet startup must survive
      // an unexpected error without surfacing a notice.
      return false;
    } finally {
      googleDriveBusy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> refreshGoogleDrive() async {
    if (gateway is! GoogleDriveGateway || googleDriveBusy) return;
    googleDriveBusy = true;
    final snapshotRevision = _snapshotRevision;
    notifyListeners();
    try {
      final value = await (gateway as GoogleDriveGateway).refreshGoogleDrive();
      await _applySnapshotRead(
        value,
        startedAtRevision: snapshotRevision,
        reloadIfSuperseded: true,
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

  Future<void> moveLocalLibraryToGoogleDrive() async {
    if (gateway is! GoogleDriveGateway) return;
    if (!googleDriveConnected) {
      showNotice('Connect Google Drive before moving local items.');
      return;
    }
    if (googleDriveBusy) return;
    googleDriveBusy = true;
    notifyListeners();
    try {
      late GoogleDriveCopyResult moved;
      final operation = _driveCopyQueue.then((_) async {
        moved = await (gateway as GoogleDriveGateway)
            .moveLocalLibraryToGoogleDrive();
      });
      _driveCopyQueue = operation.then<void>((_) {}, onError: (_) {});
      await operation;
      _apply(moved.snapshot);
      final total = moved.generations + moved.references;
      showNotice(
        total == 0
            ? 'The local library was removed. Every item already lives in '
                  'Google Drive.'
            : 'Moved ${moved.generations} generation${moved.generations == 1 ? '' : 's'} and ${moved.references} reference${moved.references == 1 ? '' : 's'} to Drive. The local copies were removed.',
      );
    } on Object catch (error) {
      showNotice(_message(error));
    } finally {
      googleDriveBusy = false;
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
    if (thumbnailBytes.isEmpty) return;
    _referencePreviewBytes[reference.id] = thumbnailBytes;
    notifyListeners();
    if (gateway is! MediaPreviewGateway ||
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
      final retained = savedReferences
          .where((item) => item.id == reference.id)
          .firstOrNull
          ?.thumbnailAsset;
      if (retained != null) {
        _restoredAssetBytes[_assetCacheKey(retained)] = thumbnailBytes;
      }
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
    bool cacheOnly = false,
  }) async {
    Future<Uint8List?> read(AssetReference value) {
      if (!cacheOnly || value.kind != 'drive') {
        return gateway.readAsset(value);
      }
      return _mediaCacheGateway?.cachedAssetBytes(value) ??
          Future<Uint8List?>.value();
    }

    Uint8List? thumbnailBytes;
    if (thumbnailAsset != null) {
      try {
        thumbnailBytes = await read(thumbnailAsset);
      } on Object {
        // The original media remains reusable without its cached preview.
      }
    }
    final bytes = await read(reference);
    if (bytes == null) {
      throw StateError('The retained media is not cached on this device.');
    }
    return PickedAsset(
      name: reference.label,
      bytes: bytes,
      mimeType: reference.contentType ?? 'application/octet-stream',
      retained: reference,
      thumbnailAsset: thumbnailAsset,
      thumbnailBytes: thumbnailBytes,
    );
  }

  /// Rehydrates [tab] (the tab in front by default) from [item]: retained
  /// keyframes, references, and source media plus every scalar setting.
  Future<void> _restoreGenerationSettings(
    Generation item, {
    bool includePrompt = false,
    bool cacheOnly = false,
    ComposerTab? tab,
  }) async {
    final target = tab ?? activeComposerTab;
    if (includePrompt &&
        providers.any((provider) => provider.id == item.provider)) {
      _inComposerTab(target, () {
        selectedProviderId = item.provider;
        selectedModelId = modelById(item.provider, item.model).id;
      });
    }
    final retainedFrames = <KeyframeDraft>[];
    for (final frame in item.config.keyframes ?? const <KeyframeLabel>[]) {
      final storedReference = frame.source;
      final saved = _savedReferenceForInput(
        referenceId: frame.referenceId,
        kind: MediaReferenceKind.image,
        asset: storedReference,
      );
      final reference = storedReference ?? saved?.asset;
      PickedAsset? asset;
      if (reference?.isLocal == true) {
        try {
          asset = await _retainedAsset(reference!, cacheOnly: cacheOnly);
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
          savedReferenceId: saved?.id ?? frame.referenceId,
        ),
      );
    }
    final retainedReferences = <MediaReferenceDraft>[];
    final restoredReferenceCounts = <MediaReferenceKind, int>{};
    for (final media
        in item.config.references ?? const <MediaReferenceLabel>[]) {
      final promptNumber = (restoredReferenceCounts[media.kind] ?? 0) + 1;
      restoredReferenceCounts[media.kind] = promptNumber;
      final storedReference = media.source;
      final saved = _savedReferenceForInput(
        referenceId: media.referenceId,
        kind: media.kind,
        asset: storedReference,
      );
      final reference = storedReference ?? saved?.asset;
      PickedAsset? asset;
      Uint8List? thumbnailBytes;
      if (media.thumbnailAsset != null) {
        try {
          thumbnailBytes = cacheOnly && media.thumbnailAsset!.kind == 'drive'
              ? await _mediaCacheGateway?.cachedAssetBytes(
                  media.thumbnailAsset!,
                )
              : await gateway.readAsset(media.thumbnailAsset!);
        } on Object {
          // The original reference can regenerate its preview.
        }
      }
      if (reference?.isLocal == true) {
        try {
          asset = await _retainedAsset(
            reference!,
            thumbnailAsset: media.thumbnailAsset,
            cacheOnly: cacheOnly,
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
          promptName: media.promptName ?? '${media.kind.label} $promptNumber',
          asset: asset,
          retained: reference,
          thumbnailAsset: media.thumbnailAsset,
          thumbnailBytes: asset?.thumbnailBytes ?? thumbnailBytes,
          savedReferenceId: saved?.id ?? media.referenceId,
        ),
      );
    }
    PickedAsset? retainedSource;
    final savedSource = _savedReferenceForInput(
      referenceId: item.config.sourceReferenceId,
      kind: MediaReferenceKind.video,
      asset: item.config.source,
    );
    final durableSource = item.config.source ?? savedSource?.asset;
    if ((item.mode == VideoMode.v2v ||
            item.mode == VideoMode.draftEnhance ||
            item.mode == VideoMode.upscale) &&
        durableSource?.isLocal == true) {
      try {
        retainedSource = await _retainedAsset(
          durableSource!,
          thumbnailAsset: item.config.sourceThumbnailAsset,
          cacheOnly: cacheOnly,
        );
      } on Object {
        // Preserve the rest of the last-used settings when an asset is gone.
        if (!cacheOnly) {
          showNotice(
            item.mode == VideoMode.upscale
                ? 'The retained source video is no longer available. Attach a video to upscale.'
                : item.mode == VideoMode.v2v
                ? 'The retained starting video is no longer available. Attach a video to continue one.'
                : 'The retained draft cache is no longer available. Attach a draft to enhance it.',
          );
        }
      }
    }
    Uint8List? sourceThumbnailBytes = retainedSource?.thumbnailBytes;
    if (sourceThumbnailBytes == null &&
        item.config.sourceThumbnailAsset != null) {
      try {
        final thumbnail = item.config.sourceThumbnailAsset!;
        sourceThumbnailBytes = cacheOnly && thumbnail.kind == 'drive'
            ? await _mediaCacheGateway?.cachedAssetBytes(thumbnail)
            : await gateway.readAsset(thumbnail);
      } on Object {
        // Reused source media can regenerate its preview in the Create panel.
      }
    }
    if (_disposed) return;
    // Everything below is one synchronous stretch aimed at the target tab,
    // so nothing the director does meanwhile can land in the wrong draft.
    _inComposerTab(target, () {
      final restoredTask =
          selectedModel.referenceTasks.contains(item.config.referenceTask)
          ? item.config.referenceTask
          : MediaReferenceTask.reference;
      _disabledReferences.clear();
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
        ..videoSavedReferenceId =
            item.mode == VideoMode.v2v || item.mode == VideoMode.upscale
            ? savedSource?.id ?? item.config.sourceReferenceId
            : null
        ..videoUrl =
            (item.mode == VideoMode.v2v || item.mode == VideoMode.upscale) &&
                durableSource?.kind == 'remote'
            ? durableSource!.value
            : ''
        ..videoThumbnailBytes = sourceThumbnailBytes
        ..videoMetadata = null
        ..draftAsset = item.mode == VideoMode.draftEnhance
            ? retainedSource
            : null
        ..draftUrl =
            item.mode == VideoMode.draftEnhance &&
                durableSource?.kind == 'remote'
            ? durableSource!.value
            : '';
      _generateAudioExplicitlyDisabled = _generationExplicitlyDisabledAudio(
        item,
      );
      _selectCompatibleModel();
      _normalizeFormForModel();
      _invalidateProviderEstimate();
      formRevision += 1;
    });
    _scheduleComposerTabsSave(touched: target);
    notifyListeners();
  }

  /// Files the destination folder [item] was saved to on [tab], so a tab
  /// opened from a film generates back into the same place.
  void _adoptGenerationFolder(ComposerTab tab, Generation item) {
    if (item.storage == LibraryStorage.drive) {
      tab.driveFolderId = item.folderId;
    } else {
      tab.localFolderId = item.folderId;
    }
  }

  /// Opens a fresh composer tab seeded from [item] (prompt, settings, and
  /// retained references), optionally replacing the prompt with [prompt].
  ///
  /// Shows no notice of its own — Reuse and AI Rewrite each say their piece.
  Future<void> openGenerationInNewTab(
    Generation item, {
    String? prompt,
    String? rewriteSummary,
  }) async {
    final tab = addComposerTab();
    try {
      await _restoreGenerationSettings(item, includePrompt: true, tab: tab);
    } on Object catch (error) {
      showNotice(_message(error));
    }
    _inComposerTab(tab, () {
      if (prompt != null) tab.form.prompt = prompt;
      tab.sourceGenerationId = item.localId;
      tab.rewriteSummary = rewriteSummary;
      _adoptGenerationFolder(tab, item);
      tab.formRevision += 1;
    });
    _scheduleComposerTabsSave(touched: tab);
    notifyListeners();
    await navigate(AppSection.create);
  }

  Future<void> reuse(Generation item) async {
    if (!canReuse(item)) {
      showNotice(
        'That provider or model is not available in this app version.',
      );
      return;
    }
    // A tab with direction already typed in it is somebody's work; the film
    // reopens beside it instead of over it.
    if (!activeComposerTab.isBlank) {
      await openGenerationInNewTab(item);
      showNotice(
        'Prompt, settings, and retained references copied to a new tab.',
      );
      return;
    }
    final tab = activeComposerTab;
    try {
      await _restoreGenerationSettings(item, includePrompt: true, tab: tab);
      _inComposerTab(tab, () {
        tab.sourceGenerationId = item.localId;
        _adoptGenerationFolder(tab, item);
      });
      _scheduleComposerTabsSave(touched: tab);
    } on Object catch (error) {
      showNotice(_message(error));
    }
    await navigate(AppSection.create);
    showNotice('Prompt, settings, and retained references copied.');
  }

  void enhance(Generation item) {
    if (item.draftCacheUrl == null) return;
    // Draft enhance hides the prompt entirely, so an enhance-born tab is
    // "blank" by prompt alone: the attached cache is what makes it occupied.
    final current = activeComposerTab;
    final free =
        current.isBlank &&
        current.form.draftAsset == null &&
        current.form.draftUrl.trim().isEmpty;
    final tab = free ? current : addComposerTab();
    _inComposerTab(tab, () {
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
      _generateAudioExplicitlyDisabled = _generationExplicitlyDisabledAudio(
        item,
      );
      tab.sourceGenerationId = item.localId;
      _adoptGenerationFolder(tab, item);
      _invalidateProviderEstimate();
      formRevision += 1;
    });
    _scheduleComposerTabsSave(touched: tab);
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
    late Uint8List bytes;
    if (item.resultAsset == null) {
      bytes = await gateway.downloadMedia(item.resultUrl!);
    } else {
      try {
        bytes = await gateway.readAsset(item.resultAsset!);
      } on Object {
        if (item.resultUrl == null) rethrow;
        bytes = await gateway.downloadMedia(item.resultUrl!);
      }
    }
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
    if (item.resultAsset != null) {
      try {
        return await gateway.assetUri(item.resultAsset!);
      } on Object {
        if (item.resultUrl == null) rethrow;
      }
    }
    return item.resultUrl == null ? null : gateway.mediaUri(item.resultUrl!);
  }

  /// Resolves a playable URI while exposing byte progress for surfaces that
  /// can observe it (native Drive downloads). Web builds hand playback to the
  /// browser, so their progress listenable simply stays null (indeterminate).
  GenerationMediaDelivery generationMediaDelivery(Generation item) {
    final progress = ValueNotifier<double?>(null);
    final asset = item.resultAsset;
    final cacheGateway = _videoCacheGateway;
    void Function()? detach;
    if (asset != null && asset.kind == 'drive' && cacheGateway != null) {
      void listener(double? fraction) => progress.value = fraction;
      cacheGateway.addVideoProgressListener(asset.value, listener);
      detach = () =>
          cacheGateway.removeVideoProgressListener(asset.value, listener);
    }
    final uri = generationMediaUri(item)
        .then((value) {
          // URI resolution ends the byte-transfer phase. Player
          // initialization has no meaningful percentage, so keep that phase
          // indeterminate instead of leaving the loading surface at 100%.
          progress.value = null;
          if (asset?.kind == 'drive') _markVideoPreviewSourceAvailable();
          return value;
        })
        .whenComplete(() => detach?.call());
    return GenerationMediaDelivery(uri: uri, progress: progress);
  }

  /// A URI usable for preview-frame extraction only when producing it is
  /// cheap: an already-cached Drive film, a local file, or a companion URL.
  /// Never triggers a full Drive download. A cold Drive item can use its
  /// provider delivery while that remains available; otherwise the card keeps
  /// its tap-to-play placeholder until the retained film is cached.
  Future<Uri?> generationPreviewSourceUri(Generation item) async {
    final asset = item.resultAsset;
    final cacheGateway = _videoCacheGateway;
    if (asset != null && asset.kind == 'drive' && cacheGateway != null) {
      final cached = await cacheGateway.cachedVideoAssetUri(asset);
      if (cached != null) return cached;
      return item.resultUrl == null ? null : gateway.mediaUri(item.resultUrl!);
    }
    return generationMediaUri(item);
  }

  /// Resolves a reference-video URI only when frame extraction is cheap.
  /// Cold Drive videos wait for the bounded background cache instead of
  /// turning every visible card into a full media download.
  Future<Uri?> referencePreviewSourceUri(SavedReference reference) async {
    final asset = reference.asset;
    final cacheGateway = _videoCacheGateway;
    if (asset.kind == 'drive' && cacheGateway != null) {
      return cacheGateway.cachedVideoAssetUri(asset);
    }
    if (asset.isLocal) return gateway.assetUri(asset);
    final remote = Uri.tryParse(asset.value);
    if (remote?.scheme == 'https') return gateway.mediaUri(asset.value);
    return null;
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

  /// Reference twin of [generationMediaDelivery]: resolves the playable URI
  /// while exposing byte progress for native Drive downloads.
  GenerationMediaDelivery referenceMediaDelivery(SavedReference reference) {
    final progress = ValueNotifier<double?>(null);
    final asset = reference.asset;
    final cacheGateway = _videoCacheGateway;
    void Function()? detach;
    if (asset.kind == 'drive' && cacheGateway != null) {
      void listener(double? fraction) => progress.value = fraction;
      cacheGateway.addVideoProgressListener(asset.value, listener);
      detach = () =>
          cacheGateway.removeVideoProgressListener(asset.value, listener);
    }
    final uri = referenceMediaUri(reference)
        .then((value) {
          progress.value = null;
          return value;
        })
        .whenComplete(() => detach?.call());
    return GenerationMediaDelivery(uri: uri, progress: progress);
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
    _disposed = true;
    unawaited(_backgroundActivity.setPendingWork(false));
    _providerCatalogClient.close();
    _pollTimer?.cancel();
    _creditTimer?.cancel();
    _estimateTimer?.cancel();
    _noticeTimer?.cancel();
    _prefetchDebounce?.cancel();
    _composerTabsSaveTimer?.cancel();
    super.dispose();
  }
}

enum VideoSaveDestination { photos, files }

/// One video delivery in flight: the resolving URI plus a live download
/// fraction for the loading surface. The progress value is null while the
/// total is unknown, the surface cannot observe bytes, or delivery has
/// finished and the player is initializing.
class GenerationMediaDelivery {
  const GenerationMediaDelivery({required this.uri, required this.progress});

  final Future<Uri?> uri;
  final ValueListenable<double?> progress;
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
