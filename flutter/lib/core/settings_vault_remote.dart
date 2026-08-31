import 'dart:typed_data';

import 'google_drive.dart';

const clawnsoleSettingsVaultFile = 'clawnsole-vault.json';
const clawnsoleSettingsVaultMaxBytes = 1024 * 1024;

class SettingsVaultRemoteDocument {
  const SettingsVaultRemoteDocument(this.bytes, {this.etag});

  final Uint8List bytes;
  final String? etag;
}

abstract interface class SettingsVaultRemote {
  bool get isConnected;

  Future<SettingsVaultRemoteDocument?> connect(
    String accessToken,
    String folderId,
  );

  Future<SettingsVaultRemoteDocument?> read();

  Future<SettingsVaultRemoteDocument> write(
    Uint8List bytes, {
    String? expectedEtag,
  });

  Future<void> disconnect();
  Future<void> delete();
}

typedef SettingsVaultApiFactory = GoogleDriveApi Function(String accessToken);

class GoogleDriveSettingsVaultRemote implements SettingsVaultRemote {
  GoogleDriveSettingsVaultRemote({SettingsVaultApiFactory? apiFactory})
    : _apiFactory = apiFactory;

  final SettingsVaultApiFactory? _apiFactory;
  GoogleDriveApi? _api;
  GoogleDriveFile? _file;
  String _folderId = '';

  @override
  bool get isConnected => _api != null && _folderId.isNotEmpty;

  @override
  Future<SettingsVaultRemoteDocument?> connect(
    String accessToken,
    String folderId,
  ) async {
    final token = accessToken.trim();
    final parent = folderId.trim();
    if (token.isEmpty || parent.isEmpty) {
      throw StateError('Connect Google Drive before syncing secure settings.');
    }
    _api = _apiFactory?.call(token) ?? GoogleDriveApi(accessToken: token);
    _folderId = parent;
    _file = await _api!.findChild(
      parent,
      clawnsoleSettingsVaultFile,
      appPropertyKey: 'clawnsoleSettingsVault',
    );
    return read();
  }

  @override
  Future<SettingsVaultRemoteDocument?> read() async {
    _requireConnected();
    final file = _file;
    if (file == null) return null;
    final content = (await _api!.readFile(file.id))!;
    _checkSize(content.bytes);
    _file = GoogleDriveFile(
      id: file.id,
      name: file.name,
      mimeType: file.mimeType,
      size: content.bytes.length,
      modifiedTime: file.modifiedTime,
      etag: content.etag,
    );
    return SettingsVaultRemoteDocument(content.bytes, etag: content.etag);
  }

  @override
  Future<SettingsVaultRemoteDocument> write(
    Uint8List bytes, {
    String? expectedEtag,
  }) async {
    _requireConnected();
    _checkSize(bytes);
    if (_file == null) {
      _file = await _api!.createFile(
        parentId: _folderId,
        name: clawnsoleSettingsVaultFile,
        bytes: bytes,
        contentType: 'application/json',
        appProperties: const <String, String>{
          'clawnsoleSettingsVault': 'true',
          'schema': '1',
        },
      );
    } else {
      _file = await _api!.updateFile(
        _file!.id,
        bytes,
        contentType: 'application/json',
        etag: expectedEtag ?? _file!.etag,
      );
    }
    return SettingsVaultRemoteDocument(bytes, etag: _file!.etag);
  }

  @override
  Future<void> disconnect() async {
    _api = null;
    _file = null;
    _folderId = '';
  }

  @override
  Future<void> delete() async {
    _requireConnected();
    final file = _file;
    if (file == null) return;
    await _api!.deleteFile(file.id);
    _file = null;
  }

  void _requireConnected() {
    if (!isConnected) {
      throw StateError('Connect Google Drive before syncing secure settings.');
    }
  }

  void _checkSize(Uint8List bytes) {
    if (bytes.length > clawnsoleSettingsVaultMaxBytes) {
      throw StateError('The encrypted settings vault is unexpectedly large.');
    }
  }
}
