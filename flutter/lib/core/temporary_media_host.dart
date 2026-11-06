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
  sourceRemoved,
}

enum TemporaryMediaReadiness {
  ready,
  signedOut,
  driveDisabled,
  unsupported,
  unavailable,
}

/// Removing a source and revoking a published link are different operations.
enum TemporaryMediaCleanupSemantics { permissionRevocation, deferredExpiry }

class TemporaryMediaBackendAvailability {
  const TemporaryMediaBackendAvailability({
    required this.backendId,
    required this.readiness,
    this.accountScope,
    this.message,
    this.cleanupSemantics = TemporaryMediaCleanupSemantics.permissionRevocation,
  });

  final String backendId;
  final TemporaryMediaReadiness readiness;
  final String? accountScope;
  final String? message;
  final TemporaryMediaCleanupSemantics cleanupSemantics;

  bool get available =>
      readiness == TemporaryMediaReadiness.ready &&
      accountScope != null &&
      accountScope!.isNotEmpty;
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
    this.backendId = 'googleDrive',
    this.cleanupSemantics = TemporaryMediaCleanupSemantics.permissionRevocation,
    this.state = TemporaryMediaLeaseState.intent,
    this.fileId,
    this.permissionId,
    this.requestId,
    this.pollingUrl,
    this.lastError,
    this.publicationAttemptedAt,
    this.publishedAt,
    this.publishedExpiresAt,
    this.sourceRemovedAt,
  });

  final String id;
  final String operationId;
  final String scopeId;
  final String backendId;
  final TemporaryMediaCleanupSemantics cleanupSemantics;
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
  final DateTime? publicationAttemptedAt;
  final DateTime? publishedAt;

  /// The host-reported expiration, not proof of remote erasure or revocation.
  final DateTime? publishedExpiresAt;
  final DateTime? sourceRemovedAt;

  TemporaryMediaLease copyWith({
    TemporaryMediaLeaseState? state,
    String? fileId,
    String? permissionId,
    String? requestId,
    String? pollingUrl,
    String? lastError,
    TemporaryMediaCleanupSemantics? cleanupSemantics,
    DateTime? publicationAttemptedAt,
    DateTime? publishedAt,
    DateTime? publishedExpiresAt,
    DateTime? sourceRemovedAt,
    bool clearPublishedExpiry = false,
    bool clearError = false,
    required DateTime updatedAt,
  }) => TemporaryMediaLease(
    id: id,
    operationId: operationId,
    scopeId: scopeId,
    backendId: backendId,
    cleanupSemantics: cleanupSemantics ?? this.cleanupSemantics,
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
    publicationAttemptedAt:
        publicationAttemptedAt ?? this.publicationAttemptedAt,
    publishedAt: publishedAt ?? this.publishedAt,
    publishedExpiresAt: clearPublishedExpiry
        ? null
        : publishedExpiresAt ?? this.publishedExpiresAt,
    sourceRemovedAt: sourceRemovedAt ?? this.sourceRemovedAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'operationId': operationId,
    'scopeId': scopeId,
    'backendId': backendId,
    'cleanupSemantics': cleanupSemantics.name,
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
    if (publicationAttemptedAt != null)
      'publicationAttemptedAt': publicationAttemptedAt!.toIso8601String(),
    if (publishedAt != null) 'publishedAt': publishedAt!.toIso8601String(),
    if (publishedExpiresAt != null)
      'publishedExpiresAt': publishedExpiresAt!.toIso8601String(),
    if (sourceRemovedAt != null)
      'sourceRemovedAt': sourceRemovedAt!.toIso8601String(),
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
      // Version-one journals used Google Drive exclusively.
      backendId: json.containsKey('backendId')
          ? requiredString('backendId')
          : 'googleDrive',
      cleanupSemantics: json.containsKey('cleanupSemantics')
          ? TemporaryMediaCleanupSemantics.values.byName(
              requiredString('cleanupSemantics'),
            )
          : TemporaryMediaCleanupSemantics.permissionRevocation,
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
      publicationAttemptedAt: json['publicationAttemptedAt'] == null
          ? null
          : DateTime.parse(requiredString('publicationAttemptedAt')).toUtc(),
      publishedAt: json['publishedAt'] == null
          ? null
          : DateTime.parse(requiredString('publishedAt')).toUtc(),
      publishedExpiresAt: json['publishedExpiresAt'] == null
          ? null
          : DateTime.parse(requiredString('publishedExpiresAt')).toUtc(),
      sourceRemovedAt: json['sourceRemovedAt'] == null
          ? null
          : DateTime.parse(requiredString('sourceRemovedAt')).toUtc(),
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
  const TemporaryMediaCopy({
    required this.fileId,
    this.publishedAt,
    this.expiresAt,
    this.publicationAttempted,
  });
  final String fileId;

  /// False confirms the owned copy never reached publication; null means the
  /// backend cannot determine whether it did. True includes uncertain attempts.
  final bool? publicationAttempted;

  /// Recovery metadata for a publication whose response was not journaled.
  /// The backend must preserve these before removing its owned source copy.
  final DateTime? publishedAt;
  final DateTime? expiresAt;
}

