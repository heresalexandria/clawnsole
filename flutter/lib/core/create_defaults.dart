/// What a new Create draft starts with, when the director wants to say.
///
/// Every field is nullable and **null means "Last used"** — the inheriting
/// behaviour a blank tab has always had. A non-null field is an instruction:
/// open the draft this way regardless of what the previous one held. Only
/// controls a fresh blank draft actually offers belong here; upscale and
/// enhance knobs are properties of a film being reworked, not of a new one.
///
/// These are defaults for *blank* drafts only. Reuse, Extend and Enhance
/// restore a film's own recipe and are never overridden by them.
library;

/// The duration a new draft opens on: the provider's own choice, or a fixed
/// number of seconds.
class CreateDurationDefault {
  const CreateDurationDefault.auto() : seconds = null;

  const CreateDurationDefault.seconds(int this.seconds);

  /// Null means the model picks the length ("Auto").
  final int? seconds;

  bool get isAuto => seconds == null;

  Object toJson() => seconds ?? 'auto';

  /// Reads a stored value, rejecting anything outside the broad bounds the
  /// composer could ever offer. Model-specific limits stay with the provider
  /// capability contract, which normalizes the form after the default lands.
  static CreateDurationDefault? tryFromJson(Object? value) {
    if (value == 'auto') return const CreateDurationDefault.auto();
    if (value is! num || !value.isFinite) return null;
    final seconds = value.toInt();
    if (seconds < 1 || seconds > 86400) return null;
    return CreateDurationDefault.seconds(seconds);
  }

  @override
  bool operator ==(Object other) =>
      other is CreateDurationDefault && seconds == other.seconds;

  @override
  int get hashCode => seconds.hashCode;
}

class CreateDefaults {
  const CreateDefaults({
    this.screenplayMode,
    this.providerId,
    this.modelId,
    this.aspectRatio,
    this.resolution,
    this.duration,
    this.generateAudio,
    this.draft,
    this.aestheticReferenceId,
  });

  static const schemaVersion = 1;

  /// The aesthetic value meaning "start with none", as distinct from null's
  /// "carry over whatever the last draft had".
  static const String noAesthetic = '';

  /// Nothing has been asked for: every new draft simply inherits.
  static const CreateDefaults none = CreateDefaults();

  /// Screenplay (true) or Plaintext (false); null inherits.
  final bool? screenplayMode;

  /// The model a new draft opens on. Both halves travel together — a
  /// provider without a model is not a model — and both are checked against
  /// the live catalog before they are applied.
  final String? providerId;
  final String? modelId;

  final String? aspectRatio;
  final String? resolution;
  final CreateDurationDefault? duration;
  final bool? generateAudio;
  final bool? draft;

  /// An aesthetic id, [noAesthetic] for "None", or null to inherit.
  final String? aestheticReferenceId;

  /// Whether a model was named. A half-named pair is treated as unset.
  bool get hasModel =>
      (providerId?.isNotEmpty ?? false) && (modelId?.isNotEmpty ?? false);

  bool get isEmpty =>
      screenplayMode == null &&
      !hasModel &&
      aspectRatio == null &&
      resolution == null &&
      duration == null &&
      generateAudio == null &&
      draft == null &&
      aestheticReferenceId == null;

  CreateDefaults copyWith({
    bool? screenplayMode,
    bool clearScreenplayMode = false,
    String? providerId,
    String? modelId,
    bool clearModel = false,
    String? aspectRatio,
    bool clearAspectRatio = false,
    String? resolution,
    bool clearResolution = false,
    CreateDurationDefault? duration,
    bool clearDuration = false,
    bool? generateAudio,
    bool clearGenerateAudio = false,
    bool? draft,
    bool clearDraft = false,
    String? aestheticReferenceId,
    bool clearAesthetic = false,
  }) => CreateDefaults(
    screenplayMode: clearScreenplayMode
        ? null
        : screenplayMode ?? this.screenplayMode,
    providerId: clearModel ? null : providerId ?? this.providerId,
    modelId: clearModel ? null : modelId ?? this.modelId,
    aspectRatio: clearAspectRatio ? null : aspectRatio ?? this.aspectRatio,
    resolution: clearResolution ? null : resolution ?? this.resolution,
    duration: clearDuration ? null : duration ?? this.duration,
    generateAudio: clearGenerateAudio
        ? null
        : generateAudio ?? this.generateAudio,
    draft: clearDraft ? null : draft ?? this.draft,
    aestheticReferenceId: clearAesthetic
        ? null
        : aestheticReferenceId ?? this.aestheticReferenceId,
  );

  /// Only what was actually asked for is written, so untouched defaults add
  /// nothing to the settings record and an empty set is omitted entirely.
  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    if (screenplayMode != null) 'screenplayMode': screenplayMode,
    if (hasModel) 'providerId': providerId,
    if (hasModel) 'modelId': modelId,
    if (aspectRatio != null) 'aspectRatio': aspectRatio,
    if (resolution != null) 'resolution': resolution,
    if (duration != null) 'duration': duration!.toJson(),
    if (generateAudio != null) 'generateAudio': generateAudio,
    if (draft != null) 'draft': draft,
    if (aestheticReferenceId != null)
      'aestheticReferenceId': aestheticReferenceId,
  };

  /// Ignores unsupported records and unknown fields. A field that cannot be
  /// read is left unset, which is the inheriting behaviour it replaced.
  static CreateDefaults? tryFromJson(Object? value) {
    if (value is! Map<Object?, Object?>) return null;
    final version = value['schemaVersion'] ?? schemaVersion;
    if (version != schemaVersion) return null;
    final provider = _id(value['providerId']);
    final model = _id(value['modelId']);
    return CreateDefaults(
      screenplayMode: _boolean(value['screenplayMode']),
      providerId: model == null ? null : provider,
      modelId: provider == null ? null : model,
      aspectRatio: _id(value['aspectRatio']),
      resolution: _id(value['resolution']),
      duration: CreateDurationDefault.tryFromJson(value['duration']),
      generateAudio: _boolean(value['generateAudio']),
      draft: _boolean(value['draft']),
      // The empty string is "None" here, so it survives the blank check the
      // other ids get.
      aestheticReferenceId: switch (value['aestheticReferenceId']) {
        final String text when text.length <= 128 => text.trim(),
        _ => null,
      },
    );
  }

  static bool? _boolean(Object? value) => value is bool ? value : null;

  static String? _id(Object? value) {
    if (value is! String) return null;
    final text = value.trim();
    return text.isNotEmpty && text.length <= 128 ? text : null;
  }

  @override
  bool operator ==(Object other) =>
      other is CreateDefaults &&
      screenplayMode == other.screenplayMode &&
      providerId == other.providerId &&
      modelId == other.modelId &&
      aspectRatio == other.aspectRatio &&
      resolution == other.resolution &&
      duration == other.duration &&
      generateAudio == other.generateAudio &&
      draft == other.draft &&
      aestheticReferenceId == other.aestheticReferenceId;

  @override
  int get hashCode => Object.hash(
    screenplayMode,
    providerId,
    modelId,
    aspectRatio,
    resolution,
    duration,
    generateAudio,
    draft,
    aestheticReferenceId,
  );
}
