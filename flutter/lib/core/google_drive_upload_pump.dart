import 'dart:async';

import 'asset_extensions.dart';
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

  /// Staged ids a pass found no bytes for on this device: another device's
  /// media in transit. Remembered across passes so the chip does not flip
  /// back to "Syncing…" between them.
  final Set<String> foreign = <String>{};

  /// Consecutive passes that failed to publish everything this device holds.
  int consecutiveFailures = 0;

  /// The Drive file a staged local id turned into, if this process
  /// published it.
  AssetReference? resolve(String stagedId) => resolved[stagedId];
}

/// A gateway that runs this device's Drive upload pump and can say what its
/// queue is doing. The studio installs the report so record helpers — and
/// through them the storage chip — describe this device's own work instead of
/// guessing from the record alone.
abstract interface class DriveUploadStatusSource {
  /// The latest report from this device's pass.
  DriveUploadQueueReport get driveUploadStatus;

  /// Called whenever [driveUploadStatus] changes.
  set onDriveUploadStatus(void Function()? listener);

  /// Runs one pass now, outside the pump's schedule. Answers true when
  /// nothing this device can publish remains pending.
  Future<bool> flushDriveUploads();
}

/// The wire form of a [DriveUploadQueueReport], for the one surface whose
/// pump runs in another process: the Electron renderer publishes nothing
/// itself, the companion beside it does, so the companion serves what its
/// pass reported and `WebGateway` reads it back.
///
/// Absence carries meaning that an empty queue does not. A companion that
/// sends no report at all has said nothing about who owes these uploads, and
/// the renderer must fall back to [DriveUploadQueueReport.unknown] instead of
/// reading silence as "everything is published" — hence [reported] on the
/// wire rather than inferring it from the payload's shape.
Map<String, Object?> driveUploadQueueReportToJson(
  DriveUploadQueueReport report,
) => <String, Object?>{
  'queued': report.queued.toList(),
  'foreign': report.foreign.toList(),
  if (report.stalledDetail != null) 'stalledDetail': report.stalledDetail,
  'reported': report.reported,
};

/// Reads a report served by the process that owns the pump.
DriveUploadQueueReport driveUploadQueueReportFromJson(
  Map<String, Object?> json,
) {
  Set<String> ids(Object? value) => <String>{
    for (final id in value is List<Object?> ? value : const <Object?>[])
      if (id is String && id.isNotEmpty) id,
  };
  final detail = json['stalledDetail']?.toString();
  return DriveUploadQueueReport(
    queued: ids(json['queued']),
    foreign: ids(json['foreign']),
    stalledDetail: detail != null && detail.isNotEmpty ? detail : null,
    reported: json['reported'] == true,
  );
}

