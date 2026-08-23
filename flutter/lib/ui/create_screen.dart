import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import '../core/models.dart';
import '../core/provider_catalog.dart';
import '../core/reference_prompts.dart';
import 'common_widgets.dart';
import 'claw_mark.dart';
import 'formatters.dart';
import 'generation_view_widgets.dart';
import 'hardware.dart';
import 'inline_video.dart';
import 'library_screen.dart';
import 'media_picker_source.dart';
import 'media_thumbnail.dart';
import 'panels.dart';
import 'reference_prompt_field.dart';
import 'references_screen.dart';
import 'visual_reference_viewer.dart';

/// Below this window height the Create screen switches to its dense spacing
/// so the whole composer lands above the fold on a 900px-tall display.
bool _isShort(BuildContext context) => MediaQuery.sizeOf(context).height < 950;

class CreateScreen extends StatelessWidget {
  const CreateScreen({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final short = _isShort(context);
      final pad = constraints.maxWidth < 620 ? 16.0 : (short ? 20.0 : 28.0);
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(pad, short ? 10 : pad, pad, pad),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _CreateHeading(controller: controller),
                SizedBox(height: short ? 8 : 18),
                _Composer(controller: controller),
                SizedBox(height: short ? 12 : 24),
                _RecentWork(controller: controller),
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
  Widget build(BuildContext context) {
    final upscaling = controller.selectedModel.isUpscaler;
    final short = _isShort(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final title = ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 650),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Eyebrow(
                controller.selectedProvider.isLocal
                    ? 'On-device image studio'
                    : upscaling
                    ? 'Video finishing studio'
                    : 'Video studio',
              ),
              SizedBox(height: short ? 5 : 10),
              Text(
                controller.selectedProvider.isLocal
                    ? 'Make it local.'
                    : upscaling
                    ? 'Make it sharper.'
                    : 'Make it move.',
                style: short
                    ? Theme.of(context).textTheme.headlineLarge
                    : Theme.of(context).textTheme.displayLarge,
              ),
              // Short viewports drop the description so the composer itself
              // stays above the fold.
              if (!short) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  controller.selectedProvider.isLocal
                      ? 'Create private still images on this Apple device, with no account or API key.'
                      : upscaling
                      ? 'Remaster a finished clip with source-faithful or creative detail, up to 4K.'
                      : 'Direct one continuous moment, pin the important frames, and let Clawnsole mind the render.',
                  style: TextStyle(color: context.colors.onSurfaceVariant),
                ),
              ],
            ],
          ),
        );
        final plaque = _ProviderPlaque(controller: controller);
        final plaqueLabel = Text(
          'Model & Provider:',
          style: TextStyle(
            color: context.colors.onSurfaceVariant,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: .3,
          ),
        );
        // Wide layouts keep the quiet label and pin the plaque to the far
        // right. Phones drop the heading entirely and place the model selector
        // at the top-right edge to keep the composer compact.
        if (constraints.maxWidth < 720) {
          return Align(alignment: Alignment.topRight, child: plaque);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: Align(alignment: Alignment.centerLeft, child: title),
            ),
            const SizedBox(width: 22),
            plaqueLabel,
            const SizedBox(width: 10),
            plaque,
          ],
        );
      },
    );
  }
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
    await controller.selectProviderModel(provider, model);
  }

  @override
  Widget build(BuildContext context) {
    final ink = PanelSurface.navyLeather.ink(context.tokens);
    return TexturePanel(
      key: const ValueKey('provider-plaque'),
      surface: PanelSurface.navyLeather,
      stitched: true,
      // Both paddings keep content at least 4px clear of the saddle stitch,
      // whose thread sits about 9.6px inside the panel edge.
      padding: _isShort(context)
          ? const EdgeInsets.symmetric(horizontal: 14, vertical: 14)
          : const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
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
              child: Icon(
                _providerPlaqueIcon(controller.selectedProvider.id),
                color: ink.accent,
                size: 18,
                semanticLabel: controller.selectedProvider.name,
              ),
            ),
            const SizedBox(width: 12),
            // Flexible bounds the names on narrow layouts so long provider or
            // model labels ellipsize instead of overflowing the card.
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    controller.selectedProvider.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ink.on,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    controller.selectedModel.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: ink.onMuted, fontSize: 10.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(Icons.unfold_more_rounded, size: 17, color: ink.accent),
          ],
        ),
      ),
    );
  }
}

