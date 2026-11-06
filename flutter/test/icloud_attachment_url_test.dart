import 'package:clawnsole/core/icloud_attachment_url.dart';
import 'package:clawnsole/core/icloud_reference_transport.dart';
import 'package:flutter_test/flutter_test.dart';

String _publication({
  String path = '/attachment/',
  String template =
      r'https://cvws.icloud-content.com/B/test/${f}?o=signed&k=${uk}&s=tail',
  String key = 'synthetic+key/with=padding',
  String filename = 'reference clip.mp4',
  int bytes = 42,
}) =>
    'https://www.icloud.com$path?u=${Uri.encodeComponent(template)}'
    '&uk=${Uri.encodeComponent(key)}&f=${Uri.encodeComponent(filename)}&sz=$bytes';

Matcher get _safeFailure => throwsA(
  isA<ICloudReferenceException>()
      .having((error) => error.code, 'code', 'unsupportedPublication')
      .having(
        (error) => error.toString(),
        'redacted message',
        isNot(contains('synthetic')),
      )
      .having(
        (error) => error.toString(),
        'no URL',
        isNot(contains('https://')),
      ),
);

void main() {
  test(
    'resolves observed attachment paths and preserves signed plus characters',
    () {
      for (final path in ['/attachment', '/attachment/']) {
        final result = resolveICloudAttachmentUrl(
          _publication(path: path),
          expectedBytes: 42,
        );
        expect(
          result.toString(),
          'https://cvws.icloud-content.com/B/test/reference%20clip.mp4?o=signed&k=synthetic+key/with=padding&s=tail',
        );
        expect(result.query, contains('k=synthetic+key/with=padding'));
      }
    },
  );

  test('decodes wrapper exactly once and preserves existing percent escapes', () {
    final result = resolveICloudAttachmentUrl(
      _publication(
        template:
            r'https://cvws.icloud-content.com/B/a%2Fb/${f}?o=a%2Bb&k=${uk}&s=x%2Fy',
        key: 'synthetic%2Bkey',
        filename: 'snow ☃.mp4',
      ),
      expectedBytes: 42,
    );
    expect(
      result.toString(),
      'https://cvws.icloud-content.com/B/a%2Fb/snow%20%E2%98%83.mp4?o=a%2Bb&k=synthetic%2Bkey&s=x%2Fy',
    );
  });

  test(
    'rejects changed wrapper, template, filename, and size without URL errors',
    () {
      final valid = _publication();
      final invalid = <String>[
        valid.replaceFirst('https:', 'http:'),
        valid.replaceFirst('www.icloud.com', 'icloud.com.attacker.example'),
        valid.replaceFirst('www.icloud.com', 'user:pass@www.icloud.com'),
        valid.replaceFirst('www.icloud.com', 'www.icloud.com:8443'),
        '$valid#fragment',
        _publication(path: '/attachment/extra'),
        _publication(path: '/other'),
        _publication(bytes: 43),
        _publication(bytes: 0),
        valid.replaceFirst('?u=', '?other='),
        valid.replaceFirst('&uk=', '&changed='),
        '$valid&unexpected=1',
        _publication(template: r'https://attacker.example/${f}?k=${uk}'),
        _publication(
          template:
              r'https://cvws.icloud-content.com.attacker.example/${f}?k=${uk}',
        ),
        _publication(
          template: r'https://user@cvws.icloud-content.com/${f}?k=${uk}',
        ),
        _publication(
          template: r'https://cvws.icloud-content.com:8443/${f}?k=${uk}',
        ),
        _publication(
          template: r'https://cvws.icloud-content.com/${f}?k=${uk}#fragment',
        ),
        _publication(
          template: r'https://cvws.icloud-content.com/${f}/${f}?k=${uk}',
        ),
        _publication(
          template: r'https://cvws.icloud-content.com/${f}?missing=key',
        ),
        _publication(
          template:
              r'https://cvws.icloud-content.com/${f}?k=${uk}&left=${unknown}',
        ),
        _publication(key: ''),
        _publication(key: 'synthetic&injected=1'),
        _publication(key: 'synthetic\nheader'),
        _publication(filename: ''),
        _publication(filename: '../original.mp4'),
        _publication(filename: 'reference.mp4?extra=1'),
        _publication(filename: 'reference.mp4&extra=1'),
        _publication(filename: 'reference\u0000.mp4'),
      ];
      for (var index = 0; index < invalid.length; index++) {
        expect(
          () => resolveICloudAttachmentUrl(invalid[index], expectedBytes: 42),
          _safeFailure,
          reason: 'invalid shape $index',
        );
      }
    },
  );

  test(
    'asset allowlist admits only anonymous HTTPS Apple content subdomains',
    () {
      expect(
        isICloudAssetUrl(
          Uri.parse('https://cvws.icloud-content.com/file?k=synthetic'),
        ),
        isTrue,
      );
      for (final value in [
        'http://cvws.icloud-content.com/file',
        'https://icloud-content.com/file',
        'https://attacker.icloud-content.com.evil/file',
        'https://user:pass@cvws.icloud-content.com/file',
        'https://cvws.icloud-content.com:8443/file',
        'https://cvws.icloud-content.com/file#fragment',
        'https://127.0.0.1/file',
      ]) {
        expect(isICloudAssetUrl(Uri.parse(value)), isFalse);
      }
    },
  );
}
