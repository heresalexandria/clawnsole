import 'apipod_catalog.dart';
import 'apipod_schema_data.dart';
import 'bfl_api.dart';
import 'models.dart';
import 'provider_catalog.dart' show VideoModelDefinition;
import 'reference_prompts.dart';

/// Maps provider-neutral input through the exact public schema for each online
/// APIPod route. Catalog capabilities and wire validation use the same audited
/// schema snapshot; arbitrary remote model IDs never become executable routes.
Map<String, Object?> apipodGenerationPayload(
  String model,
  Map<String, Object?> input,
) {
  // Logical selection aliases are conveniences for API callers. Existing
  // persisted wire IDs keep their exact contract; the composer resolves them
  // before creating a record so billing and history retain the dispatched ID.
  if (!apipodRouteSchemas.containsKey(model)) {
    model = resolveApipodRouteForInput(model, input);
    final hasGuidance = const [
      'keyframes',
      'reference_images',
      'reference_videos',
      'reference_audios',
    ].any((key) => input[key] is List && (input[key]! as List).isNotEmpty);
    final hasSource = const [
      'start_video',
      'input_video',
    ].any((key) => input[key] != null && input[key] != '');
    if (hasSource) {
      input = {...input, 'mode': 'v2v'};
    } else if (hasGuidance && input['mode'] != 'draft_enhance') {
      input = {...input, 'mode': 'i2v'};
    }
  }
  final schema = apipodRouteSchemas[model];
  final definition = apipodProvider.models
      .where((candidate) => candidate.id == model)
      .firstOrNull;
  if (schema == null || definition == null) {
    _invalid('This APIPod model is not supported by this build.');
  }
  final properties = _map(schema['properties']);
  final modeName = input['mode'] ?? definition.modes.first.wireValue;
  final mode = VideoMode.values
      .where((candidate) => candidate.wireValue == modeName)
      .firstOrNull;
  if (mode == null || !definition.modes.contains(mode)) {
    _invalid(
      'This APIPod route does not support the selected generation mode.',
    );
  }
  if (mode == VideoMode.draftEnhance) {
    return _draftFinal(model, definition, properties, input);
  }
  if (input['draft'] == true) {
    _invalid('Choose the dedicated APIPod draft route to create a preview.');
  }
  final task = input['reference_task'];
  if (task != null &&
      !definition.referenceTasks.any((candidate) => candidate.name == task)) {
    _invalid('This APIPod route does not support the selected reference task.');
  }

  final frames = _sources(input['keyframes'], frames: true);
  final images = _sources(input['reference_images']);
  final videos = _sources(input['reference_videos']);
  final audios = _sources(input['reference_audios']);
  final source = _sourceVideo(input);
  if (frames.length > definition.maxKeyframesFor(mode) ||
      images.length >
          definition.maxReferences(MediaReferenceKind.image, mode) ||
      videos.length >
          definition.maxReferences(MediaReferenceKind.video, mode) ||
      audios.length >
          definition.maxReferences(MediaReferenceKind.audio, mode)) {
    _invalid('The media count exceeds this APIPod route’s supported inputs.');
  }
  if (definition.framesExclusiveWithReferences &&
      frames.isNotEmpty &&
      (images.isNotEmpty || videos.isNotEmpty || audios.isNotEmpty)) {
    _invalid(
      'This APIPod route cannot combine pinned frames and creative references.',
    );
  }
  if (source != null && mode != VideoMode.v2v) {
    _invalid(
      'Select video-to-video to use a source video on this APIPod route.',
    );
  }
  if (mode == VideoMode.v2v && source == null) {
    _invalid('This APIPod route requires a source video.');
  }
  if (definition.requiresStartFrameWithSource &&
      source != null &&
      frames.isEmpty) {
    _invalid('This APIPod route also requires a character image.');
  }
  if (mode == VideoMode.i2v &&
      frames.isEmpty &&
      images.isEmpty &&
      videos.isEmpty &&
      audios.isEmpty) {
    _invalid('This APIPod route requires image or media guidance.');
  }
  if (mode == VideoMode.t2v &&
      (frames.isNotEmpty ||
          images.isNotEmpty ||
          videos.isNotEmpty ||
          audios.isNotEmpty)) {
    _invalid('Select a guided mode to use media with this APIPod route.');
  }
  if (definition.requiresVisualReferenceForAudio &&
      audios.isNotEmpty &&
      images.isEmpty &&
      videos.isEmpty &&
      frames.isEmpty &&
      source == null) {
    _invalid('APIPod audio guidance also requires an image or video.');
  }
  final prompt = input['prompt'] ?? '';
  if (prompt is! String ||
      (prompt.trim().isEmpty &&
          !definition.promptIsOptional(mode, hasFrames: frames.isNotEmpty))) {
    _invalid('A prompt is required for this APIPod route.');
  }
  final resolution =
      input['resolution']?.toString() ?? definition.resolutions.first.id;
  final supportedResolutions =
      definition.resolutionsByMode[mode] ??
      definition.resolutions.map((entry) => entry.id).toList();
  if (!supportedResolutions.contains(resolution)) {
    _invalid('This APIPod route does not support the selected resolution.');
  }
  final ratio =
      input['aspect_ratio']?.toString() ?? definition.aspectRatios.first;
  if (!definition
      .aspectRatiosFor(resolution, withFrames: frames.isNotEmpty, mode: mode)
      .contains(ratio)) {
    _invalid('This APIPod route does not support the selected aspect ratio.');
  }
  final payload = <String, Object?>{'model': model};
  if (properties.containsKey('prompt')) {
    payload['prompt'] = _translatePrompt(
      prompt,
      model: model,
      videoOffset: source != null && properties.containsKey('video_urls')
          ? 1
          : 0,
      available: promptReferenceMentions(<MediaReferenceKind>[
        ...List.filled(images.length, MediaReferenceKind.image),
        ...List.filled(videos.length, MediaReferenceKind.video),
        ...List.filled(audios.length, MediaReferenceKind.audio),
      ], names: referencePromptNamesFromInput(input)),
    );
  }
  if (properties.containsKey('resolution')) {
    payload['resolution'] = _wireResolution(
      resolution,
      _map(properties['resolution']),
    );
  } else if (properties.containsKey('quality')) {
    payload['quality'] = _wireResolution(
      resolution,
      _map(properties['quality']),
    );
  }
  if (properties.containsKey('aspect_ratio')) {
    final rule = _map(properties['aspect_ratio']);
    final choices = _list(rule['enum']);
    payload['aspect_ratio'] = ratio == 'auto'
        ? (choices.contains('adaptive') ? 'adaptive' : 'auto')
        : ratio;
  }
  if (properties.containsKey('duration') &&
      !definition.durationComesFromSource(mode)) {
    final duration = input['duration'] ?? definition.minDuration;
    if (duration == 'auto') {
      if (!definition.supportsAutoDuration) {
        _invalid('This APIPod route requires a fixed duration.');
      }
      payload['duration'] = -1;
    } else {
      if (duration is! num ||
          !duration.isFinite ||
          duration != duration.roundToDouble()) {
        _invalid('APIPod requires a whole-number duration.');
      }
      final allowed = definition.durationRangeFor(
        resolution,
        withImageGuidance: frames.isNotEmpty || images.isNotEmpty,
      );
      if (duration < allowed.minimumSeconds ||
          duration > allowed.maximumSeconds ||
          (definition.durationOptions.isNotEmpty &&
              !definition.durationOptions.contains(duration.toInt())) ||
          (duration - definition.minDuration) % definition.durationStep != 0) {
        _invalid(
          'The duration is outside this APIPod route’s supported range.',
        );
      }
      payload['duration'] = duration.toInt();
    }
  }
  if (properties.containsKey('generate_audio')) {
    final audio = input['generate_audio'] ?? true;
    if (audio is! bool) {
      _invalid('The APIPod audio setting must be true or false.');
    }
    payload['generate_audio'] = audio;
  }
  if (input['seed'] != null) {
    if (!properties.containsKey('seed')) {
      _invalid('This APIPod route does not support a seed.');
    }
    payload['seed'] = input['seed'];
  }

  _mapImages(
    payload,
    properties,
    frames,
    images,
    frameRoles: input['_clawnsole_keyframe_roles'],
  );
  _mapMedia(payload, properties, 'video', <String>[
    if (source != null) source,
    ...videos,
  ]);
  _mapMedia(payload, properties, 'audio', audios);
  if (properties.containsKey('role') &&
      (frames.isNotEmpty || images.isNotEmpty)) {
    payload['role'] = frames.isNotEmpty
        ? 'first_last_frame'
        : 'reference_images';
  }
  // A separate model, rather than a generic draft flag, selects the preview.
  if (definition.draftSourceIsTaskId && resolution != 'sd') {
    _invalid(
      'APIPod draft previews require 480p; enhance a completed draft for 1080p.',
    );
  }
  if (model == 'kling-4.0-i2v' &&
      payload['duration'] is int &&
      frames.length > (payload['duration']! as int) + 1) {
    _invalid('Kling 4.0 allows at most duration + 1 pinned frames, up to 10.');
  }
  // The only non-media required fields are scalar form controls. Supply a
  // declared valid default when the API requires it but it has no app control.
  for (final raw in _list(schema['required'])) {
    final field = raw.toString();
    if (payload.containsKey(field)) continue;
    final rule = _map(properties[field]);
    final fallback = rule['default'];
    if (fallback != null && _fieldAllows(rule, fallback)) {
      payload[field] = fallback;
    }
  }
  _validatePayload(schema, payload);
  return payload;
}