IconData _providerPlaqueIcon(String providerId) => switch (providerId) {
  'artcraft' => Icons.palette_outlined,
  'atlas' => Icons.cloud_outlined,
  'bfl' => Icons.forest_outlined,
  'ltx' => Icons.movie_filter_outlined,
  _ => Icons.auto_awesome_motion_outlined,
};

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
      final providerIdentity = '${provider.name} ${provider.id}';
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
    final upscaling = form.mode == VideoMode.upscale;
    final draftActive =
        !upscaling &&
        (form.draftAsset != null ||
            form.draftUrl.trim().isNotEmpty ||
            _showDraftPanel);
    final videoActive =
        !draftActive &&
        (upscaling ||
            form.videoAsset != null ||
            form.videoUrl.trim().isNotEmpty ||
            _showVideoPanel);
    final enhancing = form.mode == VideoMode.draftEnhance;
    final short = _isShort(context);
    // "Or start from" alternates fold into the guidance sections instead of
    // occupying a row of their own.
    final videoAction = controller.selectedModel.modes.contains(VideoMode.v2v)
        ? _QuietAction(
            icon: Icons.movie_filter_rounded,
            label: 'Or continue a video',
            onTap: () => setState(() => _showVideoPanel = true),
          )
        : null;
    final draftAction =
        controller.selectedModel.modes.contains(VideoMode.draftEnhance)
        ? _QuietAction(
            icon: Icons.auto_fix_high_rounded,
            label: 'Or enhance a saved draft',
            onTap: () => setState(() => _showDraftPanel = true),
          )
        : null;

    return SurfaceCard(
      padding: EdgeInsets.all(short ? 12 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (!enhancing) ...<Widget>[
            FieldLabel(
              upscaling ? 'Detail guidance · optional' : 'Direction',
              icon: Icons.edit_note_rounded,
            ),
            const SizedBox(height: 7),
            ReferencePromptField(
              key: ValueKey('generation-prompt-${controller.formRevision}'),
              prompt: form.prompt,
              formRevision: controller.formRevision,
              references: _promptReferenceOptions(form.references),
              onChanged: (value) =>
                  controller.updateForm((form) => form.prompt = value),
            ),
            SizedBox(height: short ? 10 : 16),
          ],
          if (draftActive)
            _SourceEditor(
              controller: controller,
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
              controller: controller,
              title: upscaling ? 'Video to upscale' : 'Continue a video',
              description: upscaling
                  ? 'Upload an MP4 up to 20 seconds and 50 MB, at 2560×1440 or below. Hosted HTTP(S) clips also work, and source audio is preserved.'
                  : 'FLUX 3 extends the motion of an uploaded clip or a hosted provider-compatible URL.',
              icon: upscaling
                  ? Icons.high_quality_rounded
                  : Icons.movie_filter_rounded,
              mediaKind: MediaReferenceKind.video,
              asset: form.videoAsset,
              url: form.videoUrl,
              onPick: () async {
                final source = await chooseMediaPickerSource(
                  context,
                  MediaReferenceKind.video,
                );
                if (source != null) await controller.pickVideo(source: source);
              },
              onUrl: controller.updateVideoSourceUrl,
              onDismiss: () {
                setState(() => _showVideoPanel = false);
                controller.updateForm((form) {
                  form.videoAsset = null;
                  form.videoSavedReferenceId = null;
                  form.videoUrl = '';
                  form.videoThumbnailBytes = null;
                  form.videoMetadata = null;
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
            _GuidanceInputsSection(
              controller: controller,
              videoAction: videoAction,
              draftAction: draftAction,
            ),
          SizedBox(height: short ? 8 : 14),
          Divider(height: 1, color: context.colors.outlineVariant),
          SizedBox(height: short ? 8 : 14),
          if (upscaling)
            _UpscaleSettings(controller: controller)
          else if (enhancing)
            _EnhanceSettings(controller: controller)
          else
            _SettingsGrid(controller: controller),
          SizedBox(height: short ? 10 : 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final sideBySide = constraints.maxWidth >= 880;
              final costWidth = sideBySide
                  ? math.min(680.0, (constraints.maxWidth - 14) / 2)
                  : constraints.maxWidth;
              final cost = _CostPreview(
                controller: controller,
                wide: costWidth >= 650,
              );
              final destination = _GenerationDestinationControls(
                controller: controller,
              );
              if (!sideBySide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    cost,
                    SizedBox(height: short ? 10 : 14),
                    destination,
                  ],
                );
              }
              // IntrinsicHeight lets the two panels share one row height
              // inside the scroll view's unbounded column.
              return IntrinsicHeight(
                child: Row(
                  key: const ValueKey('cost-destination-row'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    SizedBox(width: costWidth, child: cost),
                    const SizedBox(width: 14),
                    Expanded(child: destination),
                  ],
                ),
              );
            },
          ),
          SizedBox(height: short ? 8 : 12),
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
    final selected = controller.selectedGenerationFolderId;
    final storageControl =
        controller.supportsLocalLibrary && controller.googleDriveConnected
        ? Wrap(
            spacing: 6,
            runSpacing: 6,
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
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) =>
                        unawaited(controller.setDefaultStorage(value)),
                  ),
                )
                .toList(),
          )
        : StorageBadge(storage: storage);
    final folderMenu = PopupMenuButton<String>(
      key: ValueKey('generation-folder-${storage.name}'),
      tooltip: 'Choose generation folder',
      onSelected: (value) => unawaited(
        controller.setGenerationFolder(value.isEmpty ? null : value),
      ),
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        const PopupMenuItem(value: '', child: Text('Library (top level)')),
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: context.colors.outlineVariant),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.folder_outlined, size: 17),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                selected == null
                    ? 'Library (top level)'
                    : controller.folderPath(selected),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more_rounded, size: 17),
          ],
        ),
      ),
    );
    final newFolder = IconButton(
      tooltip: 'New folder',
      visualDensity: VisualDensity.compact,
      onPressed: () => unawaited(
        _showGenerationFolderDialog(context, controller, parentId: selected),
      ),
      icon: const Icon(Icons.create_new_folder_outlined, size: 18),
    );
    return Container(
      key: const ValueKey('generation-destination-panel'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Tooltip(
            message: 'Save generation to',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Icon(
                  Icons.save_outlined,
                  size: 16,
                  color: context.tokens.brass,
                ),
                const SizedBox(width: 7),
                Text(
                  'SAVE TO',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.3,
                    fontWeight: FontWeight.w700,
                    color: context.colors.onSurface.withValues(alpha: .82),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: storageControl,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: folderMenu,
              ),
              newFolder,
            ],
          ),
          if (controller.supportsGoogleDrive &&
              !controller.googleDriveConnected) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              'Connect Google Drive in Settings to generate directly into your Drive library.',
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
  const _GuidanceInputsSection({
    required this.controller,
    required this.videoAction,
    required this.draftAction,
  });

  final AppController controller;
  final Widget? videoAction;
  final Widget? draftAction;

  @override
  Widget build(BuildContext context) {
    final model = controller.selectedModel;
    final showFrames =
        model.maxKeyframes > 0 || controller.form.keyframes.isNotEmpty;
    final showReferences =
        model.supportsMediaReferences || controller.form.references.isNotEmpty;
    if (!showFrames && !showReferences) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
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
          ),
          if (videoAction != null || draftAction != null) ...<Widget>[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              children: <Widget>[
                if (videoAction != null) videoAction!,
                if (draftAction != null) draftAction!,
              ],
            ),
          ],
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final frames = showFrames
            ? _FramesSection(
                controller: controller,
                compact: compact,
                startActions: <Widget>[
                  if (videoAction != null) videoAction!,
                  if (!showReferences && draftAction != null) draftAction!,
                ],
              )
            : null;
        final references = showReferences
            ? _ReferencesSection(
                controller: controller,
                compact: compact,
                startActions: <Widget>[
                  if (!showFrames && videoAction != null) videoAction!,
                  if (draftAction != null) draftAction!,
                ],
              )
            : null;
        final hasVisualReference =
            controller.form.keyframes.isNotEmpty ||
            controller.form.referenceCount(MediaReferenceKind.image) > 0 ||
            controller.form.referenceCount(MediaReferenceKind.video) > 0;
        late final Widget sections;
        if (frames != null &&
            references != null &&
            constraints.maxWidth >= 880) {
          sections = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: frames),
              const SizedBox(width: 22),
              Expanded(child: references),
            ],
          );
        } else {
          sections = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (frames != null) frames,
              if (frames != null && references != null)
                SizedBox(height: compact ? 12 : 16),
              if (references != null) references,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            sections,
            if (hasVisualReference) ...<Widget>[
              const SizedBox(height: 8),
              _ReferenceNormalizationToggle(controller: controller),
            ],
          ],
        );
      },
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
  final VoidCallback onTap;

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
  const _FramesSection({
    required this.controller,
    this.compact = false,
    this.startActions = const <Widget>[],
  });

  final AppController controller;

  /// Narrow layouts collapse the section to a single header row with inline
  /// add buttons and drop the informational caption.
  final bool compact;

  /// "Or start from" alternates folded into this section's action row.
  final List<Widget> startActions;

  @override
  Widget build(BuildContext context) {
    final form = controller.form;
    final model = controller.selectedModel;
    final setAside = controller.framesBlockedByReferences;
    final conflicted =
        model.framesExclusiveWithReferences &&
        form.keyframes.isNotEmpty &&
        form.references.isNotEmpty;
    final frameLimit = model.supportsTimedKeyframes
        ? '${model.maxKeyframes} frames max · custom timing available'
        : model.supportsEndFrame
        ? '${model.maxKeyframes} frames max · first + last · pinned by the provider'
        : '1 first frame max · pins frame 0';
    final exclusiveInputs = model.maxKeyframes == 1
        ? 'a first frame or creative references'
        : 'first/last frames or creative references';
    final caption = conflicted
        ? '${model.label} cannot combine $exclusiveInputs. Remove one side.'
        : setAside
        ? '$frameLimit. References attached — remove them to add frames.'
        : model.framesExclusiveWithReferences
        ? '$frameLimit. ${model.label}: use $exclusiveInputs, not both.'
        : frameLimit;
    final timingPill = form.keyframes.isNotEmpty && model.supportsTimedKeyframes
        ? TogglePill(
            label: 'Custom timing',
            selected: form.usesTimedKeyframes,
            onChanged: form.requiresTimedKeyframes
                ? null
                : controller.setExactTiming,
          )
        : null;
    final addButtons = setAside
        ? const <Widget>[]
        : KeyframeRole.values
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
              .toList();
    final tiles = form.keyframes.isEmpty
        ? null
        : Wrap(
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
          );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              _SectionLabelChip(
                icon: Icons.collections_rounded,
                label: 'Keyframes',
                hint: caption,
              ),
              if (timingPill != null) timingPill,
              ...addButtons,
              ...startActions,
            ],
          ),
          if (conflicted || setAside) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              caption,
              style: TextStyle(
                color: conflicted
                    ? context.colors.error
                    : context.colors.onSurfaceVariant,
                fontSize: 10.5,
                height: 1.35,
              ),
            ),
          ],
          if (tiles != null) ...<Widget>[const SizedBox(height: 10), tiles],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FieldLabel(
          'Keyframes · optional',
          icon: Icons.collections_rounded,
          trailing: timingPill,
        ),
        const SizedBox(height: 7),
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
        if (tiles != null) ...<Widget>[const SizedBox(height: 10), tiles],
        if (addButtons.isNotEmpty || startActions.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[...addButtons, ...startActions],
          ),
        ],
      ],
    );
  }
}

