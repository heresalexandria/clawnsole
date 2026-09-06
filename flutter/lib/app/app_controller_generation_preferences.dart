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

  ComposerTab _blankComposerTab(ComposerTab source) {
    final tab = ComposerTab(
      id: _uid(),
      providerId: source.providerId,
      modelId: source.modelId,
      localFolderId: source.localFolderId,
      driveFolderId: source.driveFolderId,
    );
    _applyGenerationSettings(
      tab,
      _generationPreferences[generationPreferenceKey(
            tab.providerId,
            tab.modelId,
          )] ??
          _generationSettings(source),
    );
    _inComposerTab(tab, _normalizeFormForModel);
    return tab;
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
