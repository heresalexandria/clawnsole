part of 'app_controller.dart';

/// AI Rewrite: the controller half of the feature.
///
/// Keys live beside the video-provider credentials (vault ids `openai` and
/// `anthropic`), the LLM call runs through [PromptRewriteGateway] so the key
/// never enters the renderer, and the result opens a new composer tab seeded
/// from the film it rewrote.
extension AiRewriteController on AppController {
  /// Rewrite providers with a usable key on this device.
  Set<String> get connectedRewriteProviders =>
      snapshot?.connectedRewriteProviders ?? const <String>{};

  /// Whether the rewrite feature is set up at all.
  bool get canRewriteAnything =>
      gateway is PromptRewriteGateway && connectedRewriteProviders.isNotEmpty;

  /// AI Rewrite applies to delivered films whose recipe can still be reused
  /// with this build's providers and models. It does not wait for a key:
  /// the dialog asks for one the first time, so the action is discoverable.
  bool canRewrite(Generation item) =>
      gateway is PromptRewriteGateway &&
      item.hasDeliveredMedia &&
      !item.isImage &&
      item.mode != VideoMode.upscale &&
      item.mode != VideoMode.draftEnhance &&
      item.prompt.trim().isNotEmpty &&
      canReuse(item);

  /// Whether the Direction box in front holds something to rewrite.
  bool get canRewriteDirection =>
      gateway is PromptRewriteGateway && form.prompt.trim().isNotEmpty;

  /// Puts [result] into the tab it was written for, keeping the direction it
  /// replaced one notice tap away. A tab closed meanwhile drops the result
  /// with a word rather than landing it somewhere else.
  void applyRewrittenDirection(
    PromptRewriteResult result, {
    required String tabId,
  }) {
    final tab = _composerTabById(tabId);
    if (tab == null) {
      showNotice('That tab was closed before the rewrite came back.');
      return;
    }
    _directionRewriteUndo = (
      tabId: tab.id,
      previous: tab.form.prompt,
      rewritten: result.prompt,
    );
    _inComposerTab(tab, () {
      tab.form.prompt = result.prompt;
      tab.formRevision += 1;
    });
    _scheduleComposerTabsSave(touched: tab);
    notifyListeners();
    final summary = result.summary.trim();
    showNotice(
      summary.isEmpty
          ? 'Direction rewritten.'
          : 'Direction rewritten: $summary',
      action: AppNoticeAction.undoDirectionRewrite,
    );
  }

  /// Restores the direction the last rewrite replaced, unless it has been
  /// edited since or its tab is gone.
  void undoDirectionRewrite() {
    final undo = _directionRewriteUndo;
    _directionRewriteUndo = null;
    if (undo == null) return;
    final tab = _composerTabById(undo.tabId);
    if (tab == null || tab.form.prompt != undo.rewritten) {
      showNotice('That direction has changed since; nothing to undo.');
      return;
    }
    _inComposerTab(tab, () {
      tab.form.prompt = undo.previous;
      tab.formRevision += 1;
    });
    _scheduleComposerTabsSave(touched: tab);
    notifyListeners();
    showNotice('Direction restored.');
  }

  /// The provider the rewrite dialog should open with: the remembered one
  /// when it still has a key, else the first connected provider.
  RewriteProvider? get preferredRewriteProvider {
    final remembered = RewriteProvider.byId(rewriteProviderId);
    if (remembered != null &&
        connectedRewriteProviders.contains(remembered.id)) {
      return remembered;
    }
    for (final id in rewriteProviderIds) {
      if (connectedRewriteProviders.contains(id)) {
        return RewriteProvider.byId(id);
      }
    }
    return null;
  }

  /// The remembered model for [provider], falling back to its default.
  String rewriteModelFor(RewriteProvider provider) =>
      rewriteModelIds[provider.id] ?? provider.defaultModelId;

  /// The remembered effort for [provider], falling back to its default.
  String rewriteEffortFor(RewriteProvider provider) =>
      rewriteEfforts[provider.id] ?? provider.defaultEffort;

  /// Models for [provider]: the live listing when it can be fetched (cached
  /// per session), otherwise the curated list. Never throws; a listing
  /// failure simply leaves the curated models in place.
  Future<List<RewriteModel>> loadRewriteModels(
    RewriteProvider provider, {
    bool refresh = false,
  }) async {
    final cached = rewriteModels[provider.id];
    if (cached != null && !refresh) return cached;
    if (gateway case final PromptRewriteGateway rewriteGateway) {
      try {
        final listed = await rewriteGateway.listRewriteModels(provider.id);
        if (listed.isNotEmpty) {
          rewriteModels[provider.id] = listed;
          notifyListeners();
          return listed;
        }
      } on Object {
        // Fall through to the curated list; the dialog stays usable offline.
      }
    }
    return provider.curatedModels;
  }

  /// Remembers the dialog's choices so the next rewrite opens the same way.
  Future<void> rememberRewriteChoice({
    required RewriteProvider provider,
    required String modelId,
    String? effort,
  }) async {
    rewriteProviderId = provider.id;
    rewriteModelIds[provider.id] = modelId;
    if (effort == null || effort.isEmpty) {
      rewriteEfforts.remove(provider.id);
    } else {
      rewriteEfforts[provider.id] = effort;
    }
    try {
      await _savePreferences(_preferences());
    } on Object {
      // A failed preference write must not block the rewrite itself.
    }
  }

  /// Asks the LLM for a revised prompt. Throws [PromptRewriteException]
  /// with a typed failure on every error path.
  Future<PromptRewriteResult> rewritePrompt(PromptRewriteRequest request) {
    if (gateway case final PromptRewriteGateway rewriteGateway) {
      return rewriteGateway.rewritePrompt(request);
    }
    throw const PromptRewriteException(
      'This app build cannot run AI Rewrite.',
      failure: PromptRewriteFailure.other,
    );
  }

  /// Verifies [key] against the vendor (a models listing) and saves it.
  Future<void> saveRewriteKey(RewriteProvider provider, String key) async {
    final clean = key.trim();
    if (clean.isEmpty) {
      throw const PromptRewriteException(
        'Paste an API key first.',
        failure: PromptRewriteFailure.missingKey,
      );
    }
    if (gateway is! ProviderGateway || gateway is! PromptRewriteGateway) {
      throw const PromptRewriteException(
        'This app build cannot save AI Rewrite keys.',
        failure: PromptRewriteFailure.other,
      );
    }
    final listed = await (gateway as PromptRewriteGateway).listRewriteModels(
      provider.id,
      candidateKey: clean,
    );
    if (listed.isNotEmpty) rewriteModels[provider.id] = listed;
    _apply(
      await (gateway as ProviderGateway).setProviderApiKey(provider.id, clean),
    );
    showNotice('${provider.name} key verified and saved locally.');
  }

  /// Forgets the saved key for [provider] on this device.
  Future<void> removeRewriteKey(RewriteProvider provider) async {
    if (gateway is! ProviderGateway) {
      throw const PromptRewriteException(
        'This app build cannot remove AI Rewrite keys.',
        failure: PromptRewriteFailure.other,
      );
    }
    _apply(await (gateway as ProviderGateway).clearProviderApiKey(provider.id));
    rewriteModels.remove(provider.id);
    showNotice('${provider.name} access removed from this device.');
  }
}
