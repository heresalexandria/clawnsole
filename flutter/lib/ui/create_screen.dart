import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import '../core/models.dart';
import '../core/provider_catalog.dart';
import 'app_intents.dart';
import 'common_widgets.dart';
import 'claw_mark.dart';
import 'composer_tab_rail.dart';
import 'formatters.dart';
import 'generation_view_widgets.dart';
import 'hardware.dart';
import 'inline_video.dart';
import 'library_screen.dart';
import 'media_picker_source.dart';
import 'media_thumbnail.dart';
import 'panels.dart';
import 'prompt_rewrite_dialog.dart';
import 'reference_prompt_field.dart';
import 'references_screen.dart';
import 'visual_reference_viewer.dart';

/// Below this window height the Create screen switches to its dense spacing
/// so the whole composer lands above the fold on a 900px-tall display.
bool _isShort(BuildContext context) => MediaQuery.sizeOf(context).height < 950;

class CreateScreen extends StatefulWidget {
  const CreateScreen({required this.controller, super.key});

  final AppController controller;

  @override
  State<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends State<CreateScreen> {
  static const int _pageSize = 20;

  final ScrollController _scrollController = ScrollController();
  int _itemLimit = _pageSize;
  bool _pageAdvancePending = false;
  GenerationViewMode? _viewMode;

  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadMoreNearEnd);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _loadMoreNearEnd() {
    if (_scrollController.position.extentAfter < 720) _loadMore();
  }