Map<String, Object?> _draftFinal(
  String model,
  VideoModelDefinition definition,
  Map<String, Object?> properties,
  Map<String, Object?> input,
) {
  if (!definition.draftSourceIsTaskId ||
      !properties.containsKey('draft_task_id')) {
    _invalid('This APIPod route does not support draft finalization.');
  }
  final id = input['draft_task_id'] ?? input['draft_cache'];
  if (id is! String || !RegExp(r'^[A-Za-z0-9_-]{1,256}$').hasMatch(id)) {
    _invalid(
      'Enter the APIPod task ID of a completed draft from the last seven days.',
    );
  }
  for (final field in const [
    'prompt',
    'duration',
    'aspect_ratio',
    'generate_audio',
    'seed',
    'keyframes',
    'reference_images',
    'reference_videos',
    'reference_audios',
    'start_video',
    'input_video',
  ]) {
    final value = input[field];
    if (value != null && value != '' && !(value is List && value.isEmpty)) {
      _invalid('APIPod finalization reuses the draft; do not resend $field.');
    }
  }
  final resolution = input['resolution'] ?? 'fhd';
  if (resolution != 'fhd') {
    _invalid('APIPod draft finalization requires 1080p.');
  }
  final payload = <String, Object?>{
    'model': model,
    'draft_task_id': id,
    'resolution': _wireResolution('fhd', _map(properties['resolution'])),
  };
  // The draft stage's required prompt/media fields are deliberately absent
  // for finalization; the published two-stage contract reuses them server-side.
  for (final entry in payload.entries) {
    if (!_fieldAllows(_map(properties[entry.key]), entry.value)) {
      _invalid('The APIPod finalization field ${entry.key} is invalid.');
    }
  }
  return payload;
}

