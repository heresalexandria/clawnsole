part of 'app_controller.dart';

/// Last-used generation knobs are separate from any particular creative draft.
extension AppControllerGenerationPreferences on AppController {
  GenerationPreferences _generationSettings(ComposerTab tab) {
    final value = tab.form;
    return GenerationPreferences(
      aspectRatio: value.aspectRatio,
      autoDuration: value.autoDuration,
      durationSeconds: value.durationSeconds,
      frameRate: value.frameRate,
      resolution: value.resolution,
      generateAudio: value.generateAudio,
      safetyTolerance: value.safetyTolerance,
      draft: value.draft,
      exactTiming: value.exactTiming,
      upscaleFactor: value.upscaleFactor,
      upscaleCreativity: value.upscaleCreativity,
    );
  }

  void _applyGenerationSettings(
    ComposerTab tab,
    GenerationPreferences settings,
  ) {
    tab.form
      ..aspectRatio = settings.aspectRatio
      ..autoDuration = settings.autoDuration
      ..durationSeconds = settings.durationSeconds
      ..frameRate = settings.frameRate
      ..resolution = settings.resolution
      ..generateAudio = settings.generateAudio
      ..safetyTolerance = settings.safetyTolerance
      ..draft = settings.draft
      ..exactTiming = settings.exactTiming
      ..upscaleFactor = settings.upscaleFactor
      ..upscaleCreativity = settings.upscaleCreativity;
    tab.generateAudioExplicitlyDisabled = !settings.generateAudio;
  }

  void _restoreGenerationPreferences(ComposerTab tab) {
    final settings =
        _generationPreferences[generationPreferenceKey(
          tab.providerId,
          tab.modelId,
        )];
    if (settings != null) {
      _applyGenerationSettings(tab, settings);
    } else if (modelById(
      tab.providerId,
      tab.modelId,
    ).upscaleUsesResolutionTargets) {
      // A first visit gets the model's default. Subsequent normalization must
      // preserve a deliberate 0% or 1% creative-detail setting.
      tab.form.upscaleCreativity = 50;
    }
  }

  /// The model a new blank draft opens on: the Defaults desk's choice while
  /// the live catalog still has it, and otherwise nothing — a model that has
  /// been withdrawn falls back to whatever the last draft was using.
  (String, String)? _defaultProviderModel() {
    final defaults = createDefaults;
    if (!defaults.hasModel) return null;
    final provider = providers
        .where((item) => item.id == defaults.providerId)
        .firstOrNull;
    final model = provider?.models
        .where((item) => item.id == defaults.modelId)
        .firstOrNull;
    if (provider == null || model == null) return null;
    return (provider.id, model.id);
  }

  /// Opens a blank draft carrying the source tab's provider, model, folders,
  /// and studio-wide choices, plus the last-used controls for that model, then
  /// the Defaults desk's answers over the top.
  ///
  /// The format and the chosen aesthetic ride along on the tab rather than
  /// through [GenerationPreferences]: they are decisions about the film being
  /// written, not knobs belonging to a model, so a director working in
  /// Screenplay keeps writing screenplays in the next draft while switching
  /// model inside a draft leaves the format alone.
  ComposerTab _blankComposerTab(
    ComposerTab source, {
    bool applyCreateDefaults = true,
  }) {
    // The model comes first: its own remembered controls are what the rest of
    // the defaults are then laid over.
    final chosen = applyCreateDefaults ? _defaultProviderModel() : null;
    final tab = ComposerTab(
      id: _uid(),
      providerId: chosen?.$1 ?? source.providerId,
      modelId: chosen?.$2 ?? source.modelId,
      localFolderId: source.localFolderId,
      driveFolderId: source.driveFolderId,
    );
    tab.form
      ..screenplayMode = source.form.screenplayMode
      ..aestheticReferenceId = source.form.aestheticReferenceId;
    _applyGenerationSettings(
      tab,
      _generationPreferences[generationPreferenceKey(
            tab.providerId,
            tab.modelId,
          )] ??
          _generationSettings(source),
    );
    if (applyCreateDefaults) _applyCreateDefaults(tab);
    // What the tab opened with is nobody's work in it yet, so Reuse, Extend
    // and Enhance may still seed it in place.
    tab
      ..openedScreenplayMode = tab.form.screenplayMode
      ..openedAestheticReferenceId = tab.form.aestheticReferenceId;
    _inComposerTab(tab, _normalizeFormForModel);
    return tab;
  }