/// Whether two reports describe the same queue. Reports arrive on every poll
/// of an unchanged library, and each one that is treated as news rebuilds the
/// studio for nothing.
bool sameDriveUploadQueueReport(
  DriveUploadQueueReport a,
  DriveUploadQueueReport b,
) =>
    a.reported == b.reported &&
    a.stalledDetail == b.stalledDetail &&
    a.queued.length == b.queued.length &&
    a.foreign.length == b.foreign.length &&
    a.queued.containsAll(b.queued) &&
    a.foreign.containsAll(b.foreign);

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
///
/// [onReport] receives what this device's queue is doing, once when the pass
/// starts and again when it settles. Nothing else can tell the difference
/// between a film this device is pushing and one it is merely waiting for, so
/// without it every surface has to describe both as "Syncing…".
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
  void Function(DriveUploadQueueReport report)? onReport,
}) async {
  assert(
    swap != null || (read != null && write != null),
    'Provide swap, or read and write.',
  );
  final memory = ledger ?? DriveUploadLedger();
  final pending = await (readPending ?? hybrid.readCached)();
  final queued = HybridDataStore.pendingDriveUploads(pending);
  memory.foreign.retainWhere(queued.containsKey);

  void report({String? stalledDetail}) {
    onReport?.call(
      DriveUploadQueueReport(
        queued: <String>{
          for (final id in queued.keys)
            if (!memory.foreign.contains(id)) id,
        },
        foreign: <String>{...memory.foreign},
        stalledDetail: stalledDetail,
        reported: true,
      ),
    );
  }

  if (queued.isEmpty) {
    report();
    return true;
  }
  if (!hybrid.isDriveConnected) {
    memory.consecutiveFailures += 1;
    report(stalledDetail: 'Google Drive is not connected on this device.');
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
  // Anything not already known to live elsewhere is this device's to push
  // while the pass runs, so a film staged a moment ago reads as syncing from
  // its first frame instead of waiting for the pass to finish.
  report();
  // Staged ids this process already published are replayed from the ledger
  // rather than uploaded again: a cross-device merge can re-introduce the
  // pre-swap reference, and by then the staged original has been adopted into
  // the Drive media cache, so a second upload would either duplicate the file
  // or report bytes that are no longer where the record says they are.
  final result = await hybrid.uploadQueuedDriveAssets(
    pending,
    published: <String, AssetReference>{
      ...memory.resolved,
      ...memory.published,
    },
    log: log,
  );
  memory.published.addAll(result.replacements);
  memory.resolved.addAll(result.replacements);
  memory.foreign.addAll(result.missing.keys);

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
    // Persisting an input reuses the file already on disk, so a Drive
    // generation can name the very asset a local-library record keeps.
    // Adopting is a rename: moving those bytes would empty that record.
    final adopted = await hybrid.adoptPublishedAssets(
      result,
      keepStaged: <String>{
        for (final asset in <AssetReference>[
          ...pending.generations
              .where((item) => item.storage != LibraryStorage.drive)
              .expand(generationAssetReferences),
          ...pending.savedReferences
              .where((item) => item.storage != LibraryStorage.drive)
              .expand(savedReferenceAssetReferences),
        ])
          if (asset.kind == 'local') asset.value,
      },
    );
    if (adopted > 0) {
      log?.call(
        'Drive upload pass: kept $adopted published file(s) in the local '
        'media cache.',
      );
    }
  } else if (result.failures > 0) {
    log?.call('Drive upload pass: ${result.failures} upload(s) failed.');
  }
  final settled = result.failures == 0 && restagedReplacements.isEmpty;
  if (result.failures > 0) {
    memory.consecutiveFailures += 1;
  } else {
    memory.consecutiveFailures = 0;
  }
  // Report on the library as this pass left it, so anything published here
  // stops describing itself as pending at all.
  final remaining = <String>{
    for (final id in queued.keys)
      if (!replacements.containsKey(id)) id,
  };
  memory.foreign.retainWhere(remaining.contains);
  onReport?.call(
    DriveUploadQueueReport(
      queued: remaining.difference(memory.foreign),
      foreign: <String>{...memory.foreign},
      stalledDetail: result.failures > 0
          ? 'Uploads from this device have failed '
                '${memory.consecutiveFailures} time(s) in a row.'
          : null,
      reported: true,
    ),
  );
  return settled;
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
  Future<bool>? _current;
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

  /// Schedules a pass only when none is already pending. Callers that merely
  /// notice staged media — every library read does — use this so they cannot
  /// reset the retry backoff of a pass that keeps failing into a tight loop.
  void ensureScheduled() {
    if (_disposed || _running || _timer != null) return;
    schedule();
  }

  /// Runs a pass now and answers its outcome, joining the pass already in
  /// flight when there is one. A manual refresh uses this so it reports what
  /// the pump actually did instead of racing it into a duplicate upload.
  Future<bool> flushNow() => _run();

  Future<bool> _run() {
    if (_disposed) return Future<bool>.value(false);
    return _current ??= _pass();
  }

  Future<bool> _pass() async {
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
      _current = null;
    }
    if (_disposed) return done;
    if (done) {
      _retryDelay = null;
      if (_rerunRequested) {
        _rerunRequested = false;
        schedule();
      }
      return done;
    }
    _rerunRequested = false;
    final delay = _retryDelay ?? initialRetryDelay;
    final doubled = delay * 2;
    _retryDelay = doubled > maximumRetryDelay ? maximumRetryDelay : doubled;
    schedule(delay);
    return done;
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