void _mapImages(
  Map<String, Object?> payload,
  Map<String, Object?> properties,
  List<String> frames,
  List<String> images, {
  Object? frameRoles,
}) {
  var remainingFrames = frames;
  if (frames.isNotEmpty && properties.containsKey('first_frame_image')) {
    payload['first_frame_image'] = frames.first;
    if (frames.length > 1) {
      if (!properties.containsKey('last_frame_image') || frames.length > 2) {
        _invalid('This APIPod route does not support these pinned frames.');
      }
      payload['last_frame_image'] = frames.last;
    }
    remainingFrames = const [];
  }
  if (properties.containsKey('keyframe_urls') && remainingFrames.isNotEmpty) {
    if (frameRoles != null) {
      if (frameRoles is! List ||
          frameRoles.length != remainingFrames.length ||
          frameRoles.any(
            (role) => !const ['start', 'middle', 'end'].contains(role),
          ) ||
          frameRoles.first != 'start' ||
          frameRoles.where((role) => role == 'start').length != 1 ||
          frameRoles.where((role) => role == 'end').length > 1 ||
          (frameRoles.contains('end') && frameRoles.last != 'end')) {
        _invalid('The ordered APIPod keyframe roles are invalid.');
      }
      payload['image_urls'] = <String>[
        remainingFrames.first,
        if (frameRoles.last == 'end') remainingFrames.last,
      ];
      final middle = <String>[
        for (var i = 0; i < remainingFrames.length; i++)
          if (frameRoles[i] == 'middle') remainingFrames[i],
      ];
      if (middle.isNotEmpty) payload['keyframe_urls'] = middle;
      remainingFrames = const [];
    } else if (remainingFrames.length > 2) {
      payload['image_urls'] = [remainingFrames.first, remainingFrames.last];
      payload['keyframe_urls'] = remainingFrames.sublist(
        1,
        remainingFrames.length - 1,
      );
      remainingFrames = const [];
    }
  }
  final combined = <String>[...remainingFrames, ...images];
  if (combined.isEmpty) return;
  if (properties.containsKey('image_urls') &&
      !payload.containsKey('image_urls')) {
    payload['image_urls'] = combined;
  } else if (properties.containsKey('image_url') && combined.length == 1) {
    payload['image_url'] = combined.single;
  } else {
    _invalid('This APIPod route cannot represent the selected images.');
  }
}

void _mapMedia(
  Map<String, Object?> payload,
  Map<String, Object?> properties,
  String kind,
  List<String> sources,
) {
  if (sources.isEmpty) return;
  if (properties.containsKey('${kind}_urls')) {
    payload['${kind}_urls'] = sources;
  } else if (properties.containsKey('${kind}_url') && sources.length == 1) {
    payload['${kind}_url'] = sources.single;
  } else {
    _invalid('This APIPod route cannot represent the selected $kind inputs.');
  }
}

