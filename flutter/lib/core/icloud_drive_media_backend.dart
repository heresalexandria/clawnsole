import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';

import 'asset_extensions.dart';
import 'asset_stream.dart';
import 'icloud_attachment_url.dart';
import 'icloud_reference_transport.dart';
import 'public_media_http.dart';
import 'secure_value_store.dart';
import 'temporary_media_host.dart';

/// Publishes disposable copies through the signed-in user's iCloud Drive.
/// No CloudKit database or developer-owned hosting account is involved.
class ICloudDriveMediaBackend
    implements
        TemporaryMediaBackend,
        TemporaryMediaBackendCapabilities,
        TemporaryMediaConsentBackend {
  ICloudDriveMediaBackend({
    required ICloudReferenceTransport transport,
    required SecureValueStore consentStore,
    required Future<StagedAsset> Function(TemporaryMediaSource) stageSource,
    http.Client? publicClient,
    DateTime Function()? clock,
  }) : _transport = transport,
       _consentStore = consentStore,
       _stageSource = stageSource,
       _publicClient = publicClient,
       _clock = clock ?? DateTime.now;

  final ICloudReferenceTransport _transport;
  final SecureValueStore _consentStore;
  final Future<StagedAsset> Function(TemporaryMediaSource) _stageSource;
  final http.Client? _publicClient;
  final DateTime Function() _clock;
  String? _scope;

  @override
  String get backendId => 'iCloudDrive';
  @override
  String? get scopeId => _scope;

  @override
  Future<TemporaryMediaBackendAvailability> refreshAvailability() async {
    try {
      final result = await _transport.call('status');
      final readiness = switch (result['state']) {
        'ready' => TemporaryMediaReadiness.ready,
        'noAccount' => TemporaryMediaReadiness.signedOut,
        'driveUnavailable' => TemporaryMediaReadiness.driveDisabled,
        'unsupported' => TemporaryMediaReadiness.unsupported,
        _ => TemporaryMediaReadiness.unavailable,
      };
      final scope = result['accountScope'];
      _scope =
          readiness == TemporaryMediaReadiness.ready &&
              scope is String &&
              RegExp(r'^[a-f0-9]{64}$').hasMatch(scope)
          ? scope
          : null;
      return TemporaryMediaBackendAvailability(
        backendId: backendId,
        readiness: readiness == TemporaryMediaReadiness.ready && _scope == null
            ? TemporaryMediaReadiness.unavailable
            : readiness,
        accountScope: _scope,
        cleanupSemantics: TemporaryMediaCleanupSemantics.deferredExpiry,
        message: result['message'] as String?,
      );
    } on Object {
      _scope = null;
      return const TemporaryMediaBackendAvailability(
        backendId: 'iCloudDrive',
        readiness: TemporaryMediaReadiness.unavailable,
        cleanupSemantics: TemporaryMediaCleanupSemantics.deferredExpiry,
        message:
            'iCloud Drive is unavailable. Check your Apple Account and iCloud Drive settings, then retry.',
      );
    }
  }

  String _consentKey(String scope) => 'icloud-reference-sharing.v1.$scope';

  @override
  Future<bool> isSharingAccepted() async {
    final scope = _scope;
    return scope != null &&
        await _consentStore.read(_consentKey(scope)) == 'accepted' &&
        _scope == scope;
  }

  @override
  Future<void> acceptSharing() async {
    final expected = _scope;
    final availability = await refreshAvailability();
    if (!availability.available || expected == null || expected != _scope) {
      throw const ICloudReferenceException(
        'accountChanged',
        'Check your Apple Account and review iCloud reference sharing again.',
      );
    }
    await _consentStore.write(_consentKey(expected), 'accepted');
  }

  Future<void> _requireAccount(TemporaryMediaLease lease) async {
    final availability = await refreshAvailability();
    if (!availability.available || _scope != lease.scopeId) {
      throw const ICloudReferenceException(
        'accountChanged',
        'Sign in to the same Apple Account and enable iCloud Drive to use or clean up this reference.',
      );
    }
  }

  Map<String, Object?> _arguments(TemporaryMediaLease lease) => {
    'leaseId': lease.id,
    'expectedAccountScope': lease.scopeId,
  };

  Future<Map<String, Object?>?> _receipt(TemporaryMediaLease lease) async {
    await _requireAccount(lease);
    try {
      return await _transport.call('lease', _arguments(lease));
    } on ICloudReferenceException catch (error) {
      if (error.code == 'leaseNotFound') return null;
      rethrow;
    }
  }

  DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;

  TemporaryMediaCopy _copy(
    TemporaryMediaLease lease,
    Map<String, Object?> value,
  ) => TemporaryMediaCopy(
    fileId: lease.id,
    publicationAttempted: switch (value['state']) {
      'preparing' || 'uploading' => false,
      'publishing' || 'published' => true,
      _ => null,
    },
    publishedAt: value['expiresAt'] == null ? null : _date(value['updatedAt']),
    expiresAt: _date(value['expiresAt']),
  );

  @override
  Future<List<TemporaryMediaCopy>> findCopies(TemporaryMediaLease lease) async {
    final value = await _receipt(lease);
    if (value == null) {
      // Native publication journals intent first. An absent receipt proves
      // this attempt never published; a read failure still throws instead.
      return lease.state == TemporaryMediaLeaseState.cleanupPending
          ? [TemporaryMediaCopy(fileId: lease.id, publicationAttempted: false)]
          : const [];
    }
    // An interrupted upload still needs prepare to resume. Cleanup, however,
    // must discover every owned source, including an uncertain publication.
    if (lease.state != TemporaryMediaLeaseState.cleanupPending &&
        value['state'] != 'published' &&
        value['state'] != 'cleaned') {
      return const [];
    }
    return [_copy(lease, value)];
  }

  @override
  Future<TemporaryMediaCopy> createCopy(
    TemporaryMediaLease lease,
    TemporaryMediaSource source,
  ) async {
    await _requireAccount(lease);
    if (!await isSharingAccepted()) {
      throw const ICloudReferenceException(
        'consentRequired',
        'Review and allow iCloud reference sharing before uploading this reference.',
      );
    }
    final staged = await _stageSource(source);
    try {
      final header = <int>[];
      await for (final chunk in staged.openRead()) {
        header.addAll(chunk.take(64 - header.length));
        if (header.length >= 64) break;
      }
      final mime =
          lookupMimeType(source.label, headerBytes: header) ??
          source.contentType?.split(';').first.trim().toLowerCase();
      if (mime == null || !mime.startsWith('${source.kind.name}/')) {
        throw ICloudReferenceException(
          'unsupportedMedia',
          'The selected file is not a supported ${source.kind.name}.',
        );
      }
      await _requireAccount(lease);
      final result = await _transport.call('prepare', {
        ..._arguments(lease),
        'sourcePath': staged.path,
        'filename': 'reference${retainedAssetExtension(mime, source.label)}',
        'sha256': staged.sha256,
        'bytes': staged.length,
        'timeoutMs': 180000,
      });
      return _copy(lease, result);
    } finally {
      await staged.dispose();
    }
  }

  @override
  Future<TemporaryMediaShare> shareCopy(
    TemporaryMediaLease lease,
    TemporaryMediaCopy copy,
  ) async {
    final value = await _receipt(lease);
    final publication = value?['publishedUrl'];
    final expires = _date(value?['expiresAt']);
    final checksum = value?['sha256'];
    final bytes = (value?['bytes'] as num?)?.toInt();
    if (copy.fileId != lease.id ||
        publication is! String ||
        expires == null ||
        expires.difference(_clock().toUtc()) < const Duration(minutes: 5) ||
        checksum is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(checksum) ||
        bytes == null ||
        bytes <= 0) {
      throw const ICloudReferenceException(
        'publicationUnavailable',
        'The iCloud reference link is unavailable or expired. Select the reference again.',
      );
    }
    final uri = resolveICloudAttachmentUrl(publication, expectedBytes: bytes);
    // No automatic redirects: never forward an Apple bearer URL to another
    // host, and never accept an HTML interstitial as a media reference.
    final client =
        _publicClient ?? PublicMediaClient(maxRedirects: 0, maxBytes: bytes);
    try {
      final response = await client.send(
        http.Request('GET', uri)..followRedirects = false,
      );
      final mime = response.headers['content-type']
          ?.split(';')
          .first
          .toLowerCase();
      if (response.statusCode != 200 ||
          !isICloudAssetUrl(response.request?.url ?? uri) ||
          mime == null ||
          !(mime.startsWith('video/') ||
              mime.startsWith('image/') ||
              mime.startsWith('audio/') ||
              mime == 'application/octet-stream')) {
        await response.stream.listen(null).cancel();
        throw const ICloudReferenceException(
          'downloadUnavailable',
          'Unavailable',
        );
      }
      await consumeAssetStream(
        response.stream,
        write: (_) async {},
        expectedLength: bytes,
        expectedSha256: checksum,
        maxBytes: bytes,
      );
    } on Object {
      // HTTP/parser errors can contain the bearer URL. Never propagate them.
      throw const ICloudReferenceException(
        'downloadUnavailable',
        'iCloud could not provide a verified public media download. No generation was submitted. Retry or use a public HTTPS media URL.',
      );
    } finally {
      if (_publicClient == null) client.close();
    }
    await _requireAccount(lease);
    return TemporaryMediaShare(
      url: uri.toString(),
      publishedAt: _date(value?['updatedAt']),
      expiresAt: expires,
      cleanupSemantics: TemporaryMediaCleanupSemantics.deferredExpiry,
    );
  }

  @override
  Future<void> releaseCopy(
    TemporaryMediaLease lease,
    TemporaryMediaCopy copy,
  ) async {
    if (copy.fileId != lease.id) {
      throw const ICloudReferenceException(
        'invalidLease',
        'Invalid iCloud reference cleanup request.',
      );
    }
    await _requireAccount(lease);
    try {
      await _transport.call('cleanup', _arguments(lease));
    } on ICloudReferenceException catch (error) {
      if (error.code != 'leaseNotFound') rethrow;
    }
  }
}
