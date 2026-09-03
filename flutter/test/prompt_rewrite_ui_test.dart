import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/prompt_rewrite.dart';
import 'package:clawnsole/ui/common_widgets.dart';
import 'package:clawnsole/ui/create_screen.dart';
import 'package:clawnsole/ui/generation_view_widgets.dart';
import 'package:clawnsole/ui/library_screen.dart';
import 'package:clawnsole/ui/prompt_rewrite_dialog.dart';
import 'package:clawnsole/ui/prompt_rewrite_frames.dart';
import 'package:clawnsole/ui/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('full cards keep AI Rewrite in their actions menu', (
    tester,
  ) async {
    await _sized(tester, const Size(1400, 1600));
    final controller = _controller(_gateway());
    addTearDown(controller.dispose);

    await _pump(tester, GenerationCard(controller: controller, item: _film()));
    expect(find.text('AI Rewrite'), findsNothing);
    expect(
      tester
          .widget<GenerationActionsMenu>(find.byType(GenerationActionsMenu))
          .includeRewrite,
      isTrue,
    );
    await tester.tap(find.byType(GenerationActionsMenu));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('AI Rewrite'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    // An image has no frames to read and no film to re-cut.
    await _pump(
      tester,
      GenerationCard(
        controller: controller,
        item: _film(outputKind: GenerationOutputKind.image),
      ),
    );
    expect(find.text('AI Rewrite'), findsNothing);

    // A generation that never delivered has nothing to look at.
    await _pump(
      tester,
      GenerationCard(
        controller: controller,
        item: _film(status: 'Error', resultUrl: null),
      ),
    );
    expect(find.text('AI Rewrite'), findsNothing);

    // No rewrite key yet: the action still shows, and the dialog asks for
    // one, so the feature is discoverable before it is set up.
    final keyless = _controller(
      _gateway(connectedRewriteProviders: const <String>{}),
    );
    addTearDown(keyless.dispose);
    await _pump(tester, GenerationCard(controller: keyless, item: _film()));
    await tester.tap(find.byType(GenerationActionsMenu));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('AI Rewrite'), findsOneWidget);
  });

  testWidgets('a keyless dialog asks for a key first, then carries on', (
    tester,
  ) async {
    await _sized(tester, const Size(1400, 1600));
    final gateway = _gateway(connectedRewriteProviders: const <String>{});
    final controller = _controller(gateway);
    addTearDown(controller.dispose);

    await _openDialog(tester, controller);
    expect(find.byKey(const ValueKey('rewrite-key-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('rewrite-direction')), findsNothing);
    FilledButton save() => tester.widget<FilledButton>(
      find.byKey(const ValueKey('rewrite-key-save')),
    );
    expect(save().onPressed, isNull);

    await tester.tap(
      find.byKey(const ValueKey('rewrite-key-provider-anthropic')),
    );
    await tester.pump();
    expect(find.text('Anthropic API key'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('rewrite-key-field')),
      ' sk-ant-test ',
    );
    await tester.pump();
    expect(save().onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('rewrite-key-save')));
    await tester.pumpAndSettle();

    // Verified through a listing, saved, and the dialog moved on to the
    // rewrite form on the vendor the key belongs to.
    expect(gateway.candidateKeys, <String>['sk-ant-test']);
    expect(gateway.savedKeys, <String, String>{'anthropic': 'sk-ant-test'});
    expect(find.byKey(const ValueKey('rewrite-key-field')), findsNothing);
    expect(find.byKey(const ValueKey('rewrite-direction')), findsOneWidget);
    expect(find.text('Claude Opus 5'), findsOneWidget);
    await _expireNotice(tester);
  });

  testWidgets('a rejected first key stays in the dialog with its reason', (
    tester,
  ) async {
    await _sized(tester, const Size(1400, 1600));
    final gateway = _gateway(connectedRewriteProviders: const <String>{})
      ..listError = const PromptRewriteException(
        'OpenAI rejected this API key.',
        failure: PromptRewriteFailure.unauthorized,
      );
    final controller = _controller(gateway);
    addTearDown(controller.dispose);

    await _openDialog(tester, controller);
    await tester.enterText(
      find.byKey(const ValueKey('rewrite-key-field')),
      'sk-bad',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('rewrite-key-save')));
    await tester.pumpAndSettle();

    expect(gateway.savedKeys, isEmpty);
    expect(find.byKey(const ValueKey('rewrite-key-field')), findsOneWidget);
    expect(find.text('OpenAI rejected this API key.'), findsOneWidget);
  });

  testWidgets('the wand rewrites the draft in place with Undo on the notice', (
    tester,
  ) async {
    await _sized(tester, const Size(1400, 1600));
    final gateway = _gateway();
    final controller = _controller(gateway);
    addTearDown(controller.dispose);
    controller.updateForm((form) => form.prompt = _prompt);

    await _openDraftDialog(tester, controller);
    expect(find.byKey(const ValueKey('rewrite-frame-caption')), findsNothing);
    expect(find.text('Current direction'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('rewrite-direction')),
      'Name the camera move.',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('rewrite-submit')));
    await tester.pumpAndSettle();

    final request = gateway.rewriteRequests.single;
    expect(request.originalPrompt, _prompt);
    expect(request.frames, isEmpty);
    expect(request.targetProviderName, controller.selectedProvider.name);
    expect(request.targetModelName, controller.selectedModel.label);
    expect(request.mode, 't2v');
    expect(request.aspectRatio, controller.form.aspectRatio);

    expect(controller.form.prompt, 'A slower dolly past a warm lantern.');
    expect(controller.notice, 'Direction rewritten: Warmed the lantern.');
    expect(controller.noticeAction, AppNoticeAction.undoDirectionRewrite);
    expect(controller.noticeActionLabel, 'Undo');
    expect(find.byType(AlertDialog), findsNothing);

    await controller.performNoticeAction();
    expect(controller.form.prompt, _prompt);
    expect(controller.notice, 'Direction restored.');
    await _expireNotice(tester);
  });

  testWidgets('a rewrite lands in the tab it was opened for', (tester) async {
    await _sized(tester, const Size(1400, 1600));
    final gateway = _gateway();
    final controller = _controller(gateway);
    addTearDown(controller.dispose);
    controller.updateForm((form) => form.prompt = _prompt);
    final draftTab = controller.activeComposerTabId;

    await _openDraftDialog(tester, controller);
    await tester.enterText(
      find.byKey(const ValueKey('rewrite-direction')),
      'Tighter.',
    );
    await tester.pump();
    // The director opens another draft while the model thinks.
    controller.addComposerTab();
    await tester.tap(find.byKey(const ValueKey('rewrite-submit')));
    await tester.pumpAndSettle();

    expect(controller.activeComposerTab.form.prompt, isEmpty);
    expect(
      controller.composerTabs
          .firstWhere((tab) => tab.id == draftTab)
          .form
          .prompt,
      'A slower dolly past a warm lantern.',
    );
    await _expireNotice(tester);
  });

  testWidgets('the Direction header carries the rewrite wand', (tester) async {
    await _sized(tester, const Size(1400, 2000));
    final controller = _controller(_gateway());
    addTearDown(controller.dispose);

    await _pumpScreen(
      tester,
      AnimatedBuilder(
        animation: controller,
        builder: (context, _) => CreateScreen(controller: controller),
      ),
    );
    IconButton wand() => tester.widget<IconButton>(
      find.byKey(const ValueKey('prompt-rewrite-button')),
    );
    expect(wand().onPressed, isNull, reason: 'nothing to rewrite yet');

    controller.updateForm((form) => form.prompt = _prompt);
    await tester.pumpAndSettle();
    expect(wand().onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('prompt-rewrite-button')));
    await tester.pumpAndSettle();
    expect(find.text('Rewrite direction'), findsOneWidget);
  });

  testWidgets('the activity card offers AI Rewrite on a delivered film', (
    tester,
  ) async {
    await _sized(tester, const Size(1400, 1600));
    final controller = _controller(_gateway());
    addTearDown(controller.dispose);

    await _pump(tester, ActivityCard(controller: controller, item: _film()));

    expect(find.byKey(const ValueKey('activity-rewrite')), findsOneWidget);
  });

  testWidgets('the dense actions menu carries AI Rewrite', (tester) async {
    await _sized(tester, const Size(600, 800));
    final controller = _controller(_gateway());
    addTearDown(controller.dispose);

    await _pump(
      tester,
      GenerationActionsMenu(controller: controller, item: _film()),
    );
    await tester.tap(find.byType(GenerationActionsMenu));
    await tester.pumpAndSettle();

    expect(find.text('AI Rewrite'), findsOneWidget);
  });

  testWidgets('the rewrite surfaces fit a dark 375 px phone', (tester) async {
    await _sized(tester, const Size(375, 900));
    final controller = _controller(
      _gateway(
        connectedRewriteProviders: const <String>{'openai', 'anthropic'},
      ),
    );
    addTearDown(controller.dispose);

    // A RenderFlex overflow or an unbounded row fails the test on its own;
    // the assertions here only prove the surfaces actually mounted.
    await _openDialog(
      tester,
      controller,
      brightness: Brightness.dark,
      frames: <RewriteFrame>[
        RewriteFrame(bytes: _onePixelPng, seconds: 0),
        RewriteFrame(bytes: _onePixelPng, seconds: 4),
      ],
    );
    expect(find.text('2 frames sampled'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('rewrite-original-toggle')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('rewrite-original-prompt')),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildClawnsoleTheme(Brightness.dark),
        home: Scaffold(body: SettingsScreen(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('rewrite-key-anthropic')),
    );
    expect(find.text('Replace key'), findsNWidgets(2));
  });

  testWidgets(
    'the dialog opens on the remembered provider, model, and effort',
    (tester) async {
      await _sized(tester, const Size(1400, 1600));
      final controller = _controller(
        _gateway(
          connectedRewriteProviders: const <String>{'openai', 'anthropic'},
          preferences: const AppPreferences(
            rewriteProvider: 'anthropic',
            rewriteModels: <String, String>{'anthropic': 'claude-sonnet-5'},
            rewriteEfforts: <String, String>{'anthropic': 'low'},
          ),
        ),
      );
      addTearDown(controller.dispose);

      await _openDialog(tester, controller);

      // Both keys are present, so the provider row appears with Anthropic lit.
      expect(
        find.byKey(const ValueKey('rewrite-provider-openai')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('rewrite-provider-anthropic')),
        findsOneWidget,
      );
      expect(find.text('Claude Sonnet 5'), findsOneWidget);
      expect(find.text('Low'), findsOneWidget);

      // The direction is required before anything can be asked of the model.
      expect(_submitButton(tester).onPressed, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('rewrite-direction')),
        'Warmer lantern light.',
      );
      await tester.pump();
      expect(_submitButton(tester).onPressed, isNotNull);
    },
  );

  testWidgets('a rewrite lands its prompt in the composer with a notice', (
    tester,
  ) async {
    await _sized(tester, const Size(1400, 1600));
    final gateway = _gateway();
    final controller = _controller(gateway);
    addTearDown(controller.dispose);

    await _openDialog(tester, controller);
    await tester.enterText(
      find.byKey(const ValueKey('rewrite-direction')),
      '  Slower dolly, warmer lantern.  ',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('rewrite-submit')));
    await tester.pumpAndSettle();

    final request = gateway.rewriteRequests.single;
    expect(request.providerId, 'openai');
    expect(request.modelId, 'gpt-5.5');
    expect(request.effort, 'medium');
    expect(request.originalPrompt, _prompt);
    expect(request.direction, 'Slower dolly, warmer lantern.');
    expect(request.referenceMentions, <String>['@Lantern', '@Image 2']);
    expect(request.aspectRatio, '16:9');
    expect(request.durationSeconds, 8);
    expect(request.mode, 't2v');
    expect(request.targetProviderName, 'ArtCraft');
    expect(request.targetModelName, 'Seedance 2.5');

    expect(controller.form.prompt, 'A slower dolly past a warm lantern.');
    expect(controller.notice, 'Prompt rewritten: Warmed the lantern.');
    expect(find.byType(AlertDialog), findsNothing);

    // The choices are remembered for the next film.
    expect(controller.rewriteProviderId, 'openai');
    expect(controller.rewriteModelIds['openai'], 'gpt-5.5');
    expect(controller.rewriteEfforts['openai'], 'medium');
    await _expireNotice(tester);
  });

  testWidgets('a rejected key explains itself without closing the dialog', (
    tester,
  ) async {
    await _sized(tester, const Size(1400, 1600));
    final gateway = _gateway()
      ..rewriteError = const PromptRewriteException(
        'OpenAI rejected this key.',
        failure: PromptRewriteFailure.unauthorized,
        status: 401,
      );
    final controller = _controller(gateway);
    addTearDown(controller.dispose);

    await _openDialog(tester, controller);
    await tester.enterText(
      find.byKey(const ValueKey('rewrite-direction')),
      'Make it slower.',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('rewrite-submit')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.text('OpenAI rejected this key. Check the key in Settings.'),
      findsOneWidget,
    );
    expect(
      controller.form.prompt,
      isNot('A slower dolly past a warm lantern.'),
    );
  });

  testWidgets('the Settings card verifies a key before saving it', (
    tester,
  ) async {
    await _sized(tester, const Size(1000, 2400));
    final gateway = _gateway(connectedRewriteProviders: const <String>{});
    final controller = _controller(gateway);
    addTearDown(controller.dispose);

    await _pumpScreen(tester, SettingsScreen(controller: controller));
    final field = find.byKey(const ValueKey('rewrite-key-openai'));
    await tester.ensureVisible(field);
    await tester.enterText(field, 'sk-test-key');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('rewrite-key-save-openai')));
    await tester.pumpAndSettle();

    expect(gateway.candidateKeys, <String>['sk-test-key']);
    expect(gateway.savedKeys, <String, String>{'openai': 'sk-test-key'});
    expect(controller.connectedRewriteProviders, contains('openai'));

    final remove = find.byKey(const ValueKey('rewrite-key-remove-openai'));
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pumpAndSettle();

    expect(gateway.clearedKeys, <String>['openai']);
    expect(controller.connectedRewriteProviders, isEmpty);
    await _expireNotice(tester);
  });

  testWidgets('a rejected Settings key reports the vendor message', (
    tester,
  ) async {
    await _sized(tester, const Size(1000, 2400));
    final gateway = _gateway(connectedRewriteProviders: const <String>{})
      ..listError = const PromptRewriteException(
        'Anthropic rejected this key.',
        failure: PromptRewriteFailure.unauthorized,
      );
    final controller = _controller(gateway);
    addTearDown(controller.dispose);

    await _pumpScreen(tester, SettingsScreen(controller: controller));
    final field = find.byKey(const ValueKey('rewrite-key-anthropic'));
    await tester.ensureVisible(field);
    await tester.enterText(field, 'sk-ant-bad');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('rewrite-key-save-anthropic')));
    await tester.pumpAndSettle();

    expect(gateway.savedKeys, isEmpty);
    expect(find.text('Anthropic rejected this key.'), findsOneWidget);
  });

  testWidgets('cards name their tab and link back to the film they rewrote', (
    tester,
  ) async {
    await _sized(tester, const Size(1400, 1800));
    final source = _film(localId: 'film-a', title: 'Kite');
    final iteration = _film(
      localId: 'film-b',
      rewriteOfLocalId: 'film-a',
      rewriteSummary: 'Recolored the kite.',
    );
    final gateway = _gateway();
    gateway.snapshot = gateway.snapshot.copyWith(
      generations: <Generation>[iteration, source],
    );
    final controller = _controller(gateway);
    addTearDown(controller.dispose);

    // A named tab shows its name above the prompt; an unnamed one shows no
    // title row at all.
    await _pump(tester, GenerationCard(controller: controller, item: source));
    expect(find.byKey(const ValueKey('generation-title-film-a')), findsOne);
    expect(find.text('Kite'), findsOneWidget);
    await _pump(tester, GenerationCard(controller: controller, item: _film()));
    expect(find.byKey(const ValueKey('generation-title-film-1')), findsNothing);

    // The iteration links to its source, and the link opens that film.
    await _pump(
      tester,
      GenerationCard(controller: controller, item: iteration),
    );
    expect(find.text('Rewrite of Kite'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('generation-rewrite-source-film-b')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      find.byType(Dialog).evaluate().isNotEmpty ||
          find.byType(AlertDialog).evaluate().isNotEmpty,
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('detail-close')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // A source that is gone reads as such and is not a link.
    await _pump(
      tester,
      GenerationCard(
        controller: controller,
        item: _film(localId: 'film-c', rewriteOfLocalId: 'film-gone'),
      ),
    );
    expect(find.text('Rewrite of a removed film'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('generation-rewrite-source-film-c')),
      findsNothing,
    );

    // Dense cards carry the same line, and every card body opens the film.
    await _pump(
      tester,
      MiniGenerationCard(controller: controller, item: iteration),
    );
    expect(find.text('Rewrite of Kite'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('generation-open-film-b')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const ValueKey('detail-close')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('detail-close')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await _pump(
      tester,
      CompactGenerationRow(controller: controller, item: source),
    );
    expect(find.text('Kite'), findsOneWidget);
  });

  test('a preference write keeps the connected rewrite providers', () async {
    final gateway = _gateway(
      connectedRewriteProviders: const <String>{'openai'},
    );
    final controller = _controller(gateway);
    addTearDown(controller.dispose);
    expect(controller.connectedRewriteProviders, <String>{'openai'});

    // Navigation persists preferences, and the controller rebuilds its
    // snapshot from the write's answer without restoring preferences; the
    // rewrite providers must ride along or the action vanishes mid-session.
    await controller.navigate(AppSection.library);

    expect(controller.connectedRewriteProviders, <String>{'openai'});
    expect(controller.canRewriteAnything, isTrue);
  });

  test('frame sampling drops repeats and survives a sourceless film', () async {
    final controller = _controller(_gateway());
    addTearDown(controller.dispose);

    // Windows answers every seek with the same representative frame.
    final repeated = await sampleGenerationFrames(
      controller,
      _film(),
      count: 4,
      frameLoader: (uri, position, {int maxWidth = 180}) async =>
          Uint8List.fromList(<int>[7, 7, 7, 7]),
      metadataLoader: (_) async => const VideoSourceMetadata(
        width: 1280,
        height: 720,
        durationSeconds: 8,
      ),
      durationLoader: (_) async => 8,
    );
    expect(repeated, hasLength(1));
    expect(repeated.single.seconds, 0);
    expect(repeated.single.mimeType, 'image/jpeg');

    final distinct = await sampleGenerationFrames(
      controller,
      _film(),
      count: 3,
      frameLoader: (uri, position, {int maxWidth = 180}) async {
        expect(maxWidth, 640);
        return Uint8List.fromList(<int>[position.inMilliseconds % 251, 9]);
      },
      metadataLoader: (_) async => const VideoSourceMetadata(
        width: 1280,
        height: 720,
        durationSeconds: 8,
      ),
      durationLoader: (_) async => 8,
    );
    expect(distinct, hasLength(3));
    expect(distinct.last.seconds, closeTo(7.96, .01));

    // Nothing delivered means nothing to sample, and no exception either.
    final none = await sampleGenerationFrames(
      controller,
      _film(resultUrl: null, status: 'Error'),
      count: 4,
      frameLoader: (uri, position, {int maxWidth = 180}) async =>
          Uint8List.fromList(<int>[1]),
      metadataLoader: (_) async => null,
      durationLoader: (_) async => null,
    );
    expect(none, isEmpty);
  });
}

const String _prompt = 'A lantern sways over a wet harbor at midnight.';

/// A decodable 1×1 PNG, so image cards paint instead of logging a codec error.
final Uint8List _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAC'
  'hwGA60e6kgAAAABJRU5ErkJggg==',
);

Future<void> _sized(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildClawnsoleTheme(brightness),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pump();
}

/// Lets the controller's four-second notice timer fire, so the test does not
/// end with it still pending.
Future<void> _expireNotice(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
}

/// Screens bring their own scroll view; a second one would leave
/// [WidgetTester.ensureVisible] with two scrollables to choose from.
Future<void> _pumpScreen(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildClawnsoleTheme(Brightness.light),
      home: Scaffold(body: child),
    ),
  );
  await tester.pumpAndSettle();
}

