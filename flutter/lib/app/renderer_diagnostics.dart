import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../core/renderer_diagnostic_bridge.dart';

typedef RendererDiagnosticReporter = void Function(Map<String, Object> event);

/// Heap pressure codes carried by `flutter-health`.
enum RendererHeapPressure { none, growing, critical }

/// Observes errors and completed frames without requesting extra frames or
/// reading application data. The desktop shell records these small summaries
/// alongside process memory, including when the Flutter surface stops painting.
///
/// The same low-rate health sampling drives two in-app judgements that never
/// leave numeric form: a CanvasKit heap watchdog that latches
/// [motionConstrained] before the Wasm heap can reach its hard cap, and an
/// engine-stall self-report when an active window stops completing frames
/// while errors keep arriving. Recovery itself stays with the desktop shell.
class RendererDiagnostics with WidgetsBindingObserver {
  RendererDiagnostics({
    WidgetsBinding? binding,
    RendererDiagnosticReporter reporter = reportRendererDiagnostic,
    DateTime Function()? now,
    int? Function() heapBytesReader = readCanvasKitHeapBytes,
    int Function() documentHiddenReader = readDocumentHidden,
    this.healthInterval = const Duration(minutes: 1),
    this.showReleaseErrorWidget = kReleaseMode,
  }) : _binding = binding ?? WidgetsBinding.instance,
       _reporter = reporter,
       _now = now ?? DateTime.now,
       _readHeapBytes = heapBytesReader,
       _readDocumentHidden = documentHiddenReader;

  static const maximumErrorReportsPerMinute = 10;
  static const maximumLifecycleEventsPerMinute = 20;
  static const maximumStackCharacters = 4096;

  /// Heap growth in one health interval that counts as `growing`.
  static const heapGrowthPerIntervalBytes = 64 * 1024 * 1024;

  /// Heap growth across [heapGrowthWindow] that counts as `growing`.
  static const heapGrowthPerWindowBytes = 256 * 1024 * 1024;
  static const heapGrowthWindow = Duration(minutes: 10);

  /// Ten intervals of history need eleven samples: the base plus the ten
  /// readings after it.
  static const heapSampleCount = 11;

  /// Errors in one health interval that make a silent interval count toward
  /// a stall even before Dart's own report cap suppresses any: the same
  /// storm threshold the desktop shell applies per minute.
  static const stormErrorsPerInterval = 1000;

  /// Allocated heap at or above which motion is constrained for good. The
  /// Wasm heap never shrinks, so half of the 2 GiB cap leaves headroom for a
  /// graceful brake before Emscripten aborts.
  static const heapCriticalBytes = 1073741824;

  /// Consecutive foreground health intervals in which no frame completed
  /// while errors kept arriving before the renderer reports itself stalled.
  /// A static screen is not a stall; a static screen that throws every time
  /// the engine tries to draw is.
  static const stalledHealthIntervals = 2;

  final WidgetsBinding _binding;
  final RendererDiagnosticReporter _reporter;
  final DateTime Function() _now;
  final int? Function() _readHeapBytes;
  final int Function() _readDocumentHidden;
  final Duration healthInterval;
  final bool showReleaseErrorWidget;
  final ValueNotifier<bool> _motionConstrained = ValueNotifier<bool>(false);
  final List<_HeapSample> _heapSamples = <_HeapSample>[];
  FlutterExceptionHandler? _previousFlutterError;
  ui.ErrorCallback? _previousPlatformError;
  ErrorWidgetBuilder? _previousErrorWidget;
  Timer? _healthTimer;
  DateTime? _lastFrameAt;
  DateTime? _startedAt;
  DateTime? _errorWindowAt;
  DateTime? _lifecycleWindowAt;
  int _frameCount = 0;
  int _frameCountAtLastHealth = 0;
  int _errorReports = 0;
  int _lifecycleReports = 0;
  int _suppressedErrors = 0;
  int _totalErrors = 0;
  int _totalErrorsAtLastHealth = 0;
  int _suppressedErrorsAtLastHealth = 0;
  int _silentErrorIntervals = 0;
  int _errorsInStallWindow = 0;
  bool _stallReported = false;
  RendererHeapPressure _heapPressure = RendererHeapPressure.none;
  AppLifecycleState? _lifecycle;
  bool _installed = false;
  bool _active = false;

  /// True once the CanvasKit heap reached [heapCriticalBytes]. Never returns
  /// to false for this Flutter instance: the Wasm heap does not shrink, so
  /// continuous animation would only bring the abort closer.
  ValueListenable<bool> get motionConstrained => _motionConstrained;

