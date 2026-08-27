import 'dart:io';

import 'package:clawnsole/core/krea_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final key = Platform.environment['KREA_API_KEY']?.trim() ?? '';

  test(
    'live Krea minimum-duration Vidu Q3 generation',
    () async {
      final api = KreaApi();
      final account = await api.verify(key);
      expect(account.provider, 'krea');

      final models = await api.listVideoModels();
      expect(models.where((model) => model.createReady), isNotEmpty);

      final receipt = await api.submit(key, 'vidu/q3', <String, Object?>{
        'mode': 't2v',
        'prompt':
            'Dry deadpan nature documentary, one continuous locked shot: '
            'a real brown-throated three-toed sloth hangs from a rainforest '
            'branch and slowly, triumphantly, stamps a tiny form APPROVED. '
            'Natural daylight, biologically accurate animal, subtle '
            'movement, no humans, no cuts.',
        'duration': 1,
        'resolution': 'sd',
        'aspect_ratio': '16:9',
        'generate_audio': false,
      });
      final pollingUrl = receipt['polling_url']! as String;
      Map<String, Object?> status = <String, Object?>{};
      for (var attempt = 0; attempt < 120; attempt += 1) {
        status = await api.poll(key, pollingUrl);
        final state = status['status']?.toString() ?? '';
        // ignore: avoid_print
        print('Krea smoke ${attempt + 1}: $state');
        if (state == 'completed' || state == 'failed' || state == 'cancelled') {
          break;
        }
        await Future<void>.delayed(const Duration(seconds: 5));
      }
      // ignore: avoid_print
      print(
        'Krea live receipt: job=${receipt['id']} '
        'output=${status['outputs']}',
      );
      expect(status['status'], 'completed', reason: '${status['error']}');
      expect(status['outputs'], isNotEmpty);
    },
    skip: key.isEmpty
        ? 'Set KREA_API_KEY to run the paid first-party smoke test.'
        : false,
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