class TemporaryMediaShare {
  const TemporaryMediaShare({
    required this.url,
    this.permissionId,
    this.publishedAt,
    this.expiresAt,
    this.cleanupSemantics = TemporaryMediaCleanupSemantics.permissionRevocation,
  });
  final String? permissionId;
  final String url;
  final DateTime? publishedAt;
  final DateTime? expiresAt;
  final TemporaryMediaCleanupSemantics cleanupSemantics;
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

/// Optional for legacy Drive adapters. Refresh must update the backend's cached
/// [TemporaryMediaBackend.scopeId], which the final synchronous send guard reads.
/// Native adapters must also recheck ownership/account identity on every action.
abstract interface class TemporaryMediaBackendCapabilities {
  String get backendId;
  Future<TemporaryMediaBackendAvailability> refreshAvailability();
}

/// Consent belongs to this device, hosting account and disclosure version.
/// Implementations must not infer it from synced library preferences.
abstract interface class TemporaryMediaConsentBackend {
  Future<bool> isSharingAccepted();
  Future<void> acceptSharing();
}

class TemporaryMediaHostStatus {
  const TemporaryMediaHostStatus({
    required this.available,
    required this.activeLeases,
    required this.pendingCleanup,
    this.lastCleanupError,
    this.backendId = 'googleDrive',
    TemporaryMediaReadiness? readiness,
    this.message,
    this.accountScope,
    this.cleanupSemantics = TemporaryMediaCleanupSemantics.permissionRevocation,
    this.publishedSnapshots = 0,
    this.publishedSnapshotsUnknownExpiry = 0,
    this.latestPublishedExpiry,
    this.sharingAccepted = true,
  }) : _readiness = readiness;
  final bool available;
  final int activeLeases;

  /// Source copies awaiting cleanup; this is not a count of revoked links.
  final int pendingCleanup;
  final String? lastCleanupError;
  final String backendId;
  final TemporaryMediaReadiness? _readiness;
  TemporaryMediaReadiness get readiness =>
      _readiness ??
      (available
          ? TemporaryMediaReadiness.ready
          : TemporaryMediaReadiness.unavailable);
  final String? message;
  final String? accountScope;
  final TemporaryMediaCleanupSemantics cleanupSemantics;

  /// Known or possibly issued snapshots whose reported expiration has not
  /// passed. This is retained even after the source has been removed.
  final int publishedSnapshots;
  final int publishedSnapshotsUnknownExpiry;
  final DateTime? latestPublishedExpiry;
  final bool sharingAccepted;

