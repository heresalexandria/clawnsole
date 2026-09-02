/// Provider-neutral contract for AI Rewrite.
///
/// AI Rewrite sends sampled frames of a finished film, the prompt that made
/// it, and the director's change notes to a multimodal LLM (OpenAI or
/// Anthropic) and gets back one revised prompt as structured JSON. This
/// module owns the request/response shapes, the provider registry, the
/// instructions both providers receive, and the output schema. The HTTP
/// clients live in `openai_rewrite_api.dart` and `anthropic_rewrite_api.dart`;
/// gateways dispatch through `prompt_rewrite_router.dart`.
///
/// Keys for these providers are ordinary vault credentials keyed by
/// [RewriteProvider.id]; they never reach the web renderer.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Credential ids of every rewrite provider, in display order.
const List<String> rewriteProviderIds = <String>['openai', 'anthropic'];

/// The vendors that can rewrite prompts. Effort levels are each vendor's own
/// vocabulary so the request carries them through untouched.
enum RewriteProvider {
  openai(
    id: 'openai',
    name: 'OpenAI',
    consoleUrl: 'https://platform.openai.com/api-keys',
    keyHint: 'sk-…',
    effortLevels: <String>['low', 'medium', 'high', 'xhigh'],
    defaultEffort: 'medium',
    defaultModelId: 'gpt-5.5',
  ),
  anthropic(
    id: 'anthropic',
    name: 'Anthropic',
    consoleUrl: 'https://console.anthropic.com/settings/keys',
    keyHint: 'sk-ant-…',
    effortLevels: <String>['low', 'medium', 'high', 'xhigh', 'max'],
    defaultEffort: 'high',
    defaultModelId: 'claude-opus-5',
  );

  const RewriteProvider({
    required this.id,
    required this.name,
    required this.consoleUrl,
    required this.keyHint,
    required this.effortLevels,
    required this.defaultEffort,
    required this.defaultModelId,
  });

  final String id;
  final String name;

  /// Where the director gets a key. Desktop opens it through the Electron
  /// allowlist, so every host here must also be in `EXTERNAL_HOSTS`.
  final String consoleUrl;
  final String keyHint;
  final List<String> effortLevels;
  final String defaultEffort;
  final String defaultModelId;

  /// Bundled fallback used when the live model listing is unavailable, and
  /// the source of display names for ids the listing does not describe.
  List<RewriteModel> get curatedModels => switch (this) {
    RewriteProvider.openai => const <RewriteModel>[
      RewriteModel(id: 'gpt-5.6-sol', label: 'GPT-5.6 Sol'),
      RewriteModel(id: 'gpt-5.6-terra', label: 'GPT-5.6 Terra'),
      RewriteModel(id: 'gpt-5.6-luna', label: 'GPT-5.6 Luna'),
      RewriteModel(id: 'gpt-5.5', label: 'GPT-5.5'),
      RewriteModel(id: 'gpt-5.4', label: 'GPT-5.4'),
      RewriteModel(id: 'gpt-5.4-mini', label: 'GPT-5.4 mini'),
      RewriteModel(id: 'gpt-5.2', label: 'GPT-5.2'),
      RewriteModel(id: 'gpt-5.1', label: 'GPT-5.1'),
      RewriteModel(id: 'gpt-5', label: 'GPT-5'),
      RewriteModel(id: 'gpt-5-mini', label: 'GPT-5 mini'),
      RewriteModel(
        id: 'gpt-4.1',
        label: 'GPT-4.1',
        supportsEffort: false,
        supportsThinking: false,
      ),
    ],
    RewriteProvider.anthropic => const <RewriteModel>[
      RewriteModel(id: 'claude-opus-5', label: 'Claude Opus 5'),
      RewriteModel(id: 'claude-fable-5-1', label: 'Claude Fable 5.1'),
      RewriteModel(id: 'claude-sonnet-5', label: 'Claude Sonnet 5'),
      RewriteModel(id: 'claude-opus-4-8', label: 'Claude Opus 4.8'),
      RewriteModel(id: 'claude-opus-4-7', label: 'Claude Opus 4.7'),
      RewriteModel(
        id: 'claude-opus-4-6',
        label: 'Claude Opus 4.6',
        effortLevels: <String>['low', 'medium', 'high', 'max'],
      ),
      RewriteModel(
        id: 'claude-sonnet-4-6',
        label: 'Claude Sonnet 4.6',
        effortLevels: <String>['low', 'medium', 'high', 'max'],
      ),
      RewriteModel(
        id: 'claude-haiku-4-5',
        label: 'Claude Haiku 4.5',
        supportsEffort: false,
        supportsThinking: false,
      ),
    ],
  };

