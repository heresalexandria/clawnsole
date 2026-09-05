import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'provider_submission.dart';
import 'bfl_api.dart';
import 'models.dart';
import 'provider_catalog.dart';
import 'reference_prompts.dart';

/// Wire quirks for one Krea video route.
///
/// Krea normalizes most request fields across vendors — `prompt`,
/// `start_image`, `end_image`, `aspect_ratio`, `duration`, `resolution`,
/// `generate_audio`, `reference_*`, `seed` — so a spec only records which of
/// those a route accepts and how Clawnsole's neutral ids map onto the route's
/// accepted values.
class _KreaRouteSpec {
  const _KreaRouteSpec({
    this.resolutionValues = const <String, String>{},
    this.modeByResolution = const <String, String>{},
    this.aspectRatioValues = const <String, String>{},
    this.sendsAspectRatio = true,
    this.sendsDuration = true,
    this.sendsAudio = false,
    this.sendsSeed = false,
    this.sendsEndImage = false,
    this.sendsStartVideo = false,
    this.sendsImageReferences = false,
    this.sendsVideoReferences = false,
    this.sendsAudioReferences = false,
    this.dimensionsFromResolution = false,
  });

  /// Clawnsole resolution id → the route's `resolution` value. Empty when the
  /// route has no resolution field.
  final Map<String, String> resolutionValues;

  /// Clawnsole resolution id → the route's `mode` quality tier (Kling 3.0).
  final Map<String, String> modeByResolution;

  /// Clawnsole aspect-ratio id → the route's accepted value, for routes whose
  /// enum differs from the neutral ids ('auto' → 'adaptive', pixel ratios).
  final Map<String, String> aspectRatioValues;

  final bool sendsAspectRatio;
  final bool sendsDuration;
  final bool sendsAudio;
  final bool sendsSeed;
  final bool sendsEndImage;
  final bool sendsStartVideo;
  final bool sendsImageReferences;
  final bool sendsVideoReferences;
  final bool sendsAudioReferences;

  /// The route takes explicit `width`/`height` computed from the selected
  /// resolution tier and aspect ratio (Luma Ray 2).
  final bool dimensionsFromResolution;
}

const _seedanceSpec = _KreaRouteSpec(
  resolutionValues: <String, String>{
    'sd': '480p',
    'hd': '720p',
    'fhd': '1080p',
    '4k': '4k',
  },
  sendsAudio: true,
  sendsSeed: true,
  sendsEndImage: true,
  sendsImageReferences: true,
  sendsVideoReferences: true,
  sendsAudioReferences: true,
);

const _veoSpec = _KreaRouteSpec(
  resolutionValues: <String, String>{'hd': '720p', 'fhd': '1080p', '4k': '4K'},
  sendsAudio: true,
  sendsEndImage: true,
  sendsImageReferences: true,
);

const _hailuo23Spec = _KreaRouteSpec(
  resolutionValues: <String, String>{'hd': '768p', 'fhd': '1080p'},
  sendsAspectRatio: false,
  sendsEndImage: true,
);

const _ltxSpec = _KreaRouteSpec(
  resolutionValues: <String, String>{
    'hd': '720p',
    'fhd': '1080p',
    'qhd': '1440p',
    '4k': '4k',
  },
  sendsAudio: true,
  sendsEndImage: true,
);

