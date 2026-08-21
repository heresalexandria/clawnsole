import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'google_drive_asset_presenter_base.dart';
import 'models.dart';

GoogleDriveAssetPresenter createPlatformGoogleDriveAssetPresenter() =>
    _WebGoogleDriveAssetPresenter();

class _WebGoogleDriveAssetPresenter implements GoogleDriveAssetPresenter {
  final Map<String, String> _urls = <String, String>{};

  @override
  Future<Uri?> lookup(AssetReference reference) async {
    final cached = _urls[reference.value];
    return cached == null ? null : Uri.parse(cached);
  }

  @override
  Future<Uri> present(
    AssetReference reference,
    Stream<List<int>> bytes, {
    int? expectedLength,
  }) async {
    final cached = _urls[reference.value];
    if (cached != null) return Uri.parse(cached);
    final builder = BytesBuilder(copy: false);
    await for (final chunk in bytes) {
      builder.add(chunk);
    }
    final blob = web.Blob(
      <web.BlobPart>[builder.takeBytes().toJS].toJS,
      web.BlobPropertyBag(
        type: reference.contentType ?? 'application/octet-stream',
      ),
    );
    final url = web.URL.createObjectURL(blob);
    _urls[reference.value] = url;
    return Uri.parse(url);
  }

  @override
  Future<void> clear() async {
    for (final url in _urls.values) {
      web.URL.revokeObjectURL(url);
    }
    _urls.clear();
  }
}