  /// The lifecycle code used in health and lifecycle records: 0 detached,
  /// 1 resumed, 2 inactive, 3 hidden, 4 paused.
  static int lifecycleStateCode(AppLifecycleState? state) => switch (state) {
    AppLifecycleState.detached => 0,
    // A binding that has not reported a state yet is treated as foreground,
    // matching the activity flag used since the first health record.
    null || AppLifecycleState.resumed => 1,
    AppLifecycleState.inactive => 2,
    AppLifecycleState.hidden => 3,
    AppLifecycleState.paused => 4,
  };

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
    _lifecycle = _binding.lifecycleState;
    _active = _lifecycle == null || _lifecycle == AppLifecycleState.resumed;
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
    if (_totalErrors < 1000000000) _totalErrors += 1;
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
    // A completed frame re-arms the stall report for the next silent span.
    _silentErrorIntervals = 0;
    _errorsInStallWindow = 0;
    _stallReported = false;
  }

  void _emitHealth() {
    if (!_installed) return;
    final now = _now();
    final cache = PaintingBinding.instance.imageCache;
    final age = now.difference(_lastFrameAt ?? _startedAt!).inMilliseconds;
    final framesSinceLastHealth = _frameCount - _frameCountAtLastHealth;
    final errorsSinceLastHealth = _totalErrors - _totalErrorsAtLastHealth;
    final suppressedSinceLastHealth =
        _suppressedErrors - _suppressedErrorsAtLastHealth;
    _frameCountAtLastHealth = _frameCount;
    _totalErrorsAtLastHealth = _totalErrors;
    _suppressedErrorsAtLastHealth = _suppressedErrors;
    var heapBytes = -1;
    try {
      _observeHeap(now, _readHeapBytes());
      heapBytes = _heapSamples.isEmpty ? -1 : _heapSamples.last.bytes;
    } on Object {
      // A failing heap probe leaves pressure unchanged; health still goes out.
    }
    _observeStall(
      age < 0 ? 0 : age,
      framesSinceLastHealth,
      errorsSinceLastHealth,
      suppressedSinceLastHealth,
    );
    var documentHidden = -1;
    try {
      final hidden = _readDocumentHidden();
      documentHidden = hidden == 0 || hidden == 1 ? hidden : -1;
    } on Object {
      // Visibility is optional context.
    }
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
      'lifecycleState': lifecycleStateCode(_lifecycle),
      'documentHidden': documentHidden,
      'framesSinceLastHealth': framesSinceLastHealth,
      'motionConstrained': _motionConstrained.value ? 1 : 0,
      'heapPressure': _heapPressure.index,
      if (heapBytes >= 0) 'canvasKitHeapBytes': heapBytes,
    });
  }

  void _observeHeap(DateTime now, int? bytes) {
    if (bytes == null || bytes < 0) return;
    final previous = _heapSamples.isEmpty ? null : _heapSamples.last;
    _heapSamples.add(_HeapSample(now, bytes));
    if (_heapSamples.length > heapSampleCount) _heapSamples.removeAt(0);
    final growthPerInterval = previous == null ? 0 : bytes - previous.bytes;
    final windowStart = now.subtract(heapGrowthWindow);
    var windowBase = bytes;
    for (final sample in _heapSamples) {
      if (!sample.at.isBefore(windowStart)) {
        windowBase = sample.bytes;
        break;
      }
    }
    final growthPerWindow = bytes - windowBase;
    if (bytes >= heapCriticalBytes) {
      _heapPressure = RendererHeapPressure.critical;
      if (!_motionConstrained.value) {
        _motionConstrained.value = true;
        _report({'event': 'flutter-motion-constrained', 'heapBytes': bytes});
      }
    } else if (growthPerInterval >= heapGrowthPerIntervalBytes ||
        growthPerWindow >= heapGrowthPerWindowBytes) {
      _heapPressure = RendererHeapPressure.growing;
    } else {
      _heapPressure = RendererHeapPressure.none;
    }
  }

  void _observeStall(
    int lastFrameAgeMs,
    int frames,
    int errors,
    int suppressed,
  ) {
    // The same gate the shell applies: errors "keep arriving" only when this
    // instance's suppressed counter moved (more than the ten reports a
    // minute it forwards) or a storm of them landed in the interval. One or
    // two isolated failures on a static screen are recorded, never a stall.
    final erroring = suppressed > 0 || errors >= stormErrorsPerInterval;
    if (!_active || frames > 0 || !erroring) {
      // Hidden or paused windows legitimately stop painting, a completed
      // frame proves the engine still draws, and a silent interval without
      // errors is a static screen. Each starts the span over; only a frame
      // re-arms a report that was already sent.
      _silentErrorIntervals = 0;
      _errorsInStallWindow = 0;
      if (frames > 0) _stallReported = false;
      return;
    }
    _silentErrorIntervals += 1;
    _errorsInStallWindow += errors;
    if (_stallReported || _silentErrorIntervals < stalledHealthIntervals) {
      return;
    }
    _stallReported = true;
    _report({
      'event': 'flutter-engine-stalled',
      'lastFrameAgeMs': lastFrameAgeMs,
      'errorsInWindow': _errorsInStallWindow,
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_installed) return;
    _lifecycle = state;
    _active = state == AppLifecycleState.resumed;
    final now = _now();
    if (_lifecycleWindowAt == null ||
        now.difference(_lifecycleWindowAt!) >= const Duration(minutes: 1)) {
      _lifecycleWindowAt = now;
      _lifecycleReports = 0;
    }
    if (_lifecycleReports >= maximumLifecycleEventsPerMinute) return;
    _lifecycleReports += 1;
    _report({
      'event': 'flutter-lifecycle',
      'lifecycleState': lifecycleStateCode(state),
    });
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

class _HeapSample {
  const _HeapSample(this.at, this.bytes);

  final DateTime at;
  final int bytes;
}

/// Owns observer/handler cleanup when the application is removed or replaced,
/// and exposes the diagnostics to descendants through [maybeOf].
class RendererDiagnosticsScope extends StatefulWidget {
  const RendererDiagnosticsScope({
    required this.diagnostics,
    required this.child,
    super.key,
  });

  final RendererDiagnostics diagnostics;
  final Widget child;

  /// The diagnostics installed above [context], or null outside a scope.
  static RendererDiagnostics? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_RendererDiagnosticsInherited>()
      ?.diagnostics;

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
  Widget build(BuildContext context) => _RendererDiagnosticsInherited(
    diagnostics: widget.diagnostics,
    child: widget.child,
  );
}

class _RendererDiagnosticsInherited extends InheritedWidget {
  const _RendererDiagnosticsInherited({
    required this.diagnostics,
    required super.child,
  });

  final RendererDiagnostics diagnostics;

  @override
  bool updateShouldNotify(_RendererDiagnosticsInherited oldWidget) =>
      !identical(oldWidget.diagnostics, diagnostics);
}
