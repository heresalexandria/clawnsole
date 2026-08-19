import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'models.dart';

String retainedAssetExtension(String? contentType, String label) {
  final normalized = contentType?.split(';').first.trim().toLowerCase();
  return switch (normalized) {
    'video/mp4' => '.mp4',
    'video/quicktime' => '.mov',
    'video/webm' => '.webm',
    'image/png' => '.png',
    'image/jpeg' => '.jpg',
    'image/webp' => '.webp',
    'image/gif' => '.gif',
    'audio/mpeg' => '.mp3',
    'audio/mp4' => '.m4a',
    'audio/wav' || 'audio/x-wav' => '.wav',
    'audio/ogg' => '.ogg',
    _ => switch (label.toLowerCase()) {
      final value when value.endsWith('.mp4') => '.mp4',
      final value when value.endsWith('.mov') => '.mov',
      final value when value.endsWith('.webm') => '.webm',
      final value when value.endsWith('.png') => '.png',
      final value when value.endsWith('.jpg') || value.endsWith('.jpeg') =>
        '.jpg',
      final value when value.endsWith('.webp') => '.webp',
      final value when value.endsWith('.gif') => '.gif',
      final value when value.endsWith('.mp3') => '.mp3',
      final value when value.endsWith('.m4a') => '.m4a',
      final value when value.endsWith('.wav') => '.wav',
      final value when value.endsWith('.ogg') => '.ogg',
      _ => '.asset',
    },
  };
}

class LocalDataStore {
  File? _cachedFile;

  Future<File> _file() async {
    if (_cachedFile != null) return _cachedFile!;
    final documents = await getApplicationDocumentsDirectory();
    _cachedFile = File(
      '${documents.path}${Platform.pathSeparator}Clawnsole${Platform.pathSeparator}clawnsole.json',
    );
    return _cachedFile!;
  }

  Future<Directory> _assets() async => Directory(
    '${(await _file()).parent.path}${Platform.pathSeparator}assets',
  );

  Future<bool> exists() async => (await _file()).exists();

  String _assetId() {
    final random = Random.secure();
    final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final suffix = List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '$timestamp-$suffix';
  }

  Future<File> _assetFile(String id, [String extension = '.asset']) async {
    if (!RegExp(r'^[a-f0-9-]{16,80}$').hasMatch(id)) {
      throw StateError('The local asset id is invalid.');
    }
    return File(
      '${(await _assets()).path}${Platform.pathSeparator}$id$extension',
    );
  }

  Future<File> _resolveAssetFile(
    AssetReference reference, {
    bool migrateGenericName = false,
  }) async {
    final extension = retainedAssetExtension(
      reference.contentType,
      reference.label,
    );
    final preferred = await _assetFile(reference.value, extension);
    if (await preferred.exists()) return preferred;
    final legacy = await _assetFile(reference.value);
    if (!await legacy.exists() || extension == '.asset') return legacy;
    if (!migrateGenericName) return legacy;
    return legacy.rename(preferred.path);
  }

  Future<AssetReference> writeAsset(
    Uint8List bytes, {
    required String label,
    required String contentType,
  }) async {
    final id = _assetId();
    final assets = await _assets();
    await assets.create(recursive: true);
    final extension = retainedAssetExtension(contentType, label);
    await (await _assetFile(id, extension)).writeAsBytes(bytes, flush: true);
    return AssetReference(
      kind: 'local',
      value: id,
      label: label,
      contentType: contentType,
      bytes: bytes.length,
    );
  }

  Future<AssetReference?> persistSource(
    String source, {
    required String label,
    AssetReference? retained,
  }) async {
    if (retained?.isLocal == true) {
      final file = await _resolveAssetFile(retained!);
      if (await file.exists()) {
        return AssetReference(
          kind: 'local',
          value: retained.value,
          label: label,
          contentType: retained.contentType,
          bytes: await file.length(),
        );
      }
    }
    if (source.startsWith('data:')) {
      final comma = source.indexOf(',');
      if (comma < 0) throw StateError('A selected local asset is malformed.');
      final metadata = source.substring(5, comma).split(';');
      final contentType = metadata.firstOrNull?.isNotEmpty == true
          ? metadata.first
          : 'application/octet-stream';
      final encoded = source.substring(comma + 1);
      final bytes = metadata.contains('base64')
          ? base64Decode(encoded)
          : Uint8List.fromList(utf8.encode(Uri.decodeComponent(encoded)));
      return writeAsset(bytes, label: label, contentType: contentType);
    }
    final remote = Uri.tryParse(source);
    if (remote?.scheme == 'https') {
      return AssetReference(kind: 'remote', value: source, label: label);
    }
    return null;
  }

  Future<Uint8List> readAsset(AssetReference reference) async {
    if (!reference.isLocal) {
      throw StateError('The asset is not stored locally.');
    }
    return (await _resolveAssetFile(reference)).readAsBytes();
  }

  Future<Uri> assetUri(AssetReference reference) async {
    if (!reference.isLocal) return Uri.parse(reference.value);
    return (await _resolveAssetFile(reference, migrateGenericName: true)).uri;
  }

  Set<String> _referencedAssets(
    List<Generation> generations,
    List<SavedReference> savedReferences,
  ) {
    final retained = <String>{};
    void add(AssetReference? reference) {
      if (reference?.isLocal == true) retained.add(reference!.value);
    }

    for (final generation in generations) {
      add(generation.resultAsset);
      add(generation.config.source);
      for (final frame
          in generation.config.keyframes ?? const <KeyframeLabel>[]) {
        add(frame.source);
      }
      for (final media
          in generation.config.references ?? const <MediaReferenceLabel>[]) {
        add(media.source);
      }
    }
    for (final reference in savedReferences) {
      add(reference.asset);
    }
    return retained;
  }

  Future<void> pruneAssets(
    List<Generation> generations, [
    List<SavedReference> savedReferences = const <SavedReference>[],
  ]) async {
    final assets = await _assets();
    if (!await assets.exists()) return;
    final retained = _referencedAssets(generations, savedReferences);
    await for (final entry in assets.list()) {
      if (entry is! File) continue;
      final name = entry.uri.pathSegments.last;
      final dot = name.lastIndexOf('.');
      final id = dot > 0 ? name.substring(0, dot) : '';
      if (!retained.contains(id)) await entry.delete();
    }
  }

  Future<void> clearAssets() async {
    final assets = await _assets();
    if (await assets.exists()) await assets.delete(recursive: true);
  }

  Future<StoredData> read() async {
    final file = await _file();
    if (!await file.exists()) return const StoredData();
    try {
      return StoredData.decode(await file.readAsString());
    } on FormatException {
      throw StateError(
        'Clawnsole could not read ${file.path}. The JSON file is malformed.',
      );
    }
  }

  Future<void> write(StoredData data) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final temporary = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await temporary.writeAsString(data.encode(), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  Future<void> delete() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
    await clearAssets();
  }

  Future<StorageStats> stats(int records) async {
    final file = await _file();
    final assets = await _assets();
    var assetBytes = 0;
    var assetCount = 0;
    if (await assets.exists()) {
      await for (final entry in assets.list()) {
        if (entry is! File) continue;
        assetBytes += await entry.length();
        assetCount += 1;
      }
    }
    if (!await file.exists()) {
      return StorageStats(
        path: file.path,
        bytes: 0,
        records: records,
        assetBytes: assetBytes,
        assets: assetCount,
      );
    }
    final current = await file.stat();
    return StorageStats(
      path: file.path,
      bytes: current.size,
      records: records,
      assetBytes: assetBytes,
      assets: assetCount,
      lastUpdated: current.modified,
    );
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
