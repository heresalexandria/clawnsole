import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'api_transcript.dart';
import 'api_transcript_store.dart';

/// One JSON Lines file per film, in `api-transcripts/` beside the library.
///
/// A sidecar, deliberately: `clawnsole.json` is read whole on every load and
/// AGENTS.md keeps it compact, so a debugging log of provider traffic has no
/// business in it. Appending a line costs nothing, a film's transcript is
/// read only when a director asks for it, and losing one loses nothing.
class ApiTranscriptFileStore implements ApiTranscriptStore {
  ApiTranscriptFileStore(this._directory);

  /// The transcript directory, resolved lazily because the library can be
  /// relocated underneath a running app.
  final Future<Directory> Function() _directory;

  Future<void> _queue = Future<void>.value();
  final Map<String, int> _sequences = <String, int>{};
  final Map<String, int> _lineCounts = <String, int>{};

  static const String directoryName = 'api-transcripts';

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _queue.then((_) => operation());
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  /// A file name that is always this operation and never a path.
  static String fileStem(String operationId) {
    final trimmed = operationId.trim();
    final safe = trimmed.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final leading = safe.replaceFirst(RegExp(r'^[.]+'), '');
    if (leading.isEmpty || leading.length > 100 || leading != trimmed) {
      final digest = sha256.convert(utf8.encode(trimmed)).toString();
      return 'op-${digest.substring(0, 32)}';
    }
    return leading;
  }

  Future<File> _file(String operationId) async => File(
    '${(await _directory()).path}'
    '${Platform.pathSeparator}${fileStem(operationId)}.jsonl',
  );

  @override
  Future<void> appendApiRequest(ApiRequestRecord record) =>
      _serialize(() async {
        final file = await _file(record.operationId);
        var next = _sequences[record.operationId];
        var lines = _lineCounts[record.operationId];
        if (next == null || lines == null) {
          // The first append of a session pays for one read; every later
          // one only stats the file.
          final existing = await _readRecords(file);
          next = existing.isEmpty ? 1 : existing.last.sequence + 1;
          lines = existing.length;
        }
        final line = jsonEncode(record.copyWith(sequence: next).toJson());
        await file.parent.create(recursive: true);
        await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
        _sequences[record.operationId] = next + 1;
        _lineCounts[record.operationId] = lines + 1;
        if (lines + 1 > maxApiRequestsPerFilm ||
            await file.length() > maxApiTranscriptBytes) {
          _lineCounts[record.operationId] = await _capFile(file);
        }
      });

  /// Keeps the newest records within both caps by rewriting the file, and
  /// reports how many lines survived. Only runs when a cap is crossed.
  Future<int> _capFile(File file) async {
    var lines = await _readLines(file);
    if (lines.length > maxApiRequestsPerFilm) {
      lines = lines.sublist(lines.length - maxApiRequestsPerFilm);
    }
    var bytes = lines.fold<int>(0, (total, line) => total + line.length + 1);
    while (lines.length > 1 && bytes > maxApiTranscriptBytes) {
      bytes -= lines.removeAt(0).length + 1;
    }
    await file.writeAsString('${lines.join('\n')}\n', flush: true);
    return lines.length;
  }

  Future<List<String>> _readLines(File file) async {
    if (!await file.exists()) return const <String>[];
    return LineSplitter.split(
      await file.readAsString(),
    ).where((line) => line.trim().isNotEmpty).toList();
  }

  Future<List<ApiRequestRecord>> _readRecords(File file) async {
    final records = <ApiRequestRecord>[];
    for (final line in await _readLines(file)) {
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map<Object?, Object?>) {
          records.add(
            ApiRequestRecord.fromJson(
              decoded.map((key, value) => MapEntry('$key', value)),
            ),
          );
        }
      } on FormatException {
        // A half-written line from a killed process is skipped, not fatal.
      }
    }
    return records;
  }

  @override
  Future<List<ApiRequestRecord>> readApiRequests(String operationId) =>
      _serialize(() async => _readRecords(await _file(operationId)));

  @override
  Future<void> deleteApiRequests(String operationId) => _serialize(() async {
    _sequences.remove(operationId);
    _lineCounts.remove(operationId);
    final file = await _file(operationId);
    if (await file.exists()) await file.delete();
  });

  /// Forgets every transcript, for the wipe that clears the whole library.
  Future<void> deleteAllApiRequests() => _serialize(() async {
    _sequences.clear();
    _lineCounts.clear();
    final directory = await _directory();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  @override
  Future<void> pruneApiTranscripts(Set<String> retainedOperationIds) =>
      _serialize(() async {
        final directory = await _directory();
        if (!await directory.exists()) return;
        final retained = retainedOperationIds.map(fileStem).toSet();
        // A film's record is written before its first provider call, but a
        // submission still in flight during a prune has been seen with no
        // record at all; the grace window keeps its transcript alive until
        // the record it belongs to is durable.
        final grace = DateTime.now().subtract(const Duration(hours: 1));
        await for (final entry in directory.list()) {
          if (entry is! File || !entry.path.endsWith('.jsonl')) continue;
          final name = entry.uri.pathSegments.last;
          final stem = name.substring(0, name.length - '.jsonl'.length);
          if (retained.contains(stem)) continue;
          if ((await entry.stat()).modified.isAfter(grace)) continue;
          await entry.delete();
          _sequences.removeWhere((id, _) => fileStem(id) == stem);
          _lineCounts.removeWhere((id, _) => fileStem(id) == stem);
        }
      });
}
