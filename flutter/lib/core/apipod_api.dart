import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_transcript.dart';
import 'apipod_model_contracts.dart';
import 'bfl_api.dart';
import 'generation_status.dart';
import 'models.dart';
import 'provider_submission.dart';

/// APIPod's shared asynchronous media API, used by native gateways and the
/// desktop companion. Only the canonical polling URL is retained with a job.
class ApipodApi {
  ApipodApi({http.Client? client, Uri? baseUrl})
    : _rawClient = client ?? http.Client(),
      _baseUrl = baseUrl ?? Uri.parse('https://api.apipod.ai') {
    _client = recordingProviderClient(_rawClient);
  }

  final http.Client _rawClient;
  late final http.Client _client;
  final Uri _baseUrl;
  static final _taskId = RegExp(r'^[A-Za-z0-9_-]{1,256}$');
  static final _userInfo = RegExp(r'^[^:/?#]+://[^/?#]*@');

  Future<ProviderAccountStatus> verify(String key) async {
    // APIPod documents this authenticated probe, but no stable balance schema.
    // Do not infer a zero balance or record private account details.
    _read(await _send('GET', '/v1/account/status', key, record: false), key);
    return const ProviderAccountStatus(
      provider: 'apipod',
      balanceLabel: 'Open APIPod to view balance ↗',
    );
  }

  Map<String, Object?> generationPayload(
    String model,
    Map<String, Object?> input,
  ) => apipodGenerationPayload(model, input);

  Future<Map<String, Object?>> submit(
    String key,
    String model,
    Map<String, Object?> input, {
    BeforeGenerationSend? beforeSend,
    String? operationId,
  }) async {
    _validateKey(key);
    final body = jsonEncode(generationPayload(model, input));
    await beforeSend?.call();
    final envelope = _read(
      await _send(
        'POST',
        '/v1/videos/generations',
        key,
        body: body,
        idempotencyKey: operationId == null
            ? null
            : submissionIdempotencyToken(operationId),
      ),
      key,
    );
    final data = envelope['data'];
    final id = data is Map ? data['task_id'] : null;
    if (id is! String || !_taskId.hasMatch(id)) {
      throw const ProviderException(
        'APIPod returned an invalid generation receipt.',
        status: 502,
      );
    }
    return <String, Object?>{
      'id': id,
      'polling_url': _baseUrl.resolve('/v1/videos/status/$id').toString(),
    };
  }

  Future<Map<String, Object?>> poll(String key, String pollingUrl) async {
    final url = _validatedStatusUrl(pollingUrl);
    final id = url.pathSegments.last;
    final response = await _send('GET', url.path, key);
    if (response.statusCode == 404 || response.statusCode == 410) {
      return <String, Object?>{'id': id, 'status': 'Task not found'};
    }
    final envelope = _read(response, key);
    final data = envelope['data'];
    if (data is! Map || data['task_id'] != id) {
      throw const ProviderException(
        'APIPod returned an invalid task status.',
        status: 502,
      );
    }
    final status = data['status'];
    if (!const [
      'pending',
      'processing',
      'completed',
      'failed',
      'cancelled',
    ].contains(status)) {
      throw const ProviderException(
        'APIPod returned an unrecognized task status.',
        status: 502,
      );
    }
    final progress = data['progress'];
    final result = <String, Object?>{
      'id': id,
      'status': status,
      if (progress is num &&
          progress.isFinite &&
          progress >= 0 &&
          progress <= 100)
        'progress_percentage': progress,
    };
    if (status == 'failed' || status == 'cancelled') {
      result['error'] = _message(
        <String, Object?>{'error': data['error'] ?? data['error_message']},
        key,
        status == 'cancelled'
            ? 'APIPod cancelled this generation.'
            : 'APIPod reported that this generation failed.',
      );
      if (data['error_code'] is String) {
        result['error_code'] = _scrub(data['error_code'], key);
      }
    }
    if (status == 'completed') {
      final usage = data['usage'];
      final cost = usage is Map ? usage['cost'] : null;
      // Only the completed task's usage.cost is a final USD charge. Pending
      // account observations or quoted prices must never become realized cost.
      if (cost is num && cost.isFinite && cost >= 0) result['cost'] = cost;
      final outputs = data['result'];
      if (outputs is! List || outputs.isEmpty) {
        return <String, Object?>{
          ...result,
          'status': 'Failed',
          'error': 'APIPod completed this request without a video output.',
        };
      }
      result['outputs'] = outputs.map((value) {
        if (value is! String) {
          throw const ProviderException(
            'APIPod returned an invalid video URL.',
            status: 502,
          );
        }
        return validatedProviderUrl(value).toString();
      }).toList();
    }
    return result;
  }