  RewriteModel? curatedModel(String id) =>
      curatedModels.where((model) => model.id == id).firstOrNull;

  /// Effort levels the picker offers for [modelId]; a model can narrow the
  /// provider's list but never widen it.
  List<String> effortLevelsFor(String modelId, {RewriteModel? model}) {
    final known = model ?? curatedModel(modelId);
    if (known == null) return effortLevels;
    if (!known.supportsEffort) return const <String>[];
    final narrowed = known.effortLevels;
    if (narrowed == null) return effortLevels;
    return narrowed.where(effortLevels.contains).toList();
  }

  static RewriteProvider? byId(String? id) {
    if (id == null) return null;
    for (final provider in values) {
      if (provider.id == id) return provider;
    }
    return null;
  }
}

/// One selectable LLM.
class RewriteModel {
  const RewriteModel({
    required this.id,
    required this.label,
    this.supportsEffort = true,
    this.supportsThinking = true,
    this.effortLevels,
    this.createdAt,
  });

  final String id;
  final String label;

  /// Whether the vendor's effort parameter is accepted. Sending it to a
  /// model that rejects it is a hard 400, so unknown ids are answered by
  /// [RewriteProvider.effortLevelsFor] heuristics in the clients.
  final bool supportsEffort;

  /// Whether adaptive thinking (Anthropic) may be requested.
  final bool supportsThinking;

  /// Narrower effort vocabulary than the provider default, when known.
  final List<String>? effortLevels;
  final DateTime? createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'label': label,
    'supportsEffort': supportsEffort,
    'supportsThinking': supportsThinking,
    if (effortLevels != null) 'effortLevels': effortLevels,
    if (createdAt != null) 'createdAt': createdAt!.toUtc().toIso8601String(),
  };

  factory RewriteModel.fromJson(Map<String, Object?> json) => RewriteModel(
    id: json['id']?.toString() ?? '',
    label: json['label']?.toString() ?? json['id']?.toString() ?? '',
    supportsEffort: json['supportsEffort'] is bool
        ? json['supportsEffort']! as bool
        : true,
    supportsThinking: json['supportsThinking'] is bool
        ? json['supportsThinking']! as bool
        : true,
    effortLevels: switch (json['effortLevels']) {
      final List<Object?> levels => levels.whereType<String>().toList(),
      _ => null,
    },
    createdAt: json['createdAt'] is String
        ? DateTime.tryParse(json['createdAt']! as String)?.toUtc()
        : null,
  );
}

/// A human label for a model id the listing did not describe.
String rewriteModelLabel(String id) {
  final trimmed = id.trim();
  if (trimmed.isEmpty) return trimmed;
  // OpenAI keeps its own casing: "GPT-5.4 mini", "o4-mini".
  if (trimmed.startsWith('gpt-')) {
    return 'GPT-${trimmed.substring(4).replaceAll('-', ' ')}';
  }
  if (RegExp(r'^o\d').hasMatch(trimmed)) return trimmed;
  return trimmed
      .split(RegExp(r'[-_]'))
      .where((word) => word.isNotEmpty)
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
}

/// One sampled frame of the film, sent as an inline image.
class RewriteFrame {
  const RewriteFrame({
    required this.bytes,
    required this.seconds,
    this.mimeType = 'image/jpeg',
  });

  final Uint8List bytes;
  final double seconds;
  final String mimeType;

  String get base64Data => base64Encode(bytes);

  Map<String, Object?> toJson() => <String, Object?>{
    'data': base64Data,
    'seconds': seconds,
    'mimeType': mimeType,
  };

