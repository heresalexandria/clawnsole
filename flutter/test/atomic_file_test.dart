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

  test(
    'full deletion removes owned recovery copies and preserves neighbors',
    () async {
      await writeTextAtomically(target(), 'first');
      await writeTextAtomically(target(), 'second');
      final corrupt = File('${target().path}.corrupt-1');
      final temporary = File('${target().path}.1.2.tmp');
      final neighbor = File('${root.path}/other.json.bak');
      await corrupt.writeAsString('recoverable');
      await temporary.writeAsString('interrupted');
      await neighbor.writeAsString('unrelated');

      await deleteTextWithRecovery(target());

      expect(await readTextWithFallback(target(), (value) => value), isNull);
      expect(await corrupt.exists(), isFalse);
      expect(await temporary.exists(), isFalse);
      expect(await neighbor.readAsString(), 'unrelated');
    },
  );

  test('invalid library shape recovers a good backup', () async {
    final store = LocalDataStore(documentsDirectory: root);
    await store.write(
      const StoredData(
        preferences: AppPreferences(themeMode: AppThemeMode.dark),
      ),
    );
    await store.write(const StoredData());
    final file = File('${root.path}/Clawnsole/clawnsole.json');
    await file.writeAsString('[]');

    expect((await store.read()).preferences.themeMode, AppThemeMode.dark);
    expect(
      await file.parent
          .list()
          .where((entry) => entry.path.contains('.corrupt-'))
          .length,
      1,
    );
  });

  test(
    'newer schema is neither recovered over nor overwritten by stale writes',
    () async {
      final store = LocalDataStore(documentsDirectory: root);
      await store.write(const StoredData());
      await store.write(const StoredData());
      final file = File('${root.path}/Clawnsole/clawnsole.json');
      const future = '{"schemaVersion":999,"futureField":"preserve"}';
      await file.writeAsString(future);

      await expectLater(store.read(), throwsUnsupportedError);
      await expectLater(
        store.write(const StoredData()),
        throwsUnsupportedError,
      );

      expect(await file.readAsString(), future);
      expect(
        await file.parent
            .list()
            .where((entry) => entry.path.contains('.corrupt-'))
            .length,
        0,
      );
    },
  );

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

  test('stale writes preserve a future nested composer schema', () async {
    final store = LocalDataStore(documentsDirectory: root);
    await store.write(const StoredData());
    await store.write(const StoredData());
    final file = File('${root.path}/Clawnsole/clawnsole.json');
    final future = jsonEncode(<String, Object?>{
      'schemaVersion': StoredData.currentSchemaVersion,
      'composerTabs': <String, Object?>{
        'schemaVersion': 999,
        'futureField': 'preserve',
      },
    });
    await file.writeAsString(future);

    await expectLater(store.read(), throwsUnsupportedError);
    await expectLater(store.write(const StoredData()), throwsUnsupportedError);

    expect(await file.readAsString(), future);
    expect(
      await file.parent
          .list()
          .where((entry) => entry.path.contains('.corrupt-'))
          .length,
      0,
    );
  });
}
