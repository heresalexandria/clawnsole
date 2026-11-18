import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'api_transcript.dart';
import 'bfl_api.dart';
import 'comfyui_settings.dart';
import 'models.dart';
import 'provider_submission.dart';
import 'stream_discard.dart';

/// ComfyUI's self-hosted HTTP queue. All calls run in the native gateway or
/// companion. The receipt carries the original server and chosen output node,
/// so editing settings cannot redirect a queued job to a different machine.
class ComfyUiApi {
  ComfyUiApi({http.Client? client})
    : _client = recordingProviderClient(client ?? http.Client());

  final http.Client _client;
  static final _id = RegExp(r'^[A-Za-z0-9_.-]{1,256}$');

  Future<ProviderAccountStatus> verify(ComfyUiSettings settings) async {
    settings.validate();
    final base = comfyUiServerUri(settings.serverUrl);
    final stats = await _get(base.resolve('system_stats'));
    if (stats['system'] is! Map || stats['devices'] is! List) {
      throw const ProviderException(
        'That server did not return ComfyUI system information.',
      );
    }
    return const ProviderAccountStatus(
      provider: 'comfyui',
      balanceLabel: 'Connected to your ComfyUI server',
    );
  }

  Future<Map<String, Object?>> submit(
    ComfyUiSettings settings,
    String model,
    Map<String, Object?> input, {
    BeforeGenerationSend? beforeSend,
  }) async {
    settings.validate();
    final workflow = settings.workflows[model];
    if (workflow == null) {
      throw const ProviderException(
        'Import this ComfyUI workflow in Providers before generating.',
        status: 400,
      );
    }
    final graph = workflow.validate();
    final base = comfyUiServerUri(settings.serverUrl);
    final prompt = input['prompt']?.toString() ?? '';
    if (prompt.trim().isEmpty) {
      throw const ProviderException(
        'Enter a prompt before generating.',
        status: 400,
      );
    }
    const fps = 24;
    final seconds = (input['duration'] as num?)?.toInt() ?? 5;
    final edge = input['resolution'] == 'fhd' ? 1024 : 768;
    final ratio = (input['aspect_ratio']?.toString() ?? '16:9').split(':');
    final rw = ratio.length == 2 ? int.tryParse(ratio[0]) ?? 16 : 16;
    final rh = ratio.length == 2 ? int.tryParse(ratio[1]) ?? 9 : 9;
    int aligned(double value) => max(64, (value / 64).round() * 64);
    final values = <String, Object>{
      'seed':
          (input['seed'] as num?)?.toInt() ??
          Random.secure().nextInt(0x7fffffff),
      'width': rw >= rh ? edge : aligned(edge * rw / rh),
      'height': rh >= rw ? edge : aligned(edge * rh / rw),
      'duration': seconds,
      'fps': fps,
      'frames': seconds * fps + 1,
    };
    Object? replace(Object? value) {
      if (value is String) {
        for (final entry in values.entries) {
          if (value == '{{${entry.key}}}') return entry.value;
        }
        return value.replaceAll('{{prompt}}', prompt);
      }
      if (value is List) return value.map(replace).toList();
      if (value is Map) {
        return value.map((key, child) => MapEntry(key, replace(child)));
      }
      return value;
    }

    // Only inputs are substituted: metadata, node IDs, and graph wiring stay
    // byte-equivalent JSON values. User prompts are never parsed as templates.
    final prepared = {
      for (final entry in graph.entries)
        entry.key: {
          ...entry.value! as Map,
          'inputs': replace((entry.value! as Map)['inputs']),
        },
    };
    final request = http.Request('POST', base.resolve('prompt'))
      ..followRedirects = false
      ..headers['content-type'] = 'application/json'
      ..body = jsonEncode({'prompt': prepared});
    await beforeSend?.call();
    final response = await _sendJson(request);
    final id = response['prompt_id'];
    if (id is! String || !_id.hasMatch(id)) {
      throw const ProviderException(
        'ComfyUI returned an invalid prompt receipt.',
        status: 502,
      );
    }
    return {
      'id': id,
      'polling_url': base
          .resolve('history/$id')
          .replace(
            queryParameters: {
              'clawnsole_output': workflow.outputNodeId.trim(),
              'clawnsole_kind': model == 'comfyui-image' ? 'image' : 'video',
            },
          )
          .toString(),
    };
  }

  Future<Map<String, Object?>> poll(String pollingUrl) async {
    final receipt = _receipt(pollingUrl);
    final history = await _get(receipt.history);
    final item = history[receipt.id];
    if (item is! Map) {
      final queue = await _get(receipt.base.resolve('queue'));
      bool contains(String field) => (queue[field] as List? ?? const []).any(
        (entry) => entry is List && entry.length > 1 && entry[1] == receipt.id,
      );
      if (contains('queue_running')) return {'status': 'Running'};
      if (contains('queue_pending')) return {'status': 'Pending'};
      // Read history again to cover a job leaving the queue between reads.
      final latest = await _get(receipt.history);
      if (latest[receipt.id] is Map) {
        return _completed(receipt, latest[receipt.id] as Map);
      }
      return {
        'status': 'Task not found',
        'error':
            'ComfyUI no longer has this job. The server may have restarted or cleared its history.',
      };
    }
    return _completed(receipt, item);
  }

