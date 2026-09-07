import 'dart:typed_data';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/google_drive.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/ui/section_tabs.dart';
import 'package:clawnsole/ui/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/settings_tabs.dart';

/// One finder that only ever matches on the named desk.
final Map<SettingsTab, Finder> _marks = <SettingsTab, Finder>{
  SettingsTab.general: find.byKey(
    const ValueKey('generation-placeholder-style'),
  ),
  SettingsTab.defaults: find.text('New drafts start with…'),
  SettingsTab.aiRewrite: find.byKey(const ValueKey('rewrite-key-openai')),
  SettingsTab.storage: find.byKey(const ValueKey('local-video-cache-cap')),
  SettingsTab.sync: find.text('Google Drive library'),
  SettingsTab.data: find.byKey(const ValueKey('clear-Clear history')),
};

void main() {
  testWidgets('the rail carries every desk in order', (tester) async {
    final controller = await _controller(_DriveGateway());
    await _pump(tester, controller);

    final rail = tester.widget<SectionTabRail>(find.byType(SectionTabRail));
    expect(rail.semanticLabel, 'Settings desk');
    expect(rail.tabs.map((tab) => tab.label).toList(), <String>[
      'General',
      'Defaults',
      'AI Rewrite',
      'Storage',
      'Sync',
      'Data',
    ]);
    expect(rail.tabs.map((tab) => tab.key).toList(), <Key>[
      const ValueKey<String>('settings-tab-general'),
      const ValueKey<String>('settings-tab-defaults'),
      const ValueKey<String>('settings-tab-ai-rewrite'),
      const ValueKey<String>('settings-tab-storage'),
      const ValueKey<String>('settings-tab-sync'),
      const ValueKey<String>('settings-tab-data'),
    ]);
    await _close(tester, controller);
  });

  testWidgets('a desk shows its own cards and nobody else’s', (tester) async {
    final controller = await _controller(_DriveGateway());
    await _pump(tester, controller);

    // Settings opens on General.
    expect(_marks[SettingsTab.general], findsOneWidget);
    expect(
      find.byKey(const ValueKey('alexandria-profile-link')),
      findsOneWidget,
    );

    for (final tab in SettingsTab.values) {
      await openSettingsTab(tester, tab);
      expect(
        controller.settingsTab,
        tab,
        reason: 'tapping ${tab.label} should select it',
      );
      for (final other in SettingsTab.values) {
        expect(
          _marks[other]!,
          other == tab ? findsOneWidget : findsNothing,
          reason: 'the ${other.label} card on the ${tab.label} desk',
        );
      }
    }
    await _close(tester, controller);
  });

  testWidgets('a build without Drive has no Sync desk at all', (tester) async {
    final controller = await _controller(_PlainGateway());
    await _pump(tester, controller);

    final rail = tester.widget<SectionTabRail>(find.byType(SectionTabRail));
    expect(rail.tabs.map((tab) => tab.label), isNot(contains('Sync')));
    expect(find.byKey(const ValueKey('settings-tab-sync')), findsNothing);

    // The other five desks are all still reachable.
    for (final tab in SettingsTab.values.where(
      (value) => value != SettingsTab.sync,
    )) {
      await openSettingsTab(tester, tab);
      expect(_marks[tab]!, findsOneWidget);
    }
    await _close(tester, controller);
  });

  testWidgets('a Sync deep link opens Settings on the Sync desk', (
    tester,
  ) async {
    final controller = await _controller(_DriveGateway());
    await _pump(tester, controller);
    expect(controller.settingsTab, SettingsTab.general);

    await controller.openSettings(SettingsTab.sync);
    await tester.pumpAndSettle();

    expect(controller.section, AppSection.settings);
    expect(controller.settingsTab, SettingsTab.sync);
    expect(_marks[SettingsTab.sync]!, findsOneWidget);
    expect(_marks[SettingsTab.general]!, findsNothing);
    await _close(tester, controller);
  });

  testWidgets('a phone scrolls the rail rather than overflowing it', (
    tester,
  ) async {
    final controller = await _controller(_DriveGateway());
    await _pump(tester, controller, size: const Size(390, 844));

    expect(tester.takeException(), isNull);
    // The last desk starts off the right edge and is reached by scrolling.
    await openSettingsTab(tester, SettingsTab.data);
    expect(controller.settingsTab, SettingsTab.data);
    expect(_marks[SettingsTab.data]!, findsOneWidget);
    expect(tester.takeException(), isNull);
    await _close(tester, controller);
  });
}

/// Initialize starts the studio's periodic timers, so every test here hands
/// the controller back to [_close] before it ends.
Future<AppController> _controller(AppGateway gateway) async {
  final controller = AppController(gateway: gateway);
  await controller.initialize();
  return controller;
}

Future<void> _close(WidgetTester tester, AppController controller) async {
  await tester.pumpWidget(const SizedBox.shrink());
  controller.dispose();
}

Future<void> _pump(
  WidgetTester tester,
  AppController controller, {
  Size size = const Size(1000, 2400),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildClawnsoleTheme(Brightness.light),
      home: Scaffold(body: SettingsScreen(controller: controller)),
    ),
  );
  await tester.pumpAndSettle();
}

class _PlainGateway implements AppGateway {
  LocalSnapshot snapshot = const LocalSnapshot(
    generations: <Generation>[],
    preferences: AppPreferences(),
    hasApiKey: false,
    storage: StorageStats(path: 'memory', bytes: 0, records: 0),
  );

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
  Future<double> getCredits() async => 1000;

  @override
  Future<Generation> poll(Generation generation) async => generation;

  @override
  Future<Uint8List> readAsset(AssetReference reference) async => Uint8List(0);

  @override
  Uri mediaUri(String source) => Uri.parse(source);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A gateway that reaches Drive, so the Sync desk has something to show.
class _DriveGateway extends _PlainGateway implements GoogleDriveGateway {
  @override
  bool get supportsLocalLibrary => true;

  @override
  GoogleDriveConnection get googleDriveConnection =>
      const GoogleDriveConnection(
        state: GoogleDriveConnectionState.disconnected,
        folderName: 'Clawnsole',
      );

  @override
  Future<LocalSnapshot?> resumeGoogleDrive({bool force = false}) async => null;
}