String _wireResolution(String resolution, Map<String, Object?> rule) {
  final candidates = switch (resolution) {
    'sd' => const ['480p', 'sd'],
    'hd' => const ['720p', '768p', 'hd', 'std'],
    'fhd' => const ['1080p', 'fhd', 'pro'],
    'qhd' => const ['2k', '1440p'],
    '4k' => const ['4k', '2160p'],
    _ => [resolution.toLowerCase()],
  };
  final wire = _list(rule['enum'])
      .whereType<String>()
      .where((value) => candidates.contains(value.toLowerCase()))
      .firstOrNull;
  if (wire == null) _invalid('APIPod does not define this output resolution.');
  return wire;
}

String _translatePrompt(
  String prompt, {
  required String model,
  required int videoOffset,
  required Iterable<PromptReferenceMention> available,
}) {
  final result = StringBuffer();
  var offset = 0;
  for (final match in promptReferenceMatches(prompt, available: available)) {
    result.write(prompt.substring(offset, match.start));
    final mention = match.mention;
    final number =
        mention.number +
        (mention.kind == MediaReferenceKind.video ? videoOffset : 0);
    // Kling 4 documents underscore placeholders; Seedance and Wan use compact
    // tags. Other routes accept ordinary ordered reference descriptions.
    result.write(
      model.startsWith('kling-4.0-')
          ? '@${mention.kind.name}_$number'
          : model.startsWith('seedance-') || model.startsWith('wan')
          ? '@${mention.kind.name}$number'
          : '${mention.kind.name} $number',
    );
    offset = match.end;
  }
  result.write(prompt.substring(offset));
  return result.toString();
}

void _validatePayload(
  Map<String, Object?> schema,
  Map<String, Object?> payload,
) {
  final properties = _map(schema['properties']);
  for (final raw in _list(schema['required'])) {
    if (!payload.containsKey(raw)) _invalid('APIPod requires the $raw field.');
  }
  for (final entry in payload.entries) {
    if (!properties.containsKey(entry.key) ||
        !_fieldAllows(_map(properties[entry.key]), entry.value)) {
      _invalid(
        'The ${entry.key} field does not satisfy this APIPod route’s API contract.',
      );
    }
  }
}

bool _fieldAllows(Map<String, Object?> rule, Object? value) {
  if (rule.isEmpty) return true;
  if (rule.containsKey('const') && rule['const'] != value) return false;
  final choices = _list(rule['enum']);
  // APIPod models Auto as the -1 enum alongside a positive slider range.
  final autoRange =
      choices.length == 1 &&
      choices.first == -1 &&
      rule['minimum'] is num &&
      rule['maximum'] is num;
  if (choices.isNotEmpty && !choices.contains(value) && !autoRange) {
    return false;
  }
  switch (rule['type']) {
    case 'string':
      if (value is! String) return false;
      if (rule['minLength'] case final num minimum) {
        if (value.length < minimum) return false;
      }
      if (rule['maxLength'] case final num maximum) {
        if (value.length > maximum) return false;
      }
    case 'integer':
      if (value is! num || !value.isFinite || value != value.roundToDouble()) {
        return false;
      }
    case 'number':
      if (value is! num || !value.isFinite) return false;
    case 'boolean':
      if (value is! bool) return false;
    case 'array':
      if (value is! List) return false;
      if (rule['minItems'] case final num minimum) {
        if (value.length < minimum) return false;
      }
      if (rule['maxItems'] case final num maximum) {
        if (value.length > maximum) return false;
      }
      final itemRule = _map(rule['items']);
      if (itemRule.isNotEmpty &&
          value.any((item) => !_fieldAllows(itemRule, item))) {
        return false;
      }
    case 'object':
      if (value is! Map) return false;
  }
  if (value is num && !(autoRange && value == -1)) {
    if (rule['minimum'] case final num minimum) {
      if (value < minimum) return false;
    }
    if (rule['maximum'] case final num maximum) {
      if (value > maximum) return false;
    }
  }
  return true;
}

String? _sourceVideo(Map<String, Object?> input) {
  final values = [
    input['start_video'],
    input['input_video'],
  ].where((value) => value != null && value != '').toList();
  if (values.length > 1 && values.toSet().length > 1) {
    _invalid('Provide one source video.');
  }
  return values.isEmpty ? null : _sources([values.first]).single;
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
        'APIPod requires public HTTPS media URLs; its API does not support local uploads.',
      );
    }
    final url = validatedProviderUrl(source);
    if (url.hasFragment) {
      _invalid('APIPod media URLs cannot contain fragments.');
    }
    return url.toString();
  }).toList();
}

Map<String, Object?> _map(Object? value) => value is Map
    ? value.map((key, child) => MapEntry(key.toString(), child))
    : const {};
List<Object?> _list(Object? value) =>
    value is List ? value.cast<Object?>() : const [];
Never _invalid(String message) => throw ProviderException(message, status: 400);
