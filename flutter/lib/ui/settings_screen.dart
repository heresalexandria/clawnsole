import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import '../core/app_links.dart';
import '../core/create_defaults.dart';
import '../core/google_drive.dart';
import '../core/models.dart';
import '../core/prompt_rewrite.dart';
import '../core/provider_catalog.dart';
import 'busy_button.dart';
import 'claw_mark.dart';
import 'common_widgets.dart';
import 'panels.dart';
import 'provider_model_picker.dart';
import 'section_tabs.dart';
import 'formatters.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({required this.controller, super.key});

  final AppController controller;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<bool> _confirm(String title, String detail) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(detail),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      ) ??
      false;

  AppController get controller => widget.controller;

  /// The desks on the rail, in order.
  ///
  /// Sync is dropped entirely without Drive: the encrypted settings vault
  /// that shares the desk with it comes from the same gateways, so a build
  /// without `supportsGoogleDrive` has neither control to show.
  List<SettingsTab> get _tabs => <SettingsTab>[
    SettingsTab.general,
    SettingsTab.defaults,
    SettingsTab.aiRewrite,
    SettingsTab.storage,
    if (controller.supportsGoogleDrive) SettingsTab.sync,
    SettingsTab.data,
  ];

  static IconData _icon(SettingsTab tab) => switch (tab) {
    SettingsTab.general => Icons.tune_rounded,
    SettingsTab.defaults => Icons.playlist_add_check_rounded,
    SettingsTab.aiRewrite => Icons.auto_awesome_rounded,
    SettingsTab.storage => Icons.storage_rounded,
    SettingsTab.sync => Icons.cloud_sync_rounded,
    SettingsTab.data => Icons.delete_sweep_outlined,
  };

  /// Every desk is one column at every width: a tab holds one domain, so the
  /// old 7/4 split had nothing left to balance.
  List<Widget> _cards(SettingsTab tab) => switch (tab) {
    SettingsTab.general => <Widget>[
      _GenerationAppearanceCard(controller: controller),
      _ProviderAccessCard(controller: controller),
      const _AboutSection(),
    ],
    SettingsTab.defaults => <Widget>[
      _CreateDefaultsCard(controller: controller),
    ],
    SettingsTab.aiRewrite => <Widget>[_AiRewriteCard(controller: controller)],
    SettingsTab.storage => <Widget>[
      _StorageSection(controller: controller),
      _LibraryRoomPanel(controller: controller),
    ],
    SettingsTab.sync => <Widget>[_GoogleDriveSection(controller: controller)],
    SettingsTab.data => <Widget>[
      _ClearDataCard(controller: controller, confirm: _confirm),
    ],
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    // The rail is the screen's own state, so a bare Settings screen switches
    // desks without waiting for a caller to rebuild it.
    listenable: controller,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final tabs = _tabs;
        final selected = tabs.contains(controller.settingsTab)
            ? controller.settingsTab
            : SettingsTab.general;
        final cards = _cards(selected);
        return SingleChildScrollView(
          padding: EdgeInsets.all(constraints.maxWidth < 620 ? 16 : 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1320),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Eyebrow('Personal setup', icon: Icons.tune_rounded),
                  const SizedBox(height: 10),
                  Text(
                    'Settings.',
                    style: Theme.of(context).textTheme.displayLarge,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    controller.supportsGoogleDrive
                        ? 'Manage appearance, Drive sync, and this device’s private keys.'
                        : 'Manage appearance, updates, and Clawnsole’s private local data.',
                  ),
                  const SizedBox(height: 24),
                  SectionTabRail(
                    semanticLabel: 'Settings desk',
                    tabs: <SectionTab>[
                      for (final tab in tabs)
                        SectionTab(
                          key: ValueKey<String>(tab.tabKey),
                          label: tab.label,
                          semanticLabel: '${tab.label} settings',
                          icon: _icon(tab),
                          selected: tab == selected,
                          onTap: () => controller.setSettingsTab(tab),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  for (var index = 0; index < cards.length; index += 1) ...[
                    if (index > 0) const SizedBox(height: 18),
                    cards[index],
                  ],
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// The Defaults desk: what a new Create draft opens with.
///
/// Every row's first answer is **Last used**, which is the inheriting
/// behaviour a blank tab has always had; anything else is an instruction the
/// composer follows when it opens the next blank draft. Reuse, Extend and
/// Enhance restore a film's own recipe and never consult this card.
class _CreateDefaultsCard extends StatelessWidget {
  const _CreateDefaultsCard({required this.controller});

  final AppController controller;

  CreateDefaults get _defaults => controller.createDefaults;

  /// The model these choices are being made for: the one named here while the
  /// catalog still has it, and otherwise the model the composer is on.
  VideoModelDefinition get _model {
    final provider = controller.providers
        .where((item) => item.id == _defaults.providerId)
        .firstOrNull;
    return provider?.models
            .where((item) => item.id == _defaults.modelId)
            .firstOrNull ??
        controller.selectedModel;
  }

  String get _modelLabel {
    if (!_defaults.hasModel) return 'Last used';
    final provider = controller.providers
        .where((item) => item.id == _defaults.providerId)
        .firstOrNull;
    final model = provider?.models
        .where((item) => item.id == _defaults.modelId)
        .firstOrNull;
    if (provider == null || model == null) return 'No longer available';
    return '${provider.name} · ${model.label}';
  }

  /// The resolution the ratio and duration choices are read against.
  String get _resolution {
    final resolutions = _model.resolutions.map((item) => item.id).toList();
    final chosen = _defaults.resolution;
    if (chosen != null && resolutions.contains(chosen)) return chosen;
    if (resolutions.contains(controller.form.resolution)) {
      return controller.form.resolution;
    }
    return resolutions.isEmpty ? 'hd' : resolutions.first;
  }

  void _write(CreateDefaults value) =>
      unawaited(controller.setCreateDefaults(value));

  Future<void> _pickModel(BuildContext context) => showProviderModelPicker(
    context,
    controller,
    selectedProviderId: _defaults.providerId,
    selectedModelId: _defaults.modelId,
    onSelected: (providerId, modelId) async => controller.setCreateDefaults(
      _defaults.copyWith(providerId: providerId, modelId: modelId),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final model = _model;
    final resolution = _resolution;
    final ratios = model.aspectRatiosFor(resolution, mode: VideoMode.t2v);
    final durations = model.durationRangeFor(resolution);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CircleAvatar(
                backgroundColor: context.colors.primaryContainer,
                child: Icon(
                  Icons.playlist_add_check_rounded,
                  color: context.colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'New drafts start with…',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Say what a fresh draft should open with, or leave a row '
                      'on Last used.',
                      style: TextStyle(color: context.colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _DefaultRow(
            label: 'Format',
            hint: 'How the Direction field is written.',
            child: _FormatSegments(
              value: _defaults.screenplayMode,
              onChanged: (value) => _write(
                value == null
                    ? _defaults.copyWith(clearScreenplayMode: true)
                    : _defaults.copyWith(screenplayMode: value),
              ),
            ),
          ),
          _DefaultRow(
            label: 'Model',
            hint: 'The provider and model a new draft opens on.',
            trailing: _defaults.hasModel
                ? IconButton(
                    key: const ValueKey('create-default-model-clear'),
                    tooltip: 'Back to last used',
                    onPressed: () =>
                        _write(_defaults.copyWith(clearModel: true)),
                    icon: const Icon(Icons.close_rounded, size: 17),
                  )
                : null,
            child: OutlinedButton.icon(
              key: const ValueKey('create-default-model'),
              onPressed: () => unawaited(_pickModel(context)),
              icon: const Icon(Icons.expand_more_rounded, size: 17),
              iconAlignment: IconAlignment.end,
              label: Text(_modelLabel, overflow: TextOverflow.ellipsis),
            ),
          ),
          _DefaultRow(
            label: 'Frame',
            hint: 'Aspect ratio.',
            child: _DefaultDropdown<String>(
              fieldKey: const ValueKey('create-default-aspect-ratio'),
              value: _defaults.aspectRatio,
              values: ratios,
              labelOf: (ratio) => ratio == 'auto' ? 'Auto' : ratio,
              onChanged: (value) => _write(
                value == null
                    ? _defaults.copyWith(clearAspectRatio: true)
                    : _defaults.copyWith(aspectRatio: value),
              ),
            ),
          ),
          _DefaultRow(
            label: 'Finish',
            hint: 'Resolution.',
            child: _DefaultDropdown<String>(
              fieldKey: const ValueKey('create-default-resolution'),
              value: _defaults.resolution,
              values: model.resolutions.map((item) => item.id).toList(),
              labelOf: (id) =>
                  model.resolutions
                      .where((item) => item.id == id)
                      .firstOrNull
                      ?.label ??
                  id,
              onChanged: (value) => _write(
                value == null
                    ? _defaults.copyWith(clearResolution: true)
                    : _defaults.copyWith(resolution: value),
              ),
            ),
          ),
          _DefaultRow(
            label: 'Duration',
            hint: 'How long a new draft asks for.',
            child: _DefaultDropdown<CreateDurationDefault>(
              fieldKey: const ValueKey('create-default-duration'),
              value: _defaults.duration,
              values: <CreateDurationDefault>[
                if (model.supportsAutoDuration)
                  const CreateDurationDefault.auto(),
                for (
                  var seconds = durations.minimumSeconds;
                  seconds <= durations.maximumSeconds;
                  seconds += durations.stepSeconds
                )
                  CreateDurationDefault.seconds(seconds),
              ],
              labelOf: (duration) =>
                  duration.isAuto ? 'Auto' : '${duration.seconds} s',
              onChanged: (value) => _write(
                value == null
                    ? _defaults.copyWith(clearDuration: true)
                    : _defaults.copyWith(duration: value),
              ),
            ),
          ),
          _DefaultRow(
            label: 'Audio',
            hint: 'Whether new drafts ask for sound.',
            child: _DefaultDropdown<bool>(
              fieldKey: const ValueKey('create-default-audio'),
              value: _defaults.generateAudio,
              values: const <bool>[true, false],
              labelOf: (value) => value ? 'On' : 'Off',
              onChanged: (value) => _write(
                value == null
                    ? _defaults.copyWith(clearGenerateAudio: true)
                    : _defaults.copyWith(generateAudio: value),
              ),
            ),
          ),
          _DefaultRow(
            label: 'Fast draft',
            hint: 'Quick, cheaper renders at HD.',
            child: _DefaultDropdown<bool>(
              fieldKey: const ValueKey('create-default-draft'),
              value: _defaults.draft,
              values: const <bool>[true, false],
              labelOf: (value) => value ? 'On' : 'Off',
              onChanged: (value) => _write(
                value == null
                    ? _defaults.copyWith(clearDraft: true)
                    : _defaults.copyWith(draft: value),
              ),
            ),
          ),
          _DefaultRow(
            label: 'Aesthetic',
            hint: 'A definition appended to every new draft.',
            child: _DefaultDropdown<String>(
              fieldKey: const ValueKey('create-default-aesthetic'),
              value: _defaults.aestheticReferenceId,
              values: <String>[
                CreateDefaults.noAesthetic,
                for (final item in controller.aestheticReferences) item.id,
              ],
              labelOf: (id) => id == CreateDefaults.noAesthetic
                  ? 'None'
                  : controller.aestheticReferences
                            .where((item) => item.id == id)
                            .firstOrNull
                            ?.title ??
                        'No longer available',
              onChanged: (value) => _write(
                value == null
                    ? _defaults.copyWith(clearAesthetic: true)
                    : _defaults.copyWith(aestheticReferenceId: value),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Last used carries over whatever the previous draft had. Reuse, '
            'Extend and Enhance keep the film’s own settings, and the chosen '
            'model still has the last word on a combination it cannot take. '
            'Where new films are saved lives on the Storage desk.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.4,
              color: context.colors.onSurfaceVariant,
            ),
          ),
          if (!_defaults.isEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('create-defaults-reset'),
                onPressed: () => _write(CreateDefaults.none),
                icon: const Icon(Icons.restart_alt_rounded, size: 17),
                label: const Text('Reset to last used'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One setting on the Defaults desk: its name on the left, its control on the
/// right, stacked instead when the room is too narrow to read them side by
/// side.
class _DefaultRow extends StatelessWidget {
  const _DefaultRow({
    required this.label,
    required this.hint,
    required this.child,
    this.trailing,
  });

  final String label;
  final String hint;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final name = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          hint,
          style: TextStyle(
            fontSize: 11,
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ],
    );
    final control = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Flexible(child: child),
        if (trailing != null) trailing!,
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth < 460
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  name,
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerLeft, child: control),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Expanded(child: name),
                  const SizedBox(width: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 340),
                    child: control,
                  ),
                ],
              ),
      ),
    );
  }
}

/// Plaintext / Screenplay / Last used, with Last used first because it is the
/// answer a director who has not thought about it already has.
class _FormatSegments extends StatelessWidget {
  const _FormatSegments({required this.value, required this.onChanged});

  final bool? value;
  final ValueChanged<bool?> onChanged;

  @override
  // Three segments want a little more than the desk's control column at
  // desk widths; scaling the whole control down a few percent keeps every
  // word whole where a scroll view would clip "Screenplay" at the edge.
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerRight,
    child: SegmentedButton<String>(
      key: const ValueKey('create-default-format'),
      showSelectedIcon: false,
      segments: const <ButtonSegment<String>>[
        ButtonSegment<String>(value: 'inherit', label: Text('Last used')),
        ButtonSegment<String>(value: 'plaintext', label: Text('Plaintext')),
        ButtonSegment<String>(value: 'screenplay', label: Text('Screenplay')),
      ],
      selected: <String>{
        switch (value) {
          null => 'inherit',
          true => 'screenplay',
          false => 'plaintext',
        },
      },
      onSelectionChanged: (choice) => onChanged(switch (choice.single) {
        'screenplay' => true,
        'plaintext' => false,
        _ => null,
      }),
    ),
  );
}

/// A Defaults-desk dropdown whose first entry is always Last used.
///
/// A stored answer the current model no longer offers stays selectable rather
/// than breaking the field: the composer normalizes it when it opens a draft,
/// and the director can see what they asked for until they change it.
class _DefaultDropdown<T extends Object> extends StatelessWidget {
  const _DefaultDropdown({
    required this.fieldKey,
    required this.value,
    required this.values,
    required this.labelOf,
    required this.onChanged,
  });

  final Key fieldKey;
  final T? value;
  final List<T> values;
  final String Function(T value) labelOf;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = <T>[
      ...values,
      if (value != null && !values.contains(value)) value as T,
    ];
    return DropdownButtonFormField<T?>(
      key: fieldKey,
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      items: <DropdownMenuItem<T?>>[
        DropdownMenuItem<T?>(value: null, child: const Text('Last used')),
        for (final option in options)
          DropdownMenuItem<T?>(
            value: option,
            child: Text(labelOf(option), overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

class _GenerationAppearanceCard extends StatelessWidget {
  const _GenerationAppearanceCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CircleAvatar(
          backgroundColor: context.colors.primaryContainer,
          child: Icon(
            Icons.live_tv_rounded,
            color: context.colors.onPrimaryContainer,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Generation appearance',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Choose what plays in the preview while a video is rendering.',
                style: TextStyle(color: context.colors.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<GenerationPlaceholderStyle>(
                key: const ValueKey('generation-placeholder-style'),
                initialValue: controller.generationPlaceholderStyle,
                decoration: const InputDecoration(
                  labelText: 'Generation Placeholder',
                  helperText:
                      'Static recreates analog broadcast snow; Cyclone keeps the luminous ribbon field.',
                  // Phones would otherwise ellipsize this after "sno…".
                  helperMaxLines: 3,
                ),
                items: GenerationPlaceholderStyle.values
                    .map(
                      (style) => DropdownMenuItem<GenerationPlaceholderStyle>(
                        value: style,
                        child: Text(style.label),
                      ),
                    )
                    .toList(),
                onChanged: (style) {
                  if (style != null) {
                    unawaited(controller.setGenerationPlaceholderStyle(style));
                  }
                },
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ProviderAccessCard extends StatelessWidget {
  const _ProviderAccessCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final summary = Row(
          children: <Widget>[
            CircleAvatar(
              backgroundColor: context.colors.primaryContainer,
              child: Icon(
                Icons.hub_rounded,
                color: context.colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Provider keys and costs',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 4),
                  Text(
                    controller.supportsLocalLibrary
                        ? 'Set provider keys and compare live model costs in Providers.'
                        : 'Set an Atlas Cloud key for the verified backend-free Pages route.',
                  ),
                ],
              ),
            ),
          ],
        );
        final action = FilledButton.icon(
          onPressed: () => unawaited(controller.navigate(AppSection.providers)),
          icon: const Icon(Icons.arrow_forward_rounded, size: 17),
          label: const Text('Open Providers'),
        );

        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[summary, const SizedBox(height: 14), action],
          );
        }
        return Row(
          children: <Widget>[
            Expanded(child: summary),
            const SizedBox(width: 16),
            action,
          ],
        );
      },
    ),
  );
}

/// Keys for the LLMs that revise prompts. They sit here rather than on the
/// Providers desk because they render nothing: they only read a finished film
/// and hand back better words for it.
class _AiRewriteCard extends StatefulWidget {
  const _AiRewriteCard({required this.controller});

  final AppController controller;

  @override
  State<_AiRewriteCard> createState() => _AiRewriteCardState();
}

class _AiRewriteCardState extends State<_AiRewriteCard> {
  final Map<String, TextEditingController> _keys =
      <String, TextEditingController>{
        for (final provider in RewriteProvider.values)
          provider.id: TextEditingController(),
      };
  final Set<String> _visibleKeys = <String>{};
  final Set<String> _busyProviders = <String>{};
  final Map<String, _RewriteKeyResult> _results = <String, _RewriteKeyResult>{};

  @override
  void dispose() {
    for (final controller in _keys.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save(RewriteProvider provider) async {
    final candidate = _keys[provider.id]!.text;
    setState(() {
      _busyProviders.add(provider.id);
      _results.remove(provider.id);
    });
    try {
      await widget.controller.saveRewriteKey(provider, candidate);
      if (!mounted) return;
      _keys[provider.id]!.clear();
      _results[provider.id] = const _RewriteKeyResult('Connected');
    } on PromptRewriteException catch (error) {
      _results[provider.id] = _RewriteKeyResult(error.message, failed: true);
    } on Object catch (error) {
      _results[provider.id] = _RewriteKeyResult(error.toString(), failed: true);
    } finally {
      if (mounted) setState(() => _busyProviders.remove(provider.id));
    }
  }

  Future<void> _remove(RewriteProvider provider) async {
    setState(() => _busyProviders.add(provider.id));
    try {
      await widget.controller.removeRewriteKey(provider);
      if (!mounted) return;
      setState(() => _results.remove(provider.id));
    } on Object catch (error) {
      if (!mounted) return;
      setState(
        () => _results[provider.id] = _RewriteKeyResult(
          error.toString(),
          failed: true,
        ),
      );
    } finally {
      if (mounted) setState(() => _busyProviders.remove(provider.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = widget.controller.connectedRewriteProviders;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CircleAvatar(
                backgroundColor: context.colors.primaryContainer,
                child: Icon(
                  Icons.auto_awesome_outlined,
                  color: context.colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'AI Rewrite',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Adds an AI Rewrite action to finished films: frames of '
                      'the film and its prompt go to the model you pick, and a '
                      'revised prompt opens in a new composer tab.',
                      style: TextStyle(color: context.colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          for (final provider in RewriteProvider.values) ...<Widget>[
            const SizedBox(height: 18),
            _RewriteProviderKey(
              provider: provider,
              connected: connected.contains(provider.id),
              keyController: _keys[provider.id]!,
              keyVisible: _visibleKeys.contains(provider.id),
              busy: _busyProviders.contains(provider.id),
              result: _results[provider.id],
              onToggleKey: () => setState(() {
                if (!_visibleKeys.remove(provider.id)) {
                  _visibleKeys.add(provider.id);
                }
              }),
              onSave: () => _save(provider),
              onRemove: () => _remove(provider),
            ),
          ],
        ],
      ),
    );
  }
}

class _RewriteKeyResult {
  const _RewriteKeyResult(this.message, {this.failed = false});

  final String message;
  final bool failed;
}

class _RewriteProviderKey extends StatelessWidget {
  const _RewriteProviderKey({
    required this.provider,
    required this.connected,
    required this.keyController,
    required this.keyVisible,
    required this.busy,
    required this.onToggleKey,
    required this.onSave,
    required this.onRemove,
    this.result,
  });

  final RewriteProvider provider;
  final bool connected;
  final TextEditingController keyController;
  final bool keyVisible;
  final bool busy;
  final _RewriteKeyResult? result;
  final VoidCallback onToggleKey;
  final Future<void> Function() onSave;
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context) {
    final status = result;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          key: ValueKey('rewrite-key-${provider.id}'),
          controller: keyController,
          obscureText: !keyVisible,
          autocorrect: false,
          enableSuggestions: false,
          enabled: !busy,
          decoration: InputDecoration(
            labelText: '${provider.name} API key',
            hintText: connected
                ? 'Connected — paste a replacement'
                : provider.keyHint,
            suffixIcon: IconButton(
              tooltip: keyVisible ? 'Hide key' : 'Show key',
              onPressed: onToggleKey,
              icon: Icon(
                keyVisible
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
              ),
            ),
          ),
        ),
        if (status != null || connected) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            status?.message ?? 'Connected',
            key: ValueKey('rewrite-key-status-${provider.id}'),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: status?.failed == true
                  ? context.colors.error
                  : context.colors.primary,
            ),
          ),
        ],
        const SizedBox(height: 11),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: <Widget>[
            BusyFilledButton(
              key: ValueKey('rewrite-key-save-${provider.id}'),
              onPressed: busy ? null : onSave,
              busyLabel: connected ? 'Replacing…' : 'Verifying…',
              child: Text(connected ? 'Replace key' : 'Verify & save'),
            ),
            if (connected)
              BusyTextButton(
                key: ValueKey('rewrite-key-remove-${provider.id}'),
                onPressed: busy ? null : onRemove,
                busyLabel: 'Removing…',
                child: Text(
                  'Remove',
                  style: TextStyle(color: context.colors.error),
                ),
              ),
            TextButton(
              onPressed: () =>
                  unawaited(launchUrl(Uri.parse(provider.consoleUrl))),
              child: const Text('Get a key ↗'),
            ),
          ],
        ),
      ],
    );
  }
}

class _StorageSection extends StatefulWidget {
  const _StorageSection({required this.controller});

  final AppController controller;

  @override
  State<_StorageSection> createState() => _StorageSectionState();
}

class _StorageSectionState extends State<_StorageSection> {
  AppController get controller => widget.controller;

  Future<bool> _confirm({
    required String title,
    required String detail,
    required String actionLabel,
    required Key actionKey,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Text(detail),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: actionKey,
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(actionLabel),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _changeLocation() async {
    if (controller.shellManagesDataRelocation) {
      // The desktop shell shows its own picker and confirmations, migrates
      // the files, and relaunches the app on success.
      await controller.relocateDataDirectoryViaShell();
      return;
    }
    final directory = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose a Clawnsole data folder',
      lockParentWindow: true,
    );
    if (directory == null || !mounted) return;
    final hasLibrary = await controller.dataDirectoryHasLibrary(directory);
    if (hasLibrary == null || !mounted) return;
    if (hasLibrary) {
      final adopt = await _confirm(
        title: 'Use the existing library?',
        detail:
            'That folder already contains a Clawnsole library. Clawnsole can '
            'switch to it as-is; your current library stays where it is and '
            'is no longer shown.',
        actionLabel: 'Use existing library',
        actionKey: const ValueKey('data-location-use-existing'),
      );
      if (!adopt || !mounted) return;
      await controller.relocateDataDirectory(
        directory,
        useExistingLibrary: true,
      );
      return;
    }
    final confirmed = await _confirm(
      title: 'Move Clawnsole data?',
      detail:
          'Your library file and assets will be copied to $directory and '
          'used from there. The current copy stays in the old folder until '
          'you delete it.',
      actionLabel: 'Move data',
      actionKey: const ValueKey('data-location-move-confirm'),
    );
    if (!confirmed || !mounted) return;
    await controller.relocateDataDirectory(directory);
  }

  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            CircleAvatar(
              backgroundColor: context.colors.secondaryContainer,
              child: Icon(
                Icons.storage_rounded,
                color: context.colors.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    controller.supportsGoogleDrive
                        ? controller.supportsLocalLibrary
                              ? 'Combined project data'
                              : 'Drive project data'
                        : 'Local project data',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    controller.supportsGoogleDrive
                        ? controller.supportsLocalLibrary
                              ? 'Local and Drive metadata, retained inputs, and finished media.'
                              : 'Drive metadata, retained inputs, and finished media.'
                        : 'Compact JSON plus retained reference inputs and finished videos.',
                  ),
                ],
              ),
            ),
            Text(
              formatBytes(
                controller.storage.bytes + controller.storage.assetBytes,
              ),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: <Widget>[
            Expanded(
              child: _Stat(
                value: formatBytes(controller.storage.bytes),
                label: 'Metadata',
              ),
            ),
            Expanded(
              child: _Stat(
                value: formatBytes(controller.storage.assetBytes),
                label: '${controller.storage.assets} assets',
              ),
            ),
            Expanded(
              child: _Stat(
                value: '${controller.storage.records}',
                label: 'Generations',
              ),
            ),
            Expanded(
              child: _Stat(
                value: controller.storage.lastUpdated == null
                    ? 'Not yet'
                    : relativeTime(controller.storage.lastUpdated!),
                label: 'Last write',
              ),
            ),
          ],
        ),
        if (controller.supportsGoogleDrive) ...<Widget>[
          const SizedBox(height: 15),
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Default for new generations and references',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (!controller.googleDriveConnected) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        'Connect Google Drive on the Sync desk to save new items there.',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              StorageDestinationButton(controller: controller),
            ],
          ),
        ],
        const SizedBox(height: 15),
        _LocalVideoCacheControl(controller: controller, thumbnails: true),
        const SizedBox(height: 12),
        _LocalVideoCacheControl(controller: controller),
        const SizedBox(height: 15),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'DATA FILE',
                style: TextStyle(
                  fontSize: 9.5,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700,
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 5),
              SelectableText(
                controller.storage.path.isEmpty
                    ? 'Not created yet'
                    : controller.storage.path,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
              const SizedBox(height: 8),
              Text(
                controller.gateway.persistenceDescription,
                style: const TextStyle(fontSize: 11.5, height: 1.4),
              ),
            ],
          ),
        ),
        if (controller.supportsRevealDataFolder ||
            controller.supportsDataRelocation) ...<Widget>[
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              if (controller.supportsRevealDataFolder)
                OutlinedButton.icon(
                  key: const ValueKey('storage-open-folder'),
                  onPressed: () => unawaited(controller.revealDataFolder()),
                  icon: const Icon(Icons.folder_open_rounded, size: 17),
                  label: const Text('Open folder'),
                ),
              if (controller.supportsDataRelocation)
                BusyOutlinedButton.icon(
                  key: const ValueKey('storage-change-location'),
                  busy: controller.dataRelocationBusy,
                  busyLabel: 'Moving library…',
                  onPressed: _changeLocation,
                  icon: const Icon(Icons.drive_folder_upload_rounded, size: 17),
                  label: const Text('Change location…'),
                ),
            ],
          ),
        ],
      ],
    ),
  );
}

