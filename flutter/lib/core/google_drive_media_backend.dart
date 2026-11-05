import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';

import 'asset_extensions.dart';
import 'asset_stream.dart';
import 'bfl_api.dart' show validatedProviderUrl;
import 'google_drive.dart';
import 'public_media_http.dart';
import 'temporary_media_host.dart';

/// Publishes only disposable, tagged copies in a private My Drive root folder.
/// The connected library's originals and folder permissions are never changed.
class GoogleDriveMediaBackend implements TemporaryMediaBackend {
  GoogleDriveMediaBackend({
    required String? Function() scopeId,
    required GoogleDriveApi? Function() api,
    required Future<StagedAsset> Function(TemporaryMediaSource) stageSource,
    http.Client? publicClient,
  }) : _scopeId = scopeId,
       _api = api,
       _stageSource = stageSource,
       _publicClient = publicClient;

  final String? Function() _scopeId;
  final GoogleDriveApi? Function() _api;
  final Future<StagedAsset> Function(TemporaryMediaSource) _stageSource;
  final http.Client? _publicClient;

  @override
  String? get scopeId => _scopeId();

  static String _tag(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  GoogleDriveApi _connected(TemporaryMediaLease lease) {
    final api = _api();
    if (api == null || scopeId == null || lease.scopeId != scopeId) {
      throw StateError(
        'Reconnect the same Google Drive library to manage temporary media.',
      );
    }
    return api;
  }

  Map<String, String> _rootTags(String scope) => {
    'clawnsoleMediaRoot': '1',
    'clawnsoleMediaScope': _tag(scope),
  };

  Map<String, String> _copyTags(TemporaryMediaLease lease) => {
    'clawnsoleMediaCopy': '1',
    'clawnsoleMediaScope': _tag(lease.scopeId),
    'clawnsoleMediaLease': _tag(lease.id),
    'clawnsoleMediaOperation': _tag(lease.operationId),
  };

  bool _matches(GoogleDriveFile file, Map<String, String> tags) => tags.entries
      .every((entry) => file.appProperties[entry.key] == entry.value);

  bool _onlyOwner(List<GoogleDrivePermission> permissions) =>
      permissions.isNotEmpty &&
      permissions.every((item) => item.type == 'user' && item.role == 'owner');

  Future<void> _requirePrivateRoot(
    GoogleDriveApi api,
    String id,
    String scope,
  ) async {
    final root = await api.getFileDetails(id);
    if (!root.ownedByMe ||
        root.driveId != null ||
        root.trashed ||
        root.mimeType != 'application/vnd.google-apps.folder' ||
        !_matches(root, _rootTags(scope)) ||
        !_onlyOwner(await api.listPermissions(id))) {
      throw StateError(
        'The temporary media folder must be private and owned by your Google account.',
      );
    }
    final roots = await api.findFilesByProperties(
      _rootTags(scope),
      atMyDriveRoot: true,
    );
    if (!roots.any((item) => item.id == id)) {
      throw StateError('The temporary media folder was moved out of My Drive.');
    }
  }

  Future<String> _stagingRoot(GoogleDriveApi api, String scope) async {
    final roots = await api.findFilesByProperties(
      _rootTags(scope),
      mimeType: 'application/vnd.google-apps.folder',
      atMyDriveRoot: true,
    );
    final root = roots.isEmpty
        ? await api.createFolder(
            'Clawnsole temporary media',
            parentId: 'root',
            appProperties: _rootTags(scope),
          )
        : roots.first;
    await _requirePrivateRoot(api, root.id, scope);
    return root.id;
  }

  Future<GoogleDriveFile> _ownedCopy(
    GoogleDriveApi api,
    TemporaryMediaLease lease,
    TemporaryMediaCopy copy, {
    GoogleDriveFile? details,
    bool verifyParent = true,
  }) async {
    final file = details ?? await api.getFileDetails(copy.fileId);
    if (!file.ownedByMe ||
        file.driveId != null ||
        !_matches(file, _copyTags(lease)) ||
        file.parents.length != 1) {
      throw StateError(
        'This file is not a temporary copy owned by this generation.',
      );
    }
    if (verifyParent) {
      await _requirePrivateRoot(api, file.parents.single, lease.scopeId);
    }
    return file;
  }

  @override
  Future<List<TemporaryMediaCopy>> findCopies(TemporaryMediaLease lease) async {
    final api = _connected(lease);
    final copies = await api.findFilesByProperties(
      _copyTags(lease),
      includeTrashed: lease.state == TemporaryMediaLeaseState.cleanupPending,
    );
    return [for (final file in copies) TemporaryMediaCopy(fileId: file.id)];
  }

  @override
  Future<TemporaryMediaCopy> createCopy(
    TemporaryMediaLease lease,
    TemporaryMediaSource source,
  ) async {
    final api = _connected(lease);
    final root = await _stagingRoot(api, lease.scopeId);
    final staged = await _stageSource(source);
    try {
      final header = <int>[];
      await for (final chunk in staged.openRead()) {
        header.addAll(chunk.take(64 - header.length));
        if (header.length >= 64) break;
      }
      final declared = source.contentType
          ?.split(';')
          .first
          .trim()
          .toLowerCase();
      final contentType = declared?.startsWith('${source.kind.name}/') == true
          ? declared!
          : lookupMimeType(source.label, headerBytes: header);
      if (contentType == null ||
          !contentType.startsWith('${source.kind.name}/')) {
        throw StateError(
          'The selected file is not a supported ${source.kind.name}.',
        );
      }
      _connected(lease);
      final file = await api.createFileStream(
        parentId: root,
        name:
            'Clawnsole provider media ${_tag(lease.id).substring(0, 16)}'
            '${retainedAssetExtension(contentType, source.label)}',
        bytes: staged.openRead(),
        length: staged.length,
        contentType: contentType,
        appProperties: {
          ..._copyTags(lease),
          'clawnsoleMediaSha256': staged.sha256,
          'clawnsoleMediaCreated': lease.createdAt.toUtc().toIso8601String(),
        },
      );
      return TemporaryMediaCopy(fileId: file.id);
    } finally {
      await staged.dispose();
    }
  }

  @override
  Future<TemporaryMediaShare> shareCopy(
    TemporaryMediaLease lease,
    TemporaryMediaCopy copy,
  ) async {
    final api = _connected(lease);
    final file = await _ownedCopy(api, lease, copy);
    if (file.trashed) throw StateError('The temporary media copy is in Trash.');
    final permissions = await api.listPermissions(file.id);
    final public = permissions.where((item) => item.type == 'anyone').toList();
    final others = permissions.where((item) => item.type != 'anyone').toList();
    if (!_onlyOwner(others) ||
        public.length > 1 ||
        public.any(
          (item) =>
              item.inherited ||
              item.role != 'reader' ||
              item.allowFileDiscovery,
        )) {
      throw StateError(
        'The temporary media copy has unexpected sharing permissions.',
      );
    }
    _connected(lease);
    final permission = public.isEmpty
        ? await api.createUnlistedReader(file.id)
        : public.single;
    if (permission.id.isEmpty ||
        permission.type != 'anyone' ||
        permission.role != 'reader' ||
        permission.allowFileDiscovery) {
      throw StateError('Google Drive did not create unlisted read access.');
    }
    final shared = await api.getFileDetails(file.id);
    final url = shared.webContentLink;
    if (url == null) {
      throw StateError('Google Drive did not provide a media download link.');
    }
    final uri = validatedProviderUrl(url);
    if (uri.scheme != 'https' ||
        !(uri.host == 'drive.google.com' ||
            uri.host == 'drive.usercontent.google.com' ||
            uri.host.endsWith('.googleusercontent.com'))) {
      throw StateError('Google Drive returned an unsupported download link.');
    }
    final directUri = await _verifyAnonymousMedia(uri, shared);
    _connected(lease);
    return TemporaryMediaShare(
      permissionId: permission.id,
      url: directUri.toString(),
    );
  }

  Future<Uri> _verifyAnonymousMedia(Uri uri, GoogleDriveFile file) async {
    final client = _publicClient ?? PublicMediaClient();
    try {
      final response = await client.send(http.Request('GET', uri));
      final contentType = response.headers['content-type']
          ?.split(';')
          .first
          .toLowerCase();
      final checksum = file.appProperties['clawnsoleMediaSha256'];
      if (response.statusCode != 200 ||
          file.size <= 0 ||
          checksum == null ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(checksum) ||
          contentType == null ||
          !(contentType.startsWith('video/') ||
              contentType.startsWith('image/') ||
              contentType.startsWith('audio/') ||
              contentType == 'application/octet-stream')) {
        await response.stream.listen(null).cancel();
        throw StateError(
          'Google Drive could not provide a public media download. No generation was submitted.',
        );
      }
      await consumeAssetStream(
        response.stream,
        write: (_) async {},
        expectedLength: file.size,
        expectedSha256: checksum,
      );
      // Some provider asset fetchers reject Drive's browser-facing 303. The
      // media transport validates every redirect and exposes its actual final
      // request, so return that verified target without inventing URL formats.
      final directUri = validatedProviderUrl(
        (response.request?.url ?? uri).toString(),
      );
      if (directUri.scheme != 'https' ||
          !(directUri.host == 'drive.google.com' ||
              directUri.host == 'drive.usercontent.google.com' ||
              directUri.host.endsWith('.googleusercontent.com'))) {
        throw StateError(
          'Google Drive redirected to an unsupported download host.',
        );
      }
      return directUri;
    } finally {
      if (_publicClient == null) client.close();
    }
  }

  @override
  Future<void> releaseCopy(
    TemporaryMediaLease lease,
    TemporaryMediaCopy copy,
  ) async {
    final api = _connected(lease);
    late GoogleDriveFile file;
    try {
      file = await api.getFileDetails(copy.fileId);
    } on GoogleDriveException catch (error) {
      if (error.status == 404) return;
      rethrow;
    }
    // Lost/deleted parent access must not be confused with a deleted copy.
    // Tags and ownership identify our copy even if someone moved its folder.
    await _ownedCopy(api, lease, copy, details: file, verifyParent: false);
    final permissions = await api.listPermissions(file.id);
    for (final permission in permissions) {
      if (permission.type == 'anyone' && !permission.inherited) {
        _connected(lease);
        await api.deletePermission(file.id, permission.id);
      }
    }
    if (!_onlyOwner(await api.listPermissions(file.id))) {
      throw StateError(
        'Temporary media cleanup could not verify private access. Reconnect Google Drive to retry.',
      );
    }
    _connected(lease);
    if (!file.trashed) await api.trashFile(file.id);
  }
}
