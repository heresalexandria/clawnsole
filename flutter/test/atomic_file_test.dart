import 'dart:convert';
import 'dart:io';

import 'package:clawnsole/core/atomic_file.dart';
import 'package:clawnsole/core/local_data_store_io.dart';
import 'package:clawnsole/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('clawnsole-atomic-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  File target() => File('${root.path}/clawnsole.json');

  test(
    'write keeps the previous contents as a backup and no temp files',
    () async {
      await writeTextAtomically(target(), 'first');
      await writeTextAtomically(target(), 'second');

      expect(await target().readAsString(), 'second');
      expect(await File(backupPath(target())).readAsString(), 'first');
      final leftovers = await root
          .list()
          .where((entry) => entry.path.endsWith('.tmp'))
          .toList();
      expect(leftovers, isEmpty);
    },
  );

  test('read falls back to the backup when the file is missing', () async {
    await writeTextAtomically(target(), 'first');
    await writeTextAtomically(target(), 'second');
    await target().delete();

    // The backup is the previous generation of the file: losing the canonical
    // copy costs at most one write, never the whole library.
    expect(await readTextWithFallback(target(), (text) => text), 'first');
  });

  test('read falls back to the backup when the file is malformed', () async {
    await writeTextAtomically(target(), '{"ok":1}');
    await writeTextAtomically(target(), '{"ok":2}');
    await target().writeAsString('{"ok":', flush: true);

    final decoded = await readTextWithFallback(
      target(),
      (text) => jsonDecode(text) as Map<String, Object?>,
    );
    expect(decoded, <String, Object?>{'ok': 1});
    final preserved = await root
        .list()
        .where((entry) => entry.path.contains('.corrupt-'))
        .toList();
    expect(preserved, hasLength(1));
  });

  test('read returns null when neither copy exists', () async {
    expect(await readTextWithFallback(target(), (text) => text), isNull);
  });

  test('LocalDataStore recovers a library from its backup', () async {
    final store = LocalDataStore(documentsDirectory: root);
    const preferences = AppPreferences(themeMode: AppThemeMode.dark);
    await store.write(const StoredData(preferences: preferences));
    await store.write(
      const StoredData(
        preferences: AppPreferences(themeMode: AppThemeMode.light),
      ),
    );
    final file = File('${root.path}/Clawnsole/clawnsole.json');
    expect(await file.exists(), isTrue);
    await file.delete();

    final restored = await store.read();
    expect(restored.preferences.themeMode, AppThemeMode.dark);
  });
}
