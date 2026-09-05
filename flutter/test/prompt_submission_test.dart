import 'dart:convert';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/core/krea_api.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/runway_api.dart';
import 'package:clawnsole/core/web_gateway.dart';
import 'package:clawnsole/ui/create_screen.dart';
import 'package:clawnsole/ui/reference_prompt_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final provider in ['krea', 'runway']) {
    for (final screenplay in [false, true]) {
      for (final expanded in [false, true]) {
        testWidgets(
          '$provider receives edited prompt and named video: screenplay=$screenplay expanded=$expanded',
          (tester) async {
            await tester.binding.setSurfaceSize(const Size(1200, 1600));
            addTearDown(() => tester.binding.setSurfaceSize(null));
            const snapshot = LocalSnapshot(
              generations: [],
              preferences: AppPreferences(),
              hasApiKey: false,
              connectedProviders: {'krea', 'runway'},
              storage: StorageStats(path: 'memory', bytes: 0, records: 0),
            );
            final submissions = <Map<String, dynamic>>[];
            final gateway = WebGateway(
              baseUrl: Uri.parse('http://127.0.0.1:8787'),
              client: MockClient((request) async {
                switch (request.url.path) {
                  case '/account':
                    return http.Response(
                      jsonEncode({'provider': provider}),
                      200,
                    );
                  case '/generations':
                    final body =
                        jsonDecode(request.body) as Map<String, dynamic>;
                    submissions.add(body);
                    return http.Response(
                      jsonEncode({'generation': body['record']}),
                      201,
                    );
                  case '/composer-tabs':
                    return http.Response('{}', 200);
                  case '/action':
                    return http.Response(jsonEncode(snapshot.toJson()), 200);
                  default:
                    throw StateError('Unexpected request: ${request.url}');
                }
              }),
            );
            final controller = AppController(gateway: gateway)
              ..snapshot = snapshot
              ..loading = false
              ..selectedProviderId = provider
              ..selectedModelId = provider == 'krea'
                  ? 'bytedance/seedance-2-5'
                  : 'seedance2_5';
            addTearDown(controller.dispose);
            controller.updateForm((form) {
              form.prompt = 'Old prompt that must not be submitted.';
              form.references = [
                MediaReferenceDraft(
                  id: 'video',
                  kind: MediaReferenceKind.video,
                  label: 'source.mp4',
                  promptName: 'Street scene',
                  thumbnailBytes: base64Decode(
                    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jD1kAAAAASUVORK5CYII=',
                  ),
                  source: 'https://example.com/source.mp4',
                ),
              ];
            });
            controller.setScreenplayMode(screenplay);
            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) =>
                        CreateScreen(controller: controller),
                  ),
                ),
              ),
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            if (expanded) {
              await tester.tap(
                find.byKey(const ValueKey('prompt-fullscreen-button')),
              );
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 300));
            }
            final promptField = find.descendant(
              of: find.byType(ReferencePromptField).last,
              matching: find.byType(TextFormField),
            );
            final prompt = screenplay
                ? 'EXT. STREET - DAY\n\nThe taxi is red and stays intact until it lands.'
                : 'Match the reference video except the taxi is red and stays intact until it lands.';
            await tester.enterText(promptField, prompt);
            await tester.pump();
            final shownPrompt = tester
                .widget<TextFormField>(promptField)
                .controller!
                .text;
            expect(controller.form.prompt, shownPrompt);
            await controller.submit(providerRetentionRiskAcknowledged: true);
            expect(submissions, hasLength(1), reason: controller.notice);
            expect(submissions.last['record']['prompt'], shownPrompt.trim());
            expect(submissions.last['input']['prompt'], shownPrompt.trim());

            // Accept a custom @ name through the actual prompt menu, then
            // inspect the provider HTTP body, not just the saved history text.
            await tester.enterText(promptField, '$shownPrompt\n\nUse @');
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pump();
            final taggedPrompt = tester
                .widget<TextFormField>(promptField)
                .controller!
                .text;
            expect(taggedPrompt, contains('@Street scene'));
            await controller.submit(providerRetentionRiskAcknowledged: true);
            expect(submissions, hasLength(2));
            final submitted = submissions.last;
            expect(submitted['record']['prompt'], taggedPrompt.trim());
            final wireBodies = <Map<String, dynamic>>[];
            final client = MockClient((request) async {
              wireBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
              return http.Response(
                provider == 'krea'
                    ? '{"job_id":"test-job"}'
                    : '{"id":"test-job"}',
                200,
              );
            });
            for (final submission in submissions) {
              final input = Map<String, Object?>.from(
                submission['input'] as Map,
              );
              if (provider == 'krea') {
                await KreaApi(
                  client: client,
                ).submit('test-key', controller.selectedModelId, input);
              } else {
                await RunwayApi(
                  client: client,
                ).submit('test-key', controller.selectedModelId, input);
              }
            }
            final promptKey = provider == 'krea' ? 'prompt' : 'promptText';
            expect(wireBodies.first[promptKey], shownPrompt.trim());
            expect(
              wireBodies.last[promptKey],
              taggedPrompt.trim().replaceAll('@Street scene', '@video1'),
            );
            expect(
              wireBodies.last[provider == 'krea'
                  ? 'reference_videos'
                  : 'referenceVideos'],
              isNotEmpty,
            );
            await tester.pumpWidget(const SizedBox.shrink());
            // Drain the notice and browser preview timeouts for mock media.
            await tester.pump(const Duration(seconds: 15));
          },
        );
      }
    }
  }
}