const _kreaRouteSpecs = <String, _KreaRouteSpec>{
  'alibaba/wan-2.5': _KreaRouteSpec(
    resolutionValues: <String, String>{
      'sd': '480p',
      'hd': '720p',
      'fhd': '1080p',
    },
    sendsAudio: true,
    sendsSeed: true,
  ),
  'alibaba/wan-3.0': _KreaRouteSpec(
    resolutionValues: <String, String>{
      'sd': '480p',
      'hd': '720p',
      'fhd': '1080p',
    },
    aspectRatioValues: <String, String>{'auto': 'adaptive'},
    sendsAudio: true,
    sendsSeed: true,
    sendsEndImage: true,
    sendsImageReferences: true,
    sendsVideoReferences: true,
    sendsAudioReferences: true,
  ),
  'black-forest-labs/flux-3-video': _KreaRouteSpec(
    resolutionValues: <String, String>{'hd': '720p', 'fhd': '1080p'},
    sendsAudio: true,
    sendsEndImage: true,
    sendsStartVideo: true,
  ),
  'bytedance/seedance-2': _seedanceSpec,
  'bytedance/seedance-2-5': _seedanceSpec,
  'bytedance/seedance-2-fast': _seedanceSpec,
  'bytedance/seedance-2-mini': _seedanceSpec,
  'google/veo-3.1': _veoSpec,
  'google/veo-3.1-fast': _veoSpec,
  'google/veo-3.1-lite': _KreaRouteSpec(
    resolutionValues: <String, String>{'hd': '720p', 'fhd': '1080p'},
    sendsEndImage: true,
  ),
  'kling/kling-2.6': _KreaRouteSpec(sendsAudio: true, sendsEndImage: true),
  'kling/kling-3.0': _KreaRouteSpec(
    modeByResolution: <String, String>{'hd': 'std', 'fhd': 'pro', '4k': '4k'},
    sendsAudio: true,
    sendsEndImage: true,
  ),
  'kling/kling-o1': _KreaRouteSpec(sendsEndImage: true),
  'lightricks/ltx-video-2.5-fast': _ltxSpec,
  'lightricks/ltx-video-2.5-pro': _ltxSpec,
  'luma/ray-2': _KreaRouteSpec(
    sendsDuration: false,
    dimensionsFromResolution: true,
  ),
  'minimax/h3-max': _KreaRouteSpec(
    resolutionValues: <String, String>{'sd': '480p', 'hd': '768p'},
    sendsSeed: true,
    sendsEndImage: true,
  ),
  'minimax/hailuo-2.3': _hailuo23Spec,
  'minimax/hailuo-2.3-fast': _hailuo23Spec,
  'minimax/hailuo-3': _KreaRouteSpec(
    aspectRatioValues: <String, String>{'auto': 'adaptive'},
    sendsEndImage: true,
    sendsImageReferences: true,
    sendsVideoReferences: true,
    sendsAudioReferences: true,
  ),
  'runway/gen-4.5': _KreaRouteSpec(
    aspectRatioValues: <String, String>{
      '21:9': '1584:672',
      '16:9': '1280:720',
      '4:3': '1104:832',
      '1:1': '960:960',
      '3:4': '832:1104',
      '9:16': '720:1280',
      '9:21': '672:1584',
    },
    sendsSeed: true,
  ),
  'vidu/q3': _KreaRouteSpec(
    resolutionValues: <String, String>{
      'sd': '540p',
      'hd': '720p',
      'fhd': '1080p',
    },
    sendsAudio: true,
    sendsSeed: true,
  ),
  'xai/grok-video-1.5': _KreaRouteSpec(
    resolutionValues: <String, String>{
      'sd': '480p',
      'hd': '720p',
      'fhd': '1080p',
    },
    sendsStartVideo: true,
  ),
};

