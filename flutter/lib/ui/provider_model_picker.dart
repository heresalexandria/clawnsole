// The provider/model picker: one searchable list of every model the studio
// can reach, opened as a modal dialog so more than one control can reach it.
//
// The footer's console readout opens it, and so does the text trigger in the
// Direction header — the same rows, the same stars, the same memory of which
// sections are folded. It is a dialog rather than a contextual popup because
// it belongs to the screen, not to whichever control happened to summon it.

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import '../core/provider_catalog.dart';
import 'hardware.dart';
import 'panels.dart';

/// How tall a section heading stands. The picker's headings are casework
/// facings rather than tinted bars, so they carry the weight of one: room
/// for 12.5 px capitals and a star without either crowding the other.
const double _headingHeight = 50;

/// The favorites section's key in the veneer run. Not a provider id, and
/// no provider id can look like it.
const String _favoritesSliceKey = '#favorites';

/// Which provider sections this studio has folded away, remembered for the
/// life of the controller so both triggers open the list as the user left it.
///
/// Keyed on the controller rather than held statically: a widget test builds
/// a fresh studio per case and must not inherit the previous one's folds.
final Expando<Set<String>> _collapsedProviders = Expando<Set<String>>(
  'provider-model-picker collapsed sections',
);

/// Seeded on first open: every provider is folded except the one in use and
/// the starred ones, which are pinned for quick reach.
Set<String> _collapsedFor(AppController controller) =>
    _collapsedProviders[controller] ??= <String>{
      for (final provider in controller.providers)
        if (provider.id != controller.selectedProviderId &&
            !controller.isFavoriteProvider(provider.id))
          provider.id,
    };

/// Opens the shared provider/model picker as a modal dialog over [context].
///
/// The chosen model is applied through [AppController.selectProviderModel]
/// before the future completes; dismissing without a choice changes nothing.
///
/// A caller choosing a model for something other than the open draft — the
/// Defaults desk picks the model new drafts start on — passes [onSelected] to
/// take the choice itself, and [selectedProviderId] / [selectedModelId] so the
/// list ticks the model it is actually choosing for.
Future<void> showProviderModelPicker(
  BuildContext context,
  AppController controller, {
  Future<void> Function(String providerId, String modelId)? onSelected,
  String? selectedProviderId,
  String? selectedModelId,
}) async {
  final choice = await showDialog<String>(
    context: context,
    builder: (context) => _ProviderModelPickerDialog(
      key: const ValueKey<String>('provider-model-picker'),
      controller: controller,
      selectedProviderId: selectedProviderId,
      selectedModelId: selectedModelId,
    ),
  );
  if (choice == null) return;
  final divider = choice.indexOf('|');
  final provider = choice.substring(0, divider);
  final model = choice.substring(divider + 1);
  // A provider the director just picked from stays open next time.
  _collapsedFor(controller).remove(provider);
  await (onSelected == null
      ? controller.selectProviderModel(provider, model)
      : onSelected(provider, model));
}

/// The dialog shell: the theme's dialog surface, sized to the room, with the
/// search field standing in for a title bar.
class _ProviderModelPickerDialog extends StatelessWidget {
  const _ProviderModelPickerDialog({
    required this.controller,
    super.key,
    this.selectedProviderId,
    this.selectedModelId,
  });

  final AppController controller;

  /// The model to tick, when it is not the open draft's.
  final String? selectedProviderId;
  final String? selectedModelId;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Narrow rooms give the list the whole width less a modest inset; wider
    // ones hold it to a column that reads in one glance.
    final narrow = size.width < 520;
    final height = (size.height * .72).clamp(320.0, 600.0);
    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: narrow
          ? const EdgeInsets.symmetric(horizontal: 16, vertical: 24)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      child: SizedBox(
        width: narrow ? double.infinity : 420,
        height: height,
        child: _ProviderSearchMenu(
          controller: controller,
          selectedProviderId: selectedProviderId,
          selectedModelId: selectedModelId,
        ),
      ),
    );
  }
}

/// The picker's body: the search field, then the scrolling list of favorites
/// and provider sections.
class _ProviderSearchMenu extends StatefulWidget {
  const _ProviderSearchMenu({
    required this.controller,
    this.selectedProviderId,
    this.selectedModelId,
  });

  final AppController controller;
  final String? selectedProviderId;
  final String? selectedModelId;

  @override
  State<_ProviderSearchMenu> createState() => _ProviderSearchMenuState();
}

class _ProviderSearchMenuState extends State<_ProviderSearchMenu> {
  final TextEditingController _search = TextEditingController();

  Set<String> get _collapsedProviders => _collapsedFor(widget.controller);

  String get _selectedProviderId =>
      widget.selectedProviderId ?? widget.controller.selectedProviderId;
  String get _selectedModelId =>
      widget.selectedModelId ?? widget.controller.selectedModel.id;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _setExpanded(String providerId, bool expanded) {
    if (expanded) {
      _collapsedProviders.remove(providerId);
    } else {
      _collapsedProviders.add(providerId);
    }
  }

