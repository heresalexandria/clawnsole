import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'models.dart';

const googleDriveFileScope = 'https://www.googleapis.com/auth/drive.file';
const clawnsoleDriveStateFile = 'clawnsole.json';
const clawnsoleDriveAssetsFolder = 'assets';

/// Removes credentials and preferences before library data is serialized.
/// Both are synchronized only through the independently encrypted settings
/// vault; this file remains portable generation and asset metadata.
StoredData googleDrivePortableData(StoredData data) => StoredData(
  generations: data.generations,
  folders: data.folders,
  savedReferences: data.savedReferences,
);

/// Applies one device's changes to the latest Drive snapshot. This preserves
/// unrelated additions and updates made by another device between reads.
StoredData mergeGoogleDriveData({
  required StoredData base,
  required StoredData next,
  required StoredData remote,
}) {
  final generations = _mergeById<Generation>(
    base: base.generations,
    next: next.generations,
    remote: remote.generations,
    id: (item) => item.localId,
    json: (item) => item.toJson(),
    updatedAt: (item) => item.updatedAt,
  )..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final folders = _mergeById<LibraryFolder>(
    base: base.folders,
    next: next.folders,
    remote: remote.folders,
    id: (item) => item.id,
    json: (item) => item.toJson(),
    updatedAt: (item) => item.updatedAt,
  );
  final references = _mergeById<SavedReference>(
    base: base.savedReferences,
    next: next.savedReferences,
    remote: remote.savedReferences,
    id: (item) => item.id,
    json: (item) => item.toJson(),
    updatedAt: (item) => item.updatedAt,
  )..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return StoredData(
    generations: generations,
    folders: folders,
    savedReferences: references,
  );
}

List<T> _mergeById<T>({
  required List<T> base,
  required List<T> next,
  required List<T> remote,
  required String Function(T item) id,
  required Map<String, Object?> Function(T item) json,
  required DateTime Function(T item) updatedAt,
}) {
  final baseById = <String, T>{for (final item in base) id(item): item};
  final nextById = <String, T>{for (final item in next) id(item): item};
  final merged = <String, T>{for (final item in remote) id(item): item};
  for (final removed in baseById.keys.where(
    (key) => !nextById.containsKey(key),
  )) {
    merged.remove(removed);
  }
  for (final item in next) {
    final key = id(item);
    final previous = baseById[key];
    if (previous == null ||
        jsonEncode(json(previous)) != jsonEncode(json(item))) {
      final remoteItem = merged[key];
      final remoteAlsoChanged =
          previous != null &&
          remoteItem != null &&
          jsonEncode(json(previous)) != jsonEncode(json(remoteItem));
      if (!remoteAlsoChanged) {
        merged[key] = item;
        continue;
      }
      final timestamp = updatedAt(item).compareTo(updatedAt(remoteItem));
      if (timestamp > 0 ||
          (timestamp == 0 &&
              jsonEncode(json(item)).compareTo(jsonEncode(json(remoteItem))) >=
                  0)) {
        merged[key] = item;
      }
    }
  }
  return merged.values.toList();
}

enum GoogleDriveConnectionState {
  unavailable,
  disconnected,
  connecting,
  connected,
}

class GoogleDriveConnection {
  const GoogleDriveConnection({
    required this.state,
    this.folderName = '',
    this.folderId = '',
    this.message = '',
  });

  final GoogleDriveConnectionState state;
  final String folderName;
  final String folderId;
  final String message;

  bool get isConnected => state == GoogleDriveConnectionState.connected;
  bool get isConfigured => folderName.isNotEmpty || folderId.isNotEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'state': state.name,
    'folderName': folderName,
    'folderId': folderId,
    'message': message,
  };

  factory GoogleDriveConnection.fromJson(Map<String, Object?> json) =>
      GoogleDriveConnection(
        state: GoogleDriveConnectionState.values.firstWhere(
          (value) => value.name == json['state'],
          orElse: () => GoogleDriveConnectionState.disconnected,
        ),
        folderName: json['folderName'] as String? ?? '',
        folderId: json['folderId'] as String? ?? '',
        message: json['message'] as String? ?? '',
      );
}

abstract interface class GoogleDriveGateway {
  GoogleDriveConnection get googleDriveConnection;
  bool get supportsLocalLibrary;

