import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'models.dart';
import 'bfl_api.dart' show validatedProviderUrl;

enum TemporaryMediaLeaseState {
  intent,
  prepared,
  submitting,
  accepted,
  cleanupPending,
}

/// This journal contains recovery identifiers, never media bytes or public URLs.
class TemporaryMediaLease {
  const TemporaryMediaLease({
    required this.id,
    required this.operationId,
    required this.scopeId,
    required this.provider,
    required this.model,
    required this.createdAt,
    required this.updatedAt,
    this.state = TemporaryMediaLeaseState.intent,
    this.fileId,
    this.permissionId,
    this.requestId,
    this.pollingUrl,
    this.lastError,
  });

  final String id;
  final String operationId;
  final String scopeId;
  final String provider;
  final String model;
  final DateTime createdAt;
  final DateTime updatedAt;
  final TemporaryMediaLeaseState state;
  final String? fileId;
  final String? permissionId;
  final String? requestId;
  final String? pollingUrl;
  final String? lastError;

  TemporaryMediaLease copyWith({
    TemporaryMediaLeaseState? state,
    String? fileId,
    String? permissionId,
    String? requestId,
    String? pollingUrl,
    String? lastError,
    bool clearError = false,
    required DateTime updatedAt,
  }) => TemporaryMediaLease(
    id: id,
    operationId: operationId,
    scopeId: scopeId,
    provider: provider,
    model: model,
    createdAt: createdAt,
    updatedAt: updatedAt,
    state: state ?? this.state,
    fileId: fileId ?? this.fileId,
    permissionId: permissionId ?? this.permissionId,
    requestId: requestId ?? this.requestId,
    pollingUrl: pollingUrl ?? this.pollingUrl,
    lastError: clearError ? null : lastError ?? this.lastError,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'operationId': operationId,
    'scopeId': scopeId,
    'provider': provider,
    'model': model,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'state': state.name,
    if (fileId != null) 'fileId': fileId,
    if (permissionId != null) 'permissionId': permissionId,
    if (requestId != null) 'requestId': requestId,
    if (pollingUrl != null) 'pollingUrl': pollingUrl,
    if (lastError != null) 'lastError': lastError,
  };

  factory TemporaryMediaLease.fromJson(Map<String, Object?> json) {
    String requiredString(String key) {
      final value = json[key];
      if (value is! String || value.isEmpty) {
        throw const FormatException('Invalid temporary media recovery record.');
      }
      return value;
    }

    return TemporaryMediaLease(
      id: requiredString('id'),
      operationId: requiredString('operationId'),
      scopeId: requiredString('scopeId'),
      provider: requiredString('provider'),
      model: requiredString('model'),
      createdAt: DateTime.parse(requiredString('createdAt')).toUtc(),
      updatedAt: DateTime.parse(requiredString('updatedAt')).toUtc(),
      state: TemporaryMediaLeaseState.values.byName(requiredString('state')),
      fileId: json['fileId'] as String?,
      permissionId: json['permissionId'] as String?,
      requestId: json['requestId'] as String?,
      pollingUrl: json['pollingUrl'] as String?,
      lastError: json['lastError'] as String?,
    );
  }
}

abstract interface class TemporaryMediaLeaseJournal {
  Future<List<TemporaryMediaLease>> read();
  Future<void> write(List<TemporaryMediaLease> leases);
}

class TemporaryMediaSource {
  const TemporaryMediaSource({
    required this.source,
    required this.label,
    required this.kind,
    this.retained,
    this.contentType,
  });
  final String source;
  final AssetReference? retained;
  final String label;
  final MediaReferenceKind kind;
  final String? contentType;
}

class TemporaryMediaCopy {
  const TemporaryMediaCopy({required this.fileId});
  final String fileId;
}

class TemporaryMediaShare {
  const TemporaryMediaShare({required this.permissionId, required this.url});
  final String permissionId;
  final String url;
}

