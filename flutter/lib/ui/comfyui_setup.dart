import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../core/comfyui_settings.dart';

Future<void> showComfyUiSetup(BuildContext context, AppController controller) =>
    showDialog<void>(
      context: context,
      builder: (_) => _ComfyUiSetup(controller: controller),
    );

class _ComfyUiSetup extends StatefulWidget {
  const _ComfyUiSetup({required this.controller});
  final AppController controller;

  @override
  State<_ComfyUiSetup> createState() => _ComfyUiSetupState();
}

class _ComfyUiSetupState extends State<_ComfyUiSetup> {
  late final TextEditingController _server;
  final _json = TextEditingController();
  final _output = TextEditingController();
  late final Map<String, ComfyUiWorkflow> _workflows;
  String _model = 'comfyui-video';
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final settings = widget.controller.comfyUiSettings;
    _server = TextEditingController(text: settings.serverUrl);
    _workflows = Map.of(settings.workflows);
    _load();
  }

  @override
  void dispose() {
    _server.dispose();
    _json.dispose();
    _output.dispose();
    super.dispose();
  }

  void _load() {
    _json.text = _workflows[_model]?.json ?? '';
    _output.text = _workflows[_model]?.outputNodeId ?? '';
  }

  void _stage() {
    if (_json.text.trim().isEmpty) {
      _workflows.remove(_model);
    } else {
      _workflows[_model] = ComfyUiWorkflow(
        json: _json.text.trim(),
        outputNodeId: _output.text.trim(),
      );
    }
  }

  Future<void> _import() async {
    try {
      final selection = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      if (!mounted || selection == null) return;
      final file = selection.files.single;
      if (file.size > ComfyUiWorkflow.maxBytes || file.bytes == null) {
        throw const FormatException(
          'Choose an API workflow JSON smaller than 128 KB.',
        );
      }
      _json.text = utf8.decode(file.bytes!);
      setState(() => _error = null);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _stage();
      final settings = ComfyUiSettings(
        serverUrl: _server.text.trim(),
        workflows: Map.of(_workflows),
      );
      await widget.controller.saveComfyUiSettings(settings);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Connect ComfyUI'),
    content: SizedBox(
      width: 680,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Run a workflow successfully in ComfyUI, then export it in API format. Your server supplies the models and custom nodes, including any H3 or LTX installation.',
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('comfyui-server-url'),
              controller: _server,
              enabled: !_busy,
              autocorrect: false,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Server URL',
                hintText: 'http://127.0.0.1:8188',
                helperText:
                    'Use your server’s LAN or Tailscale address from another device.',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _model,
              decoration: const InputDecoration(labelText: 'Workflow slot'),
              items: const [
                DropdownMenuItem(
                  value: 'comfyui-video',
                  child: Text('Video workflow'),
                ),
                DropdownMenuItem(
                  value: 'comfyui-image',
                  child: Text('Image workflow'),
                ),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() {
                      _stage();
                      _model = value!;
                      _load();
                      _error = null;
                    }),
            ),
            const SizedBox(height: 12),
            const SelectableText(
              'Replace the positive prompt input with "{{prompt}}". Optional numeric inputs can use "{{seed}}", "{{width}}", "{{height}}", "{{duration}}", "{{fps}}", or "{{frames}}" (seconds × 24 + 1). {{fps}} is 24. Keep each numeric placeholder as the whole quoted value.',
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _import,
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('Import API workflow JSON'),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('comfyui-workflow-json'),
              controller: _json,
              enabled: !_busy,
              minLines: 5,
              maxLines: 10,
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(labelText: 'API workflow JSON'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('comfyui-output-node'),
              controller: _output,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Final output node ID',
                hintText: '9',
                helperText:
                    'The JSON key for SaveImage, SaveVideo, or a video node that saves output. Clawnsole retains its first matching file.',
                helperMaxLines: 3,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Only inputs mapped with placeholders follow Create controls. All other settings stay exactly as saved in your workflow. This connection uses no API key; use a trusted private network or Tailscale, and keep ComfyUI running until results are saved.',
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      if (widget.controller.comfyUiSettings.isConfigured)
        TextButton(
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  try {
                    await widget.controller.removeComfyUiSettings();
                    if (context.mounted) Navigator.of(context).pop();
                  } on Object catch (error) {
                    if (mounted) {
                      setState(() {
                        _error = error.toString();
                        _busy = false;
                      });
                    }
                  }
                },
          child: const Text('Remove connection'),
        ),
      TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: Text(_busy ? 'Connecting…' : 'Test & save'),
      ),
    ],
  );
}
