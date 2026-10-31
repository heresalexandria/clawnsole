import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api_transcript.dart';
import 'bfl_api.dart';
import 'fal_catalog.dart';
import 'fal_model_contracts.dart';
import 'generation_status.dart';
import 'models.dart';
import 'provider_submission.dart';

/// fal's durable queue transport. The stored status URL contains everything
/// needed to resume a request; no process-local handle or provider key is saved.
class FalApi {
  FalApi({
    http.Client? client,
    Uri? baseUrl,
    Uri? platformBaseUrl,
    Uri? storageBaseUrl,
  }) : _rawClient = client ?? http.Client(),
       _baseUrl = baseUrl ?? Uri.parse('https://queue.fal.run'),
       _platformBaseUrl = platformBaseUrl ?? Uri.parse('https://api.fal.ai'),
       _storageBaseUrl = storageBaseUrl ?? Uri.parse('https://rest.fal.ai') {
    _client = recordingProviderClient(_rawClient);
  }

  final http.Client _rawClient;
  late final http.Client _client;
  final Uri _baseUrl;
  final Uri _platformBaseUrl;
  final Uri _storageBaseUrl;
  int _uploadSequence = 0;

  static const _verificationModel = 'blackforestlabs/flux-3-max/text-to-video';
  static const _maxSingleUploadBytes = 90 * 1024 * 1024;
  static final _segment = RegExp(r'^[A-Za-z0-9_-][A-Za-z0-9_.-]*$');
  static final _requestId = RegExp(r'^[A-Za-z0-9_-]{1,256}$');
  static final _userInfo = RegExp(r'^[^:/?#]+://[^/?#]*@');

  Future<ProviderAccountStatus> verify(String key) async {
    // The public model catalog accepts anonymous callers. Request listing
    // requires the normal API preset's models:requests:read permission and
    // performs no inference. Never record another request's history response.
    _read(
      await _send(
        'GET',
        _platformBaseUrl
            .resolve('/v1/models/requests/by-endpoint')
            .replace(
              queryParameters: const <String, String>{
                'endpoint_id': _verificationModel,
                'limit': '1',
              },
            ),
        key: key,
        record: false,
      ),
      key,
    );
    return const ProviderAccountStatus(
      provider: 'fal',
      balanceLabel: 'Open fal to view usage ↗',
    );
  }

  Future<List<ProviderModelPrice>> listVideoModels([String? key]) async {
    return falPublishedPrices();
  }

  Future<Map<String, Object?>> submit(
    String key,
    String model,
    Map<String, Object?> input, {
    BeforeGenerationSend? beforeSend,
  }) async {
    _validateKey(key);
    final spec = falRouteByModel(model);
    if (spec == null) {
      throw const ProviderException(
        'This fal model is not supported by this build.',
        status: 400,
      );
    }
    final segments = model.split('/');
    if (segments.length < 2 || !segments.every(_segment.hasMatch)) {
      throw const ProviderException(
        'The fal model route is invalid.',
        status: 400,
      );
    }
    // Validate and map before uploading anything. Only media present in the
    // final payload is uploaded, so stale settings cannot upload unused files.
    final payload = spec.buildPayload(input);
    final media = <String>{};
    void collect(Object? value) {
      if (value is String && value.isNotEmpty) media.add(value);
      if (value is List) {
        for (final child in value) {
          collect(child);
        }
      }
    }

    for (final field in const <String>[
      'keyframes',
      'start_video',
      'input_video',
      'reference_images',
      'reference_videos',
      'reference_audios',
    ]) {
      collect(input[field]);
    }
    final prepared = <String, String>{};
    Future<Object?> prepare(Object? value) async {
      if (value is String && media.contains(value)) {
        return prepared[value] ??= await _prepareSource(key, value);
      }
      if (value is List) {
        return <Object?>[for (final child in value) await prepare(child)];
      }
      if (value is Map) {
        return <String, Object?>{
          for (final entry in value.entries)
            entry.key.toString(): await prepare(entry.value),
        };
      }
      return value;
    }

    final encoded = jsonEncode(await prepare(payload));
    await beforeSend?.call();
    final receipt = _read(
      await _send('POST', _baseUrl.resolve('/$model'), key: key, body: encoded),
      key,
    );
    final id = receipt['request_id'];
    if (id is! String || !_requestId.hasMatch(id)) {
      throw const ProviderException(
        'fal returned an invalid generation receipt.',
        status: 502,
      );
    }
    final result = _baseUrl.resolve(
      '/${segments.take(2).join('/')}/requests/$id',
    );
    final status = result.replace(path: '${result.path}/status');
    // Validate convenience URLs before retaining any of them. Always store
    // the canonical owner/app URL, never the submission endpoint's subroute.
    _checkReturnedUrl(receipt['status_url'], status);
    _checkReturnedUrl(receipt['response_url'], result);
    return <String, Object?>{'id': id, 'polling_url': status.toString()};
  }

