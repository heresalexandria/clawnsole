import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import '../core/models.dart';
import '../core/provider_catalog.dart';
import '../core/reference_prompts.dart';
import 'common_widgets.dart';
import 'claw_mark.dart';
import 'formatters.dart';
import 'hardware.dart';
import 'panels.dart';
import 'reference_prompt_field.dart';
import 'references_screen.dart';

class CreateScreen extends StatelessWidget {
  const CreateScreen({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final split = constraints.maxWidth >= 1160;
      return SingleChildScrollView(
        padding: EdgeInsets.all(constraints.maxWidth < 620 ? 16 : 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _CreateHeading(controller: controller),
                const SizedBox(height: 26),
                if (split)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        flex: 7,
                        child: _Composer(controller: controller),
                      ),
                      const SizedBox(width: 22),
                      Expanded(
                        flex: 4,
                        child: _RecentWork(controller: controller),
                      ),
                    ],
                  )
                else ...<Widget>[
                  _Composer(controller: controller),
                  const SizedBox(height: 24),
                  _RecentWork(controller: controller),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _CreateHeading extends StatelessWidget {
  const _CreateHeading({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final title = ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 650),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Eyebrow(
              controller.selectedProvider.isLocal
                  ? 'On-device image studio'
                  : 'Video studio',
            ),
            const SizedBox(height: 10),
            Text(
              controller.selectedProvider.isLocal
                  ? 'Make it local.'
                  : 'Make it move.',
              style: Theme.of(context).textTheme.displayLarge,
            ),
            const SizedBox(height: 10),
            Text(
              controller.selectedProvider.isLocal
                  ? 'Create private still images on this Apple device, with no account or API key.'
                  : 'Direct one continuous moment, pin the important frames, and let Clawnsole mind the render.',
              style: TextStyle(color: context.colors.onSurfaceVariant),
            ),
          ],
        ),
      );
      final plaque = _ProviderPlaque(controller: controller);
      // Wide layouts pin the plaque to the far right of the page; narrow ones
      // stack it under the title rather than squeezing both onto one line.
      if (constraints.maxWidth < 720) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[title, const SizedBox(height: 16), plaque],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: title),
          ),
          const SizedBox(width: 22),
          plaque,
        ],
      );
    },
  );
}

class _ProviderPlaque extends StatefulWidget {
  const _ProviderPlaque({required this.controller});

  final AppController controller;

  @override
  State<_ProviderPlaque> createState() => _ProviderPlaqueState();
}

class _ProviderPlaqueState extends State<_ProviderPlaque> {
  final Set<String> _collapsedProviders = <String>{};

  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _collapsedProviders.addAll(
      controller.providers
          .where((provider) => provider.id != controller.selectedProviderId)
          .map((provider) => provider.id),
    );
  }

  Future<void> _select(String value) async {
    final divider = value.indexOf('|');
    final provider = value.substring(0, divider);
    final model = value.substring(divider + 1);
    if (mounted) setState(() => _collapsedProviders.remove(provider));
    if (controller.selectedProviderId != provider) {
      await controller.selectProvider(provider);
    }
    await controller.selectModel(model);
  }

  @override
  Widget build(BuildContext context) {
    final ink = PanelSurface.navyLeather.ink(context.tokens);
    return TexturePanel(
      surface: PanelSurface.navyLeather,
      stitched: true,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      child: PopupMenuButton<String>(
        tooltip: 'Choose provider and model',
        onSelected: (value) => unawaited(_select(value)),
        constraints: const BoxConstraints(minWidth: 340, maxWidth: 420),
        itemBuilder: (context) => <PopupMenuEntry<String>>[
          PopupMenuItem<String>(
            enabled: false,
            padding: EdgeInsets.zero,
            child: _ProviderSearchMenu(
              providers: controller.providers,
              collapsedProviders: _collapsedProviders,
              selectedProviderId: controller.selectedProviderId,
              selectedModelId: controller.selectedModel.id,
              onExpandedChanged: (providerId, expanded) {
                if (expanded) {
                  _collapsedProviders.remove(providerId);
                } else {
                  _collapsedProviders.add(providerId);
                }
              },
            ),
          ),
        ],
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: ink.accent),
                color: ink.on.withValues(alpha: .06),
              ),
              child: Text(
                controller.selectedProvider.shortName,
                style: TextStyle(
                  color: ink.accent,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .5,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'MODEL & PROVIDER',
                  style: TextStyle(
                    color: ink.onMuted,
                    fontSize: 8.5,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  controller.selectedProvider.name,
                  style: TextStyle(
                    color: ink.on,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  controller.selectedModel.label,
                  style: TextStyle(color: ink.onMuted, fontSize: 10.5),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Icon(Icons.unfold_more_rounded, size: 17, color: ink.accent),
          ],
        ),
      ),
    );
  }
}

class _ProviderSearchMenu extends StatefulWidget {
  const _ProviderSearchMenu({
    required this.providers,
    required this.collapsedProviders,
    required this.selectedProviderId,
    required this.selectedModelId,
    required this.onExpandedChanged,
  });

  final List<VideoProviderDefinition> providers;
  final Set<String> collapsedProviders;
  final String selectedProviderId;
  final String selectedModelId;
  final void Function(String providerId, bool expanded) onExpandedChanged;

  @override
  State<_ProviderSearchMenu> createState() => _ProviderSearchMenuState();
}

