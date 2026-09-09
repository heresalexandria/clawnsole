import 'dart:ui' as ui;

import 'package:clawnsole/app/renderer_diagnostics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _mebibyte = 1024 * 1024;

/// Every numeric key a `flutter-health` record may carry. The desktop shell
/// allowlists these names; a new measurement must be added on both sides.
const _healthFields = [
  'appActive',
  'frameCount',
  'lastFrameAgeMs',
  'cacheBytes',
  'cacheImages',
  'liveImages',
  'pendingImages',
  'flutterErrorsSuppressed',
  'lifecycleState',
  'documentHidden',
  'framesSinceLastHealth',
  'motionConstrained',
  'heapPressure',
];

ui.FrameTiming _frame() => ui.FrameTiming(
  vsyncStart: 0,
  buildStart: 100,
  buildFinish: 200,
  rasterStart: 300,
  rasterFinish: 400,
  rasterFinishWallTime: 500,
);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  Iterable<Map<String, Object>> ofType(
    List<Map<String, Object>> events,
    String event,
  ) => events.where((e) => e['event'] == event);

  Map<String, Object> lastHealth(List<Map<String, Object>> events) =>
      ofType(events, 'flutter-health').last;

  test('errors preserve the prior handlers and omit private messages', () {
    final originalFlutter = FlutterError.onError;
    final originalPlatform = ui.PlatformDispatcher.instance.onError;
    final events = <Map<String, Object>>[];
    final flutterErrors = <FlutterErrorDetails>[];
    final platformErrors = <Object>[];
    void onFlutter(FlutterErrorDetails details) => flutterErrors.add(details);
    bool onPlatform(Object error, StackTrace stack) {
      platformErrors.add(error);
      return true;
    }

    FlutterError.onError = onFlutter;
    ui.PlatformDispatcher.instance.onError = onPlatform;
    final diagnostics = RendererDiagnostics(reporter: events.add)..install();
    try {
      final error = StateError('private prompt and provider response');
      final stack = StackTrace.fromString('a' * 10000);
      FlutterError.onError!(
        FlutterErrorDetails(exception: error, stack: stack),
      );
      expect(ui.PlatformDispatcher.instance.onError!(error, stack), isTrue);
      expect(flutterErrors.single.exception, same(error));
      expect(platformErrors.single, same(error));
      expect(events.map((event) => event['event']), [
        'flutter-error',
        'flutter-platform-error',
      ]);
      for (final event in events) {
        expect(event.keys, unorderedEquals(['event', 'errorType', 'stack']));
        expect(event['errorType'], 'StateError');
        expect(
          (event['stack']! as String).length,
          RendererDiagnostics.maximumStackCharacters,
        );
        expect(event.toString(), isNot(contains('private prompt')));
      }
    } finally {
      diagnostics.dispose();
      expect(FlutterError.onError, onFlutter);
      expect(ui.PlatformDispatcher.instance.onError, onPlatform);
      FlutterError.onError = originalFlutter;
      ui.PlatformDispatcher.instance.onError = originalPlatform;
    }
  });

  test('diagnostic failures never turn an unhandled error into a success', () {
    final original = ui.PlatformDispatcher.instance.onError;
    ui.PlatformDispatcher.instance.onError = null;
    final diagnostics = RendererDiagnostics(
      reporter: (_) => throw StateError('log unavailable'),
    )..install();
    try {
      expect(
        ui.PlatformDispatcher.instance.onError!(
          StateError('failed operation'),
          StackTrace.current,
        ),
        isFalse,
      );
      expect(
        ui.PlatformDispatcher.instance.onError!(
          StateError('failed'),
          _BrokenStack(),
        ),
        isFalse,
      );
    } finally {
      diagnostics.dispose();
      ui.PlatformDispatcher.instance.onError = original;
    }
  });

  test('a repeated rendering error has a bounded reporting rate', () {
    var now = DateTime.utc(2026, 9, 8);
    final original = ui.PlatformDispatcher.instance.onError;
    ui.PlatformDispatcher.instance.onError = null;
    final events = <Map<String, Object>>[];
    final diagnostics = RendererDiagnostics(
      reporter: events.add,
      now: () => now,
    )..install();
    try {
      for (var i = 0; i < 100; i++) {
        ui.PlatformDispatcher.instance.onError!(
          StateError('repeat'),
          StackTrace.empty,
        );
      }
      expect(
        events,
        hasLength(RendererDiagnostics.maximumErrorReportsPerMinute),
      );
      now = now.add(const Duration(minutes: 1));
      ui.PlatformDispatcher.instance.onError!(
        StateError('later'),
        StackTrace.empty,
      );
      expect(
        events,
        hasLength(RendererDiagnostics.maximumErrorReportsPerMinute + 1),
      );
    } finally {
      diagnostics.dispose();
      ui.PlatformDispatcher.instance.onError = original;
    }
  });

  testWidgets(
    'health continues while inactive without scheduling extra frames',
    (tester) async {
      final events = <Map<String, Object>>[];
      final diagnostics = RendererDiagnostics(
        reporter: events.add,
        now: () => binding.clock.now(),
      );
      await tester.pumpWidget(
        RendererDiagnosticsScope(
          diagnostics: diagnostics,
          child: const SizedBox.shrink(),
        ),
      );
      expect(events.single, {'event': 'flutter-ready'});
      diagnostics.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(events.last, {'event': 'flutter-lifecycle', 'lifecycleState': 1});
      binding.platformDispatcher.onReportTimings!([_frame()]);
      await tester.pump(const Duration(seconds: 59));
      expect(events, hasLength(2));
      expect(binding.hasScheduledFrame, isFalse);
      await tester.pump(const Duration(seconds: 1));
      final health = events.last;
      expect(health['event'], 'flutter-health');
      expect(health['appActive'], 1);
      expect(health['frameCount'], 1);
      expect(health['framesSinceLastHealth'], 1);
      expect(health['lastFrameAgeMs'], 60000);
      expect(health['lifecycleState'], 1);
      expect(health['motionConstrained'], 0);
      expect(health['heapPressure'], 0);
      // Native targets have neither a document nor a CanvasKit heap.
      expect(health['documentHidden'], -1);
      expect(health.keys, unorderedEquals(['event', ..._healthFields]));
      for (final entry in health.entries.where((e) => e.key != 'event')) {
        expect(entry.value, isA<int>());
        if (entry.key != 'documentHidden') expect(entry.value, isNonNegative);
      }
      diagnostics.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(events.last, {'event': 'flutter-lifecycle', 'lifecycleState': 4});
      await tester.pump(const Duration(minutes: 3));
      expect(events, hasLength(7));
      expect(events.last['event'], 'flutter-health');
      expect(events.last['appActive'], 0);
      expect(events.last['lifecycleState'], 4);
      expect(events.last['framesSinceLastHealth'], 0);
      expect(binding.hasScheduledFrame, isFalse);
      binding.platformDispatcher.onReportTimings!([_frame()]);
      diagnostics.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump(const Duration(minutes: 1));
      expect(events, hasLength(9));
      expect(events.last['appActive'], 1);
      expect(events.last['frameCount'], 2);
      expect(events.last['framesSinceLastHealth'], 1);
      expect(events.last['lastFrameAgeMs'], 60000);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(minutes: 2));
      expect(events, hasLength(9));
      expect(binding.hasScheduledFrame, isFalse);
    },
  );

  testWidgets('a release build failure displays safe recovery text', (
    tester,
  ) async {
    final original = FlutterError.onError;
    final originalBuilder = ErrorWidget.builder;
    final errors = <FlutterErrorDetails>[];
    FlutterError.onError = errors.add;
    final events = <Map<String, Object>>[];
    final diagnostics = RendererDiagnostics(
      reporter: events.add,
      showReleaseErrorWidget: true,
    );
    try {
      await tester.pumpWidget(
        RendererDiagnosticsScope(
          diagnostics: diagnostics,
          child: Builder(builder: (_) => throw StateError('PRIVATE_CONTENT')),
        ),
      );
      expect(errors, hasLength(1));
      expect(find.textContaining('could not be displayed'), findsOneWidget);
      expect(find.textContaining('PRIVATE_CONTENT'), findsNothing);
      expect(events.first['event'], 'flutter-error');
      expect(events.first.toString(), isNot(contains('PRIVATE_CONTENT')));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(ErrorWidget.builder, originalBuilder);
    } finally {
      diagnostics.dispose();
      FlutterError.onError = original;
    }
  });

  testWidgets(
    'health retains cumulative counts for errors suppressed in Dart',
    (tester) async {
      final original = ui.PlatformDispatcher.instance.onError;
      ui.PlatformDispatcher.instance.onError = null;
      final events = <Map<String, Object>>[];
      final diagnostics = RendererDiagnostics(
        reporter: events.add,
        now: () => binding.clock.now(),
      );
      try {
        await tester.pumpWidget(
          RendererDiagnosticsScope(
            diagnostics: diagnostics,
            child: const SizedBox.shrink(),
          ),
        );
        for (var i = 0; i < 100; i++) {
          ui.PlatformDispatcher.instance.onError!(
            StateError('repeat'),
            StackTrace.empty,
          );
        }
        await tester.pump(const Duration(minutes: 1));
        expect(events.last['flutterErrorsSuppressed'], 90);
        await tester.pump(const Duration(minutes: 1));
        expect(events.last['flutterErrorsSuppressed'], 90);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        diagnostics.dispose();
        ui.PlatformDispatcher.instance.onError = original;
      }
    },
  );

  testWidgets('health payloads carry only the documented numeric fields', (
    tester,
  ) async {
    final events = <Map<String, Object>>[];
    final diagnostics = RendererDiagnostics(
      reporter: events.add,
      now: () => binding.clock.now(),
      heapBytesReader: () => 300 * _mebibyte,
      documentHiddenReader: () => 1,
    );
    await tester.pumpWidget(
      RendererDiagnosticsScope(
        diagnostics: diagnostics,
        child: const SizedBox.shrink(),
      ),
    );
    await tester.pump(const Duration(minutes: 1));
    final health = lastHealth(events);
    expect(
      health.keys,
      unorderedEquals(['event', ..._healthFields, 'canvasKitHeapBytes']),
    );
    for (final entry in health.entries.where((e) => e.key != 'event')) {
      expect(entry.value, isA<int>());
      expect(entry.value, isNonNegative);
    }
    expect(health['documentHidden'], 1);
    expect(health['canvasKitHeapBytes'], 300 * _mebibyte);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a failing probe leaves health reporting intact', (tester) async {
    final events = <Map<String, Object>>[];
    final diagnostics = RendererDiagnostics(
      reporter: events.add,
      now: () => binding.clock.now(),
      heapBytesReader: () => throw StateError('engine gone'),
      documentHiddenReader: () => 7,
    );
    await tester.pumpWidget(
      RendererDiagnosticsScope(
        diagnostics: diagnostics,
        child: const SizedBox.shrink(),
      ),
    );
    await tester.pump(const Duration(minutes: 1));
    final health = lastHealth(events);
    expect(health.keys, unorderedEquals(['event', ..._healthFields]));
    expect(health['heapPressure'], 0);
    expect(health['documentHidden'], -1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'heap growth raises pressure and a critical heap latches motion off',
    (tester) async {
      var heap = 100 * _mebibyte;
      final events = <Map<String, Object>>[];
      final diagnostics = RendererDiagnostics(
        reporter: events.add,
        now: () => binding.clock.now(),
        heapBytesReader: () => heap,
      );
      var notifications = 0;
      diagnostics.motionConstrained.addListener(() => notifications += 1);
      await tester.pumpWidget(
        RendererDiagnosticsScope(
          diagnostics: diagnostics,
          child: const SizedBox.shrink(),
        ),
      );
      Future<Map<String, Object>> tick() async {
        await tester.pump(const Duration(minutes: 1));
        return lastHealth(events);
      }

      expect((await tick())['heapPressure'], 0);
      // One interval of 64 MiB growth is a leak signal on its own.
      heap += 64 * _mebibyte;
      expect((await tick())['heapPressure'], 1);
      expect(events.last['canvasKitHeapBytes'], 164 * _mebibyte);
      // A flat interval with under 256 MiB of growth in the window calms down.
      expect((await tick())['heapPressure'], 0);
      // Slow growth below the per-interval bar still trips the window bar.
      for (var minute = 4; minute <= 9; minute++) {
        heap += 30 * _mebibyte;
        expect((await tick())['heapPressure'], 0, reason: 'minute $minute');
      }
      heap += 30 * _mebibyte;
      final growing = await tick();
      expect(growing['heapPressure'], 1);
      expect(growing['motionConstrained'], 0);
      expect(diagnostics.motionConstrained.value, isFalse);
      expect(ofType(events, 'flutter-motion-constrained'), isEmpty);

      heap = RendererDiagnostics.heapCriticalBytes;
      final critical = await tick();
      expect(critical['heapPressure'], 2);
      expect(critical['motionConstrained'], 1);
      expect(diagnostics.motionConstrained.value, isTrue);
      expect(notifications, 1);
      final constrained = ofType(events, 'flutter-motion-constrained').single;
      expect(constrained, {
        'event': 'flutter-motion-constrained',
        'heapBytes': 1073741824,
      });
      expect(events.indexOf(constrained), lessThan(events.indexOf(critical)));

      heap += 8 * _mebibyte;
      expect((await tick())['heapPressure'], 2);
      expect(ofType(events, 'flutter-motion-constrained'), hasLength(1));
      // The latch never releases, even if a replaced engine reads small.
      heap = 10 * _mebibyte;
      final replaced = await tick();
      expect(replaced['heapPressure'], 0);
      expect(replaced['motionConstrained'], 1);
      expect(diagnostics.motionConstrained.value, isTrue);
      expect(notifications, 1);
      expect(ofType(events, 'flutter-motion-constrained'), hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'an active renderer without frames but with errors reports a stall',
    (tester) async {
      final original = ui.PlatformDispatcher.instance.onError;
      ui.PlatformDispatcher.instance.onError = null;
      final events = <Map<String, Object>>[];
      final diagnostics = RendererDiagnostics(
        reporter: events.add,
        now: () => binding.clock.now(),
      );
      void fail(int count) {
        for (var i = 0; i < count; i++) {
          ui.PlatformDispatcher.instance.onError!(
            StateError('frame failed'),
            StackTrace.empty,
          );
        }
      }

      try {
        await tester.pumpWidget(
          RendererDiagnosticsScope(
            diagnostics: diagnostics,
            child: const SizedBox.shrink(),
          ),
        );
        diagnostics.didChangeAppLifecycleState(AppLifecycleState.resumed);
        // Two silent intervals without any error is a static screen.
        await tester.pump(const Duration(minutes: 2));
        expect(ofType(events, 'flutter-engine-stalled'), isEmpty);
        // A few isolated errors on a static screen never count, however
        // many silent intervals they span.
        for (var minute = 0; minute < 3; minute++) {
          fail(5);
          await tester.pump(const Duration(minutes: 1));
        }
        expect(ofType(events, 'flutter-engine-stalled'), isEmpty);
        // Errors past the report cap during one silent interval are not yet
        // a stall.
        fail(30);
        await tester.pump(const Duration(minutes: 1));
        expect(ofType(events, 'flutter-engine-stalled'), isEmpty);
        // The same across a second consecutive silent interval is.
        fail(30);
        await tester.pump(const Duration(minutes: 1));
        expect(ofType(events, 'flutter-engine-stalled').single, {
          'event': 'flutter-engine-stalled',
          'lastFrameAgeMs': 420000,
          'errorsInWindow': 60,
        });
        // The report stays single-shot while the stall persists, including
        // across a quiet interval followed by more errors.
        fail(5);
        await tester.pump(const Duration(minutes: 2));
        fail(5);
        await tester.pump(const Duration(minutes: 1));
        fail(5);
        await tester.pump(const Duration(minutes: 1));
        expect(ofType(events, 'flutter-engine-stalled'), hasLength(1));
        expect(lastHealth(events)['flutterErrorsSuppressed'], 40);
        // A completed frame re-arms the detector.
        binding.platformDispatcher.onReportTimings!([_frame()]);
        await tester.pump(const Duration(minutes: 1));
        expect(lastHealth(events)['framesSinceLastHealth'], 1);
        fail(20);
        await tester.pump(const Duration(minutes: 1));
        expect(ofType(events, 'flutter-engine-stalled'), hasLength(1));
        fail(20);
        await tester.pump(const Duration(minutes: 1));
        expect(ofType(events, 'flutter-engine-stalled'), hasLength(2));
        expect(ofType(events, 'flutter-engine-stalled').last, {
          'event': 'flutter-engine-stalled',
          'lastFrameAgeMs': 180000,
          'errorsInWindow': 40,
        });
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        diagnostics.dispose();
        ui.PlatformDispatcher.instance.onError = original;
      }
    },
  );

  testWidgets('a hidden or paused renderer never reports a stall', (
    tester,
  ) async {
    final original = ui.PlatformDispatcher.instance.onError;
    ui.PlatformDispatcher.instance.onError = null;
    final events = <Map<String, Object>>[];
    final diagnostics = RendererDiagnostics(
      reporter: events.add,
      now: () => binding.clock.now(),
    );
    void fail() {
      // Enough to move the suppressed counter, as a frame-throwing engine
      // does every interval.
      for (var i = 0; i < 20; i++) {
        ui.PlatformDispatcher.instance.onError!(
          StateError('background failure'),
          StackTrace.empty,
        );
      }
    }

    try {
      await tester.pumpWidget(
        RendererDiagnosticsScope(
          diagnostics: diagnostics,
          child: const SizedBox.shrink(),
        ),
      );
      diagnostics.didChangeAppLifecycleState(AppLifecycleState.hidden);
      for (var minute = 0; minute < 5; minute++) {
        fail();
        await tester.pump(const Duration(minutes: 1));
      }
      expect(ofType(events, 'flutter-engine-stalled'), isEmpty);
      // The silent span restarts at resume rather than inheriting the
      // hidden minutes.
      diagnostics.didChangeAppLifecycleState(AppLifecycleState.resumed);
      fail();
      await tester.pump(const Duration(minutes: 1));
      expect(ofType(events, 'flutter-engine-stalled'), isEmpty);
      fail();
      await tester.pump(const Duration(minutes: 1));
      expect(ofType(events, 'flutter-engine-stalled'), hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      diagnostics.dispose();
      ui.PlatformDispatcher.instance.onError = original;
    }
  });

  testWidgets('lifecycle transitions are logged as codes with a bounded rate', (
    tester,
  ) async {
    final events = <Map<String, Object>>[];
    final diagnostics = RendererDiagnostics(
      reporter: events.add,
      now: () => binding.clock.now(),
    );
    await tester.pumpWidget(
      RendererDiagnosticsScope(
        diagnostics: diagnostics,
        child: const SizedBox.shrink(),
      ),
    );
    expect(RendererDiagnostics.lifecycleStateCode(null), 1);
    for (final (state, code) in [
      (AppLifecycleState.detached, 0),
      (AppLifecycleState.resumed, 1),
      (AppLifecycleState.inactive, 2),
      (AppLifecycleState.hidden, 3),
      (AppLifecycleState.paused, 4),
    ]) {
      diagnostics.didChangeAppLifecycleState(state);
      expect(events.last, {
        'event': 'flutter-lifecycle',
        'lifecycleState': code,
      });
    }
    for (var i = 0; i < 40; i++) {
      diagnostics.didChangeAppLifecycleState(
        i.isEven ? AppLifecycleState.inactive : AppLifecycleState.resumed,
      );
    }
    expect(
      ofType(events, 'flutter-lifecycle'),
      hasLength(RendererDiagnostics.maximumLifecycleEventsPerMinute),
    );
    // The suppressed transitions still update the health record.
    await tester.pump(const Duration(minutes: 1));
    expect(lastHealth(events)['lifecycleState'], 1);
    expect(lastHealth(events)['appActive'], 1);
    diagnostics.didChangeAppLifecycleState(AppLifecycleState.hidden);
    expect(
      ofType(events, 'flutter-lifecycle'),
      hasLength(RendererDiagnostics.maximumLifecycleEventsPerMinute + 1),
    );
    expect(events.last, {'event': 'flutter-lifecycle', 'lifecycleState': 3});
    await tester.pump(const Duration(minutes: 1));
    expect(lastHealth(events)['lifecycleState'], 3);
    expect(lastHealth(events)['appActive'], 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('descendants can look up the installed diagnostics', (
    tester,
  ) async {
    final diagnostics = RendererDiagnostics(reporter: (_) {});
    RendererDiagnostics? inside;
    RendererDiagnostics? outside;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          outside = RendererDiagnosticsScope.maybeOf(context);
          return RendererDiagnosticsScope(
            diagnostics: diagnostics,
            child: Builder(
              builder: (context) {
                inside = RendererDiagnosticsScope.maybeOf(context);
                return const SizedBox.shrink();
              },
            ),
          );
        },
      ),
    );
    expect(inside, same(diagnostics));
    expect(outside, isNull);
    expect(inside!.motionConstrained.value, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _BrokenStack implements StackTrace {
  @override
  String toString() => throw StateError('cannot serialize');
}