  Uri _validatedStatusUrl(String value) {
    final url = Uri.tryParse(value);
    final parts = url?.pathSegments ?? const <String>[];
    if (url == null ||
        url.scheme != _baseUrl.scheme ||
        url.host != _baseUrl.host ||
        url.port != _baseUrl.port ||
        _userInfo.hasMatch(value) ||
        url.hasQuery ||
        url.hasFragment ||
        parts.length != 4 ||
        parts[0] != 'v1' ||
        parts[1] != 'videos' ||
        parts[2] != 'status' ||
        !_taskId.hasMatch(parts[3]) ||
        url.path != '/${parts.join('/')}') {
      throw const ProviderException(
        'The APIPod status URL is invalid.',
        status: 400,
      );
    }
    return url;
  }

  Future<http.Response> _send(
    String method,
    String path,
    String key, {
    String? body,
    String? idempotencyKey,
    bool record = true,
  }) async {
    _validateKey(key);
    final request = http.Request(method, _baseUrl.resolve(path))
      ..followRedirects = false
      ..headers.addAll(<String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $key',
        if (body != null) 'Content-Type': 'application/json',
        if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
      });
    if (body != null) request.body = body;
    Future<http.Response> send() async => http.Response.fromStream(
      await (record ? _client : _rawClient).send(request),
    );
    try {
      final scope = ApiTranscriptScope.current;
      final future = record && scope != null
          ? ApiTranscriptScope.run(
              send,
              sink: _ApipodTranscriptSink(scope.sink, key),
              operationId: scope.operationId,
              provider: scope.provider,
              purpose: scope.purpose,
            )
          : send();
      return await future.timeout(const Duration(seconds: 60));
    } on TimeoutException {
      throw const ProviderException(
        'APIPod did not respond in time. Check the existing request before submitting again.',
      );
    } on http.ClientException {
      throw const ProviderException(
        'Clawnsole could not reach APIPod. Check the existing request before submitting again.',
      );
    }
  }

  void _validateKey(String key) {
    if (key.trim().isEmpty || key.contains(RegExp(r'[\r\n]'))) {
      throw const ProviderException(
        'Add a valid APIPod API key first.',
        status: 401,
      );
    }
  }

  Map<String, Object?> _read(http.Response response, String key) {
    Object? body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      body = null;
    }
    final success = response.statusCode >= 200 && response.statusCode < 300;
    if (success &&
        body is Map<String, Object?> &&
        body['error'] == null &&
        (body['code'] == null || body['code'] == 200)) {
      return body;
    }
    // HTTP is authoritative for rejection classification. A malformed or
    // contradictory success envelope cannot prove that create was rejected.
    final status =
        success || response.statusCode >= 300 && response.statusCode < 400
        ? 502
        : response.statusCode;
    final fallback = switch (status) {
      400 || 422 => 'APIPod rejected these generation settings.',
      401 || 403 => 'APIPod rejected this API key or its permissions.',
      402 => 'This APIPod account does not have enough balance.',
      404 => 'APIPod no longer recognizes this request.',
      429 => 'APIPod is at this account’s request limit. Try again shortly.',
      _ => 'APIPod returned an invalid response (HTTP ${response.statusCode}).',
    };
    final message = _message(body, key, fallback);
    throw ProviderException(
      message,
      status: status,
      details: {'error': message},
    );
  }

  String _message(Object? body, String key, String fallback) {
    String? find(Object? value) {
      if (value is String && value.trim().isNotEmpty) return value.trim();
      if (value is Map) {
        for (final field in const [
          'error',
          'error_message',
          'message',
          'detail',
        ]) {
          final message = find(value[field]);
          if (message != null) return message;
        }
      }
      return null;
    }

    return sanitizeProviderDiagnosticValue(_scrub(find(body) ?? fallback, key))
        as String;
  }
}

Object? _scrub(Object? value, String key) {
  if (value is String) {
    return key.isEmpty ? value : value.replaceAll(key, redactedValue);
  }
  if (value is List) return value.map((item) => _scrub(item, key)).toList();
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        _scrub(entry.key.toString(), key)! as String: _scrub(entry.value, key),
    };
  }
  return value;
}

class _ApipodTranscriptSink implements ApiTranscriptSink {
  _ApipodTranscriptSink(this.inner, this.key);
  final ApiTranscriptSink inner;
  final String key;

  @override
  void addApiRequest(ApiRequestRecord record) => inner.addApiRequest(
    ApiRequestRecord.fromJson(
      _scrub(record.toJson(), key)! as Map<String, Object?>,
    ),
  );
}