class _ProviderSearchMenuState extends State<_ProviderSearchMenu> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final terms = query.split(RegExp(r'\s+')).where((term) => term.isNotEmpty);
    bool containsAll(String value) {
      final haystack = value.toLowerCase();
      return terms.every(haystack.contains);
    }

    final matches =
        <
          ({
            VideoProviderDefinition provider,
            List<VideoModelDefinition> models,
          })
        >[];
    for (final provider in widget.providers) {
      final providerIdentity =
          '${provider.name} ${provider.shortName} ${provider.id}';
      final providerMatches = query.isNotEmpty && containsAll(providerIdentity);
      final models = query.isEmpty || providerMatches
          ? provider.models
          : provider.models
                .where(
                  (model) => containsAll(
                    '$providerIdentity ${model.label} ${model.id} ${model.canonicalId}',
                  ),
                )
                .toList();
      if (models.isNotEmpty) matches.add((provider: provider, models: models));
    }
    final menuHeight = (MediaQuery.sizeOf(context).height * .68)
        .clamp(320.0, 560.0)
        .toDouble();
    return SizedBox(
      width: 400,
      height: menuHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: TextField(
              key: const ValueKey('provider-model-search'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search models or providers',
                prefixIcon: const Icon(Icons.search_rounded, size: 19),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _search.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                isDense: true,
              ),
            ),
          ),
          Divider(height: 1, color: context.colors.outlineVariant),
          Expanded(
            child: matches.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No models or providers match.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                : ListView(
                    padding: EdgeInsets.zero,
                    children: matches
                        .map(
                          (match) => _ProviderMenuSection(
                            key: ValueKey(
                              'provider-model-section-${match.provider.id}',
                            ),
                            provider: match.provider,
                            models: match.models,
                            forceExpanded: query.isNotEmpty,
                            initiallyExpanded: !widget.collapsedProviders
                                .contains(match.provider.id),
                            selectedProviderId: widget.selectedProviderId,
                            selectedModelId: widget.selectedModelId,
                            onExpandedChanged: (expanded) => widget
                                .onExpandedChanged(match.provider.id, expanded),
                          ),
                        )
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ProviderMenuSection extends StatefulWidget {
  const _ProviderMenuSection({
    required this.provider,
    required this.models,
    required this.forceExpanded,
    required this.initiallyExpanded,
    required this.selectedProviderId,
    required this.selectedModelId,
    required this.onExpandedChanged,
    super.key,
  });

  final VideoProviderDefinition provider;
  final List<VideoModelDefinition> models;
  final bool forceExpanded;
  final bool initiallyExpanded;
  final String selectedProviderId;
  final String selectedModelId;
  final ValueChanged<bool> onExpandedChanged;

  @override
  State<_ProviderMenuSection> createState() => _ProviderMenuSectionState();
}

class _ProviderMenuSectionState extends State<_ProviderMenuSection> {
  late bool _expanded = widget.initiallyExpanded;

  void _toggle() {
    setState(() => _expanded = !_expanded);
    widget.onExpandedChanged(_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final expanded = widget.forceExpanded || _expanded;
    final headingBackground = Theme.of(context).brightness == Brightness.dark
        ? context.colors.surfaceContainerLowest
        : context.colors.surfaceContainerHighest;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ColoredBox(
          key: ValueKey(
            'provider-model-heading-background-${widget.provider.id}',
          ),
          color: headingBackground,
          child: InkWell(
            key: ValueKey('provider-model-heading-${widget.provider.id}'),
            onTap: widget.forceExpanded ? null : _toggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 11, 12, 9),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      widget.provider.name.toUpperCase(),
                      style: TextStyle(
                        color: context.colors.onSurface,
                        fontSize: 10,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${widget.models.length}',
                    style: TextStyle(
                      color: context.colors.onSurface.withValues(alpha: .72),
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: context.colors.onSurface.withValues(alpha: .72),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: expanded
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: widget.models.map((model) {
                    final selected =
                        widget.provider.id == widget.selectedProviderId &&
                        model.id == widget.selectedModelId;
                    return InkWell(
                      key: ValueKey(
                        'provider-model-option-${widget.provider.id}-${model.id}',
                      ),
                      onTap: () => Navigator.of(
                        context,
                      ).pop('${widget.provider.id}|${model.id}'),
                      child: Container(
                        color: selected
                            ? context.colors.primaryContainer.withValues(
                                alpha: .5,
                              )
                            : null,
                        padding: const EdgeInsets.fromLTRB(24, 10, 14, 10),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                model.label,
                                style: TextStyle(
                                  color: context.colors.onSurface,
                                  fontSize: 13,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                            if (selected)
                              Icon(
                                Icons.check_rounded,
                                size: 17,
                                color: context.colors.primary,
                              ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                )
              : const SizedBox.shrink(),
        ),
        Divider(height: 1, color: context.colors.outlineVariant),
      ],
    );
  }
}

class _Composer extends StatefulWidget {
  const _Composer({required this.controller});

  final AppController controller;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  bool _showVideoPanel = false;
  bool _showDraftPanel = false;
  int _seenRevision = -1;

  AppController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    if (_seenRevision != controller.formRevision) {
      // A reuse/enhance action replaced the form; let its contents decide
      // which source panels are open.
      _seenRevision = controller.formRevision;
      _showVideoPanel = false;
      _showDraftPanel = false;
    }
    final form = controller.form;
    final draftActive =
        form.draftAsset != null ||
        form.draftUrl.trim().isNotEmpty ||
        _showDraftPanel;
    final videoActive =
        !draftActive &&
        (form.videoAsset != null ||
            form.videoUrl.trim().isNotEmpty ||
            _showVideoPanel);
    final enhancing = form.mode == VideoMode.draftEnhance;

    return SurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (!enhancing) ...<Widget>[
            const FieldLabel('Direction', icon: Icons.edit_note_rounded),
            const SizedBox(height: 9),
            ReferencePromptField(
              key: ValueKey('generation-prompt-${controller.formRevision}'),
              prompt: form.prompt,
              formRevision: controller.formRevision,
              references: _promptReferenceOptions(form.references),
              onChanged: (value) =>
                  controller.updateForm((form) => form.prompt = value),
            ),
            const SizedBox(height: 20),
          ],
          if (draftActive)
            _SourceEditor(
              title: 'Enhance a draft render',
              description:
                  'Re-render a saved FLUX 3 draft cache at full quality. Prompt, framing, and duration come from the original.',
              icon: Icons.auto_fix_high_rounded,
              asset: form.draftAsset,
              url: form.draftUrl,
              onPick: controller.pickDraft,
              onUrl: (value) =>
                  controller.updateForm((form) => form.draftUrl = value),
              onDismiss: () {
                setState(() => _showDraftPanel = false);
                controller.updateForm((form) {
                  form.draftAsset = null;
                  form.draftUrl = '';
                });
              },
              formRevision: controller.formRevision,
            )
          else if (videoActive) ...<Widget>[
            _SourceEditor(
              title: 'Continue a video',
              description:
                  'FLUX 3 extends the motion of an uploaded clip or a hosted provider-compatible URL.',
              icon: Icons.movie_filter_rounded,
              asset: form.videoAsset,
              url: form.videoUrl,
              onPick: controller.pickVideo,
              onUrl: (value) =>
                  controller.updateForm((form) => form.videoUrl = value),
              onDismiss: () {
                setState(() => _showVideoPanel = false);
                controller.updateForm((form) {
                  form.videoAsset = null;
                  form.videoUrl = '';
                });
              },
              formRevision: controller.formRevision,
            ),
            if (form.keyframes.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Your ${form.keyframes.length} reference '
                '${form.keyframes.length == 1 ? 'frame is' : 'frames are'} set '
                'aside while a starting video is attached.',
                style: TextStyle(
                  fontSize: 11,
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ] else
            _GuidanceInputsSection(controller: controller),
          if (!draftActive && !videoActive) ...<Widget>[
            const SizedBox(height: 14),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text(
                  'Or start from',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
                _QuietAction(
                  icon: Icons.movie_filter_rounded,
                  label: 'a video to continue',
                  onTap:
                      controller.selectedProvider.models.any(
                        (model) => model.modes.contains(VideoMode.v2v),
                      )
                      ? () => setState(() => _showVideoPanel = true)
                      : null,
                ),
                _QuietAction(
                  icon: Icons.auto_fix_high_rounded,
                  label: 'a saved draft to enhance',
                  onTap:
                      controller.selectedProvider.models.any(
                        (model) => model.modes.contains(VideoMode.draftEnhance),
                      )
                      ? () => setState(() => _showDraftPanel = true)
                      : null,
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          Divider(color: context.colors.outlineVariant),
          const SizedBox(height: 20),
          if (enhancing)
            _EnhanceSettings(controller: controller)
          else
            _SettingsGrid(controller: controller),
          const SizedBox(height: 20),
          _CostPreview(controller: controller),
          const SizedBox(height: 18),
          _GenerationDestinationControls(controller: controller),
          const SizedBox(height: 12),
          _ComposerFooter(controller: controller),
        ],
      ),
    );
  }
}

class _GenerationDestinationControls extends StatelessWidget {
  const _GenerationDestinationControls({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final storage = controller.effectiveStorage;
    final folders = controller.foldersFor(
      LibraryCollection.generated,
      storage: storage,
    );
    final selected = controller.selectedGenerationFolderId;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const FieldLabel('Save generation to', icon: Icons.save_outlined),
          const SizedBox(height: 10),
          if (controller.supportsLocalLibrary &&
              controller.googleDriveConnected)
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: LibraryStorage.values
                  .map(
                    (value) => ChoiceChip(
                      avatar: Icon(
                        value == LibraryStorage.drive
                            ? Icons.cloud_outlined
                            : Icons.devices_outlined,
                        size: 15,
                      ),
                      label: Text(value.shortLabel),
                      selected: storage == value,
                      onSelected: (_) =>
                          unawaited(controller.setDefaultStorage(value)),
                    ),
                  )
                  .toList(),
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: StorageBadge(storage: storage),
            ),
          if (controller.supportsGoogleDrive &&
              !controller.googleDriveConnected) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              'Connect Google Drive in Settings to generate directly into your Drive library.',
              style: TextStyle(
                fontSize: 11,
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 10),
          PopupMenuButton<String>(
            key: ValueKey('generation-folder-${storage.name}'),
            tooltip: 'Choose generation folder',
            onSelected: (value) => unawaited(
              controller.setGenerationFolder(value.isEmpty ? null : value),
            ),
            itemBuilder: (context) => <PopupMenuEntry<String>>[
              const PopupMenuItem(
                value: '',
                child: Text('Library (top level)'),
              ),
              ...controller.folderTree
                  .where((folder) => folder.storage == storage)
                  .map(
                    (folder) => PopupMenuItem(
                      value: folder.id,
                      child: Text(controller.folderPath(folder.id)),
                    ),
                  ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                border: Border.all(color: context.colors.outlineVariant),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.folder_outlined, size: 18),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      selected == null
                          ? 'Library (top level)'
                          : controller.folderPath(selected),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.expand_more_rounded, size: 18),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => unawaited(
                _showGenerationFolderDialog(
                  context,
                  controller,
                  parentId: selected,
                ),
              ),
              icon: const Icon(Icons.create_new_folder_outlined, size: 17),
              label: Text(selected == null ? 'New folder' : 'New subfolder'),
            ),
          ),
          if (folders.isEmpty) ...<Widget>[
            const SizedBox(height: 7),
            Text(
              'No ${storage.shortLabel.toLowerCase()} folders yet. You can generate at the top level or create one now.',
              style: TextStyle(
                fontSize: 10.5,
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> _showGenerationFolderDialog(
  BuildContext context,
  AppController controller, {
  String? parentId,
}) async {
  final name = TextEditingController();
  var saving = false;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('New generation folder'),
        content: TextField(
          controller: name,
          autofocus: true,
          maxLength: 48,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'Folder name',
            helperText: parentId == null
                ? 'Created at the top level'
                : 'Inside ${controller.folderPath(parentId)}',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: saving
                ? null
                : () async {
                    setState(() => saving = true);
                    final before = controller.folders
                        .map((item) => item.id)
                        .toSet();
                    final saved = await controller.saveLibraryFolder(
                      name.text,
                      parentId: parentId,
                      storage: controller.effectiveStorage,
                    );
                    if (!dialogContext.mounted) return;
                    if (!saved) {
                      setState(() => saving = false);
                      return;
                    }
                    final created = controller.folders
                        .where((item) => !before.contains(item.id))
                        .toList();
                    await controller.setGenerationFolder(
                      created.isEmpty ? null : created.first.id,
                    );
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
            icon: saving
                ? const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.create_new_folder_outlined),
            label: const Text('Create'),
          ),
        ],
      ),
    ),
  );
  name.dispose();
}

List<PromptReferenceOption> _promptReferenceOptions(
  List<MediaReferenceDraft> references,
) {
  final mentions = promptReferenceMentions(
    references.map((reference) => reference.kind),
  );
  return references
      .asMap()
      .entries
      .map(
        (entry) => PromptReferenceOption(
          id: entry.value.id,
          mention: mentions[entry.key],
          label: entry.value.label,
        ),
      )
      .toList();
}

class _GuidanceInputsSection extends StatelessWidget {
  const _GuidanceInputsSection({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final model = controller.selectedModel;
    final showFrames =
        model.maxKeyframes > 0 || controller.form.keyframes.isNotEmpty;
    final showReferences =
        model.supportsMediaReferences || controller.form.references.isNotEmpty;
    if (!showFrames && !showReferences) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.colors.outlineVariant),
        ),
        child: Text(
          '${model.label} is a text-only endpoint. Choose a Frames or References model to attach media.',
          style: TextStyle(
            color: context.colors.onSurfaceVariant,
            fontSize: 11.5,
            height: 1.4,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (showFrames) _FramesSection(controller: controller),
        if (showFrames && showReferences) const SizedBox(height: 22),
        if (showReferences) _ReferencesSection(controller: controller),
      ],
    );
  }
}

class _QuietAction extends StatelessWidget {
  const _QuietAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onTap,
    style: TextButton.styleFrom(
      foregroundColor: context.colors.secondary,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
    ),
    icon: Icon(icon, size: 15),
    label: Text(label),
  );
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.label, {required this.icon, super.key, this.trailing});

  final String label;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Icon(icon, size: 16, color: context.tokens.brass),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.3,
            fontWeight: FontWeight.w700,
            color: context.colors.onSurface.withValues(alpha: .82),
          ),
        ),
      ),
      if (trailing != null) trailing!,
    ],
  );
}

class _FramesSection extends StatelessWidget {
  const _FramesSection({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final form = controller.form;
    final model = controller.selectedModel;
    final setAside = controller.framesBlockedByReferences;
    final conflicted =
        model.framesExclusiveWithReferences &&
        form.keyframes.isNotEmpty &&
        form.references.isNotEmpty;
    final caption = conflicted
        ? '${model.label} takes pinned frames or creative references, not both — remove one side before generating.'
        : setAside
        ? 'Creative references are attached, and ${model.label} takes frames or references — never both. Remove the references below to pin frames instead.'
        : form.keyframes.isEmpty
        ? controller.selectedProvider.isLocal
              ? 'Add one image to anchor the design, or leave this empty to begin from the continuity-locked text prompt.'
              : model.supportsTimedKeyframes
              ? 'Pin up to ${model.maxKeyframes} images at exact moments in ${model.label}.'
              : 'Set the first${model.supportsEndFrame ? ' and optional last' : ''} frame for ${model.label}.'
                    '${model.framesExclusiveWithReferences ? ' Pinning a frame sets creative references aside.' : ''}'
        : form.requiresTimedKeyframes
        ? 'This sparse layout uses timestamps automatically. A last frame can stand alone; middle frames can too.'
        : 'First-only pins the opening. First + last pins both ends. Reference behavior follows ${controller.selectedProvider.shortName}.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FieldLabel(
          'Keyframes · optional',
          icon: Icons.collections_rounded,
          trailing: form.keyframes.isEmpty
              ? null
              : !model.supportsTimedKeyframes
              ? null
              : TogglePill(
                  label: 'Custom timing',
                  selected: form.usesTimedKeyframes,
                  onChanged: form.requiresTimedKeyframes
                      ? null
                      : controller.setExactTiming,
                ),
        ),
        const SizedBox(height: 9),
        Text(
          caption,
          style: TextStyle(
            color: conflicted
                ? context.colors.error
                : context.colors.onSurfaceVariant,
            fontSize: 11.5,
            height: 1.4,
          ),
        ),
        if (form.keyframes.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: form.keyframes
                .asMap()
                .entries
                .map(
                  (entry) => _FrameTile(
                    controller: controller,
                    index: entry.key,
                    frame: entry.value,
                  ),
                )
                .toList(),
          ),
        ],
        if (!setAside) ...<Widget>[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: KeyframeRole.values
                .where(
                  (role) => switch (role) {
                    KeyframeRole.start => model.supportsStartFrame,
                    KeyframeRole.middle => model.supportsTimedKeyframes,
                    KeyframeRole.end => model.supportsEndFrame,
                  },
                )
                .map(
                  (role) => _AddFrameButton(controller: controller, role: role),
                )
                .toList(),
          ),
        ],
      ],
    );
  }
}

