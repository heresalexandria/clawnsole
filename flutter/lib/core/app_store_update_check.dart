import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_version.dart';
import 'store_update.dart';
import 'update_check.dart';

const _appStoreLookupHost = 'itunes.apple.com';
const _appStoreLookupPath = '/lookup';

/// Asks Apple which Clawnsole version is currently public in the App Store.
///
/// GitHub releases can precede App Store review and processing. Native iOS
/// builds therefore use Apple's catalog as the availability boundary so an
/// update is never announced or required before users can install it.
Future<UpdateCheckResult> checkLatestIosAppStoreVersion({
  http.Client? client,
}) async {
  final active = client ?? http.Client();
  try {
    final response = await active
        .get(
          Uri.https(_appStoreLookupHost, _appStoreLookupPath, <String, String>{
            'id': clawnsoleIosAppStoreId,
          }),
          headers: const <String, String>{'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      return UpdateCheckResult(
        current: clawnsoleVersion,
        error: 'App Store returned HTTP ${response.statusCode}.',
        releaseUrl: clawnsoleIosAppStoreWebUrl,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<Object?, Object?>) {
      return const UpdateCheckResult(
        current: clawnsoleVersion,
        error: 'App Store returned an unexpected lookup payload.',
        releaseUrl: clawnsoleIosAppStoreWebUrl,
      );
    }
    final results = decoded['results'];
    if (results is! List<Object?> || results.isEmpty) {
      return const UpdateCheckResult(
        current: clawnsoleVersion,
        error: 'Clawnsole is not currently listed by the App Store.',
        releaseUrl: clawnsoleIosAppStoreWebUrl,
      );
    }

    final app = results.first;
    if (app is! Map<Object?, Object?> ||
        app['trackId']?.toString() != clawnsoleIosAppStoreId ||
        app['bundleId']?.toString() != clawnsoleIosBundleId) {
      return const UpdateCheckResult(
        current: clawnsoleVersion,
        error: 'App Store returned an unexpected Clawnsole listing.',
        releaseUrl: clawnsoleIosAppStoreWebUrl,
      );
    }

    final latest = app['version']?.toString().trim() ?? '';
    if (parseSemanticVersion(latest) == null) {
      return const UpdateCheckResult(
        current: clawnsoleVersion,
        error: 'App Store returned an invalid Clawnsole version.',
        releaseUrl: clawnsoleIosAppStoreWebUrl,
      );
    }
    final trackViewUrl = _trustedAppStoreUrl(app['trackViewUrl']?.toString());
    return UpdateCheckResult(
      current: clawnsoleVersion,
      latest: latest,
      available: (compareSemanticVersions(latest, clawnsoleVersion) ?? 0) > 0,
      releaseUrl: trackViewUrl ?? clawnsoleIosAppStoreWebUrl,
    );
  } on Object catch (error) {
    return UpdateCheckResult(
      current: clawnsoleVersion,
      error: error.toString().replaceFirst('Exception: ', ''),
      releaseUrl: clawnsoleIosAppStoreWebUrl,
    );
  } finally {
    if (client == null) active.close();
  }
}

String? _trustedAppStoreUrl(String? value) {
  final uri = value == null ? null : Uri.tryParse(value);
  return uri != null && uri.scheme == 'https' && uri.host == 'apps.apple.com'
      ? uri.toString()
      : null;
}