/// Implementations own app-created copies only, and reject a different scope.
/// [shareCopy] verifies anonymous media access before returning. [releaseCopy]
/// must also recover a permission created before its response was persisted.
abstract interface class TemporaryMediaBackend {
  String? get scopeId;
  Future<List<TemporaryMediaCopy>> findCopies(TemporaryMediaLease lease);
  Future<TemporaryMediaCopy> createCopy(
    TemporaryMediaLease lease,
    TemporaryMediaSource source,
  );
  Future<TemporaryMediaShare> shareCopy(
    TemporaryMediaLease lease,
    TemporaryMediaCopy copy,
  );
  Future<void> releaseCopy(TemporaryMediaLease lease, TemporaryMediaCopy copy);
}

class TemporaryMediaHostStatus {
  const TemporaryMediaHostStatus({
    required this.available,
    required this.activeLeases,
    required this.pendingCleanup,
    this.lastCleanupError,
  });
  final bool available;
  final int activeLeases;
  final int pendingCleanup;
  final String? lastCleanupError;
}

/// One request position, including the URL component of a timed keyframe.
class TemporaryMediaSlot {
  const TemporaryMediaSlot({
    required this.field,
    required this.media,
    this.index,
    this.timed = false,
  });
  final String field;
  final int? index;
  final bool timed;
  final TemporaryMediaSource media;

  void replaceIn(Map<String, Object?> input, String url) {
    final offset = index;
    if (offset == null) {
      input[field] = url;
      return;
    }
    final values = List<Object?>.from(input[field]! as List);
    if (timed) {
      final pair = List<Object?>.from(values[offset]! as List);
      pair[1] = url;
      values[offset] = pair;
    } else {
      values[offset] = url;
    }
    input[field] = values;
  }
}

/// Enumerates only canonical media fields, never prompt text or task IDs.
List<TemporaryMediaSlot> temporaryMediaSlots(
  GenerationConfig config,
  Map<String, Object?> input,
) {
  if (input['mode'] == 'draft_enhance' && input.containsKey('draft_task_id')) {
    return const [];
  }
  final slots = <TemporaryMediaSlot>[];
  void list(String field, MediaReferenceKind kind) {
    final values = input[field];
    if (values is! List) return;
    final references =
        config.references?.where((item) => item.kind == kind).toList() ??
        const <MediaReferenceLabel>[];
    for (var index = 0; index < values.length; index++) {
      final value = values[index];
      final timed = field == 'keyframes' && value is List;
      final raw = timed && value.length > 1 ? value[1] : value;
      if (raw is! String) continue;
      final frame =
          field == 'keyframes' && index < (config.keyframes?.length ?? 0)
          ? config.keyframes![index]
          : null;
      final reference = field != 'keyframes' && index < references.length
          ? references[index]
          : null;
      final retained = frame?.source ?? reference?.source;
      slots.add(
        TemporaryMediaSlot(
          field: field,
          index: index,
          timed: timed,
          media: TemporaryMediaSource(
            source: raw,
            retained: retained,
            kind: kind,
            label:
                frame?.label ?? reference?.label ?? '${kind.name} ${index + 1}',
            contentType: retained?.contentType,
          ),
        ),
      );
    }
  }

  list('keyframes', MediaReferenceKind.image);
  list('reference_images', MediaReferenceKind.image);
  list('reference_videos', MediaReferenceKind.video);
  list('reference_audios', MediaReferenceKind.audio);
  for (final field in ['start_video', 'input_video', 'draft_cache']) {
    final value = input[field];
    if (value is String && value.isNotEmpty) {
      slots.add(
        TemporaryMediaSlot(
          field: field,
          media: TemporaryMediaSource(
            source: value,
            retained: config.source,
            label: config.sourceLabel ?? 'Source video',
            kind: MediaReferenceKind.video,
            contentType: config.source?.contentType,
          ),
        ),
      );
    }
  }
  return slots;
}

bool isPublicTemporaryMediaSource(String source) {
  try {
    return validatedProviderUrl(source).scheme == 'https';
  } on Object {
    return false;
  }
}

typedef TemporaryMediaPoll =
    Future<Generation?> Function(TemporaryMediaLease lease);