  void _toggleProviderFavorite(String providerId) {
    // A freshly starred provider opens so its models are in reach at once.
    if (!widget.controller.isFavoriteProvider(providerId)) {
      _setExpanded(providerId, true);
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
    // The headings are burlwood facings, cut in the order they are laid so
    // that no two touching ones come off the same part of the sheet.
    final sliceKeys = <String>[
      if (favorites.isNotEmpty) _favoritesSliceKey,
      for (final match in matches) match.provider.id,
    ];
    final cuts = <String, BurlwoodCut>{
      for (final (index, cut) in BurlwoodCut.run(sliceKeys).indexed)
        sliceKeys[index]: cut,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 6, 10),
          // The search field is the header — no title bar over it. The
          // close key beside it is for the platforms with no Escape.
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: const ValueKey('provider-model-search'),
                  controller: _search,
                  // Desktop lands in the field ready to type; a phone would
                  // only bury the list under its keyboard.
                  autofocus: !isHardwareTouchPlatform,
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
              IconButton(
                key: const ValueKey('provider-model-picker-close'),
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
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
                      style: TextStyle(color: context.colors.onSurfaceVariant),
                    ),
                  ),
                )
              : ListView(
                  padding: EdgeInsets.zero,
                  children: <Widget>[
                    if (favorites.isNotEmpty)
                      _FavoriteModelsSection(
                        key: const ValueKey('provider-model-favorites'),
                        cut: cuts[_favoritesSliceKey]!,
                        favorites: favorites,
                        selectedProviderId: _selectedProviderId,
                        selectedModelId: _selectedModelId,
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
                        cut: cuts[match.provider.id]!,
                        provider: match.provider,
                        models: match.models,
                        forceExpanded: query.isNotEmpty,
                        initiallyExpanded: !_collapsedProviders.contains(
                          match.provider.id,
                        ),
                        selectedProviderId: _selectedProviderId,
                        selectedModelId: _selectedModelId,
                        favorite: controller.isFavoriteProvider(
                          match.provider.id,
                        ),
                        isModelFavorite: (model) => controller.isFavoriteModel(
                          match.provider.id,
                          model.id,
                        ),
                        onProviderFavoriteToggle: () =>
                            _toggleProviderFavorite(match.provider.id),
                        onModelFavoriteToggle: (model) => unawaited(
                          controller.toggleFavoriteModel(
                            match.provider.id,
                            model.id,
                          ),
                        ),
                        onExpandedChanged: (expanded) =>
                            _setExpanded(match.provider.id, expanded),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _ProviderMenuSection extends StatefulWidget {
  const _ProviderMenuSection({
    required this.cut,
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

  /// Which patch of the burl sheet this heading is faced with.
  final BurlwoodCut cut;
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
    final ink = PanelSurface.burlwood.ink(context.tokens);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        BurlwoodSlice(
          cut: widget.cut,
          groundKey: ValueKey(
            'provider-model-heading-background-${widget.provider.id}',
          ),
          // The veneer is opaque, so the key brings its own Material and
          // the ripple lands on the wood instead of behind it.
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: ValueKey('provider-model-heading-${widget.provider.id}'),
              onTap: widget.forceExpanded ? null : _toggle,
              splashColor: ink.on.withValues(alpha: .12),
              highlightColor: ink.on.withValues(alpha: .06),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: _headingHeight),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          widget.provider.name.toUpperCase(),
                          style: TextStyle(
                            color: ink.on,
                            fontSize: 12.5,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      _FavoriteStar(
                        key: ValueKey(
                          'provider-favorite-${widget.provider.id}',
                        ),
                        starred: widget.favorite,
                        subject: widget.provider.name,
                        onPressed: widget.onProviderFavoriteToggle,
                        ink: ink,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${widget.models.length}',
                        style: TextStyle(color: ink.onMuted, fontSize: 11),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        expanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 19,
                        color: ink.onMuted,
                      ),
                    ],
                  ),
                ),
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
    required this.cut,
    required this.favorites,
    required this.selectedProviderId,
    required this.selectedModelId,
    required this.onUnstar,
    super.key,
  });

  final BurlwoodCut cut;
  final List<FavoriteModel> favorites;
  final String selectedProviderId;
  final String selectedModelId;
  final ValueChanged<FavoriteModel> onUnstar;

  @override
  Widget build(BuildContext context) {
    final ink = PanelSurface.burlwood.ink(context.tokens);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Cut from the same sheet as the provider headings: it is the same
        // kind of thing, and one pale bar among them would read as a slip.
        BurlwoodSlice(
          cut: cut,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _headingHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
              child: Row(
                children: <Widget>[
                  Icon(Icons.star_rounded, size: 15, color: ink.accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'FAVORITES',
                      style: TextStyle(
                        color: ink.on,
                        fontSize: 12.5,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${favorites.length}',
                    style: TextStyle(color: ink.onMuted, fontSize: 11),
                  ),
                ],
              ),
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
    this.ink,
  });

  final bool starred;
  final String subject;
  final VoidCallback onPressed;

  /// Set when the star sits on a panel rather than on the dialog surface —
  /// casework keeps cream ink and its own brass in both modes.
  final PanelInk? ink;

  @override
  Widget build(BuildContext context) {
    final panel = ink;
    return IconButton(
      tooltip: starred
          ? 'Remove $subject from favorites'
          : 'Add $subject to favorites',
      onPressed: onPressed,
      isSelected: starred,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      iconSize: 17,
      selectedIcon: Icon(
        Icons.star_rounded,
        color: panel?.accent ?? context.tokens.brass,
      ),
      icon: Icon(
        Icons.star_border_rounded,
        color:
            panel?.onMuted ?? context.colors.onSurface.withValues(alpha: .45),
      ),
    );
  }
}
