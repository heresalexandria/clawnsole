import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'prompt_rewrite.dart';

/// OpenAI Responses API client for AI Rewrite (`POST /v1/responses`,
/// `GET /v1/models`).
///
/// The key is a per-call argument so one instance serves every saved
/// credential. It only ever reaches the `Authorization` header: nothing here
/// logs it, and no failure message repeats it.
class OpenAiRewriteApi implements PromptRewriteApi {
  OpenAiRewriteApi({http.Client? client, Uri? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? Uri.parse('https://api.openai.com');

  /// Listing a catalog is cheap; a reasoning rewrite over several frames is
  /// not, so the two calls get their own ceilings.
  static const Duration listTimeout = Duration(seconds: 20);
  static const Duration rewriteTimeout = Duration(seconds: 90);

  /// A revised prompt plus one summary sentence never needs more, and the
  /// ceiling stops a runaway reasoning model from billing indefinitely.
  static const int maxOutputTokens = 4096;

  final http.Client _client;
  final Uri _baseUrl;

  Uri get baseUrl => _baseUrl;
  http.Client get client => _client;

  Map<String, String> _headers(String apiKey, {bool json = false}) =>
      <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $apiKey',
        if (json) 'Content-Type': 'application/json',
      };

  @override
  Future<List<RewriteModel>> listModels(String apiKey) async {
    final response = await _send(
      _client.get(_baseUrl.resolve('/v1/models'), headers: _headers(apiKey)),
      listTimeout,
      'list its models',
    );
    return openAiRewriteModelsFromListing(_rows(_read(response)['data']));
  }

  @override
  Future<PromptRewriteResult> rewrite(
    PromptRewriteRequest request,
    String apiKey,
  ) async {
    final response = await _send(
      _client.post(
        _baseUrl.resolve('/v1/responses'),
        headers: _headers(apiKey, json: true),
        body: jsonEncode(rewritePayload(request)),
      ),
      rewriteTimeout,
      'rewrite this prompt',
    );
    return _resultFrom(_read(response), request);
  }

  /// The exact `POST /v1/responses` body, so tests and anyone auditing what
  /// leaves the device can read it without a network call. It never carries
  /// the key.
  Map<String, Object?> rewritePayload(PromptRewriteRequest request) {
    final frames = request.frames;
    final content = <Map<String, Object?>>[
      for (
        var index = 0;
        index < frames.length;
        index++
      ) ...<Map<String, Object?>>[
        <String, Object?>{
          'type': 'input_text',
          'text': rewriteFrameLabel(
            index,
            frames.length,
            frames[index].seconds,
          ),
        },
        <String, Object?>{
          'type': 'input_image',
          'image_url':
              'data:${frames[index].mimeType};base64,'
              '${frames[index].base64Data}',
          'detail': 'auto',
        },
      ],
      <String, Object?>{
        'type': 'input_text',
        'text': buildRewriteBrief(request),
      },
    ];
    final effort = request.effort;
    return <String, Object?>{
      'model': request.modelId,
      'instructions': buildRewriteInstructions(request),
      'input': <Map<String, Object?>>[
        <String, Object?>{'role': 'user', 'content': content},
      ],
      'text': <String, Object?>{
        'format': <String, Object?>{
          'type': 'json_schema',
          'name': rewriteOutputSchemaName,
          'schema': rewriteOutputSchema,
          'strict': true,
        },
      },
      // Sending `reasoning` to a model that has none is a hard 400.
      if (effort != null && openAiReasoningModel(request.modelId))
        'reasoning': <String, Object?>{'effort': effort},
      'max_output_tokens': maxOutputTokens,
      // The prompt and the frames are the director's work, not training or
      // dashboard fodder.
      'store': false,
    };
  }

  PromptRewriteResult _resultFrom(
    Map<String, Object?> body,
    PromptRewriteRequest request,
  ) {
    final error = body['error'];
    if (error != null) {
      throw PromptRewriteException(
        _message(error) ?? 'OpenAI could not complete this rewrite.',
        failure: PromptRewriteFailure.other,
      );
    }
    final status = _text(body['status']);
    if (status == 'incomplete') {
      final reason = _text(_map(body['incomplete_details'])?['reason']);
      throw PromptRewriteException(
        reason == null
            ? 'OpenAI stopped before finishing the rewrite.'
            : 'OpenAI stopped before finishing the rewrite ($reason).',
        failure: PromptRewriteFailure.invalidResponse,
      );
    }
    if (status != 'completed') {
      throw PromptRewriteException(
        'OpenAI answered with status "${status ?? 'unknown'}".',
        failure: PromptRewriteFailure.other,
      );
    }
    final texts = StringBuffer();
    for (final item in _rows(body['output'])) {
      if (_text(item['type']) != 'message') continue;
      for (final part in _rows(item['content'])) {
        final type = _text(part['type']);
        if (type == 'refusal') {
          throw PromptRewriteException(
            _text(part['refusal']) ??
                _text(part['text']) ??
                'OpenAI declined to rewrite this prompt.',
            failure: PromptRewriteFailure.refused,
          );
        }
        // Written raw: trimming a part would close a gap the model meant to
        // leave when it split one payload across several.
        final text = part['text'];
        if (type == 'output_text' && text is String) texts.write(text);
      }
    }
    return parseRewriteOutput(
      texts.toString(),
      providerId: RewriteProvider.openai.id,
      modelId: _text(body['model']) ?? request.modelId,
    );
  }

  /// Awaits [request] under [timeout] and turns every transport failure into
  /// a [PromptRewriteFailure.network] exception. `TimeoutException`,
  /// `SocketException`, and `http.ClientException` all land here; catching
  /// broadly is what keeps `dart:io` out of a library the web renderer
  /// compiles.
  Future<http.Response> _send(
    Future<http.Response> request,
    Duration timeout,
    String operation,
  ) async {
    try {
      return await request.timeout(timeout);
    } on TimeoutException {
      throw PromptRewriteException(
        'OpenAI did not respond while Clawnsole tried to $operation.',
        failure: PromptRewriteFailure.network,
      );
    } on Object catch (error) {
      throw PromptRewriteException(
        'Clawnsole could not reach OpenAI to $operation (${_detail(error)}).',
        failure: PromptRewriteFailure.network,
      );
    }
  }

  Map<String, Object?> _read(http.Response response) {
    final body = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _statusFailure(response.statusCode, body);
    }
    if (body == null) {
      throw PromptRewriteException(
        'OpenAI returned an answer Clawnsole could not read.',
        failure: PromptRewriteFailure.invalidResponse,
        status: response.statusCode,
      );
    }
    return body;
  }