/// Durable ownership of temporary public media, shared by native and companion.
/// The 24-hour orphan limit is enforced when connected, not by the host server.
class TemporaryMediaHost {
  TemporaryMediaHost({
    required this.journal,
    required this.backend,
    DateTime Function()? clock,
    this.orphanLifetime = const Duration(hours: 24),
    this.onPublicUrl,
  }) : _clock = clock ?? DateTime.now;
  final TemporaryMediaLeaseJournal journal;
  final TemporaryMediaBackend backend;
  final Duration orphanLifetime;
  final void Function(String)? onPublicUrl;
  final DateTime Function() _clock;
  Future<void> _tail = Future<void>.value();
  Map<String, TemporaryMediaLease>? _leases;
  final Map<String, Future<Map<String, Object?>>> _preparing = {};
  final Map<String, Future<void>> _releasing = {};
  final Set<String> _publicUrls = {};
  final Set<String> _knownFileIds = {};
  final Map<String, Set<String>> _operationUrls = {};
  bool _suspended = false;

  /// Call before changing Drive credentials; [releaseAll] drains preparations.
  void suspend() => _suspended = true;
  void resume() => _suspended = false;

  void _requirePreparingScope(String scope) {
    if (_suspended || backend.scopeId != scope) {
      throw StateError(
        'Google Drive sharing stopped. Reconnect Drive before generating with this media.',
      );
    }
  }

  Set<String> get activePublicUrls => Set.unmodifiable(_publicUrls);
  Set<String> hostedUrlsFor(String operationId) =>
      Set.unmodifiable(_operationUrls[operationId] ?? const <String>{});
  String redactText(String text) {
    for (final url in _publicUrls) {
      text = text.replaceAll(url, '«temporary media URL»');
    }
    return text.replaceAllMapped(RegExp(r'''https?://[^\s"'<>]+'''), (match) {
      final value = match.group(0)!;
      final uri = Uri.tryParse(value);
      if (_knownFileIds.any(value.contains) ||
          (uri != null &&
              (uri.pathSegments.any(_knownFileIds.contains) ||
                  uri.queryParametersAll.values.any(
                    (values) => values.any(_knownFileIds.contains),
                  )))) {
        return '«temporary media URL»';
      }
      return value;
    });
  }

  Map<String, Object?> redactResponse(Map<String, Object?> response) {
    Object? scrub(Object? value) {
      if (value is String) return redactText(value);
      if (value is List) return value.map(scrub).toList();
      if (value is Map) {
        return value.map((key, item) => MapEntry(key.toString(), scrub(item)));
      }
      return value;
    }

    return scrub(response)! as Map<String, Object?>;
  }

  DateTime get _now => _clock().toUtc();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> _load() async {
    _leases ??= {for (final lease in await journal.read()) lease.id: lease};
    _knownFileIds.addAll(
      _leases!.values.map((lease) => lease.fileId).whereType<String>(),
    );
  }

  Future<List<TemporaryMediaLease>> _read() => _serialized(() async {
    await _load();
    return _leases!.values.toList();
  });

  Future<void> _change(
    void Function(Map<String, TemporaryMediaLease>) change,
  ) => _serialized(() async {
    await _load();
    final next = Map<String, TemporaryMediaLease>.from(_leases!);
    change(next);
    if (next.length == _leases!.length &&
        next.entries.every(
          (entry) => identical(entry.value, _leases![entry.key]),
        )) {
      return;
    }
    await journal.write(next.values.toList());
    _leases = next;
    _knownFileIds.addAll(
      next.values.map((lease) => lease.fileId).whereType<String>(),
    );
  });

  Future<Map<String, Object?>> prepare(
    Generation record,
    Map<String, Object?> input,
  ) => _preparing[record.localId] ??= _prepare(record, input).whenComplete(() {
    _preparing.remove(record.localId);
  });

