import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../core/renderer_diagnostic_bridge.dart';

typedef RendererDiagnosticReporter = void Function(Map<String, Object> event);

/// Observes errors and completed frames without requesting extra frames or
/// reading application data. The desktop shell records these small summaries
/// alongside process memory, including when the Flutter surface stops painting.
class RendererDiagnostics with WidgetsBindingObserver {
  RendererDiagnostics({
    WidgetsBinding? binding,
    RendererDiagnosticReporter reporter = reportRendererDiagnostic,
    DateTime Function()? now,
    this.healthInterval = const Duration(minutes: 1),
    this.showReleaseErrorWidget = kReleaseMode,
  }) : _binding = binding ?? WidgetsBinding.instance,
       _reporter = reporter,
       _now = now ?? DateTime.now;

  static const maximumErrorReportsPerMinute = 10;
  static const maximumStackCharacters = 4096;

  final WidgetsBinding _binding;
  final RendererDiagnosticReporter _reporter;
  final DateTime Function() _now;
  final Duration healthInterval;
  final bool showReleaseErrorWidget;
  FlutterExceptionHandler? _previousFlutterError;
  ui.ErrorCallback? _previousPlatformError;
  ErrorWidgetBuilder? _previousErrorWidget;
  Timer? _healthTimer;
  DateTime? _lastFrameAt;
  DateTime? _startedAt;
  DateTime? _errorWindowAt;
  int _frameCount = 0;
  int _errorReports = 0;
  int _suppressedErrors = 0;
  bool _installed = false;
  bool _active = false;

  void install() {
    if (_installed) return;
    _installed = true;
    _startedAt = _now();
    _previousFlutterError = FlutterError.onError;
    _previousPlatformError = ui.PlatformDispatcher.instance.onError;
    FlutterError.onError = _onFlutterError;
    ui.PlatformDispatcher.instance.onError = _onPlatformError;
    if (showReleaseErrorWidget) {
      _previousErrorWidget = ErrorWidget.builder;
      ErrorWidget.builder = _buildErrorWidget;
    }
    _binding.addObserver(this);
    _binding.addTimingsCallback(_onFrameTimings);
    _active =
        _binding.lifecycleState == null ||
        _binding.lifecycleState == AppLifecycleState.resumed;
    // Hidden windows can still accumulate renderer resources. Continue the
    // same low-rate sampling, recording activity instead of hiding that span.
    _healthTimer = Timer.periodic(healthInterval, (_) => _emitHealth());
    _binding.addPostFrameCallback((_) {
      if (_installed) _report({'event': 'flutter-ready'});
    });
  }

  void _report(Map<String, Object> event) {
    try {
      _reporter(event);
    } on Object {
      // Logging must never become an additional application error.
    }
  }

  void _reportError(String event, Object error, StackTrace? stack) {
    final now = _now();
    if (_errorWindowAt == null ||
        now.difference(_errorWindowAt!) >= const Duration(minutes: 1)) {
      _errorWindowAt = now;
      _errorReports = 0;
    }
    if (_errorReports >= maximumErrorReportsPerMinute) {
      if (_suppressedErrors < 1000000000) _suppressedErrors += 1;
      return;
    }
    _errorReports += 1;
    // Exception messages and FlutterErrorDetails.context can contain prompts,
    // file paths, or service responses. Only the type and bounded stack leave
    // the framework; the shell further keeps only allowlisted source frames.
    final trace = stack?.toString() ?? '';
    final type = error.runtimeType.toString();
    _report({
      'event': event,
      'errorType': type.length <= 80 ? type : 'Error',
      if (trace.isNotEmpty)
        'stack': trace.length <= maximumStackCharacters
            ? trace
            : trace.substring(0, maximumStackCharacters),
    });
  }

  void _onFlutterError(FlutterErrorDetails details) {
    try {
      _reportError('flutter-error', details.exception, details.stack);
    } on Object {
      // Even a custom StackTrace implementation cannot break the old handler.
    }
    _previousFlutterError?.call(details);
  }

  bool _onPlatformError(Object error, StackTrace stack) {
    try {
      _reportError('flutter-platform-error', error, stack);
    } on Object {
      // Preserve the prior handler even when diagnostic serialization fails.
    }
    // A diagnostic record does not mean an unhandled exception was recovered.
    return _previousPlatformError?.call(error, stack) ?? false;
  }

  void _onFrameTimings(List<ui.FrameTiming> timings) {
    if (!_installed || timings.isEmpty) return;
    _frameCount += timings.length;
    _lastFrameAt = _now();
  }

  void _emitHealth() {
    if (!_installed) return;
    final cache = PaintingBinding.instance.imageCache;
    final age = _now().difference(_lastFrameAt ?? _startedAt!).inMilliseconds;
    _report({
      'event': 'flutter-health',
      'appActive': _active ? 1 : 0,
      'frameCount': _frameCount,
      'lastFrameAgeMs': age < 0 ? 0 : age,
      'cacheBytes': cache.currentSizeBytes,
      'cacheImages': cache.currentSize,
      'liveImages': cache.liveImageCount,
      'pendingImages': cache.pendingImageCount,
      'flutterErrorsSuppressed': _suppressedErrors,
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_installed) _active = state == AppLifecycleState.resumed;
  }

  Widget _buildErrorWidget(FlutterErrorDetails details) => const Directionality(
    textDirection: TextDirection.ltr,
    child: ColoredBox(
      color: Color(0xFFF1EBDE),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'This part of Clawnsole could not be displayed. '
            'Reopen Clawnsole to try again.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF271E25), fontSize: 14),
          ),
        ),
      ),
    ),
  );

  void dispose() {
    if (!_installed) return;
    _installed = false;
    _healthTimer?.cancel();
    _healthTimer = null;
    _binding.removeObserver(this);
    _binding.removeTimingsCallback(_onFrameTimings);
    if (FlutterError.onError == _onFlutterError) {
      FlutterError.onError = _previousFlutterError;
    }
    if (ui.PlatformDispatcher.instance.onError == _onPlatformError) {
      ui.PlatformDispatcher.instance.onError = _previousPlatformError;
    }
    if (ErrorWidget.builder == _buildErrorWidget) {
      ErrorWidget.builder = _previousErrorWidget!;
    }
  }
}

/// Owns observer/handler cleanup when the application is removed or replaced.
class RendererDiagnosticsScope extends StatefulWidget {
  const RendererDiagnosticsScope({
    required this.diagnostics,
    required this.child,
    super.key,
  });

  final RendererDiagnostics diagnostics;
  final Widget child;

  @override
  State<RendererDiagnosticsScope> createState() =>
      _RendererDiagnosticsScopeState();
}

class _RendererDiagnosticsScopeState extends State<RendererDiagnosticsScope> {
  @override
  void initState() {
    super.initState();
    widget.diagnostics.install();
  }

  @override
  void didUpdateWidget(covariant RendererDiagnosticsScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.diagnostics, widget.diagnostics)) {
      oldWidget.diagnostics.dispose();
      widget.diagnostics.install();
    }
  }

  @override
  void dispose() {
    widget.diagnostics.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
