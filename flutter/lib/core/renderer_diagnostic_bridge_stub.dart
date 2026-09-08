/// Installed native targets retain their platform error reporting. The desktop
/// shell owns the bounded diagnostic log used by its internal web renderer.
void reportRendererDiagnostic(Map<String, Object> diagnostic) {}

/// Native renderers have no CanvasKit Wasm heap to watch.
int? readCanvasKitHeapBytes() => null;

/// Document visibility only exists for the web renderer; -1 means unknown.
int readDocumentHidden() => -1;
