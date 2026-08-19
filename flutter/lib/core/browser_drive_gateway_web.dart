import 'package:http/http.dart' as http;

import 'direct_gateway.dart';
import 'gateway.dart';
import 'google_drive.dart';
import 'google_drive_store_web.dart';
import 'models.dart';
import 'provider_api.dart';

AppGateway createBrowserDriveGateway() => BrowserDriveGateway();

class BrowserDriveGateway extends DirectGateway implements GoogleDriveGateway {
  factory BrowserDriveGateway({
    GoogleDriveStore? store,
    http.Client? client,
    ProviderApiRouter? providerRouter,
  }) {
    final driveStore = store ?? GoogleDriveStore(client: client);
    return BrowserDriveGateway._(
      driveStore,
      client: client,
      providerRouter: providerRouter,
    );
  }

  // Separate named parameters keep the factory injectable for browser tests.
  // ignore: use_super_parameters
  BrowserDriveGateway._(
    this._driveStore, {
    http.Client? client,
    ProviderApiRouter? providerRouter,
  }) : super(
         store: _driveStore,
         client: client,
         providerRouter: providerRouter,
         persistenceDescription:
             'Portable metadata and media in Google Drive; API keys stay in this browser only',
         availableProviders: const <String>{'atlas'},
       );

  final GoogleDriveStore _driveStore;

  @override
  GoogleDriveConnection get googleDriveConnection => _driveStore.connection;

  @override
  Future<LocalSnapshot> connectGoogleDrive(String folderName) async {
    await _driveStore.connect(folderName);
    return load();
  }

  @override
  Future<LocalSnapshot> disconnectGoogleDrive() async {
    await _driveStore.disconnect();
    return load();
  }

  @override
  Future<LocalSnapshot> refreshGoogleDrive() async {
    await _driveStore.refresh();
    return load();
  }
}
