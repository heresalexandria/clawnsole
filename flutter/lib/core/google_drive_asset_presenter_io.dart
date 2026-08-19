import 'dart:io';
import 'dart:typed_data';

import 'asset_extensions.dart';
import 'google_drive_asset_presenter_base.dart';
import 'models.dart';

GoogleDriveAssetPresenter createPlatformGoogleDriveAssetPresenter() =>
    _IoGoogleDriveAssetPresenter();

class _IoGoogleDriveAssetPresenter implements GoogleDriveAssetPresenter {
  Directory? _directory;

  Future<Directory> _cache() async {
    final current = _directory;
    if (current != null) return current;
    // This code is also used by the standalone Dart companion, where Flutter
    // plugins such as path_provider are unavailable. A private, randomized
    // system-temporary directory works for both runtimes and avoids collisions
    // between concurrent Clawnsole processes.
    final next = await Directory.systemTemp.createTemp(
      'clawnsole-drive-cache-',
    );
    _directory = next;
    return next;
  }

  @override
  Future<Uri> present(AssetReference reference, Uint8List bytes) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{8,200}$').hasMatch(reference.value)) {
      throw StateError('The Google Drive asset id is invalid.');
    }
    final extension = retainedAssetExtension(
      reference.contentType,
      reference.label,
    );
    final file = File(
      '${(await _cache()).path}${Platform.pathSeparator}${reference.value}$extension',
    );
    if (!await file.exists() || await file.length() != bytes.length) {
      await file.writeAsBytes(bytes, flush: true);
    }
    return file.uri;
  }

  @override
  Future<void> clear() async {
    final directory = _directory;
    if (directory != null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
    _directory = null;
  }
}
