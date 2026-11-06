import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

typedef _NativeMalloc = Pointer<Void> Function(IntPtr);
typedef _DartMalloc = Pointer<Void> Function(int);
typedef _NativeFree = Void Function(Pointer<Void>);
typedef _DartFree = void Function(Pointer<Void>);
typedef _NativeChmod = Int32 Function(Pointer<Uint8>, Uint32);
typedef _DartChmod = int Function(Pointer<Uint8>, int);

void protectTemporaryMediaJournal(String path) {
  // Windows uses the enclosing per-user application-data ACL, not POSIX mode.
  if (Platform.isWindows) return;
  final library = DynamicLibrary.process();
  final malloc = library.lookupFunction<_NativeMalloc, _DartMalloc>('malloc');
  final free = library.lookupFunction<_NativeFree, _DartFree>('free');
  final chmod = library.lookupFunction<_NativeChmod, _DartChmod>('chmod');
  final bytes = utf8.encode(path);
  final pointer = malloc(bytes.length + 1).cast<Uint8>();
  if (pointer.address == 0) {
    throw StateError('Could not protect the temporary media recovery journal.');
  }
  try {
    pointer.asTypedList(bytes.length + 1)
      ..setRange(0, bytes.length, bytes)
      ..[bytes.length] = 0;
    if (chmod(pointer, 384) != 0) {
      throw FileSystemException(
        'Could not protect the temporary media recovery journal.',
        path,
      );
    }
  } finally {
    free(pointer.cast<Void>());
  }
}