/// A compact inline section label for narrow layouts, standing in for the
/// full-width [FieldLabel] row inside a [Wrap].
class _SectionLabelChip extends StatelessWidget {
  const _SectionLabelChip({required this.icon, required this.label, this.hint});

  final IconData icon;
  final String label;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 15, color: context.tokens.brass),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10.5,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
            color: context.colors.onSurface.withValues(alpha: .82),
          ),
        ),
      ],
    );
    return hint == null ? row : Tooltip(message: hint!, child: row);
  }
}

class _ReferencesSection extends StatelessWidget {
  const _ReferencesSection({
    required this.controller,
    this.compact = false,
    this.startActions = const <Widget>[],
  });

  final AppController controller;

  /// Narrow layouts collapse the section to a single header row with inline
  /// add buttons and drop the limit summary.
  final bool compact;

  /// "Or start from" alternates folded into this section's action row.
  final List<Widget> startActions;

  @override
  Widget build(BuildContext context) {
    final form = controller.form;
    final model = controller.selectedModel;
    final limits = MediaReferenceKind.values
        .where((kind) => model.maxReferences(kind) > 0)
        .map((kind) {
          final maximum = controller.referenceLimit(kind);
          final label = maximum == 1
              ? switch (kind) {
                  MediaReferenceKind.image => 'image',
                  MediaReferenceKind.video => 'video',
                  MediaReferenceKind.audio => 'audio clip',
                }
              : kind.pluralLabel;
          final seconds = model.maxReferenceSeconds(kind, form.resolution);
          final duration = seconds == null
              ? ''
              : maximum == 1
              ? ' (up to ${seconds}s)'
              : ' (${seconds}s total)';
          return '$maximum $label$duration';
        })
        .join(' · ');
    final limitSummary = model.maxTotalReferences == null
        ? limits
        : '$limits · ${model.maxTotalReferences} files total';
    final setAside = controller.referencesBlockedByFrames;
    final conflicted =
        model.framesExclusiveWithReferences &&
        form.keyframes.isNotEmpty &&
        form.references.isNotEmpty;
    final taskChips =
        !setAside && !conflicted && model.referenceTasks.length > 1
        ? Wrap(
            spacing: 7,
            runSpacing: 7,
            children: model.referenceTasks
                .map(
                  (task) => ChoiceChip(
                    key: ValueKey('reference-task-${task.name}'),
                    label: Text(task.label),
                    selected: form.referenceTask == task,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => controller.setReferenceTask(task),
                    showCheckmark: false,
                  ),
                )
                .toList(),
          )
        : null;
    final notes = <String>[
      if (!setAside && model.maxImageReferences > 0)
        'Creative images can guide the opening, subject, identity, or style; use First frame for stricter frame-0 conditioning.',
      if (setAside && !conflicted)
        'Frames attached — remove them to add creative references.',
      if (!setAside && form.referenceTask != MediaReferenceTask.reference)
        form.referenceTask == MediaReferenceTask.edit
            ? 'Edit uses exactly 1 video · Auto duration · source aspect ratio'
            : 'Extend uses exactly 1 video · source aspect ratio',
      if (!setAside && model.requiresVisualReferenceForAudio)
        'Audio guidance requires at least one image or video reference for this model.',
    ];
    final tiles = form.references.isEmpty
        ? null
        : Wrap(
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
          );
    final addButtons = setAside
        ? const <Widget>[]
        : MediaReferenceKind.values
              .where(
                (kind) =>
                    model.maxReferences(kind) > 0 ||
                    form.referenceCount(kind) > 0,
              )
              .map(
                (kind) =>
                    _AddReferenceButton(controller: controller, kind: kind),
              )
              .toList();
    final noteStyle = TextStyle(
      color: context.colors.onSurfaceVariant,
      fontSize: 10.5,
      height: 1.35,
    );
    if (compact) {
      return Column(
        key: const ValueKey('media-references-section'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SectionLabelChip(
            icon: Icons.perm_media_rounded,
            label: 'References',
            hint: limitSummary,
          ),
          if (addButtons.isNotEmpty || startActions.isNotEmpty) ...<Widget>[
            const SizedBox(height: 7),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[...addButtons, ...startActions],
            ),
          ],
          if (taskChips != null) ...<Widget>[
            const SizedBox(height: 6),
            taskChips,
          ],
          for (final note in notes) ...<Widget>[
            const SizedBox(height: 5),
            Text(note, style: noteStyle),
          ],
          if (tiles != null) ...<Widget>[const SizedBox(height: 10), tiles],
        ],
      );
    }
    return Column(
      key: const ValueKey('media-references-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const FieldLabel(
          'Creative references · optional',
          icon: Icons.perm_media_rounded,
        ),
        const SizedBox(height: 7),
        if (taskChips != null) ...<Widget>[
          taskChips,
          const SizedBox(height: 7),
        ],
        Text(
          limitSummary,
          style: TextStyle(
            color: context.colors.onSurfaceVariant,
            fontSize: 11.5,
            height: 1.4,
          ),
        ),
        for (final note in notes) ...<Widget>[
          const SizedBox(height: 5),
          Text(note, style: noteStyle),
        ],
        if (tiles != null) ...<Widget>[const SizedBox(height: 10), tiles],
        if (addButtons.isNotEmpty || startActions.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[...addButtons, ...startActions],
          ),
        ],
      ],
    );
  }
}

