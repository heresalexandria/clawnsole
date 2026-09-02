import 'package:http/http.dart' as http;

import 'prompt_rewrite.dart';

/// OpenAI Responses API client for AI Rewrite (`POST /v1/responses`,
/// `GET /v1/models`).
///
/// Implementation pending: see the AI Rewrite work plan. The public surface
/// below is the contract the gateways and companion compile against.
class OpenAiRewriteApi implements PromptRewriteApi {
  OpenAiRewriteApi({http.Client? client, Uri? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? Uri.parse('https://api.openai.com');

  final http.Client _client;
  final Uri _baseUrl;

  Uri get baseUrl => _baseUrl;
  http.Client get client => _client;

  @override
  Future<List<RewriteModel>> listModels(String apiKey) {
    throw UnimplementedError('OpenAiRewriteApi.listModels');
  }

  @override
  Future<PromptRewriteResult> rewrite(
    PromptRewriteRequest request,
    String apiKey,
  ) {
    throw UnimplementedError('OpenAiRewriteApi.rewrite');
  }
}
