import 'dart:typed_data';

import 'models.dart';

abstract interface class GoogleDriveAssetPresenter {
  /// Returns bytes for an asset that is already materialized on this surface,
  /// or null when reading it would require a download.
  Future<Uint8List?> read(AssetReference reference);

  /// Returns a playable URI for an asset that is already materialized on this
  /// surface, or null when presenting it would require a download.
  Future<Uri?> lookup(AssetReference reference);

  /// Materializes [bytes] for playback and returns the resulting URI. The
  /// stream is consumed exactly once; [expectedLength] enables determinate
  /// progress reporting where the surface supports it.
  Future<Uri> present(
    AssetReference reference,
    Stream<List<int>> bytes, {
    int? expectedLength,
  });

  /// Makes an already-complete local file the materialized copy of
  /// [reference] without passing its bytes through memory, and returns the
  /// resulting URI. Returns null, leaving [localFile] untouched, on surfaces
  /// that cannot adopt files (the browser) or have no durable cache for them.
  Future<Uri?> adopt(AssetReference reference, Uri localFile);

  Future<void> clear();
}