  Future<Map<String, Object?>> poll(String key, String pollingUrl) async {
    final statusUrl = _validatedStatusUrl(pollingUrl);
    final resultUrl = statusUrl.replace(
      path: statusUrl.path.substring(
        0,
        statusUrl.path.length - '/status'.length,
      ),
    );
    final id = statusUrl.pathSegments[3];
    final response = await _send('GET', statusUrl, key: key);
    if (response.statusCode == 404 || response.statusCode == 410) {
      return <String, Object?>{'id': id, 'status': 'Task not found'};
    }
    final status = _read(response, key);
    if (status['request_id'] != null && status['request_id'] != id) {
      throw const ProviderException(
        'fal returned a status for another request.',
        status: 502,
      );
    }
    _checkReturnedUrl(status['response_url'], resultUrl);
    if (status['status'] == 'IN_QUEUE') {
      return <String, Object?>{
        'id': id,
        'status': 'queued',
        if (status['queue_position'] is num)
          'queue_position': status['queue_position'],
      };
    }
    if (status['status'] == 'IN_PROGRESS') {
      return <String, Object?>{'id': id, 'status': 'processing'};
    }
    if (status['status'] != 'COMPLETED') {
      throw const ProviderException(
        'fal returned an unrecognized queue status.',
        status: 502,
      );
    }
    if (_hasError(status)) return _failure(id, status, key);
    final resultResponse = await ApiTranscriptScope.runPurpose(
      () => _send('GET', resultUrl, key: key),
      ApiRequestPurpose.result,
    );
    if (resultResponse.statusCode == 404 || resultResponse.statusCode == 410) {
      return <String, Object?>{'id': id, 'status': 'Task not found'};
    }
    final rawResult = _decode(resultResponse);
    if (resultResponse.statusCode == 422 ||
        (resultResponse.statusCode >= 400 &&
            resultResponse.statusCode != 401 &&
            resultResponse.statusCode != 403 &&
            resultResponse.statusCode != 429 &&
            rawResult is Map &&
            rawResult['error_type'] != null)) {
      return _failure(id, rawResult, key);
    }
    final result = _read(resultResponse, key);
    if (_hasError(result)) return _failure(id, result, key);
    final outputs = <String>[];
    void addVideo(Object? video) {
      final url = video is Map ? video['url'] : video;
      if (url is String && url.isNotEmpty) {
        outputs.add(validatedProviderUrl(url).toString());
      }
    }

    addVideo(result['video']);
    addVideo(result['video_url']);
    if (result['videos'] case final List videos) {
      for (final video in videos) {
        addVideo(video);
      }
    }
    if (outputs.isEmpty) {
      return <String, Object?>{
        'id': id,
        'status': 'Failed',
        'error': 'fal completed this request without a video output.',
      };
    }
    return <String, Object?>{
      'id': id,
      'status': 'Ready',
      'outputs': outputs.toSet().toList(),
    };
  }

