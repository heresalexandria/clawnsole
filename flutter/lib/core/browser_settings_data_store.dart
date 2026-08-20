import 'dart:convert';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'durable_data_store.dart';
import 'models.dart';

const _deviceDataKey = 'clawnsole.web.deviceData.v2';
const _legacyApiKeysKey = 'clawnsole.web.apiKeys.v1';
const _legacyPreferencesKey = 'clawnsole.web.preferences.v1';
const _legacyDriveFolderNameKey = 'clawnsole.web.driveFolderName.v1';
const _legacyDriveFolderIdKey = 'clawnsole.web.driveFolderId.v1';

/// Device-only settings for the standalone browser build.
///
/// Media and library records are intentionally rejected here; they must be
/// stored in the connected Drive library.
class BrowserSettingsDataStore implements DurableDataStore {
  @override
  Future<StoredData> read() async {
    final saved = web.window.localStorage.getItem(_deviceDataKey);
    if (saved != null && saved.isNotEmpty) {
      try {
        return StoredData.decode(saved);
      } on FormatException {
        // Fall through to the v1 migration below.
      }
    }
    final keys = _decodeMap(web.window.localStorage.getItem(_legacyApiKeysKey));
    final preferences = _decodeMap(
      web.window.localStorage.getItem(_legacyPreferencesKey),
    );
    final migrated = StoredData(
      apiKey: keys['bfl']?.toString() ?? '',
      apiKeys: keys.map((key, value) => MapEntry(key, value?.toString() ?? ''))
        ..removeWhere((key, value) => value.isEmpty),
      preferences: AppPreferences.fromJson(
        preferences,
      ).copyWithStorageDefault(),
      driveFolderName:
          web.window.localStorage.getItem(_legacyDriveFolderNameKey) ?? '',
      driveFolderId:
          web.window.localStorage.getItem(_legacyDriveFolderIdKey) ?? '',
    );
    await write(migrated);
    return migrated;
  }

  @override
  Future<void> write(StoredData data) async {
    final device = StoredData(
      apiKey: data.apiKey,
      apiKeys: data.apiKeys,
      preferences: data.preferences,
      preferencesUpdatedAt: data.preferencesUpdatedAt,
      driveFolderName: data.driveFolderName,
      driveFolderId: data.driveFolderId,
    );
    web.window.localStorage.setItem(_deviceDataKey, device.encode());
  }

  @override
  Future<void> delete() async {
    web.window.localStorage.removeItem(_deviceDataKey);
    web.window.localStorage.removeItem(_legacyApiKeysKey);
    web.window.localStorage.removeItem(_legacyPreferencesKey);
    web.window.localStorage.removeItem(_legacyDriveFolderNameKey);
    web.window.localStorage.removeItem(_legacyDriveFolderIdKey);
  }

  @override
  Future<AssetReference> writeAsset(
    Uint8List bytes, {
    required String label,
    required String contentType,
    LibraryStorage storage = LibraryStorage.local,
  }) => throw StateError(
    'The standalone browser stores generated media in Google Drive.',
  );

  @override
  Future<AssetReference?> persistSource(
    String source, {
    required String label,
    AssetReference? retained,
    LibraryStorage storage = LibraryStorage.local,
  }) => throw StateError(
    'The standalone browser stores retained media in Google Drive.',
  );

  @override
  Future<Uint8List> readAsset(AssetReference reference) =>
      throw StateError('That media is not stored in this browser.');

  @override
  Future<Uri> assetUri(AssetReference reference) =>
      throw StateError('That media is not stored in this browser.');

  @override
  Future<void> pruneAssets(
    List<Generation> generations, [
    List<SavedReference> savedReferences = const <SavedReference>[],
  ]) async {}

  @override
  Future<StorageStats> stats(int records) async {
    final bytes = utf8
        .encode(web.window.localStorage.getItem(_deviceDataKey) ?? '')
        .length;
    return StorageStats(
      path: 'Browser-local settings and API keys',
      bytes: bytes,
      records: 0,
    );
  }

  Map<String, Object?> _decodeMap(String? source) {
    if (source == null || source.isEmpty) return <String, Object?>{};
    try {
      final value = jsonDecode(source);
      if (value is Map<Object?, Object?>) {
        return value.map((key, child) => MapEntry(key.toString(), child));
      }
    } on FormatException {
      // Corrupt device settings fall back to defaults; Drive is untouched.
    }
    return <String, Object?>{};
  }
}

extension on AppPreferences {
  AppPreferences copyWithStorageDefault() => AppPreferences(
    activeSection: activeSection,
    libraryFilter: libraryFilter,
    recentWorkViewMode: recentWorkViewMode,
    libraryViewMode: libraryViewMode,
    provider: provider,
    model: model,
    defaultStorage: LibraryStorage.drive,
    libraryStorageFilter: libraryStorageFilter,
    referenceStorageFilter: referenceStorageFilter,
  );
}
