import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'secure_value_store.dart';

const _secureValuesFormat = 'app.clawnsole.secure-values';
const _secureValuesVersion = 1;
const _secureValuesAlgorithm = 'xchacha20-poly1305';
const _keyBytes = 32;
const _nonceBytes = 24;
const _macBytes = 16;
const _maximumFileBytes = 1024 * 1024;
const _maximumPlaintextBytes = 768 * 1024;
const _maximumValueBytes = 64 * 1024;

/// A small encrypted key/value sidecar for the desktop companion.
///
/// [deviceKey] is the canonical base64url encoding of 32 random bytes. The
/// Electron shell protects that key with the operating system's credential
/// store and supplies it to the companion once, over stdin, at launch.
class EncryptedFileSecureValueStore implements SecureValueStore {
  EncryptedFileSecureValueStore({required this.file, required String deviceKey})
    : _deviceKey = _decodeDeviceKey(deviceKey);

  final File file;
  final Uint8List _deviceKey;
  final Cipher _cipher = Xchacha20.poly1305Aead();
  final Random _random = Random.secure();
  Future<void> _queue = Future<void>.value();

  @override
  Future<String?> read(String key) {
    _validateValueKey(key);
    return _serialized<String?>(() async => (await _readValues())[key]);
  }

  @override
  Future<void> write(String key, String value) {
    _validateValueKey(key);
    if (utf8.encode(value).length > _maximumValueBytes) {
      throw ArgumentError.value(
        value.length,
        'value',
        'The secure value is too large.',
      );
    }
    return _serialized<void>(() async {
      final values = await _readValues();
      values[key] = value;
      await _writeValues(values);
    });
  }

  @override
  Future<void> delete(String key) {
    _validateValueKey(key);
    return _serialized<void>(() async {
      final values = await _readValues();
      if (values.remove(key) == null) return;
      if (values.isEmpty) {
        if (await file.exists()) await file.delete();
        return;
      }
      await _writeValues(values);
    });
  }

  Future<T> _serialized<T>(Future<T> Function() callback) {
    final operation = _queue.then((_) => callback());
    _queue = operation.then<void>((_) {}, onError: (_) {});
    return operation;
  }

  Future<Map<String, String>> _readValues() async {
    if (!await file.exists()) return <String, String>{};
    try {
      final length = await file.length();
      if (length <= 0 || length > _maximumFileBytes) {
        throw const FormatException();
      }
      final source = await file.readAsString();
      final decoded = jsonDecode(source);
      if (decoded is! Map<Object?, Object?> ||
          decoded['format'] != _secureValuesFormat ||
          decoded['version'] != _secureValuesVersion ||
          decoded['algorithm'] != _secureValuesAlgorithm) {
        throw const FormatException();
      }
      final nonce = _decodeField(decoded['nonce'], _nonceBytes);
      final ciphertext = _decodeField(
        decoded['ciphertext'],
        null,
        maximumBytes: _maximumPlaintextBytes,
      );
      final mac = _decodeField(decoded['mac'], _macBytes);
      final secretKey = SecretKeyData(
        Uint8List.fromList(_deviceKey),
        overwriteWhenDestroyed: true,
        debugLabel: 'Clawnsole companion device key',
      );
      List<int> cleartext;
      try {
        cleartext = await _cipher.decrypt(
          SecretBox(ciphertext, nonce: nonce, mac: Mac(mac)),
          secretKey: secretKey,
          aad: _associatedData,
        );
      } finally {
        secretKey.destroy();
      }
      if (cleartext.length > _maximumPlaintextBytes) {
        throw const FormatException();
      }
      final contents = jsonDecode(utf8.decode(cleartext));
      if (contents is! Map<Object?, Object?>) throw const FormatException();
      final values = <String, String>{};
      for (final entry in contents.entries) {
        if (entry.key is! String || entry.value is! String) {
          throw const FormatException();
        }
        final key = entry.key! as String;
        final value = entry.value! as String;
        _validateValueKey(key);
        if (utf8.encode(value).length > _maximumValueBytes) {
          throw const FormatException();
        }
        values[key] = value;
      }
      return values;
    } on Object {
      throw StateError('The encrypted device storage could not be opened.');
    }
  }

  Future<void> _writeValues(Map<String, String> values) async {
    final cleartext = utf8.encode(jsonEncode(values));
    if (cleartext.length > _maximumPlaintextBytes) {
      throw StateError('The encrypted device storage is full.');
    }
    final secretKey = SecretKeyData(
      Uint8List.fromList(_deviceKey),
      overwriteWhenDestroyed: true,
      debugLabel: 'Clawnsole companion device key',
    );
    SecretBox box;
    try {
      box = await _cipher.encrypt(
        cleartext,
        secretKey: secretKey,
        nonce: Uint8List.fromList(
          List<int>.generate(_nonceBytes, (_) => _random.nextInt(256)),
        ),
        aad: _associatedData,
      );
    } finally {
      secretKey.destroy();
    }
    final source = jsonEncode(<String, Object?>{
      'format': _secureValuesFormat,
      'version': _secureValuesVersion,
      'algorithm': _secureValuesAlgorithm,
      'nonce': _encodeBytes(box.nonce),
      'ciphertext': _encodeBytes(box.cipherText),
      'mac': _encodeBytes(box.mac.bytes),
    });
    if (utf8.encode(source).length > _maximumFileBytes) {
      throw StateError('The encrypted device storage is full.');
    }

    await file.parent.create(recursive: true);
    final suffix = List<int>.generate(
      12,
      (_) => _random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    final temporary = File('${file.path}.$suffix.tmp');
    try {
      await temporary.writeAsString(source, flush: true);
      if (!Platform.isWindows) {
        final result = await Process.run('chmod', <String>[
          '600',
          temporary.path,
        ]);
        if (result.exitCode != 0) {
          throw FileSystemException(
            'Could not protect encrypted device storage.',
            temporary.path,
          );
        }
      }
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}

final List<int> _associatedData = utf8.encode(
  '$_secureValuesFormat:$_secureValuesVersion:$_secureValuesAlgorithm',
);

void _validateValueKey(String key) {
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$').hasMatch(key)) {
    throw ArgumentError.value(key, 'key', 'The secure value key is invalid.');
  }
}

Uint8List _decodeDeviceKey(String value) {
  Uint8List bytes;
  try {
    bytes = _decodeBase64Url(value);
  } on FormatException {
    throw ArgumentError.value(
      value.length,
      'deviceKey',
      'The device key must be 32 canonical base64url bytes.',
    );
  }
  if (bytes.length != _keyBytes || _encodeBytes(bytes) != value) {
    throw ArgumentError.value(
      value.length,
      'deviceKey',
      'The device key must be 32 canonical base64url bytes.',
    );
  }
  return bytes;
}

Uint8List _decodeField(Object? value, int? exactBytes, {int? maximumBytes}) {
  if (value is! String) throw const FormatException();
  final bytes = _decodeBase64Url(value);
  if ((exactBytes != null && bytes.length != exactBytes) ||
      (maximumBytes != null && bytes.length > maximumBytes) ||
      _encodeBytes(bytes) != value) {
    throw const FormatException();
  }
  return bytes;
}

Uint8List _decodeBase64Url(String value) {
  try {
    return Uint8List.fromList(base64Url.decode(base64Url.normalize(value)));
  } on FormatException {
    throw const FormatException();
  }
}

String _encodeBytes(List<int> bytes) =>
    base64UrlEncode(bytes).replaceAll('=', '');