class KreaApi {
  KreaApi({http.Client? client, Uri? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? Uri.parse('https://api.krea.ai');

  final http.Client _client;
  final Uri _baseUrl;
  int _uploadSequence = 0;

  Map<String, String> _headers(String key, {bool json = false}) =>
      <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $key',
        if (json) 'Content-Type': 'application/json',
      };

  Future<ProviderAccountStatus> verify(String key) async {
    // Krea's public API does not expose a balance endpoint. A one-item job
    // listing is a read-only credential probe: valid keys receive 200 and
    // invalid keys 401/403.
    await _read(
      await _request(
        _client.get(
          _baseUrl
              .resolve('/jobs')
              .replace(queryParameters: const <String, String>{'limit': '1'}),
          headers: _headers(key),
        ),
        'verify your API key',
      ),
    );
    return const ProviderAccountStatus(
      provider: 'krea',
      balanceLabel: 'Open Krea to view usage ↗',
    );
  }

  /// Krea serves its own OpenAPI spec without authentication. This merges
  /// newly published video routes into the audited local rate card. Unknown
  /// routes stay visible in the cost desk but are not made create-ready until
  /// their request shape, limits, and price are known.
  Future<List<ProviderModelPrice>> listVideoModels() async {
    final published = publishedProviderPrices('krea');
    try {
      final response = await _request(
        _client.get(
          _baseUrl.resolve('/openapi.json'),
          headers: const <String, String>{'Accept': 'application/json'},
        ),
        'refresh the model catalog',
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return published;
      }
      final spec = jsonDecode(response.body);
      if (spec is! Map<Object?, Object?>) return published;
      final paths = spec['paths'];
      if (paths is! Map<Object?, Object?>) return published;
      final known = published
          .map((item) => item.model.split(':').first)
          .toSet();
      final discovered = <ProviderModelPrice>[];
      for (final entry in paths.entries) {
        final path = entry.key.toString();
        if (!path.startsWith('/generate/video/')) continue;
        final id = path.substring('/generate/video/'.length);
        if (id.isEmpty || known.contains(id)) continue;
        final post = entry.value is Map<Object?, Object?>
            ? (entry.value as Map<Object?, Object?>)['post']
            : null;
        final summary = post is Map<Object?, Object?>
            ? post['summary']?.toString()
            : null;
        discovered.add(
          ProviderModelPrice(
            provider: 'krea',
            model: id,
            label: summary?.trim().isNotEmpty == true
                ? summary!.trim()
                : _humanizeModelId(id),
            usdPerSecond: 0,
            modes: const <VideoMode>[],
            source: 'In Krea’s live API · awaiting audited limits and pricing',
            createReady: false,
            pricingUnit: 'catalog-unpriced',
          ),
        );
      }
      discovered.sort(
        (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
      );
      return <ProviderModelPrice>[...published, ...discovered];
    } on Object {
      return published;
    }
  }

  Future<Map<String, Object?>> submit(
    String key,
    String model,
    Map<String, Object?> input, {
    BeforeGenerationSend? beforeSend,
  }) async {
    final spec = _kreaRouteSpecs[model];
    if (spec == null) {
      throw ProviderException(
        'Krea route "$model" is not create-ready in this build.',
        status: 400,
      );
    }
    final mode = input['mode']?.toString() ?? 't2v';
    final frames = await _prepareSources(key, input['keyframes'], frames: true);
    final images = spec.sendsImageReferences
        ? await _prepareSources(key, input['reference_images'])
        : const <String>[];
    final videos = spec.sendsVideoReferences
        ? await _prepareSources(key, input['reference_videos'])
        : const <String>[];
    final audios = spec.sendsAudioReferences
        ? await _prepareSources(key, input['reference_audios'])
        : const <String>[];
    final source = mode == 'v2v' && spec.sendsStartVideo
        ? await _prepareSource(key, input['start_video'])
        : null;
    if (mode == 'v2v' && (source == null || source.isEmpty)) {
      throw const ProviderException(
        'Krea needs a source video for this route.',
        status: 400,
      );
    }
    final resolution = input['resolution']?.toString() ?? 'hd';
    final payload = <String, Object?>{
      'prompt': _prompt(
        model,
        input['prompt']?.toString() ?? '',
        images: images.length,
        videos: videos.length,
        audios: audios.length,
        names: referencePromptNamesFromInput(input),
      ),
      if (frames.isNotEmpty) 'start_image': frames.first,
      if (spec.sendsEndImage && frames.length > 1) 'end_image': frames[1],
      if (source != null && source.isNotEmpty) 'start_video': source,
      if (images.isNotEmpty) 'reference_images': images,
      if (videos.isNotEmpty) 'reference_videos': videos,
      if (audios.isNotEmpty) 'reference_audios': audios,
      if (spec.sendsDuration && input['duration'] is num)
        'duration': input['duration'],
      if (spec.resolutionValues[resolution] case final String value)
        'resolution': value,
      if (spec.modeByResolution[resolution] case final String value)
        'mode': value,
      if (spec.sendsAudio) 'generate_audio': input['generate_audio'] == true,
      if (spec.sendsSeed && input['seed'] is num) 'seed': input['seed'],
    };
    if (spec.sendsAspectRatio) {
      final ratio = input['aspect_ratio']?.toString() ?? '16:9';
      payload['aspect_ratio'] = spec.aspectRatioValues[ratio] ?? ratio;
    }
    if (spec.dimensionsFromResolution) {
      final (width, height) = _pixelDimensions(
        resolution,
        input['aspect_ratio']?.toString() ?? '16:9',
      );
      payload['width'] = width;
      payload['height'] = height;
    }

    final encodedPayload = jsonEncode(payload);
    await beforeSend?.call();
    final body = await _read(
      await _request(
        _client.post(
          _baseUrl.resolve('/generate/video/$model'),
          headers: _headers(key, json: true),
          body: encodedPayload,
        ),
        'submit the generation',
      ),
    );
    if (body is! Map<String, Object?> || body['job_id'] is! String) {
      throw const ProviderException(
        'Krea returned an invalid generation receipt.',
        status: 502,
      );
    }
    final id = body['job_id']! as String;
    return <String, Object?>{
      ...body,
      'id': id,
      'polling_url': _baseUrl.resolve('/jobs/$id').toString(),
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
        'Krea returned an invalid generation status.',
        status: 502,
      );
    }
    final outputs = _resultUrls(body['result']);
    return <String, Object?>{
      ...body,
      // Krea's early and mid-run states are provider-specific; map them onto
      // the queue/processing vocabulary the app normalizes.
      'status': switch (body['status']) {
        'backlogged' || 'scheduled' => 'queued',
        'sampling' || 'intermediate-complete' => 'processing',
        final Object? value => value,
      },
      if (outputs.isNotEmpty) 'outputs': outputs,
    };
  }

  List<String> _resultUrls(Object? result) {
    if (result is! Map<Object?, Object?>) return const <String>[];
    final urls = result['urls'];
    if (urls is List<Object?>) {
      final typed = urls.whereType<Map<Object?, Object?>>().toList();
      if (typed.isNotEmpty) {
        List<String> select(bool Function(Map<Object?, Object?>) test) => typed
            .where(test)
            .map((item) => item['url']?.toString() ?? '')
            .where((url) => url.isNotEmpty)
            .toList();
        final finals = select((item) => item['type'] == 'model');
        return finals.isNotEmpty ? finals : select((_) => true);
      }
      return urls.whereType<String>().where((url) => url.isNotEmpty).toList();
    }
    if (urls is Map<Object?, Object?>) {
      return urls.values
          .map((value) => value?.toString() ?? '')
          .where((url) => url.isNotEmpty)
          .toList();
    }
    return const <String>[];
  }

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
    return translateReferencePrompt(
      prompt,
      dialect: model.startsWith('bytedance/seedance')
          ? ReferencePromptDialect.compactAt
          : ReferencePromptDialect.plainOrdinal,
      available: mentions,
    );
  }

