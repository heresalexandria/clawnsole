part of 'app_controller.dart';

extension _AppControllerDelivery on AppController {
  /// Keep provider receipts moving even while both media slots are occupied.
  Future<void> _pollDeliveryStages({required bool ignoreSchedule}) async {
    if (_disposed) return;
    final now = DateTime.now().toUtc();
    for (final item in generations) {
      if (item.resultUrl != null &&
          (item.resultRetentionFailures == 0 || !hasApiKeyFor(item.provider)) &&
          (ignoreSchedule
              ? item.needsResultRetention
              : item.isResultRetentionDue(now))) {
        _queueResultRetention(item);
      }
    }
    if (_polling) {
      if (ignoreSchedule) _pollAgainIgnoringSchedule = true;
      return;
    }
    _pollAgainIgnoringSchedule = false;
    final working = generations.where((item) {
      if (!item.canCheckStatus ||
          !hasApiKeyFor(item.provider) ||
          _statusChecks.contains(item.localId) ||
          _queuedRetentions.containsKey(item.localId) ||
          _activeRetentions.contains(item.localId)) {
        return false;
      }
      final due = ignoreSchedule || item.isStatusCheckDue(now);
      return due &&
          (item.isWorking ||
              (item.needsResultRetention &&
                  (ignoreSchedule || item.isResultRetentionDue(now))));
    }).toList();
    if (working.isEmpty) return;
    _polling = true;
    try {
      // A single status request at a time is also a per-provider limit. Media
      // transfers use a separate pool, never this status request slot.
      for (final original in working) {
        if (_disposed) break;
        final item = _currentGeneration(original.localId);
        if (item == null ||
            !hasApiKeyFor(item.provider) ||
            !_statusChecks.add(item.localId)) {
          continue;
        }
        try {
          final updated = await (gateway as GenerationDeliveryGateway)
              .pollStatus(item)
              .timeout(const Duration(seconds: 90));
          if (!_applyGenerationWorkUpdate(updated)) continue;
          final rejected = await _invalidateRejectedApiKey(
            updated.lastProviderStatusCode,
            showNoticeOnFailure: true,
            providerId: item.provider,
          );
          if (_disposed) break;
          _showGenerationWorkNotice(item, updated);
          if (updated.needsResultRetention && !rejected) {
            _queueResultRetention(updated);
          }
        } on Object catch (error) {
          if (_disposed) break;
          if (await _invalidateRejectedApiKey(
            error,
            showNoticeOnFailure: true,
            providerId: item.provider,
          )) {
            continue;
          }
          final current = _currentGeneration(item.localId);
          if (current == null ||
              current.statusCheckCount != item.statusCheckCount) {
            continue;
          }
          // An outer transport failure has no persisted write version. Keep
          // the saved counter so the next attempt can still compare-and-save.
          _applyGenerationWorkUpdate(
            current.copyWith(
              lastCheckedAt: DateTime.now().toUtc(),
              consecutiveCheckFailures: current.consecutiveCheckFailures + 1,
              lastCheckError: _message(error),
            ),
          );
        } finally {
          _statusChecks.remove(item.localId);
        }
      }
    } finally {
      _polling = false;
      if (!_disposed) notifyListeners();
      if (_pollAgainIgnoringSchedule && !_disposed) {
        _pollAgainIgnoringSchedule = false;
        unawaited(pollWorking(ignoreSchedule: true));
      }
    }
  }

  Generation? _currentGeneration(String localId) =>
      generations.where((item) => item.localId == localId).firstOrNull;

  bool _applyGenerationWorkUpdate(Generation updated) {
    if (_disposed) return false;
    final current = _currentGeneration(updated.localId);
    if (current == null ||
        current.statusCheckCount > updated.statusCheckCount ||
        (current.resultAsset != null && updated.resultAsset == null)) {
      return false;
    }
    _replaceInMemory(updated);
    return true;
  }

  void _showGenerationWorkNotice(Generation before, Generation after) {
    if (_disposed) return;
    if (before.resultAsset == null && after.resultAsset != null) {
      showNotice('Your film is ready and safely saved.');
      if (after.storage == LibraryStorage.drive) {
        _enqueueVideoPrefetch(after.resultAsset);
      }
    } else if (!before.isReady && after.isReady) {
      showNotice('Your film is ready. Saving its media now.');
    } else if (!before.isFailed && after.isFailed) {
      showNotice(
        'Generation needs attention: ${after.error ?? after.statusLabel}',
      );
    }
  }

  void _queueResultRetention(Generation item) {
    if (_disposed ||
        !item.needsResultRetention ||
        _activeRetentions.contains(item.localId)) {
      return;
    }
    _queuedRetentions[item.localId] = item;
    // Deferring until the next microtask lets a batch sort by link expiry.
    scheduleMicrotask(_drainResultRetentions);
  }

  void _drainResultRetentions() {
    if (_disposed) return;
    while (_activeRetentions.length < 2 && _queuedRetentions.isNotEmpty) {
      final queue = _queuedRetentions.values.toList()
        ..sort((a, b) {
          final expiryA = a.deliveryExpiresAt;
          final expiryB = b.deliveryExpiresAt;
          if (expiryA != null && expiryB == null) return -1;
          if (expiryA == null && expiryB != null) return 1;
          final expiryOrder = expiryA?.compareTo(expiryB!) ?? 0;
          return expiryOrder != 0
              ? expiryOrder
              : a.createdAt.compareTo(b.createdAt);
        });
      final queued = queue.first;
      _queuedRetentions.remove(queued.localId);
      final item = _currentGeneration(queued.localId);
      if (item == null || !item.needsResultRetention) continue;
      _activeRetentions.add(item.localId);
      unawaited(_runResultRetention(item));
    }
  }

  Future<void> _runResultRetention(Generation item) async {
    try {
      final updated = await (gateway as GenerationDeliveryGateway)
          .retainResult(item)
          .timeout(const Duration(minutes: 10));
      if (_applyGenerationWorkUpdate(updated)) {
        _showGenerationWorkNotice(item, updated);
      }
    } on Object catch (error) {
      final current = _currentGeneration(item.localId);
      if (!_disposed && current != null && current.needsResultRetention) {
        _applyGenerationWorkUpdate(
          current.copyWith(
            lastResultRetentionAttemptAt: DateTime.now().toUtc(),
            resultRetentionFailures: current.resultRetentionFailures + 1,
            resultRetentionError: _message(error),
          ),
        );
      }
    } finally {
      _activeRetentions.remove(item.localId);
      if (!_disposed) {
        notifyListeners();
        _drainResultRetentions();
      }
    }
  }
}