  Map<String, Object?> toJson() => {
    'available': available,
    'activeLeases': activeLeases,
    'pendingCleanup': pendingCleanup,
    'backendId': backendId,
    'readiness': readiness.name,
    'cleanupSemantics': cleanupSemantics.name,
    'publishedSnapshots': publishedSnapshots,
    'publishedSnapshotsUnknownExpiry': publishedSnapshotsUnknownExpiry,
    'sharingAccepted': sharingAccepted,
    if (message != null) 'message': message,
    if (accountScope != null) 'accountScope': accountScope,
    if (lastCleanupError != null) 'lastCleanupError': lastCleanupError,
    if (latestPublishedExpiry != null)
      'latestPublishedExpiry': latestPublishedExpiry!.toIso8601String(),
  };

  factory TemporaryMediaHostStatus.fromJson(Map<String, Object?> json) =>
      TemporaryMediaHostStatus(
        available: json['available'] == true,
        activeLeases: (json['activeLeases'] as num?)?.toInt() ?? 0,
        pendingCleanup: (json['pendingCleanup'] as num?)?.toInt() ?? 0,
        backendId: json['backendId'] as String? ?? 'googleDrive',
        readiness: TemporaryMediaReadiness.values
            .where((value) => value.name == json['readiness'])
            .firstOrNull,
        cleanupSemantics:
            TemporaryMediaCleanupSemantics.values
                .where((value) => value.name == json['cleanupSemantics'])
                .firstOrNull ??
            TemporaryMediaCleanupSemantics.permissionRevocation,
        message: json['message'] as String?,
        accountScope: json['accountScope'] as String?,
        lastCleanupError: json['lastCleanupError'] as String?,
        publishedSnapshots: (json['publishedSnapshots'] as num?)?.toInt() ?? 0,
        publishedSnapshotsUnknownExpiry:
            (json['publishedSnapshotsUnknownExpiry'] as num?)?.toInt() ?? 0,
        latestPublishedExpiry: json['latestPublishedExpiry'] is String
            ? DateTime.tryParse(
                json['latestPublishedExpiry']! as String,
              )?.toUtc()
            : null,
        sharingAccepted: json['sharingAccepted'] != false,
      );
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
/// The orphan source-copy limit is enforced when connected. It is not a public
/// access deadline: deferred publications can outlive the owned source copy.
class TemporaryMediaHost {
  TemporaryMediaHost({
    required this.journal,
    required this.backend,
    this.cleanupBackends = const {},
    DateTime Function()? clock,
    this.orphanLifetime = const Duration(hours: 24),
    this.onPublicUrl,
  }) : _clock = clock ?? DateTime.now;
  final TemporaryMediaLeaseJournal journal;
  final TemporaryMediaBackend backend;

  /// Older hosts remain reachable for owned-lease cleanup only. New media is
  /// always prepared with [backend], even when that backend is unavailable.
  final Map<String, TemporaryMediaBackend> cleanupBackends;
  String get backendId => _backendId(backend);
  TemporaryMediaBackendAvailability? _availability;
  bool _sharingAccepted = true;
  bool _redactApplePublicationUrls = false;
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

  /// Call before changing active-host credentials; [releaseAll] drains work.
  void suspend() => _suspended = true;
  void resume() => _suspended = false;

  void _requirePreparingScope(String scope) {
    if (_suspended ||
        _availability?.available != true ||
        _availability?.accountScope != scope ||
        backend.scopeId != scope) {
      throw StateError(
        'Media sharing stopped. Reconnect the same hosting account before generating.',
      );
    }
  }

  static String _backendId(TemporaryMediaBackend value) =>
      value is TemporaryMediaBackendCapabilities
      ? (value as TemporaryMediaBackendCapabilities).backendId
      : 'googleDrive';

  TemporaryMediaBackend? _backendFor(TemporaryMediaLease lease) =>
      lease.backendId == backendId ? backend : cleanupBackends[lease.backendId];

