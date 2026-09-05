import 'dart:io';

/// Crash-safe replacement of a whole file.
///
/// The canonical file must exist at every instant: the contents are written
/// to a sibling temporary file, flushed, and then renamed over the target.
/// `rename` replaces atomically on POSIX and Dart maps it to
/// `MoveFileEx(MOVEFILE_REPLACE_EXISTING)` on Windows, so no step ever leaves
/// the target missing. Before the swap, the previous contents are copied to
/// [backupPath] so a reader can fall back when the canonical file turns out
/// missing or malformed (see [readTextWithFallback]).
Future<void> writeTextAtomically(
  File file,
  String contents, {
  bool keepBackup = true,
  String Function(String contents)? prepareBackup,
}) async {
  await file.parent.create(recursive: true);
  final temporary = File(
    '${file.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
  );
  await temporary.writeAsString(contents, flush: true);
  if (keepBackup && await file.exists()) {
    try {
      if (prepareBackup == null) {
        await file.copy(backupPath(file));
      } else {
        await writeTextAtomically(
          File(backupPath(file)),
          prepareBackup(await file.readAsString()),
          keepBackup: false,
        );
      }
    } on FileSystemException {
      // A backup is insurance, never a reason to fail the write itself.
    }
  }
  try {
    await temporary.rename(file.path);
  } on FileSystemException {
    // Some filesystems refuse to replace an open target (notably network
    // and sync-managed folders on Windows). The backup taken above makes the
    // delete-then-rename fallback recoverable.
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }
  unawaitedCleanup(file);
}

/// The sibling file holding the previous contents of [file].
String backupPath(File file) => '${file.path}.bak';

/// Removes a library and only its owned recovery siblings. Recovery copies
/// are removed before the primary, so an interrupted/failed deletion cannot
/// make a missing primary silently revive a backup on the next launch.
Future<void> deleteTextWithRecovery(File file) async {
  if (await file.parent.exists()) {
    final name = file.uri.pathSegments.last;
    await for (final entry in file.parent.list()) {
      if (entry is! File) continue;
      final sibling = entry.uri.pathSegments.last;
      if (sibling == '$name.bak' ||
          sibling.startsWith('$name.corrupt-') ||
          (sibling.startsWith('$name.') && sibling.endsWith('.tmp'))) {
        await entry.delete();
      }
    }
  }
  if (await file.exists()) await file.delete();
}

/// Reads [file], falling back to its backup when the canonical copy is
/// missing or fails [decode]. A malformed canonical file is preserved as a
/// `.corrupt-<timestamp>` sibling for inspection instead of being overwritten
/// silently by the next write.
///
/// Returns null when neither copy exists.
Future<T?> readTextWithFallback<T>(
  File file,
  T Function(String contents) decode,
) async {
  final backup = File(backupPath(file));
  if (await file.exists()) {
    try {
      return decode(await file.readAsString());
    } on FormatException {
      if (!await backup.exists()) rethrow;
      try {
        await file.rename(
          '${file.path}.corrupt-${DateTime.now().toUtc().millisecondsSinceEpoch}',
        );
      } on FileSystemException {
        // Keeping the damaged file is best effort.
      }
    }
  }
  if (await backup.exists()) {
    return decode(await backup.readAsString());
  }
  return null;
}

/// Removes temporary files left behind by writes interrupted before rename.
/// Best effort and fire-and-forget: leftovers only cost disk space.
void unawaitedCleanup(File file) {
  final name = file.uri.pathSegments.last;
  file.parent.list().listen(
    (entry) {
      if (entry is! File) return;
      final entryName = entry.uri.pathSegments.last;
      if (entryName.startsWith('$name.') && entryName.endsWith('.tmp')) {
        // A temporary from another process may still be mid-write; skip
        // anything younger than a minute.
        entry.stat().then((stat) {
          if (DateTime.now().difference(stat.modified) >
              const Duration(minutes: 1)) {
            entry.delete().catchError((Object _) => entry);
          }
        }, onError: (Object _) {});
      }
    },
    onError: (Object _) {},
    cancelOnError: true,
  );
}
