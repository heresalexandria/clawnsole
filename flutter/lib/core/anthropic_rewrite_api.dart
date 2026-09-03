import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'prompt_rewrite.dart';

/// Anthropic Messages API client for AI Rewrite (`POST /v1/messages`,
/// `GET /v1/models`), spoken over plain HTTP because there is no Dart SDK.
///
/// The key is a per-call argument so one instance serves every saved
/// credential. It only ever reaches the `x-api-key` header: nothing here logs
/// it, and no failure message repeats it.
class AnthropicRewriteApi implements PromptRewriteApi {
  AnthropicRewriteApi({http.Client? client, Uri? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? Uri.parse('https://api.anthropic.com');

  static const String apiVersion = '2023-06-01';

  /// Sent only alongside a `fallbacks` body; an unrecognized beta header is
  /// an error in its own right.
  static const String fallbackBeta = 'server-side-fallback-2026-07-01';

  /// Listing a catalog is cheap; a rewrite that thinks over several frames is
  /// not, so the two calls get their own ceilings.
  static const Duration listTimeout = Duration(seconds: 20);
  static const Duration rewriteTimeout = Duration(seconds: 90);

  /// Adaptive thinking spends tokens before the answer, so the ceiling has to
  /// leave room for both. It is a ceiling, not a target.
  static const int maxTokens = 16000;

  final http.Client _client;
  final Uri _baseUrl;

  Uri get baseUrl => _baseUrl;
  http.Client get client => _client;

  Map<String, String> _headers(
    String apiKey, {
    bool json = false,
    bool fallbacks = false,
  }) => <String, String>{
    'x-api-key': apiKey,
    'anthropic-version': apiVersion,
    if (json) 'content-type': 'application/json',
    if (fallbacks) 'anthropic-beta': fallbackBeta,
  };

  @override
  Future<List<RewriteModel>> listModels(String apiKey) async {
    final response = await _send(
      _client.get(
        _baseUrl.resolve('/v1/models?limit=100'),
        headers: _headers(apiKey),
      ),
      listTimeout,
      'list its models',
    );
    return anthropicRewriteModelsFromListing(_rows(_read(response)['data']));
  }

  @override
  Future<PromptRewriteResult> rewrite(
    PromptRewriteRequest request,
    String apiKey,
  ) async {
    final response = await _post(request, apiKey, structured: true);
    // Structured output is newer than some deployments and some models.
    // Rather than fail the rewrite, ask again in prose: parseRewriteOutput
    // digs the JSON object out of whatever comes back.
    final answer = _rejectedStructuredOutput(response)
        ? await _post(request, apiKey, structured: false)
        : response;
    return _resultFrom(_read(answer, modelId: request.modelId), request);
  }

  Future<http.Response> _post(
    PromptRewriteRequest request,
    String apiKey, {
    required bool structured,
  }) {
    final payload = rewritePayload(request, structured: structured);
    return _send(
      _client.post(
        _baseUrl.resolve('/v1/messages'),
        headers: _headers(
          apiKey,
          json: true,
          fallbacks: payload.containsKey('fallbacks'),
        ),
        body: jsonEncode(payload),
      ),
      rewriteTimeout,
      'rewrite this prompt',
    );
  }

  /// The exact `POST /v1/messages` body, so tests and anyone auditing what
  /// leaves the device can read it without a network call. It never carries
  /// the key. Pass `structured: false` for the retry that drops
  /// `output_config.format` but keeps the effort level.
  Map<String, Object?> rewritePayload(
    PromptRewriteRequest request, {
    bool structured = true,
  }) {
    final traits = anthropicModelTraits(request.modelId);
    final frames = request.frames;
    final content = <Map<String, Object?>>[
      for (
        var index = 0;
        index < frames.length;
        index++
      ) ...<Map<String, Object?>>[
        <String, Object?>{
          'type': 'text',
          'text': rewriteFrameLabel(
            index,
            frames.length,
            frames[index].seconds,
          ),
        },
        <String, Object?>{
          'type': 'image',
          'source': <String, Object?>{
            'type': 'base64',
            'media_type': frames[index].mimeType,
            'data': frames[index].base64Data,
          },
        },
      ],
      <String, Object?>{'type': 'text', 'text': buildRewriteBrief(request)},
    ];
    final effort = traits.supportsEffort ? request.effort : null;
    final outputConfig = <String, Object?>{
      if (structured)
        'format': <String, Object?>{
          'type': 'json_schema',
          'schema': rewriteOutputSchema,
        },
      if (effort != null) 'effort': effort,
    };
    return <String, Object?>{
      'model': request.modelId,
      'max_tokens': maxTokens,
      'system': buildRewriteInstructions(request),
      'messages': <Map<String, Object?>>[
        <String, Object?>{'role': 'user', 'content': content},
      ],
      if (outputConfig.isNotEmpty) 'output_config': outputConfig,
      // Adaptive lets the model decide how long to think. A fixed
      // `budget_tokens` would either starve a hard rewrite or burn tokens on
      // an easy one, and sampling controls fight the effort setting.
      if (traits.supportsAdaptiveThinking)
        'thinking': <String, Object?>{'type': 'adaptive'},
      if (traits.wantsFallback) 'fallbacks': 'default',
    };
  }

  /// True when a 400 blames the structured-output fields, which is the one
  /// rejection worth retrying.
  bool _rejectedStructuredOutput(http.Response response) {
    if (response.statusCode != 400) return false;
    final message = _message(_decode(response.body)?['error'])?.toLowerCase();
    if (message == null) return false;
    return message.contains('output_config') || message.contains('format');
  }

  PromptRewriteResult _resultFrom(
    Map<String, Object?> body,
    PromptRewriteRequest request,
  ) {
    final stop = _text(body['stop_reason']);
    if (stop == 'refusal') {
      throw PromptRewriteException(
        _text(_map(body['stop_details'])?['explanation']) ??
            'The model declined to rewrite this prompt.',
        failure: PromptRewriteFailure.refused,
      );
    }
    if (stop == 'max_tokens') {
      throw const PromptRewriteException(
        'Claude ran out of room before it finished the rewrite.',
        failure: PromptRewriteFailure.invalidResponse,
      );
    }
    // Thinking and fallback blocks are bookkeeping; only text carries the
    // answer. Joined without a separator so a payload split across blocks
    // still parses.
    final texts = StringBuffer();
    for (final block in _rows(body['content'])) {
      final text = block['text'];
      if (_text(block['type']) == 'text' && text is String) texts.write(text);
    }
    return parseRewriteOutput(
      texts.toString(),
      providerId: RewriteProvider.anthropic.id,
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
        'Anthropic did not respond while Clawnsole tried to $operation.',
        failure: PromptRewriteFailure.network,
      );
    } on Object catch (error) {
      throw PromptRewriteException(
        'Clawnsole could not reach Anthropic to $operation '
        '(${_detail(error)}).',
        failure: PromptRewriteFailure.network,
      );
    }
  }

  Map<String, Object?> _read(http.Response response, {String? modelId}) {
    final body = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _statusFailure(response.statusCode, body, modelId);
    }
    if (body == null) {
      throw PromptRewriteException(
        'Anthropic returned an answer Clawnsole could not read.',
        failure: PromptRewriteFailure.invalidResponse,
        status: response.statusCode,
      );
    }
    return body;
  }