  Future<String> _prepareSource(String key, String source) async {
    if (!source.startsWith('data:')) {
      return validatedProviderUrl(source).toString();
    }
    late final UriData data;
    try {
      data = UriData.parse(source);
      if (!data.isBase64 ||
          !RegExp(
            r'^(image|video|audio)/[A-Za-z0-9.+-]+$',
          ).hasMatch(data.mimeType)) {
        throw const FormatException();
      }
    } on FormatException {
      throw const ProviderException(
        'A fal media input is malformed.',
        status: 400,
      );
    }
    if (data.contentText.length > ((_maxSingleUploadBytes + 2) ~/ 3) * 4) {
      throw const ProviderException(
        'fal uploads in Clawnsole must be at most 90 MB. Use a hosted media URL for a larger file.',
        status: 413,
      );
    }
    late final Uint8List bytes;
    try {
      bytes = data.contentAsBytes();
    } on FormatException {
      throw const ProviderException(
        'A fal media input contains invalid base64 data.',
        status: 400,
      );
    }
    if (bytes.isEmpty || bytes.length > _maxSingleUploadBytes) {
      throw const ProviderException(
        'A fal media input is empty or exceeds the 90 MB upload limit.',
        status: 413,
      );
    }
    final receipt = _read(
      await _send(
        'POST',
        _storageBaseUrl
            .resolve('/storage/upload/initiate')
            .replace(
              queryParameters: const <String, String>{
                'storage_type': 'fal-cdn-v3',
              },
            ),
        key: key,
        record: false,
        body: jsonEncode(<String, Object?>{
          'content_type': data.mimeType,
          'file_name':
              'clawnsole-${++_uploadSequence}.${_extension(data.mimeType)}',
        }),
      ),
      key,
    );
    final uploadUrl = _cdnUrl(receipt['upload_url']);
    final fileUrl = _cdnUrl(receipt['file_url']);
    final upload = await _send(
      'PUT',
      uploadUrl,
      bytes: bytes,
      contentType: data.mimeType,
      timeout: const Duration(seconds: 90),
      // Presigned storage URLs authorize this operation. Never forward the
      // account key to a returned CDN URL, even when it belongs to fal.
      record: false,
    );
    if (upload.statusCode < 200 || upload.statusCode >= 300) {
      throw ProviderException(
        'fal could not store the media upload.',
        status: upload.statusCode,
      );
    }
    return fileUrl.toString();
  }

  Uri _cdnUrl(Object? value) {
    final url = value is String ? Uri.tryParse(value) : null;
    if (url == null ||
        url.scheme != 'https' ||
        _userInfo.hasMatch(value as String) ||
        url.hasFragment ||
        url.port != 443 ||
        !(url.host == 'fal.media' || url.host.endsWith('.fal.media'))) {
      throw const ProviderException(
        'fal returned an invalid storage URL.',
        status: 502,
      );
    }
    return url;
  }

  String _extension(String mime) => switch (mime) {
    'image/jpeg' => 'jpg',
    'video/quicktime' => 'mov',
    'audio/mpeg' => 'mp3',
    'audio/x-wav' => 'wav',
    _ => mime.split('/').last,
  };

  Uri _validatedStatusUrl(String value) {
    final url = Uri.tryParse(value);
    final parts = url?.pathSegments ?? const <String>[];
    if (url == null ||
        !_sameOrigin(url, _baseUrl) ||
        _userInfo.hasMatch(value) ||
        url.hasQuery ||
        url.hasFragment ||
        parts.length != 5 ||
        !_segment.hasMatch(parts[0]) ||
        !_segment.hasMatch(parts[1]) ||
        parts[2] != 'requests' ||
        !_requestId.hasMatch(parts[3]) ||
        parts[4] != 'status' ||
        url.path != '/${parts.join('/')}') {
      throw const ProviderException(
        'The fal status URL is invalid.',
        status: 400,
      );
    }
    return url;
  }

  bool _sameOrigin(Uri a, Uri b) =>
      a.scheme == b.scheme && a.host == b.host && a.port == b.port;

  void _checkReturnedUrl(Object? value, Uri expected) {
    if (value == null) return;
    final url = value is String ? Uri.tryParse(value) : null;
    if (url == null ||
        !_sameOrigin(url, expected) ||
        _userInfo.hasMatch(value as String) ||
        url.hasQuery ||
        url.hasFragment ||
        url.path != expected.path) {
      throw const ProviderException(
        'fal returned an invalid queue URL.',
        status: 502,
      );
    }
  }