class _ReferencesSection extends StatelessWidget {
  const _ReferencesSection({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final form = controller.form;
    final model = controller.selectedModel;
    final limits = MediaReferenceKind.values
        .where((kind) => model.maxReferences(kind) > 0)
        .map((kind) => '${controller.referenceLimit(kind)} ${kind.pluralLabel}')
        .join(' · ');
    final durationNotes = <String>{
      if (model.maxReferenceVideoSeconds != null)
        '${model.maxReferenceVideoSeconds}s total video',
      if (model.maxReferenceAudioSeconds != null)
        '${model.maxReferenceAudioSeconds}s total audio',
    }.join(' · ');
    final required =
        !model.modes.contains(VideoMode.t2v) && model.maxKeyframes == 0;
    final setAside = controller.referencesBlockedByFrames;
    final conflicted =
        model.framesExclusiveWithReferences &&
        form.keyframes.isNotEmpty &&
        form.references.isNotEmpty;
    return Column(
      key: const ValueKey('media-references-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FieldLabel(
          required
              ? 'Creative references · required'
              : 'Creative references · optional',
          icon: Icons.perm_media_rounded,
        ),
        const SizedBox(height: 9),
        if (!setAside &&
            !conflicted &&
            model.referenceTasks.length > 1) ...<Widget>[
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: model.referenceTasks
                .map(
                  (task) => ChoiceChip(
                    key: ValueKey('reference-task-${task.name}'),
                    label: Text(task.label),
                    selected: form.referenceTask == task,
                    onSelected: (_) => controller.setReferenceTask(task),
                    showCheckmark: false,
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 9),
        ],
        Text(
          conflicted
              ? '${model.label} takes pinned frames or creative references, not both — remove one side before generating.'
              : setAside
              ? 'Frames are pinned above, and ${model.label} takes frames or references — never both. Remove the frames to guide with references instead.'
              : '${switch (form.referenceTask) {
                      MediaReferenceTask.reference => 'Guide identity, style, motion, or sound without pinning media to a timeline.',
                      MediaReferenceTask.edit => 'Change one reference video while preserving its length and framing.',
                      MediaReferenceTask.extend => 'Continue one reference video while preserving its framing.',
                    }} '
                    '$limits${durationNotes.isEmpty ? '' : ' · $durationNotes'}. '
                    'Type @ in Direction to mention attached media; Clawnsole '
                    'adapts the tag for ${model.label}. '
                    '${model.referencePromptHint ?? 'References keep the numbered order shown here.'}'
                    '${model.framesExclusiveWithReferences && form.references.isEmpty ? ' Attaching a reference sets pinned frames aside.' : ''}',
          style: TextStyle(
            color: conflicted
                ? context.colors.error
                : context.colors.onSurfaceVariant,
            fontSize: 11.5,
            height: 1.4,
          ),
        ),
        if (!setAside && model.requiresVisualReferenceForAudio) ...<Widget>[
          const SizedBox(height: 5),
          Text(
            'Audio guidance requires at least one image or video reference for this model.',
            style: TextStyle(
              color: context.colors.onSurfaceVariant,
              fontSize: 10.5,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        if (form.references.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: form.references
                .asMap()
                .entries
                .map(
                  (entry) => _ReferenceTile(
                    controller: controller,
                    reference: entry.value,
                    number: form.references
                        .take(entry.key + 1)
                        .where((item) => item.kind == entry.value.kind)
                        .length,
                  ),
                )
                .toList(),
          ),
        ],
        if (!setAside) ...<Widget>[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: MediaReferenceKind.values
                .where(
                  (kind) =>
                      model.maxReferences(kind) > 0 ||
                      form.referenceCount(kind) > 0,
                )
                .map(
                  (kind) =>
                      _AddReferenceButton(controller: controller, kind: kind),
                )
                .toList(),
          ),
        ],
      ],
    );
  }
}

