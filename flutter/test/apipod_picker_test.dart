import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/core/apipod_catalog.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/provider_catalog.dart';
import 'package:clawnsole/ui/create_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.android,
    TargetPlatform.windows,
    TargetPlatform.macOS,
  ]) {
    testWidgets('$platform exposes every APIPod route in the model picker', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final mobile =
            platform == TargetPlatform.iOS ||
            platform == TargetPlatform.android;
        await tester.binding.setSurfaceSize(
          mobile ? const Size(430, 932) : const Size(1400, 1000),
        );
        final controller = AppController(gateway: _Gateway())
          ..snapshot = _snapshot
          ..loading = false
          ..selectedProviderId = 'apipod'
          ..selectedModelId = 'seedance-2.5-t2v';
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          resetProviderCatalog();
          await tester.binding.setSurfaceSize(null);
          debugDefaultTargetPlatformOverride = null;
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: buildClawnsoleTheme(Brightness.light),
            home: Scaffold(
              body: AnimatedBuilder(
                animation: controller,
                builder: (_, _) => CreateScreen(controller: controller),
              ),
            ),
          ),
        );
        await tester.ensureVisible(find.byTooltip('Choose provider and model'));
        await tester.tap(find.byTooltip('Choose provider and model'));
        await tester.pumpAndSettle();
        expect(apipodProvider.models, hasLength(103));
        for (final model in apipodProvider.models) {
          expect(
            find.byKey(ValueKey('provider-model-option-apipod-${model.id}')),
            findsOneWidget,
            reason: '${platform.name}/${model.id}',
          );
        }
        await tester.enterText(
          find.byKey(const ValueKey('provider-model-search')),
          'seedance-2.5-draft',
        );
        await tester.pumpAndSettle();
        final draft = find.byKey(
          const ValueKey('provider-model-option-apipod-seedance-2.5-draft'),
        );
        await tester.ensureVisible(draft);
        await tester.tap(draft);
        await tester.pumpAndSettle();
        expect(controller.selectedModelId, 'seedance-2.5-draft');
        expect(controller.availableResolutions.map((item) => item.id), ['sd']);
        expect(find.text('Or enhance a saved draft'), findsOneWidget);
        for (final modelId in ['gemini-omni-t2v', 'muse-video-t2v']) {
          await controller.selectModel(modelId);
          await tester.pumpAndSettle();
          if (modelId == 'gemini-omni-t2v') {
            expect(
              find.byKey(const ValueKey('fixed-duration')),
              findsOneWidget,
            );
            expect(find.byKey(const ValueKey('duration-slider')), findsNothing);
          }
          final notice = controller.selectedModel.generationNotice;
          expect(notice, isNotNull);
          final noticeWidget = find.byKey(const ValueKey('generation-notice'));
          await tester.ensureVisible(noticeWidget);
          expect(
            find.descendant(of: noticeWidget, matching: find.text(notice!)),
            findsOneWidget,
          );
          expect(
            tester.getTopLeft(noticeWidget).dy,
            lessThan(
              tester.getTopLeft(find.byKey(const ValueKey('generate-key'))).dy,
            ),
          );
        }
        await controller.selectModel('seedance-2.5-t2v');
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('generation-notice')), findsNothing);
        for (final model in apipodProvider.models) {
          await controller.selectModel(model.id);
          await tester.pumpAndSettle();
          expect(controller.selectedModelId, model.id);
          expect(
            tester.takeException(),
            isNull,
            reason: '${platform.name}/${model.id}',
          );
        }

        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}

const _snapshot = LocalSnapshot(
  generations: [],
  preferences: AppPreferences(provider: 'apipod'),
  hasApiKey: false,
  availableProviders: {'apipod'},
  storage: StorageStats(path: 'memory', bytes: 0, records: 0),
);

class _Gateway implements AppGateway {
  @override
  bool get usesCompanion => false;
  @override
  bool get supportsPhotoLibrarySave => false;
  @override
  String get persistenceDescription => 'Memory';
  @override
  Uri mediaUri(String source) => Uri.parse(source);
  @override
  Future<LocalSnapshot> setPreferences(AppPreferences preferences) async =>
      _snapshot;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
