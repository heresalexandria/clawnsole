import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import '../core/models.dart';
import '../core/prompt_rewrite.dart';
import '../core/provider_catalog.dart';
import '../core/reference_prompts.dart';
import 'filter_menu.dart';
import 'prompt_rewrite_frames.dart';

/// Samples the frames that ride along with a rewrite. Injected so tests can
/// drive the dialog without a decoder or a network fetch.
typedef RewriteFrameSampler =
    Future<List<RewriteFrame>> Function(
      AppController controller,
      Generation item,
    );

/// The value the model dropdown uses for its "Custom model id…" row.
const String _customModelValue = ' custom';

/// Asks the director what should change and sends it to their chosen LLM.
///
/// With [item], the film's sampled frames and prompt go along and the
/// rewritten prompt opens in a new composer tab seeded from the film.
/// Without one, the Direction in the tab in front is rewritten in place
/// (no frames: nothing has been rendered yet), with Undo on the notice.
///
/// When no rewrite key is saved yet, the dialog asks for one first, right
/// where the director is, and carries on once it verifies.
Future<void> showPromptRewriteDialog(
  BuildContext context, {
  required AppController controller,
  Generation? item,
  RewriteFrameSampler? frameSampler,
}) => showDialog<void>(
  context: context,
  builder: (dialogContext) => _PromptRewriteDialog(
    controller: controller,
    item: item,
    frameSampler: frameSampler ?? sampleGenerationFrames,
  ),
);

class _PromptRewriteDialog extends StatefulWidget {
  const _PromptRewriteDialog({
    required this.controller,
    required this.item,
    required this.frameSampler,
  });

  final AppController controller;
  final Generation? item;
  final RewriteFrameSampler frameSampler;

  @override
  State<_PromptRewriteDialog> createState() => _PromptRewriteDialogState();
}

class _PromptRewriteDialogState extends State<_PromptRewriteDialog> {
  final TextEditingController _direction = TextEditingController();
  final TextEditingController _customModel = TextEditingController();
  final TextEditingController _key = TextEditingController();
  final Map<String, List<RewriteModel>> _models =
      <String, List<RewriteModel>>{};

  late RewriteProvider _provider;
  late String _modelSelection;
  String? _effort;
  List<RewriteFrame> _frames = const <RewriteFrame>[];
  bool _sampling = false;
  bool _busy = false;

  /// True while a submit is waiting for the frame sample to finish, so the
  /// button can say what it is actually doing.
  bool _awaitingFrames = false;
  Future<void>? _samplingFuture;
  bool _showOriginal = false;
  String? _error;

  /// The tab and direction a draft rewrite was opened for, so the answer
  /// lands there even if the director has moved on to another tab.
  late final String _draftTabId;
  late final String _originalPrompt;

  /// Key entry, shown until a rewrite provider has a key on this device.
  RewriteProvider _keyProvider = RewriteProvider.openai;
  bool _keyVisible = false;
  bool _savingKey = false;
  String? _keyError;

  Generation? get _film => widget.item;

  List<RewriteProvider> get _connected => RewriteProvider.values
      .where(
        (provider) =>
            widget.controller.connectedRewriteProviders.contains(provider.id),
      )
      .toList();

  bool get _needsKey => _connected.isEmpty;

  @override
  void initState() {
    super.initState();
    final controller = widget.controller;
    _draftTabId = controller.activeComposerTabId;
    _originalPrompt = _film?.prompt ?? controller.form.prompt;
    _provider =
        controller.preferredRewriteProvider ??
        _connected.firstOrNull ??
        RewriteProvider.openai;
    for (final provider in RewriteProvider.values) {
      _models[provider.id] = provider.curatedModels;
    }
    _adoptProviderChoice(_provider);
    _direction.addListener(_onTextChanged);
    _key.addListener(_onTextChanged);
    if (!_needsKey) unawaited(_loadModels(_provider));
    if (_film != null) {
      _sampling = true;
      _samplingFuture = _sampleFrames();
    }
  }