class _ReferenceTile extends StatelessWidget {
  const _ReferenceTile({
    required this.controller,
    required this.reference,
    required this.number,
  });

  final AppController controller;
  final MediaReferenceDraft reference;
  final int number;

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey('media-reference-${reference.id}'),
    width: 148,
    padding: const EdgeInsets.all(7),
    decoration: BoxDecoration(
      color: context.colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: context.colors.outlineVariant),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Stack(
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 76,
                width: double.infinity,
                child:
                    reference.kind == MediaReferenceKind.image &&
                        reference.asset != null
                    ? Image.memory(reference.asset!.bytes, fit: BoxFit.cover)
                    : Builder(
                        builder: (context) {
                          final dark =
                              Theme.of(context).brightness == Brightness.dark;
                          return Container(
                            color: dark
                                ? ClawnsoleColors.plumInk
                                : context.colors.surfaceContainer,
                            child: Icon(
                              switch (reference.kind) {
                                MediaReferenceKind.image => Icons.image_rounded,
                                MediaReferenceKind.video =>
                                  Icons.video_library_rounded,
                                MediaReferenceKind.audio =>
                                  Icons.graphic_eq_rounded,
                              },
                              color: dark
                                  ? ClawnsoleColors.creamMuted
                                  : context.colors.onSurfaceVariant,
                              size: 24,
                            ),
                          );
                        },
                      ),
              ),
            ),
            Positioned(
              top: 4,
              left: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2.5,
                ),
                decoration: BoxDecoration(
                  color: ClawnsoleColors.plumInk.withValues(alpha: .82),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${reference.kind.label} $number'.toUpperCase(),
                  style: const TextStyle(
                    color: ClawnsoleColors.cream,
                    fontSize: 8,
                    letterSpacing: .8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 3,
              right: 3,
              child: IconButton.filledTonal(
                tooltip: 'Remove ${reference.kind.label.toLowerCase()}',
                constraints: const BoxConstraints.tightFor(
                  width: 26,
                  height: 26,
                ),
                padding: EdgeInsets.zero,
                onPressed: () => controller.removeReference(reference.id),
                icon: const Icon(Icons.close_rounded, size: 14),
              ),
            ),
            Positioned(
              top: 3,
              right: 32,
              child: IconButton.filledTonal(
                tooltip: reference.savedReferenceId == null
                    ? 'Save to References'
                    : 'Saved to References',
                constraints: const BoxConstraints.tightFor(
                  width: 26,
                  height: 26,
                ),
                padding: EdgeInsets.zero,
                onPressed: reference.savedReferenceId != null
                    ? null
                    : () => unawaited(
                        showReferenceMetadataDialog(
                          context,
                          controller,
                          draft: reference,
                        ),
                      ),
                icon: Icon(
                  reference.savedReferenceId == null
                      ? Icons.bookmark_add_outlined
                      : Icons.bookmark_added_rounded,
                  size: 14,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          reference.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600),
        ),
        if (reference.asset == null) ...<Widget>[
          const SizedBox(height: 6),
          TextFormField(
            key: ValueKey('media-reference-url-${reference.id}'),
            initialValue: reference.source,
            onChanged: (value) =>
                controller.updateReference(reference.id, value),
            decoration: const InputDecoration(
              hintText: 'https://…',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            style: const TextStyle(fontSize: 10.5),
          ),
        ],
      ],
    ),
  );
}

