import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_version.dart';

const clawnsoleRepository = 'heresalexandria/clawnsole';
const clawnsoleReleasePage =
    'https://github.com/$clawnsoleRepository/releases/latest';
const _releaseApi =
    'https://api.github.com/repos/$clawnsoleRepository/releases/latest';

/// What the app knows about the latest published release.
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.current,
    this.latest,
    this.available = false,
    this.installable = false,
    this.error,
    this.releaseUrl = clawnsoleReleasePage,
  });

  final String current;
  final String? latest;
  final bool available;

  /// Whether the running shell can download and install it in place.
  final bool installable;
  final String? error;
  final String releaseUrl;

  factory UpdateCheckResult.fromShell(Map<String, Object?> payload) =>
      UpdateCheckResult(
        current: payload['current'] as String? ?? clawnsoleVersion,
        latest: payload['latest'] as String?,
        available: payload['available'] == true,
        installable: payload['installable'] == true,
        error: payload['error'] as String?,
        releaseUrl: payload['htmlUrl'] as String? ?? clawnsoleReleasePage,
      );
}

List<int>? parseSemanticVersion(String value) {
  final match = RegExp(
    r'^v?(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$',
  ).firstMatch(value.trim());
  if (match == null) return null;
  return <int>[
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  ];
}

/// Returns a positive number when [candidate] is newer than [current], zero
/// when equal, negative when older, and null when either cannot be parsed.
int? compareSemanticVersions(String candidate, String current) {
  final a = parseSemanticVersion(candidate);
  final b = parseSemanticVersion(current);
  if (a == null || b == null) return null;
  for (var index = 0; index < 3; index += 1) {
    if (a[index] != b[index]) return a[index] - b[index];
  }
  return 0;
}

/// Whether [candidate] crosses a major-version compatibility boundary from
/// [current]. Invalid or same-major versions are never treated as mandatory.
bool isMajorVersionUpgrade(String candidate, String current) {
  final next = parseSemanticVersion(candidate);
  final running = parseSemanticVersion(current);
  return next != null && running != null && next.first > running.first;
}

/// Asks GitHub for the latest stable release. Used on surfaces without a
/// shell updater except native iOS, which checks Apple's published listing.
Future<UpdateCheckResult> checkLatestRelease({http.Client? client}) async {
  final http.Client active = client ?? http.Client();
  try {
    final response = await active
        .get(
          Uri.parse(_releaseApi),
          headers: const <String, String>{
            'Accept': 'application/vnd.github+json',
          },
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      return UpdateCheckResult(
        current: clawnsoleVersion,
        error: 'GitHub returned HTTP ${response.statusCode}.',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<Object?, Object?>) {
      return const UpdateCheckResult(
        current: clawnsoleVersion,
        error: 'GitHub returned an unexpected release payload.',
      );
    }
    final latest = (decoded['tag_name']?.toString() ?? '').replaceFirst(
      RegExp('^v'),
      '',
    );
    final htmlUrl = decoded['html_url']?.toString();
    return UpdateCheckResult(
      current: clawnsoleVersion,
      latest: latest.isEmpty ? null : latest,
      available: (compareSemanticVersions(latest, clawnsoleVersion) ?? 0) > 0,
      releaseUrl: htmlUrl != null && htmlUrl.startsWith('https://github.com/')
          ? htmlUrl
          : clawnsoleReleasePage,
    );
  } on Object catch (error) {
    return UpdateCheckResult(
      current: clawnsoleVersion,
      error: error.toString().replaceFirst('Exception: ', ''),
    );
  } finally {
    if (client == null) active.close();
  }
}
