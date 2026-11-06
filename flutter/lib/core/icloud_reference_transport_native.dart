import 'dart:async';

import 'package:flutter/services.dart';

import 'icloud_reference_transport.dart';

class NativeICloudReferenceTransport implements ICloudReferenceTransport {
  const NativeICloudReferenceTransport({
    MethodChannel channel = const MethodChannel(
      'ai.clawnsole/icloud_reference_host',
    ),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<Map<String, Object?>> call(
    String method, [
    Map<String, Object?> arguments = const {},
  ]) async {
    try {
      return checkedICloudReferenceReply(
        await _channel
            .invokeMethod<Object?>(method, arguments)
            .timeout(
              method == 'prepare'
                  ? const Duration(minutes: 4)
                  : const Duration(seconds: 30),
            ),
      );
    } on ICloudReferenceException {
      rethrow;
    } on TimeoutException {
      if (method == 'prepare') {
        unawaited(
          _channel
              .invokeMethod<void>('cancel', {'leaseId': arguments['leaseId']})
              .catchError((Object _) {}),
        );
      }
      throw const ICloudReferenceException(
        'timeout',
        'iCloud Drive took too long. Check your connection and retry; Clawnsole will recover its temporary copy.',
      );
    } on Object {
      throw const ICloudReferenceException(
        'unavailable',
        'iCloud Drive is unavailable. Check your Apple Account and enable iCloud Drive for Clawnsole in Settings.',
      );
    }
  }

  @override
  Future<void> close() async {}
}