  factory RewriteFrame.fromJson(Map<String, Object?> json) => RewriteFrame(
    bytes: base64Decode(json['data']?.toString() ?? ''),
    seconds: json['seconds'] is num ? (json['seconds']! as num).toDouble() : 0,
    mimeType: json['mimeType']?.toString() ?? 'image/jpeg',
  );
}

/// Everything the LLM needs to revise one prompt. Serializable so the web
/// renderer can hand it to the companion, which holds the key.
class PromptRewriteRequest {
  const PromptRewriteRequest({
    required this.providerId,
    required this.modelId,
    required this.originalPrompt,
    required this.direction,
    this.effort,
    this.frames = const <RewriteFrame>[],
    this.targetProviderName,
    this.targetModelName,
    this.maxPromptCharacters,
    this.durationSeconds,
    this.aspectRatio,
    this.mode,
    this.referenceMentions = const <String>[],
  });

  /// [RewriteProvider.id].
  final String providerId;
  final String modelId;

  /// Vendor effort level, or null to send none.
  final String? effort;
  final String originalPrompt;

  /// What the director wants changed, in their words.
  final String direction;
  final List<RewriteFrame> frames;

  /// The video model the revised prompt will be sent to.
  final String? targetProviderName;
  final String? targetModelName;
  final int? maxPromptCharacters;
  final int? durationSeconds;
  final String? aspectRatio;

  /// `VideoMode.name` of the original generation.
  final String? mode;

  /// Reference mentions such as `@Image 1` the prompt may use verbatim.
  final List<String> referenceMentions;

  Map<String, Object?> toJson() => <String, Object?>{
    'provider': providerId,
    'model': modelId,
    if (effort != null) 'effort': effort,
    'originalPrompt': originalPrompt,
    'direction': direction,
    'frames': frames.map((frame) => frame.toJson()).toList(),
    if (targetProviderName != null) 'targetProviderName': targetProviderName,
    if (targetModelName != null) 'targetModelName': targetModelName,
    if (maxPromptCharacters != null) 'maxPromptCharacters': maxPromptCharacters,
    if (durationSeconds != null) 'durationSeconds': durationSeconds,
    if (aspectRatio != null) 'aspectRatio': aspectRatio,
    if (mode != null) 'mode': mode,
    if (referenceMentions.isNotEmpty) 'referenceMentions': referenceMentions,
  };

  factory PromptRewriteRequest.fromJson(Map<String, Object?> json) {
    String? text(Object? value) {
      if (value is! String) return null;
      final clean = value.trim();
      return clean.isEmpty ? null : clean;
    }

    return PromptRewriteRequest(
      providerId: json['provider']?.toString() ?? '',
      modelId: json['model']?.toString() ?? '',
      effort: text(json['effort']),
      originalPrompt: json['originalPrompt']?.toString() ?? '',
      direction: json['direction']?.toString() ?? '',
      frames: (json['frames'] as List<Object?>? ?? const <Object?>[])
          .whereType<Map<Object?, Object?>>()
          .map(
            (item) => RewriteFrame.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .where((frame) => frame.bytes.isNotEmpty)
          .toList(),
      targetProviderName: text(json['targetProviderName']),
      targetModelName: text(json['targetModelName']),
      maxPromptCharacters: json['maxPromptCharacters'] is num
          ? (json['maxPromptCharacters']! as num).toInt()
          : null,
      durationSeconds: json['durationSeconds'] is num
          ? (json['durationSeconds']! as num).toInt()
          : null,
      aspectRatio: text(json['aspectRatio']),
      mode: text(json['mode']),
      referenceMentions:
          (json['referenceMentions'] as List<Object?>? ?? const <Object?>[])
              .whereType<String>()
              .toList(),
    );
  }
}

/// The revised prompt plus a one-line account of what changed.
class PromptRewriteResult {
  const PromptRewriteResult({
    required this.prompt,
    required this.summary,
    required this.providerId,
    required this.modelId,
  });

  final String prompt;
  final String summary;
  final String providerId;

  /// The model that actually answered (a vendor may serve a fallback).
  final String modelId;