  @override
  void dispose() {
    _direction
      ..removeListener(_onTextChanged)
      ..dispose();
    _key
      ..removeListener(_onTextChanged)
      ..dispose();
    _customModel.dispose();
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  /// Applies [provider]'s remembered model and effort to the pickers. A model
  /// the list does not offer becomes the custom entry, pre-filled.
  void _adoptProviderChoice(RewriteProvider provider) {
    final remembered = widget.controller.rewriteModelFor(provider);
    final known = (_models[provider.id] ?? provider.curatedModels).any(
      (model) => model.id == remembered,
    );
    _modelSelection = known ? remembered : _customModelValue;
    if (!known) _customModel.text = remembered;
    _effort = _clampEffort(widget.controller.rewriteEffortFor(provider));
  }

  String? _clampEffort(String? candidate) {
    final levels = _effortLevels;
    if (levels.isEmpty) return null;
    if (candidate != null && levels.contains(candidate)) return candidate;
    final fallback = _provider.defaultEffort;
    return levels.contains(fallback) ? fallback : levels.first;
  }

  List<RewriteModel> get _providerModels =>
      _models[_provider.id] ?? _provider.curatedModels;

  String get _modelId => _modelSelection == _customModelValue
      ? _customModel.text.trim()
      : _modelSelection;

  RewriteModel? get _selectedModel =>
      _providerModels.where((model) => model.id == _modelId).firstOrNull;

  List<String> get _effortLevels =>
      _provider.effortLevelsFor(_modelId, model: _selectedModel);

  String get _modelLabel {
    final id = _modelId;
    if (id.isEmpty) return 'the model';
    return _selectedModel?.label ??
        _provider.curatedModel(id)?.label ??
        rewriteModelLabel(id);
  }

  Future<void> _loadModels(RewriteProvider provider) async {
    final listed = await widget.controller.loadRewriteModels(provider);
    if (!mounted || listed.isEmpty) return;
    setState(() {
      _models[provider.id] = listed;
      if (provider == _provider) {
        if (_modelSelection == _customModelValue) {
          // An id the live listing does turn out to carry stops reading as a
          // hand-typed model.
          final typed = _customModel.text.trim();
          if (listed.any((model) => model.id == typed)) _modelSelection = typed;
        } else if (!listed.any((model) => model.id == _modelSelection)) {
          // A listing that dropped the remembered id keeps the director's
          // choice usable as a custom entry instead of silently losing it.
          _customModel.text = _modelSelection;
          _modelSelection = _customModelValue;
        }
      }
      _effort = _clampEffort(_effort);
    });
  }

  Future<void> _sampleFrames() async {
    final film = _film;
    if (film == null) return;
    List<RewriteFrame> frames;
    try {
      frames = await widget.frameSampler(widget.controller, film);
    } on Object {
      frames = const <RewriteFrame>[];
    }
    if (!mounted) return;
    setState(() {
      _frames = frames;
      _sampling = false;
    });
  }

  void _selectProvider(RewriteProvider provider) {
    if (provider == _provider) return;
    setState(() {
      _provider = provider;
      _error = null;
      _adoptProviderChoice(provider);
    });
    unawaited(_loadModels(provider));
  }

  /// Verifies and stores the typed key, then carries on into the rewrite
  /// form on the provider it belongs to.
  Future<void> _saveKey() async {
    if (_savingKey || _key.text.trim().isEmpty) return;
    setState(() {
      _savingKey = true;
      _keyError = null;
    });
    final provider = _keyProvider;
    try {
      await widget.controller.saveRewriteKey(provider, _key.text);
      if (!mounted) return;
      setState(() {
        _savingKey = false;
        _provider = provider;
        _adoptProviderChoice(provider);
      });
      unawaited(_loadModels(provider));
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _savingKey = false;
        _keyError = error.toString();
      });
    }
  }

  PromptRewriteRequest _buildRequest() {
    final controller = widget.controller;
    final film = _film;
    final base = (
      providerId: _provider.id,
      modelId: _modelId,
      effort: _effortLevels.isEmpty ? null : _effort,
      direction: _direction.text.trim(),
    );
    if (film != null) {
      final catalogProvider = providerByIdForRouting(film.provider);
      final catalogModel = catalogProvider?.models
          .where((model) => model.id == film.model.split(':').first)
          .firstOrNull;
      final duration = film.config.duration;
      return PromptRewriteRequest(
        providerId: base.providerId,
        modelId: base.modelId,
        effort: base.effort,
        originalPrompt: film.prompt,
        screenplayMode: film.config.screenplayMode,
        direction: base.direction,
        frames: _frames,
        targetProviderName: catalogProvider?.name,
        targetModelName: catalogModel?.label,
        maxPromptCharacters: catalogModel?.maxPromptCharacters,
        durationSeconds: duration is num ? duration.round() : null,
        aspectRatio: film.config.aspectRatio,
        mode: film.mode.name,
        referenceMentions: rewriteReferenceMentions(film),
      );
    }
    // A draft: the tab in front is the recipe, and nothing has rendered yet.
    final form = controller.form;
    final model = controller.selectedModel;
    return PromptRewriteRequest(
      providerId: base.providerId,
      modelId: base.modelId,
      effort: base.effort,
      originalPrompt: _originalPrompt,
      screenplayMode: form.screenplayMode,
      direction: base.direction,
      targetProviderName: controller.selectedProvider.name,
      targetModelName: model.label,
      maxPromptCharacters: model.maxPromptCharacters,
      durationSeconds: form.autoDuration ? null : form.durationSeconds,
      aspectRatio: form.aspectRatio,
      mode: form.mode.name,
      referenceMentions: rewriteDraftReferenceMentions(form),
    );
  }

  Future<void> _submit() async {
    if (_busy || _direction.text.trim().isEmpty || _modelId.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final controller = widget.controller;
    final film = _film;
    try {
      // A quick director can press Rewrite before the frames are in; the
      // frames are the point, so wait for the sample rather than send text.
      if (_sampling) {
        setState(() => _awaitingFrames = true);
        await _samplingFuture;
        if (!mounted) return;
        setState(() => _awaitingFrames = false);
      }
      final result = await controller.rewritePrompt(_buildRequest());
      await controller.rememberRewriteChoice(
        provider: _provider,
        modelId: _modelId,
        effort: _effortLevels.isEmpty ? null : _effort,
      );
      if (film != null) {
        await controller.openGenerationInNewTab(
          film,
          prompt: result.prompt,
          rewriteSummary: result.summary,
        );
      }
      // Escape can dismiss the dialog while the model is still thinking; the
      // result and its notice still land, there is just nothing left to pop.
      if (mounted) navigator.pop();
      if (film == null) {
        controller.applyRewrittenDirection(result, tabId: _draftTabId);
        return;
      }
      final summary = result.summary.trim();
      controller.showNotice(
        summary.isEmpty
            ? 'Prompt rewritten in a new tab.'
            : 'Prompt rewritten: $summary',
      );
    } on PromptRewriteException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.failure == PromptRewriteFailure.unauthorized
            ? '${error.message} Check the key in Settings.'
            : error.message;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_needsKey) return _buildKeyStep(context);
    final connected = _connected;
    final levels = _effortLevels;
    final film = _film;
    final ready = _direction.text.trim().isNotEmpty && _modelId.isNotEmpty;
    return AlertDialog(
      title: const Text('AI Rewrite'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                film != null
                    ? 'Frames from this film, its prompt, and your notes go '
                          'to the model you pick. Only the rewritten prompt '
                          'comes back.'
                    : 'Your direction and your notes go to the model you '
                          'pick. Only the rewritten direction comes back, and '
                          'Undo keeps the old one a tap away.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              if (connected.length > 1) ...<Widget>[
                const SizedBox(height: 16),
                const _FieldLabel('Rewrite with', icon: Icons.hub_rounded),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: connected
                      .map(
                        (provider) => ConsoleFilterSegment(
                          key: ValueKey('rewrite-provider-${provider.id}'),
                          label: provider.name,
                          selected: provider == _provider,
                          onTap: () => _selectProvider(provider),
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: ValueKey('rewrite-model-${_provider.id}-$_modelSelection'),
                initialValue: _modelSelection,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Model'),
                items: <DropdownMenuItem<String>>[
                  for (final model in _providerModels)
                    DropdownMenuItem<String>(
                      value: model.id,
                      child: Text(model.label, overflow: TextOverflow.ellipsis),
                    ),
                  const DropdownMenuItem<String>(
                    value: _customModelValue,
                    child: Text(
                      'Custom model id…',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() {
                          _modelSelection = value;
                          _effort = _clampEffort(_effort);
                        });
                      },
              ),
              if (_modelSelection == _customModelValue) ...<Widget>[
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('rewrite-custom-model'),
                  controller: _customModel,
                  autocorrect: false,
                  enableSuggestions: false,
                  enabled: !_busy,
                  onChanged: (_) =>
                      setState(() => _effort = _clampEffort(_effort)),
                  decoration: InputDecoration(
                    labelText: 'Model id',
                    hintText: _provider.defaultModelId,
                  ),
                ),
              ],
              if (levels.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey('rewrite-effort-${_provider.id}-$_effort'),
                  initialValue: _effort,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Effort'),
                  items: levels
                      .map(
                        (level) => DropdownMenuItem<String>(
                          value: level,
                          child: Text(
                            _effortLabel(level),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _effort = value),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('rewrite-direction'),
                controller: _direction,
                autofocus: true,
                enabled: !_busy,
                minLines: 3,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(fontFamily: promptFontFamily),
                decoration: InputDecoration(
                  labelText: 'What should change?',
                  hintText: film != null
                      ? 'Keep the dolly move, but make the lantern light '
                            'warmer and slower'
                      : 'Tighten it, name the camera move, and make the '
                            'lighting specific',
                  hintMaxLines: 2,
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 10),
              _OriginalPrompt(
                title: film != null ? 'Original prompt' : 'Current direction',
                prompt: _originalPrompt,
                expanded: _showOriginal,
                onToggle: () => setState(() => _showOriginal = !_showOriginal),
              ),
              if (film != null) ...<Widget>[
                const SizedBox(height: 12),
                _FrameStrip(frames: _frames, sampling: _sampling),
              ],
              if (_error != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  key: const ValueKey('rewrite-error'),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                    color: context.colors.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('rewrite-submit'),
          onPressed: ready && !_busy ? () => unawaited(_submit()) : null,
          child: _busy
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const SizedBox.square(
                      dimension: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 9),
                    Flexible(
                      child: Text(
                        _awaitingFrames
                            ? 'Sampling frames…'
                            : 'Asking $_modelLabel…',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                )
              : Text(film != null ? 'Rewrite prompt' : 'Rewrite direction'),
        ),
      ],
    );
  }

  /// The first-run step: pick a vendor, paste a key, verify, carry on.
  Widget _buildKeyStep(BuildContext context) {
    final provider = _keyProvider;
    final ready = _key.text.trim().isNotEmpty && !_savingKey;
    return AlertDialog(
      title: const Text('AI Rewrite'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'AI Rewrite asks an OpenAI or Anthropic model to revise your '
                'prompt, so it needs one of their API keys. The key is kept '
                'in the encrypted settings vault with your provider keys and '
                'syncs with them.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              const _FieldLabel('Vendor', icon: Icons.hub_rounded),
              const SizedBox(height: 7),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: RewriteProvider.values
                    .map(
                      (candidate) => ConsoleFilterSegment(
                        key: ValueKey('rewrite-key-provider-${candidate.id}'),
                        label: candidate.name,
                        selected: candidate == provider,
                        onTap: () => setState(() {
                          _keyProvider = candidate;
                          _keyError = null;
                        }),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('rewrite-key-field'),
                controller: _key,
                autofocus: true,
                enabled: !_savingKey,
                obscureText: !_keyVisible,
                autocorrect: false,
                enableSuggestions: false,
                onSubmitted: (_) => unawaited(_saveKey()),
                decoration: InputDecoration(
                  labelText: '${provider.name} API key',
                  hintText: provider.keyHint,
                  suffixIcon: IconButton(
                    tooltip: _keyVisible ? 'Hide key' : 'Show key',
                    onPressed: () => setState(() => _keyVisible = !_keyVisible),
                    icon: Icon(
                      _keyVisible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('rewrite-key-get'),
                  onPressed: () =>
                      unawaited(launchUrl(Uri.parse(provider.consoleUrl))),
                  icon: const Icon(Icons.open_in_new_rounded, size: 15),
                  label: Text('Get a ${provider.name} key'),
                ),
              ),
              if (_keyError != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  _keyError!,
                  key: const ValueKey('rewrite-key-error'),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                    color: context.colors.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _savingKey ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('rewrite-key-save'),
          onPressed: ready ? () => unawaited(_saveKey()) : null,
          child: _savingKey
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    SizedBox.square(
                      dimension: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 9),
                    Text('Checking…'),
                  ],
                )
              : const Text('Verify & save'),
        ),
      ],
    );
  }
}

/// The `@Image 1` style mentions [item]'s prompt may already use, so the
/// rewrite keeps them bound to the media that comes along to the new tab.
List<String> rewriteReferenceMentions(Generation item) => _mentions(
  (item.config.references ?? const <MediaReferenceLabel>[]).map(
    (reference) => (kind: reference.kind, name: reference.promptName),
  ),
);

/// The mentions the draft in [form] may use, from the references attached
/// to it right now.
List<String> rewriteDraftReferenceMentions(GenerationFormState form) =>
    _mentions(
      form.references.map(
        (reference) => (kind: reference.kind, name: reference.promptName),
      ),
    );

List<String> _mentions(
  Iterable<({MediaReferenceKind kind, String? name})> references,
) {
  final counts = <MediaReferenceKind, int>{};
  return references.map((reference) {
    final number = (counts[reference.kind] ?? 0) + 1;
    counts[reference.kind] = number;
    final assigned = reference.name?.trim() ?? '';
    return PromptReferenceMention(
      kind: reference.kind,
      number: number,
      // A stored name that is just a reserved default may disagree with this
      // attachment order; the canonical numbering wins in that case.
      name: assigned.isEmpty || isReservedReferenceName(assigned)
          ? null
          : assigned,
    ).canonical;
  }).toList();
}

String _effortLabel(String level) => switch (level) {
  'low' => 'Low',
  'medium' => 'Medium',
  'high' => 'High',
  'xhigh' => 'Extra high',
  'max' => 'Maximum',
  _ => level,
};

/// The house field label: 11 px, 700, uppercase, near-ink, brass icon.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Icon(icon, size: 16, color: context.tokens.brass),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.3,
            color: context.colors.onSurface.withValues(alpha: .82),
          ),
        ),
      ),
    ],
  );
}