class _AddReferenceButton extends StatelessWidget {
  const _AddReferenceButton({required this.controller, required this.kind});

  final AppController controller;
  final MediaReferenceKind kind;

  @override
  Widget build(BuildContext context) {
    final enabled = controller.canAddReference(kind);
    final count = controller.form.referenceCount(kind);
    final maximum = controller.referenceLimit(kind);
    return PopupMenuButton<String>(
      key: ValueKey('add-${kind.name}-reference'),
      enabled: enabled,
      tooltip: enabled
          ? 'Add reference ${kind.pluralLabel}'
          : '$maximum ${kind.pluralLabel} attached',
      onSelected: (choice) {
        if (choice == 'saved') {
          unawaited(() async {
            final selected = await showReferencePicker(
              context,
              controller,
              kind: kind,
              maximum: maximum - count,
            );
            if (selected != null) {
              await controller.addReferenceCandidates(kind, selected);
            }
          }());
        } else if (choice == 'upload') {
          unawaited(controller.addMediaReferences(kind));
        } else {
          controller.addUrlReference(kind);
        }
      },
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        PopupMenuItem(
          value: 'saved',
          child: Row(
            children: <Widget>[
              const Icon(Icons.collections_bookmark_outlined, size: 17),
              const SizedBox(width: 9),
              Text('Choose saved ${kind.pluralLabel}'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'upload',
          child: Row(
            children: <Widget>[
              const Icon(Icons.upload_file_rounded, size: 17),
              const SizedBox(width: 9),
              Text('Upload ${kind.pluralLabel}'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'url',
          child: Row(
            children: <Widget>[
              const Icon(Icons.add_link_rounded, size: 17),
              const SizedBox(width: 9),
              Text('Paste ${kind.label.toLowerCase()} URL'),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: enabled
                ? context.colors.outline.withValues(alpha: .55)
                : context.colors.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              enabled ? Icons.add_rounded : Icons.check_rounded,
              size: 15,
              color: enabled
                  ? context.colors.primary
                  : context.colors.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
            Text(
              '${kind.label} $count/$maximum',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: enabled
                    ? context.colors.onSurface
                    : context.colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FrameTile extends StatelessWidget {
  const _FrameTile({
    required this.controller,
    required this.index,
    required this.frame,
  });

  final AppController controller;
  final int index;
  final KeyframeDraft frame;

  @override
  Widget build(BuildContext context) {
    final form = controller.form;
    final roleLabel = frame.role == KeyframeRole.middle
        ? 'Middle ${form.keyframes.take(index + 1).where((item) => item.role == KeyframeRole.middle).length}'
        : frame.role == KeyframeRole.start
        ? 'First'
        : 'Last';
    return Container(
      width: 148,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Stack(
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 76,
                  width: double.infinity,
                  child: frame.asset != null
                      ? Image.memory(frame.asset!.bytes, fit: BoxFit.cover)
                      : Uri.tryParse(frame.source)?.scheme == 'https'
                      ? Image.network(
                          frame.source,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const _FrameLinkGhost(),
                        )
                      : const _FrameLinkGhost(),
                ),
              ),
              Positioned(
                top: 4,
                left: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2.5,
                  ),
                  decoration: BoxDecoration(
                    color: ClawnsoleColors.plumInk.withValues(alpha: .82),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    roleLabel.toUpperCase(),
                    style: const TextStyle(
                      color: ClawnsoleColors.cream,
                      fontSize: 8,
                      letterSpacing: .8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 3,
                right: 3,
                child: IconButton.filledTonal(
                  tooltip: 'Remove frame',
                  constraints: const BoxConstraints.tightFor(
                    width: 26,
                    height: 26,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: () => controller.removeFrame(frame.id),
                  icon: const Icon(Icons.close_rounded, size: 14),
                ),
              ),
            ],
          ),
          if (frame.asset == null) ...<Widget>[
            const SizedBox(height: 6),
            TextFormField(
              key: ValueKey('frame-url-${frame.id}'),
              initialValue: frame.source,
              onChanged: (value) =>
                  controller.updateFrame(frame.id, source: value),
              decoration: const InputDecoration(
                hintText: 'https://…',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
              ),
              style: const TextStyle(fontSize: 10.5),
            ),
          ],
          if (controller.form.usesTimedKeyframes) ...<Widget>[
            const SizedBox(height: 6),
            TextFormField(
              key: ValueKey('frame-time-${frame.id}'),
              initialValue: frame.seconds.toString(),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (value) => controller.updateFrame(
                frame.id,
                seconds: double.tryParse(value) ?? frame.seconds,
              ),
              decoration: const InputDecoration(
                suffixText: 'sec',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
              ),
              style: const TextStyle(fontSize: 10.5),
            ),
          ],
        ],
      ),
    );
  }
}

class _FrameLinkGhost extends StatelessWidget {
  const _FrameLinkGhost();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: dark ? ClawnsoleColors.plumInk : context.colors.surfaceContainer,
      child: Icon(
        Icons.link_rounded,
        color: dark
            ? ClawnsoleColors.creamMuted
            : context.colors.onSurfaceVariant,
        size: 18,
      ),
    );
  }
}

class _AddFrameButton extends StatelessWidget {
  const _AddFrameButton({required this.controller, required this.role});

  final AppController controller;
  final KeyframeRole role;

  @override
  Widget build(BuildContext context) {
    final enabled = controller.canAddFrame(role);
    final label = switch (role) {
      KeyframeRole.start => 'First frame',
      KeyframeRole.middle => 'Middle frame',
      KeyframeRole.end => 'Last frame',
    };
    final hint = switch (role) {
      KeyframeRole.start => 'Pins the opening at 0 s',
      KeyframeRole.middle => 'Timed waypoint · repeatable',
      KeyframeRole.end => 'Pins the ending · works alone',
    };
    return Tooltip(
      message: hint,
      child: PopupMenuButton<String>(
        enabled: enabled,
        tooltip: '',
        onSelected: (choice) {
          if (choice == 'upload') {
            unawaited(controller.addImageFrame(role));
          } else {
            controller.addUrlFrame(role);
          }
        },
        itemBuilder: (context) => <PopupMenuEntry<String>>[
          const PopupMenuItem(
            value: 'upload',
            child: Row(
              children: <Widget>[
                Icon(Icons.add_photo_alternate_rounded, size: 17),
                SizedBox(width: 9),
                Text('Upload an image'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'url',
            child: Row(
              children: <Widget>[
                Icon(Icons.add_link_rounded, size: 17),
                SizedBox(width: 9),
                Text('Paste an image URL'),
              ],
            ),
          ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: enabled
                  ? context.colors.outline.withValues(alpha: .55)
                  : context.colors.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                enabled ? Icons.add_rounded : Icons.check_rounded,
                size: 15,
                color: enabled
                    ? context.colors.primary
                    : context.colors.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Text(
                enabled ? label : '$label added',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: enabled
                      ? context.colors.onSurface
                      : context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceEditor extends StatelessWidget {
  const _SourceEditor({
    required this.title,
    required this.description,
    required this.icon,
    required this.asset,
    required this.url,
    required this.onPick,
    required this.onUrl,
    required this.onDismiss,
    required this.formRevision,
  });

  final String title;
  final String description;
  final IconData icon;
  final PickedAsset? asset;
  final String url;
  final Future<void> Function() onPick;
  final ValueChanged<String> onUrl;
  final VoidCallback onDismiss;
  final int formRevision;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: context.colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: context.colors.outlineVariant),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, size: 20, color: context.tokens.brass),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.35,
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Remove this source',
              onPressed: onDismiss,
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (asset != null)
          ListTile(
            tileColor: context.colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
            leading: const Icon(Icons.insert_drive_file_rounded),
            title: Text(
              asset!.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(formatBytes(asset!.bytes.length)),
            trailing: IconButton(
              tooltip: 'Clear file',
              onPressed: onDismiss,
              icon: const Icon(Icons.close_rounded),
            ),
          )
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: () => unawaited(onPick()),
                icon: const Icon(Icons.upload_file_rounded, size: 16),
                label: const Text('Choose file'),
              ),
              Text(
                'or',
                style: TextStyle(
                  fontSize: 11,
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              SizedBox(
                width: 300,
                child: TextFormField(
                  key: ValueKey('$title-url-$formRevision'),
                  initialValue: url,
                  onChanged: onUrl,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.link_rounded, size: 17),
                    hintText: 'Paste a hosted URL',
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
            ],
          ),
      ],
    ),
  );
}

class _SettingsGrid extends StatelessWidget {
  const _SettingsGrid({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth > 640;
      final first = <Widget>[
        const FieldLabel('Frame', icon: Icons.crop_rounded),
        const SizedBox(height: 10),
        _RatioStrip(controller: controller),
        const SizedBox(height: 20),
        if (controller.selectedModel.outputKind ==
            GenerationOutputKind.video) ...<Widget>[
          _DurationControl(controller: controller),
          if (controller.selectedModel.supportsFrameRate) ...<Widget>[
            const SizedBox(height: 18),
            _FrameRateControl(controller: controller),
          ],
        ],
      ];
      final second = <Widget>[
        const FieldLabel('Finish', icon: Icons.high_quality_rounded),
        const SizedBox(height: 10),
        _ResolutionRow(controller: controller),
        const SizedBox(height: 8),
        if (controller.selectedModel.supportsAudio)
          HardwareSwitchTile(
            title: 'Synchronized audio',
            subtitle: 'Dialogue, ambience, and sound',
            value: controller.form.generateAudio,
            onChanged: controller.selectedModel.supportsAudio
                ? (value) => controller.updateForm(
                    (form) => form.generateAudio = value,
                  )
                : null,
          ),
        if (controller.selectedModel.supportsDraft)
          HardwareSwitchTile(
            title: 'Fast draft',
            subtitle: 'HD preview now, enhance later',
            value: controller.form.draft,
            onChanged: (value) =>
                controller.updateForm((form) => form.draft = value),
          ),
        if (controller.selectedProviderId == 'bfl') ...<Widget>[
          const SizedBox(height: 8),
          _SafetyControl(controller: controller),
        ],
      ];
      if (!columns) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[...first, const SizedBox(height: 22), ...second],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: first,
            ),
          ),
          const SizedBox(width: 26),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: second,
            ),
          ),
        ],
      );
    },
  );
}

class _EnhanceSettings extends StatelessWidget {
  const _EnhanceSettings({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth > 640;
      final finish = <Widget>[
        const FieldLabel('Finish', icon: Icons.high_quality_rounded),
        const SizedBox(height: 10),
        _ResolutionRow(controller: controller),
      ];
      final safety = <Widget>[_SafetyControl(controller: controller)];
      if (!columns) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[...finish, const SizedBox(height: 20), ...safety],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: finish,
            ),
          ),
          const SizedBox(width: 26),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: safety,
            ),
          ),
        ],
      );
    },
  );
}

class _RatioStrip extends StatelessWidget {
  const _RatioStrip({required this.controller});

  final AppController controller;

  static const _hints = <String, String>{
    'auto': 'Provider chooses the frame',
    '21:9': 'Cinema wide',
    '2:1': 'Panoramic',
    '16:9': 'Widescreen',
    '4:3': 'Classic',
    '1:1': 'Square',
    '3:4': 'Tall',
    '9:16': 'Vertical',
  };

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 7,
    runSpacing: 7,
    children: controller.availableAspectRatios.map((ratio) {
      final selected = controller.form.aspectRatio == ratio;
      return Tooltip(
        message: _hints[ratio] ?? ratio,
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: () =>
              controller.updateForm((form) => form.aspectRatio = ratio),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 58,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: consoleKeyDecoration(context, selected: selected),
            child: Column(
              children: <Widget>[
                SizedBox(
                  width: 30,
                  height: 20,
                  child: Center(
                    child: _RatioGlyph(
                      ratio: ratio,
                      color: selected
                          ? context.colors.onPrimary
                          : context.colors.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  ratio == 'auto' ? 'Auto' : ratio,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? context.colors.onPrimary
                        : context.colors.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }).toList(),
  );
}

class _RatioGlyph extends StatelessWidget {
  const _RatioGlyph({required this.ratio, required this.color});

  final String ratio;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (ratio == 'auto') {
      return Icon(Icons.crop_free_rounded, size: 17, color: color);
    }
    final parts = ratio.split(':');
    final aspect = double.parse(parts[0]) / double.parse(parts[1]);
    final width = aspect >= 1 ? 28.0 : 18.0 * aspect;
    final height = aspect >= 1 ? 28.0 / aspect : 18.0;
    return Container(
      width: width,
      height: height.clamp(9, 18),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(3.5),
      ),
    );
  }
}

class _DurationControl extends StatelessWidget {
  const _DurationControl({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final form = controller.form;
    final model = controller.selectedModel;
    final maximumDuration = model.maxDurationFor(form.resolution);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FieldLabel(
          'Duration',
          icon: Icons.timelapse_rounded,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              CounterReadout(
                form.autoDuration ? 'AUTO' : '${form.durationSeconds}',
                unit: form.autoDuration ? null : 's',
              ),
              const SizedBox(width: 8),
              TogglePill(
                label: 'Auto',
                selected: form.autoDuration,
                onChanged:
                    form.requiresFixedDuration ||
                        !model.supportsAutoDuration ||
                        form.referenceTask == MediaReferenceTask.edit
                    ? null
                    : (value) => controller.updateForm(
                        (form) => form.autoDuration = value,
                      ),
              ),
            ],
          ),
        ),
        HardwareSlider(
          min: model.minDuration.toDouble(),
          max: maximumDuration.toDouble(),
          divisions:
              (maximumDuration - model.minDuration) ~/ model.durationStep,
          label: '${form.durationSeconds} s',
          value: form.durationSeconds.toDouble(),
          onChanged: (value) => controller.setDurationSeconds(value.round()),
        ),
        Row(
          children: <Widget>[
            Text(
              '${model.minDuration} s',
              style: TextStyle(
                fontSize: 10.5,
                color: context.colors.onSurfaceVariant,
              ),
            ),
            Expanded(
              child: Text(
                form.autoDuration ? 'Auto — the provider chooses' : '',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              '$maximumDuration s',
              style: TextStyle(
                fontSize: 10.5,
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        if (form.requiresFixedDuration)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'This keyframe layout needs a fixed duration.',
              style: TextStyle(
                fontSize: 10.5,
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _FrameRateControl extends StatelessWidget {
  const _FrameRateControl({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final frames = controller.form.frameRate * controller.form.durationSeconds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FieldLabel(
          'Frame rate',
          icon: Icons.animation_rounded,
          trailing: CounterReadout('${controller.form.frameRate}', unit: 'fps'),
        ),
        HardwareSlider(
          min: 1,
          max: 6,
          divisions: 5,
          label: '${controller.form.frameRate} fps',
          value: controller.form.frameRate.toDouble(),
          onChanged: (value) => controller.setFrameRate(value.round()),
        ),
        Text(
          '${controller.form.frameRate} fps × ${controller.form.durationSeconds} s = $frames frames. Each frame is generated separately, so higher values take proportionally longer.',
          style: TextStyle(
            fontSize: 10.5,
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ResolutionRow extends StatelessWidget {
  const _ResolutionRow({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final resolutions = controller.availableResolutions;
      final width = resolutions.length <= 2
          ? (constraints.maxWidth - 8) / resolutions.length
          : (constraints.maxWidth - 8) / 2;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: resolutions
            .map(
              (resolution) => SizedBox(
                width: width,
                child: _ResolutionButton(
                  label: resolution.label,
                  detail: resolution.detail,
                  active: controller.form.resolution == resolution.id,
                  enabled: !controller.form.draft || resolution.id == 'hd',
                  onTap: () => controller.updateForm(
                    (form) => form.resolution = resolution.id,
                  ),
                ),
              ),
            )
            .toList(),
      );
    },
  );
}

class _ResolutionButton extends StatelessWidget {
  const _ResolutionButton({
    required this.label,
    required this.detail,
    required this.active,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final String detail;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: enabled ? 1 : .45,
    child: InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(11),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 10),
        decoration: consoleKeyDecoration(context, selected: active),
        child: Column(
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                color: active
                    ? context.colors.onPrimary
                    : context.colors.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: active
                    ? context.colors.onPrimary.withValues(alpha: .78)
                    : context.colors.onSurfaceVariant,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SafetyControl extends StatelessWidget {
  const _SafetyControl({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      FieldLabel(
        'Safety tolerance',
        icon: Icons.shield_outlined,
        trailing: CounterReadout(
          '${controller.form.safetyTolerance}',
          unit: '/ 4',
        ),
      ),
      HardwareSlider(
        min: 0,
        max: 4,
        divisions: 4,
        label: '${controller.form.safetyTolerance} / 4',
        value: controller.form.safetyTolerance.toDouble(),
        onChanged: (value) => controller.updateForm(
          (form) => form.safetyTolerance = value.round(),
        ),
      ),
    ],
  );
}

class _CostPreview extends StatelessWidget {
  const _CostPreview({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.selectedProvider.isLocal) {
      final frames = controller.selectedModel.supportsFrameRate
          ? controller.form.frameRate * controller.form.durationSeconds
          : 1;
      return TexturePanel(
        surface: PanelSurface.hunterFelt,
        stitched: true,
        padding: const EdgeInsets.all(18),
        child: Row(
          children: <Widget>[
            Icon(Icons.memory_rounded, color: context.tokens.moneyAccent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'APPLE SYSTEM · NO PROVIDER CHARGE',
                    style: TextStyle(
                      color: context.tokens.onMoneyMuted,
                      fontSize: 9,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    controller.selectedModel.outputKind ==
                            GenerationOutputKind.image
                        ? 'One Apple image'
                        : '$frames Apple frames → silent MP4',
                    style: TextStyle(
                      color: context.tokens.onMoney,
                      fontFamily: 'Fraunces',
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Uses Apple Image Playground with no provider key. On Mac, keep its generation window in front.',
                    style: TextStyle(
                      color: context.tokens.onMoneyMuted,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final tokens = context.tokens;
    final estimate = controller.currentEstimate;
    final providerUnits = estimate.providerUnitsMinimum != null;
    final account = controller.providerAccounts[controller.selectedProviderId];
    final balanceUsesCredits = account?.currency == 'credits';
    final chargeMinimum = providerUnits
        ? estimate.providerUnitsMinimum!
        : estimate.minimumUsd;
    final chargeMaximum = providerUnits
        ? estimate.providerUnitsMaximum!
        : estimate.maximumUsd;
    final afterMin = controller.credits == null
        ? null
        : (controller.credits! -
                  (balanceUsesCredits
                      ? estimate.providerUnitsMaximum ?? 0
                      : estimate.maximumUsd))
              .clamp(0, double.infinity)
              .toDouble();
    final afterMax = controller.credits == null
        ? null
        : (controller.credits! -
                  (balanceUsesCredits
                      ? estimate.providerUnitsMinimum ?? 0
                      : estimate.minimumUsd))
              .clamp(0, double.infinity)
              .toDouble();
    return TexturePanel(
      surface: PanelSurface.hunterFelt,
      stitched: true,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 20,
            runSpacing: 10,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: tokens.moneyAccent),
                      color: tokens.onMoney.withValues(alpha: .05),
                    ),
                    child: Icon(
                      Icons.toll_rounded,
                      color: tokens.moneyAccent,
                      size: 17,
                    ),
                  ),
                  const SizedBox(width: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 230),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'ESTIMATED CHARGE',
                          style: TextStyle(
                            color: tokens.onMoneyMuted,
                            fontSize: 9,
                            letterSpacing: 1.6,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          providerUnits
                              ? '${formatCreditRange(chargeMinimum, chargeMaximum)} credits'
                              : formatUsdAmountRange(
                                  estimate.minimumUsd,
                                  estimate.maximumUsd,
                                ),
                          style: TextStyle(
                            fontFamily: 'Fraunces',
                            color: tokens.onMoney,
                            fontSize: 21,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Text(
                providerUnits
                    ? formatUsdAmountRange(
                        estimate.minimumUsd,
                        estimate.maximumUsd,
                      )
                    : controller.selectedModel.label,
                style: TextStyle(
                  fontFamily: 'Fraunces',
                  color: tokens.moneyAccent,
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: tokens.onMoney.withValues(alpha: .14)),
          const SizedBox(height: 11),
          Row(
            children: <Widget>[
              Expanded(
                child: _BalanceLine(
                  label: 'Available now',
                  value: controller.credits == null
                      ? (controller.hasApiKey
                            ? account?.balanceLabel ?? 'Connected'
                            : 'Add API key')
                      : balanceUsesCredits
                      ? '${formatCredits(controller.credits!)} credits'
                      : formatUsdAmount(controller.credits!),
                ),
              ),
              Expanded(
                child: _BalanceLine(
                  label: 'Estimated after',
                  value: afterMin == null || afterMax == null
                      ? '—'
                      : balanceUsesCredits
                      ? '${formatCreditRange(afterMin, afterMax)} credits'
                      : formatUsdAmountRange(afterMin, afterMax),
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text(
                '${controller.form.draft ? 'Drafts use the provider’s HD draft tier. ' : ''}'
                '${estimate.basis == 'provider-history' ? 'Calibrated from exact charges.' : 'Based on the provider’s current published or live rate.'}',
                style: TextStyle(color: tokens.onMoneyMuted, fontSize: 10.5),
              ),
              TextButton(
                onPressed: () => unawaited(
                  launchUrl(Uri.parse(controller.selectedProvider.pricingUrl)),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: tokens.moneyAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('Rate card ↗'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BalanceLine extends StatelessWidget {
  const _BalanceLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(
        label.toUpperCase(),
        style: TextStyle(
          color: context.tokens.onMoneyMuted,
          fontSize: 8.5,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        value,
        style: TextStyle(
          color: context.tokens.onMoney,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _ComposerFooter extends StatelessWidget {
  const _ComposerFooter({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final form = controller.form;
    final status = Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (!controller.selectedProvider.requiresApiKey ||
                controller.hasApiKey)
              ClawMark(size: 19, color: context.tokens.brass)
            else
              Icon(
                Icons.key_off_rounded,
                color: context.colors.error,
                size: 18,
              ),
            const SizedBox(width: 9),
            Text(
              !controller.selectedProvider.requiresApiKey ||
                      controller.hasApiKey
                  ? 'Ready when you are'
                  : 'API key needed',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: context.colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: context.colors.outlineVariant),
          ),
          child: Text(
            controller.selectedModel.outputKind == GenerationOutputKind.image
                ? (form.mode == VideoMode.i2v
                      ? 'Reference to image'
                      : 'Text to image')
                : form.referenceTask != MediaReferenceTask.reference
                ? form.referenceTask.label
                : form.mode.label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
    final generate = FilledButton.icon(
      onPressed: controller.submitting
          ? null
          : () => unawaited(controller.submit()),
      icon: controller.submitting
          ? SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.colors.onPrimary,
              ),
            )
          : const Icon(Icons.play_arrow_rounded, size: 20),
      label: Text(
        controller.selectedModel.outputKind == GenerationOutputKind.image
            ? 'Generate image'
            : 'Generate video',
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 480) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[status, const SizedBox(height: 12), generate],
          );
        }
        return Row(
          children: <Widget>[
            Expanded(child: status),
            generate,
          ],
        );
      },
    );
  }
}

class _RecentWork extends StatelessWidget {
  const _RecentWork({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Eyebrow('On the branch'),
                const SizedBox(height: 6),
                Text(
                  'Recent work',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => unawaited(controller.navigate(AppSection.library)),
            child: const Text('View library'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (controller.generations.isEmpty)
        SurfaceCard(
          child: Column(
            children: <Widget>[
              const SizedBox(height: 10),
              ClawMark(size: 40, color: context.tokens.brass),
              const SizedBox(height: 13),
              Text(
                'A quiet branch.',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                'Your generations will gather here with live progress and playback.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.colors.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
            ],
          ),
        )
      else
        ...controller.generations
            .take(5)
            .map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ActivityCard(controller: controller, item: item),
              ),
            ),
      const SizedBox(height: 2),
      SurfaceCard(
        color: context.colors.surfaceContainer,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Wrap(
          spacing: 18,
          runSpacing: 8,
          children: <Widget>[
            _Summary('${controller.generations.length}', 'in library'),
            _Summary('${controller.readyCount}', 'complete'),
            _Summary('${controller.workingCount}', 'moving'),
            _Summary(formatUsdAmount(controller.spentUsd), 'recorded spend'),
          ],
        ),
      ),
    ],
  );
}

class _Summary extends StatelessWidget {
  const _Summary(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Text(
        value,
        style: TextStyle(
          fontFamily: 'Fraunces',
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: context.colors.onSurface,
        ),
      ),
      const SizedBox(width: 5),
      Text(
        label,
        style: TextStyle(fontSize: 11, color: context.colors.onSurfaceVariant),
      ),
    ],
  );
}
