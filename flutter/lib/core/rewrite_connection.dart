import 'dart:convert';

import 'prompt_rewrite.dart';

/// A custom rewrite endpoint and its key are one versioned vault credential.
/// Saving or syncing them together prevents a host change from reusing a key
/// intended for another service. Existing provider credentials stay unchanged.
class RewriteConnection {
  RewriteConnection({required String endpoint, required String apiKey})
    : endpoint = normalizeRewriteEndpoint(endpoint),
      apiKey = apiKey.trim() {
    if (this.apiKey.isEmpty) {
      throw const PromptRewriteException(
        'Paste an API key first.',
        failure: PromptRewriteFailure.missingKey,
      );
    }
  }

  final Uri endpoint;
  final String apiKey;

  String toCredential() => jsonEncode(<String, Object?>{
    'schemaVersion': 1,
    'endpoint': endpoint.toString(),
    'apiKey': apiKey,
  });

  factory RewriteConnection.fromCredential(String value) {
    try {
      final json = jsonDecode(value);
      if (json is Map<String, dynamic> &&
          json['schemaVersion'] == 1 &&
          json['endpoint'] is String &&
          json['apiKey'] is String) {
        return RewriteConnection(
          endpoint: json['endpoint'] as String,
          apiKey: json['apiKey'] as String,
        );
      }
    } on FormatException {
      // Report no fragments of a malformed credential.
    }
    throw const PromptRewriteException(
      'Save the custom AI Rewrite endpoint and API key again in Settings.',
      failure: PromptRewriteFailure.badRequest,
    );
  }

  static RewriteConnection? tryFromCredential(String value) {
    try {
      return RewriteConnection.fromCredential(value);
    } on PromptRewriteException {
      return null;
    }
  }
}

/// Accepts an API base (including its version path) or a full chat endpoint.
/// Only the harmless base URL is exposed in snapshots; credentials in URLs
/// and query strings are rejected so they can never escape the vault.
Uri normalizeRewriteEndpoint(String value) {
  final clean = value.trim();
  final uri = Uri.tryParse(clean);
  if (uri == null ||
      !const <String>{'http', 'https'}.contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      RegExp(r'\s').hasMatch(clean)) {
    throw const PromptRewriteException(
      'Enter an HTTP or HTTPS API base URL without credentials, a query, or a fragment.',
      failure: PromptRewriteFailure.badRequest,
    );
  }
  var path = uri.path.replaceFirst(RegExp(r'/+$'), '');
  if (path.endsWith('/chat/completions')) {
    path = path.substring(0, path.length - '/chat/completions'.length);
  }
  return uri.replace(path: '$path/');
}
