import 'dart:io';

import 'hard_link.dart';

/// Crash-safe replacement of a whole file.
///
/// The canonical file must exist at every instant: the contents are written
/// to a sibling temporary file, flushed, and then renamed over the target.
/// `rename` replaces atomically on POSIX and Dart maps it to
/// `MoveFileEx(MOVEFILE_REPLACE_EXISTING)` on Windows, so no step ever leaves
/// the target missing. Before the swap, the previous revision is kept at
/// [backupPath] so a reader can fall back when the canonical file turns out
/// missing or malformed (see [readTextWithFallback]).
///
/// The backup is normally a hard link to the current inode rather than a
/// second copy of every byte: the rename that follows only swaps the
/// canonical *name* to the new inode, so the old inode lives on under the
/// backup name unchanged. Filesystems that refuse links get a copy instead.
/// When [prepareBackup] rewrites the previous contents (legacy credential or
/// diagnostic scrubbing) the rewritten text is written out as before. A
/// caller that has already read the file can hand the text over as
/// [previousContents] so it is not read a second time.
Future<void> writeTextAtomically(
  File file,
  String contents, {
  bool keepBackup = true,
  String Function(String contents)? prepareBackup,
  String? previousContents,
}) async {
  await file.parent.create(recursive: true);
  final temporary = File(
    '${file.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
  );
  try {
    await temporary.writeAsString(contents, flush: true);
    if (keepBackup && await file.exists()) {
      try {
        await _keepPreviousRevision(file, prepareBackup, previousContents);
      } on FileSystemException {
        // A backup is insurance, never a reason to fail the write itself.
      }
    }
    // If replacement fails (full disk, permissions or a Windows sharing lock),
    // leave the canonical copy intact. Deleting it to retry creates a data-loss
    // window, especially when making a backup failed for the same reason.
    await temporary.rename(file.path);
  } finally {
    try {
      if (await temporary.exists()) await temporary.delete();
    } on FileSystemException {
      // Preserve the original write error; a later sweep can remove leftovers.
    }
  }
  unawaitedCleanup(file);
}

/// Keeps the revision currently at [file] under [backupPath] before the
/// canonical name is swapped to the new contents.
///
/// A [prepareBackup] whose result differs from the previous text is written
/// out as a fresh file. Otherwise the previous inode is linked under a
/// temporary sibling name (a directory entry, no data written) — or copied
/// there when the filesystem refuses links — and that sibling is renamed
/// over the backup name. `link(2)` will not replace a name but `rename`
/// does, atomically, so the previous revision is never absent and a copy
/// interrupted mid-write never lands as the backup. The canonical file — the
/// only copy that matters — exists throughout.
Future<void> _keepPreviousRevision(
  File file,
  String Function(String contents)? prepareBackup,
  String? previousContents,
) async {
  final backup = File(backupPath(file));
  if (prepareBackup != null) {
    final previous = previousContents ?? await file.readAsString();
    final prepared = prepareBackup(previous);
    if (prepared != previous) {
      await writeTextAtomically(backup, prepared, keepBackup: false);
      return;
    }
  }
  final staged = File(
    '${backup.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
  );
  try {
    if (!createHardLink(file.path, staged.path)) {
      await file.copy(staged.path);
    }
    await staged.rename(backup.path);
  } finally {
    try {
      if (await staged.exists()) await staged.delete();
    } on FileSystemException {
      // Best effort; the temporary-file sweep removes stale leftovers.
    }
  }
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
