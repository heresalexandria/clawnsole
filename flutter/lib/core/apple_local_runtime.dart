import 'package:flutter/services.dart';

abstract interface class AppleLocalRuntime {
  Future<bool> isAvailable();
  Future<Map<String, Object?>> submit(Map<String, Object?> request);
  Future<Map<String, Object?>> poll(String jobId);
}

class MethodChannelAppleLocalRuntime implements AppleLocalRuntime {
  const MethodChannelAppleLocalRuntime();

  static const _channel = MethodChannel('ai.clawnsole/apple_local');

  @override
  Future<bool> isAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<Map<String, Object?>> submit(Map<String, Object?> request) async {
    final value = await _channel.invokeMapMethod<String, Object?>(
      'submit',
      request,
    );
    if (value == null) {
      throw StateError('Apple Local returned an invalid generation receipt.');
    }
    return value;
  }

  @override
  Future<Map<String, Object?>> poll(String jobId) async {
    final value = await _channel.invokeMapMethod<String, Object?>('poll', {
      'jobId': jobId,
    });
    if (value == null) {
      throw StateError('Apple Local returned an invalid status response.');
    }
    return value;
  }
}
