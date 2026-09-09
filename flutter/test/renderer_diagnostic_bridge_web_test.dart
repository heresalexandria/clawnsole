@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:clawnsole/core/renderer_diagnostic_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

@JS('clawnsole')
external JSAny? get _shell;
@JS('clawnsole')
external set _shell(JSAny? value);

@JS('flutterCanvasKit')
external JSAny? get _canvasKit;
@JS('flutterCanvasKit')
external set _canvasKit(JSAny? value);

void main() {
  test(
    'diagnostics support absent and older preloads without network work',
    () {
      final previous = _shell;
      try {
        _shell = null;
        reportRendererDiagnostic({'event': 'flutter-ready'});
        _shell = JSObject();
        reportRendererDiagnostic({'event': 'flutter-ready'});
        _shell = JSObject()..setProperty('reportDiagnostic'.toJS, 1.toJS);
        reportRendererDiagnostic({'event': 'flutter-ready'});
      } finally {
        _shell = previous;
      }
    },
  );

  test('diagnostics use the single guarded desktop bridge', () {
    final previous = _shell;
    final previousKit = _canvasKit;
    final received = <Object?>[];
    final callback = ((JSAny value) => received.add(value.dartify())).toJS;
    try {
      _canvasKit = null;
      _shell = JSObject()..setProperty('reportDiagnostic'.toJS, callback);
      reportRendererDiagnostic({'event': 'flutter-health', 'frameCount': 3});
      expect(received, [
        {'event': 'flutter-health', 'frameCount': 3},
      ]);
    } finally {
      _shell = previous;
      _canvasKit = previousKit;
    }
  });

  test('health reads CanvasKit scalar counters without copying its heap', () {
    final previous = _shell;
    final previousKit = _canvasKit;
    final received = <Object?>[];
    final callback = ((JSAny value) => received.add(value.dartify())).toJS;
    try {
      _shell = JSObject()..setProperty('reportDiagnostic'.toJS, callback);
      // A heap-shaped object with no actual backing bytes proves this code
      // reads byteLength rather than materializing a Dart typed array.
      final heap = JSObject()..setProperty('byteLength'.toJS, 2147483648.toJS);
      _canvasKit = JSObject()
        ..setProperty('HEAPU8'.toJS, heap)
        ..setProperty('getDecodeCacheUsedBytes'.toJS, (() => 1024.toJS).toJS)
        ..setProperty('getDecodeCacheLimitBytes'.toJS, (() => 2048.toJS).toJS);
      final event = <String, Object>{
        'event': 'flutter-health',
        'frameCount': 3,
      };
      reportRendererDiagnostic(event);
      expect(received.single, {
        'event': 'flutter-health',
        'frameCount': 3,
        'canvasKitHeapBytes': 2147483648,
        'canvasKitDecodeCacheBytes': 1024,
        'canvasKitDecodeCacheLimitBytes': 2048,
      });
      expect(event, {'event': 'flutter-health', 'frameCount': 3});
    } finally {
      _shell = previous;
      _canvasKit = previousKit;
    }
  });

  test('the heap watchdog reads the same scalar byte length', () {
    final previousKit = _canvasKit;
    try {
      _canvasKit = null;
      expect(readCanvasKitHeapBytes(), isNull);
      _canvasKit = JSObject();
      expect(readCanvasKitHeapBytes(), isNull);
      final heap = JSObject()..setProperty('byteLength'.toJS, 1073741824.toJS);
      _canvasKit = JSObject()..setProperty('HEAPU8'.toJS, heap);
      expect(readCanvasKitHeapBytes(), 1073741824);
      heap.setProperty('byteLength'.toJS, double.nan.toJS);
      expect(readCanvasKitHeapBytes(), isNull);
      heap.setProperty('byteLength'.toJS, 'large'.toJS);
      expect(readCanvasKitHeapBytes(), isNull);
    } finally {
      _canvasKit = previousKit;
    }
  });

  test('document visibility is reported as a small code', () {
    // A browser test page is a real document; only its visibility varies.
    expect(readDocumentHidden(), anyOf(0, 1));
  });

  test('unavailable CanvasKit counters do not suppress health reporting', () {
    final previous = _shell;
    final previousKit = _canvasKit;
    final received = <Object?>[];
    final callback = ((JSAny value) => received.add(value.dartify())).toJS;
    try {
      _shell = JSObject()..setProperty('reportDiagnostic'.toJS, callback);
      _canvasKit = JSObject()
        ..setProperty('getDecodeCacheUsedBytes'.toJS, 1.toJS)
        ..setProperty(
          'getDecodeCacheLimitBytes'.toJS,
          (() => double.nan.toJS).toJS,
        );
      reportRendererDiagnostic({'event': 'flutter-health', 'frameCount': 3});
      expect(received.single, {'event': 'flutter-health', 'frameCount': 3});
    } finally {
      _shell = previous;
      _canvasKit = previousKit;
    }
  });

  test(
    'a failed native counter is skipped until the CanvasKit instance changes',
    () {
      final previous = _shell;
      final previousKit = _canvasKit;
      final received = <Object?>[];
      var failedCalls = 0;
      var healthyCalls = 0;
      JSNumber failRead() {
        failedCalls += 1;
        throw StateError('corrupted native engine');
      }

      final callback = ((JSAny value) => received.add(value.dartify())).toJS;
      try {
        _shell = JSObject()..setProperty('reportDiagnostic'.toJS, callback);
        final heap = JSObject()
          ..setProperty('byteLength'.toJS, 2147483648.toJS);
        _canvasKit = JSObject()
          ..setProperty('HEAPU8'.toJS, heap)
          ..setProperty('getDecodeCacheUsedBytes'.toJS, failRead.toJS)
          ..setProperty(
            'getDecodeCacheLimitBytes'.toJS,
            (() {
              healthyCalls += 1;
              return 2048.toJS;
            }).toJS,
          );
        for (var i = 0; i < 3; i++) {
          reportRendererDiagnostic({'event': 'flutter-health'});
        }
        expect(failedCalls, 1);
        expect(healthyCalls, 3);
        expect(
          received,
          everyElement({
            'event': 'flutter-health',
            'canvasKitHeapBytes': 2147483648,
            'canvasKitDecodeCacheLimitBytes': 2048,
          }),
        );
        _canvasKit = JSObject()
          ..setProperty('getDecodeCacheUsedBytes'.toJS, (() => 1024.toJS).toJS);
        reportRendererDiagnostic({'event': 'flutter-health'});
        expect(received.last, {
          'event': 'flutter-health',
          'canvasKitDecodeCacheBytes': 1024,
        });
      } finally {
        _shell = previous;
        _canvasKit = previousKit;
      }
    },
  );
}
