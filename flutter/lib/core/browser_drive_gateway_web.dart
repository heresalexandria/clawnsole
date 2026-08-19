import 'package:http/http.dart' as http;

import 'browser_settings_data_store.dart';
import 'direct_gateway.dart';
import 'gateway.dart';
import 'google_drive.dart';
import 'google_drive_auth.dart';
import 'google_drive_store.dart';
import 'hybrid_data_store.dart';
import 'models.dart';
import 'provider_api.dart';

AppGateway createBrowserDriveGateway() => BrowserDriveGateway();

class BrowserDriveGateway extends DirectGateway implements GoogleDriveGateway {
  factory BrowserDriveGateway({
    HybridDataStore? store,
    GoogleDriveAuthorizer? authorizer,
    http.Client? client,
    ProviderApiRouter? providerRouter,
  }) {
    final driveStore =
        store ??
        HybridDataStore(
          local: BrowserSettingsDataStore(),
          drive: GoogleDriveStore(client: client),
          localLibraryAvailable: false,
        );
    return BrowserDriveGateway._(
      driveStore,
      authorizer: authorizer ?? createGoogleDriveAuthorizer(),
      client: client,
      providerRouter: providerRouter,
    );
  }

  // Separate named parameters keep the factory injectable for browser tests.
  // ignore: use_super_parameters
  BrowserDriveGateway._(
    this._driveStore, {
    required GoogleDriveAuthorizer authorizer,
    http.Client? client,
    ProviderApiRouter? providerRouter,
  }) : _authorizer = authorizer,
       super(
         store: _driveStore,
         client: client,
         providerRouter: providerRouter,
         persistenceDescription:
             'Google Drive library with API keys stored only in this browser',
         availableProviders: const <String>{'atlas'},
       );

  final HybridDataStore _driveStore;
  final GoogleDriveAuthorizer _authorizer;

  @override
  bool get supportsLocalLibrary => false;

  @override
  GoogleDriveConnection get googleDriveConnection {
    final connection = _driveStore.connection;
    if (_authorizer.isAvailable || connection.isConfigured) return connection;
    return GoogleDriveConnection(
      state: GoogleDriveConnectionState.unavailable,
      message: _authorizer.unavailableMessage,
    );
  }

  @override
  Future<LocalSnapshot> connectGoogleDrive(String folderName) async {
    final token = await _authorizer.authorize();
    await _driveStore.connect(token, folderName);
    return load();
  }

  @override
  Future<LocalSnapshot> disconnectGoogleDrive() async {
    await _driveStore.disconnect();
    await _authorizer.disconnect();
    return load();
  }

  @override
  Future<LocalSnapshot> refreshGoogleDrive() async {
    final token = await _authorizer.authorize();
    await _driveStore.connect(token, googleDriveConnection.folderName);
    return load();
  }

  @override
  Future<GoogleDriveCopyResult> copyLocalLibraryToGoogleDrive({
    Set<String> generationIds = const <String>{},
    Set<String> referenceIds = const <String>{},
  }) async {
    final copied = await _driveStore.copyLocalToDrive(
      generationIds: generationIds,
      referenceIds: referenceIds,
    );
    return GoogleDriveCopyResult(
      snapshot: await load(),
      generations: copied.generations,
      references: copied.references,
    );
  }
}
