import 'dart:convert';

const submissionUnknownStatus = 'Submission unknown';
const submissionUnknownMessage =
    'The provider may have accepted this generation, but Clawnsole could not '
    'confirm its receipt. Check your provider account before making another '
    'generation to avoid a duplicate charge. Clawnsole will not resend it automatically.';

const Set<String> generationFailureStatuses = <String>{
  'Task not found',
  'Error',
  'Failed',
  'Request Moderated',
  'Content Moderated',
  'Cancelled',
};

String normalizeGenerationStatus(Object? value) {
  final status = value?.toString().trim() ?? '';
  return switch (status.toLowerCase()) {
    'submitting' => 'submitting',
    'submission unknown' => submissionUnknownStatus,
    'pending' ||
    'queued' ||
    'throttled' ||
    'processing' ||
    'running' ||
    'in_progress' => 'Pending',
    'ready' || 'success' || 'succeeded' || 'completed' => 'Ready',
    'task not found' => 'Task not found',
    'error' => 'Error',
    'failed' => 'Failed',
    'request moderated' => 'Request Moderated',
    'content moderated' => 'Content Moderated',
    'cancelled' || 'canceled' => 'Cancelled',
    _ => status.isEmpty ? 'Unknown' : status,
  };
}

bool isGenerationFailureStatus(String status) =>
    generationFailureStatuses.contains(normalizeGenerationStatus(status));

bool isGenerationWorkingStatus(String status, {required bool canPoll}) {
  final normalized = normalizeGenerationStatus(status);
  if (normalized == 'submitting' || normalized == 'Pending') return true;
  if (normalized == submissionUnknownStatus) return false;
  if (normalized == 'Ready' || isGenerationFailureStatus(normalized)) {
    return false;
  }
  return canPoll;
}

String generationStatusLabel(String status) =>
    switch (normalizeGenerationStatus(status)) {
      'submitting' => 'Submitting',
      'Pending' => 'In progress',
      'Ready' => 'Ready',
      final other => other,
    };

final RegExp _identifierShapedToken = RegExp(
  r'^(?:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{12}|[0-9a-fA-F]{16,}|[A-Za-z0-9_-]{22,})$',
);

/// Whether [value] reads as a job id, hash, or URL rather than a sentence a
/// person should be shown as an error message.
bool _identifierLike(String value) =>
    !value.contains(' ') &&
    (_identifierShapedToken.hasMatch(value) ||
        value.startsWith('http://') ||
        value.startsWith('https://'));

/// Whether stored failure copy is unfit to show: a bare task id, hash, or URL
/// rather than a sentence. Records written before the parser learned to skip
/// identifier fields still carry these and must fall back at display time.
bool isIdentifierLikeFailureText(String? value) {
  final clean = value?.trim() ?? '';
  return clean.isNotEmpty && _identifierLike(clean);
}

/// Plain-language failure copy for a record whose provider no longer holds
/// the task; the delivery window has closed, so re-polling cannot help.
const String expiredGenerationMessage =
    'The provider no longer has this task; its delivery link expired before '
    'the film could be retained.';

/// Whether [status] means the provider forgot the task — the one failure that
/// nothing but the film itself can overturn.
bool isExpiryShapedStatus(String status) =>
    normalizeGenerationStatus(status) == 'Task not found';