  PromptRewriteException _statusFailure(
    int status,
    Map<String, Object?>? body,
    String? modelId,
  ) {
    final error = _map(body?['error']);
    final vendor = _message(error);
    if (status == 404 && _text(error?['type']) == 'not_found_error') {
      return PromptRewriteException(
        modelId == null
            ? vendor ?? 'Anthropic could not find that resource.'
            : 'Anthropic has no model named "$modelId". Pick another model.'
                  '${vendor == null ? '' : ' $vendor'}',
        failure: PromptRewriteFailure.badRequest,
        status: status,
      );
    }
    return switch (status) {
      401 || 403 => PromptRewriteException(
        'Anthropic rejected this API key.',
        failure: PromptRewriteFailure.unauthorized,
        status: status,
      ),
      402 => PromptRewriteException(
        vendor ?? 'This Anthropic account is out of credit.',
        failure: PromptRewriteFailure.rateLimited,
        status: status,
      ),
      429 => PromptRewriteException(
        vendor ?? 'Anthropic is rate limiting this key. Try again shortly.',
        failure: PromptRewriteFailure.rateLimited,
        status: status,
      ),
      400 || 404 || 422 => PromptRewriteException(
        vendor ?? 'Anthropic rejected this rewrite request.',
        failure: PromptRewriteFailure.badRequest,
        status: status,
      ),
      _ => PromptRewriteException(
        vendor ?? 'Anthropic returned $status.',
        failure: PromptRewriteFailure.other,
        status: status,
      ),
    };
  }
}