  PromptRewriteException _statusFailure(
    int status,
    Map<String, Object?>? body,
  ) {
    final vendor = _message(body?['error']);
    return switch (status) {
      // OpenAI's own 401 text quotes a masked key back, so this one message
      // is ours rather than the vendor's.
      401 || 403 => PromptRewriteException(
        'OpenAI rejected this API key.',
        failure: PromptRewriteFailure.unauthorized,
        status: status,
      ),
      402 => PromptRewriteException(
        vendor ?? 'This OpenAI account is out of quota.',
        failure: PromptRewriteFailure.rateLimited,
        status: status,
      ),
      429 => PromptRewriteException(
        vendor ?? 'OpenAI is rate limiting this key. Try again shortly.',
        failure: PromptRewriteFailure.rateLimited,
        status: status,
      ),
      400 || 404 || 422 => PromptRewriteException(
        vendor ?? 'OpenAI rejected this rewrite request.',
        failure: PromptRewriteFailure.badRequest,
        status: status,
      ),
      _ => PromptRewriteException(
        vendor ?? 'OpenAI returned $status.',
        failure: PromptRewriteFailure.other,
        status: status,
      ),
    };
  }
}

/// Whether [id] is a reasoning model, which is the same question as whether
/// it accepts `reasoning.effort`. `gpt-4*`, `chatgpt-*`, and everything else
/// reject the parameter outright.
bool openAiReasoningModel(String id) {
  final trimmed = id.trim();
  return trimmed.startsWith('gpt-5') || _openAiOSeries.hasMatch(trimmed);
}

