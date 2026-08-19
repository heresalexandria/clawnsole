import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'bfl_api.dart';
import 'models.dart';
import 'reference_prompts.dart';

class LtxApi {
  LtxApi({http.Client? client, Uri? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? Uri.parse('https://api.ltx.io');

  final http.Client _client;
  final Uri _baseUrl;

  Map<String, String> _headers(String key, {bool json = false}) =>
      <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $key',
        if (json) 'Content-Type': 'application/json',
      };

  Future<ProviderAccountStatus> verify(String key) async {
    // LTX does not expose a balance endpoint. A deliberately unknown job is a
    // read-only credential probe: authenticated keys receive 404, bad keys 401.
    final response = await _request(
      _client.get(
        _baseUrl.resolve(
          '/v2/text-to-video/00000000-0000-0000-0000-000000000000',
        ),
        headers: _headers(key),
      ),
      'verify your API key',
    );
    if (response.statusCode != 404 &&
        (response.statusCode < 200 || response.statusCode >= 300)) {
      await _read(response);
    }
    return const ProviderAccountStatus(
      provider: 'ltx',
      balanceLabel: 'Open LTX Console to view balance ↗',
    );
  }

  Future<Map<String, Object?>> submit(
    String key,
    String model,
    Map<String, Object?> input,
  ) async {
    final mode = input['mode']?.toString();
    final frames = (input['keyframes'] as List<Object?>? ?? const <Object?>[])
        .map(_frameSource)
        .where((source) => source.isNotEmpty)
        .toList();
    final referenceImages =
        (input['reference_images'] as List<Object?>? ?? const <Object?>[])
            .map((item) => item?.toString() ?? '')
            .where((source) => source.isNotEmpty)
            .toList();
    final referenceAudios =
        (input['reference_audios'] as List<Object?>? ?? const <Object?>[])
            .map((item) => item?.toString() ?? '')
            .where((source) => source.isNotEmpty)
            .toList();
    final audioDriven = referenceAudios.isNotEmpty;
    final endpoint = audioDriven
        ? 'audio-to-video'
        : mode == 'i2v'
        ? 'image-to-video'
        : 'text-to-video';
    final duration = input['duration'];
    final prompt = translateReferencePrompt(
      input['prompt']?.toString() ?? '',
      dialect: ReferencePromptDialect.plainOrdinal,
      available: promptReferenceMentions(<MediaReferenceKind>[
        ...List<MediaReferenceKind>.filled(
          referenceImages.length,
          MediaReferenceKind.image,
        ),
        ...List<MediaReferenceKind>.filled(
          referenceAudios.length,
          MediaReferenceKind.audio,
        ),
      ]),
    );
    final payload = <String, Object?>{
      'model': model,
      'prompt': prompt,
      'duration': duration == 'auto' ? null : duration,
      'resolution': _resolution(
        input['resolution']?.toString() ?? 'hd',
        input['aspect_ratio']?.toString() ?? '16:9',
      ),
      'fps': 24,
      'generate_audio': input['generate_audio'] != false,
      if (audioDriven) 'audio_uri': referenceAudios.first,
      if (endpoint != 'text-to-video' &&
          (frames.isNotEmpty || referenceImages.isNotEmpty))
        'image_uri': frames.isNotEmpty ? frames.first : referenceImages.first,
      if (endpoint == 'image-to-video' && frames.length > 1)
        'last_frame_uri': frames.last,
    };
    final body = await _read(
      await _request(
        _client.post(
          _baseUrl.resolve('/v2/$endpoint'),
          headers: _headers(key, json: true),
          body: jsonEncode(payload),
        ),
        'submit the generation',
      ),
    );
    if (body is! Map<String, Object?> || body['id'] is! String) {
      throw const ProviderException(
        'LTX returned an invalid generation receipt.',
        status: 502,
      );
    }
    return <String, Object?>{
      ...body,
      'polling_url': _baseUrl.resolve('/v2/$endpoint/${body['id']}').toString(),
    };
  }

  Future<Map<String, Object?>> poll(String key, String pollingUrl) async {
    final body = await _read(
      await _request(
        _client.get(_validatedPollingUrl(pollingUrl), headers: _headers(key)),
        'check the generation status',
      ),
    );
    if (body is! Map<String, Object?>) {
      throw const ProviderException(
        'LTX returned an invalid generation status.',
        status: 502,
      );
    }
    return body;
  }

  Uri _validatedPollingUrl(String value) {
    final url = Uri.tryParse(value);
    if (url == null ||
        url.scheme != _baseUrl.scheme ||
        url.host != _baseUrl.host ||
        url.port != _baseUrl.port ||
        !RegExp(
          r'^/v2/(?:text|image|audio)-to-video/[^/]+$',
        ).hasMatch(url.path)) {
      throw const ProviderException(
        'The LTX status URL is invalid.',
        status: 400,
      );
    }
    return url;
  }

  String _resolution(String value, String ratio) {
    final landscape = switch (value) {
      'fhd' => '1920x1080',
      'qhd' => '2560x1440',
      '4k' => '3840x2160',
      _ => '1280x720',
    };
    if (ratio != '9:16') return landscape;
    final parts = landscape.split('x');
    return '${parts.last}x${parts.first}';
  }

  String _frameSource(Object? value) {
    if (value is String) return value;
    if (value is List<Object?> && value.length > 1) {
      return value[1]?.toString() ?? '';
    }
    return '';
  }

  Future<http.Response> _request(
    Future<http.Response> request,
    String operation,
  ) async {
    try {
      return await request.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw ProviderException(
        'LTX did not respond while Clawnsole tried to $operation.',
      );
    }
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
      401 || 403 => 'LTX rejected this API key.',
      402 => 'This LTX account does not have enough credits.',
      429 => 'LTX is busy. Try again shortly.',
      _ => 'LTX returned ${response.statusCode}.',
    };
    throw ProviderException(
      providerNamedFailureMessage('LTX', payload, fallback: fallback),
      status: response.statusCode,
      details: payload,
    );
  }
}
