import 'dart:async';

import 'hybrid_data_store.dart';
import 'models.dart';

/// Re-fetches a Drive-tagged result whose staged bytes are missing on this
/// device, from the provider link the [owner] record still carries. Returns
/// the newly staged local reference, or null when nothing could be fetched.
typedef DriveResultRestager =
    Future<AssetReference?> Function(Generation owner, AssetReference staged);

/// What one process remembers about its own Drive uploads between passes.
///
/// Uploading and swapping the record are separate steps, and the swap can
/// fail on its own (Drive drops the session between the two, say). Without a
/// memory of what already reached Drive, the retry would upload the same
/// bytes again and leave a duplicate file behind. [resolved] also lets the
/// media routes keep serving a staged id a client still holds after the
/// record it read has moved on to the Drive id.
class DriveUploadLedger {
  /// Drive files uploaded by this process whose record swap has not landed.
  final Map<String, AssetReference> published = <String, AssetReference>{};

  /// Every staged id this process published, and the Drive file it became.
  final Map<String, AssetReference> resolved = <String, AssetReference>{};

  /// Staged ids whose missing bytes were already re-fetched once. Second
  /// attempts wait for the next launch so a dead link cannot loop.
  final Set<String> restaged = <String>{};

  /// Whether the last pass found Drive disconnected with uploads waiting, so
  /// the wait is logged once per episode rather than on every retry.
  bool waitingForDrive = false;

  /// The Drive file a staged local id turned into, if this process
  /// published it.
  AssetReference? resolve(String stagedId) => resolved[stagedId];
}

/// Runs one background Drive upload pass: publishes staged media, swaps the
/// records over through the owner's canonical read/write path (the vault
/// facade on native builds, the serialized companion store on desktop web),
/// then keeps the staged originals as this device's cached copies.
///
/// Which media is pending comes from [readPending] — by default the local
/// mirror, which needs no Drive round trip — so a Drive hiccup cannot fail a
/// pass before it starts. Provide either [swap] or both [read] and [write].
///
/// Returns true when nothing this device can publish remains pending. While
/// Drive is disconnected and uploads are waiting, the pass reports false so
/// the pump keeps retrying (cheaply, from the local mirror) until Drive is
/// back, instead of leaving the films marked "Syncing…" until a relaunch.
///
/// A staged result whose bytes are not on this device is normally another
/// device's film in transit and is left alone. Only once its record has sat
/// unpublished for [restageAfter] — the origin device lost the file, or went
/// away — is it fetched again from the provider link, when one is still live.
Future<bool> runDriveUploadPass({
  required HybridDataStore hybrid,
  Future<StoredData> Function()? read,
  Future<void> Function(StoredData data)? write,
  Future<void> Function(Map<String, AssetReference> replacements)? swap,
  Future<StoredData> Function()? readPending,
  DriveUploadLedger? ledger,
  DriveResultRestager? restage,
  Duration restageAfter = const Duration(minutes: 10),
  DateTime Function()? clock,
  void Function(String message)? log,
}) async {
  assert(
    swap != null || (read != null && write != null),
    'Provide swap, or read and write.',
  );
  final memory = ledger ?? DriveUploadLedger();
  final pending = await (readPending ?? hybrid.readCached)();
  final queued = HybridDataStore.pendingDriveUploads(pending);
  if (queued.isEmpty) return true;
  if (!hybrid.isDriveConnected) {
    if (!memory.waitingForDrive) {
      memory.waitingForDrive = true;
      log?.call(
        'Drive upload pass: ${queued.length} staged file(s) waiting for '
        'Drive to reconnect.',
      );
    }
    return false;
  }
  memory.waitingForDrive = false;
  final result = await hybrid.uploadQueuedDriveAssets(
    pending,
    published: memory.published,
    log: log,
  );
  memory.published.addAll(result.replacements);
  memory.resolved.addAll(result.replacements);

  // A staged result whose bytes vanished can be fetched again from the
  // provider link the record still carries; the next pass then uploads it.
  final restagedReplacements = <String, AssetReference>{};
  if (restage != null) {
    final stuckBefore = (clock ?? DateTime.now)().toUtc().subtract(
      restageAfter,
    );
    for (final entry in result.missing.entries) {
      final owner = pending.generations
          .where((item) => item.resultAsset?.value == entry.key)
          .firstOrNull;
      if (owner == null ||
          !owner.isReady ||
          owner.resultUrl == null ||
          owner.updatedAt.isAfter(stuckBefore) ||
          !memory.restaged.add(entry.key)) {
        continue;
      }
      try {
        final fetched = await restage(owner, entry.value);
        if (fetched != null) {
          restagedReplacements[entry.key] = fetched;
          log?.call(
            'Drive upload pass: re-fetched ${entry.value.label} for '
            '${owner.localId}; its staged copy was missing.',
          );
        }
      } on Object catch (error) {
        log?.call(
          'Drive upload pass: could not re-fetch ${entry.value.label}: $error',
        );
      }
    }
  }

  final replacements = <String, AssetReference>{
    ...result.replacements,
    ...restagedReplacements,
  };
  if (replacements.isNotEmpty) {
    if (result.replacements.isNotEmpty) {
      log?.call(
        'Drive upload pass: published ${result.replacements.length} file(s)'
        '${result.failures > 0 ? ', ${result.failures} failed' : ''}.',
      );
    }
    try {
      if (swap != null) {
        await swap(replacements);
      } else {
        // Swap on a fresh read so records written while the uploads ran are
        // kept.
        await write!(
          HybridDataStore.applyDriveAssetReplacements(
            await read!(),
            replacements,
          ),
        );
      }
    } on Object catch (error) {
      // The uploads stand; only the record swap is retried, from memory.
      log?.call('Drive upload pass: record swap deferred: $error');
      rethrow;
    }
    memory.published.removeWhere(
      (id, _) => result.replacements.containsKey(id),
    );
    final adopted = await hybrid.adoptPublishedAssets(result);
    if (adopted > 0) {
      log?.call(
        'Drive upload pass: kept $adopted published file(s) in the local '
        'media cache.',
      );
    }
  } else if (result.failures > 0) {
    log?.call('Drive upload pass: ${result.failures} upload(s) failed.');
  }
  return result.failures == 0 && restagedReplacements.isEmpty;
}