class _OriginalPrompt extends StatelessWidget {
  const _OriginalPrompt({
    required this.title,
    required this.prompt,
    required this.expanded,
    required this.onToggle,
  });

  final String title;
  final String prompt;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const ValueKey('rewrite-original-toggle'),
          onPressed: onToggle,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: Icon(
            expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
            size: 17,
          ),
          label: Text(title),
        ),
      ),
      if (expanded) ...<Widget>[
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: context.colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: context.colors.outlineVariant),
          ),
          child: SelectableText(
            prompt,
            key: const ValueKey('rewrite-original-prompt'),
            style: TextStyle(
              fontFamily: promptFontFamily,
              fontSize: 12,
              height: 1.45,
              color: context.colors.onSurface,
            ),
          ),
        ),
      ],
    ],
  );
}

class _FrameStrip extends StatelessWidget {
  const _FrameStrip({required this.frames, required this.sampling});

  final List<RewriteFrame> frames;
  final bool sampling;

  String get _caption {
    if (sampling) return 'Sampling frames…';
    if (frames.isEmpty) return 'No frames available — sending text only';
    return '${frames.length} ${frames.length == 1 ? 'frame' : 'frames'} sampled';
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      if (frames.isNotEmpty) ...<Widget>[
        // A lazy ListView cannot report an intrinsic width, which is exactly
        // what AlertDialog measures its content by. Eight thumbnails do not
        // need laziness anyway.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final frame in frames)
                Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.memory(
                      frame.bytes,
                      height: 42,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (context, _, _) => Container(
                        width: 42,
                        height: 42,
                        color: context.colors.surfaceContainerHigh,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
      ],
      Row(
        children: <Widget>[
          if (sampling) ...<Widget>[
            const SizedBox.square(
              dimension: 11,
              child: CircularProgressIndicator(strokeWidth: 1.6),
            ),
            const SizedBox(width: 7),
          ],
          Flexible(
            child: Text(
              _caption,
              key: const ValueKey('rewrite-frame-caption'),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    ],
  );
}
