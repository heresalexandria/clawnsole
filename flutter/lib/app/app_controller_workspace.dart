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

  void saveAestheticReference({
    String? id,
    required String title,
    required String text,
    required String icon,
    required int color,
  }) {
    if (title.trim().isEmpty || text.trim().isEmpty) return;
    final record = AestheticReference(
      id: id ?? _uid(),
      title: title.trim(),
      text: text.trim(),
      icon: icon,
      color: color,
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
