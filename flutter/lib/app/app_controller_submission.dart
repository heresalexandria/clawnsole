part of 'app_controller.dart';

/// A Generate activation captures one independent operation. The lock covers
/// preparation and acceptance only: an identical later activation is a new job.
extension AppControllerSubmission on AppController {
  ComposerTab _captureSubmissionTab() {
    final source = activeComposerTab;
    final tab = ComposerTab(
      id: source.id,
      providerId: source.providerId,
      modelId: source.modelId,
      title: source.title,
      sourceGenerationId: source.sourceGenerationId,
      rewriteSummary: source.rewriteSummary,
      localFolderId: source.localFolderId,
      driveFolderId: source.driveFolderId,
      createdAt: source.createdAt,
      updatedAt: source.updatedAt,
    );
    final value = source.form;
    tab.form
      ..prompt = value.prompt
      ..screenplayMode = value.screenplayMode
      ..aestheticReferenceId = value.aestheticReferenceId
      ..screenplayLinkedCharacters.addAll(value.screenplayLinkedCharacters)
      ..screenplayCharacterAliases.addAll(value.screenplayCharacterAliases)
      ..draftCharacterNames.addAll(value.draftCharacterNames)
      ..aspectRatio = value.aspectRatio
      ..autoDuration = value.autoDuration
      ..durationSeconds = value.durationSeconds
      ..frameRate = value.frameRate
      ..resolution = value.resolution
      ..generateAudio = value.generateAudio
      ..safetyTolerance = value.safetyTolerance
      ..draft = value.draft
      ..exactTiming = value.exactTiming
      ..keyframes = List.of(value.keyframes)
      ..references = List.of(value.references)
      ..referenceTask = value.referenceTask
      ..videoAsset = value.videoAsset
      ..videoSavedReferenceId = value.videoSavedReferenceId
      ..videoUrl = value.videoUrl
      ..videoThumbnailBytes = value.videoThumbnailBytes
      ..videoMetadata = value.videoMetadata
      ..draftAsset = value.draftAsset
      ..draftUrl = value.draftUrl
      ..upscale = value.upscale
      ..upscaleFactor = value.upscaleFactor
      ..upscaleCreativity = value.upscaleCreativity
      ..seed = value.seed;
    return tab;
  }

