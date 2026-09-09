import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

/// Test seam for [createHardLink]: when set, it replaces the platform call so
/// a test can force the "filesystem refused" path without a special volume.
bool Function(String existingPath, String linkPath)? hardLinkOverrideForTesting;

/// Creates [linkPath] as a second directory entry for the file behind
/// [existingPath] — a hard link. This is deliberately not `dart:io`'s [Link],
/// which creates a *symbolic* link: a symlink named `.bak` would follow the
/// canonical name and read the new revision the moment the canonical file is
/// replaced, keeping no previous copy at all. A hard link keeps the old inode
/// alive under the backup name while a rename swaps the canonical name to the
/// new inode, so a backup costs a directory entry instead of another copy of
/// every byte.
///
/// Returns false instead of throwing when the platform, the filesystem
/// (FAT/exFAT, some network shares) or the path refuses, so callers can fall
/// back to copying. Nothing else is written or removed.
bool createHardLink(String existingPath, String linkPath) {
  final override = hardLinkOverrideForTesting;
  if (override != null) return override(existingPath, linkPath);
  final linker = _platformLinker();
  if (linker == null) return false;
  try {
    return linker.link(existingPath, linkPath);
  } on Object {
    return false;
  }
}

_Linker? _linker;
var _linkerResolved = false;

_Linker? _platformLinker() {
  if (!_linkerResolved) {
    _linkerResolved = true;
    try {
      _linker = Platform.isWindows ? _WindowsLinker() : _PosixLinker();
    } on Object {
      // No usable symbol on this runtime: every call falls back to copying.
      _linker = null;
    }
  }
  return _linker;
}

abstract interface class _Linker {
  bool link(String existingPath, String linkPath);
}

typedef _PosixLinkNative = Int32 Function(Pointer<Uint8>, Pointer<Uint8>);
typedef _PosixLink = int Function(Pointer<Uint8>, Pointer<Uint8>);
typedef _MallocNative = Pointer<Uint8> Function(Size);
typedef _Malloc = Pointer<Uint8> Function(int);
typedef _FreeNative = Void Function(Pointer<Uint8>);
typedef _Free = void Function(Pointer<Uint8>);

/// `link(2)` from the C library already loaded into the process (macOS, iOS,
/// Linux, Android). Strings are copied into C memory from the same library so
/// no extra FFI helper package is needed.
final class _PosixLinker implements _Linker {
  _PosixLinker() : this._(DynamicLibrary.process());

  _PosixLinker._(DynamicLibrary library)
    : _link = library.lookupFunction<_PosixLinkNative, _PosixLink>('link'),
      _malloc = library.lookupFunction<_MallocNative, _Malloc>('malloc'),
      _free = library.lookupFunction<_FreeNative, _Free>('free');

  final _PosixLink _link;
  final _Malloc _malloc;
  final _Free _free;

  @override
  bool link(String existingPath, String linkPath) {
    final existing = _cString(existingPath);
    try {
      final target = _cString(linkPath);
      try {
        return _link(existing, target) == 0;
      } finally {
        _free(target);
      }
    } finally {
      _free(existing);
    }
  }

  Pointer<Uint8> _cString(String value) {
    final bytes = utf8.encode(value);
    final pointer = _malloc(bytes.length + 1);
    if (pointer == nullptr) throw StateError('malloc failed');
    pointer.asTypedList(bytes.length + 1)
      ..setAll(0, bytes)
      ..[bytes.length] = 0;
    return pointer;
  }
}

typedef _CreateHardLinkNative =
    Int32 Function(Pointer<Uint16>, Pointer<Uint16>, Pointer<Void>);
typedef _CreateHardLink =
    int Function(Pointer<Uint16>, Pointer<Uint16>, Pointer<Void>);
typedef _WideMallocNative = Pointer<Uint16> Function(Size);
typedef _WideMalloc = Pointer<Uint16> Function(int);
typedef _WideFreeNative = Void Function(Pointer<Uint16>);
typedef _WideFree = void Function(Pointer<Uint16>);

/// `CreateHardLinkW` on NTFS; other volumes answer false and callers copy.
final class _WindowsLinker implements _Linker {
  _WindowsLinker()
    : this._(
        DynamicLibrary.open('kernel32.dll'),
        DynamicLibrary.open('ucrtbase.dll'),
      );

  _WindowsLinker._(DynamicLibrary kernel32, DynamicLibrary runtime)
    : _create = kernel32.lookupFunction<_CreateHardLinkNative, _CreateHardLink>(
        'CreateHardLinkW',
      ),
      _malloc = runtime.lookupFunction<_WideMallocNative, _WideMalloc>(
        'malloc',
      ),
      _free = runtime.lookupFunction<_WideFreeNative, _WideFree>('free');

  final _CreateHardLink _create;
  final _WideMalloc _malloc;
  final _WideFree _free;

  @override
  bool link(String existingPath, String linkPath) {
    final existing = _wideString(existingPath);
    try {
      final target = _wideString(linkPath);
      try {
        // Argument order is (new link name, existing file).
        return _create(target, existing, nullptr) != 0;
      } finally {
        _free(target);
      }
    } finally {
      _free(existing);
    }
  }

  Pointer<Uint16> _wideString(String value) {
    final units = value.codeUnits;
    final pointer = _malloc((units.length + 1) * 2);
    if (pointer == nullptr) throw StateError('malloc failed');
    pointer.asTypedList(units.length + 1)
      ..setAll(0, units)
      ..[units.length] = 0;
    return pointer;
  }
}
