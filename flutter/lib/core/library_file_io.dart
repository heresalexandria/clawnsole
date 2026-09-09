import 'dart:convert';
import 'dart:io';

import 'atomic_file.dart';
import 'composer_tabs.dart';
import 'generation_status.dart';
import 'models.dart';

/// Retains the previous library metadata while removing legacy plaintext
/// credentials and unsafe diagnostics from app-owned recovery copies. This
/// deliberately preserves unknown fields instead of round-tripping an older
/// model schema over a newer library.
///
/// A library is saved on every generation poll, so the cost of one call is
/// what the desktop companion dirties all day. The previous contents are read
/// once (the unchanged-save comparison needs the real bytes on disk) and that
/// one read feeds the schema check, the backup preparation and the recovery
/// sweep; the backup itself is a hard link of the previous inode unless the
/// sanitizer had to change it (see [writeTextAtomically]).
Future<void> writeLibraryTextAtomically(File file, String contents) async {
  String? previousContents;
  Object? previousValue;
  FileStat? previousStat;
  final stat = await file.stat();
  if (stat.type != FileSystemEntityType.notFound) {
    previousStat = stat;
    previousContents = await file.readAsString();
    try {
      previousValue = jsonDecode(previousContents);
    } on FormatException {
      // Malformed metadata remains eligible for the existing backup recovery.
    }
    final schema = previousValue is Map<String, dynamic>
        ? previousValue['schemaVersion']
        : null;
    if (schema is int && schema > StoredData.currentSchemaVersion) {
      throw UnsupportedError(
        'This library needs a newer Clawnsole version (schema $schema).',
      );
    }
    final workspace = previousValue is Map<String, dynamic>
        ? previousValue['composerTabs']
        : null;
    final workspaceSchema = workspace is Map<String, dynamic>
        ? workspace['schemaVersion']
        : null;
    if (workspaceSchema is int &&
        workspaceSchema > ComposerTabsState.schemaVersion) {
      throw UnsupportedError(
        'These Create tabs need a newer Clawnsole version '
        '(schema $workspaceSchema).',
      );
    }
  }
  // Polls, reconciliations and draft callbacks can save an unchanged snapshot.
  // Compare with the actual disk contents, not a process cache: another app
  // instance or a library restore may have replaced it since the last write.
  // Keep the previous *different* revision as recovery insurance as well as
  // avoiding two whole-file writes and flushes on every no-op save.
  if (previousContents != contents) {
    var backupIsPreviousRevision = false;
    await writeTextAtomically(
      file,
      contents,
      previousContents: previousContents,
      prepareBackup: (previous) {
        // The decoded tree from the schema check is reused when the writer
        // hands back the same text it was given; anything else is decoded
        // afresh rather than trusted.
        final sanitized = _sanitizedLibraryRecovery(
          previous,
          decoded: identical(previous, previousContents) ? previousValue : null,
        );
        backupIsPreviousRevision = sanitized == previous;
        return sanitized;
      },
    );
    if (backupIsPreviousRevision && previousStat != null) {
      // The backup is the previous inode (or a copy of it), already known to
      // be clean: the sweep below can trust it by stamp instead of reading and
      // decoding it again.
      _verifiedRecoveryCopies[backupPath(file)] = _stamp(previousStat);
    }
  }
  await _sanitizeRecoveryCopies(file);
}

typedef _RecoveryStamp = ({int size, DateTime modified});

_RecoveryStamp _stamp(FileStat stat) =>
    (size: stat.size, modified: stat.modified);

/// Recovery copies this process has already read and found clean, by path and
/// on-disk stamp. A copy whose size or modification time moved is read again,
/// so an edit or restore from outside the process is still sanitized; an
/// unchanged copy costs a stat, not a whole-library read and decode.
final _verifiedRecoveryCopies = <String, _RecoveryStamp>{};

Future<void> _sanitizeRecoveryCopies(File file) async {
  final name = file.uri.pathSegments.last;
  await for (final entry in file.parent.list()) {
    if (entry is! File) continue;
    final sibling = entry.uri.pathSegments.last;
    if (sibling != '$name.bak' && !sibling.startsWith('$name.corrupt-')) {
      continue;
    }
    var stat = await entry.stat();
    if (_verifiedRecoveryCopies[entry.path] == _stamp(stat)) continue;
    final previous = await entry.readAsString();
    final sanitized = _sanitizedLibraryRecovery(previous);
    if (sanitized != previous) {
      await writeTextAtomically(entry, sanitized, keepBackup: false);
      stat = await entry.stat();
    }
    _verifiedRecoveryCopies[entry.path] = _stamp(stat);
  }
}

String _sanitizedLibraryRecovery(String source, {Object? decoded}) {
  Object? value = decoded;
  if (value == null) {
    try {
      value = jsonDecode(source);
    } on FormatException {
      // An undecodable recovery copy may be the only remaining evidence needed
      // to recover media metadata. Never destroy it by guessing at its contents.
      return source;
    }
  }
  if (value is! Map<String, dynamic>) return source;
  var changed = value.containsKey('apiKeys') || value.containsKey('apiKey');
  value.remove('apiKeys');
  value.remove('apiKey');
  final generations = value['generations'];
  if (generations is List) {
    for (final generation in generations) {
      if (generation is! Map<String, dynamic>) continue;
      for (final key in <String>[
        'lastProviderResponse',
        'error',
        'lastCheckError',
        'resultRetentionError',
      ]) {
        final diagnostic = generation[key];
        if (diagnostic == null) continue;
        final sanitized = compactProviderResponse(diagnostic);
        if (sanitized != diagnostic) {
          generation[key] = sanitized;
          changed = true;
        }
      }
    }
  }
  return changed
      ? '${const JsonEncoder.withIndent('  ').convert(value)}\n'
      : source;
}