/// Turns `GET /v1/models` rows into the picker's list: chat-capable ids only,
/// newest first, curated labels wherever Clawnsole knows a better one. Falls
/// back to the curated list when nothing survives the filter, so an account
/// with an unusual catalog still gets a working picker.
List<RewriteModel> openAiRewriteModelsFromListing(
  List<Map<String, Object?>> data,
) {
  final kept = <_Listed>[];
  for (var index = 0; index < data.length; index++) {
    final row = data[index];
    final id = _text(row['id']);
    if (id == null) continue;
    if (!id.startsWith('gpt-') && !_openAiOSeries.hasMatch(id)) continue;
    if (_openAiExcluded.any(id.contains)) continue;
    if (_openAiSnapshot.hasMatch(id)) continue;
    final created = row['created'];
    final createdAt = created is num
        ? DateTime.fromMillisecondsSinceEpoch(
            created.toInt() * 1000,
            isUtc: true,
          )
        : null;
    final reasoning = openAiReasoningModel(id);
    kept.add(
      _Listed(
        index: index,
        createdAt: createdAt,
        model: RewriteModel(
          id: id,
          label:
              RewriteProvider.openai.curatedModel(id)?.label ??
              rewriteModelLabel(id),
          supportsEffort: reasoning,
          supportsThinking: reasoning,
          createdAt: createdAt,
        ),
      ),
    );
  }
  if (kept.isEmpty) return RewriteProvider.openai.curatedModels;
  kept.sort(_Listed.newestFirst);
  return kept.map((entry) => entry.model).toList();
}

/// `o1`, `o3`, `o4-mini`: the o-series reasoning line.
final RegExp _openAiOSeries = RegExp(r'^o\d');

/// A dated snapshot such as `gpt-5.4-2026-04-11`. The undated alias is
/// already in the list and stays current, so the snapshots are noise.
final RegExp _openAiSnapshot = RegExp(r'-\d{4}-\d{2}-\d{2}$');

/// Ids that are not multimodal chat models, or are shaped and priced for
/// something other than rewriting a prompt.
const List<String> _openAiExcluded = <String>[
  'realtime',
  'transcribe',
  'tts',
  'audio',
  'whisper',
  'image',
  'search',
  'codex',
  'deep-research',
  'translate',
  'instruct',
  'moderation',
  'embedding',
  'chat-latest',
  '-pro',
  'computer-use',
];

class _Listed {
  const _Listed({
    required this.index,
    required this.createdAt,
    required this.model,
  });

  final int index;
  final DateTime? createdAt;
  final RewriteModel model;

  /// Newest first, undated last, listing order for ties.
  static int newestFirst(_Listed a, _Listed b) {
    final left = a.createdAt;
    final right = b.createdAt;
    if (left != null && right != null && left != right) {
      return right.compareTo(left);
    }
    if (left == null && right != null) return 1;
    if (left != null && right == null) return -1;
    return a.index.compareTo(b.index);
  }
}

Map<String, Object?>? _decode(String body) {
  if (body.trim().isEmpty) return null;
  try {
    final value = jsonDecode(body);
    if (value is Map<Object?, Object?>) {
      return value.map((key, child) => MapEntry(key.toString(), child));
    }
  } on FormatException {
    return null;
  }
  return null;
}

Map<String, Object?>? _map(Object? value) => value is Map<Object?, Object?>
    ? value.map((key, child) => MapEntry(key.toString(), child))
    : null;

List<Map<String, Object?>> _rows(Object? value) => <Map<String, Object?>>[
  if (value is List<Object?>)
    for (final child in value)
      if (_map(child) case final Map<String, Object?> row) row,
];

String? _text(Object? value) {
  if (value is! String) return null;
  final clean = value.trim();
  return clean.isEmpty ? null : clean;
}

/// The vendor's own sentence, which is what explains an unsupported model or
/// an effort level this model does not take.
String? _message(Object? error) {
  if (error is String) return _text(error);
  final map = _map(error);
  if (map == null) return null;
  return _text(map['message']) ?? _text(map['type']);
}

String _detail(Object error) =>
    _text(error is http.ClientException ? error.message : error.toString()) ??
    error.runtimeType.toString();
