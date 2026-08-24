import 'models.dart';

/// Progress fraction updates for one retained-asset delivery. A null fraction
/// means bytes are moving but the total is unknown (indeterminate).
typedef VideoDeliveryProgressListener = void Function(double? fraction);

/// Surfaces that keep a bounded local cache of Drive previews and videos.
///
/// The cap itself is an [AppPreferences.localVideoCacheMb] preference and
/// reaches each surface through the normal preference path; this interface
/// only covers inspection, prefetch, and progress observation.
abstract interface class VideoCacheGateway {
  /// Total bytes currently held by the local media cache, or 0 when the
  /// surface cannot measure it.
  Future<int> videoCacheUsedBytes();

  /// Deletes every cached media file.
  Future<void> clearVideoCache();

  /// Resolves a playable URI for [reference] only when it is already cached
  /// or otherwise cheap to produce (no full download). Returns null when
  /// producing a URI would require downloading the asset.
  Future<Uri?> cachedVideoAssetUri(AssetReference reference);

  /// Downloads [reference] into the cache in the background so a later play
  /// starts instantly. A no-op when caching is off or unsupported.
  Future<void> prefetchVideoAsset(AssetReference reference);

  /// Observes download progress for the asset with [assetId]. Surfaces
  /// without byte visibility may never call the listener.
  void addVideoProgressListener(
    String assetId,
    VideoDeliveryProgressListener listener,
  );

  void removeVideoProgressListener(
    String assetId,
    VideoDeliveryProgressListener listener,
  );
}