String providerFailureMessage(Object? payload, {required String fallback}) {
  String? find(Object? value, {bool guessing = false}) {
    if (value is String) {
      final clean = value.trim();
      if (clean.isEmpty) return null;
      // A speculative sweep over unnamed fields must never surface a job id
      // or URL as the user-facing failure copy.
      if (guessing && _identifierLike(clean)) return null;
      return clean;
    }
    if (value is Map<Object?, Object?>) {
      for (final key in <String>[
        'error',
        'message',
        'detail',
        'details',
        'reason',
      ]) {
        final match = value.entries
            .where((entry) => entry.key.toString().toLowerCase() == key)
            .firstOrNull;
        final found = find(match?.value, guessing: guessing);
        if (found != null) return found;
      }
      for (final entry in value.entries) {
        final key = entry.key.toString().toLowerCase();
        if (key == 'id' ||
            key == 'uuid' ||
            key.endsWith('_id') ||
            key.contains('url')) {
          continue;
        }
        final found = find(entry.value, guessing: true);
        if (found != null) return found;
      }
    }
    if (value is List<Object?>) {
      for (final child in value) {
        final found = find(child, guessing: guessing);
        if (found != null) return found;
      }
    }
    return null;
  }

  final found = find(payload);
  if (found != null &&
      found != fallback &&
      normalizeGenerationStatus(found) == found &&
      !generationFailureStatuses.contains(found)) {
    return found;
  }
  if (fallback.startsWith('BFL ')) return fallback;
  return switch (normalizeGenerationStatus(fallback)) {
    'Task not found' =>
      'BFL no longer recognizes this task. The generation receipt may have expired or become invalid.',
    'Request Moderated' => 'BFL moderated the generation request.',
    'Content Moderated' => 'BFL moderated the generated content.',
    'Error' || 'Failed' => 'BFL reported that this generation failed.',
    final status => 'BFL reported $status for this generation.',
  };
}

/// A persisted diagnostic, never a copy of the provider's request or media.
///
/// This also accepts legacy JSON strings so loading or reserializing old
/// history applies the same policy as a new native/companion response.
String compactProviderResponse(Object? payload, {int maxCharacters = 12000}) {
  String rendered;
  if (payload == null) {
    rendered = 'No response body was returned.';
  } else {
    Object? decoded = payload;
    String? originalJson;
    if (payload is String) {
      final text = payload.trim();
      if (text.startsWith('{') ||
          (text.startsWith('[') && !text.startsWith('[redacted '))) {
        try {
          decoded = jsonDecode(text);
          originalJson = text;
        } on FormatException {
          // A previously truncated JSON response cannot be safely filtered by
          // field. Do not fall back to retaining its unparsed private input.
          decoded = 'Provider response omitted: malformed diagnostic JSON.';
        }
      }
    }
    try {
      final sanitized = sanitizeProviderDiagnosticValue(decoded);
      rendered = sanitized is String
          ? sanitized
          : originalJson != null && jsonEncode(sanitized) == jsonEncode(decoded)
          ? originalJson
          : const JsonEncoder.withIndent('  ').convert(sanitized);
    } on Object {
      rendered = 'Provider response omitted: unsupported diagnostic value.';
    }
  }
  if (maxCharacters < 1) return '';
  if (rendered.length <= maxCharacters) return rendered;
  return '${rendered.substring(0, maxCharacters)}\n\n'
      '… response truncated to $maxCharacters characters by Clawnsole';
}

/// Filters structured diagnostics before they cross the companion boundary.
/// Operational provider responses still use their original data internally.
Object? sanitizeProviderDiagnosticValue(Object? value) =>
    _ProviderDiagnosticSanitizer().sanitize(value);

class _ProviderDiagnosticSanitizer {
  // Keep the provider spelling for compatibility with timing/status readers.
  // Unknown fields are omitted without visiting their values: providers may
  // echo entire uploads or credentials under newly introduced payload fields.
  static const _fields = <String>{
    'id',
    'requestid',
    'taskid',
    'generationid',
    'status',
    'state',
    'stage',
    'type',
    'code',
    'statuscode',
    'httpstatus',
    'error',
    'errors',
    'message',
    'detail',
    'details',
    'reason',
    'retryable',
    'retryafter',
    'progress',
    'progresspercentage',
    'progresspercent',
    'percentage',
    'percent',
    'createdat',
    'startedat',
    'completedat',
    'finishedat',
    'updatedat',
    'maybefirststartedat',
    'maybesuccessfullycompletedat',
    'mayberesult',
    'data',
    'result',
    'billing',
    'usage',
    'actualcost',
    'realizedcost',
    'chargedamount',
    'costincredits',
    'creditsused',
    'cost',
    'costsource',
    'costunit',
    'price',
    'currency',
    'unit',
    'duration',
    'durationseconds',
    'queueposition',
    'omittedfields',
  };
  int _remaining = 256;

