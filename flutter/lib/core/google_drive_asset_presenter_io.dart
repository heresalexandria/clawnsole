import 'dart:io';
import 'dart:typed_data';

import 'asset_extensions.dart';
import 'google_drive_asset_presenter_base.dart';
import 'models.dart';
import 'video_cache.dart';

GoogleDriveAssetPresenter createPlatformGoogleDriveAssetPresenter() =>
    IoGoogleDriveAssetPresenter();

/// Presents Google Drive assets as local files.
///
/// With a [VideoCache] the files land in a durable, size-capped cache
/// directory so a later lookup skips the network entirely. Without one (or
/// with the cache disabled) files fall back to a private process-temporary
/// directory, matching the pre-cache behavior.
///
/// This class is also used by the standalone Dart companion, where Flutter
/// plugins such as path_provider are unavailable, so the durable directory
/// always arrives from the caller through the [VideoCache].
class IoGoogleDriveAssetPresenter implements GoogleDriveAssetPresenter {
  IoGoogleDriveAssetPresenter({VideoCache? cache}) : _cache = cache;

  final VideoCache? _cache;
  Directory? _temporary;

  Future<Directory> _temporaryDirectory() async {
    final current = _temporary;
    if (current != null) return current;
    return _temporary = await Directory.systemTemp.createTemp(
      'clawnsole-drive-cache-',
    );
  }

  void _requireValidId(AssetReference reference) {
    if (!RegExp(r'^[A-Za-z0-9_-]{8,200}$').hasMatch(reference.value)) {
      throw StateError('The Google Drive asset id is invalid.');
    }
  }

  String _extension(AssetReference reference) =>
      retainedAssetExtension(reference.contentType, reference.label);

  Future<File?> _lookupFile(AssetReference reference) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{8,200}$').hasMatch(reference.value)) {
      return null;
    }
    final cache = _cache;
    if (cache != null && cache.enabled) {
      final cached = await cache.lookup(reference.value);
      if (cached != null) return cached;
    }
    final temporary = _temporary;
    if (temporary != null) {
      final file = File(
        '${temporary.path}${Platform.pathSeparator}'
        '${reference.value}${_extension(reference)}',
      );
      if (await file.exists()) return file;
    }
    return null;
  }

  @override
  Future<Uint8List?> read(AssetReference reference) async {
    try {
      return await (await _lookupFile(reference))?.readAsBytes();
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<Uri?> lookup(AssetReference reference) async =>
      (await _lookupFile(reference))?.uri;

  @override
  Future<Uri> present(
    AssetReference reference,
    Stream<List<int>> bytes, {
    int? expectedLength,
  }) async {
    _requireValidId(reference);
    final cache = _cache;
    if (cache != null && cache.enabled) {
      final file = await cache.put(
        reference.value,
        _extension(reference),
        bytes,
        expectedLength: expectedLength,
      );
      return file.uri;
    }
    final file = File(
      '${(await _temporaryDirectory()).path}${Platform.pathSeparator}'
      '${reference.value}${_extension(reference)}',
    );
    final sink = file.openWrite();
    try {
      await sink.addStream(bytes);
      await sink.flush();
    } finally {
      await sink.close();
    }
    return file.uri;
  }

  @override
  Future<void> clear() async {
    await _cache?.clear();
    final temporary = _temporary;
    if (temporary != null && await temporary.exists()) {
      await temporary.delete(recursive: true);
    }
    _temporary = null;
  }
}
