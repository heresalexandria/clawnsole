import 'dart:io';

import 'package:clawnsole/core/hard_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('clawnsole-hard-link-');
  });

  tearDown(() async {
    hardLinkOverrideForTesting = null;
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('a hard link shares the inode and is not a symbolic link', () async {
    final original = File('${root.path}/library.json');
    final link = File('${root.path}/library.json.bak');
    await original.writeAsString('revision', flush: true);

    expect(createHardLink(original.path, link.path), isTrue);

    // dart:io cannot expose st_ino, so prove the shared inode the observable
    // way: bytes appended through one name are read back through the other.
    expect(await FileSystemEntity.isLink(link.path), isFalse);
    expect(await link.readAsString(), 'revision');
    await link.writeAsString('+more', mode: FileMode.append, flush: true);
    expect(await original.readAsString(), 'revision+more');

    // Replacing the original by rename leaves the link on the old inode.
    final replacement = File('${root.path}/library.json.tmp');
    await replacement.writeAsString('next', flush: true);
    await replacement.rename(original.path);
    expect(await original.readAsString(), 'next');
    expect(await link.readAsString(), 'revision+more');
  });

  test('refusals answer false without touching either path', () async {
    final original = File('${root.path}/library.json');
    final existing = File('${root.path}/library.json.bak');
    await original.writeAsString('revision', flush: true);
    await existing.writeAsString('older', flush: true);

    expect(createHardLink(original.path, existing.path), isFalse);
    expect(await existing.readAsString(), 'older');
    expect(
      createHardLink('${root.path}/missing.json', '${root.path}/missing.bak'),
      isFalse,
    );
    expect(await File('${root.path}/missing.bak').exists(), isFalse);
  });

  test('the test seam replaces the platform call', () async {
    final calls = <(String, String)>[];
    hardLinkOverrideForTesting = (existingPath, linkPath) {
      calls.add((existingPath, linkPath));
      return false;
    };
    expect(createHardLink('a', 'b'), isFalse);
    expect(calls, [('a', 'b')]);
  });
}