  Future<void> _submitCaptured({
    required bool providerRetentionRiskAcknowledged,
  }) async {
    if (submitting || _disposed) return;
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

    // Capture every recipe and routing choice before the first await, including
    // before hydration of a restored draft. Editing/switching tabs is still safe.
    final tab = _captureSubmissionTab();
    final provider = selectedProvider;
    final model = selectedModel;
    final prompt = generationPrompt;
    final quoteInput = _providerEstimateInput();
    final fallbackEstimate = currentEstimate;
    final normalizeReferences = autoFixReferenceVideos;
    final checksVisualReferences =
        normalizeReferences &&
        (form.keyframes.isNotEmpty ||
            form.referenceCount(MediaReferenceKind.image) > 0 ||
            (model.referenceVideoCompatibilityProfile != null &&
                form.referenceCount(MediaReferenceKind.video) > 0));
    final now = DateTime.now().toUtc();
    var pending = Generation(
      localId: _uid(),
      provider: provider.id,
      model: model.id,
      canonicalModelId: model.canonicalId,
      billingUnit: provider.isLocal
          ? 'local'
          : const {'bfl', 'artcraft', 'runway'}.contains(provider.id)
          ? 'credits'
          : 'usd',
      outputKind: model.outputKind,
      status: 'submitting',
      progress: 0,
      prompt: form.mode == VideoMode.draftEnhance
          ? 'Enhance saved FLUX 3 draft'
          : prompt,
      mode: form.mode,
      config: currentConfig,
      createdAt: now,
      updatedAt: now,
      estimatedCreditsMin:
          fallbackEstimate.providerUnitsMinimum ?? fallbackEstimate.minimumUsd,
      estimatedCreditsMax:
          fallbackEstimate.providerUnitsMaximum ?? fallbackEstimate.maximumUsd,
      estimateBasis: fallbackEstimate.basis,
      quotedCostUsdMin: fallbackEstimate.minimumUsd,
      quotedCostUsdMax: fallbackEstimate.maximumUsd,
      folderId: selectedGenerationFolderId,
      title: tab.title,
      rewriteOfLocalId: tab.rewriteSummary == null
          ? null
          : tab.sourceGenerationId,
      rewriteSummary: tab.rewriteSummary,
      storage: effectiveStorage,
    );
    submitting = true;
    notifyListeners();
    try {
      if (!await _hydrateComposerMedia(tab)) {
        if (!_disposed) {
          showNotice(
            'Some draft media is unavailable. Connect Drive or restore the original media before generating.',
          );
        }
        return;
      }
      if (_disposed) return;
      final input = _inComposerTab(tab, _buildInput);
      if (input.containsKey('prompt')) input['prompt'] = prompt;
      if (provider.requiresApiKey &&
          !await refreshCredits(providerId: provider.id)) {
        return;
      }
      if (_disposed) return;
      _flushComposerTabsSave(onlyIfPending: true);
      unawaited(_requestNotificationsOnce());
      if (provider.id == 'artcraft' && gateway is ProviderGateway) {
        try {
          final quote = await (gateway as ProviderGateway).quoteProviderCost(
            provider.id,
            model.id,
            quoteInput,
          );
          if (quote != null) {
            final estimate = quote.withPricingContext(fallbackEstimate);
            pending = pending.copyWith(
              estimatedCreditsMin:
                  estimate.providerUnitsMinimum ?? estimate.minimumUsd,
              estimatedCreditsMax:
                  estimate.providerUnitsMaximum ?? estimate.maximumUsd,
              estimateBasis: estimate.basis,
              quotedCostUsdMin: estimate.minimumUsd,
              quotedCostUsdMax: estimate.maximumUsd,
            );
          }
        } on Object {
          // A failed quote retains the captured published estimate.
        }
      }
      if (_disposed) return;
      final referenceThumbnailBytes = tab.form.references
          .map((item) => item.thumbnailBytes ?? item.asset?.thumbnailBytes)
          .toList(growable: false);
      final sourceThumbnailBytes =
          tab.form.videoAsset?.thumbnailBytes ?? tab.form.videoThumbnailBytes;
      _replaceInMemory(pending);
      showNotice(
        checksVisualReferences
            ? 'Checking visual reference compatibility before sending…'
            : pending.mode == VideoMode.upscale
            ? 'Submitting upscale…'
            : 'Submitting generation…',
      );
      pending = await gateway.submit(
        GenerationSubmission(
          record: pending,
          input: input,
          autoFixReferenceVideos: normalizeReferences,
        ),
      );
      _replaceInMemory(pending);
      if (pending.isSubmissionUnknown) {
        showNotice(
          pending.error ??
              'The provider may have accepted this generation. Check its console before generating again.',
        );
        return;
      }
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
      if (pending.provider == selectedProviderId &&
          pending.creditsAfter != null) {
        credits = pending.creditsAfter;
      }
    } on Object catch (error) {
      // Receipt persistence is the irreversible boundary. Optional local work
      // must never turn an accepted or uncertain operation into a failed job.
      if (pending.canCheckStatus || pending.isSubmissionUnknown) {
        _replaceInMemory(pending);
        showNotice(
          pending.isSubmissionUnknown
              ? pending.error ??
                    'Check the provider console before submitting again.'
              : 'The provider receipt is saved. Some local follow-up work could not finish.',
        );
        return;
      }
      await _invalidateRejectedApiKey(
        error,
        showNoticeOnFailure: true,
        providerId: provider.id,
      );
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
      if (!_disposed) notifyListeners();
    }
  }
}
