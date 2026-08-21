import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clawnsole/core/encrypted_file_secure_value_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;
  late File file;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'clawnsole-secure-values-',
    );
    file = File('${temporaryDirectory.path}/secure-values.json');
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('round trips values without writing plaintext', () async {
    final store = EncryptedFileSecureValueStore(
      file: file,
      deviceKey: _deviceKey(1),
    );

    await store.write('vault.dek', 'plaintext-secret-value');

    expect(await store.read('vault.dek'), 'plaintext-secret-value');
    final encoded = await file.readAsString();
    expect(encoded, isNot(contains('plaintext-secret-value')));
    expect(jsonDecode(encoded), containsPair('version', 1));
    if (!Platform.isWindows) {
      expect((await file.stat()).modeString(), endsWith('rw-------'));
    }
  });

  test('serializes concurrent writes and deletes the empty sidecar', () async {
    final store = EncryptedFileSecureValueStore(
      file: file,
      deviceKey: _deviceKey(2),
    );

    await Future.wait(<Future<void>>[
      store.write('one', 'first'),
      store.write('two', 'second'),
      store.write('three', 'third'),
    ]);

    expect(await store.read('one'), 'first');
    expect(await store.read('two'), 'second');
    expect(await store.read('three'), 'third');
    await store.delete('one');
    await store.delete('two');
    await store.delete('three');
    expect(await file.exists(), isFalse);
  });

  test('wrong device key fails without changing the file', () async {
    final store = EncryptedFileSecureValueStore(
      file: file,
      deviceKey: _deviceKey(3),
    );
    await store.write('vault.dek', 'secret');
    final original = await file.readAsBytes();
    final wrongStore = EncryptedFileSecureValueStore(
      file: file,
      deviceKey: _deviceKey(4),
    );

    await expectLater(wrongStore.read('vault.dek'), throwsStateError);
    expect(await file.readAsBytes(), original);
  });

  test('malformed sidecar fails without overwriting it', () async {
    await file.writeAsString('{"not":"a secure sidecar"}');
    final original = await file.readAsBytes();
    final store = EncryptedFileSecureValueStore(
      file: file,
      deviceKey: _deviceKey(5),
    );

    await expectLater(store.write('vault.dek', 'secret'), throwsStateError);
    expect(await file.readAsBytes(), original);
  });

  test('validates device keys, value keys, and value size', () async {
    expect(
      () => EncryptedFileSecureValueStore(file: file, deviceKey: 'bad'),
      throwsArgumentError,
    );
    final store = EncryptedFileSecureValueStore(
      file: file,
      deviceKey: _deviceKey(6),
    );

    expect(() => store.read('../unsafe'), throwsArgumentError);
    expect(
      () => store.write('valid', 'x' * (64 * 1024 + 1)),
      throwsArgumentError,
    );
  });
}

String _deviceKey(int seed) => base64UrlEncode(
  Uint8List.fromList(List<int>.generate(32, (index) => seed + index)),
).replaceAll('=', '');
