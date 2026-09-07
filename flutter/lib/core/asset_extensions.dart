import 'models.dart';

/// A human-readable notice for a retained asset whose file is gone from disk.
/// Raw paths and exception details belong in logs, not in this message.
String missingLocalAssetMessage(String? contentType) {
  final normalized = contentType?.split(';').first.trim().toLowerCase() ?? '';
  final noun = normalized.startsWith('video/')
      ? 'video'
      : normalized.startsWith('image/')
      ? 'image'
      : normalized.startsWith('audio/')
      ? 'audio'
      : 'media';
  return "The saved $noun file is missing from this device's library storage. "
      'Check the library storage settings and your Google Drive connection.';
}

String retainedAssetExtension(String? contentType, String label) {
  final normalized = contentType?.split(';').first.trim().toLowerCase();
  return switch (normalized) {
    'video/mp4' => '.mp4',
    'video/quicktime' => '.mov',
    'video/webm' => '.webm',
    'image/png' => '.png',
    'image/jpeg' => '.jpg',
    'image/webp' => '.webp',
    'image/gif' => '.gif',
    'audio/mpeg' => '.mp3',
    'audio/mp4' => '.m4a',
    'audio/wav' || 'audio/x-wav' => '.wav',
    'audio/ogg' => '.ogg',
    _ => switch (label.toLowerCase()) {
      final value when value.endsWith('.mp4') => '.mp4',
      final value when value.endsWith('.mov') => '.mov',
      final value when value.endsWith('.webm') => '.webm',
      final value when value.endsWith('.png') => '.png',
      final value when value.endsWith('.jpg') || value.endsWith('.jpeg') =>
        '.jpg',
      final value when value.endsWith('.webp') => '.webp',
      final value when value.endsWith('.gif') => '.gif',
      final value when value.endsWith('.mp3') => '.mp3',
      final value when value.endsWith('.m4a') => '.m4a',
      final value when value.endsWith('.wav') => '.wav',
      final value when value.endsWith('.ogg') => '.ogg',
      _ => '.asset',
    },
  };
}

bool isRetainedVideoAsset(String? contentType, String label) => const <String>{
  '.mp4',
  '.mov',
  '.webm',
}.contains(retainedAssetExtension(contentType, label));

/// Every retained-media slot on [generation]: the result and preview assets
/// plus each config input (source video, keyframes, references, thumbnails).
Iterable<AssetReference> generationAssetReferences(
  Generation generation,
) sync* {
  final config = generation.config;
  for (final reference in <AssetReference?>[
    generation.resultAsset,
    generation.thumbnailAsset,
    generation.timelineThumbnailAsset,
    config.source,
    config.sourceThumbnailAsset,
    ...?config.keyframes?.map((frame) => frame.source),
    ...?config.references?.expand(
      (media) => <AssetReference?>[media.source, media.thumbnailAsset],
    ),
  ]) {
    if (reference != null) yield reference;
  }
}

/// The retained-media slots on [reference]: its media and optional preview.
Iterable<AssetReference> savedReferenceAssetReferences(
  SavedReference reference,
) sync* {
  yield reference.asset;
  final thumbnail = reference.thumbnailAsset;
  if (thumbnail != null) yield thumbnail;
}

/// Local-kind media still referenced by Drive-tagged records: bytes staged by
/// a deferred Drive write that a background upload pass has not published
/// yet. May yield the same asset id more than once.
Iterable<AssetReference> pendingDriveUploadAssets(
  Iterable<Generation> generations,
  Iterable<SavedReference> references,
) sync* {
  bool staged(AssetReference reference) =>
      reference.kind == 'local' && reference.value.isNotEmpty;
  for (final generation in generations) {
    if (generation.storage != LibraryStorage.drive) continue;
    yield* generationAssetReferences(generation).where(staged);
  }
  for (final reference in references) {
    if (reference.storage != LibraryStorage.drive) continue;
    yield* savedReferenceAssetReferences(reference).where(staged);
  }
}

/// What a Drive-tagged record's staged media is waiting for, as seen from the
/// device drawing its chip.
///
/// A `local`-kind asset on a Drive record names a file on exactly one device.
/// That device is syncing; every other device is only waiting, and saying
/// "Syncing…" there is a claim about work no local pump will ever do.
///
/// Declaration order is precedence: a record is described by the least
/// finished of its assets, so one file this device is actively pushing never
/// speaks for another that this device cannot publish at all.
enum DriveUploadState {
  /// Nothing is staged: every retained asset is published, or the record
  /// lives in the local library.
  published,

  /// This device holds the staged bytes and its upload pass has them queued
  /// or in flight.
  uploading,

  /// This device holds the bytes but its pass cannot get them out: Drive is
  /// disconnected, or the upload keeps failing.
  stalled,

  /// Staged, with nothing yet known about which device owes the upload —
  /// before this device's first pass, or on a surface with no local pump.
  awaitingUpload,

  /// The staged bytes are on another device. This one can never publish
  /// them, so it is waiting, not syncing.
  awaitingOtherDevice,
}