class _ReferenceNormalizationToggle extends StatelessWidget {
  const _ReferenceNormalizationToggle({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
    key: const ValueKey('auto-fix-reference-videos'),
    contentPadding: EdgeInsets.zero,
    dense: true,
    value: controller.autoFixReferenceVideos,
    onChanged: (value) =>
        unawaited(controller.setAutoFixReferenceVideos(value)),
    title: const Text('Normalize visual references'),
    subtitle: const Text('Converts incompatible images and videos on upload.'),
  );
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
                child: Semantics(
                  button: reference.kind != MediaReferenceKind.audio,
                  label: 'View ${reference.label} full screen',
                  child: InkWell(
                    key: ValueKey('view-media-reference-${reference.id}'),
                    onTap: reference.kind == MediaReferenceKind.audio
                        ? null
                        : () => unawaited(
                            showVisualReferenceViewer(
                              context,
                              controller: controller,
                              kind: reference.kind,
                              label: reference.label,
                              bytes: reference.asset?.bytes,
                              mimeType: reference.asset?.mimeType,
                              localPath: reference.asset?.path,
                              reference:
                                  reference.asset?.retained ??
                                  reference.retained,
                              thumbnailReference:
                                  reference.thumbnailAsset ??
                                  reference.asset?.thumbnailAsset,
                              thumbnailBytes:
                                  reference.thumbnailBytes ??
                                  reference.asset?.thumbnailBytes,
                              source: reference.source,
                            ),
                          ),
                    child: MediaThumbnail(
                      gateway: controller.gateway,
                      kind: reference.kind,
                      bytes: reference.asset?.bytes,
                      mimeType: reference.asset?.mimeType,
                      localPath: reference.asset?.path,
                      reference:
                          reference.asset?.retained ?? reference.retained,
                      thumbnailReference:
                          reference.thumbnailAsset ??
                          reference.asset?.thumbnailAsset,
                      thumbnailBytes:
                          reference.thumbnailBytes ??
                          reference.asset?.thumbnailBytes,
                      source: reference.source,
                      semanticsLabel: '${reference.label} thumbnail',
                      onThumbnail: reference.kind == MediaReferenceKind.video
                          ? (bytes) => controller.rememberReferenceThumbnail(
                              reference.id,
                              bytes,
                            )
                          : null,
                    ),
                  ),
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
        if (controller.canUseReferenceAsFirstFrame(reference)) ...<Widget>[
          const SizedBox(height: 4),
          TextButton.icon(
            key: ValueKey('use-reference-as-first-frame-${reference.id}'),
            onPressed: () =>
                unawaited(controller.useReferenceAsFirstFrame(reference.id)),
            icon: const Icon(Icons.filter_1_rounded, size: 14),
            label: const Text('Use as first frame'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
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
          unawaited(() async {
            final source = await chooseMediaPickerSource(context, kind);
            if (source != null) {
              await controller.addMediaReferences(kind, source: source);
            }
          }());
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
              Flexible(child: Text('Choose saved ${kind.pluralLabel}')),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'upload',
          child: Row(
            children: <Widget>[
              const Icon(Icons.upload_file_rounded, size: 17),
              const SizedBox(width: 9),
              Flexible(child: Text('Upload ${kind.pluralLabel}')),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'url',
          child: Row(
            children: <Widget>[
              const Icon(Icons.add_link_rounded, size: 17),
              const SizedBox(width: 9),
              Flexible(child: Text('Paste ${kind.label.toLowerCase()} URL')),
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
                  child: Semantics(
                    button: true,
                    label: 'View ${frame.label} full screen',
                    child: InkWell(
                      key: ValueKey('view-keyframe-${frame.id}'),
                      onTap: () => unawaited(
                        showVisualReferenceViewer(
                          context,
                          controller: controller,
                          kind: MediaReferenceKind.image,
                          label: frame.label,
                          bytes: frame.asset?.bytes,
                          mimeType: frame.asset?.mimeType,
                          localPath: frame.asset?.path,
                          reference: frame.asset?.retained ?? frame.retained,
                          source: frame.source,
                        ),
                      ),
                      child: frame.asset != null
                          ? Image.memory(frame.asset!.bytes, fit: BoxFit.cover)
                          : Uri.tryParse(frame.source)?.scheme == 'https'
                          ? Image.network(
                              frame.source,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const _FrameLinkGhost(),
                            )
                          : const _FrameLinkGhost(),
                    ),
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
            unawaited(() async {
              final source = await chooseMediaPickerSource(
                context,
                MediaReferenceKind.image,
              );
              if (source != null) {
                await controller.addImageFrame(role, source: source);
              }
            }());
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
                Flexible(child: Text('Upload an image')),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'url',
            child: Row(
              children: <Widget>[
                Icon(Icons.add_link_rounded, size: 17),
                SizedBox(width: 9),
                Flexible(child: Text('Paste an image URL')),
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

String _videoMetadataLabel(VideoSourceMetadata metadata) {
  final seconds =
      metadata.durationSeconds == metadata.durationSeconds.roundToDouble()
      ? metadata.durationSeconds.toStringAsFixed(0)
      : metadata.durationSeconds.toStringAsFixed(1);
  return '${metadata.width}×${metadata.height} · $seconds s';
}

class _SourceEditor extends StatelessWidget {
  const _SourceEditor({
    required this.controller,
    required this.title,
    required this.description,
    required this.icon,
    required this.asset,
    required this.url,
    required this.onPick,
    required this.onUrl,
    required this.onDismiss,
    required this.formRevision,
    this.mediaKind,
  });

  final AppController controller;
  final String title;
  final String description;
  final IconData icon;
  final PickedAsset? asset;
  final String url;
  final Future<void> Function() onPick;
  final ValueChanged<String> onUrl;
  final VoidCallback onDismiss;
  final int formRevision;
  final MediaReferenceKind? mediaKind;

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
            key: ValueKey('view-$title-file-reference'),
            tileColor: context.colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
            onTap: mediaKind == null
                ? null
                : () => unawaited(
                    showVisualReferenceViewer(
                      context,
                      controller: controller,
                      kind: mediaKind!,
                      label: asset!.name,
                      bytes: asset!.bytes,
                      mimeType: asset!.mimeType,
                      localPath: asset!.path,
                      reference: asset!.retained,
                      thumbnailReference: asset!.thumbnailAsset,
                      thumbnailBytes: asset!.thumbnailBytes,
                    ),
                  ),
            leading: mediaKind == null
                ? const Icon(Icons.insert_drive_file_rounded)
                : ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: SizedBox(
                      width: 66,
                      height: 44,
                      child: MediaThumbnail(
                        gateway: controller.gateway,
                        kind: mediaKind!,
                        bytes: asset!.bytes,
                        mimeType: asset!.mimeType,
                        localPath: asset!.path,
                        reference: asset!.retained,
                        thumbnailReference: asset!.thumbnailAsset,
                        thumbnailBytes: asset!.thumbnailBytes,
                        semanticsLabel: '${asset!.name} thumbnail',
                        onThumbnail: mediaKind == MediaReferenceKind.video
                            ? controller.rememberVideoSourceThumbnail
                            : null,
                        onVideoMetadata: mediaKind == MediaReferenceKind.video
                            ? controller.rememberVideoSourceMetadata
                            : null,
                      ),
                    ),
                  ),
            title: Text(
              asset!.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              <String>[
                formatBytes(asset!.bytes.length),
                if (mediaKind == MediaReferenceKind.video &&
                    controller.form.videoMetadata != null)
                  _videoMetadataLabel(controller.form.videoMetadata!),
              ].join(' · '),
            ),
            trailing: IconButton(
              tooltip: 'Clear file',
              onPressed: onDismiss,
              icon: const Icon(Icons.close_rounded),
            ),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (mediaKind != null &&
                  Uri.tryParse(url.trim())?.scheme == 'https') ...<Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: SizedBox(
                    width: 160,
                    height: 90,
                    child: InkWell(
                      key: ValueKey('view-$title-url-reference'),
                      onTap: () => unawaited(
                        showVisualReferenceViewer(
                          context,
                          controller: controller,
                          kind: mediaKind!,
                          label: title,
                          source: url.trim(),
                          thumbnailBytes: controller.form.videoThumbnailBytes,
                        ),
                      ),
                      child: MediaThumbnail(
                        gateway: controller.gateway,
                        kind: mediaKind!,
                        source: url.trim(),
                        thumbnailBytes: controller.form.videoThumbnailBytes,
                        semanticsLabel: '$title source thumbnail',
                        onThumbnail: mediaKind == MediaReferenceKind.video
                            ? controller.rememberVideoSourceThumbnail
                            : null,
                        onVideoMetadata: mediaKind == MediaReferenceKind.video
                            ? controller.rememberVideoSourceMetadata
                            : null,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
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
        const SizedBox(height: 6),
        _RatioDropdown(controller: controller),
        if (controller.selectedModel.outputKind ==
            GenerationOutputKind.video) ...<Widget>[
          const SizedBox(height: 10),
          _DurationControl(controller: controller),
          if (controller.selectedModel.supportsFrameRate) ...<Widget>[
            const SizedBox(height: 10),
            _FrameRateControl(controller: controller),
          ],
        ],
      ];
      final second = <Widget>[
        const FieldLabel('Finish', icon: Icons.high_quality_rounded),
        const SizedBox(height: 6),
        _ResolutionDropdown(controller: controller),
        const SizedBox(height: 4),
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
          const SizedBox(height: 6),
          _SafetyControl(controller: controller),
        ],
        if (controller.selectedModel.supportsSeed) ...<Widget>[
          const SizedBox(height: 8),
          const FieldLabel('Seed', icon: Icons.tag_rounded),
          const SizedBox(height: 6),
          _SeedControl(controller: controller),
        ],
      ];
      if (!columns) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[...first, const SizedBox(height: 16), ...second],
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

/// A row of digits for models that accept a reproducible seed. Empty means
/// the provider picks a random one; the dice rolls a fresh explicit seed.
class _SeedControl extends StatefulWidget {
  const _SeedControl({required this.controller});

  final AppController controller;

  @override
  State<_SeedControl> createState() => _SeedControlState();
}

class _SeedControlState extends State<_SeedControl> {
  late final TextEditingController _text = TextEditingController(
    text: widget.controller.form.seed?.toString() ?? '',
  );
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seedText = widget.controller.form.seed?.toString() ?? '';
    if (!_focus.hasFocus && _text.text != seedText) {
      _text.text = seedText;
    }
    return Row(
      children: <Widget>[
        Expanded(
          child: TextField(
            key: const ValueKey('seed-input'),
            controller: _text,
            focusNode: _focus,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            style: const TextStyle(
              fontSize: 12.5,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
            decoration: const InputDecoration(
              hintText: 'Random',
              helperText: 'Same seed + settings repeats a take',
              helperStyle: TextStyle(fontSize: 9.5),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            ),
            onChanged: (value) =>
                widget.controller.setSeed(int.tryParse(value)),
          ),
        ),
        const SizedBox(width: 6),
        IconButton(
          tooltip: 'New random seed',
          visualDensity: VisualDensity.compact,
          onPressed: () {
            final seed = math.Random().nextInt(1 << 31);
            widget.controller.setSeed(seed);
            _text.text = '$seed';
          },
          icon: const Icon(Icons.casino_rounded, size: 19),
        ),
      ],
    );
  }
}

class _UpscaleSettings extends StatelessWidget {
  const _UpscaleSettings({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final form = controller.form;
      final creative = form.upscaleCreativity == 1;
      final factor = form.upscaleFactor;
      final factorText = factor == factor.roundToDouble()
          ? factor.toStringAsFixed(0)
          : factor.toStringAsFixed(1);
      final scale = <Widget>[
        FieldLabel(
          'Upscale factor',
          icon: Icons.zoom_out_map_rounded,
          trailing: CounterReadout(factorText, unit: '×'),
        ),
        const SizedBox(height: 8),
        HardwareSlider(
          key: const ValueKey('upscale-factor-slider'),
          min: 1.5,
          max: 3,
          divisions: 15,
          label: '$factorText×',
          value: factor,
          onChanged: (value) => controller.updateForm(
            (form) => form.upscaleFactor = (value * 10).roundToDouble() / 10,
          ),
        ),
        Text(
          'The source aspect ratio is preserved. Output is capped at about 14.4 megapixels.',
          style: TextStyle(
            color: context.colors.onSurfaceVariant,
            fontSize: 10.5,
          ),
        ),
      ];
      final finish = <Widget>[
        const FieldLabel('Detail mode', icon: Icons.auto_awesome_rounded),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: HardwareChoiceSwitch(
            key: const ValueKey('upscale-creativity-switch'),
            firstLabel: 'PRECISE',
            secondLabel: 'CREATIVE',
            firstSelected: !creative,
            onChanged: (precise) => controller.updateForm(
              (form) => form.upscaleCreativity = precise ? 0 : 1,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          creative
              ? 'Creative restores and invents fine detail. It is sharpest on generated footage, but faces and products can drift.'
              : 'Precise sharpens while preserving identity, text, products, and brand assets as faithfully as possible.',
          style: TextStyle(
            color: context.colors.onSurfaceVariant,
            fontSize: 10.5,
          ),
        ),
        const SizedBox(height: 16),
        _SafetyControl(controller: controller),
      ];
      if (constraints.maxWidth <= 640) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[...scale, const SizedBox(height: 22), ...finish],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: scale,
            ),
          ),
          const SizedBox(width: 26),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: finish,
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
        const SizedBox(height: 6),
        _ResolutionDropdown(controller: controller),
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

/// The aspect ratio as a console-key dropdown: the trigger wears the current
/// ratio's drawn glyph, and each menu entry pairs its glyph with the label
/// and a plain-words hint.
class _RatioDropdown extends StatelessWidget {
  const _RatioDropdown({required this.controller});

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

  static String _label(String ratio) => ratio == 'auto' ? 'Auto' : ratio;

  @override
  Widget build(BuildContext context) {
    final current = controller.form.aspectRatio;
    return PopupMenuButton<String>(
      key: const ValueKey('ratio-dropdown'),
      tooltip: 'Aspect ratio · ${_hints[current] ?? current}',
      initialValue: current,
      onSelected: (ratio) =>
          controller.updateForm((form) => form.aspectRatio = ratio),
      itemBuilder: (context) => controller.availableAspectRatios
          .map(
            (ratio) => PopupMenuItem<String>(
              key: ValueKey('ratio-$ratio'),
              value: ratio,
              height: 40,
              child: Row(
                children: <Widget>[
                  Icon(ratio == current ? Icons.check_rounded : null, size: 16),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 30,
                    height: 20,
                    child: Center(
                      child: _RatioGlyph(
                        ratio: ratio,
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _label(ratio),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      _hints[ratio] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: consoleKeyDecoration(context, selected: false, radius: 10),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 30,
              height: 20,
              child: Center(
                child: _RatioGlyph(
                  ratio: current,
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                _label(current),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(
              Icons.expand_more_rounded,
              size: 17,
              color: context.colors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
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
    final range = controller.selectedDurationRange;
    final autoLocked =
        form.requiresFixedDuration ||
        form.referenceTask == MediaReferenceTask.edit;
    final rangeText = range.minimumSeconds == range.maximumSeconds
        ? '${range.minimumSeconds} seconds'
        : '${range.minimumSeconds}–${range.maximumSeconds} seconds';
    final readout = CounterReadoutField(
      fieldKey: const ValueKey('duration-input'),
      value: form.autoDuration ? 'AUTO' : '${form.durationSeconds}',
      unit: form.autoDuration ? null : 's',
      enabled: !(form.autoDuration && autoLocked),
      // Starting to type is the keyboard's version of touching the slider:
      // it drops Auto and takes manual control.
      onEditingStarted: form.autoDuration && !autoLocked
          ? () => controller.setAutoDuration(false)
          : null,
      onCommit: controller.setDurationSeconds,
    );
    final modeSwitch = model.supportsAutoDuration
        ? HardwareChoiceSwitch(
            key: const ValueKey('duration-mode-switch'),
            firstKey: const ValueKey('duration-mode-auto'),
            secondKey: const ValueKey('duration-mode-manual'),
            firstLabel: 'AUTO',
            secondLabel: 'MANUAL',
            firstSelected: form.autoDuration,
            onChanged: autoLocked ? null : controller.setAutoDuration,
          )
        : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final inlineSwitch = modeSwitch != null && constraints.maxWidth >= 430;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            FieldLabel(
              'Duration',
              icon: Icons.timelapse_rounded,
              trailing: inlineSwitch
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        modeSwitch,
                        const SizedBox(width: 10),
                        readout,
                      ],
                    )
                  : readout,
            ),
            if (modeSwitch != null && !inlineSwitch)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: modeSwitch,
                ),
              ),
            if (form.autoDuration)
              Container(
                key: const ValueKey('auto-duration-range'),
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: context.colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: context.colors.outlineVariant),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 17,
                      color: context.tokens.brass,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        '${model.label} can choose $rangeText at the current resolution.',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else ...<Widget>[
              HardwareSlider(
                key: const ValueKey('duration-slider'),
                min: range.minimumSeconds.toDouble(),
                max: range.maximumSeconds.toDouble(),
                divisions: range.divisions,
                label: '${form.durationSeconds} s',
                value: form.durationSeconds.toDouble(),
                onChanged: (value) =>
                    controller.setDurationSeconds(value.round()),
              ),
              Row(
                children: <Widget>[
                  Text(
                    '${range.minimumSeconds} s',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${range.maximumSeconds} s',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
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
      },
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

/// The output resolution as a console-key dropdown; draft mode dims every
/// choice but the provider's HD draft tier.
class _ResolutionDropdown extends StatelessWidget {
  const _ResolutionDropdown({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final resolutions = controller.availableResolutions;
    final current = resolutions.firstWhere(
      (item) => item.id == controller.form.resolution,
      orElse: () => resolutions.first,
    );
    return PopupMenuButton<String>(
      key: const ValueKey('resolution-dropdown'),
      tooltip: 'Resolution',
      initialValue: current.id,
      onSelected: (id) => controller.updateForm((form) => form.resolution = id),
      itemBuilder: (context) => resolutions.map((resolution) {
        final enabled = !controller.form.draft || resolution.id == 'hd';
        return PopupMenuItem<String>(
          key: ValueKey('resolution-${resolution.id}'),
          value: resolution.id,
          enabled: enabled,
          height: 44,
          child: Opacity(
            opacity: enabled ? 1 : .45,
            child: Row(
              children: <Widget>[
                Icon(
                  resolution.id == current.id ? Icons.check_rounded : null,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      resolution.label,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      resolution.detail,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
        decoration: consoleKeyDecoration(context, selected: false, radius: 10),
        child: Row(
          children: <Widget>[
            Text(
              current.label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                current.detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
            Icon(
              Icons.expand_more_rounded,
              size: 17,
              color: context.colors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
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
  const _CostPreview({required this.controller, this.wide = false});

  final AppController controller;

  /// Wide layouts render the whole estimate as one console row; narrow ones
  /// stack it. Passed in rather than measured so the panel stays usable
  /// inside an [IntrinsicHeight] row.
  final bool wide;

  @override
  Widget build(BuildContext context) {
    if (controller.selectedProvider.isLocal) {
      final frames = controller.selectedModel.supportsFrameRate
          ? controller.form.frameRate * controller.form.durationSeconds
          : 1;
      return TexturePanel(
        surface: PanelSurface.hunterFelt,
        stitched: true,
        // Clears the saddle stitch (thread about 9.6px inside the panel edge)
        // by roughly 4px on every side.
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
                  const SizedBox(height: 2),
                  Text(
                    controller.selectedModel.outputKind ==
                            GenerationOutputKind.image
                        ? 'One Apple image'
                        : '$frames Apple frames → silent MP4',
                    style: TextStyle(
                      color: context.tokens.onMoney,
                      fontFamily: 'Fraunces',
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
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
    final hasUpscaleSource =
        controller.form.videoAsset != null ||
        controller.form.videoUrl.trim().isNotEmpty;
    final calculation =
        controller.form.mode == VideoMode.upscale &&
            hasUpscaleSource &&
            controller.form.videoMetadata == null
        ? 'Reading source dimensions and duration…'
        : estimate.calculation;
    final providerUnits = estimate.providerUnitsMinimum != null;
    final account = controller.providerAccounts[controller.selectedProviderId];
    final balanceUsesCredits = account?.currency == 'credits';
    final rateLabel = estimate.rateUsd == null
        ? null
        : '${formatUsdAmount(estimate.rateUsd!)} / ${estimate.rateUnit ?? 'second'}';
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
    final basis =
        '${controller.form.draft ? 'Drafts use the provider’s HD draft tier. ' : ''}'
        '${estimate.basis == 'artcraft-live-quote'
            ? 'Live quote calculated from the current prompt and settings.'
            : estimate.basis == 'input-derived-published-rate'
            ? 'Calculated from the source dimensions, duration, scale, and selected mode.'
            : 'Calculated from the current pricing settings at the provider’s published or live rate.'}';
    final badge = Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: tokens.moneyAccent),
        color: tokens.onMoney.withValues(alpha: .05),
      ),
      child: Icon(Icons.toll_rounded, color: tokens.moneyAccent, size: 15),
    );
    final charge = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'ESTIMATED CHARGE',
          style: TextStyle(
            color: tokens.onMoneyMuted,
            fontSize: 8.5,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          formatUsdAmountRange(estimate.minimumUsd, estimate.maximumUsd),
          style: TextStyle(
            fontFamily: 'Fraunces',
            color: tokens.onMoney,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
    final rate = Text(
      rateLabel ?? controller.selectedModel.label,
      key: const ValueKey('estimate-rate'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: 'Fraunces',
        color: tokens.moneyAccent,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
    final credits = providerUnits
        ? Text(
            '${formatCreditRange(estimate.providerUnitsMinimum!, estimate.providerUnitsMaximum!)} credits',
            key: const ValueKey('estimate-provider-units'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tokens.onMoneyMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          )
        : null;
    // Providers without a numeric balance (console-only) skip the line
    // entirely; the top-right balance pill already links to the console.
    final afterValue = afterMin == null || afterMax == null
        ? null
        : balanceUsesCredits
        ? '${formatCreditRange(afterMin, afterMax)} credits'
        : formatUsdAmountRange(afterMin, afterMax);
    final rateCard = Tooltip(
      message: basis,
      child: TextButton(
        onPressed: () => unawaited(
          launchUrl(Uri.parse(controller.selectedProvider.pricingUrl)),
        ),
        style: TextButton.styleFrom(
          foregroundColor: tokens.moneyAccent,
          minimumSize: const Size(0, 26),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        child: const Text('Rate card ↗'),
      ),
    );
    return TexturePanel(
      key: const ValueKey('estimated-charge-panel'),
      surface: PanelSurface.hunterFelt,
      stitched: true,
      // Clears the saddle stitch (thread about 9.6px inside the panel edge)
      // by roughly 4px on every side.
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Builder(
        builder: (context) {
          // One console row when the felt is wide enough; the tight column
          // otherwise. Align keeps the content vertically centered when the
          // save-destination panel beside it is taller.
          if (wide) {
            return Align(
              alignment: Alignment.centerLeft,
              child: Row(
                children: <Widget>[
                  badge,
                  const SizedBox(width: 10),
                  charge,
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Flexible(child: rate),
                            if (credits != null) ...<Widget>[
                              const SizedBox(width: 8),
                              Flexible(child: credits),
                            ],
                          ],
                        ),
                        if (calculation != null) ...<Widget>[
                          const SizedBox(height: 2),
                          Text(
                            calculation,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tokens.onMoneyMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (afterValue != null) ...<Widget>[
                    const SizedBox(width: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: _BalanceLine(
                        label: 'Estimated after',
                        value: afterValue,
                      ),
                    ),
                  ],
                  const SizedBox(width: 6),
                  rateCard,
                ],
              ),
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  badge,
                  const SizedBox(width: 10),
                  Expanded(child: charge),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        rate,
                        if (credits != null) ...<Widget>[
                          const SizedBox(height: 1),
                          credits,
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (calculation != null) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  calculation,
                  style: TextStyle(
                    color: tokens.onMoneyMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              // Without a numeric balance the divider row has nothing to
              // carry, so the Rate card joins the basis caption instead.
              if (afterValue != null) ...<Widget>[
                const SizedBox(height: 7),
                Divider(
                  height: 1,
                  color: tokens.onMoney.withValues(alpha: .14),
                ),
                const SizedBox(height: 7),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _BalanceLine(
                        label: 'Estimated after',
                        value: afterValue,
                        vertical: true,
                      ),
                    ),
                    rateCard,
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  basis,
                  style: TextStyle(color: tokens.onMoneyMuted, fontSize: 9.5),
                ),
              ] else ...<Widget>[
                const SizedBox(height: 4),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        basis,
                        style: TextStyle(
                          color: tokens.onMoneyMuted,
                          fontSize: 9.5,
                        ),
                      ),
                    ),
                    rateCard,
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _BalanceLine extends StatelessWidget {
  const _BalanceLine({
    required this.label,
    required this.value,
    this.vertical = false,
  });

  final String label;
  final String value;

  /// Stacks the label above the value for narrow layouts. Horizontal lines
  /// need a bounded width so the flexible value can shrink.
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final labelText = Text(
      label.toUpperCase(),
      style: TextStyle(
        color: context.tokens.onMoneyMuted,
        fontSize: 8.5,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w700,
      ),
    );
    final valueText = Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: context.tokens.onMoney,
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
      ),
    );
    return vertical
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[labelText, const SizedBox(height: 2), valueText],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              labelText,
              const SizedBox(width: 6),
              Flexible(child: valueText),
            ],
          );
  }
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
            : form.mode == VideoMode.upscale
            ? 'Upscale video'
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

class _RecentWork extends StatefulWidget {
  const _RecentWork({required this.controller});

  final AppController controller;

  @override
  State<_RecentWork> createState() => _RecentWorkState();
}

class _RecentWorkState extends State<_RecentWork> {
  static const int _itemLimit = 100;

  final InlineVideoRegistry _inlinePlayback = InlineVideoRegistry();

  AppController get controller => widget.controller;

  @override
  void dispose() {
    _inlinePlayback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InlineVideoRegistryScope(
    registry: _inlinePlayback,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LayoutBuilder(
          builder: (context, constraints) {
            final title = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Eyebrow('On the branch'),
                const SizedBox(height: 6),
                Text(
                  'Recent work',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ],
            );
            final toggle = GenerationViewToggle(
              keyPrefix: 'recent-work-view',
              value: controller.recentWorkViewMode,
              onChanged: (value) =>
                  unawaited(controller.setRecentWorkViewMode(value)),
            );
            final library = TextButton(
              onPressed: () =>
                  unawaited(controller.navigate(AppSection.library)),
              child: const Text('View library'),
            );
            // Wide headers carry the view toggle inline so the first card
            // starts a row sooner; narrow ones keep it on its own line.
            if (constraints.maxWidth >= 520) {
              return Row(
                children: <Widget>[
                  Expanded(child: title),
                  toggle,
                  if (controller.supportsGoogleDrive) ...<Widget>[
                    const SizedBox(width: 8),
                    DriveRefreshButton(
                      controller: controller,
                      keyPrefix: 'recent-work',
                      compact: true,
                    ),
                  ],
                  const SizedBox(width: 8),
                  library,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(child: title),
                    library,
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    if (controller.supportsGoogleDrive) ...<Widget>[
                      DriveRefreshButton(
                        controller: controller,
                        keyPrefix: 'recent-work',
                        compact: true,
                      ),
                      const SizedBox(width: 8),
                    ],
                    toggle,
                  ],
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        if (controller.visibleGenerations.isEmpty)
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
        else if (controller.recentWorkViewMode == GenerationViewMode.compact)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: controller.visibleGenerations
                .take(_itemLimit)
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: CompactGenerationRow(
                      controller: controller,
                      item: item,
                    ),
                  ),
                )
                .toList(),
          )
        else
          // Mini and full modes lay out the same cards, at the same widths,
          // as the Library, so recent films read identically on both screens.
          LayoutBuilder(
            builder: (context, constraints) {
              final layout = GenerationCardGrid.fit(
                constraints.maxWidth,
                controller.recentWorkViewMode,
              );
              return Wrap(
                spacing: GenerationCardGrid.gap,
                runSpacing: GenerationCardGrid.gap,
                children: controller.visibleGenerations
                    .take(_itemLimit)
                    .map(
                      (item) => SizedBox(
                        width: layout.tileWidth,
                        child:
                            controller.recentWorkViewMode ==
                                GenerationViewMode.mini
                            ? MiniGenerationCard(
                                controller: controller,
                                item: item,
                              )
                            : GenerationCard(
                                controller: controller,
                                item: item,
                              ),
                      ),
                    )
                    .toList(),
              );
            },
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
    ),
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
