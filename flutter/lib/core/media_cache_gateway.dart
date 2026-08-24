import 'dart:typed_data';

import 'models.dart';

/// Cache-only access to retained media.
///
/// Implementations must never contact Google Drive while resolving this
/// method. It exists so the app can restore the first visible page from the
/// durable on-device cache before its initial frame.
abstract interface class MediaCacheGateway {
  Future<Uint8List?> cachedAssetBytes(AssetReference reference);
}
