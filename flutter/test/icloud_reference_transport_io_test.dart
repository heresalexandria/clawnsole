import 'dart:io';

import 'package:clawnsole/core/icloud_reference_transport.dart';
import 'package:clawnsole/core/icloud_reference_transport_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('native helper process transport', () {
    test(
      'a status timeout preserves an in-flight preparation and helper',
      () async {
        final fixture = await _Helper.create(
          requestTimeout: const Duration(milliseconds: 30),
        );
        addTearDown(fixture.close);
        final prepared = fixture.transport.call('prepare', {
          'delayMs': 200,
          'waitForRelease': true,
        });
        await fixture.waitFor('prepare-started');
        await expectLater(
          fixture.transport.call('status'),
          _throwsCode('timeout'),
        );
        await File('${fixture.directory.path}/release').create();
        final reply = await prepared;
        expect(reply['prepared'], isTrue);
        final firstPid = reply['pid'];
        final resumed = await fixture.transport.call('prepare');
        expect(resumed['pid'], firstPid);
        expect(fixture.starts, hasLength(1));
      },
    );

    test(
      'a crash fails every pending request and a new call restarts the helper',
      () async {
        final fixture = await _Helper.create();
        addTearDown(fixture.close);
        final prepared = fixture.transport.call('prepare', {'hold': true});
        final preparingFailed = expectLater(
          prepared,
          _throwsCode('helperUnavailable'),
        );
        await fixture.waitFor('prepare-started');
        final waiting = fixture.transport.call('hold');
        final waitingFailed = expectLater(
          waiting,
          _throwsCode('helperUnavailable'),
        );
        await fixture.waitFor('hold-started');
        await expectLater(
          fixture.transport.call('crash'),
          _throwsCode('helperUnavailable'),
        );
        await Future.wait([preparingFailed, waitingFailed]);
        final status = await fixture.transport.call('status');
        expect(status['ok'], isTrue);
        expect(fixture.starts, hasLength(2));
        expect(fixture.starts.toSet(), hasLength(2));
      },
    );

    test(
      'the prepare deadline terminates the stuck helper and allows recovery',
      () async {
        final fixture = await _Helper.create(
          prepareTimeout: const Duration(milliseconds: 200),
        );
        addTearDown(fixture.close);
        await fixture.transport.call('status');
        await expectLater(
          fixture.transport.call('prepare', {'hold': true}),
          _throwsCode('timeout'),
        );
        final status = await fixture.transport.call('status');
        expect(status['ok'], isTrue);
        expect(fixture.starts, hasLength(2));
      },
    );

    test(
      'close fails pending work and never launches another helper',
      () async {
        final fixture = await _Helper.create();
        addTearDown(fixture.close);
        final preparing = fixture.transport.call('prepare', {'hold': true});
        final failed = expectLater(preparing, _throwsCode('helperUnavailable'));
        await fixture.waitFor('prepare-started');
        await fixture.transport.close();
        await failed;
        await expectLater(
          fixture.transport.call('status'),
          _throwsCode('helperUnavailable'),
        );
        expect(fixture.starts, hasLength(1));
      },
    );
  }, skip: Platform.isWindows ? 'The helper executable is POSIX-only.' : false);
}

Matcher _throwsCode(String code) => throwsA(
  isA<ICloudReferenceException>().having((error) => error.code, 'code', code),
);

class _Helper {
  _Helper(this.directory, this.transport);
  final Directory directory;
  final ProcessICloudReferenceTransport transport;

  static Future<_Helper> create({
    Duration requestTimeout = const Duration(seconds: 2),
    Duration prepareTimeout = const Duration(seconds: 2),
  }) async {
    final directory = await Directory.systemTemp.createTemp(
      'icloud-transport.',
    );
    final script = File('${directory.path}/helper.py');
    await script.writeAsString(_script);
    final chmod = await Process.run('chmod', ['700', script.path]);
    if (chmod.exitCode != 0) {
      await directory.delete(recursive: true);
      throw StateError('Could not make the test helper executable.');
    }
    return _Helper(
      directory,
      ProcessICloudReferenceTransport(
        executable: script.path,
        journalDirectory: directory.path,
        requestTimeout: requestTimeout,
        prepareTimeout: prepareTimeout,
      ),
    );
  }

  List<String> get starts => File('${directory.path}/starts').readAsLinesSync();

  Future<void> waitFor(String name) async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (!await File('${directory.path}/$name').exists()) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('The fake helper did not reach $name.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  Future<void> close() async {
    await transport.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

// A local protocol fixture only: no CloudKit, iCloud Drive, HTTP or provider
// calls. Its serial publication delay models Foundation blocking the actor.
const _script = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
import time

root = Path(sys.argv[2])
with (root / 'starts').open('a') as output:
    output.write(str(os.getpid()) + '\n')

for line in sys.stdin:
    frame = json.loads(line)
    method = frame['method']
    args = frame['arguments']
    if method == 'crash':
        os._exit(23)
    if method == 'hold':
        (root / 'hold-started').touch()
        continue
    if method == 'prepare':
        (root / 'prepare-started').touch()
        if args.get('hold'):
            continue
        while args.get('waitForRelease') and not (root / 'release').exists():
            time.sleep(0.005)
        time.sleep(args.get('delayMs', 0) / 1000)
    result = {'ok': True, 'pid': os.getpid()}
    if method == 'prepare':
        result['prepared'] = True
    print(json.dumps({'id': frame['id'], 'result': result}), flush=True)
''';
