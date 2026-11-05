import 'bfl_api.dart';
import 'models.dart';
import 'reference_prompts.dart';

/// The standard routes in APIPod's published Seedance 2.5 OpenAPI schemas.
/// Dedicated draft/edit/extend and discounted routes have separate contracts.
const apipodSeedanceModels = <String>{
  'seedance-2.5-t2v',
  'seedance-2.5-i2v',
  'seedance-2.5-r2v',
};

Map<String, Object?> apipodGenerationPayload(
  String model,
  Map<String, Object?> input,
) {
  if (!apipodSeedanceModels.contains(model)) {
    _invalid('This APIPod model is not supported by this build.');
  }
  final framesRoute = model.endsWith('-i2v');
  final referenceRoute = model.endsWith('-r2v');
  final mode = input['mode'];
  if (mode != null && mode != (model.endsWith('-t2v') ? 't2v' : 'i2v')) {
    _invalid(
      'This APIPod route does not support the selected generation mode.',
    );
  }
  final task = input['reference_task'];
  if (task != null && task != 'reference') {
    _invalid('This APIPod route supports reference generation only.');
  }
  for (final field in const ['start_video', 'input_video']) {
    final value = input[field];
    if (value != null && value != '') {
      _invalid('This APIPod route does not accept a source video.');
    }
  }
  if (input['draft'] == true) {
    _invalid('This APIPod route does not support draft generation.');
  }
  final frames = _sources(input['keyframes'], frames: true);
  final images = _sources(input['reference_images']);
  final videos = _sources(input['reference_videos']);
  final audios = _sources(input['reference_audios']);
  if (framesRoute) {
    if (frames.isEmpty || frames.length > 2) {
      _invalid('APIPod image-to-video requires one or two pinned images.');
    }
  } else if (frames.isNotEmpty) {
    _invalid('This APIPod route does not accept pinned images.');
  }
  if (!referenceRoute &&
      (images.isNotEmpty || videos.isNotEmpty || audios.isNotEmpty)) {
    _invalid('This APIPod route does not accept creative references.');
  }
  if (images.length > 30 || videos.length > 10 || audios.length > 10) {
    _invalid(
      'APIPod supports at most 30 images, 10 videos, and 10 audio references.',
    );
  }
  if (referenceRoute && images.isEmpty && videos.isEmpty) {
    _invalid(
      'APIPod reference generation requires an image or video reference.',
    );
  }
  final prompt = input['prompt'];
  if (prompt is! String || prompt.trim().isEmpty || prompt.length > 30000) {
    _invalid('APIPod requires a prompt of 1–30,000 characters.');
  }
  final resolution = switch (input['resolution'] ?? 'hd') {
    'sd' => '480p',
    'hd' => '720p',
    _ => null,
  };
  if (resolution == null) {
    _invalid('This APIPod route supports 480p or 720p.');
  }
  final duration = input['duration'] ?? 4;
  if (duration is! num ||
      !duration.isFinite ||
      duration != duration.roundToDouble() ||
      duration < 4 ||
      duration > 30) {
    _invalid('APIPod requires a whole-number duration from 4 to 30 seconds.');
  }
  final ratio = input['aspect_ratio'] ?? 'auto';
  if (!(framesRoute
          ? const ['auto']
          : const ['auto', '16:9', '4:3', '1:1', '3:4', '9:16', '21:9'])
      .contains(ratio)) {
    _invalid(
      framesRoute
          ? 'APIPod image-to-video follows the pinned image aspect ratio.'
          : 'This APIPod route does not support the selected aspect ratio.',
    );
  }
  final audio = input['generate_audio'] ?? true;
  if (audio is! bool) {
    _invalid('The APIPod audio setting must be true or false.');
  }
  if (input['seed'] != null) {
    _invalid('This APIPod route does not expose a seed in its API schema.');
  }
  final translatedPrompt = translateReferencePrompt(
    prompt,
    dialect: ReferencePromptDialect.compactAt,
    available: promptReferenceMentions(<MediaReferenceKind>[
      ...List.filled(images.length, MediaReferenceKind.image),
      ...List.filled(videos.length, MediaReferenceKind.video),
      ...List.filled(audios.length, MediaReferenceKind.audio),
    ], names: referencePromptNamesFromInput(input)),
  );
  return <String, Object?>{
    'model': model,
    'prompt': translatedPrompt,
    'duration': duration.toInt(),
    'resolution': resolution,
    'generate_audio': audio,
    if (!framesRoute) 'aspect_ratio': ratio == 'auto' ? 'adaptive' : ratio,
    if (framesRoute) 'image_urls': frames,
    if (images.isNotEmpty) 'image_urls': images,
    if (videos.isNotEmpty) 'video_urls': videos,
    if (audios.isNotEmpty) 'audio_urls': audios,
  };
}

List<String> _sources(Object? value, {bool frames = false}) {
  if (value == null) return const [];
  if (value is! List) {
    _invalid('APIPod media inputs must be lists of public URLs.');
  }
  return value.map((item) {
    final source = frames && item is List && item.length == 2 ? item[1] : item;
    if (source is! String || source.trim().isEmpty) {
      _invalid('An APIPod media input is missing its public URL.');
    }
    if (source.startsWith('data:')) {
      _invalid(
        'APIPod requires a public HTTPS media URL. Local media uploads are not supported by its documented API.',
      );
    }
    final url = validatedProviderUrl(source);
    if (url.hasFragment) {
      _invalid('APIPod media URLs cannot contain fragments.');
    }
    return url.toString();
  }).toList();
}

Never _invalid(String message) => throw ProviderException(message, status: 400);
