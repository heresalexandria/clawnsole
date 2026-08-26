import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'bfl_api.dart';

/// A result video handed back by the platform's background transfer service.
class DeliveredResult {
  const DeliveredResult({required this.bytes, this.contentType});

  final Uint8List bytes;
  final String? contentType;
}

/// Delegates result downloads to a platform transfer service that keeps
/// working while the process is suspended.
///
/// iOS freezes app-owned sockets seconds after backgrounding, but a download
/// owned by a background URLSession is completed by the OS itself — even if
/// the app is terminated in the background — and the finished file is retained
/// until [completeResult] releases it. Platforms whose shells never suspend
/// the process register no handler and [download] reports unsupported, so the
/// caller falls back to its in-process HTTP path.
abstract class BackgroundResultDelivery {
  /// Downloads [url] through the platform service, or returns null when the
  /// platform has no service. Throws [TimeoutException] when the transfer
  /// stalled (which says nothing about the link itself) and
  /// [ProviderException] for definitive HTTP failures.
  Future<DeliveredResult?> download({required String id, required String url});

  /// Ids of finished downloads the platform is retaining — including films
  /// that completed while the process was suspended or after it was
  /// terminated.
  Future<List<String>> pendingResultIds();

  /// Reads a retained download, or null when its file is gone.
  Future<DeliveredResult?> readPendingResult(String id);

  /// Releases a retained download once the asset store owns the bytes.
  Future<void> completeResult(String id);
}

class MethodChannelBackgroundResultDelivery
    implements BackgroundResultDelivery {
  MethodChannelBackgroundResultDelivery();

  static const MethodChannel _channel = MethodChannel(
    'ai.clawnsole/background_delivery',
  );

  bool _unsupported = false;
  final Map<String, Future<DeliveredResult?>> _inFlight =
      <String, Future<DeliveredResult?>>{};

  @override
  Future<DeliveredResult?> download({required String id, required String url}) {
    if (_unsupported) return Future<DeliveredResult?>.value();
    // Retention retries for the same generation share one transfer and one
    // in-memory copy of the bytes instead of stacking channel waiters — a
    // poll abandoned by its caller's timeout leaves the future here for the
    // next retry to join.
    return _inFlight[id] ??= _download(id, url).whenComplete(() {
      _inFlight.remove(id);
    });
  }

  Future<DeliveredResult?> _download(String id, String url) async {
    final Map<String, Object?>? value;
    try {
      value = await _channel.invokeMapMethod<String, Object?>(
        'download',
        <String, Object?>{'id': id, 'url': url},
      );
    } on MissingPluginException {
      _unsupported = true;
      return null;
    } on PlatformException catch (error) {
      throw _deliveryError(error);
    }
    return _readDelivered(value);
  }

  @override
  Future<List<String>> pendingResultIds() async {
    if (_unsupported) return const <String>[];
    try {
      return await _channel.invokeListMethod<String>('pendingResultIds') ??
          const <String>[];
    } on MissingPluginException {
      _unsupported = true;
      return const <String>[];
    } on PlatformException {
      return const <String>[];
    }
  }

  @override
  Future<DeliveredResult?> readPendingResult(String id) async {
    if (_unsupported) return null;
    try {
      final value = await _channel.invokeMapMethod<String, Object?>(
        'pendingResult',
        <String, Object?>{'id': id},
      );
      return _readDelivered(value);
    } on MissingPluginException {
      _unsupported = true;
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> completeResult(String id) async {
    if (_unsupported) return;
    try {
      await _channel.invokeMethod<void>('completeResult', <String, Object?>{
        'id': id,
      });
    } on MissingPluginException {
      _unsupported = true;
    } on PlatformException {
      // The retained file is cleaned up by a later recovery pass.
    }
  }

  Future<DeliveredResult?> _readDelivered(Map<String, Object?>? value) async {
    final path = value?['path'] as String?;
    if (path == null) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    final contentType = value?['contentType'] as String?;
    return DeliveredResult(
      bytes: await file.readAsBytes(),
      contentType: contentType?.isNotEmpty == true ? contentType : null,
    );
  }

  Object _deliveryError(PlatformException error) => switch (error.code) {
    // Stalls, lost connectivity, and local write hiccups say nothing about
    // the delivery link itself, so they stay retryable — connectivity is
    // often still re-establishing at the exact moment a foreground return
    // runs this code. Only an HTTP answer from the link is definitive.
    'timeout' || 'network' || 'io' => TimeoutException(
      error.message ?? 'The provider result download stalled.',
    ),
    'http' => ProviderException(
      error.message ?? 'The provider result download failed.',
      status: error.details is int ? error.details as int : null,
    ),
    _ => ProviderException(
      error.message ?? 'The provider result download failed.',
    ),
  };
}
