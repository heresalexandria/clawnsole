import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'prompt_rewrite.dart';
import 'rewrite_connection.dart';

/// Chat Completions adapter for user-configured OpenAI-compatible services.
/// Unlike the built-in OpenAI adapter, model names and optional vendor fields
/// are not inferred. This also supports services without a model catalog.
class CompatibleRewriteApi implements PromptRewriteApi {
  CompatibleRewriteApi({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<List<RewriteModel>> listModels(String apiKey) async {
    final connection = RewriteConnection.fromCredential(apiKey);
    final response = await _send(connection, 'models');
    if (const <int>{404, 405, 501}.contains(response.statusCode)) {
      return const <RewriteModel>[];
    }
    final body = _read(response, connection.apiKey);
    final rows = body['data'];
    if (rows is! List<Object?>) {
      throw const PromptRewriteException(
        'The endpoint returned an unreadable model catalog.',
        failure: PromptRewriteFailure.invalidResponse,
      );
    }
    final seen = <String>{};
    return <RewriteModel>[
      for (final row in rows.whereType<Map<String, dynamic>>())
        if (row['id'] case final String id)
          if (id.trim().isNotEmpty && seen.add(id.trim()))
            RewriteModel(
              id: id.trim(),
              label: row['name'] is String ? row['name'] as String : id.trim(),
              supportsEffort: false,
              supportsThinking: false,
            ),
    ];
  }

  @override
  Future<PromptRewriteResult> rewrite(
    PromptRewriteRequest request,
    String apiKey,
  ) async {
    if (request.modelId.trim().isEmpty) {
      throw const PromptRewriteException(
        'Enter a model id for your custom endpoint.',
        failure: PromptRewriteFailure.badRequest,
      );
    }
    final connection = RewriteConnection.fromCredential(apiKey);
    final response = await _send(
      connection,
      'chat/completions',
      payload: rewritePayload(request),
    );
    final body = _read(response, connection.apiKey);
    final choices = body['choices'];
    final choice = choices is List<Object?> && choices.isNotEmpty
        ? choices.first
        : null;
    if (choice is! Map<String, dynamic>) {
      throw const PromptRewriteException(
        'The endpoint returned no rewrite.',
        failure: PromptRewriteFailure.invalidResponse,
      );
    }
    final message = choice['message'];
    if (choice['finish_reason'] == 'content_filter' ||
        (message is Map<String, dynamic> && message['refusal'] != null)) {
      throw const PromptRewriteException(
        'The model declined to rewrite this prompt.',
        failure: PromptRewriteFailure.refused,
      );
    }
    if (choice['finish_reason'] == 'length') {
      throw const PromptRewriteException(
        'The model stopped before finishing the rewrite.',
        failure: PromptRewriteFailure.invalidResponse,
      );
    }
    final content = message is Map<String, dynamic> ? message['content'] : null;
    final text = content is String
        ? content
        : content is List<Object?>
        ? content
              .whereType<Map<String, dynamic>>()
              .where((part) => part['type'] == 'text')
              .map(
                (part) => part['text'] is String ? part['text'] as String : '',
              )
              .join()
        : '';
    return parseRewriteOutput(
      text,
      providerId: RewriteProvider.custom.id,
      modelId: body['model'] is String
          ? body['model'] as String
          : request.modelId,
    );
  }

  Map<String, Object?> rewritePayload(PromptRewriteRequest request) =>
      <String, Object?>{
        'model': request.modelId,
        'messages': <Map<String, Object?>>[
          <String, Object?>{
            'role': 'system',
            'content': buildRewriteInstructions(request),
          },
          <String, Object?>{
            'role': 'user',
            'content': request.frames.isEmpty
                ? buildRewriteBrief(request)
                : <Map<String, Object?>>[
                    for (var i = 0; i < request.frames.length; i++) ...[
                      <String, Object?>{
                        'type': 'text',
                        'text': rewriteFrameLabel(
                          i,
                          request.frames.length,
                          request.frames[i].seconds,
                        ),
                      },
                      <String, Object?>{
                        'type': 'image_url',
                        'image_url': <String, Object?>{
                          'url':
                              'data:${request.frames[i].mimeType};base64,'
                              '${request.frames[i].base64Data}',
                        },
                      },
                    ],
                    <String, Object?>{
                      'type': 'text',
                      'text': buildRewriteBrief(request),
                    },
                  ],
          },
        ],
        // JSON is requested in the system instruction and validated locally.
        // Do not require optional structured-output or reasoning parameters
        // that many otherwise-compatible models reject.
        'max_tokens': 4096,
        'stream': false,
      };

  Future<http.Response> _send(
    RewriteConnection connection,
    String path, {
    Map<String, Object?>? payload,
  }) async {
    try {
      final request =
          http.Request(
              payload == null ? 'GET' : 'POST',
              connection.endpoint.resolve(path),
            )
            // A custom server must not redirect its credential to another host.
            ..followRedirects = false
            ..headers.addAll(<String, String>{
              'Accept': 'application/json',
              'Authorization': 'Bearer ${connection.apiKey}',
              if (payload != null) 'Content-Type': 'application/json',
            });
      if (payload != null) request.body = jsonEncode(payload);
      return await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(Duration(seconds: payload == null ? 20 : 90));
    } on TimeoutException {
      throw const PromptRewriteException(
        'The custom endpoint did not respond in time.',
        failure: PromptRewriteFailure.network,
      );
    } on Object {
      throw const PromptRewriteException(
        'Clawnsole could not reach the custom endpoint.',
        failure: PromptRewriteFailure.network,
      );
    }
  }

  Map<String, Object?> _read(http.Response response, String apiKey) {
    Map<String, Object?>? body;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) body = decoded;
    } on FormatException {
      // An HTML proxy error is not a model response.
    }
    final status = response.statusCode;
    if (status < 200 || status >= 300 || body?['error'] != null) {
      final failure = switch (status) {
        401 || 403 => PromptRewriteFailure.unauthorized,
        402 || 429 => PromptRewriteFailure.rateLimited,
        400 || 404 || 405 || 422 => PromptRewriteFailure.badRequest,
        _ => PromptRewriteFailure.other,
      };
      final error = body?['error'];
      final detail = error is Map<String, dynamic> ? error['message'] : null;
      throw PromptRewriteException(
        failure == PromptRewriteFailure.unauthorized
            ? 'The custom endpoint rejected this API key.'
            : detail is String && detail.trim().isNotEmpty
            ? detail.replaceAll(apiKey, '[redacted]')
            : status >= 300 && status < 400
            ? 'The endpoint redirected the request. Enter its final API base URL.'
            : 'The custom endpoint could not complete this request (HTTP $status).',
        failure: failure,
        status: status,
      );
    }
    if (body == null) {
      throw const PromptRewriteException(
        'The custom endpoint returned an answer Clawnsole could not read.',
        failure: PromptRewriteFailure.invalidResponse,
      );
    }
    return body;
  }
}
