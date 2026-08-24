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

  Future<void> clear();
}
