import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'asset_extensions.dart';
import 'durable_data_store.dart';
import 'models.dart';

class LocalDataStore implements DurableDataStore {
  LocalDataStore({Directory? documentsDirectory})
    : _documentsOverride = documentsDirectory;

  /// Name of the pointer file that always stays in the default data root and
  /// records a user-chosen data directory for portable installs.
  static const String locationFileName = 'data-location.json';
  static const String dataFileName = 'clawnsole.json';

  final Directory? _documentsOverride;
  File? _cachedFile;

  Future<Directory> _defaultRoot() async {
    final documents =
        _documentsOverride ?? await getApplicationDocumentsDirectory();
    return Directory('${documents.path}${Platform.pathSeparator}Clawnsole');
  }

  /// Resolves the active data directory: the pointer file's target when it
  /// names an existing directory, otherwise the default root. A missing or
  /// unreadable pointer must never block startup.
  Future<String> _resolveDataDirectory(Directory root) async {
    final pointer = File(
      '${root.path}${Platform.pathSeparator}$locationFileName',
    );
    try {
      if (await pointer.exists()) {
        final decoded = jsonDecode(await pointer.readAsString());
        final value = decoded is Map<Object?, Object?>
            ? decoded['dataDirectory']
            : null;
        if (value is String &&
            value.trim().isNotEmpty &&
            await Directory(value.trim()).exists()) {
          return Directory(value.trim()).absolute.path;
        }
      }
    } on Object {
      // Fall through to the default location below.
    }
    return root.path;
  }

  Future<File> _file() async {
    if (_cachedFile != null) return _cachedFile!;
    final root = await _defaultRoot();
    _cachedFile = File(
      '${await _resolveDataDirectory(root)}${Platform.pathSeparator}$dataFileName',
    );
    return _cachedFile!;
  }

  Future<Directory> _assets() async => Directory(
    '${(await _file()).parent.path}${Platform.pathSeparator}assets',
  );

  Future<bool> exists() async => (await _file()).exists();

  /// The directory currently holding the data file and its assets.
  Future<String> dataDirectoryPath() async => (await _file()).parent.path;

  /// Whether [directory] already holds a Clawnsole data file.
  Future<bool> hasLibraryAt(String directory) => File(
    '${Directory(directory).absolute.path}${Platform.pathSeparator}$dataFileName',
  ).exists();

  /// Moves the library to [directory] for portable installs: copies the data
  /// file and assets there (or, with [useExistingLibrary], adopts a library
  /// already present), records the choice in the default root's pointer
  /// file, and serves all further reads and writes from the new location.
  /// The files at the previous location are intentionally kept.
  Future<void> relocate(
    String directory, {
    bool useExistingLibrary = false,
  }) async {
    final separator = Platform.pathSeparator;
    if (directory.trim().isEmpty) {
      throw StateError('Choose a folder for Clawnsole data.');
    }
    final current = await _file();
    final assets = await _assets();
    final targetPath = Directory(directory.trim()).absolute.path;
    String contained(String path) =>
        path.endsWith(separator) ? path : '$path$separator';
    if (targetPath == current.parent.absolute.path) {
      throw StateError('Clawnsole already stores its data in that folder.');
    }
    if (contained(targetPath).startsWith(contained(assets.absolute.path))) {
      throw StateError('Choose a folder outside the current assets folder.');
    }
    try {
      await Directory(targetPath).create(recursive: true);
      final probe = File(
        '$targetPath$separator.clawnsole-write-probe.${DateTime.now().microsecondsSinceEpoch}.tmp',
      );
      await probe.writeAsString('clawnsole', flush: true);
      await probe.delete();
    } on FileSystemException catch (error) {
      throw StateError(
        'Clawnsole cannot write to $targetPath. '
        '${error.osError?.message ?? error.message}',
      );
    }
    final targetFile = File('$targetPath$separator$dataFileName');
    final adopt = useExistingLibrary && await targetFile.exists();
    if (!adopt) {
      if (await targetFile.exists()) {
        throw StateError('That folder already contains a Clawnsole library.');
      }
      if (await current.exists()) await current.copy(targetFile.path);
      if (await assets.exists()) {
        final targetAssets = Directory('$targetPath${separator}assets');
        await targetAssets.create(recursive: true);
        await for (final entry in assets.list()) {
          if (entry is! File) continue;
          await entry.copy(
            '${targetAssets.path}$separator${entry.uri.pathSegments.last}',
          );
        }
      }
    }
    final root = await _defaultRoot();
    await root.create(recursive: true);
    final pointer = File('${root.path}$separator$locationFileName');
    final temporary = File(
      '${pointer.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await temporary.writeAsString(
      jsonEncode(<String, String>{'dataDirectory': targetPath}),
      flush: true,
    );
    if (await pointer.exists()) await pointer.delete();
    await temporary.rename(pointer.path);
    _cachedFile = targetFile;
  }

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

  @override
  Future<AssetReference> writeAsset(
    Uint8List bytes, {
    required String label,
    required String contentType,
    LibraryStorage storage = LibraryStorage.local,
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

  @override
  Future<AssetReference?> persistSource(
    String source, {
    required String label,
    AssetReference? retained,
    LibraryStorage storage = LibraryStorage.local,
  }) async {
    if (retained?.kind == 'local') {
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

  @override
  Future<Uint8List> readAsset(AssetReference reference) async {
    if (reference.kind != 'local') {
      throw StateError('The asset is not stored locally.');
    }
    return (await _resolveAssetFile(reference)).readAsBytes();
  }

  @override
  Future<Uri> assetUri(AssetReference reference) async {
    if (reference.kind != 'local') return Uri.parse(reference.value);
    return (await _resolveAssetFile(reference, migrateGenericName: true)).uri;
  }

  Set<String> _referencedAssets(
    List<Generation> generations,
    List<SavedReference> savedReferences,
  ) {
    final retained = <String>{};
    void add(AssetReference? reference) {
      if (reference?.kind == 'local') retained.add(reference!.value);
    }

    for (final generation in generations) {
      add(generation.resultAsset);
      add(generation.thumbnailAsset);
      add(generation.timelineThumbnailAsset);
      add(generation.config.source);
      add(generation.config.sourceThumbnailAsset);
      for (final frame
          in generation.config.keyframes ?? const <KeyframeLabel>[]) {
        add(frame.source);
      }
      for (final media
          in generation.config.references ?? const <MediaReferenceLabel>[]) {
        add(media.source);
        add(media.thumbnailAsset);
      }
    }
    for (final reference in savedReferences) {
      add(reference.asset);
      add(reference.thumbnailAsset);
    }
    return retained;
  }

  @override
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

  @override
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

  @override
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

  @override
  Future<void> delete() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
    await clearAssets();
  }

  @override
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