  Future<TemporaryMediaBackendAvailability> _refreshBackend(
    TemporaryMediaBackend target,
  ) async {
    final id = _backendId(target);
    TemporaryMediaBackendAvailability value;
    try {
      if (target is TemporaryMediaBackendCapabilities) {
        value = await (target as TemporaryMediaBackendCapabilities)
            .refreshAvailability();
        if (value.backendId != id ||
            (value.available && value.accountScope != target.scopeId)) {
          throw StateError(
            'Hosting account changed during its readiness check.',
          );
        }
      } else {
        value = TemporaryMediaBackendAvailability(
          backendId: id,
          readiness: target.scopeId == null || target.scopeId!.isEmpty
              ? TemporaryMediaReadiness.signedOut
              : TemporaryMediaReadiness.ready,
          accountScope: target.scopeId,
          message: target.scopeId == null || target.scopeId!.isEmpty
              ? 'Connect Google Drive to temporarily share this media, or provide a public HTTPS URL.'
              : null,
        );
      }
    } on Object {
      value = TemporaryMediaBackendAvailability(
        backendId: id,
        readiness: TemporaryMediaReadiness.unavailable,
        message: 'Media hosting could not be checked. Reconnect and try again.',
        cleanupSemantics: identical(target, backend)
            ? _availability?.cleanupSemantics ??
                  TemporaryMediaCleanupSemantics.permissionRevocation
            : TemporaryMediaCleanupSemantics.permissionRevocation,
      );
    }
    if (value.cleanupSemantics ==
        TemporaryMediaCleanupSemantics.deferredExpiry) {
      _redactApplePublicationUrls = true;
    }
    if (identical(target, backend)) _availability = value;
    return value;
  }

  Future<bool> _refreshConsent() async {
    try {
      _sharingAccepted =
          backend is! TemporaryMediaConsentBackend ||
          await (backend as TemporaryMediaConsentBackend).isSharingAccepted();
    } on Object {
      _sharingAccepted = false;
    }
    return _sharingAccepted;
  }

  Future<void> acceptSharing({
    required String expectedBackendId,
    required String expectedAccountScope,
  }) async {
    final availability = await _refreshBackend(backend);
    if (!availability.available ||
        _suspended ||
        expectedBackendId != backendId ||
        expectedAccountScope.isEmpty ||
        expectedAccountScope != availability.accountScope) {
      throw StateError(
        availability.message ??
            'The hosting account changed. Review sharing again before continuing.',
      );
    }
    final scope = availability.accountScope!;
    if (backend case final TemporaryMediaConsentBackend consent) {
      await consent.acceptSharing();
    }
    await _refreshBackend(backend);
    _requirePreparingScope(scope);
    if (!await _refreshConsent()) {
      throw StateError('Media sharing consent could not be saved. Try again.');
    }
  }

  Future<void> _requireConsent() async {
    if (!await _refreshConsent()) {
      throw StateError(
        'Review and accept how reference copies are shared before generating.',
      );
    }
  }

  bool _hasPublishedSnapshot(TemporaryMediaLease lease) =>
      lease.cleanupSemantics == TemporaryMediaCleanupSemantics.deferredExpiry &&
      (lease.publicationAttemptedAt != null || lease.publishedAt != null) &&
      (lease.publishedExpiresAt == null ||
          lease.publishedExpiresAt!.isAfter(_now));

  Future<void> _pruneExpiredSnapshots() => _change((items) {
    items.removeWhere(
      (_, lease) =>
          lease.state == TemporaryMediaLeaseState.sourceRemoved &&
          lease.publishedExpiresAt != null &&
          !lease.publishedExpiresAt!.isAfter(_now),
    );
  });

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
      final host = uri?.host.toLowerCase();
      final applePublication =
          _redactApplePublicationUrls &&
          uri != null &&
          (host == 'icloud-content.com' ||
              host!.endsWith('.icloud-content.com') ||
              ((host == 'icloud.com' || host == 'www.icloud.com') &&
                  uri.pathSegments.firstOrNull == 'attachment'));
      if (applePublication ||
          _knownFileIds.any(value.contains) ||
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
    if (_leases!.values.any(
      (lease) =>
          lease.cleanupSemantics ==
          TemporaryMediaCleanupSemantics.deferredExpiry,
    )) {
      _redactApplePublicationUrls = true;
    }
    _knownFileIds.addAll(
      _leases!.values.map((lease) => lease.fileId).whereType<String>(),
    );
  }

