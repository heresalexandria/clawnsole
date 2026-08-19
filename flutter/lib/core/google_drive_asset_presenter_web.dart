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
  Future<Uri> present(AssetReference reference, Uint8List bytes) async {
    final cached = _urls[reference.value];
    if (cached != null) return Uri.parse(cached);
    final blob = web.Blob(
      <web.BlobPart>[bytes.toJS].toJS,
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
