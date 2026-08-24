import 'dart:async';
import 'dart:io';

/// Reports byte progress for one cached download. [total] is null when the
/// source did not announce a length.
typedef VideoCacheProgressListener =
    void Function(int received, int? total, bool done);

/// A bounded least-recently-used disk cache for Drive previews and videos.
///
/// Files are stored as `<key><extension>` inside a caller-supplied directory.
/// The recency index is the filesystem itself: a lookup touches the file's
/// modification time, and the eviction sweep removes the stalest files until
/// the total size fits [maxBytes]. Nothing about the cache is ever written to
/// history JSON.
///
/// This class is shared by the Flutter app and the standalone Dart companion,
/// so it must stay free of Flutter imports.
class VideoCache {
  VideoCache({
    required Future<Directory> Function() directory,
    int maxBytes = defaultVideoCacheBytes,
  }) : _directoryProvider = directory,
       _maxBytes = maxBytes;

  static const int defaultVideoCacheBytes = 100 * 1024 * 1024;

  final Future<Directory> Function() _directoryProvider;
  final Map<String, Future<File>> _inFlight = <String, Future<File>>{};
  final Map<String, List<VideoCacheProgressListener>> _listeners =
      <String, List<VideoCacheProgressListener>>{};
  Future<void> _maintenance = Future<void>.value();
  Directory? _directory;
  int _maxBytes;

  int get maxBytes => _maxBytes;
  bool get enabled => _maxBytes > 0;

  /// Applies a new size cap. Shrinking sweeps immediately and a cap of zero
  /// (or less) disables the cache and deletes every cached file. An unchanged
  /// cap is a no-op so routine preference writes never touch the disk.
  Future<void> setMaxBytes(int value) async {
    if (value == _maxBytes) return;
    _maxBytes = value;
    if (value <= 0) return clear();
    await _sweep(const <String>{});
  }

  static bool isValidKey(String key) =>
      RegExp(r'^[A-Za-z0-9_-]{1,200}$').hasMatch(key);

  /// Returns the cached file for [key] and marks it recently used, or null.
  Future<File?> lookup(String key) async {
    if (!isValidKey(key)) return null;
    final pending = _inFlight[key];
    if (pending != null) {
      try {
        return await pending;
      } on Object {
        return null;
      }
    }
    final file = await _find(key);
    if (file == null) return null;
    try {
      await file.setLastModified(DateTime.now());
    } on FileSystemException {
      // A read-only volume still serves cached bytes; recency is best-effort.
    }
    return file;
  }

  /// Streams [bytes] into the cache under [key] and returns the stored file.
  ///
  /// Concurrent puts for the same key share one download. Progress listeners
  /// registered for [key] observe received bytes against [expectedLength].
  /// After a successful write the cache is swept back under [maxBytes]; the
  /// file written last is never evicted by its own sweep.
  Future<File> put(
    String key,
    String extension,
    Stream<List<int>> bytes, {
    int? expectedLength,
  }) {
    if (!isValidKey(key)) {
      throw ArgumentError.value(key, 'key', 'is not a valid cache key');
    }
    final pending = _inFlight[key];
    if (pending != null) return pending;
    late final Future<File> operation;
    operation = _write(key, extension, bytes, expectedLength).whenComplete(() {
      if (identical(_inFlight[key], operation)) _inFlight.remove(key);
    });
    _inFlight[key] = operation;
    return operation;
  }

  bool isDownloading(String key) => _inFlight.containsKey(key);

  void addProgressListener(String key, VideoCacheProgressListener listener) {
    _listeners
        .putIfAbsent(key, () => <VideoCacheProgressListener>[])
        .add(listener);
  }

  void removeProgressListener(String key, VideoCacheProgressListener listener) {
    final listeners = _listeners[key];
    listeners?.remove(listener);
    if (listeners != null && listeners.isEmpty) _listeners.remove(key);
  }

  /// Total size of every completed cache file in bytes.
  Future<int> usedBytes() async {
    var total = 0;
    for (final file in await _files()) {
      total += await _sizeOf(file);
    }
    return total;
  }

