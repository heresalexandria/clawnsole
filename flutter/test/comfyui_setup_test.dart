import 'dart:async';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/core/comfyui_settings.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/ui/comfyui_setup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _workflowJson = '''{
  "1": {"class_type": "CLIPTextEncode", "inputs": {"text": "{{prompt}}"}},
  "9": {"class_type": "SaveImage", "inputs": {"images": ["1", 0]}}
}''';

const _imageSettings = ComfyUiSettings(
  serverUrl: 'http://render-machine:8188',
  workflows: <String, ComfyUiWorkflow>{
    'comfyui-image': ComfyUiWorkflow(json: _workflowJson, outputNodeId: '9'),
  },
);

void main() {
  testWidgets(
    'invalid server URLs are shown inline before server verification',
    (tester) async {
      final fixture = await _open(tester);
      await _fill(tester, server: 'not a server');
      await _save(tester);
      expect(find.textContaining('HTTP or HTTPS server URL'), findsOneWidget);
      expect(find.text('Connect ComfyUI'), findsOneWidget);
      expect(fixture.gateway.verifications, isEmpty);
      expect(fixture.gateway.preferenceWrites, 0);
      expect(fixture.controller.comfyUiSettings.isConfigured, isFalse);
    },
  );

  testWidgets('editor-format workflows cannot be saved as API graphs', (
    tester,
  ) async {
    final fixture = await _open(tester);
    await _fill(tester, workflow: '{"nodes":[],"links":[]}');
    await _save(tester);
    expect(
      find.textContaining('Export the workflow in API format'),
      findsOneWidget,
    );
    expect(fixture.gateway.verifications, isEmpty);
    expect(fixture.gateway.preferenceWrites, 0);
  });

  testWidgets('server verification failure keeps the saved connection intact', (
    tester,
  ) async {
    final fixture = await _open(tester, settings: _imageSettings);
    fixture.gateway.verificationError = StateError('ComfyUI is not reachable.');
    await _fill(tester, server: 'http://replacement:8188');
    await _save(tester);
    expect(find.textContaining('ComfyUI is not reachable'), findsOneWidget);
    expect(find.text('Connect ComfyUI'), findsOneWidget);
    expect(fixture.gateway.verifications, hasLength(1));
    expect(fixture.gateway.preferenceWrites, 0);
    expect(
      fixture.controller.comfyUiSettings.serverUrl,
      _imageSettings.serverUrl,
    );
  });

  testWidgets(
    'image-only setup waits for verification and is immediately usable',
    (tester) async {
      final fixture = await _open(tester);
      fixture.gateway.pendingVerification = Completer<ProviderAccountStatus>();
      await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Image workflow').last);
      await tester.pumpAndSettle();
      await _fill(tester);
      await tester.tap(find.text('Test & save'));
      await tester.pump();
      expect(find.text('Connecting…'), findsOneWidget);
      expect(fixture.gateway.preferenceWrites, 0);
      expect(fixture.gateway.verifications.single.$1, 'comfyui');
      final submitted = ComfyUiSettings.fromJson(
        fixture.gateway.verifications.single.$2,
      );
      expect(submitted.workflows.keys, <String>['comfyui-image']);
      expect(submitted.serverUrl, 'http://render-machine:8188');

      fixture.gateway.pendingVerification!.complete(
        const ProviderAccountStatus(
          provider: 'comfyui',
          balanceLabel: 'Local server',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Connect ComfyUI'), findsNothing);
      expect(fixture.gateway.preferenceWrites, 1);
      expect(fixture.controller.comfyUiSettings.workflows.keys, <String>[
        'comfyui-image',
      ]);
      expect(
        fixture.controller.providerAccounts['comfyui']?.balanceLabel,
        'Local server',
      );
      expect(fixture.controller.needsProviderSetup, isFalse);

      await fixture.controller.selectProvider('comfyui');
      expect(fixture.controller.selectedModelId, 'comfyui-image');
      expect(
        fixture.controller.providerModelNeedsConfiguration(
          'comfyui',
          'comfyui-image',
        ),
        isFalse,
      );
      expect(
        fixture.controller.providerModelNeedsConfiguration(
          'comfyui',
          'comfyui-video',
        ),
        isTrue,
      );
      fixture.controller.form.prompt = 'A fox under a tree.';
      expect(fixture.controller.validate(), isNull);
      // Ordinary preference writes must preserve the imported graph.
      await fixture.controller.setThemeMode(AppThemeMode.dark);
      expect(fixture.controller.comfyUiSettings.workflows.keys, <String>[
        'comfyui-image',
      ]);
      expect(
        ComfyUiSettings.fromJson(
          fixture
              .gateway
              .snapshot
              .preferences
              .providerConfigurations['comfyui'],
        ).workflows.keys,
        <String>['comfyui-image'],
      );
    },
  );

  testWidgets(
    'removing a connection updates live readiness and preserves other settings',
    (tester) async {
      final fixture = await _open(tester, settings: _imageSettings);
      fixture.controller.providerAccounts['comfyui'] =
          const ProviderAccountStatus(provider: 'comfyui');
      await tester.tap(find.text('Remove connection'));
      await tester.pumpAndSettle();
      expect(find.text('Connect ComfyUI'), findsNothing);
      expect(fixture.controller.comfyUiSettings.isConfigured, isFalse);
      expect(fixture.controller.providerAccounts, isNot(contains('comfyui')));
      expect(fixture.controller.needsProviderSetup, isTrue);
      expect(
        fixture.gateway.snapshot.preferences.providerConfigurations,
        <String, Map<String, Object?>>{
          'another-provider': <String, Object?>{'kept': true},
        },
      );
      expect(fixture.gateway.verifications, isEmpty);
    },
  );

  testWidgets('setup fields and actions fit a 375 px dark phone', (
    tester,
  ) async {
    await _open(tester, width: 375);
    expect(find.text('Connect ComfyUI'), findsOneWidget);
    await _fill(tester);
    for (final key in <String>[
      'comfyui-server-url',
      'comfyui-workflow-json',
      'comfyui-output-node',
    ]) {
      final field = find.byKey(ValueKey(key));
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      final bounds = tester.getRect(field);
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(375));
    }
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
}

Future<({AppController controller, _ConfigurationGateway gateway})> _open(
  WidgetTester tester, {
  ComfyUiSettings? settings,
  double width = 1000,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 1100));
  final gateway = _ConfigurationGateway(settings);
  final controller = AppController(gateway: gateway)
    ..snapshot = gateway.snapshot
    ..loading = false;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: buildClawnsoleTheme(Brightness.dark),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(showComfyUiSetup(context, controller)),
            child: const Text('Open setup'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open setup'));
  await tester.pumpAndSettle();
  return (controller: controller, gateway: gateway);
}

Future<void> _fill(
  WidgetTester tester, {
  String server = 'http://render-machine:8188',
  String workflow = _workflowJson,
}) async {
  for (final entry in <String, String>{
    'comfyui-server-url': server,
    'comfyui-workflow-json': workflow,
    'comfyui-output-node': '9',
  }.entries) {
    final field = find.byKey(ValueKey(entry.key));
    await tester.ensureVisible(field);
    await tester.enterText(field, entry.value);
    await tester.pump();
  }
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.text('Test & save'));
  await tester.pumpAndSettle();
}

class _ConfigurationGateway
    implements AppGateway, ProviderConfigurationGateway {
  _ConfigurationGateway(ComfyUiSettings? settings) {
    snapshot = LocalSnapshot(
      generations: const <Generation>[],
      preferences: AppPreferences(
        providerConfigurations: <String, Map<String, Object?>>{
          'another-provider': <String, Object?>{'kept': true},
          if (settings != null) 'comfyui': settings.toJson(),
        },
      ),
      hasApiKey: false,
      connectedProviders: <String>{if (settings != null) 'comfyui'},
      availableProviders: const <String>{'comfyui'},
      storage: const StorageStats(path: 'memory', bytes: 0, records: 0),
    );
  }

  late LocalSnapshot snapshot;
  final verifications = <(String, Map<String, Object?>)>[];
  int preferenceWrites = 0;
  Object? verificationError;
  Completer<ProviderAccountStatus>? pendingVerification;

  @override
  Future<ProviderAccountStatus> verifyProviderConfiguration(
    String provider,
    Map<String, Object?> configuration,
  ) async {
    verifications.add((provider, configuration));
    if (verificationError != null) throw verificationError!;
    if (pendingVerification != null) return pendingVerification!.future;
    return ProviderAccountStatus(provider: provider);
  }

  @override
  Future<LocalSnapshot> setPreferences(AppPreferences preferences) async {
    preferenceWrites += 1;
    final settings = ComfyUiSettings.fromJson(
      preferences.providerConfigurations['comfyui'],
    );
    snapshot = snapshot.copyWith(
      preferences: preferences,
      connectedProviders: <String>{if (settings.isConfigured) 'comfyui'},
    );
    return snapshot;
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
