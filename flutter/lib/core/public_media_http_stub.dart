import 'package:http/http.dart' as http;

/// Renderer media must travel through the companion's protected media route.
class PublicMediaClient extends http.BaseClient {
  PublicMediaClient({
    int maxBytes = 2 * 1024 * 1024 * 1024,
    Duration connectTimeout = const Duration(seconds: 20),
    Duration idleTimeout = const Duration(seconds: 20),
    Duration totalTimeout = const Duration(minutes: 10),
    int maxRedirects = 5,
  });

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Future<http.StreamedResponse>.error(
        UnsupportedError('Remote media requires the Clawnsole companion.'),
      );
}

Future<void> validatePublicMediaDestination(
  Uri uri, {
  Duration timeout = const Duration(seconds: 20),
}) => Future<void>.error(
  UnsupportedError('Remote media requires the Clawnsole companion.'),
);
