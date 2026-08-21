import 'dart:typed_data';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/core/data_location.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/google_drive.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/ui/common_widgets.dart';
import 'package:clawnsole/ui/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<AppController> controllerFor(_DataLocationGateway gateway) async {
    final controller = AppController(gateway: gateway);
    await controller.initialize();
    return controller;
  }

  Future<void> pumpSettings(
    WidgetTester tester,
    AppController controller,
  ) async {
    await tester.binding.setSurfaceSize(const Size(850, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildClawnsoleTheme(Brightness.light),
        home: Scaffold(
          body: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => SettingsScreen(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('storage section offers reveal and relocation per capability', (
    tester,
  ) async {
    final gateway = _DataLocationGateway(
      supportsRevealDataFolder: true,
      supportsDataRelocation: true,
      shellManagesDataRelocation: true,
    );
    final controller = await controllerFor(gateway);
    await pumpSettings(tester, controller);

    final openFolder = find.byKey(const ValueKey('storage-open-folder'));
    final changeLocation = find.byKey(
      const ValueKey('storage-change-location'),
    );
    expect(openFolder, findsOneWidget);
    expect(changeLocation, findsOneWidget);

    await tester.ensureVisible(openFolder);
    await tester.tap(openFolder);
    await tester.pumpAndSettle();
    expect(gateway.revealCalls, 1);

    await tester.ensureVisible(changeLocation);
    await tester.tap(changeLocation);
    await tester.pumpAndSettle();
    expect(gateway.shellRelocationCalls, 1);
    expect(controller.notice, contains('reopening from the new data folder'));
    controller.dispose();
  });

  testWidgets('storage controls stay hidden without the capabilities', (
    tester,
  ) async {
    final controller = await controllerFor(_DataLocationGateway());
    await pumpSettings(tester, controller);

    expect(find.byKey(const ValueKey('storage-open-folder')), findsNothing);
    expect(find.byKey(const ValueKey('storage-change-location')), findsNothing);
    controller.dispose();
  });

  testWidgets('the default destination is visible before Drive connects', (
    tester,
  ) async {
    final controller = await controllerFor(_DataLocationGateway());
    await pumpSettings(tester, controller);

    final destination = find.byType(StorageDestinationButton);
    expect(destination, findsOneWidget);
    expect(
      find.text('Default for new generations and references'),
      findsOneWidget,
    );

    await tester.ensureVisible(destination);
    await tester.tap(destination);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Google Drive').last);
    await tester.pumpAndSettle();

    expect(controller.defaultStorage, LibraryStorage.local);
    expect(controller.notice, contains('Connect Google Drive'));
    controller.dispose();
  });

  testWidgets('moving the local library to Drive requires confirmation', (
    tester,
  ) async {
    final gateway = _DataLocationGateway(
      driveConnected: true,
      localGenerations: 1,
    );
    final controller = await controllerFor(gateway);
    await pumpSettings(tester, controller);

    final moveButton = find.byKey(const ValueKey('drive-move-local-library'));
    expect(moveButton, findsOneWidget);

    await tester.ensureVisible(moveButton);
    await tester.tap(moveButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(gateway.moveCalls, 0);

    await tester.tap(moveButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('drive-move-confirm')));
    await tester.pumpAndSettle();
    expect(gateway.moveCalls, 1);
    expect(controller.notice, contains('local copies were removed'));
    controller.dispose();
  });

  testWidgets('the move action is absent while Drive is disconnected', (
    tester,
  ) async {
    final controller = await controllerFor(
      _DataLocationGateway(localGenerations: 1),
    );
    await pumpSettings(tester, controller);

    expect(
      find.byKey(const ValueKey('drive-move-local-library')),
      findsNothing,
    );
    controller.dispose();
  });
}

Generation _localGeneration(int index) {
  final now = DateTime.utc(2026, 8, 20);
  return Generation(
    localId: 'local-$index',
    status: 'Ready',
    prompt: 'local clip $index',
    mode: VideoMode.t2v,
    config: const GenerationConfig(
      aspectRatio: '16:9',
      duration: 8,
      resolution: 'hd',
      generateAudio: true,
      safetyTolerance: 2,
      draft: false,
    ),
    createdAt: now,
    updatedAt: now,
  );
}

class _DataLocationGateway
    implements AppGateway, GoogleDriveGateway, DataLocationGateway {
  _DataLocationGateway({
    this.supportsRevealDataFolder = false,
    this.supportsDataRelocation = false,
    this.shellManagesDataRelocation = false,
    this.driveConnected = false,
    int localGenerations = 0,
  }) : snapshot = LocalSnapshot(
         generations: List<Generation>.generate(
           localGenerations,
           _localGeneration,
         ),
         preferences: const AppPreferences(),
         hasApiKey: false,
         storage: const StorageStats(
           path: '/library/clawnsole.json',
           bytes: 24,
           records: 0,
         ),
       );

  LocalSnapshot snapshot;
  final bool driveConnected;
  int revealCalls = 0;
  int shellRelocationCalls = 0;
  int moveCalls = 0;

  @override
  final bool supportsRevealDataFolder;
  @override
  final bool supportsDataRelocation;
  @override
  final bool shellManagesDataRelocation;

  @override
  Future<void> revealDataFolder() async {
    revealCalls += 1;
  }

  @override
  Future<bool> dataDirectoryHasLibrary(String directory) async => false;

  @override
  Future<LocalSnapshot> relocateDataDirectory(
    String directory, {
    bool useExistingLibrary = false,
  }) async => snapshot;

  @override
  Future<ShellDataRelocation> relocateDataDirectoryViaShell() async {
    shellRelocationCalls += 1;
    return const ShellDataRelocation(moved: true);
  }

  @override
  GoogleDriveConnection get googleDriveConnection => GoogleDriveConnection(
    state: driveConnected
        ? GoogleDriveConnectionState.connected
        : GoogleDriveConnectionState.disconnected,
    folderName: driveConnected ? 'Clawnsole' : '',
    folderId: driveConnected ? 'drive-root' : '',
  );

  @override
  bool get supportsLocalLibrary => true;

  @override
  Future<LocalSnapshot> connectGoogleDrive(String folderName) async => snapshot;

  @override
  Future<LocalSnapshot> disconnectGoogleDrive() async => snapshot;

  @override
  Future<LocalSnapshot> refreshGoogleDrive() async => snapshot;

  @override
  Future<LocalSnapshot?> resumeGoogleDrive({bool force = false}) async => null;

  @override
  Future<GoogleDriveCopyResult> copyLocalLibraryToGoogleDrive({
    Set<String> generationIds = const <String>{},
    Set<String> referenceIds = const <String>{},
  }) async =>
      GoogleDriveCopyResult(snapshot: snapshot, generations: 0, references: 0);

  @override
  Future<GoogleDriveCopyResult> moveLocalLibraryToGoogleDrive() async {
    moveCalls += 1;
    snapshot = snapshot.copyWith(generations: const <Generation>[]);
    return GoogleDriveCopyResult(
      snapshot: snapshot,
      generations: 1,
      references: 0,
    );
  }

  @override
  bool get usesCompanion => false;

  @override
  bool get supportsPhotoLibrarySave => false;

  @override
  String get persistenceDescription => 'Memory';

  @override
  Future<LocalSnapshot> load() async => snapshot;

  @override
  Future<LocalSnapshot> setPreferences(AppPreferences preferences) async {
    snapshot = snapshot.copyWith(preferences: preferences);
    return snapshot;
  }

  @override
  Future<LocalSnapshot> setApiKey(String value) async => snapshot;

  @override
  Future<double> verifyKey([String? candidate]) async => 0;

  @override
  Future<double> getCredits() async => 0;

  @override
  Future<Generation> submit(GenerationSubmission submission) async =>
      submission.record;

  @override
  Future<Generation> poll(Generation generation) async => generation;

  @override
  Future<LocalSnapshot> deleteGeneration(String localId) async => snapshot;

  @override
  Future<LocalSnapshot> clearHistory() async => snapshot;

  @override
  Future<LocalSnapshot> clearPreferences() async => snapshot;

  @override
  Future<LocalSnapshot> clearApiKey() async => snapshot;

  @override
  Future<LocalSnapshot> clearAll() async => snapshot;

  @override
  Future<Uri> assetUri(AssetReference reference) async =>
      Uri.parse(reference.value);

  @override
  Future<Uint8List> readAsset(AssetReference reference) async => Uint8List(0);

  @override
  Uri mediaUri(String source) => Uri.parse(source);

  @override
  Future<Uint8List> downloadMedia(String source) async => Uint8List(0);

  @override
  Future<void> saveMediaToPhotoLibrary(
    Uint8List bytes,
    String fileName,
    String contentType,
  ) async {}
}
