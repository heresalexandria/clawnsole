import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'bfl_api.dart';
import 'models.dart';
import 'provider_catalog.dart';

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
      final hasReferences = categories.any(
        (value) => value.contains('IMAGE') || value.contains('REFERENCE'),
      );
      final readyModel = atlasProvider.models
          .where((candidate) => candidate.id == model)
          .firstOrNull;
      result.add(
        ProviderModelPrice(
          provider: 'atlas',
          model: model,
          label: item['displayName']?.toString() ?? model,
          usdPerSecond: rate,
          referenceUsdPerSecond: hasReferences ? rate : null,
          modes: <VideoMode>[
            if (categories.any((value) => value.contains('TEXT-TO-VIDEO')))
              VideoMode.t2v,
            if (hasReferences) VideoMode.i2v,
            if (categories.any((value) => value.contains('VIDEO-TO-VIDEO')))
              VideoMode.v2v,
          ],
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
      double tenSecondPrice;
      try {
        tenSecondPrice = await _calculatePrice(key, definition, 10);
      } on Object {
        enriched.add(price);
        continue;
      }
      final effectiveRate = tenSecondPrice / 10;
      final durationPrices = <int, double>{
        for (final seconds in durations)
          seconds: _roundPrice(effectiveRate * seconds),
      };
      enriched.add(
        ProviderModelPrice(
          provider: price.provider,
          model: price.model,
          label: price.label,
          usdPerSecond: effectiveRate,
          referenceUsdPerSecond: price.referenceUsdPerSecond == null
              ? null
              : effectiveRate,
          modes: price.modes,
          source: 'atlas-preflight · 720p',
          createReady: price.createReady,
          minDuration: price.minDuration,
          maxDuration: price.maxDuration,
          durationStep: price.durationStep,
          durationPrices: durationPrices,
          reference10SecondUsd: price.referenceUsdPerSecond == null
              ? null
              : tenSecondPrice,
        ),
      );
    }
    return enriched;
  }

  Future<double> _calculatePrice(
    String key,
    VideoModelDefinition model,
    int duration,
  ) async {
    final payload = <String, Object?>{
      'model': model.id,
      'prompt': 'Clawnsole pricing estimate',
      'duration': duration,
      'resolution': '720p',
      'ratio': model.modes.contains(VideoMode.t2v) ? '16:9' : 'adaptive',
      'generate_audio': model.supportsAudio,
      if (model.id.contains('/reference-to-video'))
        'reference_images': <String>[_pricingReferenceImage],
      if (model.id.contains('/image-to-video')) 'image': _pricingReferenceImage,
    };
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

  double _roundPrice(double value) => (value * 1000000).round() / 1000000;

  Future<Map<String, Object?>> submit(
    String key,
    String model,
    Map<String, Object?> input,
  ) async {
    final payload = generationPayload(
      model,
      await _uploadBinaryReferences(key, input),
    );
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
    final payload = <String, Object?>{
      'model': model,
      'prompt': input['prompt']?.toString() ?? '',
      'duration': duration == 'auto' ? -1 : duration,
      'resolution': switch (input['resolution']) {
        'sd' => '480p',
        'fhd' => '1080p',
        'qhd' => '1440p-SR',
        '4k' => '4k',
        _ => '720p',
      },
      'ratio': input['aspect_ratio'] == 'auto'
          ? 'adaptive'
          : input['aspect_ratio']?.toString() ?? '16:9',
      'generate_audio': input['generate_audio'] != false,
    };
    if (model.contains('/reference-to-video')) {
      final images = referenceImages.isEmpty ? frames : referenceImages;
      if (images.isNotEmpty) payload['reference_images'] = images;
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
      if (frames.isNotEmpty) payload['image'] = frames.first;
      if (frames.length > 1) payload['last_image'] = frames.last;
    }
    return payload;
  }

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