  Future<http.Response> _send(
    String method,
    Uri url, {
    String? key,
    String? body,
    Uint8List? bytes,
    String? contentType,
    bool record = true,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (key != null) _validateKey(key);
    final request = http.Request(method, url)
      ..followRedirects = false
      ..headers.addAll(<String, String>{
        'Accept': 'application/json',
        if (key != null) 'Authorization': 'Key $key',
        if (body != null) 'Content-Type': 'application/json',
        if (contentType != null) 'Content-Type': contentType,
      });
    if (body != null) request.body = body;
    if (bytes != null) request.bodyBytes = bytes;
    Future<http.Response> send() async {
      final response = await (record ? _client : _rawClient).send(request);
      return http.Response.fromStream(response);
    }

    try {
      final scope = ApiTranscriptScope.current;
      // Header redaction alone cannot catch a provider or transport error
      // echoing the credential in its message. Scrub the exact active key
      // before the transcript sink ever receives that record.
      final response = record && key != null && scope != null
          ? ApiTranscriptScope.run(
              send,
              sink: _FalTranscriptSink(scope.sink, key),
              operationId: scope.operationId,
              provider: scope.provider,
              purpose: scope.purpose,
            )
          : send();
      return await response.timeout(timeout);
    } on TimeoutException {
      throw const ProviderException(
        'fal did not respond in time. Check the existing request before submitting again.',
      );
    } on http.ClientException {
      throw const ProviderException(
        'Clawnsole could not reach fal. Check the existing request before submitting again.',
      );
    }
  }

  void _validateKey(String key) {
    if (key.trim().isEmpty || key.contains(RegExp(r'[\r\n]'))) {
      throw const ProviderException(
        'Add a valid fal API key first.',
        status: 401,
      );
    }
  }

  Object? _decode(http.Response response) {
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return null;
    }
  }

  Map<String, Object?> _read(http.Response response, String key) {
    final body = _decode(response);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (body is Map<String, Object?>) return body;
      throw const ProviderException(
        'fal returned an invalid response.',
        status: 502,
      );
    }
    final fallback = switch (response.statusCode) {
      400 || 422 => 'fal rejected these generation settings.',
      401 || 403 => 'fal rejected this API key or its permissions.',
      402 => 'This fal account does not have enough balance.',
      404 => 'fal no longer recognizes this request.',
      413 => 'A fal media input is too large.',
      429 => 'fal is at this account’s request limit. Try again shortly.',
      >= 300 && < 400 => 'fal returned an unexpected redirect.',
      _ => 'fal returned HTTP ${response.statusCode}.',
    };
    final message = _message(body, key, fallback);
    throw ProviderException(
      message,
      status: response.statusCode >= 300 && response.statusCode < 400
          ? 502
          : response.statusCode,
      details: <String, Object?>{'error': message},
    );
  }

  bool _hasError(Map<String, Object?> body) =>
      body['error'] != null || body['error_type'] != null;

  Map<String, Object?> _failure(String id, Object? body, String key) {
    final types = <String>[];
    void collect(Object? value) {
      if (value is List) {
        for (final item in value) {
          collect(item);
        }
      }
      if (value is Map) {
        for (final name in const ['type', 'error_type']) {
          if (value[name] is String) types.add(value[name] as String);
        }
        collect(value['detail']);
        collect(value['error']);
      }
    }

    collect(body);
    return <String, Object?>{
      'id': id,
      'status': types.contains('content_policy_violation')
          ? 'Content Moderated'
          : types.contains('client_cancelled')
          ? 'Cancelled'
          : 'Failed',
      'error': _message(body, key, 'fal reported that this generation failed.'),
    };
  }

  String _message(Object? body, String key, String fallback) {
    String? find(Object? value) {
      if (value is String && value.trim().isNotEmpty) return value.trim();
      if (value is List) {
        for (final item in value) {
          final message = find(item);
          if (message != null) return message;
        }
      }
      if (value is Map) {
        for (final field in const ['msg', 'message', 'detail', 'error']) {
          final message = find(value[field]);
          if (message != null) return message;
        }
      }
      return null;
    }

    var message = find(body) ?? fallback;
    if (key.isNotEmpty) message = message.replaceAll(key, redactedValue);
    return sanitizeProviderDiagnosticValue(message) as String;
  }
}

class _FalTranscriptSink implements ApiTranscriptSink {
  _FalTranscriptSink(this.inner, this.key);

  final ApiTranscriptSink inner;
  final String key;

  @override
  void addApiRequest(ApiRequestRecord record) {
    Object? scrub(Object? value) {
      if (value is String) return value.replaceAll(key, redactedValue);
      if (value is List) return value.map(scrub).toList();
      if (value is Map) {
        return <String, Object?>{
          for (final entry in value.entries)
            entry.key.toString().replaceAll(key, redactedValue): scrub(
              entry.value,
            ),
        };
      }
      return value;
    }

    inner.addApiRequest(
      ApiRequestRecord.fromJson(
        scrub(record.toJson())! as Map<String, Object?>,
      ),
    );
  }
}
