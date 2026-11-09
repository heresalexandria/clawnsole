import 'dart:async';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/provider_catalog.dart';
import 'package:clawnsole/core/temporary_media_host.dart';
import 'package:clawnsole/ui/common_widgets.dart';
import 'package:clawnsole/ui/generation_detail_modal.dart';
import 'package:clawnsole/ui/generation_submission.dart';
import 'package:clawnsole/ui/generation_view_widgets.dart';
import 'package:clawnsole/ui/library_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final surface in ['activity', 'library', 'menu', 'detail']) {
    testWidgets('$surface Retry starts a retry instead of reusing settings', (
      tester,
    ) async {
      final controller = _RetryController()..preparing = Completer<void>();
      addTearDown(controller.dispose);
      await _showSurface(tester, controller, surface);
      await _tapRetry(tester, surface);
      expect(controller.retryCalls, 1);
      expect(controller.reuseCalls, 0);
      expect(controller.confirmedRetries, 0);
      if (surface == 'activity' || surface == 'library') {
        expect(find.text('Retrying…'), findsOneWidget);
      }
      controller.preparing!.complete();
      await _settle(tester);
      expect(controller.confirmedRetries, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('detail Retry keeps sharing consent usable after closing', (
    tester,
  ) async {
    final controller = _RetryController()..needsSharing = true;
    addTearDown(controller.dispose);
    await _showSurface(tester, controller, 'detail');
    await _tapRetry(tester, 'detail');
    expect(find.byKey(const ValueKey('detail-close')), findsNothing);
    expect(
      find.byKey(const ValueKey('media-sharing-consent-dialog')),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await _settle(tester);
    expect(controller.confirmedRetries, 0);
    expect(controller.sharingAccepts, 0);
    expect(controller.reuseCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retry warning and suppression use the captured provider', (
    tester,
  ) async {
    final controller = _RetryController()..needsRetentionWarning = true;
    addTearDown(controller.dispose);
    await _showSurface(tester, controller, 'activity');
    await _tapRetry(tester, 'activity');
    final provider = providerById('apipod');
    expect(controller.selectedProvider.id, 'bfl');
    expect(
      find.text('Keep Clawnsole open for ${provider.name}'),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('provider-retention-warning-checkbox')),
    );
    await tester.tap(
      find.byKey(
        const ValueKey('suppress-provider-retention-warning-checkbox'),
      ),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('accept-provider-retention-warning')),
    );
    await _settle(tester);
    expect(controller.acknowledgedProvider, 'apipod');
    expect(controller.confirmedRetries, 1);
    expect(controller.reuseCalls, 0);
  });

  testWidgets('canceling the retry retention warning does not send', (
    tester,
  ) async {
    final controller = _RetryController()..needsRetentionWarning = true;
    addTearDown(controller.dispose);
    await _showSurface(tester, controller, 'library');
    await _tapRetry(tester, 'library');
    await tester.tap(find.text('Cancel'));
    await _settle(tester);
    expect(controller.confirmedRetries, 0);
    expect(controller.acknowledgedProvider, isNull);
    expect(controller.reuseCalls, 0);
  });

  testWidgets('completed generations still reuse their settings', (
    tester,
  ) async {
    final controller = _RetryController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => reuseOrRetryGeneration(
                context,
                controller,
                controller.item.copyWith(status: 'Ready'),
              ),
              child: const Text('Reuse'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Reuse'));
    await _settle(tester);
    expect(controller.reuseCalls, 1);
    expect(controller.retryCalls, 0);
  });
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _showSurface(
  WidgetTester tester,
  _RetryController controller,
  String surface,
) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1400));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: buildClawnsoleTheme(Brightness.light),
      home: Scaffold(
        body: SingleChildScrollView(
          child: switch (surface) {
            'activity' => ActivityCard(
              controller: controller,
              item: controller.item,
            ),
            'library' => GenerationCard(
              controller: controller,
              item: controller.item,
            ),
            'menu' => GenerationActionsMenu(
              controller: controller,
              item: controller.item,
            ),
            _ => Builder(
              builder: (context) => TextButton(
                onPressed: () => showGenerationDetailModal(
                  context,
                  controller: controller,
                  item: controller.item,
                ),
                child: const Text('Open'),
              ),
            ),
          },
        ),
      ),
    ),
  );
  if (surface == 'detail') await tester.tap(find.text('Open'));
  if (surface == 'menu') await tester.tap(find.byTooltip('Generation actions'));
  await _settle(tester);
}

Future<void> _tapRetry(WidgetTester tester, String surface) async {
  final finder = find.byKey(
    ValueKey(switch (surface) {
      'activity' => 'activity-reuse-failed-generation',
      'library' => 'library-reuse-failed-generation',
      'menu' => 'generation-action-reuse',
      _ => 'detail-reuse',
    }),
  );
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await _settle(tester);
}

class _RetryController extends AppController {
  _RetryController() {
    snapshot = LocalSnapshot(
      generations: [item],
      preferences: const AppPreferences(),
      hasApiKey: true,
      storage: const StorageStats(path: 'memory', bytes: 0, records: 1),
    );
    temporaryMediaHostingStatus = const TemporaryMediaHostStatus(
      backendId: 'iCloudDrive',
      available: true,
      activeLeases: 0,
      pendingCleanup: 0,
      accountScope: 'test-account',
      sharingAccepted: false,
      cleanupSemantics: TemporaryMediaCleanupSemantics.deferredExpiry,
    );
  }

  final item = Generation(
    localId: 'failed-generation',
    provider: 'apipod',
    model: 'seedance-2.5-r2v',
    status: 'Error',
    error: 'The saved video file is missing.',
    prompt: 'Use the saved reference.',
    mode: VideoMode.i2v,
    config: const GenerationConfig(
      aspectRatio: '16:9',
      duration: 5,
      resolution: 'hd',
      generateAudio: false,
      safetyTolerance: 2,
      draft: false,
    ),
    createdAt: DateTime.utc(2026, 11, 9),
    updatedAt: DateTime.utc(2026, 11, 9),
  );
  int retryCalls = 0;
  int reuseCalls = 0;
  int confirmedRetries = 0;
  int sharingAccepts = 0;
  bool needsSharing = false;
  bool needsRetentionWarning = false;
  String? acknowledgedProvider;
  Completer<void>? preparing;

  @override
  Future<void> retryGeneration(
    Generation item, {
    Future<bool> Function(GenerationRetryConfirmation)? confirm,
  }) async {
    retryCalls++;
    await preparing?.future;
    final accepted = await confirm?.call((
      provider: providerById(item.provider),
      needsMediaSharingConsent: needsSharing,
      requiresProviderRetentionAcknowledgement: needsRetentionWarning,
    ));
    if (accepted == true) confirmedRetries++;
  }

  @override
  Future<void> reuse(Generation item) async => reuseCalls++;

  @override
  Future<bool> acceptTemporaryMediaSharing(
    TemporaryMediaHostStatus shown,
  ) async {
    sharingAccepts++;
    return true;
  }

  @override
  Future<void> acknowledgeProviderRetentionRisk({String? providerId}) async {
    acknowledgedProvider = providerId;
  }
}
