import 'dart:async';
import 'dart:convert';
import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/web_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const snapshot = LocalSnapshot(
    generations: [],
    preferences: AppPreferences(),
    hasApiKey: false,
    connectedProviders: {'runway'},
    storage: StorageStats(path: 'memory', bytes: 0, records: 0),
  );
  test(
    'overlapping activation submits once; identical later activation is a new job',
    () async {
      final gate = Completer<void>();
      final submissions = <Map<String, dynamic>>[];
      final gateway = WebGateway(
        baseUrl: Uri.parse('http://127.0.0.1:8787'),
        client: MockClient((request) async {
          switch (request.url.path) {
            case '/account':
              await gate.future;
              return http.Response(jsonEncode({'provider': 'runway'}), 200);
            case '/generations':
              final body = jsonDecode(request.body) as Map<String, dynamic>;
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
        ..selectedProviderId = 'runway'
        ..selectedModelId = 'seedance2_5';
      addTearDown(controller.dispose);
      controller.updateForm((form) {
        form.prompt = 'A quiet beach.';
        form.references = [
          const MediaReferenceDraft(
            id: 'image',
            label: 'Reference',
            kind: MediaReferenceKind.image,
            source: 'https://example.com/original.jpg',
          ),
        ];
      });
      final first = controller.submit(providerRetentionRiskAcknowledged: true);
      final second = controller.submit(providerRetentionRiskAcknowledged: true);
      expect(controller.submitting, isTrue);
      gate.complete();
      await Future.wait([first, second]);
      expect(submissions, hasLength(1));
      expect(controller.submitting, isFalse);
      await controller.submit(providerRetentionRiskAcknowledged: true);
      expect(submissions, hasLength(2));
      expect(submissions[0]['input'], submissions[1]['input']);
      expect(
        submissions[0]['record']['localId'],
        isNot(submissions[1]['record']['localId']),
      );
    },
  );
  test(
    'preflight preserves captured prompt, references and selected provider',
    () async {
      final gate = Completer<void>();
      final submissions = <Map<String, dynamic>>[];
      final gateway = WebGateway(
        baseUrl: Uri.parse('http://127.0.0.1:8787'),
        client: MockClient((request) async {
          switch (request.url.path) {
            case '/account':
              await gate.future;
              return http.Response(jsonEncode({'provider': 'runway'}), 200);
            case '/generations':
              final body = jsonDecode(request.body) as Map<String, dynamic>;
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
        ..selectedProviderId = 'runway'
        ..selectedModelId = 'seedance2_5';
      addTearDown(controller.dispose);
      controller.updateForm((form) {
        form.prompt = 'The intended beach.';
        form.references = [
          const MediaReferenceDraft(
            id: 'image',
            label: 'Reference',
            kind: MediaReferenceKind.image,
            source: 'https://example.com/original.jpg',
          ),
        ];
      });
      final first = controller.submit(providerRetentionRiskAcknowledged: true);
      controller.updateForm((form) {
        form.prompt = 'An unrelated city.';
        form.references.clear();
      });
      controller.addComposerTab();
      controller.selectedProviderId = 'bfl';
      controller.selectedModelId = 'flux-3-video';
      gate.complete();
      await first;
      expect(submissions.single['record']['prompt'], 'The intended beach.');
      expect(submissions.single['record']['provider'], 'runway');
      expect(submissions.single['input']['reference_images'], [
        'https://example.com/original.jpg',
      ]);
      expect(controller.providerAccounts['runway']?.provider, 'runway');
      expect(controller.providerAccounts.containsKey('bfl'), isFalse);
    },
  );
}
