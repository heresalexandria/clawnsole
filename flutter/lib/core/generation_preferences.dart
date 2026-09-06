import 'dart:convert';

/// Identifies a model within its provider without assuming either id excludes
/// a particular separator. Registry ids may include slashes or punctuation.
String generationPreferenceKey(String providerId, String modelId) =>
    jsonEncode(<String>[providerId, modelId]);

/// Last-used generation controls, independent of any particular draft.
///
/// Only reusable scalar controls belong here. Prompts, seeds, screenplay state,
/// references, media, source generations, and destination folders stay with
/// their own composer tab. The controller checks restored controls against the
/// selected model's capabilities before applying them.
class GenerationPreferences {
  const GenerationPreferences({
    this.aspectRatio = '16:9',
    this.autoDuration = false,
    this.durationSeconds = 8,
    this.frameRate = 2,
    this.resolution = 'hd',
    this.generateAudio = true,
    this.safetyTolerance = 2,
    this.draft = false,
    this.exactTiming = false,
    this.upscaleFactor = 2,
    this.upscaleCreativity = 1,
  });

  static const schemaVersion = 1;

  final String aspectRatio;
  final bool autoDuration;
  final int durationSeconds;
  final int frameRate;
  final String resolution;
  final bool generateAudio;
  final int safetyTolerance;
  final bool draft;
  final bool exactTiming;
  final double upscaleFactor;
  final int upscaleCreativity;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'aspectRatio': aspectRatio,
    'autoDuration': autoDuration,
    'durationSeconds': durationSeconds,
    'frameRate': frameRate,
    'resolution': resolution,
    'generateAudio': generateAudio,
    'safetyTolerance': safetyTolerance,
    'draft': draft,
    'exactTiming': exactTiming,
    'upscaleFactor': upscaleFactor,
    'upscaleCreativity': upscaleCreativity,
  };

  /// Ignores unsupported records and unknown fields rather than importing
  /// draft content. Broad scalar bounds protect deserialization; model-specific
  /// bounds remain the responsibility of the provider capability contract.
  static GenerationPreferences? tryFromJson(Object? value) {
    if (value is! Map<Object?, Object?>) return null;
    final version = value['schemaVersion'] ?? schemaVersion;
    if (version != schemaVersion) return null;
    const defaults = GenerationPreferences();
    return GenerationPreferences(
      aspectRatio: _text(value['aspectRatio'], defaults.aspectRatio),
      autoDuration: _boolean(value['autoDuration'], defaults.autoDuration),
      durationSeconds: _integer(
        value['durationSeconds'],
        defaults.durationSeconds,
        1,
        86400,
      ),
      frameRate: _integer(value['frameRate'], defaults.frameRate, 1, 1000),
      resolution: _text(value['resolution'], defaults.resolution),
      generateAudio: _boolean(value['generateAudio'], defaults.generateAudio),
      safetyTolerance: _integer(
        value['safetyTolerance'],
        defaults.safetyTolerance,
        0,
        1000,
      ),
      draft: _boolean(value['draft'], defaults.draft),
      exactTiming: _boolean(value['exactTiming'], defaults.exactTiming),
      upscaleFactor: _decimal(
        value['upscaleFactor'],
        defaults.upscaleFactor,
        1,
        64,
      ),
      upscaleCreativity: _integer(
        value['upscaleCreativity'],
        defaults.upscaleCreativity,
        0,
        100,
      ),
    );
  }

  static String _text(Object? value, String fallback) {
    if (value is! String) return fallback;
    final text = value.trim();
    return text.isNotEmpty && text.length <= 128 ? text : fallback;
  }

  static bool _boolean(Object? value, bool fallback) =>
      value is bool ? value : fallback;

  static int _integer(Object? value, int fallback, int minimum, int maximum) {
    if (value is! num || !value.isFinite) return fallback;
    return value.clamp(minimum, maximum).toInt();
  }

  static double _decimal(
    Object? value,
    double fallback,
    double minimum,
    double maximum,
  ) {
    if (value is! num || !value.isFinite) return fallback;
    return value.clamp(minimum, maximum).toDouble();
  }

  @override
  bool operator ==(Object other) =>
      other is GenerationPreferences &&
      aspectRatio == other.aspectRatio &&
      autoDuration == other.autoDuration &&
      durationSeconds == other.durationSeconds &&
      frameRate == other.frameRate &&
      resolution == other.resolution &&
      generateAudio == other.generateAudio &&
      safetyTolerance == other.safetyTolerance &&
      draft == other.draft &&
      exactTiming == other.exactTiming &&
      upscaleFactor == other.upscaleFactor &&
      upscaleCreativity == other.upscaleCreativity;

  @override
  int get hashCode => Object.hash(
    aspectRatio,
    autoDuration,
    durationSeconds,
    frameRate,
    resolution,
    generateAudio,
    safetyTolerance,
    draft,
    exactTiming,
    upscaleFactor,
    upscaleCreativity,
  );
}
