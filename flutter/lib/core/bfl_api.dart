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
    Map<String, Object?> input, {
    String model = 'flux-3-video',
  }) async {
    final upscale = model == 'flux-tools-video-upscale-v1';
    final requestInput = Map<String, Object?>.from(input);
    if (upscale) {
      final video = requestInput['input_video'];
      if (video is String && video.startsWith('data:')) {
        final separator = video.indexOf(',');
        if (separator < 0) {
          throw const ProviderException(
            'The selected video is malformed.',
            status: 400,
          );
        }
        requestInput['input_video'] = video.substring(separator + 1);
      }
    }
    final payload = await _read(
      await _request(
        _client.post(
          _baseUrl.resolve(
            upscale ? '/v1/flux-tools/video-upscale-v1' : '/v1/flux-3-video',
          ),
          headers: _headers(apiKey, json: true),
          body: jsonEncode(requestInput),
        ),
        upscale ? 'submit the video upscale' : 'submit the generation',
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
      !isPublicProviderHost(host)) {
    throw const ProviderException('The provider URL is invalid.', status: 400);
  }
  return url;
}

/// Whether [host] can only name a public endpoint. Provider payloads decide
/// where media is fetched from, and the companion streams the response back,
/// so anything that could reach loopback, a private network, link-local or
/// cloud-metadata addresses — including the alternate spellings of loopback
/// (`127.1`, `2130706433`, `0x7f000001`, `[::ffff:127.0.0.1]`) — is refused.
bool isPublicProviderHost(String host) {
  final name = host.toLowerCase().trim();
  if (name.isEmpty) return false;
  if (name == 'localhost' ||
      name.endsWith('.localhost') ||
      name.endsWith('.local') ||
      name.endsWith('.internal') ||
      name.endsWith('.home.arpa') ||
      name == 'metadata' ||
      name == 'instance-data') {
    return false;
  }
  if (name.contains(':')) return _isPublicIpv6(name);
  // A host made only of digits, dots, or hex prefixes is an IPv4 literal in
  // one of its many encodings; anything but a public dotted quad is refused.
  if (RegExp(r'^[0-9a-fx.]+$').hasMatch(name) &&
      RegExp(r'^[0-9]').hasMatch(name)) {
    final octets = name.split('.');
    if (octets.length != 4) return false;
    final values = <int>[];
    for (final octet in octets) {
      if (!RegExp(r'^[0-9]{1,3}$').hasMatch(octet)) return false;
      final parsed = int.parse(octet);
      if (parsed > 255) return false;
      values.add(parsed);
    }
    return _isPublicIpv4(values);
  }
  return true;
}

bool _isPublicIpv4(List<int> o) {
  if (o[0] == 0 || o[0] == 10 || o[0] == 127) return false;
  if (o[0] == 100 && o[1] >= 64 && o[1] <= 127) return false;
  if (o[0] == 169 && o[1] == 254) return false;
  if (o[0] == 172 && o[1] >= 16 && o[1] <= 31) return false;
  if (o[0] == 192 && o[1] == 168) return false;
  if (o[0] == 192 && o[1] == 0 && (o[2] == 0 || o[2] == 2)) return false;
  if (o[0] == 198 && (o[1] == 18 || o[1] == 19)) return false;
  if (o[0] == 198 && o[1] == 51 && o[2] == 100) return false;
  if (o[0] == 203 && o[1] == 0 && o[2] == 113) return false;
  if (o[0] >= 224) return false;
  return true;
}

bool _isPublicIpv6(String address) {
  final normalized = address.replaceAll('[', '').replaceAll(']', '');
  if (normalized == '::' || normalized == '::1') return false;
  final mapped = RegExp(
    r'^::ffff:(\d+\.\d+\.\d+\.\d+)$',
  ).firstMatch(normalized);
  if (mapped != null) return isPublicProviderHost(mapped.group(1)!);
  if (normalized.startsWith('::ffff:')) return false;
  final head = normalized.split(':').first;
  if (head.isEmpty) return false;
  if (head.startsWith('fc') || head.startsWith('fd')) return false;
  if (head.startsWith('fe8') ||
      head.startsWith('fe9') ||
      head.startsWith('fea') ||
      head.startsWith('feb') ||
      head.startsWith('fec')) {
    return false;
  }
  if (head.startsWith('ff')) return false;
  return true;
}

double? normalizedProgress(Object? value) {
  final text = value is String ? value.trim() : null;
  final number = _progressNumber(value);
  if (number == null || !number.isFinite || number < 0) return null;
  final progress = text?.endsWith('%') == true
      ? number
      : number <= 1
      ? number * 100
      : number;
  return progress.toDouble().clamp(0, 100);
}

double? _progressNumber(Object? value) => switch (value) {
  num value when value.isFinite => value.toDouble(),
  String value => double.tryParse(
    value.trim().replaceFirst(RegExp(r'%$'), '').trim(),
  ),
  _ => null,
};

double? _normalizedPercentage(Object? value) {
  final number = _progressNumber(value);
  if (number == null || !number.isFinite || number < 0) return null;
  return number.clamp(0, 100).toDouble();
}

/// Finds a provider's reported completion percentage without tying the
/// generation contract to one provider's response envelope.
///
/// Providers currently return progress as numbers, numeric strings, and
/// percentage strings, using both snake_case and camelCase field names. Some
/// also nest the field below a status object. Only explicit progress field
/// names are considered so unrelated percentages cannot move the UI.
double? findProviderProgress(Object? payload) {
  final direct = normalizedProgress(payload);
  if (direct != null) return direct;

  if (payload is Map<Object?, Object?>) {
    for (final entry in payload.entries) {
      final key = entry.key.toString().toLowerCase().replaceAll(
        RegExp(r'[^a-z]'),
        '',
      );
      if (key == 'progress') {
        final found = findProviderProgress(entry.value);
        if (found != null) return found;
      } else if (const <String>{
        'progresspercentage',
        'progresspercent',
        'progresspct',
        'completionpercentage',
        'percentcomplete',
        'pct',
      }.contains(key)) {
        // Percentage-named fields use 0–100 semantics. Treating the numeric
        // value `1` as a fraction would incorrectly display 1% as complete.
        final found = _normalizedPercentage(entry.value);
        if (found != null) return found;
      }
    }
    for (final child in payload.values) {
      if (child is Map<Object?, Object?> || child is List<Object?>) {
        final found = findProviderProgress(child);
        if (found != null) return found;
      }
    }
  }
  if (payload is List<Object?>) {
    for (final child in payload) {
      if (child is Map<Object?, Object?> || child is List<Object?>) {
        final found = findProviderProgress(child);
        if (found != null) return found;
      }
    }
  }
  return null;
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
