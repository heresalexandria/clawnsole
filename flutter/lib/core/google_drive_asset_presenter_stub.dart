import 'dart:convert';
import 'dart:typed_data';

import 'google_drive_asset_presenter_base.dart';
import 'models.dart';

GoogleDriveAssetPresenter createPlatformGoogleDriveAssetPresenter() =>
    _MemoryGoogleDriveAssetPresenter();

class _MemoryGoogleDriveAssetPresenter implements GoogleDriveAssetPresenter {
  @override
  Future<Uri> present(
    AssetReference reference,
    Uint8List bytes,
  ) async => Uri.parse(
    'data:${reference.contentType ?? 'application/octet-stream'};base64,${base64Encode(bytes)}',
  );

  @override
  Future<void> clear() async {}
}
