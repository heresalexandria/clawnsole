import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'bfl_api.dart';
import 'models.dart';
import 'provider_catalog.dart';
import 'reference_prompts.dart';

class RunwayApi {
  RunwayApi({http.Client? client, Uri? baseUrl, Uri? modelGuideUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? Uri.parse('https://api.dev.runwayml.com'),
      _modelGuideUrl =
          modelGuideUrl ??
          Uri.parse('https://docs.dev.runwayml.com/guides/models/');

  static const String apiVersion = '2024-11-06';

  final http.Client _client;
  final Uri _baseUrl;
  final Uri _modelGuideUrl;
  int _uploadSequence = 0;

  Map<String, String> _headers(String key, {bool json = false}) =>
      <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $key',
        'X-Runway-Version': apiVersion,
        if (json) 'Content-Type': 'application/json',
      };

  Future<ProviderAccountStatus> verify(String key) async {
    final body = await _read(
      await _request(
        _client.get(
          _baseUrl.resolve('/v1/organization'),
          headers: _headers(key),
        ),
        'check your organization and credit balance',
      ),
    );
    final balance = body is Map<String, Object?> ? body['creditBalance'] : null;
    if (balance is! num) {
      throw const ProviderException(
        'Runway returned an invalid credit balance.',
        status: 502,
      );
    }
    return ProviderAccountStatus(
      provider: 'runway',
      balance: balance.toDouble(),
      currency: 'credits',
    );
  }

  /// Runway does not publish a list-model API. This reads the first-party
  /// model guide and merges newly documented video ids into the audited local
  /// rate card. Unknown routes stay visible in the cost desk but are not made
  /// create-ready until their request shape, limits, and price are known.
  Future<List<ProviderModelPrice>> listVideoModels() async {
    final published = publishedProviderPrices('runway');
    try {
      final response = await _request(
        _client.get(
          _modelGuideUrl,
          headers: const <String, String>{'Accept': 'text/html'},
        ),
        'refresh the model guide',
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return published;
      }
      final ids = _videoModelIds(response.body);
      final known = published
          .map((item) => item.model.split(':').first)
          .toSet();
      final discovered = ids
          .where((id) => !known.contains(id))
          .map(
            (id) => ProviderModelPrice(
              provider: 'runway',
              model: id,
              label: _humanizeModelId(id),
              usdPerSecond: 0,
              modes: const <VideoMode>[],
              source:
                  'New in Runway’s live model guide · awaiting audited limits and pricing',
              createReady: false,
              pricingUnit: 'catalog-unpriced',
            ),
          );
      return <ProviderModelPrice>[...published, ...discovered];
    } on Object {
      return published;
    }
  }

  Future<Map<String, Object?>> submit(
    String key,
    String model,
    Map<String, Object?> input,
  ) async {
    final mode = input['mode']?.toString() ?? 't2v';
    final frames = await _prepareFrames(key, input['keyframes']);
    final images = await _prepareSources(key, input['reference_images']);
    final videos = await _prepareSources(key, input['reference_videos']);
    final audios = await _prepareSources(key, input['reference_audios']);
    final source = mode == 'v2v'
        ? await _prepareSource(key, input['start_video'])
        : null;
    final prompt = _prompt(
      model,
      input['prompt']?.toString() ?? '',
      images: images.length,
      videos: videos.length,
      audios: audios.length,
      names: referencePromptNamesFromInput(input),
    );

    late final String endpoint;
    late final Map<String, Object?> payload;
    if (model == 'magnific_video_upscaler_creative') {
      final upscaleSource = await _prepareSource(key, input['input_video']);
      if (upscaleSource == null || upscaleSource.isEmpty) {
        throw const ProviderException(
          'Runway needs a source video to upscale.',
          status: 400,
        );
      }
      endpoint = '/v1/video_upscale';
      payload = <String, Object?>{
        'model': model,
        'videoUri': upscaleSource,
        'resolution': switch (input['resolution']) {
          'fhd' => '1k',
          'qhd' => '2k',
          '4k' => '4k',
          _ => '720p',
        },
        'creativity':
            (input['creativity'] as num?)?.toInt().clamp(0, 100) ?? 50,
        'flavor': 'natural',
      };
    } else if (mode == 'v2v') {
      if (source == null || source.isEmpty) {
        throw const ProviderException(
          'Runway needs a source video for this route.',
          status: 400,
        );
      }
      if (model == 'act_two') {
        final characterImages = images;
        final characterVideos = videos;
        if (characterImages.length + characterVideos.length != 1) {
          throw const ProviderException(
            'Act-Two needs exactly one character image or video.',
            status: 400,
          );
        }
        endpoint = '/v1/character_performance';
        payload = <String, Object?>{
          'model': model,
          'reference': <String, Object?>{'type': 'video', 'uri': source},
          'character': characterImages.isNotEmpty
              ? <String, Object?>{
                  'type': 'image',
                  'uri': characterImages.single,
                }
              : <String, Object?>{
                  'type': 'video',
                  'uri': characterVideos.single,
                },
          'ratio': _pixelRatio(input, resolution: 'hd'),
          if (input['seed'] is num) 'seed': input['seed'],
        };
      } else if (model == 'aleph2') {
        endpoint = '/v1/video_to_video';
        payload = <String, Object?>{
          'model': model,
          'videoUri': source,
          if (prompt.isNotEmpty) 'promptText': prompt,
          if (frames.isNotEmpty)
            'keyframes': frames
                .map(
                  (frame) => <String, Object?>{
                    'seconds': frame.seconds,
                    'uri': frame.uri,
                  },
                )
                .toList(),
          if (input['aspect_ratio'] != 'auto')
            'targetAspectRatio': input['aspect_ratio'],
          if (input['seed'] is num) 'seed': input['seed'],
        };
      } else if (model == 'gemini_omni_flash') {
        endpoint = '/v1/video_to_video';
        payload = <String, Object?>{
          'model': model,
          'videoUri': source,
          'promptText': prompt,
          if (images.isNotEmpty)
            'references': images
                .map((uri) => <String, Object?>{'uri': uri})
                .toList(),
        };
      } else {
        endpoint = '/v1/video_to_video';
        payload = _multimodalPayload(
          model,
          input,
          prompt: prompt,
          images: images,
          videos: videos,
          audios: audios,
          promptVideo: source,
        );
      }
    } else if (mode == 'i2v') {
      final frameUris = frames.map((frame) => frame.uri).toList();
      // Creative-reference requests use the text endpoint; pinned first/last
      // frames use the image endpoint. Runway documents them as distinct
      // shapes for the multimodal models.
      final creativeReferences =
          frameUris.isEmpty &&
          (images.isNotEmpty || videos.isNotEmpty || audios.isNotEmpty) &&
          const <String>{
            'seedance2_5',
            'seedance2',
            'seedance2_fast',
            'seedance2_mini',
            'hailuo3',
            'grok_imagine_1_5',
          }.contains(model);
      if (creativeReferences) {
        endpoint = '/v1/text_to_video';
        payload = _multimodalPayload(
          model,
          input,
          prompt: prompt,
          images: images,
          videos: videos,
          audios: audios,
        );
      } else {
        endpoint = '/v1/image_to_video';
        final guidance = frameUris.isNotEmpty ? frameUris : images;
        if (guidance.isEmpty) {
          throw const ProviderException(
            'Runway needs at least one image for this route.',
            status: 400,
          );
        }
        payload = _imagePayload(
          model,
          input,
          prompt: prompt,
          images: guidance,
          audios: audios,
        );
      }
    } else {
      endpoint = '/v1/text_to_video';
      payload = _multimodalPayload(
        model,
        input,
        prompt: prompt,
        images: images,
        videos: videos,
        audios: audios,
      );
    }

    final body = await _read(
      await _request(
        _client.post(
          _baseUrl.resolve(endpoint),
          headers: _headers(key, json: true),
          body: jsonEncode(payload),
        ),
        'submit the generation',
      ),
    );
    if (body is! Map<String, Object?> || body['id'] is! String) {
      throw const ProviderException(
        'Runway returned an invalid generation receipt.',
        status: 502,
      );
    }
    final id = body['id']! as String;
    return <String, Object?>{
      ...body,
      'polling_url': _baseUrl.resolve('/v1/tasks/$id').toString(),
      if (_credits(body['estimatedCost']) case final credits?)
        'estimated_credits': credits,
    };
  }

  Future<Map<String, Object?>> poll(String key, String pollingUrl) async {
    final url = _validatedPollingUrl(pollingUrl);
    final body = await _read(
      await _request(
        _client.get(url, headers: _headers(key)),
        'check the generation status',
      ),
    );
    if (body is! Map<String, Object?>) {
      throw const ProviderException(
        'Runway returned an invalid generation status.',
        status: 502,
      );
    }
    final cost = _credits(body['cost']);
    return <String, Object?>{
      ...body,
      if (body['output'] case final List<Object?> output) 'outputs': output,
      if (cost != null) 'actual_cost': cost,
      if (body['failure'] != null) 'error': body['failure'],
    };
  }

  Map<String, Object?> _multimodalPayload(
    String model,
    Map<String, Object?> input, {
    required String prompt,
    required List<String> images,
    required List<String> videos,
    required List<String> audios,
    String? promptVideo,
  }) {
    final payload = <String, Object?>{
      'model': model,
      if (prompt.isNotEmpty || model != 'seedance2_5') 'promptText': prompt,
      if (promptVideo != null) 'promptVideo': promptVideo,
      if (model.startsWith('seedance'))
        'audio': input['generate_audio'] != false,
      if (model == 'veo3.1' || model == 'veo3.1_fast')
        'audio': input['generate_audio'] != false,
      if (input['duration'] is num) 'duration': input['duration'],
      if (images.isNotEmpty)
        'references': images
            .map((uri) => <String, Object?>{'uri': uri})
            .toList(),
      if (videos.isNotEmpty)
        'referenceVideos': videos
            .map((uri) => <String, Object?>{'type': 'video', 'uri': uri})
            .toList(),
      if (audios.isNotEmpty)
        'referenceAudio': audios
            .map((uri) => <String, Object?>{'type': 'audio', 'uri': uri})
            .toList(),
    };
    _addOutputGeometry(payload, model, input, imageRoute: false);
    return payload;
  }

  Map<String, Object?> _imagePayload(
    String model,
    Map<String, Object?> input, {
    required String prompt,
    required List<String> images,
    required List<String> audios,
  }) {
    final supportsLast = const <String>{
      'seedance2_5',
      'seedance2',
      'seedance2_fast',
      'seedance2_mini',
      'veo3.1',
      'veo3.1_fast',
    }.contains(model);
    final promptImage = images.length == 1
        ? images.single
        : images.indexed
              .map(
                (entry) => <String, Object?>{
                  'uri': entry.$2,
                  'position': entry.$1 == 0 || !supportsLast ? 'first' : 'last',
                },
              )
              .toList();
    final payload = <String, Object?>{
      'model': model,
      'promptImage': promptImage,
      if (prompt.isNotEmpty || model == 'gen4.5' || model == 'hailuo3')
        'promptText': prompt,
      if (model.startsWith('seedance') ||
          model == 'veo3.1' ||
          model == 'veo3.1_fast')
        'audio': input['generate_audio'] != false,
      if (input['duration'] is num) 'duration': input['duration'],
      if (audios.isNotEmpty)
        'referenceAudio': audios
            .map((uri) => <String, Object?>{'type': 'audio', 'uri': uri})
            .toList(),
      if (input['seed'] is num && (model == 'gen4.5' || model == 'gen4_turbo'))
        'seed': input['seed'],
    };
    _addOutputGeometry(payload, model, input, imageRoute: true);
    return payload;
  }

  void _addOutputGeometry(
    Map<String, Object?> payload,
    String model,
    Map<String, Object?> input, {
    required bool imageRoute,
  }) {
    final resolution = input['resolution']?.toString() ?? 'hd';
    if (model == 'hailuo3') {
      payload['ratio'] = input['aspect_ratio'] == 'auto'
          ? imageRoute
                ? 'adaptive'
                : '16:9'
          : input['aspect_ratio'];
      payload['resolution'] = resolution == 'qhd' ? '2K' : '768P';
      return;
    }
    if (model == 'grok_imagine_1_5') {
      payload['resolution'] = _resolutionLabel(resolution);
      if (!imageRoute) payload['ratio'] = input['aspect_ratio'];
      return;
    }
    if (model == 'happyhorse_1_0' && imageRoute) {
      payload['resolution'] = resolution == 'fhd' ? '1080P' : '720P';
      return;
    }
    payload['ratio'] = _pixelRatio(input, resolution: resolution, model: model);
  }

  String _pixelRatio(
    Map<String, Object?> input, {
    required String resolution,
    String? model,
  }) {
    final ratio = input['aspect_ratio']?.toString() ?? '16:9';
    if (model == 'seedance2_5') {
      return _dimensionRatio(
        resolution,
        ratio,
        sdLandscape: '854:480',
        sdPortrait: '480:854',
      );
    }
    if (model != null && model.startsWith('seedance')) {
      return _dimensionRatio(
        resolution,
        ratio,
        sdLandscape: '864:496',
        sdPortrait: '496:864',
      );
    }
    if (model == 'happyhorse_1_0') {
      const hd = <String, String>{
        '16:9': '1280:720',
        '9:16': '720:1280',
        '1:1': '960:960',
        '4:3': '1108:832',
        '3:4': '832:1108',
      };
      const fhd = <String, String>{
        '16:9': '1920:1080',
        '9:16': '1080:1920',
        '1:1': '1440:1440',
        '4:3': '1662:1248',
        '3:4': '1248:1662',
      };
      return (resolution == 'fhd' ? fhd : hd)[ratio] ??
          (resolution == 'fhd' ? '1920:1080' : '1280:720');
    }
    if (resolution == 'fhd') return ratio == '9:16' ? '1080:1920' : '1920:1080';
    const hd = <String, String>{
      '21:9': '1584:672',
      '16:9': '1280:720',
      '4:3': '1104:832',
      '1:1': '960:960',
      '3:4': '832:1104',
      '9:16': '720:1280',
    };
    return hd[ratio] ?? '1280:720';
  }

  String _dimensionRatio(
    String resolution,
    String ratio, {
    required String sdLandscape,
    required String sdPortrait,
  }) {
    final tiers = <String, Map<String, String>>{
      'sd': <String, String>{
        '21:9': '992:432',
        '16:9': sdLandscape,
        '4:3': '752:560',
        '1:1': '640:640',
        '3:4': '560:752',
        '9:16': sdPortrait,
      },
      'hd': const <String, String>{
        '21:9': '1470:630',
        '16:9': '1280:720',
        '4:3': '1112:834',
        '1:1': '960:960',
        '3:4': '834:1112',
        '9:16': '720:1280',
      },
      'fhd': const <String, String>{
        '21:9': '2206:946',
        '16:9': '1920:1080',
        '4:3': '1664:1248',
        '1:1': '1440:1440',
        '3:4': '1248:1664',
        '9:16': '1080:1920',
      },
      '4k': const <String, String>{
        '21:9': '3840:1646',
        '16:9': '3840:2160',
        '4:3': '3840:2880',
        '1:1': '3840:3840',
        '3:4': '2880:3840',
        '9:16': '2160:3840',
      },
    };
    return tiers[resolution]?[ratio] ??
        tiers[resolution]?['16:9'] ??
        '1280:720';
  }

  String _resolutionLabel(String resolution) => switch (resolution) {
    'sd' => '480p',
    'fhd' => '1080p',
    _ => '720p',
  };

  String _prompt(
    String model,
    String prompt, {
    required int images,
    required int videos,
    required int audios,
    required Map<MediaReferenceKind, List<String>> names,
  }) {
    final mentions = promptReferenceMentions(<MediaReferenceKind>[
      ...List<MediaReferenceKind>.filled(images, MediaReferenceKind.image),
      ...List<MediaReferenceKind>.filled(videos, MediaReferenceKind.video),
      ...List<MediaReferenceKind>.filled(audios, MediaReferenceKind.audio),
    ], names: names);
    if (model.startsWith('seedance')) {
      return translateReferencePrompt(
        prompt,
        dialect: ReferencePromptDialect.compactAt,
        available: mentions,
      );
    }
    if (model == 'grok_imagine_1_5') {
      var translated = prompt;
      for (final mention in mentions) {
        translated = translated.replaceAll(
          mention.canonical,
          '[${mention.kind.label} ${mention.number}]',
        );
      }
      return translated;
    }
    return translateReferencePrompt(
      prompt,
      dialect: ReferencePromptDialect.plainOrdinal,
      available: mentions,
    );
  }

  Future<List<_RunwayFrame>> _prepareFrames(String key, Object? value) async {
    final raw = value is List<Object?> ? value : const <Object?>[];
    final result = <_RunwayFrame>[];
    for (var index = 0; index < raw.length; index += 1) {
      final item = raw[index];
      final seconds = item is List<Object?> && item.isNotEmpty
          ? (item.first as num?)?.toDouble() ?? index.toDouble()
          : index.toDouble();
      final source = item is List<Object?> && item.length > 1
          ? item[1]?.toString() ?? ''
          : item?.toString() ?? '';
      final uri = await _prepareSource(key, source);
      if (uri != null && uri.isNotEmpty) {
        result.add(_RunwayFrame(seconds: seconds, uri: uri));
      }
    }
    return result;
  }

  Future<List<String>> _prepareSources(String key, Object? value) async {
    final raw = value is List<Object?> ? value : const <Object?>[];
    final result = <String>[];
    for (final item in raw) {
      final source = await _prepareSource(key, item);
      if (source != null && source.isNotEmpty) result.add(source);
    }
    return result;
  }

  Future<String?> _prepareSource(String key, Object? value) async {
    final source = value?.toString().trim() ?? '';
    if (source.isEmpty) return null;
    if (!source.startsWith('data:')) return source;
    final comma = source.indexOf(',');
    if (comma < 0 || !source.substring(0, comma).contains(';base64')) {
      throw const ProviderException(
        'A Runway media upload is malformed.',
        status: 400,
      );
    }
    final contentType = source.substring(5, source.indexOf(';')).trim();
    late final Uint8List bytes;
    try {
      bytes = base64Decode(source.substring(comma + 1));
    } on FormatException {
      throw const ProviderException(
        'A Runway media upload contains invalid base64 data.',
        status: 400,
      );
    }
    return _upload(key, bytes, contentType);
  }

  Future<String> _upload(
    String key,
    Uint8List bytes,
    String contentType,
  ) async {
    final filename =
        'clawnsole-${++_uploadSequence}.${_extensionFor(contentType)}';
    final placeholder = await _read(
      await _request(
        _client.post(
          _baseUrl.resolve('/v1/uploads'),
          headers: _headers(key, json: true),
          body: jsonEncode(<String, Object?>{
            'filename': filename,
            'type': 'ephemeral',
          }),
        ),
        'prepare a media upload',
      ),
    );
    if (placeholder is! Map<String, Object?> ||
        placeholder['uploadUrl'] is! String ||
        placeholder['runwayUri'] is! String ||
        placeholder['fields'] is! Map<Object?, Object?>) {
      throw const ProviderException(
        'Runway returned an invalid upload receipt.',
        status: 502,
      );
    }
    final uploadUrl = validatedProviderUrl(placeholder['uploadUrl']! as String);
    final request = http.MultipartRequest('POST', uploadUrl);
    for (final entry
        in (placeholder['fields']! as Map<Object?, Object?>).entries) {
      request.fields[entry.key.toString()] = entry.value.toString();
    }
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );
    late final http.StreamedResponse response;
    try {
      response = await _client
          .send(request)
          .timeout(const Duration(seconds: 60));
    } on TimeoutException {
      throw const ProviderException(
        'Runway did not respond while Clawnsole uploaded media.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final details = await response.stream.bytesToString();
      throw ProviderException(
        'Runway’s media storage rejected the upload.',
        status: response.statusCode,
        details: details,
      );
    }
    await response.stream.drain<void>();
    return placeholder['runwayUri']! as String;
  }

  String _extensionFor(String contentType) => switch (contentType) {
    'image/jpeg' => 'jpg',
    'image/webp' => 'webp',
    'image/gif' => 'gif',
    'video/quicktime' => 'mov',
    'video/webm' => 'webm',
    'audio/mpeg' => 'mp3',
    'audio/wav' || 'audio/x-wav' => 'wav',
    'audio/mp4' => 'm4a',
    _ when contentType.startsWith('image/') => 'png',
    _ when contentType.startsWith('audio/') => 'wav',
    _ => 'mp4',
  };

  Uri _validatedPollingUrl(String value) {
    final url = Uri.tryParse(value);
    if (url == null ||
        url.scheme != _baseUrl.scheme ||
        url.host != _baseUrl.host ||
        url.port != _baseUrl.port ||
        !RegExp(r'^/v1/tasks/[^/]+$').hasMatch(url.path)) {
      throw const ProviderException(
        'The Runway status URL is invalid.',
        status: 400,
      );
    }
    return url;
  }

  Future<http.Response> _request(
    Future<http.Response> request,
    String operation,
  ) async {
    try {
      return await request.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw ProviderException(
        'Runway did not respond while Clawnsole tried to $operation.',
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
      400 || 422 => 'Runway rejected these generation settings.',
      401 || 403 => 'Runway rejected this API key.',
      402 => 'This Runway organization does not have enough credits.',
      413 => 'A Runway media input is too large.',
      429 =>
        'Runway is at this organization’s request limit. Try again shortly.',
      500 ||
      502 ||
      503 ||
      504 => 'Runway is temporarily unavailable (HTTP ${response.statusCode}).',
      _ => 'Runway returned ${response.statusCode}.',
    };
    throw ProviderException(
      providerNamedFailureMessage('Runway', payload, fallback: fallback),
      status: response.statusCode,
      details: payload,
    );
  }
}

class _RunwayFrame {
  const _RunwayFrame({required this.seconds, required this.uri});

  final double seconds;
  final String uri;
}

double? _credits(Object? value) {
  if (value is num) return value.toDouble();
  if (value is Map<Object?, Object?>) {
    final credits = value['credits'];
    if (credits is num) return credits.toDouble();
  }
  return null;
}

Set<String> _videoModelIds(String html) {
  final start = html.indexOf('id="generate-video"');
  if (start < 0) return const <String>{};
  final end = html.indexOf('<h2 id=', start + 1);
  final section = html.substring(start, end < 0 ? html.length : end);
  final row = RegExp(
    r'<tr[^>]*>\s*<td[^>]*>.*?<code[^>]*>([a-zA-Z0-9_.-]+)</code>.*?</td>\s*<td[^>]*>.*?</td>\s*<td[^>]*>.*?\bVideo\b.*?</td>',
    caseSensitive: false,
    dotAll: true,
  );
  return row.allMatches(section).map((match) => match.group(1)!).toSet();
}

String _humanizeModelId(String value) => value
    .split(RegExp(r'[_-]+'))
    .where((part) => part.isNotEmpty)
    .map(
      (part) => part.length <= 2 && int.tryParse(part) == null
          ? part.toUpperCase()
          : '${part[0].toUpperCase()}${part.substring(1)}',
    )
    .join(' ');
