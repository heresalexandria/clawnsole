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

@JS('document')
external _VisibilityDocument? get _document;

extension type _VisibilityDocument._(JSObject _) implements JSObject {
  external JSAny? get visibilityState;
}

_CanvasKitMemory? _observedCanvasKit;
final _failedNativeCounters = <String>{};

/// Accepts only a finite, non-negative, safe-integer byte count.
int? _byteCount(JSNumber? value) {
  final bytes = value?.toDartDouble;
  if (bytes == null ||
      !bytes.isFinite ||
      bytes < 0 ||
      bytes > 9007199254740991) {
    return null;
  }
  return bytes.round();
}

// Read the scalar byteLength in JavaScript. Converting HEAPU8 itself to Dart
// would copy the entire Wasm heap, potentially several gigabytes.
int? _heapBytes(_CanvasKitMemory kit) =>
    _byteCount(kit.heap?.getProperty<JSNumber?>('byteLength'.toJS));

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
        final bytes = _byteCount(read());
        if (bytes != null) diagnostic[key] = bytes;
      } on Object {
        // Different engine releases may omit or reject an optional metric.
        // A corrupted Wasm engine can also throw here. Do not repeatedly enter
        // a native getter that already failed; the scalar heap read still works.
        if (nativeCounter) _failedNativeCounters.add(key);
      }
    }

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

/// The allocated CanvasKit Wasm heap size in bytes, read as a scalar without
/// entering native code or copying the heap. Null when CanvasKit is absent.
int? readCanvasKitHeapBytes() {
  try {
    final kit = _canvasKit;
    if (kit == null) return null;
    return _heapBytes(kit);
  } on Object {
    return null;
  }
}

/// 1 when the document is hidden, 0 when visible, -1 when unknown.
int readDocumentHidden() {
  try {
    final state = _document?.visibilityState;
    if (state == null || !state.typeofEquals('string')) return -1;
    switch ((state as JSString).toDart) {
      case 'hidden':
        return 1;
      case 'visible':
        return 0;
      default:
        return -1;
    }
  } on Object {
    return -1;
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
