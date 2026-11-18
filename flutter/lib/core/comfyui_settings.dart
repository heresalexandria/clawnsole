import 'dart:convert';

/// User-owned, API-format graphs. They live in settings, never in generation
/// history. Version one adds no migration burden to existing empty settings.
class ComfyUiSettings {
  const ComfyUiSettings({
    this.serverUrl = '',
    this.workflows = const <String, ComfyUiWorkflow>{},
  });

  final String serverUrl;
  final Map<String, ComfyUiWorkflow> workflows;

  bool get isConfigured {
    try {
      validate();
      return true;
    } on Object {
      return false;
    }
  }

  void validate() {
    comfyUiServerUri(serverUrl);
    if (workflows.isEmpty) {
      throw const FormatException('Import at least one ComfyUI workflow.');
    }
    for (final entry in workflows.entries) {
      if (!const {'comfyui-video', 'comfyui-image'}.contains(entry.key)) {
        throw const FormatException('Unsupported ComfyUI workflow type.');
      }
      entry.value.validate();
    }
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'serverUrl': serverUrl,
    'workflows': {
      for (final entry in workflows.entries) entry.key: entry.value.toJson(),
    },
  };

  factory ComfyUiSettings.fromJson(Object? value) {
    if (value is! Map || value['schemaVersion'] != 1) {
      return const ComfyUiSettings();
    }
    final raw = value['workflows'];
    return ComfyUiSettings(
      serverUrl: value['serverUrl'] is String
          ? value['serverUrl'] as String
          : '',
      workflows: {
        if (raw is Map)
          for (final entry in raw.entries)
            if (entry.key is String && entry.value is Map)
              entry.key as String: ComfyUiWorkflow.fromJson(entry.value as Map),
      },
    );
  }
}

Uri comfyUiServerUri(String source) {
  final uri = Uri.tryParse(source.trim());
  if (uri == null ||
      !const {'http', 'https'}.contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw const FormatException(
      'Use a ComfyUI HTTP or HTTPS server URL without credentials, query, or fragment.',
    );
  }
  return uri.replace(path: '${uri.path.replaceFirst(RegExp(r'/+$'), '')}/');
}

class ComfyUiWorkflow {
  const ComfyUiWorkflow({required this.json, required this.outputNodeId});

  final String json;
  final String outputNodeId;

  static const maxBytes = 128 * 1024;
  static const placeholders = <String>{
    'prompt',
    'seed',
    'width',
    'height',
    'duration',
    'fps',
    'frames',
  };

  Map<String, Object?> validate() {
    if (utf8.encode(json).length > maxBytes) {
      throw const FormatException('A workflow must be smaller than 128 KB.');
    }
    final value = jsonDecode(json);
    if (value is! Map<String, Object?> ||
        value.isEmpty ||
        value.containsKey('nodes') ||
        value.containsKey('links')) {
      throw const FormatException(
        'Export the workflow in API format from ComfyUI (not the editor workflow).',
      );
    }
    if (!value.containsKey(outputNodeId.trim())) {
      throw const FormatException(
        'The output node ID is not in this workflow.',
      );
    }
    var hasPrompt = false;
    void inspect(Object? child) {
      if (child is String) {
        if (child.startsWith('data:')) {
          throw const FormatException('Workflow settings cannot embed media.');
        }
        for (final match in RegExp(r'\{\{([^{}]+)\}\}').allMatches(child)) {
          final name = match.group(1)!;
          if (!placeholders.contains(name)) {
            throw FormatException('Unknown workflow placeholder {{$name}}.');
          }
          if (name == 'prompt') hasPrompt = true;
          if (name != 'prompt' && child != match.group(0)) {
            throw FormatException('{{$name}} must fill the whole input value.');
          }
        }
      } else if (child is Map) {
        for (final value in child.values) {
          inspect(value);
        }
      } else if (child is List) {
        for (final value in child) {
          inspect(value);
        }
      }
    }

    for (final node in value.values) {
      if (node is! Map ||
          node['class_type'] is! String ||
          node['inputs'] is! Map) {
        throw const FormatException(
          'Each API node needs class_type and inputs.',
        );
      }
      inspect(node['inputs']);
    }
    if (!hasPrompt) {
      throw const FormatException(
        'Replace the positive prompt input with {{prompt}} before importing.',
      );
    }
    return value;
  }

  Map<String, Object?> toJson() => {'json': json, 'outputNodeId': outputNodeId};

  factory ComfyUiWorkflow.fromJson(Map value) => ComfyUiWorkflow(
    json: value['json'] is String ? value['json'] as String : '',
    outputNodeId: value['outputNodeId'] is String
        ? value['outputNodeId'] as String
        : '',
  );
}
