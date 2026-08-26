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
