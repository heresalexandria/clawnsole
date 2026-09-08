import 'dart:ui' as ui;

import 'package:clawnsole/app/renderer_diagnostics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

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
      binding.platformDispatcher.onReportTimings!([
        ui.FrameTiming(
          vsyncStart: 0,
          buildStart: 100,
          buildFinish: 200,
          rasterStart: 300,
          rasterFinish: 400,
          rasterFinishWallTime: 500,
        ),
      ]);
      await tester.pump(const Duration(seconds: 59));
      expect(events, hasLength(1));
      expect(binding.hasScheduledFrame, isFalse);
      await tester.pump(const Duration(seconds: 1));
      final health = events.last;
      expect(health['event'], 'flutter-health');
      expect(health['appActive'], 1);
      expect(health['frameCount'], 1);
      expect(health['lastFrameAgeMs'], 60000);
      expect(
        health.keys,
        unorderedEquals([
          'event',
          'appActive',
          'frameCount',
          'lastFrameAgeMs',
          'cacheBytes',
          'cacheImages',
          'liveImages',
          'pendingImages',
          'flutterErrorsSuppressed',
        ]),
      );
      for (final value in health.entries.where(
        (entry) => entry.key != 'event',
      )) {
        expect(value.value, isNonNegative);
      }
      diagnostics.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pump(const Duration(minutes: 3));
      expect(events, hasLength(5));
      expect(events.last['appActive'], 0);
      expect(binding.hasScheduledFrame, isFalse);
      binding.platformDispatcher.onReportTimings!([
        ui.FrameTiming(
          vsyncStart: 0,
          buildStart: 100,
          buildFinish: 200,
          rasterStart: 300,
          rasterFinish: 400,
          rasterFinishWallTime: 500,
        ),
      ]);
      diagnostics.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump(const Duration(minutes: 1));
      expect(events, hasLength(6));
      expect(events.last['appActive'], 1);
      expect(events.last['frameCount'], 2);
      expect(events.last['lastFrameAgeMs'], 60000);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(minutes: 2));
      expect(events, hasLength(6));
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
}

class _BrokenStack implements StackTrace {
  @override
  String toString() => throw StateError('cannot serialize');
}
