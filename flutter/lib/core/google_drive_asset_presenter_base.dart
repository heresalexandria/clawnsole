import 'dart:typed_data';

import 'models.dart';

abstract interface class GoogleDriveAssetPresenter {
  Future<Uri> present(AssetReference reference, Uint8List bytes);
  Future<void> clear();
}
