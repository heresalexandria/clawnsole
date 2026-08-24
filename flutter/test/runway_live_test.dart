import 'dart:io';

import 'package:clawnsole/core/runway_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final key = Platform.environment['RUNWAY_KEY']?.trim() ?? '';

  test(
    'live Runway minimum-duration Seedance Mini generation',
    () async {
      final api = RunwayApi();
      final before = await api.verify(key);
      final receipt = await api.submit(key, 'seedance2_mini', <String, Object?>{
        'mode': 't2v',
        'prompt':
            'Dry deadpan nature documentary, one continuous locked shot: '
            'a real brown-throated three-toed sloth hangs from a rainforest '
            'branch beside a tiny union placard reading NO MORE UNPAID '
            'OVERTIME. It slowly files a grievance. The branch manager '
            'looks nervous. Natural daylight, biologically accurate animal, '
            'subtle movement, no humans, no cuts.',
        'duration': 4,
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
        print('Runway smoke ${attempt + 1}: $state');
        if (state == 'SUCCEEDED' || state == 'FAILED' || state == 'CANCELLED') {
          break;
        }
        await Future<void>.delayed(const Duration(seconds: 5));
      }
      final after = await api.verify(key);
      // ignore: avoid_print
      print(
        'Runway live receipt: task=${receipt['id']} '
        'estimated=${receipt['estimated_credits']} '
        'actual=${status['actual_cost']} '
        'balance=${before.balance}→${after.balance} '
        'output=${status['outputs']}',
      );
      expect(status['status'], 'SUCCEEDED', reason: '${status['error']}');
      expect(status['outputs'], isNotEmpty);
      expect(status['actual_cost'], isA<double>());
    },
    skip: key.isEmpty
        ? 'Set RUNWAY_KEY to run the paid first-party smoke test.'
        : false,
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
