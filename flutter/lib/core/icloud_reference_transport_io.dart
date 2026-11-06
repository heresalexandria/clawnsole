import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'icloud_reference_transport.dart';

/// One native helper per companion. Payloads travel only over private pipes.
/// A crashed helper fails pending requests; a later call can start it again and
/// recover from its native journal without publishing a duplicate snapshot.
class ProcessICloudReferenceTransport implements ICloudReferenceTransport {
  ProcessICloudReferenceTransport({
    required this.executable,
    required this.journalDirectory,
    this.requestTimeout = const Duration(seconds: 30),
    this.prepareTimeout = const Duration(minutes: 4),
  });

  final String executable;
  final String journalDirectory;
  final Duration requestTimeout;
  final Duration prepareTimeout;
  final Map<String, Completer<Map<String, Object?>>> _pending = {};
  Process? _process;
  Future<Process>? _starting;
  var _nextId = 0;
  var _closed = false;

  static const _unavailable = ICloudReferenceException(
    'helperUnavailable',
    'The iCloud Drive helper is unavailable. Restart Clawnsole and retry.',
  );

  Future<Process> _start() async {
    if (_closed) throw _unavailable;
    if (_process != null) return _process!;
    if (_starting != null) return _starting!;
    _starting = () async {
      try {
        final process = await Process.start(executable, [
          '--journal-dir',
          journalDirectory,
        ]);
        if (_closed) {
          process.kill(ProcessSignal.sigkill);
          throw _unavailable;
        }
        _process = process;
        unawaited(
          process.stdin.done.then<void>(
            (_) {},
            onError: (Object _) => _abort(process),
          ),
        );
        // Never forward native stderr into API transcripts or app logs.
        unawaited(process.stderr.drain<void>().catchError((Object _) {}));
        process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
              (line) {
                if (_process != process) return;
                try {
                  if (line.length > 1024 * 1024) throw _unavailable;
                  final frame = jsonDecode(line);
                  if (frame is! Map || frame['id'] is! String) {
                    throw _unavailable;
                  }
                  final completion = _pending.remove(frame['id']);
                  if (completion == null) return;
                  try {
                    completion.complete(
                      checkedICloudReferenceReply(frame['result']),
                    );
                  } on Object catch (error, stack) {
                    completion.completeError(error, stack);
                  }
                } on Object {
                  _abort(process);
                }
              },
              onError: (Object _) => _abort(process),
              onDone: () => _abort(process),
            );
        unawaited(process.exitCode.then((_) => _abort(process)));
        return process;
      } on Object {
        throw _unavailable;
      }
    }();
    try {
      return await _starting!;
    } finally {
      _starting = null;
    }
  }

  void _abort(Process process) {
    if (_process != process) return;
    _process = null;
    process.kill(ProcessSignal.sigkill);
    final pending = _pending.values.toList();
    _pending.clear();
    for (final value in pending) {
      if (!value.isCompleted) value.completeError(_unavailable);
    }
  }

  @override
  Future<Map<String, Object?>> call(
    String method, [
    Map<String, Object?> arguments = const {},
  ]) async {
    final process = await _start();
    final id = '${++_nextId}';
    final completion = Completer<Map<String, Object?>>();
    _pending[id] = completion;
    // Attach the timeout/error observer before writing to the pipe.
    final result = completion.future.timeout(
      method == 'prepare' ? prepareTimeout : requestTimeout,
      onTimeout: () {
        _pending.remove(id);
        // A status or cleanup request can wait behind Foundation work. Its
        // shorter deadline must not terminate another reference's preparation.
        // The prepare deadline still bounds an otherwise stuck publication.
        if (method == 'prepare') _abort(process);
        throw const ICloudReferenceException(
          'timeout',
          'iCloud Drive took too long. Check your connection and retry; Clawnsole will recover its temporary copy.',
        );
      },
    );
    try {
      process.stdin.writeln(
        jsonEncode({'id': id, 'method': method, 'arguments': arguments}),
      );
    } on Object {
      _abort(process);
    }
    return result;
  }

  @override
  Future<void> close() async {
    _closed = true;
    final process = _process;
    if (process == null) return;
    try {
      await process.stdin.close().timeout(const Duration(seconds: 2));
      await process.exitCode.timeout(const Duration(seconds: 3));
    } on Object {
      // A Foundation publication can block; its intent is already journaled.
    } finally {
      _abort(process);
    }
  }
}