  Map<String, Object?> _completed(_ComfyUiReceipt receipt, Map item) {
    final status = item['status'];
    if (status is Map && status['status_str'] == 'error') {
      String message = 'ComfyUI could not execute this workflow.';
      final messages = status['messages'];
      if (messages is List) {
        for (final event in messages) {
          if (event is List && event.length > 1 && event[1] is Map) {
            final data = event[1] as Map;
            final detail = data['exception_message'];
            if (detail is String && detail.isNotEmpty) message = detail;
          }
        }
      }
      return {'status': 'Failed', 'error': message};
    }
    if (status is! Map || status['completed'] != true) {
      return {'status': 'Running'};
    }
    final outputs = item['outputs'];
    final output = outputs is Map ? outputs[receipt.outputNode] : null;
    if (output is Map) {
      // Native SaveVideo returns `images`; VideoHelperSuite uses `gifs`.
      for (final field in const ['videos', 'gifs', 'images']) {
        final files = output[field];
        if (files is! List) continue;
        for (final file in files) {
          if (file is! Map) continue;
          final name = file['filename'];
          if (name is! String ||
              name.isEmpty ||
              name.contains('/') ||
              name.contains('\\')) {
            continue;
          }
          final extension = name.split('.').last.toLowerCase();
          final supported = receipt.kind == 'image'
              ? const {'png', 'jpg', 'jpeg', 'webp'}.contains(extension)
              : const {'mp4', 'webm', 'mov'}.contains(extension);
          if (!supported) continue;
          final subfolder = file['subfolder']?.toString() ?? '';
          if (subfolder.split(RegExp(r'[/\\]')).contains('..')) continue;
          final type = file['type']?.toString() ?? 'output';
          if (type != 'output') continue;
          return {
            'status': 'Ready',
            'result': {
              'sample': receipt.base
                  .resolve('view')
                  .replace(
                    queryParameters: {
                      'filename': name,
                      'subfolder': subfolder,
                      'type': type,
                    },
                  )
                  .toString(),
            },
          };
        }
      }
    }
    return {
      'status': 'Failed',
      'error':
          'The configured ComfyUI output node did not save a ${receipt.kind} file. Use SaveImage, SaveVideo, or a video output node with save_output enabled.',
    };
  }

  /// This explicit provider-only path permits private-network media while the
  /// general media downloader keeps its public-only URL policy. It accepts
  /// only /view on the server captured in this generation's original receipt.
  Future<http.StreamedResponse> downloadResult(
    String source,
    String pollingUrl,
  ) async {
    final receipt = _receipt(pollingUrl);
    final uri = Uri.tryParse(source);
    final expected = receipt.base.resolve('view');
    if (uri == null ||
        uri.scheme != expected.scheme ||
        uri.authority != expected.authority ||
        uri.path != expected.path ||
        uri.hasFragment ||
        uri.queryParameters['type'] != 'output' ||
        uri.queryParameters['filename']?.isNotEmpty != true) {
      throw const ProviderException('Invalid ComfyUI result URL.');
    }
    final request = http.Request('GET', uri)..followRedirects = false;
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await discardStream(response.stream);
      throw ProviderException(
        'ComfyUI result download returned HTTP ${response.statusCode}.',
        status: response.statusCode,
      );
    }
    return response;
  }

  Future<Map<String, Object?>> _get(Uri uri) =>
      _sendJson(http.Request('GET', uri)..followRedirects = false);

  Future<Map<String, Object?>> _sendJson(http.Request request) async {
    final streamed = await _client
        .send(request)
        .timeout(const Duration(seconds: 30));
    final response = await http.Response.fromStream(
      streamed,
    ).timeout(const Duration(seconds: 30));
    Map<String, Object?>? body;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, Object?>) body = decoded;
    } on FormatException {
      /* Report a provider error below. */
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        body == null ||
        body['error'] != null) {
      final error = body?['error'];
      final message = error is Map ? error['message'] ?? error['type'] : error;
      throw ProviderException(
        message?.toString() ??
            'ComfyUI returned HTTP ${response.statusCode} or an invalid response.',
        status: response.statusCode >= 400 ? response.statusCode : 502,
      );
    }
    return body;
  }

  _ComfyUiReceipt _receipt(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.pathSegments.length < 2 ||
        uri.pathSegments[uri.pathSegments.length - 2] != 'history' ||
        !_id.hasMatch(uri.pathSegments.last) ||
        uri.queryParameters['clawnsole_output']?.isNotEmpty != true ||
        !const {
          'image',
          'video',
        }.contains(uri.queryParameters['clawnsole_kind'])) {
      throw const ProviderException('Invalid ComfyUI polling receipt.');
    }
    final history = Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
    );
    return _ComfyUiReceipt(
      history: history,
      base: history.resolve('../'),
      id: uri.pathSegments.last,
      outputNode: uri.queryParameters['clawnsole_output']!,
      kind: uri.queryParameters['clawnsole_kind']!,
    );
  }
}

class _ComfyUiReceipt {
  const _ComfyUiReceipt({
    required this.history,
    required this.base,
    required this.id,
    required this.outputNode,
    required this.kind,
  });
  final Uri history;
  final Uri base;
  final String id;
  final String outputNode;
  final String kind;
}
