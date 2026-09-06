part of 'app_controller.dart';

/// Portable Create workspaces and their text-only aesthetic library.
extension AppControllerWorkspace on AppController {
  List<AestheticReference> get aestheticReferences =>
      List.unmodifiable(_aestheticReferences);
  AestheticReference? get selectedAestheticReference => _aestheticReferences
      .where((item) => item.id == form.aestheticReferenceId)
      .firstOrNull;
  String get generationPrompt =>
      appendAestheticPrompt(form.prompt, selectedAestheticReference);

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
  );

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
    final memory = _closedComposerDrafts.remove(record.id);
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

  void flushComposerWorkspace() => _flushComposerTabsSave(onlyIfPending: true);

  /// Reconcile incoming records without losing local edits made
  /// while the read was in flight. Active selection remains device-local.
  Future<void> syncComposerWorkspace() async {
    if (!_composerTabsRestored ||
        _syncingComposerWorkspace ||
        _disposed ||
        gateway is! ComposerTabsGateway) {
      return;
    }
    _syncingComposerWorkspace = true;
    try {
      final remote = await (gateway as ComposerTabsGateway).loadComposerTabs();
      if (_disposed) return;
      _composerTabsLoadFailed = false;
      _composerWorkspaceSyncFailed = false;
      final merged = mergeComposerWorkspaces(_composerWorkspace, remote)!;
      _applyWorkspaceCatalog(merged);
      for (final record in merged.tabs) {
        final previous = _composerTabById(record.id);
        if (previous != null &&
            jsonEncode(_composerTabRecord(previous).toJson()) ==
                jsonEncode(record.toJson())) {
          continue;
        }
        final previousStamp = previous?.updatedAt;
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
          await _restoreGenerationSettings(
            source,
            cacheOnly: true,
            persistDraft: false,
            tab: rebuilt,
          );
        }
        if (_disposed) return;
        if (_closedComposerTabIds.contains(record.id)) continue;
        final current = _composerTabById(record.id);
        if (current?.updatedAt != previousStamp) continue;
        _inComposerTab(rebuilt, () => _applyComposerTabRecord(rebuilt, record));
        final index = _composerTabs.indexWhere((tab) => tab.id == record.id);
        if (index < 0) {
          _composerTabs.add(rebuilt);
        } else {
          _composerTabs[index] = rebuilt;
        }
        unawaited(_hydrateComposerMedia(rebuilt));
      }
      _composerTabs.removeWhere(
        (tab) => _closedComposerTabIds.contains(tab.id),
      );
      if (_composerTabs.isEmpty) {
        _composerTabs.add(
          ComposerTab(
            id: _uid(),
            providerId: providers.first.id,
            modelId: providers.first.defaultModel.id,
          ),
        );
      }
      if (_composerTabById(_activeComposerTabId) == null) {
        _activeComposerTabId = _composerTabs.first.id;
      }
      _invalidateProviderEstimate();
      notifyListeners();
      // Also publishes offline edits after reconnect, even without a new edit.
      await _saveComposerTabs();
    } on Object {
      _composerWorkspaceSyncFailed = true;
      composerTabsSaveError =
          'Draft sync could not finish. Your open drafts are still available; retry to sync.';
      if (!_disposed) notifyListeners();
    } finally {
      _syncingComposerWorkspace = false;
    }
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