  void _loadMore() {
    final items = controller.visibleGenerations;
    if (_pageAdvancePending || _itemLimit >= items.length) return;
    _pageAdvancePending = true;
    final previousLimit = _itemLimit;
    setState(() => _itemLimit += _pageSize);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pageAdvancePending = false;
    });
    controller.prefetchListedVideos(
      items
          .skip(previousLimit)
          .take(_pageSize)
          .where((item) => !item.isImage)
          .map((item) => item.resultAsset),
    );
  }

  void _syncListingPage() {
    if (_viewMode == controller.recentWorkViewMode) return;
    _viewMode = controller.recentWorkViewMode;
    _itemLimit = _pageSize;
    _pageAdvancePending = false;
  }

  @override
  Widget build(BuildContext context) {
    _syncListingPage();
    return LayoutBuilder(
      builder: (context, constraints) {
        final short = _isShort(context);
        final pad = constraints.maxWidth < 620 ? 16.0 : (short ? 20.0 : 28.0);
        // ⌘/Ctrl+Enter (mapped app-wide) runs the form from anywhere on this
        // screen, including inside the prompt field.
        return Actions(
          actions: <Type, Action<Intent>>{
            GenerateIntent: CallbackAction<GenerateIntent>(
              onInvoke: (_) {
                if (!controller.submitting) {
                  unawaited(
                    _submitWithProviderRetentionWarning(context, controller),
                  );
                }
                return null;
              },
            ),
          },
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: EdgeInsets.fromLTRB(pad, short ? 10 : pad, pad, pad),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _CreateHeading(controller: controller),
                    SizedBox(height: short ? 8 : 18),
                    // Each tab owns its disclosure panels and field state, so
                    // switching drafts rebuilds the composer from scratch.
                    KeyedSubtree(
                      key: ValueKey<String>(
                        'composer-${controller.activeComposerTabId}',
                      ),
                      child: _Composer(controller: controller),
                    ),
                    SizedBox(height: short ? 12 : 24),
                    _RecentWork(
                      controller: controller,
                      itemLimit: _itemLimit,
                      onLoadMore: _loadMore,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CreateHeading extends StatelessWidget {
  const _CreateHeading({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final local = controller.selectedProvider.isLocal;
    final upscaling = controller.selectedModel.isUpscaler;
    final short = _isShort(context);
    // A studio with nothing to render with yet explains the
    // bring-your-own-key model under the rail; short viewports drop the line
    // so the composer itself stays above the fold.
    final guidance = !short && controller.needsProviderSetup && !local
        ? _FirstRunGuidance(controller: controller)
        : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Phones drop the eyebrow and keep just the rail, the rule running
        // to the edge; the model plaque lives in the composer's footer.
        if (constraints.maxWidth < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ComposerTabRail(controller: controller),
              if (guidance != null) ...<Widget>[
                const SizedBox(height: 10),
                guidance,
              ],
            ],
          );
        }
        // Wider layouts: a quiet eyebrow names the studio, then the rail —
        // tabs on the left, the rule running to the edge. There is no display
        // headline; the tabs are the heading.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: Eyebrow(
                local
                    ? 'On-device image studio'
                    : upscaling
                    ? 'Video finishing studio'
                    : 'Video studio',
              ),
            ),
            SizedBox(height: short ? 6 : 8),
            ComposerTabRail(controller: controller),
            if (guidance != null) ...<Widget>[
              const SizedBox(height: 12),
              guidance,
            ],
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
    // Starred providers open expanded: they are pinned for quick reach.
    _collapsedProviders.addAll(
      controller.providers
          .where(
            (provider) =>
                provider.id != controller.selectedProviderId &&
                !controller.isFavoriteProvider(provider.id),
          )
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
              controller: controller,
              collapsedProviders: _collapsedProviders,
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
  'krea' => Icons.gesture_outlined,
  'ltx' => Icons.movie_filter_outlined,
  _ => Icons.auto_awesome_motion_outlined,
};

class _ProviderSearchMenu extends StatefulWidget {
  const _ProviderSearchMenu({
    required this.controller,
    required this.collapsedProviders,
    required this.onExpandedChanged,
  });

  final AppController controller;
  final Set<String> collapsedProviders;
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

  void _toggleProviderFavorite(String providerId) {
    // A freshly starred provider opens so its models are in reach at once.
    if (!widget.controller.isFavoriteProvider(providerId)) {
      widget.onExpandedChanged(providerId, true);
    }
    unawaited(widget.controller.toggleFavoriteProvider(providerId));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => _buildMenu(context),
  );

  Widget _buildMenu(BuildContext context) {
    final controller = widget.controller;
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
    // Starred providers lead the list; a search keeps that order too.
    for (final provider in controller.providersByPreference) {
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
    // Favorites sit above the provider sections while browsing; a search
    // already narrows the list, so it speaks for itself.
    final favorites = query.isEmpty
        ? controller.favoriteModels
        : const <FavoriteModel>[];
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
                    children: <Widget>[
                      if (favorites.isNotEmpty)
                        _FavoriteModelsSection(
                          key: const ValueKey('provider-model-favorites'),
                          favorites: favorites,
                          selectedProviderId: controller.selectedProviderId,
                          selectedModelId: controller.selectedModel.id,
                          onUnstar: (favorite) => unawaited(
                            controller.toggleFavoriteModel(
                              favorite.provider.id,
                              favorite.model.id,
                            ),
                          ),
                        ),
                      ...matches.map(
                        (match) => _ProviderMenuSection(
                          key: ValueKey(
                            'provider-model-section-${match.provider.id}',
                          ),
                          provider: match.provider,
                          models: match.models,
                          forceExpanded: query.isNotEmpty,
                          initiallyExpanded: !widget.collapsedProviders
                              .contains(match.provider.id),
                          selectedProviderId: controller.selectedProviderId,
                          selectedModelId: controller.selectedModel.id,
                          favorite: controller.isFavoriteProvider(
                            match.provider.id,
                          ),
                          isModelFavorite: (model) => controller
                              .isFavoriteModel(match.provider.id, model.id),
                          onProviderFavoriteToggle: () =>
                              _toggleProviderFavorite(match.provider.id),
                          onModelFavoriteToggle: (model) => unawaited(
                            controller.toggleFavoriteModel(
                              match.provider.id,
                              model.id,
                            ),
                          ),
                          onExpandedChanged: (expanded) => widget
                              .onExpandedChanged(match.provider.id, expanded),
                        ),
                      ),
                    ],
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
    required this.favorite,
    required this.isModelFavorite,
    required this.onProviderFavoriteToggle,
    required this.onModelFavoriteToggle,
    required this.onExpandedChanged,
    super.key,
  });

  final VideoProviderDefinition provider;
  final List<VideoModelDefinition> models;
  final bool forceExpanded;
  final bool initiallyExpanded;
  final String selectedProviderId;
  final String selectedModelId;
  final bool favorite;
  final bool Function(VideoModelDefinition model) isModelFavorite;
  final VoidCallback onProviderFavoriteToggle;
  final ValueChanged<VideoModelDefinition> onModelFavoriteToggle;
  final ValueChanged<bool> onExpandedChanged;

  @override
  State<_ProviderMenuSection> createState() => _ProviderMenuSectionState();
}

class _ProviderMenuSectionState extends State<_ProviderMenuSection> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  void didUpdateWidget(covariant _ProviderMenuSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The host changes this while the menu is open (starring a provider
    // opens it), so follow the change instead of freezing the first value.
    if (widget.initiallyExpanded != oldWidget.initiallyExpanded) {
      _expanded = widget.initiallyExpanded;
    }
  }

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
                  _FavoriteStar(
                    key: ValueKey('provider-favorite-${widget.provider.id}'),
                    starred: widget.favorite,
                    subject: widget.provider.name,
                    onPressed: widget.onProviderFavoriteToggle,
                  ),
                  const SizedBox(width: 2),
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
                        padding: const EdgeInsets.fromLTRB(24, 6, 10, 6),
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
                            const SizedBox(width: 4),
                            _FavoriteStar(
                              key: ValueKey(
                                'provider-model-star-${widget.provider.id}-${model.id}',
                              ),
                              starred: widget.isModelFavorite(model),
                              subject: model.label,
                              onPressed: () =>
                                  widget.onModelFavoriteToggle(model),
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

/// The starred models pinned above the provider sections of the picker.
class _FavoriteModelsSection extends StatelessWidget {
  const _FavoriteModelsSection({
    required this.favorites,
    required this.selectedProviderId,
    required this.selectedModelId,
    required this.onUnstar,
    super.key,
  });

  final List<FavoriteModel> favorites;
  final String selectedProviderId;
  final String selectedModelId;
  final ValueChanged<FavoriteModel> onUnstar;

  @override
  Widget build(BuildContext context) {
    final headingBackground = Theme.of(context).brightness == Brightness.dark
        ? context.colors.surfaceContainerLowest
        : context.colors.surfaceContainerHighest;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ColoredBox(
          color: headingBackground,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 11, 12, 9),
            child: Row(
              children: <Widget>[
                Icon(Icons.star_rounded, size: 14, color: context.tokens.brass),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'FAVORITES',
                    style: TextStyle(
                      color: context.colors.onSurface,
                      fontSize: 10,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${favorites.length}',
                  style: TextStyle(
                    color: context.colors.onSurface.withValues(alpha: .72),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ),
        ...favorites.map((favorite) {
          final selected =
              favorite.provider.id == selectedProviderId &&
              favorite.model.id == selectedModelId;
          return InkWell(
            key: ValueKey(
              'provider-model-favorite-${favorite.provider.id}-${favorite.model.id}',
            ),
            onTap: () => Navigator.of(
              context,
            ).pop('${favorite.provider.id}|${favorite.model.id}'),
            child: Container(
              color: selected
                  ? context.colors.primaryContainer.withValues(alpha: .5)
                  : null,
              padding: const EdgeInsets.fromLTRB(24, 6, 10, 6),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          favorite.model.label,
                          style: TextStyle(
                            color: context.colors.onSurface,
                            fontSize: 13,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        Text(
                          favorite.provider.name,
                          style: TextStyle(
                            color: context.colors.onSurfaceVariant,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selected)
                    Icon(
                      Icons.check_rounded,
                      size: 17,
                      color: context.colors.primary,
                    ),
                  const SizedBox(width: 4),
                  _FavoriteStar(
                    starred: true,
                    subject: favorite.model.label,
                    onPressed: () => onUnstar(favorite),
                  ),
                ],
              ),
            ),
          );
        }),
        Divider(height: 1, color: context.colors.outlineVariant),
      ],
    );
  }
}

/// A compact star toggle: brass when lit, quiet outline otherwise. Brass is
/// jewelry here, never a fill.
class _FavoriteStar extends StatelessWidget {
  const _FavoriteStar({
    required this.starred,
    required this.subject,
    required this.onPressed,
    super.key,
  });

  final bool starred;
  final String subject;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: starred
        ? 'Remove $subject from favorites'
        : 'Add $subject to favorites',
    onPressed: onPressed,
    isSelected: starred,
    visualDensity: VisualDensity.compact,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 30, height: 30),
    iconSize: 17,
    selectedIcon: Icon(Icons.star_rounded, color: context.tokens.brass),
    icon: Icon(
      Icons.star_border_rounded,
      color: context.colors.onSurface.withValues(alpha: .45),
    ),
  );
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

  Future<void> _copyPrompt() async {
    await Clipboard.setData(ClipboardData(text: controller.form.prompt));
    if (!mounted) return;
    controller.showNotice('Prompt copied to the clipboard.');
  }

  Future<void> _confirmClearPrompt() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear the prompt?'),
        content: const Text(
          'This removes the direction text. Attached frames, references, '
          'and settings stay.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('prompt-clear-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clear prompt'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    controller.updateForm((form) => form.prompt = '');
    // CreateScreen is also used without an AnimatedBuilder in focused widget
    // tests and development harnesses; refresh the inline editor directly.
    setState(() {});
  }

  Future<void> _showFullscreenPrompt({required bool upscaling}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: .58),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, _, _) =>
          _FullscreenPromptEditor(controller: controller, upscaling: upscaling),
      transitionBuilder: (context, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
    );
    // CreateScreen is also used without an AnimatedBuilder in focused widget
    // tests and development harnesses. Refresh the inline editor after the
    // modal closes so it always reflects the text entered there.
    if (mounted) setState(() {});
  }

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
    // Enhancing needs a saved draft to pick from; on a fresh studio the link
    // would only open an empty picker.
    final draftAction =
        controller.selectedModel.modes.contains(VideoMode.draftEnhance) &&
            (controller.hasDraftEnhanceCandidates || draftActive)
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
              inlineAction: IconButton(
                key: const ValueKey('prompt-clear-button'),
                tooltip: 'Clear prompt',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 26,
                  height: 26,
                ),
                iconSize: 15,
                onPressed: form.prompt.isEmpty
                    ? null
                    : () => unawaited(_confirmClearPrompt()),
                icon: const Icon(Icons.backspace_outlined),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  IconButton(
                    key: const ValueKey('prompt-rewrite-button'),
                    tooltip: 'Rewrite with AI',
                    visualDensity: VisualDensity.compact,
                    onPressed: controller.canRewriteDirection
                        ? () => unawaited(
                            showPromptRewriteDialog(
                              context,
                              controller: controller,
                            ),
                          )
                        : null,
                    icon: const Icon(Icons.auto_fix_high_rounded),
                  ),
                  _PromptCharacterCounter(controller: controller),
                  IconButton(
                    key: const ValueKey('prompt-copy-button'),
                    tooltip: 'Copy prompt to clipboard',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => unawaited(_copyPrompt()),
                    icon: const Icon(Icons.copy_rounded),
                  ),
                  IconButton(
                    key: const ValueKey('prompt-fullscreen-button'),
                    tooltip: 'Expand prompt to full screen',
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        unawaited(_showFullscreenPrompt(upscaling: upscaling)),
                    icon: const Icon(Icons.fullscreen_rounded),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 7),
            ReferencePromptField(
              key: ValueKey(
                'generation-prompt-${controller.activeComposerTabId}-'
                '${controller.formRevision}',
              ),
              prompt: form.prompt,
              formRevision: controller.formRevision,
              references: _promptReferenceOptions(controller),
              maxLength: controller.selectedModel.maxPromptCharacters,
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
              title: upscaling
                  ? 'Video to upscale'
                  : controller.selectedModel.sourceInputLabel ??
                        'Continue a video',
              description: upscaling
                  ? controller.selectedModel.sourceInputHint ??
                        'Upload an MP4 up to 20 seconds and 50 MB, at 2560×1440 or below. Hosted HTTP(S) clips also work, and source audio is preserved.'
                  : controller.selectedModel.sourceInputHint ??
                        (controller.selectedModel.maxSourceVideoSeconds == null
                            ? 'Attach an uploaded clip or a hosted provider-compatible URL.'
                            : 'Attach a clip up to ${controller.selectedModel.maxSourceVideoSeconds} seconds or use a hosted provider-compatible URL.'),
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
            if (controller
                .selectedModel
                .supportsGuidanceWithSource) ...<Widget>[
              const SizedBox(height: 14),
              _GuidanceInputsSection(
                controller: controller,
                videoAction: null,
                draftAction: null,
              ),
            ] else if (form.keyframes.isNotEmpty) ...<Widget>[
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
            // Guidance accordions and the settings column pair up side by
            // side at desktop widths; the settings block below is then owned
            // by this pairing instead of the full-width fallback.
            _GuidanceAndSettings(
              controller: controller,
              videoAction: videoAction,
              draftAction: draftAction,
            ),
          if (upscaling || enhancing || draftActive || videoActive) ...<Widget>[
            SizedBox(height: short ? 8 : 14),
            Divider(height: 1, color: context.colors.outlineVariant),
            SizedBox(height: short ? 8 : 14),
            if (upscaling)
              _UpscaleSettings(controller: controller)
            else if (enhancing)
              _EnhanceSettings(controller: controller)
            else
              _SettingsGrid(controller: controller),
          ],
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

class _FullscreenPromptEditor extends StatelessWidget {
  const _FullscreenPromptEditor({
    required this.controller,
    required this.upscaling,
  });

  final AppController controller;
  final bool upscaling;

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = MediaQuery.sizeOf(context).width < 620
        ? 14.0
        : 24.0;
    // The barrier is deliberately not dismissible (a stray click must not
    // lose the editor mid-thought), but Escape is an explicit request.
    return Actions(
      actions: <Type, Action<Intent>>{
        DismissIntent: CallbackAction<DismissIntent>(
          onInvoke: (_) {
            Navigator.of(context).pop();
            return null;
          },
        ),
      },
      child: Material(
        key: const ValueKey('prompt-fullscreen-editor'),
        type: MaterialType.transparency,
        child: AppBackdrop(
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  12,
                  horizontalPadding,
                  16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    FieldLabel(
                      upscaling ? 'Detail guidance · optional' : 'Direction',
                      icon: Icons.edit_note_rounded,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          _PromptCharacterCounter(controller: controller),
                          IconButton(
                            key: const ValueKey('prompt-fullscreen-minimize'),
                            tooltip: 'Minimize prompt',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.fullscreen_exit_rounded),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ReferencePromptField(
                        key: ValueKey(
                          'generation-prompt-fullscreen-'
                          '${controller.formRevision}',
                        ),
                        prompt: controller.form.prompt,
                        formRevision: controller.formRevision,
                        references: _promptReferenceOptions(controller),
                        expands: true,
                        autofocus: true,
                        maxLength: controller.selectedModel.maxPromptCharacters,
                        onChanged: (value) => controller.updateForm(
                          (form) => form.prompt = value,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PromptCharacterCounter extends StatelessWidget {
  const _PromptCharacterCounter({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final model = controller.selectedModel;
      final limit = model.maxPromptCharacters;
      final typed = controller.form.prompt.length;
      final nearLimit = limit != null && typed >= limit * .95;
      return Tooltip(
        message: limit == null
            ? '${model.label} does not publish a prompt limit'
            : '${model.label} accepts up to $limit characters',
        child: Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text(
            limit == null ? '$typed' : '$typed / $limit',
            key: const ValueKey('prompt-character-limit'),
            style: TextStyle(
              color: nearLimit
                  ? context.colors.error
                  : context.colors.onSurfaceVariant,
              fontSize: 10.5,
              fontWeight: nearLimit ? FontWeight.w700 : FontWeight.w500,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ),
      );
    },
  );
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

List<PromptReferenceOption> _promptReferenceOptions(AppController controller) {
  final references = controller.form.references;
  final mentions = controller.formPromptReferenceMentions;
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

/// Pairs the guidance accordions with the Frame/Finish/Duration settings
/// column: side by side at desktop widths, stacked with a divider between
/// them on narrow layouts.
class _GuidanceAndSettings extends StatelessWidget {
  const _GuidanceAndSettings({
    required this.controller,
    this.videoAction,
    this.draftAction,
  });

  final AppController controller;
  final Widget? videoAction;
  final Widget? draftAction;

  @override
  Widget build(BuildContext context) {
    final short = _isShort(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final guidance = _GuidanceInputsSection(
          controller: controller,
          videoAction: videoAction,
          draftAction: draftAction,
        );
        final settings = _SettingsGrid(controller: controller);
        if (constraints.maxWidth >= 880) {
          return Row(
            key: const ValueKey('guidance-settings-row'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: guidance),
              const SizedBox(width: 26),
              Expanded(child: settings),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            guidance,
            SizedBox(height: short ? 8 : 14),
            Divider(height: 1, color: context.colors.outlineVariant),
            SizedBox(height: short ? 8 : 14),
            settings,
          ],
        );
      },
    );
  }
}

class _GuidanceInputsSection extends StatefulWidget {
  const _GuidanceInputsSection({
    required this.controller,
    this.videoAction,
    this.draftAction,
  });

  final AppController controller;
  final Widget? videoAction;
  final Widget? draftAction;

  @override
  State<_GuidanceInputsSection> createState() => _GuidanceInputsSectionState();
}

class _GuidanceInputsSectionState extends State<_GuidanceInputsSection> {
  bool _framesOpen = false;
  bool _referencesOpen = false;
  late int _lastFrameCount;
  late int _lastReferenceCount;

  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    // Attachments already on the form (a restored draft) show as collapsed
    // header previews; only media arriving after this point auto-opens.
    _lastFrameCount = controller.form.keyframes.length;
    _lastReferenceCount = controller.form.references.length;
  }

  @override
  Widget build(BuildContext context) {
    final model = controller.selectedModel;
    final form = controller.form;
    // Media arriving through any path (picker, URL add, drop, reuse) reveals
    // its section so the new tiles are in view.
    if (form.keyframes.length > _lastFrameCount) _framesOpen = true;
    if (form.references.length > _lastReferenceCount) _referencesOpen = true;
    _lastFrameCount = form.keyframes.length;
    _lastReferenceCount = form.references.length;
    final showFrames =
        controller.keyframeLimit > 0 || form.keyframes.isNotEmpty;
    final showReferences = model.supportsMediaReferences;
    final actions = <Widget>[
      if (widget.videoAction != null) widget.videoAction!,
      if (widget.draftAction != null) widget.draftAction!,
    ];
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
          if (actions.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Wrap(spacing: 4, children: actions),
          ],
        ],
      );
    }
    final conflicted =
        model.framesExclusiveWithReferences &&
        form.keyframes.isNotEmpty &&
        form.references.isNotEmpty;
    final framesSetAside = controller.framesBlockedByReferences;
    final referencesSetAside = controller.referencesBlockedByFrames;
    // A conflicted form (via reuse or a model switch) keeps both sections
    // open so the madder warning and the tiles to remove stay in view; an
    // in-flight upload keeps its progress line and loading tiles visible.
    final framesExpanded =
        _framesOpen || conflicted || controller.pendingFrameAdds > 0;
    final referencesExpanded =
        _referencesOpen ||
        conflicted ||
        controller.referenceUploadInProgress ||
        controller.pendingReferenceAdds > 0;
    final frames = !showFrames
        ? null
        : _GuidanceAccordion(
            toggleKey: const ValueKey('keyframes-accordion-toggle'),
            icon: Icons.collections_rounded,
            label: 'Keyframes',
            expanded: framesExpanded,
            onToggle: () => setState(() => _framesOpen = !framesExpanded),
            previews: _framePreviews(form.keyframes),
            summary: conflicted
                ? 'Remove one side'
                : framesSetAside
                ? 'Set aside'
                : form.keyframes.isEmpty
                ? 'None'
                : '${form.keyframes.length} attached',
            error: conflicted,
            child: _FramesSection(controller: controller),
          );
    final references = !showReferences
        ? null
        // The whole accordion is a drop target, so local files land as
        // references without touching the pickers — and the section opens
        // to show what arrived. Files sort into image/video/audio by MIME
        // type or extension inside the controller.
        : ReferenceDropZone(
            enabled: !referencesSetAside,
            label: 'Drop to add references',
            // Loading tiles hold the dropped files' spots while their bytes
            // are read, before the controller can classify and attach them.
            onDropStarted: (count) {
              setState(() => _referencesOpen = true);
              controller.noteIncomingDroppedFiles(count);
            },
            onDropFiles: controller.addDroppedReferenceFiles,
            child: _GuidanceAccordion(
              key: const ValueKey('media-references-section'),
              toggleKey: const ValueKey('references-accordion-toggle'),
              icon: Icons.perm_media_rounded,
              label: 'References',
              expanded: referencesExpanded,
              onToggle: () =>
                  setState(() => _referencesOpen = !referencesExpanded),
              previews: _referencePreviews(form.references),
              summary: conflicted
                  ? 'Remove one side'
                  : referencesSetAside
                  ? 'Set aside'
                  : form.references.isEmpty
                  ? 'None'
                  : '${form.references.length} attached',
              error: conflicted,
              child: _ReferencesSection(controller: controller),
            ),
          );
    final hasVisualReference =
        form.keyframes.isNotEmpty ||
        form.referenceCount(MediaReferenceKind.image) > 0 ||
        form.referenceCount(MediaReferenceKind.video) > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (frames != null) frames,
        if (frames != null && references != null) const SizedBox(height: 10),
        if (references != null) references,
        // Normalization converts both keyframes and creative references, so
        // the switch sits below the pair instead of inside either section.
        if (hasVisualReference) ...<Widget>[
          const SizedBox(height: 8),
          _ReferenceNormalizationToggle(controller: controller),
        ],
        if (actions.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          Wrap(spacing: 4, children: actions),
        ],
      ],
    );
  }

  List<Widget> _framePreviews(List<KeyframeDraft> frames) => _cappedPreviews(
    frames
        .map(
          (frame) => _AccordionPreviewThumb(
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
        )
        .toList(),
    frames.length,
  );

  List<Widget> _referencePreviews(List<MediaReferenceDraft> references) =>
      _cappedPreviews(
        references
            .map(
              (reference) => _AccordionPreviewThumb(
                child: reference.kind == MediaReferenceKind.audio
                    ? Icon(
                        Icons.graphic_eq_rounded,
                        size: 13,
                        color: context.colors.onSurfaceVariant,
                      )
                    : MediaThumbnail(
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
                        semanticsLabel: '${reference.label} preview',
                      ),
              ),
            )
            .toList(),
        references.length,
      );

  /// At most four thumbnails plus a "+n" spillover chip keep the header row
  /// legible at any width.
  List<Widget> _cappedPreviews(List<Widget> thumbs, int total) {
    const cap = 4;
    if (total <= cap) return thumbs;
    return <Widget>[
      ...thumbs.take(cap),
      _AccordionPreviewThumb(
        child: Center(
          child: Text(
            '+${total - cap}',
            style: TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w700,
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    ];
  }
}

/// One collapsible guidance section: the header row carries the section
/// label, tiny previews of what is attached, and a status word; the full
/// editing surface (tiles, gauges, add buttons) lives in the body.
class _GuidanceAccordion extends StatelessWidget {
  const _GuidanceAccordion({
    required this.toggleKey,
    required this.icon,
    required this.label,
    required this.expanded,
    required this.onToggle,
    required this.child,
    this.previews = const <Widget>[],
    this.summary,
    this.error = false,
    super.key,
  });

  final Key toggleKey;
  final IconData icon;
  final String label;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;
  final List<Widget> previews;
  final String? summary;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final summaryText = summary == null
        ? null
        : Text(
            summary!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: error ? colors.error : colors.onSurfaceVariant,
            ),
          );
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: error ? colors.error : colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            key: toggleKey,
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              child: Row(
                children: <Widget>[
                  Icon(icon, size: 15, color: context.tokens.brass),
                  const SizedBox(width: 7),
                  Text(
                    label.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10.5,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface.withValues(alpha: .82),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: previews.isEmpty
                        ? Align(
                            alignment: Alignment.centerRight,
                            child: summaryText ?? const SizedBox.shrink(),
                          )
                        : SizedBox(
                            height: 24,
                            child: Row(
                              children: <Widget>[
                                Expanded(
                                  // A scrollable strip never overflows the
                                  // header, whatever the column width.
                                  child: ListView(
                                    scrollDirection: Axis.horizontal,
                                    padding: EdgeInsets.zero,
                                    children: previews,
                                  ),
                                ),
                                if (summaryText != null) ...<Widget>[
                                  const SizedBox(width: 8),
                                  summaryText,
                                ],
                              ],
                            ),
                          ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: expanded ? .5 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: Icon(
                      Icons.expand_more_rounded,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: !expanded
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(11, 2, 11, 11),
                    child: child,
                  ),
          ),
        ],
      ),
    );
  }
}

/// A tiny rounded thumbnail in an accordion header.
class _AccordionPreviewThumb extends StatelessWidget {
  const _AccordionPreviewThumb({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: 24,
    height: 24,
    margin: const EdgeInsets.only(right: 4),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: context.colors.surfaceContainer,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: context.colors.outlineVariant),
    ),
    child: child,
  );
}

/// The one explanation a new studio needs: renders run on the person's own
/// provider accounts. Shown in place of the screen description until a key
/// (or a working on-device provider) exists, then it simply disappears. It
/// is a single sentence with an inline link — never a button row — so it
/// occupies exactly the description's height and the composer keeps its
/// place above the fold.
class _FirstRunGuidance extends StatefulWidget {
  const _FirstRunGuidance({required this.controller});

  final AppController controller;

  @override
  State<_FirstRunGuidance> createState() => _FirstRunGuidanceState();
}

class _FirstRunGuidanceState extends State<_FirstRunGuidance> {
  late final TapGestureRecognizer _openProviders = TapGestureRecognizer()
    ..onTap = () => unawaited(widget.controller.navigate(AppSection.providers));

  @override
  void dispose() {
    _openProviders.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      style: TextStyle(color: context.colors.onSurfaceVariant),
      children: <InlineSpan>[
        const TextSpan(
          text:
              'Renders run on your own provider accounts — add an API key in ',
        ),
        TextSpan(
          text: 'Providers',
          recognizer: _openProviders,
          semanticsLabel: 'Open Providers',
          style: TextStyle(
            color: context.colors.primary,
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.underline,
            decorationColor: context.colors.primary,
          ),
        ),
        const TextSpan(
          text:
              ' to begin. Apple Intelligence runs with no key on a supported '
              'iPhone or iPad.',
        ),
      ],
    ),
    key: const ValueKey<String>('first-run-guidance'),
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
  );
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
  const FieldLabel(
    this.label, {
    required this.icon,
    super.key,
    this.inlineAction,
    this.trailing,
  });

  final String label;
  final IconData icon;

  /// A small control that hugs the label text (e.g. clear-prompt), unlike
  /// [trailing], which sits at the far end of the row.
  final Widget? inlineAction;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        letterSpacing: 1.3,
        fontWeight: FontWeight.w700,
        color: context.colors.onSurface.withValues(alpha: .82),
      ),
    );
    return Row(
      children: <Widget>[
        Icon(icon, size: 16, color: context.tokens.brass),
        const SizedBox(width: 8),
        Expanded(
          child: inlineAction == null
              ? text
              : Row(
                  children: <Widget>[
                    Flexible(child: text),
                    const SizedBox(width: 4),
                    inlineAction!,
                  ],
                ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _FramesSection extends StatelessWidget {
  const _FramesSection({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final form = controller.form;
    final model = controller.selectedModel;
    final maximumFrames = controller.keyframeLimit;
    final setAside = controller.framesBlockedByReferences;
    final conflicted =
        model.framesExclusiveWithReferences &&
        form.keyframes.isNotEmpty &&
        form.references.isNotEmpty;
    final frameLimit = model.supportsTimedKeyframes
        ? '$maximumFrames frames max · custom timing available'
        : model.supportsEndFrame
        ? '$maximumFrames frames max · first + last · pinned by the provider'
        : '1 first frame max · pins frame 0';
    final exclusiveInputs = maximumFrames == 1
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
    final pendingAdds = controller.pendingFrameAdds;
    final tiles = form.keyframes.isEmpty && pendingAdds == 0
        ? null
        : Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              ...form.keyframes.asMap().entries.map(
                (entry) => _FrameTile(
                  controller: controller,
                  index: entry.key,
                  frame: entry.value,
                ),
              ),
              for (var index = 0; index < pendingAdds; index += 1)
                _PendingGuidanceTile(
                  key: ValueKey('pending-frame-tile-$index'),
                ),
            ],
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          caption,
          style: TextStyle(
            color: conflicted
                ? context.colors.error
                : context.colors.onSurfaceVariant,
            fontSize: 11,
            height: 1.4,
          ),
        ),
        if (tiles != null) ...<Widget>[const SizedBox(height: 10), tiles],
        if (addButtons.isNotEmpty || timingPill != null) ...<Widget>[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              ...addButtons,
              if (timingPill != null) timingPill,
            ],
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
        .where((kind) => controller.referenceLimit(kind) > 0)
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
          final minimum = kind == MediaReferenceKind.audio
              ? model.minReferenceAudioSeconds
              : null;
          final duration = seconds == null
              ? ''
              : minimum != null && maximum == 1
              ? ' ($minimum–${seconds}s)'
              : minimum != null
              ? ' (${minimum}s min each · ${seconds}s total)'
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
    final pendingAdds = controller.pendingReferenceAdds;
    final tiles = form.references.isEmpty && pendingAdds == 0
        ? null
        : Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              ...form.references.map(
                (reference) => _ReferenceTile(
                  controller: controller,
                  reference: reference,
                ),
              ),
              for (var index = 0; index < pendingAdds; index += 1)
                _PendingGuidanceTile(
                  key: ValueKey('pending-reference-tile-$index'),
                ),
            ],
          );
    final addButtons = setAside
        ? const <Widget>[]
        : MediaReferenceKind.values
              .where(
                (kind) =>
                    controller.referenceLimit(kind) > 0 ||
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (taskChips != null) ...<Widget>[
          taskChips,
          const SizedBox(height: 7),
        ],
        Text(
          limitSummary,
          style: TextStyle(
            color: context.colors.onSurfaceVariant,
            fontSize: 11,
            height: 1.4,
          ),
        ),
        if (!setAside) ...<Widget>[
          const SizedBox(height: 10),
          _ReferenceCapacityGauges(controller: controller),
        ],
        for (final note in notes) ...<Widget>[
          const SizedBox(height: 5),
          Text(note, style: noteStyle),
        ],
        ReferenceUploadIndicator(controller: controller),
        if (tiles != null) ...<Widget>[const SizedBox(height: 10), tiles],
        if (addButtons.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: addButtons,
          ),
        ],
      ],
    );
  }
}

class _ReferenceCapacityGauges extends StatelessWidget {
  const _ReferenceCapacityGauges({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final form = controller.form;
    final model = controller.selectedModel;
    final gauges = <Widget>[];
    final totalMaximum = model.maxTotalReferences;
    if (totalMaximum != null &&
        totalMaximum > 0 &&
        form.references.isNotEmpty) {
      gauges.add(
        _ReferenceCapacityGauge(
          key: const ValueKey('reference-capacity-total'),
          label: 'All references',
          value: form.references.length / totalMaximum,
          valueLabel: '${form.references.length} / $totalMaximum added',
        ),
      );
    }
    for (final kind in MediaReferenceKind.values) {
      final maximum = controller.referenceLimit(kind);
      if (maximum <= 0) continue;
      final attached = form.references
          .where((reference) => reference.kind == kind)
          .toList();
      // Gauges appear once a reference of this kind is attached; until then
      // the summary line above already states the limits.
      if (attached.isEmpty) continue;
      final kindLabel = switch (kind) {
        MediaReferenceKind.image => 'Images',
        MediaReferenceKind.video => 'Videos',
        MediaReferenceKind.audio => 'Audio clips',
      };
      gauges.add(
        _ReferenceCapacityGauge(
          key: ValueKey('reference-capacity-${kind.name}-count'),
          label: kindLabel,
          value: attached.length / maximum,
          valueLabel: '${attached.length} / $maximum added',
        ),
      );
      final maximumSeconds = model.maxReferenceSeconds(kind, form.resolution);
      if (maximumSeconds == null) continue;
      final known = attached
          .map((reference) => reference.durationSeconds)
          .whereType<double>()
          .toList();
      final used = known.fold<double>(0, (sum, seconds) => sum + seconds);
      final unknown = attached.length - known.length;
      gauges.add(
        _ReferenceCapacityGauge(
          key: ValueKey('reference-capacity-${kind.name}-duration'),
          label: '$kindLabel duration',
          value: used / maximumSeconds,
          valueLabel:
              '${formatMediaDuration(used)} / ${formatMediaDuration(maximumSeconds.toDouble())}'
              '${unknown == 0 ? '' : ' · measuring $unknown'}',
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: gauges
          .map(
            (gauge) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: gauge,
            ),
          )
          .toList(),
    );
  }
}

class _ReferenceCapacityGauge extends StatelessWidget {
  const _ReferenceCapacityGauge({
    required this.label,
    required this.value,
    required this.valueLabel,
    super.key,
  });

  final String label;
  final double value;
  final String valueLabel;

  @override
  Widget build(BuildContext context) {
    final progress = value.isFinite ? value.clamp(0.0, 1.0) : 0.0;
    return Semantics(
      label: '$label, $valueLabel',
      value: '${(progress * 100).round()}%',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                valueLabel,
                style: TextStyle(
                  color: context.colors.onSurfaceVariant,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Directionality(
            textDirection: TextDirection.ltr,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                minHeight: 7,
                value: progress,
                backgroundColor: context.colors.surfaceContainerHighest,
              ),
            ),
          ),
        ],
      ),
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

/// Holds the spot where a picked or dropped file's card will land: the same
/// footprint as a reference/frame tile with a spinner in the thumb zone,
/// shown while files are chosen, read, or retained.
class _PendingGuidanceTile extends StatelessWidget {
  const _PendingGuidanceTile({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
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
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 76,
              color: dark
                  ? ClawnsoleColors.plumInk
                  : context.colors.surfaceContainer,
              child: const Center(
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Uploading…',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10.5,
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferenceTile extends StatelessWidget {
  const _ReferenceTile({required this.controller, required this.reference});

  final AppController controller;
  final MediaReferenceDraft reference;

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
                      onVideoMetadata:
                          reference.kind == MediaReferenceKind.video
                          ? (metadata) =>
                                controller.rememberReferenceVideoMetadata(
                                  reference.id,
                                  metadata,
                                )
                          : null,
                      onMediaDuration:
                          reference.kind == MediaReferenceKind.audio
                          ? (seconds) => controller.rememberReferenceDuration(
                              reference.id,
                              seconds,
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            ),
            // A draft picked from References renders immediately but loads
            // its media bytes in the background; the veil says so until the
            // real thumbnail is ready.
            if (controller.isReferenceDraftHydrating(reference.id))
              Positioned.fill(
                child: IgnorePointer(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: .3),
                      child: const Center(
                        child: SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 4,
              left: 4,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 74),
                child: Material(
                  color: ClawnsoleColors.plumInk.withValues(alpha: .82),
                  borderRadius: BorderRadius.circular(6),
                  clipBehavior: Clip.antiAlias,
                  child: Tooltip(
                    message: 'Rename prompt reference',
                    child: InkWell(
                      key: ValueKey('rename-media-reference-${reference.id}'),
                      onTap: () => unawaited(
                        _showDraftReferenceRenameDialog(
                          context,
                          controller,
                          reference,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2.5,
                        ),
                        child: Text(
                          '@${controller.referencePromptName(reference)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: ClawnsoleColors.cream,
                            fontSize: 8,
                            letterSpacing: .5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
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
          reference.durationSeconds == null
              ? reference.label
              : '${reference.label} · ${formatMediaDuration(reference.durationSeconds!)}',
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

Future<void> _showDraftReferenceRenameDialog(
  BuildContext context,
  AppController controller,
  MediaReferenceDraft reference,
) => showDialog<void>(
  context: context,
  builder: (context) =>
      _DraftReferenceRenameDialog(controller: controller, reference: reference),
);

class _DraftReferenceRenameDialog extends StatefulWidget {
  const _DraftReferenceRenameDialog({
    required this.controller,
    required this.reference,
  });

  final AppController controller;
  final MediaReferenceDraft reference;

  @override
  State<_DraftReferenceRenameDialog> createState() =>
      _DraftReferenceRenameDialogState();
}

class _DraftReferenceRenameDialogState
    extends State<_DraftReferenceRenameDialog> {
  late final TextEditingController _name;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.controller.referencePromptName(widget.reference),
    );
  }

  Future<void> _save() async {
    final currentName = widget.controller.referencePromptName(widget.reference);
    final clean = _name.text.trim();
    final problem = clean == currentName
        ? null
        : widget.controller.referenceNameProblem(
            clean,
            excludeDraftId: widget.reference.id,
            excludeSavedReferenceId: widget.reference.savedReferenceId,
          );
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() => _saving = true);
    final renamed = await widget.controller.renameDraftReference(
      widget.reference.id,
      clean,
    );
    if (!mounted) return;
    if (renamed) {
      Navigator.pop(context);
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename prompt reference'),
    content: TextField(
      key: const ValueKey('prompt-reference-name-field'),
      controller: _name,
      autofocus: true,
      maxLength: 80,
      onChanged: (_) {
        if (_error != null) setState(() => _error = null);
      },
      onSubmitted: _saving ? null : (_) => unawaited(_save()),
      decoration: InputDecoration(
        labelText: 'Name',
        prefixText: '@',
        errorText: _error,
        helperText:
            'Names must be unique. Image 1, Video 1, and Audio 1 are reserved.',
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('save-prompt-reference-name'),
        onPressed: _saving ? null : _save,
        child: _saving
            ? const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Rename'),
      ),
    ],
  );
}

class _AddReferenceButton extends StatelessWidget {
  const _AddReferenceButton({required this.controller, required this.kind});

  final AppController controller;
  final MediaReferenceKind kind;

  @override
  Widget build(BuildContext context) {
    // Uploads never lock the buttons: adds append instantly and persistence
    // continues on the controller's background work queue.
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
      KeyframeRole.start => 'First',
      KeyframeRole.middle => 'Middle',
      KeyframeRole.end => 'Last',
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

/// Frame, Finish, Duration, and the remaining finishing controls in one
/// column: the two console-key dropdowns share a row (so phones stop
/// spending a full row on each), and everything else stacks beneath.
class _SettingsGrid extends StatelessWidget {
  const _SettingsGrid({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final pairDropdowns = constraints.maxWidth >= 330;
      final frame = <Widget>[
        const FieldLabel('Frame', icon: Icons.crop_rounded),
        const SizedBox(height: 6),
        _RatioDropdown(controller: controller),
      ];
      final finish = <Widget>[
        const FieldLabel('Finish', icon: Icons.high_quality_rounded),
        const SizedBox(height: 6),
        _ResolutionDropdown(controller: controller),
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (pairDropdowns)
            Row(
              key: const ValueKey('frame-finish-row'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: frame,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: finish,
                  ),
                ),
              ],
            )
          else ...<Widget>[...frame, const SizedBox(height: 12), ...finish],
          if (controller.selectedModel.outputKind ==
                  GenerationOutputKind.video &&
              !controller.selectedModel.durationComesFromSource(
                controller.form.mode,
              )) ...<Widget>[
            const SizedBox(height: 12),
            _DurationControl(controller: controller),
          ],
          if (controller.selectedModel.outputKind ==
                  GenerationOutputKind.video &&
              controller.selectedModel.supportsFrameRate) ...<Widget>[
            const SizedBox(height: 10),
            _FrameRateControl(controller: controller),
          ],
          if (controller.selectedModel.supportsAudio) ...<Widget>[
            const SizedBox(height: 8),
            HardwareSwitchTile(
              title: 'Synchronized audio',
              subtitle: 'Dialogue, ambience, and sound',
              value: controller.form.generateAudio,
              onChanged: controller.selectedModel.supportsAudio
                  ? controller.setGenerateAudio
                  : null,
            ),
          ],
          if (controller.selectedModel.supportsDraft) ...<Widget>[
            const SizedBox(height: 4),
            HardwareSwitchTile(
              title: 'Fast draft',
              subtitle: 'HD preview now, enhance later',
              value: controller.form.draft,
              onChanged: (value) =>
                  controller.updateForm((form) => form.draft = value),
            ),
          ],
          if (controller.selectedProviderId == 'bfl') ...<Widget>[
            const SizedBox(height: 10),
            _SafetyControl(controller: controller),
          ],
          if (controller.selectedModel.supportsSeed) ...<Widget>[
            const SizedBox(height: 12),
            const FieldLabel('Seed', icon: Icons.tag_rounded),
            const SizedBox(height: 6),
            _SeedControl(controller: controller),
          ],
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
  Widget build(BuildContext context) {
    if (controller.selectedModel.upscaleUsesResolutionTargets) {
      final strength = controller.form.upscaleCreativity;
      return LayoutBuilder(
        builder: (context, constraints) {
          final target = <Widget>[
            const FieldLabel(
              'Target resolution',
              icon: Icons.high_quality_rounded,
            ),
            const SizedBox(height: 8),
            _ResolutionDropdown(controller: controller),
            const SizedBox(height: 8),
            Text(
              'Aspect ratio and source audio are preserved. Runway bills each output frame.',
              style: TextStyle(
                color: context.colors.onSurfaceVariant,
                fontSize: 10.5,
              ),
            ),
          ];
          final detail = <Widget>[
            FieldLabel(
              'Creative detail',
              icon: Icons.auto_awesome_rounded,
              trailing: CounterReadout(
                '$strength',
                unit: '%',
                semanticLabel: 'Creative detail',
                unitLabel: 'percent',
              ),
            ),
            const SizedBox(height: 8),
            HardwareSlider(
              key: const ValueKey('runway-upscale-creativity-slider'),
              min: 0,
              max: 100,
              divisions: 20,
              label: '$strength%',
              semanticLabel: 'Creative detail',
              semanticFormatterCallback: (value) => '${value.round()} percent',
              value: strength.toDouble(),
              onChanged: (value) => controller.updateForm(
                (form) => form.upscaleCreativity = value.round(),
              ),
            ),
            Text(
              strength <= 25
                  ? 'Faithful restoration with restrained invented detail.'
                  : 'Higher values invent more texture and may drift from faces, text, or products.',
              style: TextStyle(
                color: context.colors.onSurfaceVariant,
                fontSize: 10.5,
              ),
            ),
          ];
          if (constraints.maxWidth <= 640) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                ...target,
                const SizedBox(height: 22),
                ...detail,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: target,
                ),
              ),
              const SizedBox(width: 26),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: detail,
                ),
              ),
            ],
          );
        },
      );
    }
    return LayoutBuilder(
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
            trailing: CounterReadout(
              factorText,
              unit: '×',
              semanticLabel: 'Upscale factor',
              unitLabel: 'times',
            ),
          ),
          const SizedBox(height: 8),
          HardwareSlider(
            key: const ValueKey('upscale-factor-slider'),
            min: 1.5,
            max: 3,
            divisions: 15,
            label: '$factorText×',
            semanticLabel: 'Upscale factor',
            semanticFormatterCallback: (value) =>
                '${value.toStringAsFixed(1)} times',
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
              semanticLabel: 'Detail mode',
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
      semanticLabel: 'Duration',
      unitLabel: form.autoDuration ? null : 'seconds',
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
            semanticLabel: 'Duration mode',
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
                semanticLabel: 'Duration',
                semanticFormatterCallback: (value) =>
                    '${value.round()} seconds',
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
          trailing: CounterReadout(
            '${controller.form.frameRate}',
            unit: 'fps',
            semanticLabel: 'Frame rate',
            unitLabel: 'frames per second',
          ),
        ),
        HardwareSlider(
          min: 1,
          max: 6,
          divisions: 5,
          label: '${controller.form.frameRate} fps',
          semanticLabel: 'Frame rate',
          semanticFormatterCallback: (value) =>
              '${value.round()} frames per second',
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
          semanticLabel: 'Safety tolerance',
          unitLabel: 'out of 4',
        ),
      ),
      HardwareSlider(
        min: 0,
        max: 4,
        divisions: 4,
        label: '${controller.form.safetyTolerance} / 4',
        semanticLabel: 'Safety tolerance',
        semanticFormatterCallback: (value) => '${value.round()} of 4',
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
          : controller.selectedModel.outputKind == GenerationOutputKind.video
          ? controller.form.durationSeconds
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
                    'Uses Apple Image Playground on this device with no provider key. Image sequences render one frame per second.',
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

Future<void> _submitWithProviderRetentionWarning(
  BuildContext context,
  AppController controller,
) async {
  if (controller.requiresProviderRetentionAcknowledgement) {
    final suppressFutureWarnings = await _showProviderRetentionWarning(
      context,
      controller.selectedProvider,
    );
    if (suppressFutureWarnings == null || !context.mounted) return;
    if (suppressFutureWarnings) {
      try {
        await controller.acknowledgeProviderRetentionRisk();
      } on Object catch (error) {
        controller.showErrorNotice(error);
        return;
      }
    }
    await controller.submit(providerRetentionRiskAcknowledged: true);
    return;
  }
  await controller.submit();
}

/// Returns whether later warnings should be suppressed, or null when canceled.
Future<bool?> _showProviderRetentionWarning(
  BuildContext context,
  VideoProviderDefinition provider,
) async {
  var understood = false;
  var suppressFutureWarnings = false;
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        icon: Icon(
          Icons.warning_amber_rounded,
          color: context.colors.error,
          size: 30,
        ),
        title: Text('Keep Clawnsole open for ${provider.name}'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'When generating with ${provider.name}, keep Clawnsole '
                  'open and active and maintain an internet connection '
                  'until Clawnsole confirms the result is saved.',
                ),
                const SizedBox(height: 12),
                Text(_providerRetentionDetail(provider)),
                const SizedBox(height: 12),
                const Text(
                  'If Clawnsole cannot retrieve the completed result in '
                  'time, you may lose access to the generation even if '
                  'the provider charged for it.',
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  key: const ValueKey('provider-retention-warning-checkbox'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: understood,
                  onChanged: (value) =>
                      setState(() => understood = value ?? false),
                  title: const Text(
                    'I understand that closing or backgrounding the app '
                    'or going offline may cause me to lose this result.',
                  ),
                ),
                CheckboxListTile(
                  key: const ValueKey(
                    'suppress-provider-retention-warning-checkbox',
                  ),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: suppressFutureWarnings,
                  onChanged: (value) =>
                      setState(() => suppressFutureWarnings = value ?? false),
                  title: Text(
                    "Don't show this warning again for ${provider.name}.",
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('accept-provider-retention-warning'),
            onPressed: understood
                ? () => Navigator.pop(dialogContext, suppressFutureWarnings)
                : null,
            child: const Text('Accept & generate'),
          ),
        ],
      ),
    ),
  );
}

String _providerRetentionDetail(VideoProviderDefinition provider) {
  final availability = provider.resultDelivery.availability;
  if (availability == null) {
    return '${provider.name} does not publish a dependable result-retention '
        'window, so later retrieval cannot be guaranteed.';
  }
  final minutes = availability.inMinutes;
  final window = minutes % (24 * 60) == 0
      ? '${minutes ~/ (24 * 60)} ${minutes == 24 * 60 ? 'day' : 'days'}'
      : minutes % 60 == 0
      ? '${minutes ~/ 60} ${minutes == 60 ? 'hour' : 'hours'}'
      : '$minutes ${minutes == 1 ? 'minute' : 'minutes'}';
  return '${provider.name} hosts completed results for only $window after '
      'completion.';
}

class _ComposerFooter extends StatelessWidget {
  const _ComposerFooter({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final form = controller.form;
    final localUnavailable =
        controller.selectedProvider.isLocal &&
        !controller.localGenerationAvailable;
    final status = Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (localUnavailable)
              Icon(
                Icons.phonelink_off_rounded,
                color: context.colors.error,
                size: 18,
              )
            else if (!controller.selectedProvider.requiresApiKey ||
                controller.hasApiKey)
              ClawMark(size: 19, color: context.tokens.brass)
            else
              Icon(
                Icons.key_off_rounded,
                color: context.colors.error,
                size: 18,
              ),
            const SizedBox(width: 9),
            if (localUnavailable)
              // The on-device provider is selected but this device cannot run
              // it; say so here rather than after a failed Generate.
              Flexible(
                child: Text(
                  'Needs iOS 18.4 and Apple Intelligence',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: context.colors.error,
                  ),
                ),
              )
            else if (!controller.selectedProvider.requiresApiKey ||
                controller.hasApiKey)
              const Flexible(
                child: Text(
                  'Ready when you are',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                ),
              )
            else
              // The status line is where a new studio looks first when
              // Generate does nothing; make it the way in, not just a verdict.
              Flexible(
                child: InkWell(
                  key: const ValueKey<String>('composer-open-providers'),
                  onTap: () =>
                      unawaited(controller.navigate(AppSection.providers)),
                  borderRadius: BorderRadius.circular(6),
                  child: Text(
                    'API key needed · Open Providers',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: context.colors.primary,
                    ),
                  ),
                ),
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
          : () => unawaited(
              _submitWithProviderRetentionWarning(context, controller),
            ),
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
    // The model plaque sits in the footer, directly before Generate: the
    // last thing the eye checks before rendering, inside the draft it
    // belongs to rather than off in the heading.
    final plaque = _ProviderPlaque(controller: controller);
    return LayoutBuilder(
      builder: (context, constraints) {
        // The plaque and the button together need real room; narrower
        // composers stack them, the plaque keeping its place just above
        // Generate.
        if (constraints.maxWidth < 640) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              status,
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerLeft, child: plaque),
              const SizedBox(height: 10),
              generate,
            ],
          );
        }
        return Row(
          children: <Widget>[
            Expanded(child: status),
            const SizedBox(width: 12),
            plaque,
            const SizedBox(width: 12),
            generate,
          ],
        );
      },
    );
  }
}

class _RecentWork extends StatefulWidget {
  const _RecentWork({
    required this.controller,
    required this.itemLimit,
    required this.onLoadMore,
  });

  final AppController controller;
  final int itemLimit;
  final VoidCallback onLoadMore;

  @override
  State<_RecentWork> createState() => _RecentWorkState();
}

class _RecentWorkState extends State<_RecentWork> {
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
                // On phones the heading has no room for the first-run line,
                // so the empty branch carries the way in.
                if (controller.needsProviderSetup) ...<Widget>[
                  const SizedBox(height: 12),
                  TextButton.icon(
                    key: const ValueKey<String>('quiet-branch-open-providers'),
                    onPressed: () =>
                        unawaited(controller.navigate(AppSection.providers)),
                    icon: const Icon(Icons.hub_rounded, size: 16),
                    label: const Text('Add a provider key to begin'),
                  ),
                ],
                const SizedBox(height: 10),
              ],
            ),
          )
        else if (controller.recentWorkViewMode == GenerationViewMode.compact)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: controller.visibleGenerations
                .take(widget.itemLimit)
                .map(
                  (item) => Padding(
                    key: ValueKey('recent-generation-${item.localId}'),
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
                    .take(widget.itemLimit)
                    .map(
                      (item) => SizedBox(
                        key: ValueKey('recent-generation-${item.localId}'),
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
        if (widget.itemLimit <
            controller.visibleGenerations.length) ...<Widget>[
          const SizedBox(height: 14),
          Center(
            child: TextButton.icon(
              key: const ValueKey('recent-work-load-more'),
              onPressed: widget.onLoadMore,
              icon: const Icon(Icons.expand_more_rounded),
              label: Text(
                'Load ${((controller.visibleGenerations.length - widget.itemLimit).clamp(0, 20))} more',
              ),
            ),
          ),
        ],
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
