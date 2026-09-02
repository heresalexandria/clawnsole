import 'package:clawnsole/core/bfl_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public hosts pass', () {
    for (final host in <String>[
      'delivery.bfl.ai',
      'storage.googleapis.com',
      '8.8.8.8',
      '2606:4700:4700::1111',
    ]) {
      expect(isPublicProviderHost(host), isTrue, reason: host);
    }
    expect(
      validatedProviderUrl('https://delivery.bfl.ai/result.mp4').host,
      'delivery.bfl.ai',
    );
  });

  test('loopback, private, link-local, and metadata hosts are refused', () {
    for (final host in <String>[
      'localhost',
      'app.localhost',
      '127.0.0.1',
      '127.1',
      '2130706433',
      '0x7f000001',
      '0.0.0.0',
      '10.1.2.3',
      '172.16.9.9',
      '172.31.255.255',
      '192.168.1.1',
      '169.254.169.254',
      '100.64.0.1',
      '::1',
      '::ffff:127.0.0.1',
      '::ffff:10.0.0.1',
      'fd00::1',
      'fe80::1',
      'metadata.google.internal',
      'metadata',
      'printer.local',
    ]) {
      expect(isPublicProviderHost(host), isFalse, reason: host);
    }
  });

  test('validatedProviderUrl rejects non-https and private targets', () {
    for (final url in <String>[
      'http://delivery.bfl.ai/result.mp4',
      'https://169.254.169.254/latest/meta-data/',
      'https://[::ffff:127.0.0.1]/',
      'https://127.1/',
      'not a url',
    ]) {
      expect(() => validatedProviderUrl(url), throwsA(anything), reason: url);
    }
  });
}
