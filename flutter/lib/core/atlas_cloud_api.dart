import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'bfl_api.dart';
import 'models.dart';
import 'provider_catalog.dart';
import 'reference_prompts.dart';

class AtlasCloudApi {
  AtlasCloudApi({http.Client? client, Uri? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? Uri.parse('https://api.atlascloud.ai');

  final http.Client _client;
  final Uri _baseUrl;

  static const _pricingReferenceImage =
      'data:image/png;base64,'
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

  Map<String, String> _headers(String key, {bool json = false}) =>
      <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $key',
        if (json) 'Content-Type': 'application/json',
      };

  Future<ProviderAccountStatus> verify(String key) async {
    final body = await _read(
      await _request(
        _client.get(
          _baseUrl.resolve('/public/v1/balance'),
          headers: _headers(key),
        ),
        'check your balance',
      ),
    );
    final map = _map(body);
    final available = map['available'];
    final value = available is Map<Object?, Object?>
        ? available['value']
        : map['balance'];
    final balance = value is num ? value.toDouble() : double.tryParse('$value');
    if (balance == null) {
      throw const ProviderException(
        'Atlas Cloud returned an invalid balance.',
        status: 502,
      );
    }
    return ProviderAccountStatus(
      provider: 'atlas',
      balance: balance,
      balanceLabel: '\$${balance.toStringAsFixed(2)} available',
    );
  }

  Future<List<ProviderModelPrice>> listVideoModels([String? key]) async {
    final body = await _read(
      await _request(
        _client.get(_baseUrl.resolve('/api/v1/models')),
        'load the model catalog',
      ),
    );
    final map = _map(body);
    final data = map['data'];
    if (data is! List<Object?>) {
      throw const ProviderException(
        'Atlas Cloud returned an invalid model catalog.',
        status: 502,
      );
    }
    final readyIds = atlasProvider.models.map((item) => item.id).toSet();
    final result = <ProviderModelPrice>[];
    for (final raw in data.whereType<Map<Object?, Object?>>()) {
      final item = raw.map((key, value) => MapEntry(key.toString(), value));
      if (item['type']?.toString().toLowerCase() != 'video') continue;
      final model = item['model']?.toString() ?? '';
      final price = item['price'];
      final actual = price is Map<Object?, Object?> ? price['actual'] : null;
      final base = actual is Map<Object?, Object?>
          ? actual['base_price']
          : null;
      final rate = base is num ? base.toDouble() : double.tryParse('$base');
      if (model.isEmpty || rate == null) continue;
      final categories = (item['categories'] as List<Object?>? ?? const [])
          .map((value) => value.toString().toUpperCase())
          .toList();
      final readyModel = atlasProvider.models
          .where((candidate) => candidate.id == model)
          .firstOrNull;
      final hasReferences =
          categories.any(
            (value) => value.contains('IMAGE') || value.contains('REFERENCE'),
          ) ||
          readyModel?.modes.contains(VideoMode.i2v) == true;
      final catalogModes = <VideoMode>[
        if (categories.any((value) => value.contains('TEXT-TO-VIDEO')))
          VideoMode.t2v,
        if (hasReferences) VideoMode.i2v,
        if (categories.any((value) => value.contains('VIDEO-TO-VIDEO')))
          VideoMode.v2v,
      ];
      result.add(
        ProviderModelPrice(
          provider: 'atlas',
          model: model,
          canonicalModelId: readyModel?.canonicalId ?? model,
          label: item['displayName']?.toString() ?? model,
          usdPerSecond: rate,
          referenceUsdPerSecond: hasReferences ? rate : null,
          modes: catalogModes.isEmpty
              ? readyModel?.modes ?? const <VideoMode>[]
              : catalogModes,
          source: 'atlas-live · base \$${rate.toStringAsFixed(3)}',
          createReady: readyIds.contains(model),
          minDuration: readyModel?.minDuration,
          maxDuration: readyModel?.maxDuration,
          durationStep: readyModel?.durationStep ?? 1,
          pricingUnit: 'catalog-base',
        ),
      );
    }
    result.sort((a, b) {
      if (a.createReady != b.createReady) return a.createReady ? -1 : 1;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
    return _withPreflightPrices(result, key?.trim() ?? '');
  }

  Future<List<ProviderModelPrice>> _withPreflightPrices(
    List<ProviderModelPrice> models,
    String key,
  ) async {
    final enriched = <ProviderModelPrice>[];
    for (final price in models) {
      final definition = atlasProvider.models
          .where((model) => model.id == price.model)
          .firstOrNull;
      if (definition == null) {
        enriched.add(price);
        continue;
      }
      final durations = <int>{
        definition.minDuration,
        definition.maxDuration,
        for (final seconds in const <int>[10, 15, 20, 30])
          if (seconds >= definition.minDuration &&
              seconds <= definition.maxDuration &&
              (seconds - definition.minDuration) % definition.durationStep == 0)
            seconds,
      }.toList()..sort();
      final durationPrices = <int, double>{};
      await Future.wait(
        durations.map((seconds) async {
          try {
            durationPrices[seconds] = await _calculatePrice(
              key,
              generationPayload(
                definition.id,
                _pricingInput(definition, seconds),
              ),
            );
          } on Object {
            // A route can remain visible with its catalog base price when
            // Atlas temporarily rejects a preflight configuration.
          }
        }),
      );
      if (durationPrices.isEmpty) {
        enriched.add(price);
        continue;
      }
      final referenceDuration = durationPrices.keys.reduce(
        (left, right) => left < right ? left : right,
      );
      final effectiveRate =
          durationPrices[referenceDuration]! / referenceDuration;
      enriched.add(
        ProviderModelPrice(
          provider: price.provider,
          model: price.model,
          canonicalModelId: price.canonicalId,
          label: price.label,
          usdPerSecond: effectiveRate,
          referenceUsdPerSecond: price.referenceUsdPerSecond == null
              ? null
              : effectiveRate,
          modes: price.modes,
          source: 'atlas-preflight · exact route quotes',
          createReady: price.createReady,
          minDuration: price.minDuration,
          maxDuration: price.maxDuration,
          durationStep: price.durationStep,
          durationPrices: durationPrices,
          reference10SecondUsd: price.referenceUsdPerSecond == null
              ? null
              : durationPrices[10],
          pricingUnit: 'per-route',
        ),
      );
    }
    return enriched;
  }

  Future<double> _calculatePrice(
    String key,
    Map<String, Object?> payload,
  ) async {
    final body = await _read(
      await _request(
        _client.post(
          _baseUrl.resolve('/api/v1/model/calculate'),
          headers: <String, String>{
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            if (key.isNotEmpty) 'Authorization': 'Bearer $key',
          },
          body: jsonEncode(payload),
        ),
        'calculate the generation price',
      ),
    );
    final envelope = _map(body);
    final data = _map(envelope['data']);
    final raw = data['price'];
    final price = raw is num ? raw.toDouble() : double.tryParse('$raw');
    if (price == null || !price.isFinite || price < 0) {
      throw const ProviderException(
        'Atlas Cloud returned an invalid price estimate.',
        status: 502,
      );
    }
    return price;
  }

  Map<String, Object?> _pricingInput(
    VideoModelDefinition model,
    int duration,
  ) => <String, Object?>{
    'prompt': 'Clawnsole pricing estimate',
    'duration': duration,
    'resolution': 'hd',
    'aspect_ratio': model.aspectRatios.contains('16:9') ? '16:9' : 'auto',
    'generate_audio': model.supportsAudio,
    if (model.id.contains('/reference-to-video'))
      'reference_images': <String>[_pricingReferenceImage]
    else if (model.modes.contains(VideoMode.i2v))
      'keyframes': <String>[_pricingReferenceImage],
  };

  Future<Map<String, Object?>> submit(
    String key,
    String model,
    Map<String, Object?> input,
  ) async {
    final payload = generationPayload(
      model,
      await _uploadBinaryReferences(key, input),
    );
    double? cost;
    try {
      cost = await _calculatePrice(key, payload);
    } on Object {
      // Pricing is advisory; a temporary quote failure must not block a render.
    }
    final body = await _read(
      await _request(
        _client.post(
          _baseUrl.resolve('/api/v1/model/generateVideo'),
          headers: _headers(key, json: true),
          body: jsonEncode(payload),
        ),
        'submit the generation',
      ),
    );
    final envelope = _map(body);
    final data = _map(envelope['data']);
    final id = data['id']?.toString();
    if (id == null || id.isEmpty) {
      throw const ProviderException(
        'Atlas Cloud returned an invalid generation receipt.',
        status: 502,
      );
    }
    return <String, Object?>{
      ...data,
      'id': id,
      if (cost != null) 'cost': cost,
      if (cost != null) 'cost_unit': 'usd',
      'polling_url': _baseUrl
          .resolve('/api/v1/model/prediction/$id')
          .toString(),
    };
  }

  Future<Map<String, Object?>> _uploadBinaryReferences(
    String key,
    Map<String, Object?> input,
  ) async {
    final prepared = Map<String, Object?>.from(input);
    for (final field in const <String>[
      'reference_videos',
      'reference_audios',
    ]) {
      final values = input[field] as List<Object?>?;
      if (values == null) continue;
      final uploaded = <String>[];
      for (final raw in values) {
        final source = raw?.toString() ?? '';
        uploaded.add(
          source.startsWith('data:') ? await _uploadMedia(key, source) : source,
        );
      }
      prepared[field] = uploaded;
    }
    return prepared;
  }

  Future<String> _uploadMedia(String key, String dataUrl) async {
    final comma = dataUrl.indexOf(',');
    if (comma < 0 || !dataUrl.substring(0, comma).contains(';base64')) {
      throw const ProviderException(
        'An Atlas Cloud media upload is malformed.',
        status: 400,
      );
    }
    final mimeType = dataUrl.substring(5, dataUrl.indexOf(';'));
    late final List<int> bytes;
    try {
      bytes = base64Decode(dataUrl.substring(comma + 1));
    } on FormatException {
      throw const ProviderException(
        'An Atlas Cloud media upload is not valid base64 data.',
        status: 400,
      );
    }
    final extension = switch (mimeType.toLowerCase()) {
      'video/quicktime' => 'mov',
      'video/mp4' => 'mp4',
      'audio/wav' || 'audio/x-wav' => 'wav',
      'audio/mpeg' => 'mp3',
      _ => 'bin',
    };
    final request =
        http.MultipartRequest(
            'POST',
            _baseUrl.resolve('/api/v1/model/uploadMedia'),
          )
          ..headers.addAll(_headers(key))
          ..files.add(
            http.MultipartFile.fromBytes(
              'file',
              bytes,
              filename: 'clawnsole-reference.$extension',
            ),
          );
    final streamed = await _requestStreamed(
      _client.send(request),
      'upload reference media',
    );
    final body = await _read(await http.Response.fromStream(streamed));
    final envelope = _map(body);
    final data = _map(envelope['data']);
    final url =
        envelope['url']?.toString() ??
        data['url']?.toString() ??
        data['download_url']?.toString();
    if (url == null || url.isEmpty) {
      throw const ProviderException(
        'Atlas Cloud returned an invalid media upload receipt.',
        status: 502,
      );
    }
    return url;
  }

  Future<Map<String, Object?>> poll(String key, String pollingUrl) async {
    final body = await _read(
      await _request(
        _client.get(_validatedPollingUrl(pollingUrl), headers: _headers(key)),
        'check the generation status',
      ),
    );
    final envelope = _map(body);
    return _map(envelope['data'] ?? envelope);
  }

  Uri _validatedPollingUrl(String value) {
    final url = Uri.tryParse(value);
    if (url == null ||
        url.scheme != _baseUrl.scheme ||
        url.host != _baseUrl.host ||
        url.port != _baseUrl.port ||
        !RegExp(r'^/api/v1/model/prediction/[^/]+$').hasMatch(url.path)) {
      throw const ProviderException(
        'The Atlas Cloud status URL is invalid.',
        status: 400,
      );
    }
    return url;
  }

  Map<String, Object?> generationPayload(
    String model,
    Map<String, Object?> input,
  ) {
    final frames = (input['keyframes'] as List<Object?>? ?? const <Object?>[])
        .map(_frameSource)
        .where((source) => source.isNotEmpty)
        .toList();
    final referenceImages =
        (input['reference_images'] as List<Object?>? ?? const <Object?>[])
            .map((item) => item?.toString() ?? '')
            .where((source) => source.isNotEmpty)
            .toList();
    final referenceVideos =
        (input['reference_videos'] as List<Object?>? ?? const <Object?>[])
            .map((item) => item?.toString() ?? '')
            .where((source) => source.isNotEmpty)
            .toList();
    final referenceAudios =
        (input['reference_audios'] as List<Object?>? ?? const <Object?>[])
            .map((item) => item?.toString() ?? '')
            .where((source) => source.isNotEmpty)
            .toList();
    final duration = input['duration'];
    final selectedDuration = duration == 'auto' ? -1 : duration;
    final aspectRatio = input['aspect_ratio']?.toString() ?? '16:9';
    final resolution = input['resolution']?.toString() ?? 'hd';
    final images = frames.isEmpty ? referenceImages : frames;
    final prompt = translateReferencePrompt(
      input['prompt']?.toString() ?? '',
      dialect: atlasReferencePromptDialect(model),
      available: promptReferenceMentions(<MediaReferenceKind>[
        ...List<MediaReferenceKind>.filled(
          referenceImages.length,
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
    final payload = <String, Object?>{
      'model': model,
      'prompt': prompt,
      'duration': selectedDuration,
    };

    if (model.startsWith('bytedance/seedance-')) {
      payload.addAll(<String, Object?>{
        'resolution': _lowerResolution(resolution, superResolution: true),
        'ratio': aspectRatio == 'auto' ? 'adaptive' : aspectRatio,
        'generate_audio': input['generate_audio'] != false,
      });
      if (model.contains('/reference-to-video')) {
        final references = referenceImages.isEmpty ? frames : referenceImages;
        if (references.isNotEmpty) payload['reference_images'] = references;
        if (referenceVideos.isNotEmpty) {
          payload['reference_videos'] = referenceVideos;
        }
        if (referenceAudios.isNotEmpty) {
          payload['reference_audios'] = referenceAudios;
        }
        if (model.contains('seedance-2.5/')) {
          final task = input['reference_task'];
          if (task is String) payload['omni_reference_task_type'] = task;
        }
      } else if (model.contains('/image-to-video')) {
        if (images.isNotEmpty) payload['image'] = images.first;
        if (images.length > 1) payload['last_image'] = images.last;
      }
      return payload;
    }

    if (model.startsWith('xai/grok-imagine-video')) {
      payload.addAll(<String, Object?>{
        'resolution': _lowerResolution(resolution),
        'aspect_ratio': aspectRatio == 'auto' ? '16:9' : aspectRatio,
      });
      if (model.contains('/image-to-video') && images.isNotEmpty) {
        payload['image_url'] = images.first;
      }
      return payload;
    }

    if (model.startsWith('google/veo3.1')) {
      payload.addAll(<String, Object?>{
        'resolution': _lowerResolution(resolution),
        'aspect_ratio': aspectRatio == 'auto' ? '16:9' : aspectRatio,
        'generate_audio': input['generate_audio'] != false,
      });
      if (model.contains('/image-to-video')) {
        if (images.isNotEmpty) payload['image'] = images.first;
        if (images.length > 1) payload['last_image'] = images.last;
      }
      return payload;
    }

    if (model.startsWith('alibaba/wan-2.7')) {
      final seed = input['seed'];
      payload.addAll(<String, Object?>{
        'resolution': _upperResolution(resolution, superResolution: true),
        'prompt_extend': true,
        'seed': seed is int ? seed : -1,
      });
      if (model.contains('/text-to-video')) {
        payload['ratio'] = aspectRatio == 'auto' ? '16:9' : aspectRatio;
      } else {
        if (images.isNotEmpty) payload['image'] = images.first;
        if (images.length > 1) payload['last_image'] = images.last;
      }
      return payload;
    }

    if (model.startsWith('kwaivgi/kling-')) {
      payload.addAll(<String, Object?>{
        'cfg_scale': .5,
        'sound': input['generate_audio'] != false,
      });
      if (model.contains('/text-to-video')) {
        payload['aspect_ratio'] = aspectRatio == 'auto' ? '16:9' : aspectRatio;
      } else {
        payload['resolution'] = _upperResolution(
          resolution,
          superResolution: true,
        );
        if (images.isNotEmpty) payload['image'] = images.first;
        if (images.length > 1) payload['end_image'] = images.last;
      }
      return payload;
    }

    if (model.startsWith('vidu/q3-')) {
      payload.addAll(<String, Object?>{
        'resolution': switch (resolution) {
          'sd' => '540p',
          'fhd' => '1080p',
          'qhd' => '1440p-sr',
          _ => '720p',
        },
        'generate_audio': input['generate_audio'] != false,
        'bgm': input['generate_audio'] != false,
        'movement_amplitude': 'auto',
      });
      if (model.contains('/text-to-video')) {
        payload['aspect_ratio'] = aspectRatio == 'auto' ? '4:3' : aspectRatio;
        payload['style'] = 'general';
      } else if (images.isNotEmpty) {
        payload['image'] = images.first;
      }
      return payload;
    }

    if (model.startsWith('pixverse/')) {
      payload.addAll(<String, Object?>{
        'quality': _lowerResolution(resolution),
        'sound': input['generate_audio'] != false,
      });
      if (model.contains('/text-to-video')) {
        payload['aspect_ratio'] = aspectRatio == 'auto' ? '16:9' : aspectRatio;
      } else if (images.isNotEmpty) {
        payload['image'] = images.first;
      }
      return payload;
    }

    if (model.startsWith('minimax/hailuo-2.3')) {
      payload['enable_prompt_expansion'] = model.contains('/t2v-');
      if (model.contains('/i2v-') && images.isNotEmpty) {
        payload['image'] = images.first;
      }
      return payload;
    }

    if (model.startsWith('black-forest-labs/flux-3')) {
      payload.addAll(<String, Object?>{
        'aspect_ratio': aspectRatio,
        'resolution': _lowerResolution(resolution),
        'generate_audio': input['generate_audio'] != false,
        'safety_tolerance': input['safety_tolerance'] ?? 2,
      });
      if (model.contains('/image-to-video') && images.isNotEmpty) {
        payload['image_url'] = images.first;
      }
      return payload;
    }

    payload.addAll(<String, Object?>{
      'resolution': _lowerResolution(resolution),
      'aspect_ratio': aspectRatio == 'auto' ? '16:9' : aspectRatio,
      'generate_audio': input['generate_audio'] != false,
    });
    if (model.contains('/reference-to-video')) {
      if (images.isNotEmpty) payload['reference_images'] = images;
      if (referenceVideos.isNotEmpty) {
        payload['reference_videos'] = referenceVideos;
      }
      if (referenceAudios.isNotEmpty) {
        payload['reference_audios'] = referenceAudios;
      }
    } else if (model.contains('/image-to-video')) {
      if (images.isNotEmpty) payload['image'] = images.first;
      if (images.length > 1) payload['last_image'] = images.last;
    }
    return payload;
  }

  String _lowerResolution(String value, {bool superResolution = false}) =>
      switch (value) {
        'sd' => '480p',
        'fhd' => '1080p',
        'qhd' => superResolution ? '1440p-SR' : '1440p',
        '4k' => '4k',
        _ => '720p',
      };

  String _upperResolution(String value, {bool superResolution = false}) =>
      switch (value) {
        'sd' => '480P',
        'fhd' => '1080P',
        'qhd' => superResolution ? '1440P-SR' : '1440P',
        '4k' => '4K',
        _ => '720P',
      };

  String _frameSource(Object? value) {
    if (value is String) return value;
    if (value is List<Object?> && value.length > 1) {
      return value[1]?.toString() ?? '';
    }
    return '';
  }

  Map<String, Object?> _map(Object? value) {
    if (value is! Map<Object?, Object?>) return <String, Object?>{};
    return value.map((key, child) => MapEntry(key.toString(), child));
  }

  Future<http.Response> _request(
    Future<http.Response> request,
    String operation,
  ) async {
    try {
      return await request.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw ProviderException(
        'Atlas Cloud did not respond while Clawnsole tried to $operation.',
      );
    }
  }

  Future<http.StreamedResponse> _requestStreamed(
    Future<http.StreamedResponse> request,
    String operation,
  ) async {
    try {
      return await request.timeout(const Duration(minutes: 4));
    } on TimeoutException {
      throw ProviderException(
        'Atlas Cloud did not respond while Clawnsole tried to $operation.',
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
      401 || 403 => 'Atlas Cloud rejected this API key.',
      402 => 'This Atlas Cloud account does not have enough credits.',
      429 => 'Atlas Cloud is busy. Try again shortly.',
      _ => 'Atlas Cloud returned ${response.statusCode}.',
    };
    throw ProviderException(
      providerNamedFailureMessage('Atlas Cloud', payload, fallback: fallback),
      status: response.statusCode,
      details: payload,
    );
  }
}
