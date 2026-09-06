import 'dart:async';
import 'dart:io';

import 'asset_stream_base.dart';
import 'stream_discard.dart';

const _stagingPrefix = '.clawnsole-retain-';
const _stagingLeaseName = 'stage.lock';
final _sweptStagingRoots = <String>{};
final _activeStagingNames = <String>{};
final _stagingDirectoryName = RegExp(
  r'^\.clawnsole-retain-(?:[0-9]+-)?[A-Za-z0-9]+$',
);

String _name(FileSystemEntity entry) =>
    entry.uri.pathSegments.where((part) => part.isNotEmpty).last;

/// A crash releases the stage's advisory lock. Only old, inactive directories
/// with exactly our known file layout are eligible; links and foreign content
/// are preserved. The PID in new names also protects other isolates in this
/// process, because POSIX advisory locks are process scoped.
Future<void> _sweepAbandonedStaging(Directory root) async {
  final key = root.absolute.path;
  if (_sweptStagingRoots.contains(key)) return;
  if (_sweptStagingRoots.length >= 256) {
    _sweptStagingRoots.remove(_sweptStagingRoots.first);
  }
  _sweptStagingRoots.add(key);
  final cutoff = DateTime.now().subtract(const Duration(hours: 24));
  final watch = Stopwatch()..start();
  var candidates = 0;
  try {
    await for (final entry in root.list(followLinks: false)) {
      if (watch.elapsed > const Duration(milliseconds: 500) ||
          candidates >= 32) {
        break;
      }
      final name = _name(entry);
      if (entry is! Directory ||
          !_stagingDirectoryName.hasMatch(name) ||
          name.startsWith('$_stagingPrefix$pid-') ||
          _activeStagingNames.contains(name)) {
        continue;
      }
      RandomAccessFile? lease;
      try {
        if (!await _isOldOwnedStaging(entry, cutoff)) continue;
        candidates++;
        final leaseFile = File('${entry.path}/$_stagingLeaseName');
        if (await leaseFile.exists()) {
          lease = await leaseFile.open(mode: FileMode.append);
          // Nonblocking: a live transfer in another process owns this lock.
          await lease.lock(FileLock.exclusive);
        }
        if (!await _isOldOwnedStaging(entry, cutoff)) continue;
        // Windows cannot delete an open lease. No transfer adopts an existing
        // staging directory, so closing it here cannot hand it to a writer.
        await lease?.close();
        lease = null;
        await entry.delete(recursive: true);
      } on Object {
        // Inspection, locking and deletion are all optional housekeeping.
      } finally {
        try {
          await lease?.close();
        } on Object {
          // A failed sweep must never affect the new media transfer.
        }
      }
    }
  } on Object {
    // An unreadable cache still gets a chance to accept the new staging file.
  }
}

Future<bool> _isOldOwnedStaging(Directory directory, DateTime cutoff) async {
  if (await FileSystemEntity.type(directory.path, followLinks: false) !=
      FileSystemEntityType.directory) {
    return false;
  }
  final stat = await directory.stat();
  if (stat.type != FileSystemEntityType.directory ||
      !stat.modified.isBefore(cutoff)) {
    return false;
  }
  await for (final entry in directory.list(followLinks: false)) {
    if (entry is! File ||
        !const {'media.part', _stagingLeaseName}.contains(_name(entry))) {
      return false;
    }
    final stat = await entry.stat();
    if (stat.type != FileSystemEntityType.file ||
        await FileSystemEntity.type(entry.path, followLinks: false) !=
            FileSystemEntityType.file ||
        !stat.modified.isBefore(cutoff)) {
      return false;
    }
  }
  return await FileSystemEntity.type(directory.path, followLinks: false) ==
      FileSystemEntityType.directory;
}

Future<StagedAsset> stageAssetStream(
  Stream<List<int>> source, {
  String? directory,
  int? expectedLength,
  String? expectedSha256,
  int maxBytes = maxRetainedAssetBytes,
  Duration idleTimeout = assetStreamIdleTimeout,
  Duration totalTimeout = assetStreamTotalTimeout,
}) async {
  final watch = Stopwatch()..start();
  Duration remaining() {
    final value = totalTimeout - watch.elapsed;
    if (value <= Duration.zero) {
      throw TimeoutException('The media transfer exceeded its total deadline.');
    }
    return value;
  }

  final root = directory == null ? Directory.systemTemp : Directory(directory);
  Directory? staging;
  RandomAccessFile? sink;
  RandomAccessFile? lease;
  var ownsSource = false;
  try {
    await root.create(recursive: true);
    await _sweepAbandonedStaging(root);
    staging = await root.createTemp('$_stagingPrefix$pid-');
    _activeStagingNames.add(_name(staging));
    try {
      lease = await File(
        '${staging.path}${Platform.pathSeparator}$_stagingLeaseName',
      ).open(mode: FileMode.writeOnly);
      await lease.lock(FileLock.exclusive);
    } on Object {
      // Portable/network filesystems may not implement advisory locks. Keep
      // transfers usable, but permanently exclude these stages from the
      // opportunistic sweep because it cannot verify their ownership.
      try {
        await lease?.close();
      } on Object {
        /* The transfer can proceed without a lease. */
      }
      lease = null;
      await File('${staging.path}/preserve-unlocked-stage').writeAsString('1');
    }
    final file = File('${staging.path}${Platform.pathSeparator}media.part');
    sink = await file.open(mode: FileMode.writeOnly);
    final transferBudget = remaining();
    ownsSource = true;
    final result = await consumeAssetStream(
      source,
      write: (chunk) async {
        await sink!.writeFrom(chunk);
      },
      expectedLength: expectedLength,
      expectedSha256: expectedSha256,
      maxBytes: maxBytes,
      idleTimeout: idleTimeout,
      totalTimeout: transferBudget,
    );
    await sink.flush().timeout(remaining());
    await sink.close().timeout(remaining());
    sink = null;
    return _FileStagedAsset(file, staging, lease, result.length, result.sha256);
  } on Object {
    if (!ownsSource) await discardStream(source);
    try {
      await sink?.close();
    } on Object {
      /* Preserve the original failure. */
    }
    if (staging != null) {
      try {
        await lease?.close();
      } on Object {
        /* Preserve the original failure. */
      }
      _activeStagingNames.remove(_name(staging));
      try {
        await staging.delete(recursive: true);
      } on Object {
        /* Retryable cleanup. */
      }
    }
    rethrow;
  }
}

class _FileStagedAsset implements StagedAsset {
  _FileStagedAsset(
    this.file,
    this.directory,
    this.lease,
    this.length,
    this.sha256,
  );
  final File file;
  final Directory directory;
  RandomAccessFile? lease;
  @override
  String get path => file.path;
  @override
  final int length;
  @override
  final String sha256;
  @override
  Stream<List<int>> openRead() => file.openRead();
  @override
  Future<void> dispose() async {
    final held = lease;
    lease = null;
    try {
      await held?.close();
    } finally {
      _activeStagingNames.remove(_name(directory));
    }
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
