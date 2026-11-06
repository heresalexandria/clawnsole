/// Private platform boundary. Publication URLs must not be logged or exposed
/// to the renderer; only the privileged media backend consumes these replies.
abstract interface class ICloudReferenceTransport {
  Future<Map<String, Object?>> call(
    String method, [
    Map<String, Object?> arguments = const {},
  ]);
  Future<void> close();
}

class ICloudReferenceException implements Exception {
  const ICloudReferenceException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

Map<String, Object?> checkedICloudReferenceReply(Object? response) {
  if (response is! Map) {
    throw const ICloudReferenceException(
      'invalidResponse',
      'iCloud Drive returned an invalid response. Restart Clawnsole and retry.',
    );
  }
  final value = Map<String, Object?>.from(response);
  if (value['ok'] != true) {
    final error = value['error'];
    throw ICloudReferenceException(
      error is Map ? error['code']?.toString() ?? 'unavailable' : 'unavailable',
      (error is Map
              ? error['message']?.toString() ?? 'iCloud Drive is unavailable.'
              : 'iCloud Drive is unavailable.')
          .replaceAll(
            RegExp(r'https?://[^\s<>"\x27]+'),
            '«private reference link»',
          ),
    );
  }
  return value;
}

class UnavailableICloudReferenceTransport implements ICloudReferenceTransport {
  const UnavailableICloudReferenceTransport();
  @override
  Future<Map<String, Object?>> call(
    String method, [
    Map<String, Object?> arguments = const {},
  ]) async {
    if (method == 'status') {
      return {
        'ok': true,
        'supported': false,
        'state': 'unsupported',
        'message':
            'Uploading references through iCloud Drive requires Clawnsole on iOS or macOS. You can still use public HTTPS references on this device.',
      };
    }
    throw const ICloudReferenceException(
      'unsupported',
      'iCloud Drive reference sharing is unavailable on this device.',
    );
  }

  @override
  Future<void> close() async {}
}