  Future<Map<String, Object?>> _prepare(
    Generation record,
    Map<String, Object?> input,
  ) async {
    final slots = temporaryMediaSlots(record.config, input)
        .where((slot) => !isPublicTemporaryMediaSource(slot.media.source))
        .toList();
    if (slots.isEmpty) return Map.of(input);
    final scope = backend.scopeId;
    if (scope == null || scope.isEmpty) {
      throw StateError(
        'Connect Google Drive to temporarily share this media, or provide a public HTTPS URL.',
      );
    }
    _requirePreparingScope(scope);
    final result = Map<String, Object?>.from(input);
    final prepared = <String, String>{};
    try {
      for (final slot in slots) {
        final source = slot.media;
        final identity = source.retained == null
            ? source.source
            : jsonEncode([source.retained!.kind, source.retained!.value]);
        final id =
            'tm_${sha256.convert(utf8.encode('${record.localId}\u0000$scope\u0000${source.kind.name}\u0000$identity'))}';
        if (prepared[id] != null) {
          slot.replaceIn(result, prepared[id]!);
          continue;
        }
        var lease = (await _read()).where((item) => item.id == id).firstOrNull;
        if (lease?.state == TemporaryMediaLeaseState.cleanupPending) {
          throw StateError(
            'Temporary media cleanup is still pending. Try again after Drive reconnects.',
          );
        }
        lease ??= TemporaryMediaLease(
          id: id,
          operationId: record.localId,
          scopeId: scope,
          provider: record.provider,
          model: record.model,
          createdAt: _now,
          updatedAt: _now,
        );
        final intent = lease;
        await _change((items) => items[id] = intent);
        final copies = await backend.findCopies(lease);
        _requirePreparingScope(scope);
        final copy =
            copies.firstOrNull ?? await backend.createCopy(lease, source);
        lease = lease.copyWith(fileId: copy.fileId, updatedAt: _now);
        final uploaded = lease;
        await _change((items) => items[id] = uploaded);
        _requirePreparingScope(scope);
        final share = await backend.shareCopy(lease, copy);
        if (!isPublicTemporaryMediaSource(share.url)) {
          throw StateError(
            'The temporary media host returned an invalid public HTTPS URL.',
          );
        }
        _publicUrls.add(share.url);
        (_operationUrls[record.localId] ??= {}).add(share.url);
        onPublicUrl?.call(share.url);
        lease = lease.copyWith(
          state: TemporaryMediaLeaseState.prepared,
          permissionId: share.permissionId,
          updatedAt: _now,
          clearError: true,
        );
        final ready = lease;
        await _change((items) => items[id] = ready);
        _requirePreparingScope(scope);
        prepared[id] = share.url;
        slot.replaceIn(result, share.url);
      }
      return result;
    } on Object {
      await _releaseOperation(record.localId);
      rethrow;
    }
  }

  Future<void> beforeSend(String operationId) async {
    await _change((items) {
      final owned = items.values
          .where((lease) => lease.operationId == operationId)
          .toList();
      if (_suspended ||
          owned.any(
            (lease) =>
                lease.state != TemporaryMediaLeaseState.prepared ||
                lease.scopeId != backend.scopeId,
          ) ||
          (owned.isEmpty && hostedUrlsFor(operationId).isNotEmpty)) {
        throw StateError(
          'Temporary media sharing is no longer available. Reconnect Drive and try again.',
        );
      }
      for (final lease in owned) {
        items[lease.id] = lease.copyWith(
          state: TemporaryMediaLeaseState.submitting,
          updatedAt: _now,
        );
      }
    });
    assertCanSend(operationId);
  }

  /// Recheck synchronously after the gateway's durable uncertainty write and
  /// immediately before returning from its provider before-send callback.
  void assertCanSend(String operationId) {
    final owned =
        _leases?.values
            .where((lease) => lease.operationId == operationId)
            .toList() ??
        const <TemporaryMediaLease>[];
    if (_suspended ||
        owned.any(
          (lease) =>
              lease.state != TemporaryMediaLeaseState.submitting ||
              lease.scopeId != backend.scopeId,
        ) ||
        (owned.isEmpty && hostedUrlsFor(operationId).isNotEmpty)) {
      throw StateError(
        'Temporary media sharing is no longer available. Reconnect Drive and try again.',
      );
    }
  }

  Future<void> accepted(Generation record) => _change((items) {
    for (final lease in items.values.toList()) {
      if (lease.operationId == record.localId &&
          lease.state != TemporaryMediaLeaseState.cleanupPending) {
        items[lease.id] = lease.copyWith(
          state: TemporaryMediaLeaseState.accepted,
          requestId: record.requestId,
          pollingUrl: record.pollingUrl,
          updatedAt: _now,
          clearError: true,
        );
      }
    }
  });