  /// Hydrates only local recovery identifiers for transcript redaction. This
  /// must not depend on native account readiness or delay provider polling.
  Future<void> loadRecoveryMetadata() => _serialized(_load);

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
    final availability = await _refreshBackend(backend);
    final scope = availability.accountScope;
    if (!availability.available || scope == null || scope.isEmpty) {
      throw StateError(
        availability.message ??
            'Media hosting is unavailable. Reconnect your hosting account or provide a public HTTPS URL.',
      );
    }
    await _requireConsent();
    _requirePreparingScope(scope);
    final result = Map<String, Object?>.from(input);
    final prepared = <String, String>{};
    try {
      for (final slot in slots) {
        final source = slot.media;
        final identity = source.retained == null
            ? source.source
            : jsonEncode([source.retained!.kind, source.retained!.value]);
        // Preserve version-one Drive IDs so a resumed preparation finds its
        // existing owned copy. Other backends have a separate namespace.
        final hostingScope = backendId == 'googleDrive'
            ? scope
            : '$backendId\u0000$scope';
        final id =
            'tm_${sha256.convert(utf8.encode('${record.localId}\u0000$hostingScope\u0000${source.kind.name}\u0000$identity'))}';
        if (prepared[id] != null) {
          slot.replaceIn(result, prepared[id]!);
          continue;
        }
        var lease = (await _read()).where((item) => item.id == id).firstOrNull;
        if (lease?.state == TemporaryMediaLeaseState.cleanupPending ||
            lease?.state == TemporaryMediaLeaseState.sourceRemoved) {
          throw StateError(
            'This media copy is being cleaned up. Start a new generation after reconnecting.',
          );
        }
        lease ??= TemporaryMediaLease(
          id: id,
          operationId: record.localId,
          scopeId: scope,
          backendId: backendId,
          cleanupSemantics: availability.cleanupSemantics,
          provider: record.provider,
          model: record.model,
          createdAt: _now,
          updatedAt: _now,
        );
        if (lease.cleanupSemantics ==
            TemporaryMediaCleanupSemantics.deferredExpiry) {
          // Some native backends copy and publish atomically in createCopy.
          // Publication can succeed even when that response is lost, so record
          // the possible exposure before either mutating backend operation.
          lease = lease.copyWith(
            publicationAttemptedAt: _now,
            clearPublishedExpiry: true,
            updatedAt: _now,
          );
        }
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
        _publicUrls.add(share.url);
        (_operationUrls[record.localId] ??= {}).add(share.url);
        onPublicUrl?.call(share.url);
        lease = lease.copyWith(
          state: TemporaryMediaLeaseState.prepared,
          permissionId: share.permissionId,
          // Never downgrade a deferred backend's semantics if its response
          // omitted optional capability metadata.
          cleanupSemantics:
              lease.cleanupSemantics ==
                  TemporaryMediaCleanupSemantics.deferredExpiry
              ? lease.cleanupSemantics
              : share.cleanupSemantics,
          publishedAt: share.publishedAt ?? _now,
          publishedExpiresAt: share.expiresAt,
          updatedAt: _now,
          clearError: true,
        );
        final ready = lease;
        await _change((items) => items[id] = ready);
        _requirePreparingScope(scope);
        if (!isPublicTemporaryMediaSource(share.url)) {
          throw StateError(
            'The temporary media host returned an invalid public HTTPS URL.',
          );
        }
        if (share.expiresAt != null && !share.expiresAt!.isAfter(_now)) {
          throw StateError('The published media link has already expired.');
        }
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
    await _refreshBackend(backend);
    await _requireConsent();
    await _change((items) {
      final owned = items.values
          .where((lease) => lease.operationId == operationId)
          .toList();
      if (_suspended ||
          _availability?.available != true ||
          owned.any(
            (lease) =>
                lease.state != TemporaryMediaLeaseState.prepared ||
                lease.backendId != backendId ||
                lease.scopeId != backend.scopeId ||
                lease.scopeId != _availability?.accountScope ||
                (lease.publishedExpiresAt != null &&
                    !lease.publishedExpiresAt!.isAfter(_now)),
          ) ||
          (owned.isEmpty && hostedUrlsFor(operationId).isNotEmpty)) {
        throw StateError(
          'Media sharing is no longer available. Reconnect the same hosting account and try again.',
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
        !_sharingAccepted ||
        _availability?.available != true ||
        owned.any(
          (lease) =>
              lease.state != TemporaryMediaLeaseState.submitting ||
              lease.backendId != backendId ||
              lease.scopeId != backend.scopeId ||
              lease.scopeId != _availability?.accountScope ||
              (lease.publishedExpiresAt != null &&
                  !lease.publishedExpiresAt!.isAfter(_now)),
        ) ||
        (owned.isEmpty && hostedUrlsFor(operationId).isNotEmpty)) {
      throw StateError(
        'Media sharing is no longer available. Reconnect the same hosting account and try again.',
      );
    }
  }

  Future<void> accepted(Generation record) => _change((items) {
    for (final lease in items.values.toList()) {
      if (lease.operationId == record.localId &&
          lease.state != TemporaryMediaLeaseState.cleanupPending &&
          lease.state != TemporaryMediaLeaseState.sourceRemoved) {
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

  Future<void> _releaseOperation(String operationId, {String? backendId}) {
    final key = operationId;
    final inFlight = _releasing[key];
    if (inFlight != null) {
      // A scoped legacy cleanup and a terminal-job cleanup may overlap. Wait
      // for the existing owner, then cover this caller's requested backend(s).
      return inFlight.then(
        (_) => _releaseOperation(operationId, backendId: backendId),
      );
    }
    return _releasing[key] ??=
        _releaseClaimed(operationId, backendId: backendId).whenComplete(() {
          _releasing.remove(key);
        });
  }

  Future<void> _releaseClaimed(String operationId, {String? backendId}) async {
    final leases = (await _read())
        .where(
          (item) =>
              item.operationId == operationId &&
              (backendId == null || item.backendId == backendId),
        )
        .toList();
    for (var lease in leases) {
      if (lease.state == TemporaryMediaLeaseState.sourceRemoved) continue;
      lease = lease.copyWith(
        state: TemporaryMediaLeaseState.cleanupPending,
        updatedAt: _now,
      );
      final pending = lease;
      await _change((items) => items[lease.id] = pending);
      try {
        final target = _backendFor(lease);
        if (target == null || _backendId(target) != lease.backendId) {
          throw StateError('The original media host is unavailable.');
        }
        final availability = await _refreshBackend(target);
        if (!availability.available ||
            availability.accountScope != lease.scopeId ||
            target.scopeId != lease.scopeId) {
          throw StateError('Reconnect the original hosting account.');
        }
        final found = await target.findCopies(lease);
        final copies = {
          if (lease.fileId != null)
            lease.fileId!: TemporaryMediaCopy(fileId: lease.fileId!),
          // Preserve recovered publication metadata over the fallback ID.
          for (final copy in found) copy.fileId: copy,
        };
        for (final copy in copies.values) {
          if (copy.publishedAt != null || copy.expiresAt != null) {
            final expiry = copy.expiresAt;
            lease = lease.copyWith(
              publishedAt: copy.publishedAt,
              publishedExpiresAt:
                  expiry != null &&
                      (lease.publishedExpiresAt == null ||
                          expiry.isAfter(lease.publishedExpiresAt!))
                  ? expiry
                  : lease.publishedExpiresAt,
              updatedAt: _now,
            );
          }
        }
        final recovered = lease;
        // Save recovered expiration before deleting the backend's receipt.
        await _change((items) => items[lease.id] = recovered);
        for (final copy in copies.values) {
          if (target.scopeId != lease.scopeId) {
            throw StateError('Hosting account changed during cleanup.');
          }
          await target.releaseCopy(lease, copy);
        }
        final confirmedUnpublished =
            copies.isNotEmpty &&
            copies.values.every((copy) => copy.publicationAttempted == false) &&
            lease.publishedAt == null &&
            lease.publishedExpiresAt == null;
        if (!confirmedUnpublished && _hasPublishedSnapshot(lease)) {
          final removed = lease.copyWith(
            state: TemporaryMediaLeaseState.sourceRemoved,
            sourceRemovedAt: _now,
            updatedAt: _now,
            clearError: true,
          );
          await _change((items) => items[lease.id] = removed);
        } else {
          await _change((items) => items.remove(lease.id));
        }
      } on Object {
        final failed = lease.copyWith(
          updatedAt: _now,
          lastError:
              'Temporary source-copy cleanup is pending. Reconnect the original hosting account to retry.',
        );
        await _change((items) => items[lease.id] = failed);
      }
    }
    await _pruneExpiredSnapshots();
  }

  Future<void> releaseAll({String? backendId}) async {
    final drainsActive = backendId == null || backendId == this.backendId;
    final operations = <String>{
      if (drainsActive) ..._preparing.keys,
      ...(await _read())
          .where((item) => backendId == null || item.backendId == backendId)
          .map((item) => item.operationId),
      if (drainsActive) ..._preparing.keys,
    };
    for (final operation in operations) {
      if (drainsActive) {
        try {
          await _preparing[operation];
        } on Object {
          /* Recover owned copies below after an interrupted preparation. */
        }
      }
      await _releaseOperation(operation, backendId: backendId);
    }
  }

  Future<void> reconcile(
    List<Generation> records, {
    Set<String> activeOperations = const {},
    TemporaryMediaPoll? poll,
  }) async {
    await _pruneExpiredSnapshots();
    final byId = {for (final record in records) record.localId: record};
    final leases = await _read();
    final checked = <String>{};
    for (final lease in leases) {
      if (lease.state == TemporaryMediaLeaseState.sourceRemoved) continue;
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
      final target = _backendFor(lease);
      if (target == null) continue;
      final availability = await _refreshBackend(target);
      if (!availability.available ||
          availability.accountScope != lease.scopeId) {
        continue;
      }
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
    final availability = await _refreshBackend(backend);
    await _refreshConsent();
    await _pruneExpiredSnapshots();
    final leases = await _read();
    final pending = leases
        .where((item) => item.state == TemporaryMediaLeaseState.cleanupPending)
        .toList();
    final published = leases.where(_hasPublishedSnapshot).toList();
    final expirations =
        published
            .map((lease) => lease.publishedExpiresAt)
            .whereType<DateTime>()
            .toList()
          ..sort();
    return TemporaryMediaHostStatus(
      available: !_suspended && availability.available,
      backendId: backendId,
      readiness: _suspended
          ? TemporaryMediaReadiness.unavailable
          : availability.readiness,
      message: _suspended ? 'Media sharing is paused.' : availability.message,
      accountScope: availability.accountScope,
      cleanupSemantics: availability.cleanupSemantics,
      sharingAccepted: _sharingAccepted,
      activeLeases: leases
          .where(
            (lease) =>
                lease.state != TemporaryMediaLeaseState.cleanupPending &&
                lease.state != TemporaryMediaLeaseState.sourceRemoved,
          )
          .length,
      pendingCleanup: pending.length,
      publishedSnapshots: published.length,
      publishedSnapshotsUnknownExpiry: published
          .where((lease) => lease.publishedExpiresAt == null)
          .length,
      latestPublishedExpiry: expirations.lastOrNull,
      lastCleanupError: pending
          .map((item) => item.lastError)
          .whereType<String>()
          .firstOrNull,
    );
  }
}