/// Schedules background Drive upload passes with single-flight execution and
/// exponential retry backoff. Owners call [schedule] whenever staged media
/// may be waiting: after a deferred write, a Drive connect, or a refresh.
class DriveUploadPump {
  DriveUploadPump({
    required Future<bool> Function() flush,
    this.initialRetryDelay = const Duration(seconds: 5),
    this.maximumRetryDelay = const Duration(minutes: 5),
    this.settleDelay = const Duration(seconds: 1),
  }) : _flush = flush;

  final Future<bool> Function() _flush;
  final Duration initialRetryDelay;
  final Duration maximumRetryDelay;

  /// How long a freshly scheduled pass waits before reading what is pending.
  /// A media write stages its bytes before the record naming them is saved;
  /// this gap lets that record land so the pass sees it.
  final Duration settleDelay;

  Timer? _timer;
  bool _running = false;
  bool _rerunRequested = false;
  bool _disposed = false;
  Duration? _retryDelay;

  void schedule([Duration? delay]) {
    if (_disposed) return;
    if (_running) {
      _rerunRequested = true;
      return;
    }
    _timer?.cancel();
    _timer = Timer(delay ?? settleDelay, () {
      _timer = null;
      unawaited(_run());
    });
  }

  Future<void> _run() async {
    if (_disposed || _running) return;
    _running = true;
    var done = false;
    try {
      done = await _flush();
    } on Object {
      // A failed pass retries below; the staged bytes stay pending in the
      // records themselves, so nothing is lost by backing off.
      done = false;
    } finally {
      _running = false;
    }
    if (_disposed) return;
    if (done) {
      _retryDelay = null;
      if (_rerunRequested) {
        _rerunRequested = false;
        schedule();
      }
      return;
    }
    _rerunRequested = false;
    final delay = _retryDelay ?? initialRetryDelay;
    final doubled = delay * 2;
    _retryDelay = doubled > maximumRetryDelay ? maximumRetryDelay : doubled;
    schedule(delay);
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