  Object? sanitize(Object? value, [int depth = 0]) {
    if (_remaining-- <= 0 || depth > 8) return '[omitted]';
    if (value is Map<Object?, Object?>) {
      final safe = <String, Object?>{};
      var omitted = 0;
      for (final entry in value.entries) {
        final key = entry.key.toString();
        final normalized = key.toLowerCase().replaceAll(RegExp('[^a-z]'), '');
        if (!_fields.contains(normalized) || safe.length >= 64) {
          omitted += 1;
          continue;
        }
        safe[key] = sanitize(entry.value, depth + 1);
      }
      if (omitted > 0) safe['omitted_fields'] = omitted;
      return safe;
    }
    if (value is List<Object?>) {
      return value.take(32).map((item) => sanitize(item, depth + 1)).toList();
    }
    if (value is String) return _text(value);
    if (value == null || value is bool) return value;
    if (value is num && value.isFinite) return value;
    return '[omitted]';
  }

  String _text(String value) {
    var text = value.trim();
    if (text.isEmpty) return '(empty response)';
    if (text.length > 4096) text = '${text.substring(0, 4096)}…';
    // A diagnostic message can itself contain a JSON-encoded request. Treat
    // it as structured data as well, including older truncated responses.
    if (text.startsWith('{') || text.startsWith('[{')) {
      try {
        return jsonEncode(sanitize(jsonDecode(text)));
      } on FormatException {
        return 'Provider response omitted: malformed diagnostic JSON.';
      }
    }
    text = text.replaceAll(
      RegExp(r'''data:[^\s"'<>]+''', caseSensitive: false),
      '[redacted media]',
    );
    text = text.replaceAll(
      RegExp(r'''https?://[^\s"'<>]+''', caseSensitive: false),
      '[redacted URL]',
    );
    text = text.replaceAll(
      RegExp(r'''\b(?:Bearer|Basic)\s+[^\s,"'<>]+''', caseSensitive: false),
      '[redacted credential]',
    );
    text = text.replaceAll(
      RegExp(
        r'''\b(?:api[_-]?key|access[_-]?token|refresh[_-]?token|authorization|password|client[_-]?secret|secret|signature|token)\b["']?\s*[:=]\s*(?:"[^"]*"|'[^']*'|[^\s,;}]+)''',
        caseSensitive: false,
      ),
      '[redacted credential]',
    );
    // Inline binary without a data-URI header and long opaque credentials are
    // not useful support text. Keep ordinary prose and provider task IDs.
    return text.replaceAll(
      RegExp(r'[A-Za-z0-9+/_=-]{80,}'),
      '[redacted payload]',
    );
  }
}

String generationExceptionMessage(Object error) => error
    .toString()
    .replaceFirst('Bad state: ', '')
    .replaceFirst('ProviderException: ', '')
    .replaceFirst('Exception: ', '');

Duration automaticPollDelay(int consecutiveFailures) =>
    switch (consecutiveFailures) {
      <= 0 => const Duration(seconds: 4),
      1 => const Duration(seconds: 8),
      2 => const Duration(seconds: 16),
      3 => const Duration(seconds: 32),
      _ => const Duration(minutes: 1),
    };

/// [automaticPollDelay] spread by up to ±20% so records that failed together
/// stop retrying in lockstep; without jitter every concurrent job for one
/// provider re-synchronizes into the same burst and amplifies rate limits.
///
/// The spread is derived from [seed] (record id plus attempt number) rather
/// than a random draw so a record's due time is stable across the repeated
/// "is it due yet?" checks between two polls.
Duration spreadPollDelay(int consecutiveFailures, {required String seed}) {
  final base = automaticPollDelay(consecutiveFailures);
  final unit = (seed.hashCode & 0xFFFF) / 0xFFFF;
  final spread = (unit * 2 - 1) * .2;
  return Duration(milliseconds: (base.inMilliseconds * (1 + spread)).round());
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