  /// Deletes every cached file. In-flight downloads finish into an empty
  /// cache and are swept by their own completion pass.
  Future<void> clear() {
    final operation = _maintenance.then((_) async {
      for (final file in await _files()) {
        await _delete(file);
      }
    });
    _maintenance = operation.then<void>((_) {}, onError: (_) {});
    return operation;
  }

  Future<Directory> _cacheDirectory() async {
    final current = _directory;
    if (current != null) return current;
    final directory = await _directoryProvider();
    await directory.create(recursive: true);
    return _directory = directory;
  }

  Future<List<File>> _files() async {
    final Directory directory;
    try {
      directory = await _cacheDirectory();
    } on Object {
      // Maintenance is best-effort: an unavailable cache directory (for
      // example in a headless test) simply means there is nothing cached.
      return const <File>[];
    }
    if (!await directory.exists()) return const <File>[];
    final files = <File>[];
    await for (final entry in directory.list()) {
      if (entry is File && !entry.path.endsWith(partialSuffix)) {
        files.add(entry);
      }
    }
    return files;
  }

  Future<File?> _find(String key) async {
    for (final file in await _files()) {
      if (_stemOf(file) == key) return file;
    }
    return null;
  }

  static const String partialSuffix = '.partial';

  Future<File> _write(
    String key,
    String extension,
    Stream<List<int>> bytes,
    int? expectedLength,
  ) async {
    final directory = await _cacheDirectory();
    final separator = Platform.pathSeparator;
    final file = File('${directory.path}$separator$key$extension');
    final partial = File('${file.path}$partialSuffix');
    final sink = partial.openWrite();
    var received = 0;
    try {
      await for (final chunk in bytes) {
        sink.add(chunk);
        received += chunk.length;
        _notify(key, received, expectedLength, false);
      }
      await sink.flush();
      await sink.close();
      final stale = await _find(key);
      if (stale != null && stale.path != file.path) await _delete(stale);
      await partial.rename(file.path);
      _notify(key, received, expectedLength ?? received, true);
      await _sweep(<String>{key});
      return file;
    } on Object {
      await sink.close();
      await _delete(partial);
      _notify(key, received, expectedLength, true);
      rethrow;
    }
  }

  void _notify(String key, int received, int? total, bool done) {
    final listeners = _listeners[key];
    if (listeners == null) return;
    for (final listener in List<VideoCacheProgressListener>.of(listeners)) {
      listener(received, total, done);
    }
  }

  /// Deletes the least-recently-used files until the cache fits [maxBytes].
  /// [protectedKeys] (the write that triggered the sweep and any in-flight
  /// downloads) are never removed.
  Future<void> _sweep(Set<String> protectedKeys) {
    final operation = _maintenance.then((_) async {
      if (!enabled) return;
      final files = await _files();
      final sizes = <String, int>{};
      final modified = <String, DateTime>{};
      var total = 0;
      for (final file in files) {
        final size = await _sizeOf(file);
        sizes[file.path] = size;
        modified[file.path] = (await _statOf(file))?.modified ?? DateTime.now();
        total += size;
      }
      if (total <= _maxBytes) return;
      files.sort(
        (a, b) => (modified[a.path] ?? DateTime.now()).compareTo(
          modified[b.path] ?? DateTime.now(),
        ),
      );
      for (final file in files) {
        if (total <= _maxBytes) break;
        final key = _stemOf(file);
        if (protectedKeys.contains(key) || _inFlight.containsKey(key)) {
          continue;
        }
        await _delete(file);
        total -= sizes[file.path] ?? 0;
      }
    });
    _maintenance = operation.then<void>((_) {}, onError: (_) {});
    return operation;
  }

  String _stemOf(File file) {
    final name = file.uri.pathSegments.last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  Future<int> _sizeOf(File file) async {
    try {
      return await file.length();
    } on FileSystemException {
      return 0;
    }
  }

  Future<FileStat?> _statOf(File file) async {
    try {
      return await file.stat();
    } on FileSystemException {
      return null;
    }
  }

  Future<void> _delete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // A file already removed (or locked) must not fail the sweep.
    }
  }
}
