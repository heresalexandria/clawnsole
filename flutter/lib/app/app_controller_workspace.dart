part of 'app_controller.dart';

/// Portable Create workspaces and their text-only aesthetic library.
extension AppControllerWorkspace on AppController {
  List<AestheticReference> get aestheticReferences =>
      List.unmodifiable(_aestheticReferences);
  AestheticReference? get selectedAestheticReference => _aestheticReferences
      .where((item) => item.id == form.aestheticReferenceId)
      .firstOrNull;

  /// What is actually sent: the direction, then its casting block, then the
  /// aesthetic text. None of the two appended parts is in the editable prompt.
  String get generationPrompt =>
      appendAestheticPrompt(promptWithCast, selectedAestheticReference);

  void selectAestheticReference(String? id) {
    updateForm((form) => form.aestheticReferenceId = id);
  }

  /// Which half of the References desk is showing. Session-only: the desk
  /// always opens on media after a relaunch.
  void setReferencesTab(ReferencesTab value) {
    if (referencesTab == value) return;
    referencesTab = value;
    notifyListeners();
  }

  /// Opens the References desk on its aesthetic half, for the Create
  /// picker's "Manage aesthetics…" action.
  Future<void> openAestheticLibrary() async {
    referencesTab = ReferencesTab.aesthetics;
    await navigate(AppSection.references);
  }

  void setAestheticSearch(String value) {
    if (aestheticSearch == value) return;
    aestheticSearch = value;
    notifyListeners();
  }

  void setAestheticTag(String? value) {
    if (aestheticTag == value) return;
    aestheticTag = value;
    notifyListeners();
  }

  void setAestheticFavoritesOnly(bool value) {
    if (aestheticFavoritesOnly == value) return;
    aestheticFavoritesOnly = value;
    notifyListeners();
  }

  void resetAestheticFilters() {
    if (!hasAestheticFilters) return;
    aestheticSearch = '';
    aestheticTag = null;
    aestheticFavoritesOnly = false;
    notifyListeners();
  }

  /// Whether anything is narrowing the aesthetic library right now.
  bool get hasAestheticFilters =>
      aestheticSearch.trim().isNotEmpty ||
      aestheticTag != null ||
      aestheticFavoritesOnly;

  /// Stars or unstars one aesthetic. Starred entries lead every list, so the
  /// change is durable rather than a view preference.
  void toggleAestheticFavorite(String id) {
    final index = _aestheticReferences.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final item = _aestheticReferences[index];
    _aestheticReferences[index] = item.copyWith(
      favorite: !item.favorite,
      updatedAt: DateTime.now().toUtc(),
    );
    _flushComposerTabsSave();
    notifyListeners();
  }

  /// Every tag in the library, de-duplicated case-insensitively (the first
  /// spelling wins) and sorted case-insensitively.
  List<String> get aestheticTags {
    final names = <String, String>{};
    for (final item in _aestheticReferences) {
      for (final tag in item.tags) {
        names.putIfAbsent(tag.toLowerCase(), () => tag);
      }
    }
    final tags = names.values.toList();
    tags.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return tags;
  }

  int aestheticTagCount(String tag) =>
      _aestheticReferences.where((item) => item.hasTag(tag)).length;

  /// How many aesthetics the search and tag filters keep, optionally limited
  /// to starred ones. The starred facet is ignored so the All and Starred
  /// keys can both describe the same search.
  int aestheticCount({bool favoritesOnly = false}) => _aestheticReferences
      .where(
        (item) =>
            _matchesAestheticSearch(item) &&
            _matchesAestheticTag(item) &&
            (!favoritesOnly || item.favorite),
      )
      .length;

  /// Favorites first, then title A→Z, then the most recently edited.
  List<AestheticReference> get sortedAestheticReferences =>
      _sortAesthetics(_aestheticReferences.toList());