  /// Authorizes Drive and creates or reopens an app-owned folder by name.
  Future<LocalSnapshot> connectGoogleDrive(String folderName);

  /// Forgets the in-memory Drive access token but does not delete cloud data.
  Future<LocalSnapshot> disconnectGoogleDrive();

  Future<LocalSnapshot> refreshGoogleDrive();

  /// Reattaches a previously configured Drive connection without any user
  /// interaction, for example at app startup. [force] also replaces a session
  /// that still looks connected locally, which is necessary after a mobile
  /// access token expires while the app is suspended. Returns the refreshed
  /// snapshot when a silent grant succeeded, or null when none was possible;
  /// never throws and never opens a sign-in surface.
  Future<LocalSnapshot?> resumeGoogleDrive({bool force = false});

  /// Copies local records and retained assets into Drive without deleting the
  /// local originals. Stable `drive-` ids make the operation idempotent.
  Future<GoogleDriveCopyResult> copyLocalLibraryToGoogleDrive({
    Set<String> generationIds = const <String>{},
    Set<String> referenceIds = const <String>{},
  });

  /// Moves the whole local library into Drive: copies every local record and
  /// retained asset, verifies each copy exists, then removes the local
  /// originals. The Drive folder linkage stays in the local data file.
  Future<GoogleDriveCopyResult> moveLocalLibraryToGoogleDrive();
}

class GoogleDriveCopyResult {
  const GoogleDriveCopyResult({
    required this.snapshot,
    required this.generations,
    required this.references,
  });

  final LocalSnapshot snapshot;
  final int generations;
  final int references;
}

class GoogleDriveFile {
  const GoogleDriveFile({
    required this.id,
    required this.name,
    required this.mimeType,
    this.size = 0,
    this.modifiedTime,
    this.etag,
  });

  final String id;
  final String name;
  final String mimeType;
  final int size;
  final DateTime? modifiedTime;
  final String? etag;

  factory GoogleDriveFile.fromJson(Map<String, Object?> json, {String? etag}) =>
      GoogleDriveFile(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
        size: int.tryParse(json['size']?.toString() ?? '') ?? 0,
        modifiedTime: DateTime.tryParse(json['modifiedTime'] as String? ?? ''),
        etag: etag,
      );
}

class GoogleDriveContent {
  const GoogleDriveContent(this.bytes, {this.etag});

  final Uint8List bytes;
  final String? etag;
}

/// A media download delivered as a byte stream instead of a buffered body,
/// so large videos can be written to disk with progress as they arrive.
class GoogleDriveByteStream {
  const GoogleDriveByteStream(this.stream, {this.contentLength});

  final Stream<List<int>> stream;

  /// Total bytes announced by Drive, or null when the response did not
  /// include a usable length.
  final int? contentLength;
}

/// Small REST client for the subset of Drive used by Clawnsole.
class GoogleDriveApi {
  GoogleDriveApi({
    required String accessToken,
    http.Client? client,
    Uri? apiBase,
    Uri? uploadBase,
  }) : _accessToken = accessToken,
       _client = client ?? http.Client(),
       _apiBase = apiBase ?? Uri.parse('https://www.googleapis.com/drive/v3/'),
       _uploadBase =
           uploadBase ??
           Uri.parse('https://www.googleapis.com/upload/drive/v3/');

  final String _accessToken;
  final http.Client _client;
  final Uri _apiBase;
  final Uri _uploadBase;

  Map<String, String> get _headers => <String, String>{
    'Authorization': 'Bearer $_accessToken',
    'Accept': 'application/json',
  };

  Future<GoogleDriveFile?> findRootFolder(String name) async {
    final files = await _list(
      "mimeType = 'application/vnd.google-apps.folder' and "
      "appProperties has { key='clawnsoleRoot' and value='true' } and "
      "name = '${_queryValue(name)}' and trashed = false",
    );
    return files.firstOrNull;
  }

  Future<GoogleDriveFile?> findChild(
    String parentId,
    String name, {
    String? appPropertyKey,
    String? appPropertyValue,
  }) async {
    final property = appPropertyKey == null
        ? ''
        : " and appProperties has { key='${_queryValue(appPropertyKey)}' "
              "and value='${_queryValue(appPropertyValue ?? 'true')}' }";
    final files = await _list(
      "'${_queryValue(parentId)}' in parents and "
      "name = '${_queryValue(name)}' and trashed = false$property",
    );
    return files.firstOrNull;
  }

