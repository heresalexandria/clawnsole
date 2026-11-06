import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'temporary_media_host.dart';
import 'temporary_media_permissions_stub.dart'
    if (dart.library.io) 'temporary_media_permissions_io.dart';

/// Device-private recovery journal, deliberately outside library deletion and
/// relocation. The gateway resolves its stable application-data path.
class FileTemporaryMediaLeaseJournal implements TemporaryMediaLeaseJournal {
  FileTemporaryMediaLeaseJournal(this.fileProvider);
  final Future<File> Function() fileProvider;
  static const _maximumBytes = 4 * 1024 * 1024;
  final Random _random = Random.secure();

  @override
  Future<List<TemporaryMediaLease>> read() async {
    final file = await fileProvider();
    if (!await file.exists()) return const [];
    protectTemporaryMediaJournal(file.path);
    if (await file.length() > _maximumBytes) {
      throw const FormatException(
        'The temporary media recovery journal is too large.',
      );
    }
    final value = jsonDecode(await file.readAsString());
    if (value is! Map ||
        !const [1, 2].contains(value['version']) ||
        value['leases'] is! List) {
      throw const FormatException(
        'The temporary media recovery journal is invalid.',
      );
    }
    final leases = <TemporaryMediaLease>[];
    final ids = <String>{};
    for (final item in value['leases'] as List) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException(
          'The temporary media recovery journal is invalid.',
        );
      }
      if (value['version'] == 2 &&
          (item['backendId'] is! String ||
              (item['backendId'] as String).isEmpty)) {
        throw const FormatException(
          'The temporary media recovery record has no hosting backend.',
        );
      }
      final lease = TemporaryMediaLease.fromJson(item);
      if (!ids.add(lease.id)) {
        throw const FormatException(
          'The temporary media recovery journal contains duplicate records.',
        );
      }
      leases.add(lease);
    }
    return leases;
  }

  @override
  Future<void> write(List<TemporaryMediaLease> leases) async {
    final source = jsonEncode({
      'version': 2,
      'leases': leases.map((item) => item.toJson()).toList(),
    });
    if (utf8.encode(source).length > _maximumBytes) {
      throw StateError('The temporary media recovery journal is full.');
    }
    final file = await fileProvider();
    await file.parent.create(recursive: true);
    final suffix = List.generate(
      12,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final temporary = File('${file.path}.$suffix.tmp');
    try {
      await temporary.create(exclusive: true);
      // Protect the empty file before writing any recovery metadata. POSIX
      // FFI also works on iOS/Android, where spawning chmod is unavailable.
      protectTemporaryMediaJournal(temporary.path);
      await temporary.writeAsString(source, flush: true);
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
