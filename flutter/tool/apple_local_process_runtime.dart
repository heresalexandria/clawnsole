import 'dart:async';
import 'dart:convert';
import 'dart:io';

class AppleLocalProcessRuntime {
  AppleLocalProcessRuntime(this.applicationBundle);

  final Directory? applicationBundle;
  bool _isAvailable = false;
  final Map<String, Map<String, Object?>> _jobs =
      <String, Map<String, Object?>>{};
  final Map<String, File> _progressFiles = <String, File>{};

  File? get _executable => applicationBundle == null
      ? null
      : File(
          '${applicationBundle!.path}${Platform.pathSeparator}Contents'
          '${Platform.pathSeparator}MacOS${Platform.pathSeparator}'
          'clawnsole_apple_generator',
        );

  bool get isAvailable => _isAvailable;

  Future<void> initialize() async {
    final executable = _executable;
    if (!Platform.isMacOS || executable == null || !executable.existsSync()) {
      _isAvailable = false;
      return;
    }
    try {
      final result = await Process.run(executable.path, const <String>[
        '--check-availability',
      ]);
      _isAvailable =
          result.exitCode == 0 && result.stdout.toString().trim() == 'true';
    } on ProcessException {
      _isAvailable = false;
    }
  }

  Future<Map<String, Object?>> submit(Map<String, Object?> request) async {
    if (!isAvailable) {
      throw StateError('The Apple Local macOS helper is not installed.');
    }
    final jobId = request['requestId']?.toString() ?? '';
    if (jobId.isEmpty) throw StateError('A local generation id is required.');
    if (_jobs.containsKey(jobId)) {
      throw StateError('This local generation is already running.');
    }
    _jobs[jobId] = <String, Object?>{
      'status': 'Pending',
      'progress': 0,
      'message': 'Starting Apple image generation',
    };
    final outputDirectory = Directory(
      request['outputDirectory']?.toString() ?? '',
    );
    if (outputDirectory.path.isEmpty) {
      throw StateError('Apple Local needs a job output directory.');
    }
    await outputDirectory.create(recursive: true);
    final requestFile = File(
      '${outputDirectory.path}${Platform.pathSeparator}request.json',
    );
    final progressFile = File(
      '${outputDirectory.path}${Platform.pathSeparator}progress.jsonl',
    );
    await requestFile.writeAsString(jsonEncode(request), flush: true);
    await progressFile.writeAsString('', flush: true);
    _progressFiles[jobId] = progressFile;
    final launch = await Process.start('/usr/bin/open', <String>[
      '-W',
      '-n',
      '-a',
      applicationBundle!.path,
      '--args',
      '--request-file',
      requestFile.path,
      '--progress-file',
      progressFile.path,
    ]);
    final errors = StringBuffer();
    launch.stderr.transform(utf8.decoder).listen((chunk) {
      if (errors.length < 8000) errors.write(chunk);
    });
    unawaited(
      launch.exitCode.then((code) {
        final current = poll(jobId);
        final terminal =
            current['status'] == 'Ready' || current['status'] == 'Error';
        if (!terminal) {
          _jobs[jobId] = <String, Object?>{
            'status': 'Error',
            'progress': current['progress'] ?? 0,
            'message': 'Local generation stopped',
            'error': errors.toString().trim().isEmpty
                ? 'The Apple Local helper exited before generation finished.'
                : errors.toString().trim(),
          };
        }
      }),
    );
    return <String, Object?>{'jobId': jobId, 'status': 'Pending'};
  }

  Map<String, Object?> poll(String jobId) {
    final progressFile = _progressFiles[jobId];
    if (progressFile?.existsSync() == true) {
      final lines = progressFile!.readAsLinesSync();
      for (final line in lines.reversed) {
        if (line.trim().isEmpty) continue;
        try {
          final decoded = jsonDecode(line);
          if (decoded is Map<Object?, Object?>) {
            final update = decoded.map(
              (key, value) => MapEntry(key.toString(), value),
            );
            _jobs[jobId] = update;
            return update;
          }
        } on FormatException {
          break;
        }
      }
    }
    return _jobs[jobId] ??
        <String, Object?>{
          'status': 'Error',
          'progress': 0,
          'error':
              'This local job is no longer running. It may have been interrupted when the app closed.',
        };
  }
}
