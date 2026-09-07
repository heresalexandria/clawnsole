import 'dart:async';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/core/api_transcript.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/ui/api_requests_modal.dart';
import 'package:clawnsole/ui/generation_view_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the card menu offers API Requests for a submitted film', (
    tester,
  ) async {
    await _sized(tester, const Size(1440, 900));
    final controller = _controller();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _host(GenerationActionsMenu(controller: controller, item: _film())),
    );
    await tester.tap(find.byTooltip('Generation actions'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('generation-action-api-requests')),
      findsOneWidget,
    );
    expect(find.text('API Requests'), findsOneWidget);
  });

  testWidgets('a film that was never sent to a provider has no menu item', (
    tester,
  ) async {
    await _sized(tester, const Size(1440, 900));
    final controller = _controller();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _host(
        GenerationActionsMenu(
          controller: controller,
          item: _film(sent: false),
          onDelete: () {},
        ),
      ),
    );
    await tester.tap(find.byTooltip('Generation actions'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('generation-action-api-requests')),
      findsNothing,
    );
  });

  testWidgets('the modal lists requests, expands one, and copies it', (
    tester,
  ) async {
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await _sized(tester, const Size(1440, 900));
    final controller = _controller(records: _records());
    addTearDown(controller.dispose);

    await _open(tester, controller);
    expect(find.byKey(const ValueKey('api-requests-title')), findsOneWidget);
    expect(find.textContaining('film-b · Krea'), findsOneWidget);
    expect(find.byKey(const ValueKey('api-request-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('api-request-2')), findsOneWidget);
    expect(find.textContaining('POST'), findsWidgets);
    expect(find.textContaining('412 ms'), findsOneWidget);
    expect(find.byKey(const ValueKey('api-requests-footnote')), findsOneWidget);

    // Collapsed: no payload on screen yet.
    expect(find.textContaining('A slow dolly'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('api-request-1')));
    await tester.pumpAndSettle();
    expect(find.text('REQUEST'), findsOneWidget);
    expect(find.text('RESPONSE'), findsOneWidget);
    expect(find.textContaining('A slow dolly'), findsOneWidget);
    expect(find.textContaining('authorization: «redacted»'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('api-request-copy-1')));
    await tester.pumpAndSettle();
    // The copy notice owns a timer; let it retire inside the test.
    await tester.pump(const Duration(seconds: 5));
    expect(copied, contains('── #1 · submit · krea'));
    expect(copied, contains('POST https://api.krea.test/v1/generate'));
    expect(copied, contains('authorization: «redacted»'));
    expect(copied, isNot(contains('#2')));

    copied = null;
    await tester.tap(find.byKey(const ValueKey('api-requests-copy-all')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    expect(copied, startsWith('Clawnsole API transcript'));
    expect(copied, contains('film      film-b'));
    expect(copied, contains('── #1 · submit · krea'));
    expect(copied, contains('── #2 · poll · krea'));
    expect(copied, contains('Credentials are redacted'));

    await tester.tap(find.byKey(const ValueKey('api-requests-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('api-requests-title')), findsNothing);
  });

  testWidgets('an empty transcript explains itself and Escape closes', (
    tester,
  ) async {
    await _sized(tester, const Size(1440, 900));
    final controller = _controller();
    addTearDown(controller.dispose);

    await _open(tester, controller);
    expect(find.byKey(const ValueKey('api-requests-empty')), findsOneWidget);
    expect(
      find.textContaining('kept on the device that made them'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('api-requests-copy-all')), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('api-requests-empty')), findsNothing);
  });

  testWidgets('the modal reads in both modes without a dark island', (
    tester,
  ) async {
    for (final brightness in <Brightness>[Brightness.light, Brightness.dark]) {
      await _sized(tester, const Size(1024, 800));
      final controller = _controller(records: _records());
      await _open(tester, controller, brightness: brightness);
      await tester.tap(find.byKey(const ValueKey('api-request-2')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('api-requests-close')));
      await tester.pumpAndSettle();
      controller.dispose();
    }
  });
}

Future<void> _sized(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });
}

Widget _host(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: buildClawnsoleTheme(brightness),
      home: Scaffold(body: Center(child: child)),
    );

Future<void> _open(
  WidgetTester tester,
  AppController controller, {
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    _host(
      Builder(
        builder: (context) => TextButton(
          onPressed: () => unawaited(
            showApiRequestsModal(
              context,
              controller: controller,
              item: _film(),
            ),
          ),
          child: const Text('open'),
        ),
      ),
      brightness: brightness,
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

AppController _controller({List<ApiRequestRecord> records = const []}) =>
    AppController(gateway: _TranscriptGateway(records))..snapshot = _snapshot;

const LocalSnapshot _snapshot = LocalSnapshot(
  generations: <Generation>[],
  preferences: AppPreferences(),
  hasApiKey: true,
  connectedProviders: <String>{'krea'},
  availableProviders: <String>{'krea'},
  storage: StorageStats(path: 'memory', bytes: 0, records: 0),
);

List<ApiRequestRecord> _records() => <ApiRequestRecord>[
  ApiRequestRecord(
    id: 'a',
    operationId: 'film-b',
    sequence: 1,
    at: DateTime.utc(2026, 9, 7, 18, 22, 41),
    durationMs: 412,
    provider: 'krea',
    purpose: ApiRequestPurpose.submit,
    method: 'POST',
    url: 'https://api.krea.test/v1/generate',
    requestHeaders: const <String, String>{
      'authorization': '«redacted»',
      'content-type': 'application/json',
    },
    requestBody: '{\n  "prompt": "A slow dolly past a warm lantern."\n}',
    statusCode: 200,
    responseHeaders: const <String, String>{'content-type': 'application/json'},
    responseBody: '{\n  "job_id": "job-1"\n}',
  ),
  ApiRequestRecord(
    id: 'b',
    operationId: 'film-b',
    sequence: 2,
    at: DateTime.utc(2026, 9, 7, 18, 23, 9),
    durationMs: 88,
    provider: 'krea',
    purpose: ApiRequestPurpose.poll,
    method: 'GET',
    url: 'https://api.krea.test/v1/jobs/job-1',
    statusCode: 200,
    responseBody: '{\n  "status": "Ready"\n}',
  ),
];

Generation _film({bool sent = true}) {
  final now = DateTime.utc(2026, 9, 7, 18, 22);
  return Generation(
    localId: 'film-b',
    provider: 'krea',
    model: 'bytedance/seedance-2-5',
    status: sent ? 'Ready' : 'Draft',
    prompt: 'A slow dolly past a warm lantern.',
    mode: VideoMode.t2v,
    config: const GenerationConfig(
      aspectRatio: '16:9',
      duration: 5,
      resolution: 'sd',
      generateAudio: false,
      safetyTolerance: 2,
      draft: false,
    ),
    requestId: sent ? 'job-1' : null,
    resultUrl: sent ? 'https://cdn.krea.test/film.mp4' : null,
    providerAcceptedAt: sent ? now : null,
    createdAt: now,
    updatedAt: now,
  );
}

class _TranscriptGateway implements AppGateway, ApiTranscriptGateway {
  _TranscriptGateway(this.records);

  final List<ApiRequestRecord> records;

  @override
  bool get usesCompanion => false;

  @override
  bool get supportsPhotoLibrarySave => false;

  @override
  String get persistenceDescription => 'Memory';

  @override
  Future<LocalSnapshot> load() async => _snapshot;

  @override
  Future<List<ApiRequestRecord>> readApiRequests(String localId) async =>
      localId == 'film-b' ? records : const <ApiRequestRecord>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
