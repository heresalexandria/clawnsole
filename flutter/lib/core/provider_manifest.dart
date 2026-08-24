import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';

import 'app_version.dart';
import 'models.dart';
import 'provider_catalog.dart';
import 'update_check.dart';

const clawnsoleSiteUrl = String.fromEnvironment(
  'CLAWNSOLE_SITE_URL',
  defaultValue: 'https://clawnsole.app/',
);

const supportedProviderAdapters = <String>{
  'apple-local',
  'artcraft',
  'atlas',
  'bfl',
  'ltx',
  'runway',
};

class ProviderCatalogManifestException implements Exception {
  const ProviderCatalogManifestException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ProviderCatalogBundle {
  const ProviderCatalogBundle({
    required this.providers,
    required this.cache,
    required this.isMobileTest,
  });

  final List<VideoProviderDefinition> providers;
  final Map<String, Object?> cache;
  final bool isMobileTest;

  factory ProviderCatalogBundle.fromCache(
    Map<String, Object?> cache, {
    String appVersion = clawnsoleVersion,
    bool mobileTestBuild = clawnsoleMobileTestBuild,
  }) {
    if (_integer(cache['schema_version']) != 1) {
      throw const ProviderCatalogManifestException(
        'The model catalog cache uses an unsupported schema.',
      );
    }
    final rawProviders = _list(cache['providers']);
    final providers = <VideoProviderDefinition>[];
    final providerIds = <String>{};
    for (final raw in rawProviders) {
      final manifest = _map(raw, 'provider');
      if (_integer(manifest['schema_version']) != 1) {
        throw const ProviderCatalogManifestException(
          'A provider manifest uses an unsupported schema.',
        );
      }
      if (!_availableForVersion(manifest['availability'], appVersion)) {
        continue;
      }
      final adapter = _requiredString(manifest, 'adapter');
      if (!supportedProviderAdapters.contains(adapter)) continue;
      final id = _requiredString(manifest, 'id');
      if (!providerIds.add(id)) {
        throw ProviderCatalogManifestException(
          'The model catalog contains provider "$id" more than once.',
        );
      }
      final models = <VideoModelDefinition>[];
      final modelIds = <String>{};
      for (final rawModel in _list(manifest['models'])) {
        final modelManifest = _map(rawModel, 'model');
        if (_integer(modelManifest['schema_version']) != 1) {
          throw const ProviderCatalogManifestException(
            'A model manifest uses an unsupported schema.',
          );
        }
        if (!_availableForVersion(modelManifest['availability'], appVersion)) {
          continue;
        }
        final model = _parseModel(modelManifest);
        if (!modelIds.add(model.id)) {
          throw ProviderCatalogManifestException(
            'Provider "$id" contains model "${model.id}" more than once.',
          );
        }
        models.add(model);
      }
      if (models.isEmpty) continue;
      providers.add(_parseProvider(manifest, models));
    }
    if (providers.isEmpty) {
      throw const ProviderCatalogManifestException(
        'The model catalog has no providers compatible with this app.',
      );
    }
    final catalogVersion = _catalogVersion(cache['catalog_version']);
    final catalogCoversApp =
        catalogVersion != null &&
        (compareSemanticVersions(catalogVersion, appVersion) ?? -1) >= 0;
    final isMobileTest =
        mobileTestBuild &&
        (_testVersions(cache['test_versions']).contains(appVersion) ||
            !catalogCoversApp);
    final activeProviders = isMobileTest
        ? mobileTestProviderCatalog(providers)
        : providers;
    if (activeProviders.isEmpty) {
      throw const ProviderCatalogManifestException(
        'The mobile test catalog requires ArtCraft Seedance 1.5 Pro at 480p and 5 seconds.',
      );
    }
    return ProviderCatalogBundle(
      providers: List<VideoProviderDefinition>.unmodifiable(activeProviders),
      cache: _stringMap(cache),
      isMobileTest: isMobileTest,
    );
  }
}

class ProviderCatalogClient {
  ProviderCatalogClient({
    http.Client? client,
    Uri? siteUrl,
    this.requestTimeout = const Duration(seconds: 8),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       siteUrl = _normalizeSiteUrl(siteUrl ?? Uri.parse(clawnsoleSiteUrl));

  final http.Client _client;
  final bool _ownsClient;
  final Uri siteUrl;
  final Duration requestTimeout;

  Uri get catalogUrl => siteUrl.resolve('models/');

  Future<ProviderCatalogBundle> fetch({
    String appVersion = clawnsoleVersion,
    bool mobileTestBuild = clawnsoleMobileTestBuild,
  }) async {
    final index = _yamlMap(await _get(catalogUrl), catalogUrl);
    if (_integer(index['schema_version']) != 1) {
      throw const ProviderCatalogManifestException(
        'The remote model catalog uses an unsupported schema.',
      );
    }
    final providerPaths = _list(
      index['providers'],
    ).map((value) => _relativePath(value, 'provider')).toList();
    final providerEntries = await Future.wait(
      providerPaths.map((path) async {
        final providerUrl = _catalogResource(path);
        final provider = _yamlMap(await _get(providerUrl), providerUrl);
        final modelPaths = _list(
          provider['models'],
        ).map((value) => _relativePath(value, 'model')).toList();
        final models = await Future.wait(
          modelPaths.map((modelPath) async {
            final modelUrl = _catalogResource(modelPath);
            return _yamlMap(await _get(modelUrl), modelUrl);
          }),
        );
        return <String, Object?>{...provider, 'models': models};
      }),
    );
    return ProviderCatalogBundle.fromCache(
      <String, Object?>{
        'schema_version': 1,
        'catalog_version': _catalogVersion(index['catalog_version']),
        'test_versions': _testVersions(index['test_versions']),
        'providers': providerEntries,
      },
      appVersion: appVersion,
      mobileTestBuild: mobileTestBuild,
    );
  }

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<String> _get(Uri url) async {
    final response = await _client
        .get(url, headers: const <String, String>{'Accept': 'application/yaml'})
        .timeout(requestTimeout);
    if (response.statusCode != 200) {
      throw ProviderCatalogManifestException(
        'The model catalog returned HTTP ${response.statusCode} for $url.',
      );
    }
    if (response.bodyBytes.length > 1024 * 1024) {
      throw ProviderCatalogManifestException(
        'The model catalog resource at $url is too large.',
      );
    }
    return utf8.decode(response.bodyBytes);
  }

  Uri _catalogResource(String path) {
    final resolved = catalogUrl.resolve(path);
    final prefix = catalogUrl.path.endsWith('/')
        ? catalogUrl.path
        : '${catalogUrl.path}/';
    if (resolved.scheme != catalogUrl.scheme ||
        resolved.host != catalogUrl.host ||
        resolved.port != catalogUrl.port ||
        !resolved.path.startsWith(prefix) ||
        resolved.query.isNotEmpty ||
        resolved.fragment.isNotEmpty) {
      throw ProviderCatalogManifestException(
        'The model catalog contains an unsafe path: $path.',
      );
    }
    return resolved;
  }
}

Uri _normalizeSiteUrl(Uri value) {
  if (value.scheme != 'https' || value.host.isEmpty) {
    throw const ProviderCatalogManifestException(
      'CLAWNSOLE_SITE_URL must be an HTTPS origin.',
    );
  }
  return value.replace(
    path: value.path.endsWith('/') ? value.path : '${value.path}/',
    query: null,
    fragment: null,
  );
}

Map<String, Object?> _yamlMap(String source, Uri url) {
  Object? decoded;
  try {
    decoded = loadYaml(source);
  } on YamlException catch (error) {
    throw ProviderCatalogManifestException(
      'The model catalog contains invalid YAML at $url: ${error.message}',
    );
  }
  final plain = _plainYaml(decoded);
  if (plain is! Map<String, Object?>) {
    throw ProviderCatalogManifestException(
      'The model catalog resource at $url must be a YAML mapping.',
    );
  }
  return plain;
}

Object? _plainYaml(Object? value) => switch (value) {
  final YamlMap map => <String, Object?>{
    for (final entry in map.entries)
      entry.key.toString(): _plainYaml(entry.value),
  },
  final Map<Object?, Object?> map => <String, Object?>{
    for (final entry in map.entries)
      entry.key.toString(): _plainYaml(entry.value),
  },
  final Iterable<Object?> values => values.map(_plainYaml).toList(),
  _ => value,
};

Map<String, Object?> _stringMap(Map<String, Object?> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, Object?>;

Map<String, Object?> _map(Object? value, String label) {
  if (value is Map<String, Object?>) return value;
  if (value is Map<Object?, Object?>) {
    return value.map((key, child) => MapEntry(key.toString(), child));
  }
  throw ProviderCatalogManifestException(
    'Each $label manifest must be a YAML mapping.',
  );
}

List<Object?> _list(Object? value) => switch (value) {
  final List<Object?> values => values,
  null => const <Object?>[],
  _ => throw const ProviderCatalogManifestException(
    'A model catalog list has an invalid value.',
  ),
};

List<String> _testVersions(Object? raw) {
  final versions = _list(raw).map((value) {
    if (value is! String || parseSemanticVersion(value.trim()) == null) {
      throw const ProviderCatalogManifestException(
        'test_versions must contain semantic app versions.',
      );
    }
    return value.trim();
  }).toList();
  if (versions.toSet().length != versions.length) {
    throw const ProviderCatalogManifestException(
      'test_versions must not contain duplicates.',
    );
  }
  return versions;
}

String? _catalogVersion(Object? raw) {
  if (raw == null) return null;
  if (raw is! String || parseSemanticVersion(raw.trim()) == null) {
    throw const ProviderCatalogManifestException(
      'catalog_version must be a semantic app version.',
    );
  }
  return raw.trim();
}

String _relativePath(Object? value, String label) {
  final path = value?.toString().trim() ?? '';
  if (path.isEmpty || path.startsWith('/') || path.contains('\\')) {
    throw ProviderCatalogManifestException(
      'The model catalog contains an invalid $label path.',
    );
  }
  return path;
}

bool _availableForVersion(Object? raw, String appVersion) {
  if (raw == null) return true;
  final availability = _map(raw, 'availability');
  final exact = _optionalString(availability, 'version');
  final minimum = _optionalString(availability, 'min_version');
  final maximum = _optionalString(availability, 'max_version');
  if (parseSemanticVersion(appVersion) == null) {
    throw ProviderCatalogManifestException(
      'The running app version "$appVersion" is invalid.',
    );
  }
  for (final constraint in <String?>[exact, minimum, maximum]) {
    if (constraint != null && parseSemanticVersion(constraint) == null) {
      throw ProviderCatalogManifestException(
        'The model catalog contains invalid app version "$constraint".',
      );
    }
  }
  if (minimum != null &&
      maximum != null &&
      (compareSemanticVersions(minimum, maximum) ?? 1) > 0) {
    throw const ProviderCatalogManifestException(
      'A model catalog minimum version exceeds its maximum version.',
    );
  }
  if (exact != null &&
      ((minimum != null &&
              (compareSemanticVersions(exact, minimum) ?? -1) < 0) ||
          (maximum != null &&
              (compareSemanticVersions(exact, maximum) ?? 1) > 0))) {
    throw const ProviderCatalogManifestException(
      'A model catalog exact version falls outside its version range.',
    );
  }
  if (exact != null && compareSemanticVersions(appVersion, exact) != 0) {
    return false;
  }
  if (minimum != null &&
      (compareSemanticVersions(appVersion, minimum) ?? -1) < 0) {
    return false;
  }
  if (maximum != null &&
      (compareSemanticVersions(appVersion, maximum) ?? 1) > 0) {
    return false;
  }
  return true;
}

VideoProviderDefinition _parseProvider(
  Map<String, Object?> manifest,
  List<VideoModelDefinition> models,
) {
  final delivery = manifest['result_delivery'] == null
      ? const <String, Object?>{}
      : _map(manifest['result_delivery'], 'result delivery');
  final seconds = _optionalInteger(delivery, 'availability_seconds');
  return VideoProviderDefinition(
    id: _requiredString(manifest, 'id'),
    adapter: _requiredString(manifest, 'adapter'),
    name: _requiredString(manifest, 'name'),
    description: _requiredString(manifest, 'description'),
    consoleUrl: _requiredHttpsUrl(manifest, 'console_url'),
    docsUrl: _requiredHttpsUrl(manifest, 'docs_url'),
    pricingUrl: _requiredHttpsUrl(manifest, 'pricing_url'),
    pricingSource:
        _optionalString(manifest, 'pricing_source') ?? 'Published rate card',
    requiresApiKey: _boolean(manifest, 'requires_api_key', fallback: true),
    isLocal: _boolean(manifest, 'is_local'),
    resultDelivery: ProviderResultDelivery(
      availability: seconds == null ? null : Duration(seconds: seconds),
      keepOpenRecommended: _boolean(delivery, 'keep_open_recommended'),
    ),
    progressReporting: _progress(manifest['progress_reporting']),
    models: List<VideoModelDefinition>.unmodifiable(models),
  );
}

VideoModelDefinition _parseModel(Map<String, Object?> manifest) {
  final modes = _list(
    manifest['modes'],
  ).map(_videoMode).toList(growable: false);
  final resolutions = _list(manifest['resolutions'])
      .map((raw) {
        final value = _map(raw, 'resolution');
        return VideoResolutionDefinition(
          _requiredString(value, 'id'),
          _requiredString(value, 'label'),
          _requiredString(value, 'detail'),
        );
      })
      .toList(growable: false);
  if (modes.isEmpty || resolutions.isEmpty) {
    throw const ProviderCatalogManifestException(
      'Every model needs at least one mode and resolution.',
    );
  }
  return VideoModelDefinition(
    id: _requiredString(manifest, 'id'),
    canonicalModelId: _optionalString(manifest, 'canonical_model_id'),
    label: _requiredString(manifest, 'label'),
    description: _requiredString(manifest, 'description'),
    modes: modes,
    aspectRatios: _strings(manifest, 'aspect_ratios', required: true),
    resolutions: resolutions,
    minDuration: _requiredInteger(manifest, 'min_duration'),
    maxDuration: _requiredInteger(manifest, 'max_duration'),
    durationStep: _requiredInteger(manifest, 'duration_step'),
    maxKeyframes: _requiredInteger(manifest, 'max_keyframes'),
    maxKeyframesByMode: _modeIntegerMap(manifest['max_keyframes_by_mode']),
    usdPerSecond: _requiredDouble(manifest, 'usd_per_second'),
    referenceUsdPerSecond: _optionalDouble(
      manifest,
      'reference_usd_per_second',
    ),
    supportsStartFrame: _boolean(manifest, 'supports_start_frame'),
    supportsEndFrame: _boolean(manifest, 'supports_end_frame'),
    maxImageReferences: _integer(manifest['max_image_references']) ?? 0,
    maxVideoReferences: _integer(manifest['max_video_references']) ?? 0,
    maxAudioReferences: _integer(manifest['max_audio_references']) ?? 0,
    maxTotalReferences: _integer(manifest['max_total_references']),
    maxReferencesByMode: _referenceLimits(manifest['max_references_by_mode']),
    framesExclusiveWithReferences: _boolean(
      manifest,
      'frames_exclusive_with_references',
    ),
    maxReferenceVideoSeconds: _integer(manifest['max_reference_video_seconds']),
    maxReferenceAudioSeconds: _integer(manifest['max_reference_audio_seconds']),
    minReferenceAudioSeconds: _integer(manifest['min_reference_audio_seconds']),
    maxReferenceVideoSecondsByResolution: _stringIntegerMap(
      manifest['max_reference_video_seconds_by_resolution'],
    ),
    maxReferenceAudioSecondsByResolution: _stringIntegerMap(
      manifest['max_reference_audio_seconds_by_resolution'],
    ),
    requiresVisualReferenceForAudio: _boolean(
      manifest,
      'requires_visual_reference_for_audio',
    ),
    maxDurationWithImageGuidance: _integer(
      manifest['max_duration_with_image_guidance'],
    ),
    maxDurationByResolution: _stringIntegerMap(
      manifest['max_duration_by_resolution'],
    ),
    aspectRatiosByResolution: _stringListMap(
      manifest['aspect_ratios_by_resolution'],
    ),
    aspectRatiosByMode: _modeListMap(manifest['aspect_ratios_by_mode']),
    aspectRatiosWithFrames: manifest.containsKey('aspect_ratios_with_frames')
        ? _strings(manifest, 'aspect_ratios_with_frames')
        : null,
    resolutionsByReferenceKind: _referenceListMap(
      manifest['resolutions_by_reference_kind'],
    ),
    referencePromptHint: _optionalString(manifest, 'reference_prompt_hint'),
    referenceTasks: manifest.containsKey('reference_tasks')
        ? _list(manifest['reference_tasks']).map(_referenceTask).toList()
        : const <MediaReferenceTask>[MediaReferenceTask.reference],
    supportsAutoDuration: _boolean(manifest, 'supports_auto_duration'),
    supportsAudio: _boolean(manifest, 'supports_audio', fallback: true),
    supportsDraft: _boolean(manifest, 'supports_draft'),
    supportsTimedKeyframes: _boolean(manifest, 'supports_timed_keyframes'),
    supportsFrameRate: _boolean(manifest, 'supports_frame_rate'),
    supportsSeed: _boolean(manifest, 'supports_seed'),
    maxPromptCharacters: _integer(manifest['max_prompt_characters']),
    promptOptionalModes: _list(
      manifest['prompt_optional_modes'],
    ).map(_videoMode).toList(),
    promptOptionalWithFramesOnly: _boolean(
      manifest,
      'prompt_optional_with_frames_only',
    ),
    minSourceVideoSeconds: _integer(manifest['min_source_video_seconds']),
    maxSourceVideoSeconds: _integer(manifest['max_source_video_seconds']),
    durationFromSourceModes: _list(
      manifest['duration_from_source_modes'],
    ).map(_videoMode).toList(),
    sourceInputLabel: _optionalString(manifest, 'source_input_label'),
    sourceInputHint: _optionalString(manifest, 'source_input_hint'),
    supportsGuidanceWithSource: _boolean(
      manifest,
      'supports_guidance_with_source',
    ),
    sourceGuidanceRequiresTimestamps: _boolean(
      manifest,
      'source_guidance_requires_timestamps',
    ),
    upscaleUsesResolutionTargets: _boolean(
      manifest,
      'upscale_uses_resolution_targets',
    ),
    outputKind: _outputKind(manifest['output_kind']),
    progressReporting: manifest['progress_reporting'] == null
        ? null
        : _progress(manifest['progress_reporting']),
  );
}

String _requiredHttpsUrl(Map<String, Object?> value, String key) {
  final raw = _requiredString(value, key);
  final uri = Uri.tryParse(raw);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    throw ProviderCatalogManifestException('$key must be an HTTPS URL.');
  }
  return raw;
}

String _requiredString(Map<String, Object?> value, String key) {
  final result = _optionalString(value, key);
  if (result == null) {
    throw ProviderCatalogManifestException('$key is required.');
  }
  return result;
}

String? _optionalString(Map<String, Object?> value, String key) {
  final raw = value[key];
  if (raw == null) return null;
  if (raw is! String || raw.trim().isEmpty) {
    throw ProviderCatalogManifestException('$key must be a non-empty string.');
  }
  return raw.trim();
}

int _requiredInteger(Map<String, Object?> value, String key) {
  final result = _integer(value[key]);
  if (result == null) {
    throw ProviderCatalogManifestException('$key must be an integer.');
  }
  return result;
}

int? _optionalInteger(Map<String, Object?> value, String key) {
  if (!value.containsKey(key)) return null;
  final result = _integer(value[key]);
  if (result == null) {
    throw ProviderCatalogManifestException('$key must be an integer.');
  }
  return result;
}

int? _integer(Object? value) => value is int
    ? value
    : value is num && value == value.roundToDouble()
    ? value.toInt()
    : null;

double _requiredDouble(Map<String, Object?> value, String key) {
  final result = _optionalDouble(value, key);
  if (result == null) {
    throw ProviderCatalogManifestException('$key must be a number.');
  }
  return result;
}

double? _optionalDouble(Map<String, Object?> value, String key) {
  final raw = value[key];
  if (raw == null) return null;
  if (raw is! num || !raw.isFinite) {
    throw ProviderCatalogManifestException('$key must be a finite number.');
  }
  return raw.toDouble();
}

bool _boolean(Map<String, Object?> value, String key, {bool fallback = false}) {
  final raw = value[key];
  if (raw == null) return fallback;
  if (raw is! bool) {
    throw ProviderCatalogManifestException('$key must be true or false.');
  }
  return raw;
}

List<String> _strings(
  Map<String, Object?> value,
  String key, {
  bool required = false,
}) {
  final result = _list(value[key]).map((item) {
    if (item is! String || item.trim().isEmpty) {
      throw ProviderCatalogManifestException('$key must contain strings.');
    }
    return item.trim();
  }).toList();
  if (required && result.isEmpty) {
    throw ProviderCatalogManifestException('$key cannot be empty.');
  }
  return result;
}

Map<String, int> _stringIntegerMap(Object? raw) =>
    _mapOrEmpty(raw).map((key, value) {
      final parsed = _integer(value);
      if (parsed == null) {
        throw const ProviderCatalogManifestException(
          'A model catalog limit must be an integer.',
        );
      }
      return MapEntry(key, parsed);
    });

Map<String, List<String>> _stringListMap(Object? raw) =>
    _mapOrEmpty(raw).map((key, value) => MapEntry(key, _stringList(value)));

Map<VideoMode, int> _modeIntegerMap(Object? raw) =>
    _mapOrEmpty(raw).map((key, value) {
      final parsed = _integer(value);
      if (parsed == null) {
        throw const ProviderCatalogManifestException(
          'A model catalog limit must be an integer.',
        );
      }
      return MapEntry(_videoMode(key), parsed);
    });

Map<VideoMode, List<String>> _modeListMap(Object? raw) => _mapOrEmpty(
  raw,
).map((key, value) => MapEntry(_videoMode(key), _stringList(value)));

Map<MediaReferenceKind, List<String>> _referenceListMap(Object? raw) =>
    _mapOrEmpty(
      raw,
    ).map((key, value) => MapEntry(_referenceKind(key), _stringList(value)));

Map<VideoMode, Map<MediaReferenceKind, int>> _referenceLimits(Object? raw) =>
    _mapOrEmpty(raw).map(
      (mode, values) => MapEntry(
        _videoMode(mode),
        _map(values, 'reference limits').map((kind, limit) {
          final parsed = _integer(limit);
          if (parsed == null) {
            throw const ProviderCatalogManifestException(
              'A reference limit must be an integer.',
            );
          }
          return MapEntry(_referenceKind(kind), parsed);
        }),
      ),
    );

Map<String, Object?> _mapOrEmpty(Object? raw) =>
    raw == null ? const <String, Object?>{} : _map(raw, 'model catalog value');

List<String> _stringList(Object? raw) => _list(raw).map((value) {
  if (value is! String || value.trim().isEmpty) {
    throw const ProviderCatalogManifestException(
      'A model catalog list must contain strings.',
    );
  }
  return value.trim();
}).toList();

VideoMode _videoMode(Object? raw) => switch (raw?.toString()) {
  't2v' => VideoMode.t2v,
  'i2v' => VideoMode.i2v,
  'v2v' => VideoMode.v2v,
  'draft_enhance' => VideoMode.draftEnhance,
  'upscale' => VideoMode.upscale,
  _ => throw ProviderCatalogManifestException('Unknown video mode "$raw".'),
};

MediaReferenceKind _referenceKind(Object? raw) =>
    MediaReferenceKind.values.firstWhere(
      (value) => value.name == raw,
      orElse: () => throw ProviderCatalogManifestException(
        'Unknown reference kind "$raw".',
      ),
    );

MediaReferenceTask _referenceTask(Object? raw) =>
    MediaReferenceTask.values.firstWhere(
      (value) => value.name == raw,
      orElse: () => throw ProviderCatalogManifestException(
        'Unknown reference task "$raw".',
      ),
    );

ProviderProgressReporting _progress(Object? raw) =>
    ProviderProgressReporting.values.firstWhere(
      (value) => value.name == (raw?.toString() ?? 'none'),
      orElse: () => throw ProviderCatalogManifestException(
        'Unknown progress reporting value "$raw".',
      ),
    );

GenerationOutputKind _outputKind(Object? raw) =>
    GenerationOutputKind.values.firstWhere(
      (value) => value.name == (raw?.toString() ?? 'video'),
      orElse: () =>
          throw ProviderCatalogManifestException('Unknown output kind "$raw".'),
    );
