import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('clawnsole')
external _DiagnosticShell? get _shell;

extension type _DiagnosticShell._(JSObject _) implements JSObject {
  external void reportDiagnostic(JSAny diagnostic);
}

@JS('flutterCanvasKit')
external _CanvasKitMemory? get _canvasKit;

extension type _CanvasKitMemory._(JSObject _) implements JSObject {
  @JS('HEAPU8')
  external JSObject? get heap;
  external JSNumber getDecodeCacheUsedBytes();
  external JSNumber getDecodeCacheLimitBytes();
}

_CanvasKitMemory? _observedCanvasKit;
final _failedNativeCounters = <String>{};

void _addCanvasKitMemory(Map<String, Object> diagnostic) {
  try {
    final kit = _canvasKit;
    if (!identical(kit, _observedCanvasKit)) {
      _observedCanvasKit = kit;
      _failedNativeCounters.clear();
    }
    if (kit == null) return;
    void add(
      String key,
      JSNumber? Function() read, {
      bool nativeCounter = false,
    }) {
      if (nativeCounter && _failedNativeCounters.contains(key)) return;
      try {
        final bytes = read()?.toDartDouble;
        if (bytes != null &&
            bytes.isFinite &&
            bytes >= 0 &&
            bytes <= 9007199254740991) {
          diagnostic[key] = bytes.round();
        }
      } on Object {
        // Different engine releases may omit or reject an optional metric.
        // A corrupted Wasm engine can also throw here. Do not repeatedly enter
        // a native getter that already failed; the scalar heap read still works.
        if (nativeCounter) _failedNativeCounters.add(key);
      }
    }

    // Read the scalar byteLength in JavaScript. Converting HEAPU8 itself to
    // Dart would copy the entire Wasm heap, potentially several gigabytes.
    add(
      'canvasKitHeapBytes',
      () => kit.heap?.getProperty<JSNumber?>('byteLength'.toJS),
    );
    if (kit.has('getDecodeCacheUsedBytes')) {
      add(
        'canvasKitDecodeCacheBytes',
        () => kit.getDecodeCacheUsedBytes(),
        nativeCounter: true,
      );
    }
    if (kit.has('getDecodeCacheLimitBytes')) {
      add(
        'canvasKitDecodeCacheLimitBytes',
        () => kit.getDecodeCacheLimitBytes(),
        nativeCounter: true,
      );
    }
  } on Object {
    // Missing CanvasKit or an unavailable renderer is diagnostic information
    // only; it must not prevent the ordinary health record from being sent.
  }
}

/// Feature detection keeps this renderer compatible with an older preload and
/// plain web test harnesses. Diagnostics never introduce an HTTP request.
void reportRendererDiagnostic(Map<String, Object> diagnostic) {
  try {
    final shell = _shell;
    if (shell == null || !shell.has('reportDiagnostic')) return;
    final payload = <String, Object>{...diagnostic};
    if (payload['event'] == 'flutter-health') _addCanvasKitMemory(payload);
    shell.reportDiagnostic(payload.jsify()!);
  } on Object {
    // A failed bridge must not interfere with normal error handling.
  }
}