  Map<String, Object?> toJson() => <String, Object?>{
    'prompt': prompt,
    'summary': summary,
    'provider': providerId,
    'model': modelId,
  };

  factory PromptRewriteResult.fromJson(Map<String, Object?> json) =>
      PromptRewriteResult(
        prompt: json['prompt']?.toString() ?? '',
        summary: json['summary']?.toString() ?? '',
        providerId: json['provider']?.toString() ?? '',
        modelId: json['model']?.toString() ?? '',
      );
}

/// Why a rewrite did not produce a prompt, for UI copy and tests.
enum PromptRewriteFailure {
  /// No key saved for the provider.
  missingKey,

  /// The vendor rejected the key (401/403).
  unauthorized,

  /// The vendor rate-limited or is out of quota (429/402).
  rateLimited,

  /// The vendor's safety layer declined the request.
  refused,

  /// The vendor answered, but not with usable JSON.
  invalidResponse,

  /// The request never completed (timeout, DNS, connection).
  network,

  /// The model id, effort, or another parameter was rejected (400/404).
  badRequest,

  /// Anything else, including 5xx.
  other,
}

class PromptRewriteException implements Exception {
  const PromptRewriteException(
    this.message, {
    this.failure = PromptRewriteFailure.other,
    this.status,
  });

  final String message;
  final PromptRewriteFailure failure;
  final int? status;

