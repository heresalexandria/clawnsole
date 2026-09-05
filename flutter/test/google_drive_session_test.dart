import 'dart:async';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/google_drive.dart';
import 'package:clawnsole/core/google_drive_session.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/provider_manifest.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _snapshot = LocalSnapshot(
  generations: [],
  preferences: AppPreferences(),
  hasApiKey: false,
  storage: StorageStats(path: 'memory', bytes: 0, records: 0),
);

class _SessionGateway implements AppGateway, GoogleDriveGateway {
  bool connected = false;
  bool failRenewal = false;
  Completer<LocalSnapshot?>? renewal;
  final silentCalls = <bool>[];
  int interactiveCalls = 0;

  @override
  bool get usesCompanion => false;
  @override
  bool get supportsPhotoLibrarySave => false;
  @override
  bool get supportsLocalLibrary => true;
  @override
  GoogleDriveConnection get googleDriveConnection => GoogleDriveConnection(
    state: connected
        ? GoogleDriveConnectionState.connected
        : GoogleDriveConnectionState.disconnected,
    folderName: 'Test studio',
    folderId: 'test-folder',
  );
  @override
  Future<LocalSnapshot> load() async => _snapshot;
  @override
  Future<LocalSnapshot?> resumeGoogleDrive({bool force = false}) async {
    silentCalls.add(force);
    final value = renewal != null
        ? await renewal!.future
        : failRenewal
        ? null
        : _snapshot;
    if (value != null) connected = true;
    return value;
  }

  @override
  Future<LocalSnapshot> connectGoogleDrive(String folderName) async {
    interactiveCalls++;
    connected = true;
    return _snapshot;
  }

  @override
  Future<LocalSnapshot> refreshGoogleDrive() => connectGoogleDrive('');
  @override
  Future<LocalSnapshot> disconnectGoogleDrive() async {
    connected = false;
    return _snapshot;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AppController _controller(_SessionGateway gateway, WidgetTester tester) {
  final client = MockClient((_) async => http.Response('{}', 503));
  addTearDown(client.close);
  final controller = AppController(
    gateway: gateway,
    driveSessionSchedule: GoogleDriveSessionSchedule(
      clock: tester.binding.clock.now,
    ),
    providerCatalogClient: ProviderCatalogClient(client: client),
  );
  return controller;
}

Future<void> _advance(WidgetTester tester, Duration duration) async {
  // Pump each maintenance tick so asynchronous reconciliation settles between
  // ticks, just as it does during an open real-world studio session.
  for (var seconds = 0; seconds < duration.inSeconds; seconds += 4) {
    await tester.pump(const Duration(seconds: 4));
  }
}

void main() {
  testWidgets('eight hours in foreground renews without user interaction', (
    tester,
  ) async {
    final gateway = _SessionGateway();
    final controller = _controller(gateway, tester);
    await controller.initialize();
    await tester.pump();
    expect(gateway.silentCalls, [false]);

    await _advance(tester, const Duration(hours: 8));

    expect(gateway.silentCalls, [false, ...List.filled(10, true)]);
    expect(gateway.interactiveCalls, 0);
    expect(controller.googleDriveConnected, isTrue);
    expect(controller.loadError, isNull);
    expect(controller.notice, isNull);
    controller.dispose();
  });

  testWidgets('expired sessions reconnect on the next maintenance pass', (
    tester,
  ) async {
    final gateway = _SessionGateway();
    final controller = _controller(gateway, tester);
    await controller.initialize();
    await tester.pump();
    gateway.connected = false;

    await _advance(tester, const Duration(seconds: 4));

    expect(gateway.silentCalls, [false, true]);
    expect(controller.googleDriveConnected, isTrue);
    expect(gateway.interactiveCalls, 0);
    controller.dispose();
  });

  testWidgets('offline startup retries with backoff and later recovers', (
    tester,
  ) async {
    final gateway = _SessionGateway()..failRenewal = true;
    final controller = _controller(gateway, tester);
    await controller.initialize();
    await tester.pump();
    await _advance(tester, const Duration(seconds: 28));
    expect(gateway.silentCalls, [false]);
    await _advance(tester, const Duration(seconds: 4));
    expect(gateway.silentCalls, [false, true]);
    await _advance(tester, const Duration(seconds: 56));
    expect(gateway.silentCalls, [false, true]);
    await _advance(tester, const Duration(seconds: 4));
    expect(gateway.silentCalls, [false, true, true]);

    gateway.failRenewal = false;
    await _advance(tester, const Duration(seconds: 120));
    expect(gateway.silentCalls, [false, true, true, true]);
    expect(controller.googleDriveConnected, isTrue);
    expect(controller.notice, isNull);
    expect(gateway.interactiveCalls, 0);
    controller.dispose();
  });

  testWidgets('slow renewals never overlap across polling ticks', (
    tester,
  ) async {
    final gateway = _SessionGateway()..renewal = Completer<LocalSnapshot?>();
    final controller = _controller(gateway, tester);
    await controller.initialize();
    await _advance(tester, const Duration(minutes: 2));
    expect(gateway.silentCalls, [false]);
    gateway.renewal!.complete(_snapshot);
    await tester.pump();
    expect(controller.googleDriveConnected, isTrue);
    await _advance(tester, const Duration(minutes: 1));
    expect(gateway.silentCalls, [false]);
    controller.dispose();
  });

  testWidgets('intentional signout stays signed out until reconnect', (
    tester,
  ) async {
    final gateway = _SessionGateway();
    final controller = _controller(gateway, tester);
    await controller.initialize();
    await tester.pump();
    await controller.disconnectGoogleDrive();
    await _advance(tester, const Duration(hours: 1));
    await controller.resumeGoogleDrive(force: true);
    expect(gateway.silentCalls, [false]);
    expect(controller.googleDriveConnected, isFalse);

    await controller.connectGoogleDrive('Test studio');
    await _advance(tester, const Duration(minutes: 46));
    expect(gateway.interactiveCalls, 1);
    expect(gateway.silentCalls, [false, true]);
    expect(controller.googleDriveConnected, isTrue);
    controller.dispose();
  });

  test('repeated failed grants stop at a five-minute retry interval', () {
    var now = DateTime.utc(2026, 9, 5);
    final schedule = GoogleDriveSessionSchedule(clock: () => now);
    for (final seconds in [30, 60, 120, 240, 300, 300, 300]) {
      schedule.failed(connected: false);
      now = now.add(Duration(seconds: seconds - 1));
      expect(schedule.isDue(connected: false, configured: true), isFalse);
      now = now.add(const Duration(seconds: 1));
      expect(schedule.isDue(connected: false, configured: true), isTrue);
    }
  });
}
