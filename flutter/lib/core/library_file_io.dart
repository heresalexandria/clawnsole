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
Future<void> writeLibraryTextAtomically(File file, String contents) async {
  if (await file.exists()) {
    Object? current;
    try {
      current = jsonDecode(await file.readAsString());
    } on FormatException {
      // Malformed metadata remains eligible for the existing backup recovery.
    }
    final schema = current is Map<String, dynamic>
        ? current['schemaVersion']
        : null;
    if (schema is int && schema > StoredData.currentSchemaVersion) {
      throw UnsupportedError(
        'This library needs a newer Clawnsole version (schema $schema).',
      );
    }
    final workspace = current is Map<String, dynamic>
        ? current['composerTabs']
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
  await writeTextAtomically(
    file,
    contents,
    prepareBackup: _sanitizedLibraryRecovery,
  );
  final name = file.uri.pathSegments.last;
  await for (final entry in file.parent.list()) {
    if (entry is! File) continue;
    final sibling = entry.uri.pathSegments.last;
    if (sibling != '$name.bak' && !sibling.startsWith('$name.corrupt-')) {
      continue;
    }
    final previous = await entry.readAsString();
    final sanitized = _sanitizedLibraryRecovery(previous);
    if (sanitized != previous) {
      await writeTextAtomically(entry, sanitized, keepBackup: false);
    }
  }
}

String _sanitizedLibraryRecovery(String source) {
  Object? value;
  try {
    value = jsonDecode(source);
  } on FormatException {
    // An undecodable recovery copy may be the only remaining evidence needed
    // to recover media metadata. Never destroy it by guessing at its contents.
    return source;
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