  /// [sortedAestheticReferences] narrowed by the desk's search, tag, and
  /// starred filters.
  List<AestheticReference> get filteredAestheticReferences => _sortAesthetics(
    _aestheticReferences
        .where(
          (item) =>
              _matchesAestheticSearch(item) &&
              _matchesAestheticTag(item) &&
              (!aestheticFavoritesOnly || item.favorite),
        )
        .toList(),
  );

  List<AestheticReference> _sortAesthetics(List<AestheticReference> values) {
    values.sort((a, b) {
      if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
      final title = a.title.toLowerCase().compareTo(b.title.toLowerCase());
      if (title != 0) return title;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return values;
  }

  bool _matchesAestheticSearch(AestheticReference item) {
    final needle = aestheticSearch.trim().toLowerCase();
    if (needle.isEmpty) return true;
    return item.title.toLowerCase().contains(needle) ||
        item.text.toLowerCase().contains(needle) ||
        item.tags.any((tag) => tag.toLowerCase().contains(needle));
  }

  bool _matchesAestheticTag(AestheticReference item) {
    final tag = aestheticTag;
    return tag == null || item.hasTag(tag);
  }

  /// Creates or updates an aesthetic. Omitted [tags]/[favorite] keep the
  /// existing record's values so an edit never silently unstars or untags.
  void saveAestheticReference({
    String? id,
    required String title,
    required String text,
    required String icon,
    required int color,
    List<String>? tags,
    bool? favorite,
  }) {
    if (title.trim().isEmpty || text.trim().isEmpty) return;
    final existing = id == null
        ? null
        : _aestheticReferences.where((item) => item.id == id).firstOrNull;
    final record = AestheticReference(
      id: id ?? _uid(),
      title: title.trim(),
      text: text.trim(),
      icon: icon,
      color: color,
      tags: tags ?? existing?.tags ?? const <String>[],
      favorite: favorite ?? existing?.favorite ?? false,
      updatedAt: DateTime.now().toUtc(),
    );
    _aestheticReferences.removeWhere((item) => item.id == record.id);
    _aestheticReferences.add(record);
    _invalidateProviderEstimate();
    _flushComposerTabsSave();
    notifyListeners();
  }

  void deleteAestheticReference(String id) {
    _deletedAestheticIds.add(id);
    _aestheticReferences.removeWhere((item) => item.id == id);
    for (final tab in _composerTabs) {
      if (tab.form.aestheticReferenceId == id) {
        tab.form.aestheticReferenceId = null;
        tab.updatedAt = DateTime.now().toUtc();
      }
    }
    _invalidateProviderEstimate();
    _flushComposerTabsSave();
    notifyListeners();
  }

  ComposerTabsState get _composerWorkspace => ComposerTabsState(
    tabs: _composerTabs.map(_composerTabRecord).toList(),
    activeTabId: _activeComposerTabId,
    closedTabIds: Set.of(_closedComposerTabIds),
    closedTabs: List.of(_recoverableComposerTabs),
    aestheticReferences: List.of(_aestheticReferences),
    deletedAestheticIds: Set.of(_deletedAestheticIds),
    deviceId: _composerDeviceId,
    deviceName: _composerDeviceName,
    devicePlatform: _composerDevicePlatform,
    devices: List.of(_composerDevices),
  );

  /// Takes the store-owned facts a read carries: this device's identity and
  /// every device's published strip. Never touches the open tabs.
  void _absorbDeviceCatalog(ComposerTabsState state) {
    _composerDeviceId = state.deviceId ?? _composerDeviceId;
    _composerDeviceName = state.deviceName ?? _composerDeviceName;
    _composerDevicePlatform = state.devicePlatform ?? _composerDevicePlatform;
    _composerDevices
      ..clear()
      ..addAll(mergeComposerDevices(_composerDevices, state.devices));
  }

  /// Other devices' published drafts, newest device first. This device's
  /// own record and devices with nothing but blank tabs are left out.
  List<ComposerDeviceDrafts> get otherDeviceDrafts => [
    for (final device in _composerDevices)
      if (device.deviceId != _composerDeviceId && device.drafts.isNotEmpty)
        device,
  ];

  bool get hasOtherDeviceDrafts => otherDeviceDrafts.isNotEmpty;

  /// Pulls the other devices' latest records: a quiet Drive read when
  /// connected, else whatever the local mirror already holds.
  Future<void> refreshOtherDeviceDrafts() async {
    if (googleDriveConnected) {
      await _refreshDriveLibrary();
    } else {
      await syncComposerWorkspace();
    }
  }

  /// Opens a copy of [tabId] from [deviceId]'s published strip as a new tab
  /// here. The other device keeps its own; nothing is moved or closed.
  Future<void> openDeviceDraft(String deviceId, String tabId) async {
    final record = _composerDevices
        .where((device) => device.deviceId == deviceId)
        .firstOrNull
        ?.tabs
        .where((tab) => tab.id == tabId)
        .firstOrNull;
    if (record == null) return;
    await _openComposerTabCopy(record);
  }

  void _applyWorkspaceCatalog(ComposerTabsState state) {
    _closedComposerTabIds.addAll(state.closedTabIds);
    _recoverableComposerTabs
      ..clear()
      ..addAll(state.closedTabs.take(10));
    final retainedClosedIds = _recoverableComposerTabs
        .map((tab) => tab.id)
        .toSet();
    _closedComposerDrafts.removeWhere(
      (id, _) => !retainedClosedIds.contains(id),
    );
    _deletedAestheticIds.addAll(state.deletedAestheticIds);
    _aestheticReferences
      ..clear()
      ..addAll(state.aestheticReferences);
  }

  int get sessionOnlyComposerAttachmentCount =>
      form.keyframes
          .where(
            (item) =>
                item.asset != null &&
                item.asset!.retained == null &&
                item.retained == null,
          )
          .length +
      [...form.references, ...activeComposerTab.disabledReferences]
          .where(
            (item) =>
                item.asset != null &&
                item.asset!.retained == null &&
                item.retained == null,
          )
          .length +
      (form.videoAsset != null && form.videoAsset!.retained == null ? 1 : 0) +
      (form.draftAsset != null && form.draftAsset!.retained == null ? 1 : 0);

  bool get canReopenComposerTab => _recoverableComposerTabs.isNotEmpty;
  List<ComposerTabRecord> get recoverableComposerTabs =>
      List.unmodifiable(_recoverableComposerTabs);

  /// The original id remains tombstoned. A recovered draft is a new workspace,
  /// preserving session-only media in memory when the original is still here.
  Future<void> reopenLastComposerTab() async {
    if (_recoverableComposerTabs.isNotEmpty) {
      await reopenComposerTab(_recoverableComposerTabs.first.id);
    }
  }

  Future<void> reopenComposerTab(String id) async {
    final record = _recoverableComposerTabs
        .where((tab) => tab.id == id)
        .firstOrNull;
    if (record == null) return;
    await _openComposerTabCopy(
      record,
      memory: _closedComposerDrafts.remove(record.id),
    );
  }

  /// Opens [record] as a new tab under a fresh id, re-hydrating retained
  /// media, or reusing [memory] (the closed tab's in-memory draft) when the
  /// original is still here so session-only media survives too.
  Future<void> _openComposerTabCopy(
    ComposerTabRecord record, {
    ComposerTab? memory,
  }) async {
    final restored = record.copyWith(
      id: _uid(),
      updatedAt: DateTime.now().toUtc(),
    );
    final tab = ComposerTab(
      id: restored.id,
      providerId: restored.providerId ?? activeComposerTab.providerId,
      modelId: restored.modelId ?? activeComposerTab.modelId,
      form: memory?.form,
      createdAt: restored.createdAt,
      updatedAt: restored.updatedAt,
    );
    if (memory == null) {
      final source = _composerMediaGeneration(restored);
      if (source != null) {
        await _restoreGenerationSettings(
          source,
          cacheOnly: true,
          persistDraft: false,
          tab: tab,
        );
      }
    } else {
      tab.disabledReferences.addAll(memory.disabledReferences);
    }
    if (_disposed) return;
    _inComposerTab(tab, () => _applyComposerTabRecord(tab, restored));
    _composerTabs.add(tab);
    _activeComposerTabId = tab.id;
    _invalidateProviderEstimate();
    _flushComposerTabsSave();
    unawaited(_hydrateComposerMedia(tab));
    notifyListeners();
  }

  /// The app is leaving the foreground: write a pending draft and ask the
  /// store to publish this device's record at once rather than on its
  /// background cadence, so the other devices see it before this one sleeps.
  void flushComposerWorkspace() {
    final pending = _composerTabsSaveTimer?.isActive ?? false;
    _flushComposerTabsSave(onlyIfPending: true, publishNow: true);
    if (pending || _disposed || !_persistsComposerTabs) return;
    if (gateway case final ComposerTabsGateway tabsGateway) {
      unawaited(
        tabsGateway.publishComposerTabs().catchError((Object _) {
          // Publication retries on the next save or Drive read.
        }),
      );
    }
  }

  /// Takes what the store learned from Drive — other devices' published
  /// strips and the shared aesthetic library — without touching the tabs
  /// open here. A sync never rewrites the draft the director is typing in;
  /// another device's work is offered through [otherDeviceDrafts] and opens
  /// as a copy on request.
  Future<void> syncComposerWorkspace() async {
    if (!_composerTabsRestored ||
        _syncingComposerWorkspace ||
        _disposed ||
        gateway is! ComposerTabsGateway) {
      return;
    }
    _syncingComposerWorkspace = true;
    final recoveringUnreadStrip = _composerTabsLoadFailed;
    try {
      final stored = await (gateway as ComposerTabsGateway).loadComposerTabs();
      if (_disposed) return;
      _composerTabsLoadFailed = false;
      _composerWorkspaceSyncFailed = false;
      if (_composerSaveFailures == 0) composerTabsSaveError = null;
      if (stored == null) return;
      _absorbDeviceCatalog(stored);
      if (recoveringUnreadStrip) {
        // Startup could not read this device's own strip, so the work done
        // since lives only in memory. Both halves are this device's: bring
        // the saved tabs back beside the new ones, then write them together.
        _applyWorkspaceCatalog(stored);
        await _adoptStoredTabs(stored);
        if (_disposed) return;
        await _saveComposerTabs();
      }
      final merged = mergeComposerWorkspaces(_composerWorkspace, stored)!;
      _deletedAestheticIds.addAll(merged.deletedAestheticIds);
      _aestheticReferences
        ..clear()
        ..addAll(merged.aestheticReferences);
      for (final tab in _composerTabs) {
        final selected = tab.form.aestheticReferenceId;
        if (selected != null && _deletedAestheticIds.contains(selected)) {
          tab.form.aestheticReferenceId = null;
        }
      }
      _invalidateProviderEstimate();
      notifyListeners();
    } on Object {
      _composerWorkspaceSyncFailed = true;
      composerTabsSaveError =
          'Draft sync could not finish. Your open drafts are still available; retry to sync.';
      if (!_disposed) notifyListeners();
    } finally {
      _syncingComposerWorkspace = false;
    }
  }

  /// Rebuilds the saved tabs this device does not have open (and never
  /// closed) beside the ones in memory. Used only to recover a strip that
  /// could not be read at startup; a cross-device sync never adds tabs.
  Future<void> _adoptStoredTabs(ComposerTabsState stored) async {
    for (final record in stored.tabs) {
      if (_composerTabById(record.id) != null ||
          _closedComposerTabIds.contains(record.id)) {
        continue;
      }
      final rebuilt = ComposerTab(
        id: record.id,
        providerId: record.providerId ?? providers.first.id,
        modelId: record.modelId ?? providers.first.defaultModel.id,
        createdAt: record.createdAt,
        updatedAt: record.updatedAt,
      );
      final source =
          _composerMediaGeneration(record) ??
          generations
              .where((item) => item.localId == record.sourceGenerationId)
              .firstOrNull;
      if (source != null) {
        try {
          await _restoreGenerationSettings(
            source,
            cacheOnly: true,
            persistDraft: false,
            tab: rebuilt,
          );
        } on Object {
          // Missing media must not cost the recovered text.
        }
        if (_disposed) return;
      }
      if (_composerTabById(record.id) != null) continue;
      _inComposerTab(rebuilt, () => _applyComposerTabRecord(rebuilt, record));
      _composerTabs.add(rebuilt);
      unawaited(_hydrateComposerMedia(rebuilt));
    }
    _invalidateProviderEstimate();
    notifyListeners();
  }

  /// Loads retained bytes without rewriting authoring text or timestamps.
  Future<bool> _hydrateComposerMedia(ComposerTab tab) =>
      _composerMediaLoads[tab] ??= _loadComposerMedia(tab).whenComplete(() {
        _composerMediaLoads.remove(tab);
      });

  Future<bool> _loadComposerMedia(ComposerTab tab) async {
    var complete = true;
    Future<PickedAsset?> load(AssetReference retained) async {
      try {
        final asset = await _retainedAsset(retained);
        if (asset.bytes.isEmpty) throw StateError('Missing retained media');
        return asset;
      } on Object {
        complete = false;
        return null;
      }
    }

    for (final frame in List.of(tab.form.keyframes)) {
      if (frame.asset != null || frame.retained?.isLocal != true) continue;
      final asset = await load(frame.retained!);
      if (_disposed) return false;
      if (asset != null) {
        tab.form.keyframes = tab.form.keyframes
            .map(
              (current) => identical(current, frame)
                  ? current.copyWith(asset: asset)
                  : current,
            )
            .toList();
      }
    }
    for (final reference in List.of(tab.form.references)) {
      if (reference.asset != null || reference.retained?.isLocal != true) {
        continue;
      }
      final asset = await load(reference.retained!);
      if (_disposed) return false;
      if (asset != null) {
        tab.form.references = tab.form.references
            .map(
              (current) => identical(current, reference)
                  ? current.copyWith(asset: asset)
                  : current,
            )
            .toList();
      }
    }
    final video = tab.form.videoAsset;
    if (video != null && video.bytes.isEmpty && video.retained != null) {
      final asset = await load(video.retained!);
      if (_disposed) return false;
      if (asset != null && identical(tab.form.videoAsset, video)) {
        tab.form.videoAsset = asset;
      }
    }
    final draft = tab.form.draftAsset;
    if (draft != null && draft.bytes.isEmpty && draft.retained != null) {
      final asset = await load(draft.retained!);
      if (_disposed) return false;
      if (asset != null && identical(tab.form.draftAsset, draft)) {
        tab.form.draftAsset = asset;
      }
    }
    if (!_disposed) notifyListeners();
    return complete;
  }

  Generation? _composerMediaGeneration(ComposerTabRecord record) =>
      record.mediaConfig == null
      ? null
      : Generation.fromJson({
          'localId': record.id,
          'provider': record.providerId,
          'model': record.modelId,
          'prompt': record.prompt,
          'mode': record.mode,
          'config': record.mediaConfig,
          'createdAt': (record.createdAt ?? DateTime.now().toUtc())
              .toIso8601String(),
          'updatedAt': (record.updatedAt ?? DateTime.now().toUtc())
              .toIso8601String(),
        });
}
