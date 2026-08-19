import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'bfl_api.dart';
import 'models.dart';
import 'provider_catalog.dart';
import 'reference_prompts.dart';

class ArtCraftApi {
  ArtCraftApi({http.Client? client, Uri? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? Uri.parse('https://api.storyteller.ai');

  final http.Client _client;
  final Uri _baseUrl;

  static const _referenceOnlyModels = <String>{'seedance_2p5_preview'};
  static const _modelsWithoutEndFrames = <String>{
    'grok_imagine_video',
    'grok_imagine_video_1p5',
    'happy_horse_1p0',
    'veo_3_fast',
  };
  static const _modelsWithReferenceImages = <String>{
    'grok_imagine_video',
    'kling_1p6_pro',
    'minimax_h3',
    'seedance_2p0',
    'seedance_2p0_fast',
    'seedance_2p0_bp',
    'seedance_2p0_bp_fast',
    'seedance_2p0_bpu',
    'seedance_2p0_bpu_fast',
    'seedance_2p0_mini',
    'seedance_2p0_bp_mini',
    'seedance_2p0_bpu_mini',
    'seedance_2p5',
    'seedance_2p5_u',
    'seedance_2p5_preview',
    'veo_3p1',
    'veo_3p1_fast',
    'vidu_q3',
  };

  Map<String, String> _headers(String key, {bool json = false}) =>
      <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $key',
        if (json) 'Content-Type': 'application/json',
      };

  Future<ProviderAccountStatus> verify(String key) async {
    // ArtCraft does not expose an API-key wallet endpoint. "None" is a
    // deliberately unknown job token: an authenticated key receives 404,
    // while an invalid key is rejected before the lookup with 401.
    final response = await _request(
      _client.get(
        _baseUrl.resolve('/v1/omni_api/job_status/job/None'),
        headers: _headers(key),
      ),
      'verify your API key',
    );
    if (response.statusCode != 404 &&
        (response.statusCode < 200 || response.statusCode >= 300)) {
      await _read(response);
    }
    return const ProviderAccountStatus(
      provider: 'artcraft',
      currency: 'credits',
      balanceLabel: 'Connected · balance available in ArtCraft',
    );
  }

  Future<List<ProviderModelPrice>> listVideoModels() async {
    final body = await _read(
      await _request(
        _client.get(
          _baseUrl.resolve('/v1/omni_gen/models/video?provider=artcraft'),
          headers: const <String, String>{'Accept': 'application/json'},
        ),
        'load the model catalog',
      ),
    );
    if (body is! Map<String, Object?> || body['models'] is! List<Object?>) {
      throw ProviderException(
        'ArtCraft returned an invalid model catalog.',
        status: 502,
      );
    }

    final knownModels = <String, VideoModelDefinition>{
      for (final model in artCraftProvider.models) model.id: model,
    };
    final seen = <String>{};
    final models = <ProviderModelPrice>[];
    for (final raw
        in (body['models']! as List<Object?>)
            .whereType<Map<Object?, Object?>>()) {
      final item = raw.map((key, value) => MapEntry(key.toString(), value));
      final id = item['model']?.toString() ?? '';
      if (id.isEmpty || item['is_disabled'] == true || !seen.add(id)) continue;
      final known = knownModels[id];
      final modes = known?.modes ?? _catalogModes(item);
      final minDuration =
          known?.minDuration ?? (item['duration_seconds_min'] as num?)?.toInt();
      final maxDuration =
          known?.maxDuration ?? (item['duration_seconds_max'] as num?)?.toInt();
      models.add(
        ProviderModelPrice(
          provider: 'artcraft',
          model: id,
          canonicalModelId: known?.canonicalId ?? id,
          label: item['full_name']?.toString() ?? known?.label ?? id,
          usdPerSecond: known?.usdPerSecond ?? 0,
          referenceUsdPerSecond: modes.contains(VideoMode.i2v)
              ? known?.referenceUsdPerSecond ?? known?.usdPerSecond
              : null,
          modes: modes,
          source: known == null
              ? 'live catalog · not yet create-ready'
              : 'live catalog · published default rate',
          createReady: known != null,
          minDuration: minDuration,
          maxDuration: maxDuration,
          durationStep: known?.durationStep ?? 1,
          pricingUnit: known == null ? 'catalog-base' : 'per-second',
        ),
      );
    }
    return models;
  }

  Future<Map<String, Object?>> submit(
    String key,
    String model,
    Map<String, Object?> input,
  ) async {
    final payload = await _generationPayload(key, model, input);
    final cost = await _quote(payload);
    payload['idempotency_token'] = _uuid();
    final body = await _read(
      await _request(
        _client.post(
          _baseUrl.resolve('/v1/omni_api/generate/video'),
          headers: _headers(key, json: true),
          body: jsonEncode(payload),
        ),
        'submit the generation',
        timeout: const Duration(minutes: 4),
      ),
    );
    if (body is! Map<String, Object?> ||
        body['inference_job_token'] is! String) {
      throw const ProviderException(
        'ArtCraft returned an invalid generation receipt.',
        status: 502,
      );
    }
    final id = body['inference_job_token']! as String;
    return <String, Object?>{
      ...body,
      'id': id,
      'polling_url': _baseUrl
          .resolve('/v1/omni_api/job_status/job/$id')
          .toString(),
      if (cost != null) 'cost': cost,
    };
  }

  Future<Map<String, Object?>> poll(String key, String pollingUrl) async {
    final body = await _read(
      await _request(
        _client.get(_validatedPollingUrl(pollingUrl), headers: _headers(key)),
        'check the generation status',
      ),
    );
    if (body is! Map<String, Object?> ||
        body['state'] is! Map<Object?, Object?>) {
      throw const ProviderException(
        'ArtCraft returned an invalid generation status.',
        status: 502,
      );
    }
    final state = (body['state']! as Map<Object?, Object?>).map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final details = state['status'] is Map<Object?, Object?>
        ? (state['status']! as Map<Object?, Object?>).map(
            (key, value) => MapEntry(key.toString(), value),
          )
        : const <String, Object?>{};
    final rawStatus = details['status']?.toString() ?? '';
    final status = switch (rawStatus) {
      'complete_success' => 'Ready',
      'complete_failure' ||
      'dead' ||
      'cancelled_by_user' ||
      'cancelled_by_system' => 'Error',
      'pending' || 'started' || 'attempt_failed' => 'Pending',
      _ => rawStatus,
    };
    final failure = details['maybe_failure_category']?.toString();
    return <String, Object?>{
      ...body,
      'status': status,
      if (details['progress_percentage'] != null)
        'progress': details['progress_percentage'],
      if (state['maybe_result'] != null) 'result': state['maybe_result'],
      if (status == 'Error')
        'error': failure?.trim().isNotEmpty == true
            ? failure
            : 'ArtCraft reported $rawStatus for this generation.',
    };
  }

  Future<Map<String, Object?>> _generationPayload(
    String key,
    String model,
    Map<String, Object?> input,
  ) async {
    final frames = (input['keyframes'] as List<Object?>? ?? const <Object?>[])
        .map(_frameSource)
        .where((source) => source.isNotEmpty)
        .toList();
    final media = <_ArtCraftMediaSource>[];
    for (final frame in frames) {
      media.add(await _materialize(key, frame, MediaReferenceKind.image));
    }

    _ArtCraftMediaSource? start;
    _ArtCraftMediaSource? end;
    var references = <_ArtCraftMediaSource>[];
    if (_referenceOnlyModels.contains(model)) {
      references = media;
    } else if (media.isNotEmpty) {
      start = media.first;
      if (!_modelsWithoutEndFrames.contains(model) && media.length > 1) {
        end = media.last;
      }
      final referenceEnd = end == null ? media.length : media.length - 1;
      if (_modelsWithReferenceImages.contains(model) && referenceEnd > 1) {
        references = media.sublist(1, referenceEnd);
      }
    }
    final explicitImages = await _materializeAll(
      key,
      input['reference_images'],
      MediaReferenceKind.image,
    );
    references = await _normalizeReferenceGroup(key, <_ArtCraftMediaSource>[
      ...references,
      ...explicitImages,
    ], MediaReferenceKind.image);
    final referenceVideos = await _normalizeReferenceGroup(
      key,
      await _materializeAll(
        key,
        input['reference_videos'],
        MediaReferenceKind.video,
      ),
      MediaReferenceKind.video,
    );
    final referenceAudios = await _normalizeReferenceGroup(
      key,
      await _materializeAll(
        key,
        input['reference_audios'],
        MediaReferenceKind.audio,
      ),
      MediaReferenceKind.audio,
    );

    final duration = input['duration'];
    final modelDefinition = modelById('artcraft', model);
    final prompt = translateReferencePrompt(
      input['prompt']?.toString() ?? '',
      dialect: artCraftReferencePromptDialect(model),
      available: promptReferenceMentions(<MediaReferenceKind>[
        ...List<MediaReferenceKind>.filled(
          explicitImages.length,
          MediaReferenceKind.image,
        ),
        ...List<MediaReferenceKind>.filled(
          referenceVideos.length,
          MediaReferenceKind.video,
        ),
        ...List<MediaReferenceKind>.filled(
          referenceAudios.length,
          MediaReferenceKind.audio,
        ),
      ]),
    );
    return <String, Object?>{
      'model': model,
      'prompt': prompt,
      if (duration is num) 'duration_seconds': duration.toInt(),
      if (_aspectRatio(input['aspect_ratio']?.toString(), model) case final ar?)
        'aspect_ratio': ar,
      if (_resolution(input['resolution']?.toString()) case final resolution?)
        'resolution': resolution,
      if (modelDefinition.supportsAudio)
        'generate_audio': input['generate_audio'] != false,
      if (start?.url case final value?) 'start_frame_image_url': value,
      if (start?.token case final value?)
        'start_frame_image_media_token': value,
      if (end?.url case final value?) 'end_frame_image_url': value,
      if (end?.token case final value?) 'end_frame_image_media_token': value,
      if (references.isNotEmpty && references.first.url != null)
        'reference_image_urls': references.map((item) => item.url!).toList(),
      if (references.isNotEmpty && references.first.token != null)
        'reference_image_media_tokens': references
            .map((item) => item.token!)
            .toList(),
      if (referenceVideos.isNotEmpty && referenceVideos.first.url != null)
        'reference_video_urls': referenceVideos
            .map((item) => item.url!)
            .toList(),
      if (referenceVideos.isNotEmpty && referenceVideos.first.token != null)
        'reference_video_media_tokens': referenceVideos
            .map((item) => item.token!)
            .toList(),
      if (referenceAudios.isNotEmpty && referenceAudios.first.url != null)
        'reference_audio_urls': referenceAudios
            .map((item) => item.url!)
            .toList(),
      if (referenceAudios.isNotEmpty && referenceAudios.first.token != null)
        'reference_audio_media_tokens': referenceAudios
            .map((item) => item.token!)
            .toList(),
    };
  }

  Future<List<_ArtCraftMediaSource>> _materializeAll(
    String key,
    Object? raw,
    MediaReferenceKind kind,
  ) async {
    final result = <_ArtCraftMediaSource>[];
    for (final value in raw is List<Object?> ? raw : const <Object?>[]) {
      final source = value?.toString() ?? '';
      if (source.isNotEmpty) result.add(await _materialize(key, source, kind));
    }
    return result;
  }

  Future<double?> _quote(Map<String, Object?> payload) async {
    final body = await _read(
      await _request(
        _client.post(
          _baseUrl.resolve('/v1/omni_gen/cost/video'),
          headers: const <String, String>{
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(payload),
        ),
        'estimate the generation cost',
      ),
    );
    if (body is! Map<String, Object?>) return null;
    return (body['cost_in_credits'] as num?)?.toDouble();
  }

  Future<_ArtCraftMediaSource> _materialize(
    String key,
    String value,
    MediaReferenceKind kind,
  ) async {
    if (value.startsWith('https://')) {
      validatedProviderUrl(value);
      return _ArtCraftMediaSource(url: value);
    }
    final comma = value.indexOf(',');
    if (!value.startsWith('data:${kind.name}/') ||
        comma < 0 ||
        !value.substring(0, comma).contains(';base64')) {
      throw ProviderException(
        'ArtCraft reference ${kind.pluralLabel} must be uploads or public HTTPS URLs.',
        status: 400,
      );
    }
    Uint8List bytes;
    try {
      bytes = base64Decode(value.substring(comma + 1));
    } on FormatException {
      throw ProviderException(
        'An ArtCraft reference ${kind.label.toLowerCase()} is not valid base64 data.',
        status: 400,
      );
    }
    final mimeType = value.substring(5, value.indexOf(';'));
    return _ArtCraftMediaSource(
      token: await _uploadMedia(key, bytes, kind: kind, mimeType: mimeType),
    );
  }

  Future<List<_ArtCraftMediaSource>> _normalizeReferenceGroup(
    String key,
    List<_ArtCraftMediaSource> sources,
    MediaReferenceKind kind,
  ) async {
    if (sources.isEmpty ||
        sources.every((source) => source.url != null) ||
        sources.every((source) => source.token != null)) {
      return sources;
    }
    final normalized = <_ArtCraftMediaSource>[];
    for (final source in sources) {
      if (source.token != null) {
        normalized.add(source);
        continue;
      }
      final response = await _request(
        _client.get(validatedProviderUrl(source.url!)),
        'download a reference ${kind.label.toLowerCase()}',
        timeout: const Duration(minutes: 2),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ProviderException(
          'ArtCraft could not download mixed reference ${kind.pluralLabel}.',
          status: response.statusCode,
        );
      }
      normalized.add(
        _ArtCraftMediaSource(
          token: await _uploadMedia(
            key,
            response.bodyBytes,
            kind: kind,
            mimeType:
                response.headers['content-type'] ??
                switch (kind) {
                  MediaReferenceKind.image => 'image/jpeg',
                  MediaReferenceKind.video => 'video/mp4',
                  MediaReferenceKind.audio => 'audio/mpeg',
                },
          ),
        ),
      );
    }
    return normalized;
  }

  Future<String> _uploadMedia(
    String key,
    List<int> bytes, {
    required MediaReferenceKind kind,
    required String mimeType,
  }) async {
    final extension = switch (mimeType.split(';').first.toLowerCase()) {
      'image/png' => 'png',
      'image/gif' => 'gif',
      'image/webp' => 'webp',
      'video/quicktime' => 'mov',
      'video/mp4' => 'mp4',
      'audio/wav' || 'audio/x-wav' => 'wav',
      'audio/mpeg' => 'mp3',
      _ => 'jpg',
    };
    final request =
        http.MultipartRequest(
            'POST',
            _baseUrl.resolve('/v1/omni_api/upload/${kind.name}'),
          )
          ..headers.addAll(_headers(key))
          ..fields['uuid_idempotency_token'] = _uuid()
          ..files.add(
            http.MultipartFile.fromBytes(
              'file',
              bytes,
              filename: 'clawnsole-${kind.name}-reference.$extension',
            ),
          );
    final streamed = await _requestStreamed(
      _client.send(request),
      'upload a reference ${kind.label.toLowerCase()}',
    );
    final body = await _read(await http.Response.fromStream(streamed));
    if (body is! Map<String, Object?> || body['media_file_token'] is! String) {
      throw ProviderException(
        'ArtCraft returned an invalid ${kind.label.toLowerCase()} upload receipt.',
        status: 502,
      );
    }
    return body['media_file_token']! as String;
  }

  Uri _validatedPollingUrl(String value) {
    final url = Uri.tryParse(value);
    if (url == null ||
        url.scheme != _baseUrl.scheme ||
        url.host != _baseUrl.host ||
        url.port != _baseUrl.port ||
        !RegExp(r'^/v1/omni_api/job_status/job/[^/]+$').hasMatch(url.path)) {
      throw const ProviderException(
        'The ArtCraft status URL is invalid.',
        status: 400,
      );
    }
    return url;
  }

  String? _aspectRatio(String? value, String model) {
    if (model == 'veo_3_fast') return null;
    return switch (value) {
      'auto' => 'auto',
      '21:9' => 'wide_twenty_one_by_nine',
      '16:9' => 'wide_sixteen_by_nine',
      '4:3' => 'wide_four_by_three',
      '3:2' => 'wide_three_by_two',
      '1:1' => 'square',
      '2:3' => 'tall_two_by_three',
      '3:4' => 'tall_three_by_four',
      '9:16' => 'tall_nine_by_sixteen',
      _ => null,
    };
  }

  String? _resolution(String? value) => switch (value) {
    'sd' => 'four_eighty_p',
    'hd' => 'seven_twenty_p',
    'fhd' => 'ten_eighty_p',
    'qhd' => 'two_k',
    '4k' => 'four_k',
    _ => null,
  };

  String _frameSource(Object? value) {
    if (value is String) return value;
    if (value is List<Object?> && value.length > 1) {
      return value[1]?.toString() ?? '';
    }
    return '';
  }

  List<VideoMode> _catalogModes(Map<String, Object?> item) {
    final modes = <VideoMode>[];
    if (item['text_to_video_supported'] != false) modes.add(VideoMode.t2v);
    if (item['starting_keyframe_supported'] == true ||
        item['image_references_supported'] == true) {
      modes.add(VideoMode.i2v);
    }
    return modes;
  }

  Future<http.Response> _request(
    Future<http.Response> request,
    String operation, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      return await request.timeout(timeout);
    } on TimeoutException {
      throw ProviderException(
        'ArtCraft did not respond while Clawnsole tried to $operation.',
      );
    }
  }

  Future<http.StreamedResponse> _requestStreamed(
    Future<http.StreamedResponse> request,
    String operation,
  ) async {
    try {
      return await request.timeout(const Duration(minutes: 2));
    } on TimeoutException {
      throw ProviderException(
        'ArtCraft did not respond while Clawnsole tried to $operation.',
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
      401 || 403 => 'ArtCraft rejected this API key.',
      402 => 'This ArtCraft account does not have enough credits.',
      404 => 'ArtCraft could not find this generation.',
      429 => 'ArtCraft is busy. Try again shortly.',
      500 || 502 || 503 || 504 =>
        'ArtCraft is temporarily unavailable (HTTP ${response.statusCode}).',
      _ => 'ArtCraft returned ${response.statusCode}.',
    };
    throw ProviderException(
      providerNamedFailureMessage('ArtCraft', payload, fallback: fallback),
      status: response.statusCode,
      details: payload,
    );
  }

  String _uuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}

class _ArtCraftMediaSource {
  const _ArtCraftMediaSource({this.url, this.token});

  final String? url;
  final String? token;
}
