import 'apipod_model_groups.dart';
import 'bfl_api.dart';
import 'models.dart';
import 'provider_catalog.dart';

/// Product choices can contain multiple transport routes without changing the
/// wire identities stored in history, preferences, or submitted requests.
Iterable<VideoModelDefinition> modelsForSelection(
  VideoProviderDefinition provider,
  VideoModelDefinition model,
) => provider.models.where((item) => item.selectionId == model.selectionId);

List<VideoModelDefinition> providerModelSelections(
  VideoProviderDefinition provider,
) {
  final choices = <String, VideoModelDefinition>{};
  for (final model in provider.models) {
    final previous = choices[model.selectionId];
    if (previous == null ||
        (!previous.modes.contains(VideoMode.t2v) &&
            model.modes.contains(VideoMode.t2v))) {
      choices[model.selectionId] = model;
    }
  }
  return choices.values.toList();
}

VideoModelDefinition? resolveProviderModelSelection(
  VideoProviderDefinition provider,
  VideoModelDefinition model, {
  required VideoMode mode,
  required int keyframeCount,
  required Map<MediaReferenceKind, int> referenceCounts,
  required bool hasSourceVideo,
  String? resolution,
}) {
  if (model.selectionGroupId == null) return model;
  final String route;
  try {
    route = switch (provider.adapter) {
      'apipod' => resolveApipodRoute(
        model.id,
        mode: mode,
        keyframeCount: keyframeCount,
        imageReferenceCount: referenceCounts[MediaReferenceKind.image] ?? 0,
        videoReferenceCount: referenceCounts[MediaReferenceKind.video] ?? 0,
        audioReferenceCount: referenceCounts[MediaReferenceKind.audio] ?? 0,
        hasSourceVideo: hasSourceVideo,
        resolution: resolution,
      ),
      _ => model.id,
    };
  } on ProviderException {
    return null;
  }
  return provider.models.where((item) => item.id == route).firstOrNull;
}