  Future<List<GoogleDriveFile>> listChildren(
    String parentId, {
    String? appPropertyKey,
    String? appPropertyValue,
  }) {
    final property = appPropertyKey == null
        ? ''
        : " and appProperties has { key='${_queryValue(appPropertyKey)}' "
              "and value='${_queryValue(appPropertyValue ?? 'true')}' }";
    return _list(
      "'${_queryValue(parentId)}' in parents and trashed = false$property",
    );
  }

  Future<List<GoogleDriveFile>> _list(String query) async {
    final files = <GoogleDriveFile>[];
    String? pageToken;
    do {
      final response = await _client.get(
        _apiBase
            .resolve('files')
            .replace(
              queryParameters: <String, String>{
                'q': query,
                'spaces': 'drive',
                'pageSize': '100',
                'orderBy': 'modifiedTime desc',
                'fields':
                    'nextPageToken,files(id,name,mimeType,size,modifiedTime,appProperties)',
                if (pageToken != null) 'pageToken': pageToken,
              },
            ),
        headers: _headers,
      );
      final payload = _json(await _expect(response));
      files.addAll(
        (payload['files'] as List<Object?>? ?? const <Object?>[])
            .whereType<Map<Object?, Object?>>()
            .map(
              (item) => GoogleDriveFile.fromJson(
                item.map((key, value) => MapEntry(key.toString(), value)),
              ),
            )
            .where((item) => item.id.isNotEmpty),
      );
      pageToken = switch (payload['nextPageToken']) {
        final String value when value.isNotEmpty => value,
        _ => null,
      };
    } while (pageToken != null);
    return files;
  }

  Future<GoogleDriveFile> createFolder(
    String name, {
    String? parentId,
    Map<String, String> appProperties = const <String, String>{},
  }) async {
    final response = await _client.post(
      _apiBase
          .resolve('files')
          .replace(
            queryParameters: const <String, String>{
              'fields': 'id,name,mimeType,size,modifiedTime',
            },
          ),
      headers: <String, String>{
        ..._headers,
        'Content-Type': 'application/json',
      },
      body: jsonEncode(<String, Object?>{
        'name': name,
        'mimeType': 'application/vnd.google-apps.folder',
        if (parentId != null) 'parents': <String>[parentId],
        if (appProperties.isNotEmpty) 'appProperties': appProperties,
      }),
    );
    return GoogleDriveFile.fromJson(
      _json(await _expect(response)),
      etag: response.headers['etag'],
    );
  }

  Future<GoogleDriveFile> createFile({
    required String parentId,
    required String name,
    required Uint8List bytes,
    required String contentType,
    Map<String, String> appProperties = const <String, String>{},
  }) async {
    final boundary =
        'clawnsole-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
    final metadata = utf8.encode(
      jsonEncode(<String, Object?>{
        'name': name,
        'parents': <String>[parentId],
        if (appProperties.isNotEmpty) 'appProperties': appProperties,
      }),
    );
    final body = BytesBuilder(copy: false)
      ..add(utf8.encode('--$boundary\r\n'))
      ..add(
        utf8.encode('Content-Type: application/json; charset=UTF-8\r\n\r\n'),
      )
      ..add(metadata)
      ..add(utf8.encode('\r\n--$boundary\r\n'))
      ..add(utf8.encode('Content-Type: $contentType\r\n\r\n'))
      ..add(bytes)
      ..add(utf8.encode('\r\n--$boundary--\r\n'));
    final request =
        http.Request(
            'POST',
            _uploadBase
                .resolve('files')
                .replace(
                  queryParameters: const <String, String>{
                    'uploadType': 'multipart',
                    'fields': 'id,name,mimeType,size,modifiedTime',
                  },
                ),
          )
          ..headers.addAll(<String, String>{
            ..._headers,
            'Content-Type': 'multipart/related; boundary=$boundary',
          })
          ..bodyBytes = body.takeBytes();
    final response = await http.Response.fromStream(
      await _client.send(request),
    );
    return GoogleDriveFile.fromJson(
      _json(await _expect(response)),
      etag: response.headers['etag'],
    );
  }

