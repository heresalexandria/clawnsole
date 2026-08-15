import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'models.dart';

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
  }

  Future<StorageStats> stats(int records) async {
    final file = await _file();
    if (!await file.exists()) {
      return StorageStats(path: file.path, bytes: 0, records: records);
    }
    final current = await file.stat();
    return StorageStats(
      path: file.path,
      bytes: current.size,
      records: records,
      lastUpdated: current.modified,
    );
  }
}