  /// Lays the Defaults desk's answers over an inherited blank draft.
  ///
  /// An unset field is left exactly as inheritance and the per-model record
  /// left it — that is what "Last used" means — and `_normalizeFormForModel`
  /// still has the last word on a combination the chosen model cannot take.
  void _applyCreateDefaults(ComposerTab tab) {
    final defaults = createDefaults;
    if (defaults.isEmpty) return;
    final form = tab.form;
    if (defaults.screenplayMode case final bool value) {
      form.screenplayMode = value;
    }
    if (defaults.aestheticReferenceId case final String id) {
      // The empty string is an explicit "None". An id the library no longer
      // holds also starts the draft with none: the aesthetic that was asked
      // for is gone, and quietly borrowing the last draft's would be a lie.
      form.aestheticReferenceId =
          id.isEmpty || !_aestheticReferences.any((item) => item.id == id)
          ? null
          : id;
    }
    if (defaults.aspectRatio case final String value) form.aspectRatio = value;
    if (defaults.resolution case final String value) form.resolution = value;
    if (defaults.duration case final CreateDurationDefault value) {
      form.autoDuration = value.isAuto;
      if (value.seconds case final int seconds) {
        form.durationSeconds = seconds;
      }
    }
    if (defaults.generateAudio case final bool value) {
      form.generateAudio = value;
      // Asking for silence here is as deliberate as reaching for the switch,
      // so a model that supports audio must not turn it back on.
      tab.generateAudioExplicitlyDisabled = !value;
    }
    if (defaults.draft case final bool value) form.draft = value;
  }

  void _rememberGenerationPreferences(
    ComposerTab tab, {
    bool onlyIfAbsent = false,
    bool persist = true,
  }) {
    if (_disposed || _restoringComposerTabs) return;
    final key = generationPreferenceKey(tab.providerId, tab.modelId);
    if (onlyIfAbsent && _generationPreferences.containsKey(key)) return;
    final settings = _generationSettings(tab);
    if (_generationPreferences[key] == settings) return;
    _generationPreferences[key] = settings;
    if (persist) _scheduleGenerationPreferencesSave();
  }

  void _scheduleGenerationPreferencesSave() {
    // Protect changes immediately from an older in-flight preference restore,
    // while coalescing slider edits into one durable write.
    _preferenceRevision += 1;
    _generationPreferencesSaveTimer?.cancel();
    _generationPreferencesSaveTimer = Timer(
      AppController.composerTabsSaveDebounce,
      _flushGenerationPreferencesSave,
    );
  }

  void _flushGenerationPreferencesSave() {
    if (_generationPreferencesSaveTimer == null) return;
    _generationPreferencesSaveTimer?.cancel();
    _generationPreferencesSaveTimer = null;
    unawaited(_persistSelection());
  }

  /// Upgrade existing sessions without replacing explicit saved defaults. The
  /// newest draft for each model wins; history fills models without a draft.
  void _seedMissingGenerationPreferences({bool includeTabs = true}) {
    final tabs = List<ComposerTab>.of(_composerTabs)
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    for (final tab in tabs) {
      if (includeTabs && _hasLegacyGenerationSettings(tab)) {
        _rememberGenerationPreferences(tab, onlyIfAbsent: true, persist: false);
      }
    }
    final history = List<Generation>.of(generations)
      ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
    for (final generation in history) {
      final key = generationPreferenceKey(
        generation.provider,
        generation.model,
      );
      if (_generationPreferences.containsKey(key)) continue;
      final config = generation.config;
      _generationPreferences[key] = GenerationPreferences(
        aspectRatio: config.aspectRatio,
        autoDuration: config.duration == 'auto',
        durationSeconds: config.duration is num
            ? (config.duration as num).toInt()
            : 8,
        frameRate: config.frameRate,
        resolution: config.resolution,
        generateAudio: config.generateAudio,
        safetyTolerance: config.safetyTolerance,
        draft: config.draft,
        exactTiming: config.exactTiming,
        upscaleFactor: config.upscaleFactor,
        upscaleCreativity: config.upscaleCreativity,
      );
    }
    // Migration is presentation-only until a real preference edit is saved.
    // Writing here would make local legacy defaults newer than settings still
    // arriving from the startup Drive/vault reconciliation.
  }

  bool _hasLegacyGenerationSettings(ComposerTab tab) {
    if (tab.sourceGenerationId != null ||
        tab.form.prompt.trim().isNotEmpty ||
        tab.form.references.isNotEmpty ||
        tab.form.keyframes.isNotEmpty ||
        tab.form.videoUrl.isNotEmpty ||
        tab.form.draftUrl.isNotEmpty) {
      return true;
    }
    final baseline = ComposerTab(
      id: 'generation-preference-baseline',
      providerId: tab.providerId,
      modelId: tab.modelId,
    );
    if (modelById(tab.providerId, tab.modelId).upscaleUsesResolutionTargets) {
      baseline.form.upscaleCreativity = 50;
    }
    _inComposerTab(baseline, _normalizeFormForModel);
    return _generationSettings(tab) != _generationSettings(baseline);
  }
}
