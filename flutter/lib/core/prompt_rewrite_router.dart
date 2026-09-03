import 'package:http/http.dart' as http;

import 'anthropic_rewrite_api.dart';
import 'openai_rewrite_api.dart';
import 'prompt_rewrite.dart';

/// Dispatches AI Rewrite calls to the vendor client for a provider id.
///
/// Constructed once per gateway (native) or companion process; tests inject
/// fakes through [apis].
class PromptRewriteRouter {
  PromptRewriteRouter({
    http.Client? client,
    Map<String, PromptRewriteApi>? apis,
  }) : _apis =
           apis ??
           <String, PromptRewriteApi>{
             RewriteProvider.openai.id: OpenAiRewriteApi(client: client),
             RewriteProvider.anthropic.id: AnthropicRewriteApi(client: client),
           };

  final Map<String, PromptRewriteApi> _apis;

  PromptRewriteApi apiFor(String providerId) {
    final api = _apis[providerId];
    if (api == null) {
      throw PromptRewriteException(
        'Unknown rewrite provider "$providerId".',
        failure: PromptRewriteFailure.badRequest,
        status: 400,
      );
    }
    return api;
  }

  Future<List<RewriteModel>> listModels({
    required String providerId,
    required String apiKey,
  }) => apiFor(providerId).listModels(apiKey);

  Future<PromptRewriteResult> rewrite(
    PromptRewriteRequest request, {
    required String apiKey,
  }) => apiFor(request.providerId).rewrite(request, apiKey);
}
