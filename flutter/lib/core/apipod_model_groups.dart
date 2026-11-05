import 'apipod_models.dart';
import 'apipod_schema_data.dart';
import 'bfl_api.dart';
import 'models.dart';
import 'provider_catalog.dart';

/// Resolves a user-facing APIPod choice to one audited wire route. Wire IDs
/// remain valid selection inputs, so saved preferences and history retain their
/// identity while subsequent attachments can choose a sibling route.
String resolveApipodRoute(
  String modelOrGroupId, {
  VideoMode? mode,
  int keyframeCount = 0,
  int imageReferenceCount = 0,
  int videoReferenceCount = 0,
  int audioReferenceCount = 0,
  bool hasSourceVideo = false,
  String? resolution,
}) {
  final explicit = apipodModels
      .where((model) => model.id == modelOrGroupId)
      .firstOrNull;
  final selectionId = explicit?.selectionId ?? modelOrGroupId;
  final family = apipodModels
      .where((model) => model.selectionId == selectionId)
      .toList();
  if (family.isEmpty ||
      [
        keyframeCount,
        imageReferenceCount,
        videoReferenceCount,
        audioReferenceCount,
      ].any((count) => count < 0)) {
    throw const ProviderException(
      'This APIPod model choice is invalid.',
      status: 400,
    );
  }
  // Draft finalization inherits its source media server-side. The composer
  // retains preview attachments when switching stages, but none is submitted.
  if (mode == VideoMode.draftEnhance) {
    keyframeCount = imageReferenceCount = videoReferenceCount =
        audioReferenceCount = 0;
    hasSourceVideo = false;
  }
  final hasReferences =
      imageReferenceCount + videoReferenceCount + audioReferenceCount > 0;
  final hasGuidance = keyframeCount > 0 || hasReferences;
  final requestedMode = hasSourceVideo
      ? VideoMode.v2v
      : mode == VideoMode.draftEnhance || mode == VideoMode.v2v
      ? mode!
      : hasGuidance
      ? VideoMode.i2v
      : mode ??
            (family.any((model) => model.modes.contains(VideoMode.t2v))
                ? VideoMode.t2v
                : family.first.modes.first);
  bool accepts(VideoModelDefinition model) {
    if (!model.modes.contains(requestedMode)) return false;
    final required =
        apipodRouteSchemas[model.id]?['required'] as List? ?? const [];
    if (hasGuidance &&
        keyframeCount + imageReferenceCount == 0 &&
        required.any(
          (field) => const [
            'image_url',
            'image_urls',
            'first_frame_image',
          ].contains(field),
        )) {
      return false;
    }
    if (audioReferenceCount > 0 &&
        model.requiresVisualReferenceForAudio &&
        keyframeCount + imageReferenceCount + videoReferenceCount == 0 &&
        !hasSourceVideo) {
      return false;
    }

    if (keyframeCount > model.maxKeyframesFor(requestedMode) ||
        imageReferenceCount >
            model.maxReferences(MediaReferenceKind.image, requestedMode) ||
        videoReferenceCount >
            model.maxReferences(MediaReferenceKind.video, requestedMode) ||
        audioReferenceCount >
            model.maxReferences(MediaReferenceKind.audio, requestedMode)) {
      return false;
    }
    if (model.framesExclusiveWithReferences &&
        keyframeCount > 0 &&
        hasReferences) {
      return false;
    }
    if (resolution != null &&
        !(model.resolutionsByMode[requestedMode] ??
                model.resolutions.map((item) => item.id).toList())
            .contains(resolution)) {
      return false;
    }
    return true;
  }

  final candidates = family.where(accepts).toList();
  if (candidates.isEmpty) {
    throw const ProviderException(
      'This APIPod model choice does not support the attached media and output settings.',
      status: 400,
    );
  }
  // Preserve a compatible existing wire identity. For a group alias, prefer the
  // route dedicated to the current input shape over a more permissive sibling.
  if (explicit != null && candidates.contains(explicit)) return explicit.id;
  final preferredSuffix = hasReferences
      ? '-r2v'
      : keyframeCount > 0
      ? '-i2v'
      : '-t2v';
  return candidates
          .where((model) => model.id.endsWith(preferredSuffix))
          .firstOrNull
          ?.id ??
      candidates.first.id;
}

String resolveApipodRouteForInput(String model, Map<String, Object?> input) {
  int count(String key) {
    final value = input[key];
    if (value == null) return 0;
    if (value is! List) {
      throw const ProviderException(
        'APIPod media inputs must be lists.',
        status: 400,
      );
    }
    return value.length;
  }

  final modeName = input['mode'];
  final mode = VideoMode.values
      .where((mode) => mode.wireValue == modeName)
      .firstOrNull;
  if (modeName != null && mode == null) {
    throw const ProviderException(
      'The APIPod generation mode is invalid.',
      status: 400,
    );
  }
  return resolveApipodRoute(
    model,
    mode: mode,
    keyframeCount: count('keyframes'),
    imageReferenceCount: count('reference_images'),
    videoReferenceCount: count('reference_videos'),
    audioReferenceCount: count('reference_audios'),
    hasSourceVideo: [
      'start_video',
      'input_video',
    ].any((key) => input[key] != null && input[key] != ''),
    resolution: input['resolution']?.toString(),
  );
}