  Future<GoogleDriveFile> updateFile(
    String fileId,
    Uint8List bytes, {
    required String contentType,
    String? etag,
  }) async {
    final request =
        http.Request(
            'PATCH',
            _uploadBase
                .resolve('files/${Uri.encodeComponent(fileId)}')
                .replace(
                  queryParameters: const <String, String>{
                    'uploadType': 'media',
                    'fields': 'id,name,mimeType,size,modifiedTime',
                  },
                ),
          )
          ..headers.addAll(<String, String>{
            ..._headers,
            'Content-Type': contentType,
            if (etag != null && etag.isNotEmpty) 'If-Match': etag,
          })
          ..bodyBytes = bytes;
    final response = await http.Response.fromStream(
      await _client.send(request),
    );
    return GoogleDriveFile.fromJson(
      _json(await _expect(response)),
      etag: response.headers['etag'],
    );
  }

  Future<GoogleDriveContent> readFile(String fileId) async {
    final response = await _client.get(
      _apiBase
          .resolve('files/${Uri.encodeComponent(fileId)}')
          .replace(queryParameters: const <String, String>{'alt': 'media'}),
      headers: _headers,
    );
    await _expect(response, decodeBody: false);
    return GoogleDriveContent(
      response.bodyBytes,
      etag: response.headers['etag'],
    );
  }

  Future<Uint8List> downloadFile(String fileId) async =>
      (await readFile(fileId)).bytes;

  Uri _mediaUri(String fileId) => _apiBase
      .resolve('files/${Uri.encodeComponent(fileId)}')
      .replace(queryParameters: const <String, String>{'alt': 'media'});

  /// Streams a media download without buffering the file in memory.
  ///
  /// [readFile] remains the right call for small JSON and state documents;
  /// this one exists for videos, where the whole point is not to hold the
  /// body in RAM and to observe byte progress while it lands on disk.
  Future<GoogleDriveByteStream> readFileStream(String fileId) async {
    final request = http.Request('GET', _mediaUri(fileId))
      ..headers.addAll(_headers);
    final response = await _client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await _expect(await http.Response.fromStream(response));
    }
    final length = response.contentLength;
    return GoogleDriveByteStream(
      response.stream,
      contentLength: length != null && length > 0 ? length : null,
    );
  }

  /// Reads one byte range of a media file. Drive honors Range for
  /// `alt=media`; a server that answers 200 anyway is sliced locally so the
  /// caller always receives exactly the requested window.
  Future<Uint8List> readFileRange(String fileId, int start, int end) async {
    if (start < 0 || end < start) {
      throw ArgumentError('The requested byte range is invalid.');
    }
    final response = await _client.get(
      _mediaUri(fileId),
      headers: <String, String>{..._headers, 'Range': 'bytes=$start-$end'},
    );
    await _expect(response, decodeBody: false);
    final bytes = response.bodyBytes;
    if (response.statusCode == 206) return bytes;
    final from = start.clamp(0, bytes.length);
    final to = (end + 1).clamp(from, bytes.length);
    return Uint8List.sublistView(bytes, from, to);
  }

  Future<void> deleteFile(String fileId) async {
    final response = await _client.delete(
      _apiBase.resolve('files/${Uri.encodeComponent(fileId)}'),
      headers: _headers,
    );
    await _expect(response, decodeBody: false);
  }

  Future<http.Response> _expect(
    http.Response response, {
    bool decodeBody = true,
  }) async {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }
    var message = 'Google Drive returned HTTP ${response.statusCode}.';
    if (decodeBody || response.body.isNotEmpty) {
      try {
        final payload = _json(response);
        final error = payload['error'];
        if (error is Map<Object?, Object?>) {
          message = error['message']?.toString() ?? message;
        }
      } on FormatException {
        // Keep the status-based message for a non-JSON response.
      }
    }
    throw GoogleDriveException(message, status: response.statusCode);
  }

  Map<String, Object?> _json(http.Response response) {
    final value = jsonDecode(utf8.decode(response.bodyBytes));
    if (value is! Map<Object?, Object?>) {
      throw const FormatException('Google Drive returned invalid JSON.');
    }
    return value.map((key, child) => MapEntry(key.toString(), child));
  }

  String _queryValue(String value) =>
      value.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
}

class GoogleDriveException implements Exception {
  const GoogleDriveException(this.message, {this.status});

  final String message;
  final int? status;

  @override
  String toString() => message;
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