/// What this device's Drive upload pass last reported about its own queue.
///
/// [queued] and [foreign] are staged asset ids: the first are files this
/// device holds bytes for and will publish, the second are files whose bytes
/// are not here, which only their origin device can publish.
class DriveUploadQueueReport {
  const DriveUploadQueueReport({
    this.queued = const <String>{},
    this.foreign = const <String>{},
    this.stalledDetail,
    this.reported = false,
  });

  /// The state before any pass has run in this process.
  static const DriveUploadQueueReport unknown = DriveUploadQueueReport();

  final Set<String> queued;
  final Set<String> foreign;

  /// Why this device's pass cannot publish [queued] right now, if it cannot.
  final String? stalledDetail;

  /// Whether a pass actually produced this report. An unreported queue means
  /// "this surface has no pump to ask", not "nothing is pending".
  final bool reported;

  bool get isStalled => stalledDetail != null;

  DriveUploadState stateOf(String stagedId) {
    if (queued.contains(stagedId)) {
      return isStalled ? DriveUploadState.stalled : DriveUploadState.uploading;
    }
    if (foreign.contains(stagedId)) return DriveUploadState.awaitingOtherDevice;
    return DriveUploadState.awaitingUpload;
  }
}

DriveUploadQueueReport _driveUploadQueue = DriveUploadQueueReport.unknown;

/// The active report, consulted by the chip helpers below.
DriveUploadQueueReport get driveUploadQueue => _driveUploadQueue;

/// Publishes what this device's upload pass knows, the way the provider
/// catalog is installed: the studio owns the pump and the surfaces read the
/// result through the record helpers rather than reaching for the gateway.
void installDriveUploadQueue(DriveUploadQueueReport report) {
  _driveUploadQueue = report;
}

/// Forgets the installed report. Tests and a gateway teardown use this so one
/// device's queue cannot describe the next one's.
void resetDriveUploadQueue() {
  _driveUploadQueue = DriveUploadQueueReport.unknown;
}

/// The state of the staged media in [assets], worst case first: a record is
/// only as published as its least-published asset, and one file this device
/// is actively pushing does not make another device's file "syncing".
DriveUploadState driveUploadStateOf(Iterable<AssetReference> assets) {
  final report = driveUploadQueue;
  var state = DriveUploadState.published;
  for (final asset in assets) {
    if (asset.kind != 'local') continue;
    final next = report.stateOf(asset.value);
    if (next.index > state.index) state = next;
  }
  return state;
}

/// True only while this device is actually publishing this Drive-tagged
/// reference's media. A reference staged on another device reads as an
/// ordinary Drive reference here rather than claiming a sync that this
/// device is not running.
bool savedReferencePendingDriveUpload(SavedReference reference) =>
    reference.storage == LibraryStorage.drive &&
    driveUploadStateOf(savedReferenceAssetReferences(reference)) ==
        DriveUploadState.uploading;

/// What this Drive-tagged generation's staged media is waiting for.
///
/// The name is the one every surface already passes to `StorageBadge`; the
/// answer is no longer a bare "something is staged", because that was true
/// forever on a device that can never publish the bytes.
DriveUploadState generationPendingDriveUpload(Generation generation) =>
    generation.storage == LibraryStorage.drive
    ? driveUploadStateOf(generationAssetReferences(generation))
    : DriveUploadState.published;

/// Rewrites every retained-media slot on [generation] through [transform].
Generation mapGenerationAssets(
  Generation generation,
  AssetReference Function(AssetReference reference) transform,
) {
  AssetReference? replace(AssetReference? reference) =>
      reference == null ? null : transform(reference);
  final config = generation.config;
  return generation.copyWith(
    config: config.copyWith(
      keyframes: config.keyframes
          ?.map(
            (frame) => KeyframeLabel(
              label: frame.label,
              role: frame.role,
              seconds: frame.seconds,
              referenceId: frame.referenceId,
              source: replace(frame.source),
            ),
          )
          .toList(),
      references: config.references
          ?.map(
            (media) => MediaReferenceLabel(
              label: media.label,
              kind: media.kind,
              promptName: media.promptName,
              referenceId: media.referenceId,
              source: replace(media.source),
              thumbnailAsset: replace(media.thumbnailAsset),
              durationSeconds: media.durationSeconds,
            ),
          )
          .toList(),
      source: replace(config.source),
      sourceThumbnailAsset: replace(config.sourceThumbnailAsset),
    ),
    resultAsset: replace(generation.resultAsset),
    thumbnailAsset: replace(generation.thumbnailAsset),
    timelineThumbnailAsset: replace(generation.timelineThumbnailAsset),
  );
}

/// Rewrites the retained-media slots on [reference] through [transform].
SavedReference mapSavedReferenceAssets(
  SavedReference reference,
  AssetReference Function(AssetReference reference) transform,
) => reference.copyWith(
  asset: transform(reference.asset),
  thumbnailAsset: reference.thumbnailAsset == null
      ? null
      : transform(reference.thumbnailAsset!),
);