/// One of the independent local cache caps for Drive previews and full films.
class _LocalVideoCacheControl extends StatefulWidget {
  const _LocalVideoCacheControl({
    required this.controller,
    this.thumbnails = false,
  });

  final AppController controller;
  final bool thumbnails;

  @override
  State<_LocalVideoCacheControl> createState() =>
      _LocalVideoCacheControlState();
}

class _LocalVideoCacheControlState extends State<_LocalVideoCacheControl> {
  static const List<int> _caps = <int>[0, 50, 100, 250, 500, 1024, 2048, 5120];

  Future<int>? _usage;
  bool _updating = false;

  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _refreshUsage();
  }

  void _refreshUsage() {
    _usage = controller.supportsVideoCache
        ? widget.thumbnails
              ? controller.thumbnailCacheUsedBytes()
              : controller.videoCacheUsedBytes()
        : null;
  }

  String _capLabel(int megabytes) => switch (megabytes) {
    0 => 'Off',
    >= 1024 => '${megabytes ~/ 1024} GB',
    _ => '$megabytes MB',
  };

  Future<void> _setCap(int megabytes) async {
    setState(() => _updating = true);
    try {
      if (widget.thumbnails) {
        await controller.setLocalThumbnailCacheMb(megabytes);
      } else {
        await controller.setLocalVideoCacheMb(megabytes);
      }
    } finally {
      if (mounted) {
        setState(() {
          _updating = false;
          _refreshUsage();
        });
      }
    }
  }

  Future<void> _clear() async {
    setState(() => _updating = true);
    try {
      if (widget.thumbnails) {
        await controller.clearThumbnailCache();
      } else {
        await controller.clearVideoCache();
      }
    } finally {
      if (mounted) {
        setState(() {
          _updating = false;
          _refreshUsage();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.thumbnails
        ? controller.localThumbnailCacheMb
        : controller.localVideoCacheMb;
    final keyPrefix = widget.thumbnails
        ? 'local-thumbnail-cache'
        : 'local-video-cache';
    final caps = <int>[..._caps];
    if (!caps.contains(current)) {
      // A cap synced from another surface may not match a menu step; keep
      // the stored value selectable instead of breaking the dropdown.
      caps
        ..add(current)
        ..sort();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        DropdownButtonFormField<int>(
          key: ValueKey('$keyPrefix-cap'),
          initialValue: current,
          decoration: InputDecoration(
            labelText: widget.thumbnails
                ? 'Local thumbnail cache'
                : 'Local video cache',
            helperText: widget.thumbnails
                ? 'Keeps Drive images and video previews on this device for instant library loading. Off clears only previews.'
                : 'Keeps complete recent Drive films on this device for instant replay after relaunch. Off stops video prefetching and clears only films.',
            helperMaxLines: 3,
          ),
          items: caps
              .map(
                (cap) => DropdownMenuItem<int>(
                  value: cap,
                  child: Text(_capLabel(cap)),
                ),
              )
              .toList(),
          onChanged: _updating
              ? null
              : (cap) {
                  if (cap != null) unawaited(_setCap(cap));
                },
        ),
        if (controller.supportsVideoCache) ...<Widget>[
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: FutureBuilder<int>(
                  future: _usage,
                  builder: (context, snapshot) {
                    final loading =
                        _updating ||
                        snapshot.connectionState != ConnectionState.done;
                    return Row(
                      key: ValueKey('$keyPrefix-usage'),
                      children: <Widget>[
                        if (loading) ...<Widget>[
                          const BusySpinner(),
                          const SizedBox(width: 7),
                        ],
                        Text(
                          loading
                              ? _updating
                                    ? 'Updating cache…'
                                    : 'Measuring cache…'
                              : 'Cached now: ${formatBytes(snapshot.data ?? 0)}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              BusyTextButton.icon(
                key: ValueKey('$keyPrefix-clear'),
                busy: _updating,
                busyLabel: 'Updating…',
                onPressed: _clear,
                icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                label: const Text('Clear'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _GoogleDriveSection extends StatefulWidget {
  const _GoogleDriveSection({required this.controller});

  final AppController controller;

  @override
  State<_GoogleDriveSection> createState() => _GoogleDriveSectionState();
}

class _GoogleDriveSectionState extends State<_GoogleDriveSection> {
  late final TextEditingController _folder = TextEditingController(
    text: widget.controller.googleDriveConnection.folderName.isEmpty
        ? 'Clawnsole'
        : widget.controller.googleDriveConnection.folderName,
  );

  @override
  void dispose() {
    _folder.dispose();
    super.dispose();
  }

  /// The move runs behind the key that confirmed it — copying, verifying and
  /// then removing every local original is minutes of work, not a blink — and
  /// the dialog closes once Drive has it all.
  Future<void> _confirmMoveToDrive() => showDialog<void>(
    context: context,
    builder: (dialogContext) => BusyGate(
      child: BusyGateBuilder(
        builder: (context, moving) => PopScope(
          canPop: !moving,
          child: AlertDialog(
            title: const Text('Move the local library to Drive?'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: const Text(
                'Clawnsole copies every local generation and reference to '
                'Google Drive, verifies the copies, and then removes the '
                'local originals. Afterwards this library exists only in '
                'Drive.',
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: moving
                    ? null
                    : () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              BusyFilledButton(
                key: const ValueKey('drive-move-confirm'),
                busyLabel: 'Moving…',
                onPressed: () async {
                  await widget.controller.moveLocalLibraryToGoogleDrive();
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                },
                child: const Text('Move and remove local copies'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final connection = widget.controller.googleDriveConnection;
    final connected = connection.isConnected;
    final unavailable =
        connection.state == GoogleDriveConnectionState.unavailable;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              CircleAvatar(
                backgroundColor: context.colors.primaryContainer,
                child: Icon(
                  Icons.cloud_sync_rounded,
                  color: context.colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Google Drive library',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      connected
                          ? 'Synced with “${connection.folderName}”.'
                          : 'Use one portable library across every Clawnsole surface.',
                    ),
                    if (connected &&
                        widget.controller.pendingDriveUploadCount > 0) ...[
                      const SizedBox(height: 3),
                      Text(
                        key: const ValueKey('drive-upload-backlog'),
                        'Backing up '
                        '${widget.controller.pendingDriveUploadCount} '
                        '${widget.controller.pendingDriveUploadCount == 1 ? 'file' : 'files'} '
                        'to Drive in the background…',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.controller.googleDriveBusy)
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                )
              else
                Icon(
                  connected
                      ? Icons.cloud_done_rounded
                      : Icons.cloud_off_rounded,
                  color: connected
                      ? context.colors.primary
                      : context.colors.onSurfaceVariant,
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _folder,
            enabled: !connected && !widget.controller.googleDriveBusy,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: 'Drive folder name',
              helperText:
                  'Clawnsole creates or reopens an app-owned folder with this name.',
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              if (!connected)
                BusyFilledButton.icon(
                  onPressed: unavailable || widget.controller.googleDriveBusy
                      ? null
                      : () =>
                            widget.controller.connectGoogleDrive(_folder.text),
                  busyLabel: 'Connecting…',
                  icon: const Icon(Icons.add_to_drive_rounded, size: 18),
                  label: const Text('Connect Drive'),
                )
              else ...<Widget>[
                BusyFilledButton.tonalIcon(
                  onPressed: widget.controller.googleDriveBusy
                      ? null
                      : widget.controller.refreshGoogleDrive,
                  busyLabel: 'Working…',
                  icon: const Icon(Icons.sync_rounded, size: 18),
                  label: const Text('Refresh'),
                ),
                BusyOutlinedButton.icon(
                  key: const ValueKey('drive-disconnect'),
                  onPressed: widget.controller.googleDriveBusy
                      ? null
                      : widget.controller.disconnectGoogleDrive,
                  busyLabel: 'Disconnecting…',
                  icon: const Icon(Icons.link_off_rounded, size: 18),
                  label: const Text('Disconnect this device'),
                ),
                if (widget.controller.supportsLocalLibrary &&
                    (widget.controller.generations.any(
                          (item) => item.storage == LibraryStorage.local,
                        ) ||
                        widget.controller.savedReferences.any(
                          (item) => item.storage == LibraryStorage.local,
                        ))) ...<Widget>[
                  BusyOutlinedButton.icon(
                    key: const ValueKey('drive-copy-local-library'),
                    onPressed: widget.controller.googleDriveBusy
                        ? null
                        : widget.controller.copyLocalLibraryToGoogleDrive,
                    busyLabel: 'Copying…',
                    icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                    label: const Text('Copy local library to Drive'),
                  ),
                  // This key only asks; the dialog's own key does the move
                  // and carries the loader for it.
                  OutlinedButton.icon(
                    key: const ValueKey('drive-move-local-library'),
                    onPressed: widget.controller.googleDriveBusy
                        ? null
                        : () => unawaited(_confirmMoveToDrive()),
                    icon: const Icon(Icons.drive_file_move_outline, size: 18),
                    label: const Text('Move local library to Drive'),
                  ),
                ],
              ],
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              unavailable
                  ? connection.message
                  : 'Drive items include generated media, references, and folders. Provider keys and preferences stay in secure storage and sync only through your passphrase-encrypted vault when enabled. Copying local items keeps the originals.',
              style: const TextStyle(fontSize: 11.5, height: 1.4),
            ),
          ),
          if (connection.message.isNotEmpty && !unavailable) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              connection.message,
              style: TextStyle(
                fontSize: 11,
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
          if (widget.controller.supportsSettingsVault) ...<Widget>[
            const Divider(height: 32),
            _SettingsVaultPanel(controller: widget.controller),
          ],
        ],
      ),
    );
  }
}

class _SettingsVaultPassphraseDialog extends StatefulWidget {
  const _SettingsVaultPassphraseDialog({
    required this.title,
    required this.detail,
    required this.actionLabel,
    required this.confirm,
  });

  final String title;
  final String detail;
  final String actionLabel;
  final bool confirm;

  @override
  State<_SettingsVaultPassphraseDialog> createState() =>
      _SettingsVaultPassphraseDialogState();
}

class _SettingsVaultPassphraseDialogState
    extends State<_SettingsVaultPassphraseDialog> {
  static const _maximumEncodedBytes = 1024;

  final _passphrase = TextEditingController();
  final _confirmation = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _passphrase.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _passphrase.text;
    if (value.isEmpty || (widget.confirm && value.runes.length < 12)) {
      setState(() {
        _error = widget.confirm
            ? 'Enter at least 12 characters.'
            : 'Enter your sync passphrase.';
      });
      return;
    }
    if (utf8.encode(value).length > _maximumEncodedBytes) {
      setState(() {
        _error = 'The passphrase must be at most 1,024 encoded bytes.';
      });
      return;
    }
    if (widget.confirm && value != _confirmation.text) {
      setState(() {
        _error = 'The passphrases do not match exactly.';
      });
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(widget.detail),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('settings-vault-passphrase'),
              controller: _passphrase,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              autofocus: true,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Sync passphrase',
                helperText: widget.confirm
                    ? 'Use at least 12 characters. Spaces count.'
                    : 'Enter it exactly. Spaces count.',
              ),
            ),
            if (widget.confirm) ...<Widget>[
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('settings-vault-passphrase-confirmation'),
                controller: _confirmation,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: 'Confirm sync passphrase',
                ),
              ),
            ],
            if (_error != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                _error!,
                key: const ValueKey('settings-vault-passphrase-error'),
                style: TextStyle(color: context.colors.error),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('settings-vault-passphrase-submit'),
        onPressed: _submit,
        child: Text(widget.actionLabel),
      ),
    ],
  );
}

class _SettingsVaultRecoveryDialog extends StatefulWidget {
  const _SettingsVaultRecoveryDialog();

  @override
  State<_SettingsVaultRecoveryDialog> createState() =>
      _SettingsVaultRecoveryDialogState();
}

class _SettingsVaultRecoveryDialogState
    extends State<_SettingsVaultRecoveryDialog> {
  final _recoveryCode = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _recoveryCode.dispose();
    super.dispose();
  }

  void _submit() {
    if (_recoveryCode.text.isEmpty) {
      setState(() => _error = 'Enter your recovery code.');
      return;
    }
    Navigator.pop(context, _recoveryCode.text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Use recovery code'),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text(
            'Enter the recovery code exactly as it was shown when the vault was created.',
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('settings-vault-recovery-input'),
            controller: _recoveryCode,
            autocorrect: false,
            enableSuggestions: false,
            autofocus: true,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(labelText: 'Recovery code'),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: context.colors.error)),
          ],
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('settings-vault-recovery-submit'),
        onPressed: _submit,
        child: const Text('Recover'),
      ),
    ],
  );
}

class _SettingsVaultPanel extends StatefulWidget {
  const _SettingsVaultPanel({required this.controller});

  final AppController controller;

  @override
  State<_SettingsVaultPanel> createState() => _SettingsVaultPanelState();
}

class _SettingsVaultPanelState extends State<_SettingsVaultPanel> {
  Future<String?> _requestPassphrase({
    required String title,
    required String detail,
    required String actionLabel,
    bool confirm = false,
  }) => showDialog<String>(
    context: context,
    builder: (dialogContext) => _SettingsVaultPassphraseDialog(
      title: title,
      detail: detail,
      actionLabel: actionLabel,
      confirm: confirm,
    ),
  );

  Future<String?> _requestRecoveryCode() => showDialog<String>(
    context: context,
    builder: (dialogContext) => const _SettingsVaultRecoveryDialog(),
  );

  Future<void> _showRecoveryCode(String recoveryCode) async {
    var acknowledged = false;
    var copied = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => PopScope(
          canPop: acknowledged,
          child: AlertDialog(
            title: const Text('Save your recovery code'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text(
                    'This is shown once. Store it in a password manager. It can unlock your encrypted settings if you forget the passphrase.',
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SelectableText(
                      recoveryCode,
                      key: const ValueKey('settings-vault-recovery-code'),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    key: const ValueKey('settings-vault-recovery-copy'),
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: recoveryCode),
                      );
                      setDialogState(() => copied = true);
                    },
                    icon: Icon(
                      copied ? Icons.check_rounded : Icons.copy_rounded,
                      size: 17,
                    ),
                    label: Text(copied ? 'Copied' : 'Copy recovery code'),
                  ),
                  CheckboxListTile(
                    key: const ValueKey('settings-vault-recovery-ack'),
                    contentPadding: EdgeInsets.zero,
                    value: acknowledged,
                    onChanged: (value) =>
                        setDialogState(() => acknowledged = value == true),
                    title: const Text(
                      'I saved this recovery code somewhere safe.',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              FilledButton(
                key: const ValueKey('settings-vault-recovery-done'),
                onPressed: acknowledged
                    ? () => Navigator.pop(dialogContext)
                    : null,
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _setup() async {
    final passphrase = await _requestPassphrase(
      title: 'Set up encrypted settings sync',
      detail:
          'Your provider keys and preferences will be encrypted before they are stored in Google Drive. You will enter this passphrase once on each new device.',
      actionLabel: 'Create vault',
      confirm: true,
    );
    if (passphrase == null || !mounted) return;
    final recoveryCode = await widget.controller.setupSettingsVault(passphrase);
    if (!mounted) return;
    setState(() {});
    if (recoveryCode != null && recoveryCode.isNotEmpty) {
      await _showRecoveryCode(recoveryCode);
    }
  }

  Future<void> _unlock() async {
    final passphrase = await _requestPassphrase(
      title: 'Unlock encrypted settings',
      detail:
          'Enter your sync passphrase once. Clawnsole will remember the vault key securely on this device.',
      actionLabel: 'Unlock',
    );
    if (passphrase == null || !mounted) return;
    await widget.controller.unlockSettingsVault(passphrase);
    if (mounted) setState(() {});
  }

  Future<void> _recover() async {
    final recoveryCode = await _requestRecoveryCode();
    if (recoveryCode == null || !mounted) return;
    await widget.controller.recoverSettingsVault(recoveryCode);
    if (mounted) setState(() {});
  }

  Future<void> _changePassphrase() async {
    final passphrase = await _requestPassphrase(
      title: 'Change sync passphrase',
      detail:
          'Use the new passphrase on future devices. Devices that already remember this vault remain connected.',
      actionLabel: 'Change passphrase',
      confirm: true,
    );
    if (passphrase == null || !mounted) return;
    await widget.controller.changeSettingsVaultPassphrase(passphrase);
    if (mounted) setState(() {});
  }

  Future<void> _forget() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Forget vault unlock on this device?'),
        content: const Text(
          'Your local provider keys and encrypted Drive vault will be kept. You will need the passphrase or recovery code before this device can sync them again.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('settings-vault-forget-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Forget unlock'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.controller.forgetSettingsVaultUnlock();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.controller.settingsVaultStatus;
    final busy =
        widget.controller.settingsVaultBusy ||
        status.state == SettingsVaultState.syncing;
    final (icon, title, detail) = switch (status.state) {
      SettingsVaultState.unavailable => (
        Icons.lock_outline_rounded,
        'Encrypted settings sync unavailable',
        'This build cannot access the secure settings vault.',
      ),
      SettingsVaultState.driveDisconnected => (
        Icons.cloud_off_rounded,
        'Encrypted settings sync paused',
        'Connect Google Drive to set up or resume encrypted provider-key and preference sync.',
      ),
      SettingsVaultState.setupRequired => (
        Icons.enhanced_encryption_outlined,
        'Protect and sync provider keys',
        'Create a sync passphrase once, then enter it on each new device. The passphrase is never stored.',
      ),
      SettingsVaultState.locked => (
        Icons.lock_rounded,
        'Encrypted settings are locked',
        'This Drive has a Clawnsole vault. Unlock it once on this device with your passphrase or recovery code.',
      ),
      SettingsVaultState.syncing => (
        Icons.sync_rounded,
        'Syncing encrypted settings',
        'Provider keys and preferences are being encrypted and synchronized.',
      ),
      SettingsVaultState.ready => (
        Icons.verified_user_rounded,
        'Encrypted settings are synced',
        'Provider keys and preferences are encrypted before they leave this device.',
      ),
      SettingsVaultState.pending => (
        Icons.cloud_upload_outlined,
        'Encrypted settings sync pending',
        'Your latest settings are secure on this device and will remain pending until Drive sync succeeds.',
      ),
      SettingsVaultState.error => (
        Icons.sync_problem_rounded,
        'Encrypted settings need attention',
        'Your local provider keys remain available. Try syncing again or unlock the vault again if prompted.',
      ),
    };
    final message = status.message.trim();
    return Container(
      key: const ValueKey('settings-vault-panel'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, color: context.colors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(detail, style: const TextStyle(height: 1.35)),
                  ],
                ),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.only(left: 10),
                  child: BusySpinner(),
                ),
            ],
          ),
          if (status.lastSyncedAt != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              'Last synced ${relativeTime(status.lastSyncedAt!)}',
              style: TextStyle(
                fontSize: 11,
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
          if (message.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              message,
              key: const ValueKey('settings-vault-status-message'),
              style: TextStyle(
                fontSize: 11,
                color: status.state == SettingsVaultState.error
                    ? context.colors.error
                    : context.colors.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: switch (status.state) {
              SettingsVaultState.setupRequired => <Widget>[
                FilledButton.icon(
                  key: const ValueKey('settings-vault-setup'),
                  onPressed: busy ? null : _setup,
                  icon: const Icon(Icons.lock_rounded, size: 17),
                  label: const Text('Set up encrypted sync'),
                ),
              ],
              SettingsVaultState.locked => <Widget>[
                FilledButton.icon(
                  key: const ValueKey('settings-vault-unlock'),
                  onPressed: busy ? null : _unlock,
                  icon: const Icon(Icons.lock_open_rounded, size: 17),
                  label: const Text('Unlock with passphrase'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('settings-vault-recover'),
                  onPressed: busy ? null : _recover,
                  icon: const Icon(Icons.key_rounded, size: 17),
                  label: const Text('Use recovery code'),
                ),
              ],
              SettingsVaultState.ready ||
              SettingsVaultState.pending => <Widget>[
                FilledButton.tonalIcon(
                  key: const ValueKey('settings-vault-sync'),
                  onPressed: busy ? null : widget.controller.syncSettingsVault,
                  icon: const Icon(Icons.sync_rounded, size: 17),
                  label: const Text('Sync now'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('settings-vault-change-passphrase'),
                  onPressed: busy ? null : _changePassphrase,
                  icon: const Icon(Icons.password_rounded, size: 17),
                  label: const Text('Change passphrase'),
                ),
                TextButton.icon(
                  key: const ValueKey('settings-vault-forget'),
                  onPressed: busy ? null : _forget,
                  icon: const Icon(Icons.phonelink_erase_rounded, size: 17),
                  label: const Text('Forget cached unlock'),
                ),
              ],
              SettingsVaultState.error => <Widget>[
                FilledButton.tonalIcon(
                  key: const ValueKey('settings-vault-sync'),
                  onPressed: busy ? null : widget.controller.syncSettingsVault,
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                  label: const Text('Try sync again'),
                ),
                TextButton.icon(
                  key: const ValueKey('settings-vault-forget'),
                  onPressed: busy ? null : _forget,
                  icon: const Icon(Icons.phonelink_erase_rounded, size: 17),
                  label: const Text('Forget cached unlock'),
                ),
              ],
              _ => const <Widget>[],
            },
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      Text(
        value,
        style: const TextStyle(
          fontFamily: 'Fraunces',
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          color: context.colors.onSurfaceVariant,
        ),
      ),
    ],
  );
}

/// What the library has room for, on the Storage desk beside the figures it
/// describes.
class _LibraryRoomPanel extends StatelessWidget {
  const _LibraryRoomPanel({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final ink = PanelSurface.plumLeather.ink(context.tokens);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TexturePanel(
          stitched: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ClawMark(size: 30, color: ink.accent),
              const SizedBox(height: 13),
              Text(
                'Room to stretch.',
                style: Theme.of(
                  context,
                ).textTheme.headlineMedium?.copyWith(color: ink.on),
              ),
              const SizedBox(height: 8),
              Text(
                controller.supportsGoogleDrive
                    ? controller.supportsLocalLibrary
                          ? 'Local and Drive items appear together with clear badges. Retained media is pruned only when nothing else uses it.'
                          : 'Drive keeps this browser’s portable library. Retained media is pruned only when nothing else uses it.'
                    : 'History is uncapped. Saved references stay local until you delete them; retained generation media is pruned only when nothing else uses it.',
                style: TextStyle(color: ink.onMuted),
              ),
              if (controller.gateway.usesCompanion) ...<Widget>[
                const SizedBox(height: 13),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: ink.on.withValues(alpha: .07),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'WEB MODE · Local companion active. No localStorage or IndexedDB history is used.',
                    style: TextStyle(
                      color: ink.accent,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .4,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The Data desk: the three actions that take something away.
class _ClearDataCard extends StatelessWidget {
  const _ClearDataCard({required this.controller, required this.confirm});

  final AppController controller;
  final Future<bool> Function(String title, String detail) confirm;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                controller.supportsGoogleDrive
                    ? 'Clear Clawnsole data'
                    : 'Clear local data',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 5),
              Text(
                controller.supportsGoogleDrive
                    ? controller.supportsLocalLibrary
                          ? 'These actions cover both Local and connected Drive items. Provider keys remain in secure storage and may also exist in your encrypted sync vault.'
                          : 'These actions cover connected Drive items and this device’s secure settings.'
                    : 'These actions update only Clawnsole data on this device.',
              ),
              const SizedBox(height: 12),
              _ClearButton(
                icon: Icons.delete_sweep_outlined,
                title: 'Clear history',
                subtitle: 'Generation records and unshared media',
                confirm: () => confirm(
                  'Clear generation history?',
                  'This keeps saved references, their folders and tags, your API keys, and preferences.',
                ),
                onTap: controller.clearHistory,
              ),
              _ClearButton(
                icon: Icons.restart_alt_rounded,
                title: 'Reset preferences',
                subtitle: 'Navigation and filter state',
                onTap: controller.clearPreferences,
              ),
              _ClearButton(
                icon: Icons.warning_amber_rounded,
                title: controller.supportsGoogleDrive
                    ? controller.supportsLocalLibrary
                          ? 'Delete Local and Drive data'
                          : 'Delete Drive and device data'
                    : 'Delete all local data',
                subtitle:
                    'History, saved references, assets, preferences, and securely stored provider keys',
                danger: true,
                confirm: () => confirm(
                  controller.supportsGoogleDrive
                      ? controller.supportsLocalLibrary
                            ? 'Delete Local and Drive data?'
                            : 'Delete Drive and device data?'
                      : 'Delete all local data?',
                  controller.supportsGoogleDrive
                      ? controller.supportsLocalLibrary
                            ? 'This permanently removes Clawnsole metadata and assets from this device and the connected Drive folder, plus provider keys from secure storage.'
                            : 'This permanently removes Clawnsole metadata and assets from the connected Drive folder, plus this device’s secure settings.'
                      : 'This permanently removes the Flutter app’s local JSON file.',
                ),
                onTap: controller.clearAll,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The General desk's tail: where to read more, and who made this.
class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      for (final provider in videoProviders) ...<Widget>[
        OutlinedButton.icon(
          key: ValueKey('provider-documentation-${provider.id}'),
          onPressed: () => unawaited(launchUrl(Uri.parse(provider.docsUrl))),
          icon: const Icon(Icons.open_in_new_rounded, size: 16),
          label: Text(
            provider.id == bflProvider.id
                ? 'FLUX 3 documentation'
                : '${provider.name} documentation',
          ),
        ),
        const SizedBox(height: 8),
      ],
      OutlinedButton.icon(
        onPressed: () =>
            unawaited(launchUrl(Uri.parse(clawnsolePrivacyPolicyUrl))),
        icon: const Icon(Icons.privacy_tip_outlined, size: 16),
        label: const Text('Privacy policy'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () =>
            showLicensePage(context: context, applicationName: 'Clawnsole'),
        icon: const Icon(Icons.article_outlined, size: 16),
        label: const Text('Open source licenses'),
      ),
      const SizedBox(height: 15),
      const _CreatorCard(),
    ],
  );
}

class _CreatorCard extends StatelessWidget {
  const _CreatorCard();

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: EdgeInsets.zero,
    child: Semantics(
      link: true,
      label: 'Made by Alexandria — opens heresalexandria.com',
      child: InkWell(
        key: const ValueKey('alexandria-profile-link'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => unawaited(launchUrl(Uri.parse(alexandriaWebsiteUrl))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              const CircleAvatar(
                radius: 21,
                backgroundImage: AssetImage('assets/profile-alexandria.jpg'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Made by Alexandria',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Visit heresalexandria.com',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.open_in_new_rounded,
                size: 17,
                color: context.colors.primary,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// A destructive settings row. Clearing history or deleting a library walks
/// the store and the Drive folder, so the tile shows the work and refuses a
/// second tap until it is done.
class _ClearButton extends StatefulWidget {
  const _ClearButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.confirm,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// Asked before [onTap] runs, and outside its loader.
  final Future<bool> Function()? confirm;
  final Future<void> Function() onTap;
  final bool danger;

  @override
  State<_ClearButton> createState() => _ClearButtonState();
}

class _ClearButtonState extends State<_ClearButton> {
  bool _running = false;

  Future<void> _run() async {
    if (_running) return;
    // The question is asked before the loader starts: a tile that spins
    // while a confirmation is still on screen would be lying.
    final confirm = widget.confirm;
    if (confirm != null && !await confirm()) return;
    if (!mounted) return;
    setState(() => _running = true);
    try {
      await widget.onTap();
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tint = widget.danger ? context.colors.error : context.colors.primary;
    return ListTile(
      key: ValueKey('clear-${widget.title}'),
      contentPadding: EdgeInsets.zero,
      enabled: !_running,
      leading: Icon(widget.icon, color: tint),
      title: Text(
        widget.title,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: widget.danger ? context.colors.error : null,
        ),
      ),
      subtitle: Text(widget.subtitle, style: const TextStyle(fontSize: 11)),
      trailing: _running
          ? BusySpinner(color: tint)
          : const Icon(Icons.chevron_right_rounded, size: 17),
      onTap: () => unawaited(_run()),
    );
  }
}