  Future<void> release(String operationId) async {
    try {
      await _preparing[operationId];
    } on Object {
      /* Cleanup below also retries a failed preparation. */
    }
    await _releaseOperation(operationId);
  }

  Future<void> _releaseOperation(String operationId) =>
      _releasing[operationId] ??= _releaseClaimed(operationId).whenComplete(() {
        _releasing.remove(operationId);
      });

  Future<void> _releaseClaimed(String operationId) async {
    final leases = (await _read())
        .where((item) => item.operationId == operationId)
        .toList();
    for (var lease in leases) {
      lease = lease.copyWith(
        state: TemporaryMediaLeaseState.cleanupPending,
        updatedAt: _now,
      );
      final pending = lease;
      await _change((items) => items[lease.id] = pending);
      if (backend.scopeId != lease.scopeId) continue;
      try {
        final found = await backend.findCopies(lease);
        final copies = {
          for (final copy in found) copy.fileId: copy,
          if (lease.fileId != null)
            lease.fileId!: TemporaryMediaCopy(fileId: lease.fileId!),
        };
        for (final copy in copies.values) {
          await backend.releaseCopy(lease, copy);
        }
        await _change((items) => items.remove(lease.id));
      } on Object {
        final failed = lease.copyWith(
          updatedAt: _now,
          lastError:
              'Temporary media is still shared. Reconnect Google Drive to retry cleanup.',
        );
        await _change((items) => items[lease.id] = failed);
      }
    }
  }

  Future<void> releaseAll() async {
    final operations = <String>{
      ..._preparing.keys,
      ...(await _read()).map((item) => item.operationId),
      ..._preparing.keys,
    };
    for (final operation in operations) {
      await release(operation);
    }
  }

  Future<void> reconcile(
    List<Generation> records, {
    Set<String> activeOperations = const {},
    TemporaryMediaPoll? poll,
  }) async {
    final byId = {for (final record in records) record.localId: record};
    final leases = await _read();
    final checked = <String>{};
    for (final lease in leases) {
      if (!checked.add(lease.operationId) ||
          activeOperations.contains(lease.operationId) ||
          _preparing.containsKey(lease.operationId)) {
        continue;
      }
      if (lease.state == TemporaryMediaLeaseState.cleanupPending) {
        await release(lease.operationId);
        continue;
      }
      var record = byId[lease.operationId];
      if (record?.isReady == true || record?.isFailed == true) {
        await release(lease.operationId);
        continue;
      }
      if (record?.canCheckStatus == true) {
        await accepted(record!);
        continue;
      }
      if (record?.isSubmissionUnknown == true) {
        if (_now.difference(lease.createdAt) >= orphanLifetime) {
          await release(lease.operationId);
        }
        continue;
      }
      if (lease.state == TemporaryMediaLeaseState.intent ||
          lease.state == TemporaryMediaLeaseState.prepared) {
        await release(lease.operationId);
        continue;
      }
      if (backend.scopeId != lease.scopeId) continue;
      if (poll != null && lease.pollingUrl != null) {
        try {
          record = await poll(lease);
        } on Object {
          /* Retry on the next connected pass. */
        }
        if (record?.isReady == true || record?.isFailed == true) {
          await release(lease.operationId);
          continue;
        }
      }
      if (_now.difference(lease.createdAt) >= orphanLifetime) {
        await release(lease.operationId);
      }
    }
  }

  Future<void> onConnection(
    List<Generation> records, {
    Set<String> activeOperations = const {},
    TemporaryMediaPoll? poll,
  }) {
    resume();
    return reconcile(records, activeOperations: activeOperations, poll: poll);
  }

  Future<TemporaryMediaHostStatus> status() async {
    final leases = await _read();
    final pending = leases
        .where((item) => item.state == TemporaryMediaLeaseState.cleanupPending)
        .toList();
    return TemporaryMediaHostStatus(
      available: !_suspended && backend.scopeId != null,
      activeLeases: leases.length - pending.length,
      pendingCleanup: pending.length,
      lastCleanupError: pending
          .map((item) => item.lastError)
          .whereType<String>()
          .firstOrNull,
    );
  }
}