  @override
  String toString() => message;
}

/// The JSON schema both vendors are constrained to. Every object must set
/// `additionalProperties: false` and list every property as required, which
/// is what OpenAI strict mode and Anthropic structured outputs both demand.
const Map<String, Object?> rewriteOutputSchema = <String, Object?>{
  'type': 'object',
  'properties': <String, Object?>{
    'prompt': <String, Object?>{
      'type': 'string',
      'description':
          'The complete revised prompt, ready to submit to the video model.',
    },
    'summary': <String, Object?>{
      'type': 'string',
      'description':
          'One sentence, under 140 characters, saying what changed and why.',
    },
  },
  'required': <String>['prompt', 'summary'],
  'additionalProperties': false,
};

/// The schema name vendors want alongside the schema.
const String rewriteOutputSchemaName = 'prompt_rewrite';

/// The standing instructions (system prompt) for every rewrite request.
String buildRewriteInstructions(PromptRewriteRequest request) {
  final target = <String>[
    if (request.targetProviderName != null) request.targetProviderName!,
    if (request.targetModelName != null) request.targetModelName!,
  ].join(' ');
  final buffer = StringBuffer()
    ..writeln(
      'You are a senior prompt engineer for AI video generation models. '
      'A director generated a film with the ORIGINAL PROMPT below'
      '${target.isEmpty ? '' : ' using $target'}. '
      'The attached images are frames sampled from that film in order, '
      'each labeled with its timestamp. The CHANGE REQUEST says what the '
      'director wants different next time.',
    )
    ..writeln()
    ..writeln('Write one REVISED PROMPT for the same model that:')
    ..writeln(
      '- Keeps everything the director did not ask to change: subject, '
      'setting, style, camera language, pacing, and their own wording '
      'wherever it still applies.',
    )
    ..writeln(
      '- Makes every requested change explicit and unambiguous. Where the '
      'frames show the model misread the original, add concrete visual '
      'detail (composition, motion, timing, lighting, color) so it cannot '
      'be misread again.',
    )
    ..writeln(
      '- Removes or rewrites wording that plausibly caused the unwanted '
      'result.',
    )
    ..writeln(
      '- Reads as a single prompt in plain descriptive prose: no headings, '
      'lists, quotation marks, or notes about this revision, the frames, '
      'or the previous attempt.',
    );
  if (request.maxPromptCharacters != null) {
    buffer.writeln(
      '- Stays under ${request.maxPromptCharacters} characters in total.',
    );
  }
  if (request.referenceMentions.isNotEmpty) {
    buffer.writeln(
      '- Keeps these reference mentions exactly as written wherever the '
      'director used them, since they bind attached media: '
      '${request.referenceMentions.join(', ')}.',
    );
  }
  buffer
    ..writeln()
    ..write(
      'Respond with JSON only: {"prompt": <the revised prompt>, '
      '"summary": <one sentence under 140 characters describing what you '
      'changed>}.',
    );
  return buffer.toString();
}

/// The user-turn text that accompanies the frames.
String buildRewriteBrief(PromptRewriteRequest request) {
  final facts = <String>[
    if (request.mode != null) 'Mode: ${_describeMode(request.mode!)}',
    if (request.durationSeconds != null)
      'Duration: ${request.durationSeconds} s',
    if (request.aspectRatio != null) 'Aspect ratio: ${request.aspectRatio}',
    if (request.frames.isNotEmpty)
      'Frames attached: ${request.frames.length}'
          ' (${request.frames.map((frame) => _stamp(frame.seconds)).join(', ')})',
  ];
  final buffer = StringBuffer();
  if (facts.isNotEmpty) {
    buffer
      ..writeln(facts.join('\n'))
      ..writeln();
  }
  buffer
    ..writeln('ORIGINAL PROMPT:')
    ..writeln(request.originalPrompt.trim())
    ..writeln()
    ..writeln('CHANGE REQUEST:')
    ..write(request.direction.trim());
  return buffer.toString();
}

/// The label placed before each frame image.
String rewriteFrameLabel(int index, int count, double seconds) =>
    'Frame ${index + 1} of $count at ${_stamp(seconds)}';

String _stamp(double seconds) {
  final tenths = (seconds * 10).round();
  final whole = tenths ~/ 10;
  final fraction = tenths % 10;
  return fraction == 0 ? '$whole s' : '$whole.$fraction s';
}

String _describeMode(String mode) => switch (mode) {
  't2v' => 'text to video',
  'i2v' => 'image to video (frames or references attached)',
  'v2v' => 'video continuation',
  'draftEnhance' => 'draft enhance',
  'upscale' => 'upscale',
  _ => mode,
};

/// Decodes the JSON the model returned, tolerating fences and stray prose
/// around the object. Throws [PromptRewriteException] when no usable prompt
/// is present.
PromptRewriteResult parseRewriteOutput(
  String text, {
  required String providerId,
  required String modelId,
}) {
  final source = text.trim();
  if (source.isEmpty) {
    throw const PromptRewriteException(
      'The model returned an empty answer.',
      failure: PromptRewriteFailure.invalidResponse,
    );
  }
  Map<String, Object?>? decoded;
  for (final candidate in _jsonCandidates(source)) {
    try {
      final value = jsonDecode(candidate);
      if (value is Map<Object?, Object?>) {
        decoded = value.map((key, child) => MapEntry(key.toString(), child));
        break;
      }
    } on FormatException {
      continue;
    }
  }
  final prompt = decoded?['prompt'];
  if (prompt is! String || prompt.trim().isEmpty) {
    throw const PromptRewriteException(
      'The model did not return a revised prompt.',
      failure: PromptRewriteFailure.invalidResponse,
    );
  }
  final summary = decoded?['summary'];
  return PromptRewriteResult(
    prompt: prompt.trim(),
    summary: summary is String ? summary.trim() : '',
    providerId: providerId,
    modelId: modelId,
  );
}

Iterable<String> _jsonCandidates(String source) sync* {
  yield source;
  final fenced = RegExp(
    r'```(?:json)?\s*([\s\S]*?)```',
    caseSensitive: false,
  ).firstMatch(source);
  if (fenced != null) yield fenced.group(1)!.trim();
  final start = source.indexOf('{');
  final end = source.lastIndexOf('}');
  if (start >= 0 && end > start) yield source.substring(start, end + 1);
}

/// One vendor's HTTP client. The key is a per-call argument so a single
/// instance serves every saved credential.
abstract interface class PromptRewriteApi {
  /// Lists models usable for rewriting (multimodal chat models), newest
  /// first. Throws [PromptRewriteException] on an unauthorized key.
  Future<List<RewriteModel>> listModels(String apiKey);

  Future<PromptRewriteResult> rewrite(
    PromptRewriteRequest request,
    String apiKey,
  );
}
