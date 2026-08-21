import 'dart:convert';
import 'dart:typed_data';

import 'google_drive_asset_presenter_base.dart';
import 'models.dart';

GoogleDriveAssetPresenter createPlatformGoogleDriveAssetPresenter() =>
    _MemoryGoogleDriveAssetPresenter();

class _MemoryGoogleDriveAssetPresenter implements GoogleDriveAssetPresenter {
  @override
  Future<Uri?> lookup(AssetReference reference) async => null;

  @override
  Future<Uri> present(
    AssetReference reference,
    Stream<List<int>> bytes, {
    int? expectedLength,
  }) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in bytes) {
      builder.add(chunk);
    }
    return Uri.parse(
      'data:${reference.contentType ?? 'application/octet-stream'};'
      'base64,${base64Encode(builder.takeBytes())}',
    );
  }

  @override
  Future<void> clear() async {}
}
