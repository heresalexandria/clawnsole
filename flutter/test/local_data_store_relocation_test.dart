import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// The io implementation is imported directly: this suite exercises the
// dart:io pointer-file and relocation behavior on the test VM.
import 'package:clawnsole/core/local_data_store_io.dart';
import 'package:clawnsole/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final separator = Platform.pathSeparator;

  Future<Directory> temporary(String label) async {
    final directory = await Directory.systemTemp.createTemp(label);
    addTearDown(() => directory.delete(recursive: true));
    return directory;
  }

  String rootPath(Directory documents) =>
      '${documents.path}${separator}Clawnsole';

  File dataFile(String directory) =>
      File('$directory${separator}clawnsole.json');

  File pointerFile(Directory documents) => File(
    '${rootPath(documents)}$separator${LocalDataStore.locationFileName}',
  );

  StoredData library(String provider) =>
      StoredData(preferences: AppPreferences(provider: provider));

  test('stores data under Documents/Clawnsole by default', () async {
    final documents = await temporary('clawnsole-documents.');
    final store = LocalDataStore(documentsDirectory: documents);

    await store.write(library('ltx'));

    expect(dataFile(rootPath(documents)).existsSync(), isTrue);
    expect((await store.stats(0)).path, dataFile(rootPath(documents)).path);
    expect((await store.read()).preferences.provider, 'ltx');
  });

  test('follows a valid pointer file and ignores a broken one', () async {
    final documents = await temporary('clawnsole-documents.');
    final portable = await temporary('clawnsole-portable.');
    dataFile(portable.path).writeAsStringSync(library('artcraft').encode());
    Directory(rootPath(documents)).createSync(recursive: true);
    dataFile(rootPath(documents)).writeAsStringSync(library('bfl').encode());

    pointerFile(documents).writeAsStringSync(
      jsonEncode(<String, String>{'dataDirectory': portable.path}),
    );
    final pointed = LocalDataStore(documentsDirectory: documents);
    expect((await pointed.read()).preferences.provider, 'artcraft');
    expect((await pointed.stats(0)).path, dataFile(portable.path).path);

    pointerFile(documents).writeAsStringSync('not json at all');
    final malformed = LocalDataStore(documentsDirectory: documents);
    expect((await malformed.read()).preferences.provider, 'bfl');

    pointerFile(documents).writeAsStringSync(
      jsonEncode(<String, String>{
        'dataDirectory': '${portable.path}${separator}unplugged-drive',
      }),
    );
    final missingTarget = LocalDataStore(documentsDirectory: documents);
    expect((await missingTarget.read()).preferences.provider, 'bfl');
  });

  test('relocate copies the library and serves the new location', () async {
    final documents = await temporary('clawnsole-documents.');
    final target = await temporary('clawnsole-target.');
    final store = LocalDataStore(documentsDirectory: documents);
    await store.write(library('ltx'));
    final asset = await store.writeAsset(
      Uint8List.fromList(<int>[1, 2, 3]),
      label: 'clip.mp4',
      contentType: 'video/mp4',
    );

    await store.relocate(target.path);

    expect(dataFile(target.path).existsSync(), isTrue);
    expect(
      jsonDecode(pointerFile(documents).readAsStringSync()),
      <String, Object?>{'dataDirectory': Directory(target.path).absolute.path},
    );
    expect(await store.readAsset(asset), <int>[1, 2, 3]);

    await store.write(library('atlas'));
    expect(
      StoredData.decode(
        dataFile(target.path).readAsStringSync(),
      ).preferences.provider,
      'atlas',
    );
    // The previous copy is intentionally kept untouched.
    expect(
      StoredData.decode(
        dataFile(rootPath(documents)).readAsStringSync(),
      ).preferences.provider,
      'ltx',
    );
    expect(
      Directory(
        '${rootPath(documents)}${separator}assets',
      ).listSync().whereType<File>(),
      hasLength(1),
    );

    // A fresh process resolves the pointer to the relocated directory.
    final restarted = LocalDataStore(documentsDirectory: documents);
    expect((await restarted.read()).preferences.provider, 'atlas');
    expect((await restarted.stats(0)).path, dataFile(target.path).path);
    expect(await restarted.readAsset(asset), <int>[1, 2, 3]);
  });

  test('relocate refuses an occupied folder unless adopting it', () async {
    final documents = await temporary('clawnsole-documents.');
    final target = await temporary('clawnsole-target.');
    final store = LocalDataStore(documentsDirectory: documents);
    await store.write(library('ltx'));
    dataFile(target.path).writeAsStringSync(library('artcraft').encode());

    await expectLater(store.relocate(target.path), throwsStateError);
    expect(
      StoredData.decode(
        dataFile(target.path).readAsStringSync(),
      ).preferences.provider,
      'artcraft',
    );

    await store.relocate(target.path, useExistingLibrary: true);
    expect((await store.read()).preferences.provider, 'artcraft');
    // The handed-off library was adopted, never overwritten.
    expect(
      StoredData.decode(
        dataFile(rootPath(documents)).readAsStringSync(),
      ).preferences.provider,
      'ltx',
    );
  });

  test('relocate refuses the current and assets folders', () async {
    final documents = await temporary('clawnsole-documents.');
    final store = LocalDataStore(documentsDirectory: documents);
    await store.write(library('ltx'));

    await expectLater(store.relocate(rootPath(documents)), throwsStateError);
    await expectLater(
      store.relocate('${rootPath(documents)}${separator}assets'),
      throwsStateError,
    );
    await expectLater(
      store.relocate(
        '${rootPath(documents)}${separator}assets${separator}inner',
      ),
      throwsStateError,
    );
    expect((await store.read()).preferences.provider, 'ltx');
  });
}
