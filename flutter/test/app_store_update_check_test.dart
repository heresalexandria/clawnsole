import 'dart:convert';

import 'package:clawnsole/core/app_store_update_check.dart';
import 'package:clawnsole/core/app_version.dart';
import 'package:clawnsole/core/store_update.dart';
import 'package:clawnsole/core/update_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('uses the version Apple has published for Clawnsole', () async {
    late Uri lookupUri;
    final result = await checkLatestIosAppStoreVersion(
      client: MockClient((request) async {
        lookupUri = request.url;
        return http.Response(
          jsonEncode(<String, Object?>{
            'resultCount': 1,
            'results': <Object?>[
              <String, Object?>{
                'trackId': int.parse(clawnsoleIosAppStoreId),
                'bundleId': clawnsoleIosBundleId,
                'version': '1.0.0',
                'trackViewUrl':
                    'https://apps.apple.com/us/app/clawnsole/'
                    'id$clawnsoleIosAppStoreId',
              },
            ],
          }),
          200,
        );
      }),
    );

    expect(lookupUri.scheme, 'https');
    expect(lookupUri.host, 'itunes.apple.com');
    expect(lookupUri.queryParameters['id'], clawnsoleIosAppStoreId);
    expect(result.current, clawnsoleVersion);
    expect(result.latest, '1.0.0');
    expect(result.available, isTrue);
    expect(result.installable, isFalse);
    expect(result.error, isNull);
    expect(result.releaseUrl, startsWith('https://apps.apple.com/'));
  });

  test(
    'a release still processing at Apple is not treated as available',
    () async {
      final result = await checkLatestIosAppStoreVersion(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object?>{
              'resultCount': 0,
              'results': <Object?>[],
            }),
            200,
          ),
        ),
      );

      expect(result.available, isFalse);
      expect(result.latest, isNull);
      expect(result.error, contains('not currently listed'));
      expect(result.releaseUrl, clawnsoleIosAppStoreWebUrl);
    },
  );

  test('an Apple-published major release still requires updating', () async {
    final status = UpdateStatus.forMobileTesting(
      () => checkLatestIosAppStoreVersion(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object?>{
              'resultCount': 1,
              'results': <Object?>[
                <String, Object?>{
                  'trackId': int.parse(clawnsoleIosAppStoreId),
                  'bundleId': clawnsoleIosBundleId,
                  'version': '1.0.0',
                },
              ],
            }),
            200,
          ),
        ),
      ),
    );

    await status.refresh(force: false);

    expect(status.updateAvailable, isTrue);
    expect(status.requiresStoreUpdate, isTrue);
    expect(status.requiresMajorUpdate, isTrue);
  });

  test('rejects a listing that is not the configured iOS app', () async {
    final result = await checkLatestIosAppStoreVersion(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode(<String, Object?>{
            'resultCount': 1,
            'results': <Object?>[
              <String, Object?>{
                'trackId': int.parse(clawnsoleIosAppStoreId),
                'bundleId': 'example.wrong.app',
                'version': '1.0.0',
              },
            ],
          }),
          200,
        ),
      ),
    );

    expect(result.available, isFalse);
    expect(result.error, contains('unexpected Clawnsole listing'));
  });

  test('an App Store lookup failure never announces an update', () async {
    final result = await checkLatestIosAppStoreVersion(
      client: MockClient((_) async => http.Response('Unavailable', 503)),
    );

    expect(result.available, isFalse);
    expect(result.latest, isNull);
    expect(result.error, 'App Store returned HTTP 503.');
  });
}
