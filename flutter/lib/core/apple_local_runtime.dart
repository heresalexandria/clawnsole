import 'package:flutter/services.dart';

/// Bridge to Apple Intelligence image creation in the native iOS runner.
///
/// The method channel deliberately exposes an asynchronous job contract so a
/// long image sequence can keep using Clawnsole's existing generation polling
/// and persistence behavior.
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
    try {
      final value = await _channel.invokeMapMethod<String, Object?>(
        'submit',
        request,
      );
      if (value == null) {
        throw StateError(
          'Apple Intelligence returned an invalid generation receipt.',
        );
      }
      return value;
    } on MissingPluginException {
      throw StateError(
        'Apple Intelligence image creation is available only in the iOS app.',
      );
    }
  }

  @override
  Future<Map<String, Object?>> poll(String jobId) async {
    try {
      final value = await _channel.invokeMapMethod<String, Object?>('poll', {
        'jobId': jobId,
      });
      if (value == null) {
        throw StateError(
          'Apple Intelligence returned an invalid status response.',
        );
      }
      return value;
    } on MissingPluginException {
      throw StateError(
        'Apple Intelligence image creation is available only in the iOS app.',
      );
    }
  }
}