  /// Ray 2 takes explicit output dimensions instead of a resolution tier.
  (int, int) _pixelDimensions(String resolution, String ratio) {
    final base = switch (resolution) {
      'fhd' => 1080,
      'hd' => 720,
      _ => 540,
    };
    final parts = ratio.split(':');
    final across = double.tryParse(parts.first) ?? 16;
    final down = double.tryParse(parts.length > 1 ? parts.last : '') ?? 9;
    int clamped(double value) => value.round().clamp(540, 2520);
    return across >= down
        ? (clamped(base * across / down), clamped(base.toDouble()))
        : (clamped(base.toDouble()), clamped(base * down / across));
  }

  Future<List<String>> _prepareSources(
    String key,
    Object? value, {
    bool frames = false,
  }) async {
    final raw = value is List<Object?> ? value : const <Object?>[];
    final result = <String>[];
    for (final item in raw) {
      // Timed keyframes arrive as [seconds, source]; Krea routes only pin
      // first/last frames, so the timestamp is dropped.
      final entry = frames && item is List<Object?> && item.length > 1
          ? item[1]
          : item;
      final source = await _prepareSource(key, entry);
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
        'A Krea media upload is malformed.',
        status: 400,
      );
    }
    final contentType = source.substring(5, source.indexOf(';')).trim();
    late final Uint8List bytes;
    try {
      bytes = base64Decode(source.substring(comma + 1));
    } on FormatException {
      throw const ProviderException(
        'A Krea media upload contains invalid base64 data.',
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
    final request = http.MultipartRequest('POST', _baseUrl.resolve('/assets'))
      ..headers.addAll(_headers(key))
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename:
              'clawnsole-${++_uploadSequence}'
              '.${_extensionFor(contentType)}',
        ),
      );
    late final http.StreamedResponse streamed;
    try {
      streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 60));
    } on TimeoutException {
      throw const ProviderException(
        'Krea did not respond while Clawnsole uploaded media.',
      );
    }
    final body = await _read(await http.Response.fromStream(streamed));
    final url = body is Map<String, Object?>
        ? body['image_url']?.toString()
        : null;
    if (url == null || url.isEmpty) {
      throw const ProviderException(
        'Krea returned an invalid media upload receipt.',
        status: 502,
      );
    }
    return url;
  }

  String _extensionFor(String contentType) => switch (contentType) {
    'image/jpeg' => 'jpg',
    'image/webp' => 'webp',
    'image/heic' => 'heic',
    'video/quicktime' => 'mov',
    'video/webm' => 'webm',
    'audio/mpeg' => 'mp3',
    'audio/wav' || 'audio/x-wav' => 'wav',
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
        !RegExp(r'^/jobs/[^/]+$').hasMatch(url.path)) {
      throw const ProviderException(
        'The Krea status URL is invalid.',
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
        'Krea did not respond while Clawnsole tried to $operation.',
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
      400 || 422 => 'Krea rejected these generation settings.',
      401 || 403 => 'Krea rejected this API key.',
      402 => 'This Krea workspace does not have enough balance.',
      404 => 'Krea no longer recognizes this job.',
      413 => 'A Krea media input is too large.',
      429 => 'Krea is at this workspace’s request limit. Try again shortly.',
      500 ||
      502 ||
      503 ||
      504 => 'Krea is temporarily unavailable (HTTP ${response.statusCode}).',
      _ => 'Krea returned ${response.statusCode}.',
    };
    throw ProviderException(
      providerNamedFailureMessage('Krea', payload, fallback: fallback),
      status: response.statusCode,
      details: payload,
    );
  }
}

String _humanizeModelId(String value) => value
    .split(RegExp(r'[/_-]+'))
    .where((part) => part.isNotEmpty)
    .map(
      (part) => part.length <= 2 && int.tryParse(part) == null
          ? part.toUpperCase()
          : '${part[0].toUpperCase()}${part.substring(1)}',
    )
    .join(' ');