/// What the Messages API will accept for one model id. Sending effort or
/// thinking to a model without them is a hard 400, so the request is built
/// from these rather than from hope.
class AnthropicModelTraits {
  const AnthropicModelTraits({
    required this.supportsEffort,
    required this.supportsAdaptiveThinking,
    required this.wantsFallback,
  });

  final bool supportsEffort;
  final bool supportsAdaptiveThinking;

  /// Whether to ask for a server-side fallback, so a busy frontier model
  /// degrades to a sibling instead of failing the rewrite.
  final bool wantsFallback;
}

/// Traits for [id]: the curated entry when Clawnsole ships one, otherwise the
/// family heuristics. Frontier Opus, Sonnet, Fable, and Mythos lines take
/// effort and adaptive thinking; Haiku, 4.5 and older, and unknown ids get
/// neither.
AnthropicModelTraits anthropicModelTraits(String id) {
  final trimmed = id.trim();
  final wantsFallback = _anthropicFallbackPrefixes.any(trimmed.startsWith);
  final curated = RewriteProvider.anthropic.curatedModel(trimmed);
  if (curated != null) {
    return AnthropicModelTraits(
      supportsEffort: curated.supportsEffort,
      supportsAdaptiveThinking: curated.supportsThinking,
      wantsFallback: wantsFallback,
    );
  }
  final frontier = _anthropicFrontier.hasMatch(trimmed);
  return AnthropicModelTraits(
    supportsEffort: frontier,
    supportsAdaptiveThinking: frontier,
    wantsFallback: wantsFallback,
  );
}

/// Turns `GET /v1/models` rows into the picker's list: image-capable Claude
/// ids only, newest first, capabilities believed over heuristics wherever the
/// listing states them. Falls back to the curated list when nothing survives
/// the filter, so an unusual catalog still gets a working picker.
List<RewriteModel> anthropicRewriteModelsFromListing(
  List<Map<String, Object?>> data,
) {
  final kept = <_Listed>[];
  for (var index = 0; index < data.length; index++) {
    final row = data[index];
    final id = _text(row['id']);
    if (id == null || !id.startsWith('claude-')) continue;
    final capabilities = _map(row['capabilities']);
    // A model that cannot read the frames cannot do this job.
    if (_map(capabilities?['image_input'])?['supported'] == false) continue;
    final traits = anthropicModelTraits(id);
    final effort = _map(capabilities?['effort']);
    final adaptive = _map(
      _map(_map(capabilities?['thinking'])?['types'])?['adaptive'],
    );
    final levels = <String>[
      if (effort != null)
        for (final level in RewriteProvider.anthropic.effortLevels)
          if (_offers(effort, level)) level,
    ];
    final createdAt = _time(row['created_at']);
    kept.add(
      _Listed(
        index: index,
        createdAt: createdAt,
        model: RewriteModel(
          id: id,
          label:
              _text(row['display_name']) ??
              RewriteProvider.anthropic.curatedModel(id)?.label ??
              rewriteModelLabel(id),
          supportsEffort: _flag(effort?['supported']) ?? traits.supportsEffort,
          supportsThinking:
              _flag(adaptive?['supported']) ?? traits.supportsAdaptiveThinking,
          effortLevels: levels.isEmpty ? null : levels,
          createdAt: createdAt,
        ),
      ),
    );
  }
  if (kept.isEmpty) return RewriteProvider.anthropic.curatedModels;
  kept.sort(_Listed.newestFirst);
  return kept.map((entry) => entry.model).toList();
}

/// Ids served with a server-side fallback.
const List<String> _anthropicFallbackPrefixes = <String>[
  'claude-fable',
  'claude-opus-5',
  'claude-mythos',
];

/// The families that take effort and adaptive thinking when the listing does
/// not say and Clawnsole ships no curated entry.
final RegExp _anthropicFrontier = RegExp(
  r'^claude-(fable|mythos)|^claude-opus-(4-[6-9]|5)|^claude-sonnet-(4-6|5)',
);

/// Whether the listing offers effort [level], reading either a bare boolean
/// leaf or a `{"supported": …}` leaf under `capabilities.effort`.
bool _offers(Map<String, Object?> effort, String level) {
  final value = effort[level];
  if (value == null) return false;
  if (value is bool) return value;
  return _map(value)?['supported'] != false;
}

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

bool? _flag(Object? value) => value is bool ? value : null;

DateTime? _time(Object? value) {
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(
      value.toInt() * 1000,
      isUtc: true,
    );
  }
  final text = _text(value);
  return text == null ? null : DateTime.tryParse(text)?.toUtc();
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