/// Mounts a host whose only job is to open the rewrite dialog with a frame
/// sampler that never touches a decoder.
Future<void> _openDialog(
  WidgetTester tester,
  AppController controller, {
  Brightness brightness = Brightness.light,
  List<RewriteFrame> frames = const <RewriteFrame>[],
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildClawnsoleTheme(brightness),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(
              showPromptRewriteDialog(
                context,
                controller: controller,
                item: _film(),
                frameSampler: (_, _) async => frames,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// Opens the dialog for the draft in front, the way the Direction wand does.
Future<void> _openDraftDialog(
  WidgetTester tester,
  AppController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildClawnsoleTheme(Brightness.light),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(
              showPromptRewriteDialog(context, controller: controller),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

FilledButton _submitButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const ValueKey('rewrite-submit')));

/// A controller seeded straight from [gateway]'s snapshot. Skipping
/// `initialize()` keeps startup polling, catalog fetches, and platform probes
/// out of tests that only care about the rewrite surfaces.
AppController _controller(_RewriteGateway gateway) {
  final preferences = gateway.snapshot.preferences;
  final controller = AppController(gateway: gateway)
    ..snapshot = gateway.snapshot
    ..rewriteProviderId = preferences.rewriteProvider;
  controller.rewriteModelIds.addAll(preferences.rewriteModels);
  controller.rewriteEfforts.addAll(preferences.rewriteEfforts);
  return controller;
}

Generation _film({
  String localId = 'film-1',
  String status = 'Ready',
  String? resultUrl = 'https://cdn.example.com/film.mp4',
  GenerationOutputKind outputKind = GenerationOutputKind.video,
  String? title,
  String? rewriteOfLocalId,
  String? rewriteSummary,
}) {
  final now = DateTime.utc(2026, 9, 1, 21);
  return Generation(
    localId: localId,
    title: title,
    rewriteOfLocalId: rewriteOfLocalId,
    rewriteSummary: rewriteSummary,
    provider: 'artcraft',
    model: 'seedance_2p5',
    outputKind: outputKind,
    status: status,
    prompt: _prompt,
    mode: VideoMode.t2v,
    config: const GenerationConfig(
      aspectRatio: '16:9',
      duration: 8,
      resolution: 'hd',
      generateAudio: true,
      safetyTolerance: 2,
      draft: false,
      references: <MediaReferenceLabel>[
        MediaReferenceLabel(
          label: 'lantern.png',
          kind: MediaReferenceKind.image,
          promptName: 'Lantern',
        ),
        // A stored name that is only a reserved default defers to the
        // canonical attachment order.
        MediaReferenceLabel(
          label: 'harbor.png',
          kind: MediaReferenceKind.image,
          promptName: 'Image 7',
        ),
      ],
    ),
    resultUrl: resultUrl,
    createdAt: now,
    updatedAt: now,
  );
}

_RewriteGateway _gateway({
  Set<String> connectedRewriteProviders = const <String>{'openai'},
  AppPreferences preferences = const AppPreferences(),
}) => _RewriteGateway(
  LocalSnapshot(
    generations: const <Generation>[],
    preferences: preferences,
    hasApiKey: true,
    connectedProviders: const <String>{'artcraft'},
    availableProviders: const <String>{'artcraft'},
    providerRetentionAcknowledgements: const <String>{'artcraft'},
    storage: const StorageStats(path: 'memory', bytes: 0, records: 0),
    connectedRewriteProviders: connectedRewriteProviders,
  ),
);

class _RewriteGateway
    implements AppGateway, ProviderGateway, PromptRewriteGateway {
  _RewriteGateway(this.snapshot);

  LocalSnapshot snapshot;

  final List<PromptRewriteRequest> rewriteRequests = <PromptRewriteRequest>[];
  final List<String?> candidateKeys = <String?>[];
  final Map<String, String> savedKeys = <String, String>{};
  final List<String> clearedKeys = <String>[];
  PromptRewriteException? rewriteError;
  PromptRewriteException? listError;

  @override
  Future<List<RewriteModel>> listRewriteModels(
    String providerId, {
    String? candidateKey,
  }) async {
    if (candidateKey != null) candidateKeys.add(candidateKey);
    if (listError != null) throw listError!;
    return RewriteProvider.byId(providerId)?.curatedModels ??
        const <RewriteModel>[];
  }

  @override
  Future<PromptRewriteResult> rewritePrompt(
    PromptRewriteRequest request,
  ) async {
    rewriteRequests.add(request);
    if (rewriteError != null) throw rewriteError!;
    return PromptRewriteResult(
      prompt: 'A slower dolly past a warm lantern.',
      summary: 'Warmed the lantern.',
      providerId: request.providerId,
      modelId: request.modelId,
    );
  }

  @override
  Future<LocalSnapshot> setProviderApiKey(String provider, String value) async {
    savedKeys[provider] = value;
    return snapshot = snapshot.copyWith(
      connectedRewriteProviders: <String>{
        ...snapshot.connectedRewriteProviders,
        provider,
      },
    );
  }

  @override
  Future<LocalSnapshot> clearProviderApiKey(String provider) async {
    clearedKeys.add(provider);
    return snapshot = snapshot.copyWith(
      connectedRewriteProviders: snapshot.connectedRewriteProviders
          .where((id) => id != provider)
          .toSet(),
    );
  }

  @override
  Future<ProviderAccountStatus> verifyProviderKey(
    String provider, [
    String? candidate,
  ]) async => ProviderAccountStatus(provider: provider);

  @override
  Future<ProviderAccountStatus> getProviderAccount(String provider) async =>
      ProviderAccountStatus(provider: provider);

  @override
  Future<List<ProviderModelPrice>> listProviderModels(String provider) async =>
      const <ProviderModelPrice>[];

  @override
  Future<CostEstimate?> quoteProviderCost(
    String provider,
    String model,
    Map<String, Object?> input,
  ) async => null;

  @override
  bool get usesCompanion => false;

  @override
  bool get supportsPhotoLibrarySave => false;

  @override
  String get persistenceDescription => 'Memory';

  @override
  Future<LocalSnapshot> load() async => snapshot;

  @override
  Future<LocalSnapshot> setPreferences(AppPreferences preferences) async =>
      snapshot = snapshot.copyWith(preferences: preferences);

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
  Future<Uint8List> readAsset(AssetReference reference) async => _onePixelPng;

  @override
  Uri mediaUri(String source) => Uri.parse(source);

  @override
  Future<Uint8List> downloadMedia(String source) async => _onePixelPng;

  @override
  Future<void> saveMediaToPhotoLibrary(
    Uint8List bytes,
    String fileName,
    String contentType,
  ) async {}
}
