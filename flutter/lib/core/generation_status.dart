import 'dart:convert';

const Set<String> generationFailureStatuses = <String>{
  'Task not found',
  'Error',
  'Failed',
  'Request Moderated',
  'Content Moderated',
};

String normalizeGenerationStatus(Object? value) {
  final status = value?.toString().trim() ?? '';
  return switch (status.toLowerCase()) {
    'submitting' => 'submitting',
    'pending' => 'Pending',
    'ready' || 'success' => 'Ready',
    'task not found' => 'Task not found',
    'error' => 'Error',
    'failed' => 'Failed',
    'request moderated' => 'Request Moderated',
    'content moderated' => 'Content Moderated',
    _ => status.isEmpty ? 'Unknown' : status,
  };
}

bool isGenerationFailureStatus(String status) =>
    generationFailureStatuses.contains(normalizeGenerationStatus(status));

bool isGenerationWorkingStatus(String status, {required bool canPoll}) {
  final normalized = normalizeGenerationStatus(status);
  if (normalized == 'submitting' || normalized == 'Pending') return true;
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

String providerFailureMessage(Object? payload, {required String fallback}) {
  String? find(Object? value) {
    if (value is String) {
      final clean = value.trim();
      return clean.isEmpty ? null : clean;
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
        final found = find(match?.value);
        if (found != null) return found;
      }
      for (final child in value.values) {
        final found = find(child);
        if (found != null) return found;
      }
    }
    if (value is List<Object?>) {
      for (final child in value) {
        final found = find(child);
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

String compactProviderResponse(Object? payload, {int maxCharacters = 12000}) {
  String rendered;
  if (payload == null) {
    rendered = 'No response body was returned.';
  } else if (payload is String) {
    rendered = payload.trim().isEmpty ? '(empty response)' : payload.trim();
  } else {
    try {
      rendered = const JsonEncoder.withIndent('  ').convert(payload);
    } on Object {
      rendered = payload.toString();
    }
  }
  if (rendered.length <= maxCharacters) return rendered;
  return '${rendered.substring(0, maxCharacters)}\n\n'
      '… response truncated to $maxCharacters characters by Clawnsole';
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

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
