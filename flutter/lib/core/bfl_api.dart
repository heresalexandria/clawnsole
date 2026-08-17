import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'generation_status.dart';

class ProviderException implements Exception {
  const ProviderException(this.message, {this.status, this.details});

  final String message;
  final int? status;
  final Object? details;

  @override
  String toString() => message;
}

class BflApi {
  BflApi({http.Client? client, Uri? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? Uri.parse('https://api.bfl.ai');

  final http.Client _client;
  final Uri _baseUrl;

  Future<http.Response> _request(
    Future<http.Response> request,
    String operation,
  ) async {
    try {
      return await request.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw ProviderException(
        'BFL did not respond while Clawnsole tried to $operation. You can check again without resubmitting.',
      );
    }
  }

  Map<String, String> _headers(String apiKey, {bool json = false}) =>
      <String, String>{
        'Accept': 'application/json',
        'x-key': apiKey,
        if (json) 'Content-Type': 'application/json',
      };

  Future<double> getCredits(String apiKey) async {
    final payload = await _read(
      await _request(
        _client.get(_baseUrl.resolve('/v1/credits'), headers: _headers(apiKey)),
        'check your credits',
      ),
    );
    final credits = payload is Map<String, Object?> ? payload['credits'] : null;
    if (credits is! num) {
      throw const ProviderException(
        'BFL returned an invalid credit balance.',
        status: 502,
      );
    }
    return credits.toDouble();
  }

  Future<Map<String, Object?>> submit(
    String apiKey,
    Map<String, Object?> input,
  ) async {
    final payload = await _read(
      await _request(
        _client.post(
          _baseUrl.resolve('/v1/flux-3-video'),
          headers: _headers(apiKey, json: true),
          body: jsonEncode(input),
        ),
        'submit the generation',
      ),
    );
    if (payload is! Map<String, Object?>) {
      throw const ProviderException(
        'BFL returned an invalid submission.',
        status: 502,
      );
    }
    return payload;
  }

  Future<Map<String, Object?>> poll(String apiKey, String pollingUrl) async {
    final url = validatedBflUrl(pollingUrl);
    final payload = await _read(
      await _request(
        _client.get(url, headers: _headers(apiKey)),
        'check the generation status',
      ),
    );
    if (payload is! Map<String, Object?>) {
      throw const ProviderException(
        'BFL returned an invalid status.',
        status: 502,
      );
    }
    return payload;
  }

  Future<Object?> _read(http.Response response) async {
    Object? payload;
    try {
      payload = jsonDecode(response.body);
    } on FormatException {
      payload = response.body;
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return stringKeyMap(payload);
    }
    final fallback = switch (response.statusCode) {
      401 || 403 => 'BFL rejected this API key.',
      402 => 'This BFL project does not have enough credits.',
      429 => 'BFL is at its active request limit. Try again shortly.',
      500 || 502 || 503 || 504 =>
        'BFL is temporarily unavailable (HTTP ${response.statusCode}). Retry shortly.',
      _ => 'BFL returned ${response.statusCode}.',
    };
    throw ProviderException(
      providerFailureMessage(payload, fallback: fallback),
      status: response.statusCode,
      details: payload,
    );
  }
}

int? providerHttpStatus(Object error) =>
    error is ProviderException ? error.status : null;

Map<String, Object?>? providerErrorPayload(Object error) {
  final details = error is ProviderException ? error.details : null;
  if (details is! Map<Object?, Object?>) return null;
  return details.map((key, value) => MapEntry(key.toString(), value));
}

String providerErrorResponse(Object error) => compactProviderResponse(
  error is ProviderException
      ? error.details ?? <String, Object?>{'error': error.message}
      : <String, Object?>{'error': generationExceptionMessage(error)},
);

String providerNamedFailureMessage(
  String providerName,
  Object? payload, {
  required String fallback,
}) {
  final message = providerFailureMessage(payload, fallback: fallback);
  if (fallback.contains(providerName) && message.contains(fallback)) {
    return fallback;
  }
  return message.replaceFirst(RegExp(r'^BFL\b'), providerName);
}

Uri validatedBflUrl(String value) {
  final url = Uri.tryParse(value);
  if (url == null ||
      url.scheme != 'https' ||
      !(url.host == 'bfl.ai' || url.host.endsWith('.bfl.ai'))) {
    throw const ProviderException(
      'The BFL delivery URL is invalid.',
      status: 400,
    );
  }
  return url;
}

Object? stringKeyMap(Object? value) {
  if (value is List<Object?>) return value.map(stringKeyMap).toList();
  if (value is Map<Object?, Object?>) {
    return value.map(
      (key, child) => MapEntry(key.toString(), stringKeyMap(child)),
    );
  }
  return value;
}

Uri validatedProviderUrl(String value) {
  final url = Uri.tryParse(value);
  final host = url?.host.toLowerCase() ?? '';
  if (url == null ||
      url.scheme != 'https' ||
      host.isEmpty ||
      host == 'localhost' ||
      host == '127.0.0.1' ||
      host == '::1' ||
      host.endsWith('.local')) {
    throw const ProviderException('The provider URL is invalid.', status: 400);
  }
  return url;
}

double? normalizedProgress(Object? value) {
  if (value is! num || !value.isFinite) return null;
  final progress = value <= 1 ? value * 100 : value;
  return progress.toDouble().clamp(0, 100);
}

String? findResultUrl(Object? value, {required bool draft, String key = ''}) {
  if (value is String && value.startsWith('https://')) {
    final looksLikeDraft = RegExp(
      r'draft|cache|\.bin(?:\?|$)',
      caseSensitive: false,
    ).hasMatch('$key $value');
    if (draft == looksLikeDraft) return value;
  }
  if (value is List<Object?>) {
    for (final child in value) {
      final found = findResultUrl(child, draft: draft, key: key);
      if (found != null) return found;
    }
  }
  if (value is Map<Object?, Object?>) {
    for (final entry in value.entries) {
      final found = findResultUrl(
        entry.value,
        draft: draft,
        key: entry.key.toString(),
      );
      if (found != null) return found;
    }
  }
  return null;
}
