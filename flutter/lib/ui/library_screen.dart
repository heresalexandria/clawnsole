import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import '../core/asset_extensions.dart';
import '../core/models.dart';
import 'common_widgets.dart';
import 'filter_menu.dart';
import 'formatters.dart';
import 'generation_error_thumbnail.dart';
import 'generation_detail_modal.dart';
import 'generation_loading_placeholder.dart';
import 'generation_provenance.dart';
import 'generation_view_widgets.dart';
import 'inline_video.dart';
import 'library_folders.dart';
import 'video_save_sheet.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({required this.controller, super.key});

  final AppController controller;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  static const int _pageSize = 20;

  final ScrollController _scrollController = ScrollController();
  int _itemLimit = _pageSize;
  String? _listingSignature;
  bool _pageAdvancePending = false;

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
    final items = controller.filteredGenerations;
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
    final signature = <Object?>[
      controller.libraryFilter,
      controller.libraryStorageFilter,
      controller.libraryFavoriteFilter,
      controller.libraryVisibilityFilter,
      controller.libraryFolderView,
      controller.libraryTag,
      controller.libraryOutputKind,
      controller.librarySearch,
      controller.libraryViewMode,
    ].join('|');
    if (_listingSignature == signature) return;
    _listingSignature = signature;
    _itemLimit = _pageSize;
    _pageAdvancePending = false;
  }

  @override
  Widget build(BuildContext context) {
    _syncListingPage();
    final scope = FolderScope.generated(controller);
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = constraints.maxWidth < 620 ? 16.0 : 28.0;
        final desktop = constraints.maxWidth >= 960;
        return FolderRailLayout(
          heading: _LibraryHeading(controller: controller),
          rail: FolderRail(scope: scope),
          narrowRail: FolderDropdownBar(scope: scope),
          results: _LibraryResults(
            controller: controller,
            itemLimit: _itemLimit,
            onLoadMore: _loadMore,
            dragToFolders: desktop,
          ),
          scrollController: _scrollController,
          desktop: desktop,
          padding: padding,
        );
      },
    );
  }
}

class _LibraryResults extends StatefulWidget {
  const _LibraryResults({
    required this.controller,
    required this.itemLimit,
    required this.onLoadMore,
    required this.dragToFolders,
  });

  final AppController controller;
  final int itemLimit;
  final VoidCallback onLoadMore;

  /// Whether cards can be dragged onto the folder rail (wide layouts only —
  /// the narrow dropdown has no rows to drop on).
  final bool dragToFolders;

  @override
  State<_LibraryResults> createState() => _LibraryResultsState();
}

class _LibraryResultsState extends State<_LibraryResults> {
  final Set<String> selectedIds = <String>{};
  final InlineVideoRegistry _inlinePlayback = InlineVideoRegistry();
  bool selecting = false;

  AppController get controller => widget.controller;

  @override
  void dispose() {
    _inlinePlayback.dispose();
    super.dispose();
  }

  void _toggleSelection(String id) {
    setState(() {
      if (!selectedIds.add(id)) selectedIds.remove(id);
    });
  }

  void _setSelecting(bool value) {
    setState(() {
      selecting = value;
      if (!value) selectedIds.clear();
    });
  }

  Future<void> _moveSelected(BuildContext context) async {
    final moved = await showMoveToFolderDialog(
      context,
      FolderScope.generated(controller),
      Set<String>.of(selectedIds),
    );
    if (moved && mounted) _setSelecting(false);
  }

  /// What dragging [item] carries: the whole selection when the card is part
  /// of one (and the selection shares a storage), otherwise the card alone.
  LibraryDragData _dragDataFor(Generation item) {
    var ids = selecting && selectedIds.contains(item.localId)
        ? Set<String>.of(selectedIds)
        : <String>{item.localId};
    final storages = controller.generations
        .where((candidate) => ids.contains(candidate.localId))
        .map((candidate) => candidate.storage)
        .toSet();
    if (storages.length != 1) ids = <String>{item.localId};
    return LibraryDragData(
      collection: LibraryCollection.generated,
      storage: item.storage,
      itemIds: ids,
      label: 'Move ${ids.length} ${ids.length == 1 ? 'film' : 'films'}',
    );
  }

  Future<void> _setSelectedHidden(bool hidden) async {
    final saved = await controller.setGenerationsHidden(selectedIds, hidden);
    if (saved && mounted) _setSelecting(false);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = controller.filteredGenerations;
    final shown = filtered.take(widget.itemLimit).toList();
    final selected = controller.generations
        .where((item) => selectedIds.contains(item.localId))
        .toList();
    final selectedAreHidden =
        selected.isNotEmpty && selected.every((item) => item.hidden);
    Widget selectable(Generation item) => _SelectableGenerationCard(
      controller: controller,
      item: item,
      viewMode: controller.libraryViewMode,
      selecting: selecting,
      selected: selectedIds.contains(item.localId),
      onSelected: () => _toggleSelection(item.localId),
      dragData: widget.dragToFolders ? _dragDataFor(item) : null,
    );
    return InlineVideoRegistryScope(
      registry: _inlinePlayback,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Search, filters, view modes, and Select have nothing to act on
          // until a first film exists; the empty state carries the one call
          // to action that matters then.
          if (controller.generations.isNotEmpty)
            _LibraryToolbar(
              controller: controller,
              selecting: selecting,
              selectedCount: selected.length,
              onSelectingChanged: _setSelecting,
            ),
          if (DriveReconnectNotice.needed(controller)) ...<Widget>[
            const SizedBox(height: 12),
            DriveReconnectNotice(controller: controller, subject: 'films'),
          ],
          if (selecting) ...<Widget>[
            const SizedBox(height: 10),
            _BulkActionBar(
              selectedCount: selected.length,
              visibleCount: filtered.length,
              allVisibleSelected:
                  filtered.isNotEmpty &&
                  filtered.every((item) => selectedIds.contains(item.localId)),
              onSelectAll: () => setState(() {
                final visibleIds = filtered.map((item) => item.localId).toSet();
                if (visibleIds.every(selectedIds.contains)) {
                  selectedIds.removeAll(visibleIds);
                } else {
                  selectedIds.addAll(visibleIds);
                }
              }),
              onMove: selected.isEmpty
                  ? null
                  : () => unawaited(_moveSelected(context)),
              onVisibility: selected.isEmpty
                  ? null
                  : () => unawaited(_setSelectedHidden(!selectedAreHidden)),
              visibilityLabel: selectedAreHidden ? 'Unhide' : 'Hide',
              onCancel: () => _setSelecting(false),
            ),
          ],
          const SizedBox(height: 18),
          if (filtered.isEmpty)
            _LibraryEmpty(controller: controller)
          else if (controller.libraryViewMode == GenerationViewMode.compact)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: shown
                  .map(
                    (item) => Padding(
                      key: ValueKey('library-generation-${item.localId}'),
                      padding: const EdgeInsets.only(bottom: 9),
                      child: selectable(item),
                    ),
                  )
                  .toList(),
            )
          else
            LayoutBuilder(
              builder: (context, grid) {
                final layout = GenerationCardGrid.fit(
                  grid.maxWidth,
                  controller.libraryViewMode,
                );
                return Wrap(
                  spacing: GenerationCardGrid.gap,
                  runSpacing: GenerationCardGrid.gap,
                  children: shown
                      .map(
                        (item) => SizedBox(
                          key: ValueKey('library-generation-${item.localId}'),
                          width: layout.tileWidth,
                          child: selectable(item),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          if (shown.length < filtered.length) ...<Widget>[
            const SizedBox(height: 14),
            Center(
              child: TextButton.icon(
                key: const ValueKey('library-load-more'),
                onPressed: widget.onLoadMore,
                icon: const Icon(Icons.expand_more_rounded),
                label: Text(
                  'Load ${((filtered.length - shown.length).clamp(0, 20))} more',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LibraryHeading extends StatelessWidget {
  const _LibraryHeading({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 20,
    runSpacing: 14,
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: <Widget>[
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Eyebrow('Your library'),
            const SizedBox(height: 10),
            Text(
              'Your films.',
              style: Theme.of(context).textTheme.displayLarge,
            ),
            const SizedBox(height: 10),
            Text(
              controller.supportsLocalLibrary
                  ? 'Local work stays on this device. Drive work follows you to every connected Clawnsole.'
                  : 'Drive work follows you to every connected Clawnsole.',
              style: TextStyle(color: context.colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          if (controller.supportsGoogleDrive)
            DriveRefreshButton(controller: controller, keyPrefix: 'library'),
          FilledButton.icon(
            onPressed: () => unawaited(controller.navigate(AppSection.create)),
            icon: const Icon(Icons.add_rounded),
            label: const Text('New generation'),
          ),
        ],
      ),
    ],
  );
}

enum _LibraryToolbarAction { filters, full, mini, compact, select }

class _LibraryToolbar extends StatelessWidget {
  const _LibraryToolbar({
    required this.controller,
    required this.selecting,
    required this.selectedCount,
    required this.onSelectingChanged,
  });

  final AppController controller;
  final bool selecting;
  final int selectedCount;
  final ValueChanged<bool> onSelectingChanged;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.all(10),
    child: LayoutBuilder(
      builder: (context, constraints) {
        // Wide enough for one line of segments, a usable search field, and
        // the keys; a 1280-px window with the side rail lands just above.
        final wide = constraints.maxWidth >= 860;
        // Media type is the one always-visible facet: its counts reflect
        // every other active filter, so they read as "what is in this view".
        final keys = <Widget>[
          ConsoleFilterSegment(
            key: const ValueKey('library-kind-all'),
            label: 'All',
            semanticLabel: 'All media types',
            icon: Icons.grid_view_rounded,
            count: wide ? controller.libraryOutputKindCount(null) : null,
            selected: controller.libraryOutputKind == null,
            onTap: () => controller.setLibraryOutputKind(null),
            compact: !wide,
          ),
          ...GenerationOutputKind.values.map(
            (kind) => ConsoleFilterSegment(
              key: ValueKey('library-kind-${kind.name}'),
              label: kind.label,
              icon: outputKindIcon(kind),
              count: wide ? controller.libraryOutputKindCount(kind) : null,
              selected: controller.libraryOutputKind == kind,
              onTap: () => controller.setLibraryOutputKind(kind),
              compact: !wide,
            ),
          ),
        ];
        final segments = wide
            ? Wrap(spacing: 5, runSpacing: 5, children: keys)
            : ConsoleSegmentStrip(children: keys);
        final search = TextField(
          key: const ValueKey('generation-library-search'),
          onChanged: controller.setSearch,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded, size: 18),
            hintText: 'Search prompts, tags, folders',
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          style: const TextStyle(fontSize: 13),
        );
        final filterButton = LibraryFilterButton(
          controller: controller,
          collection: LibraryCollection.generated,
          compact: !wide,
        );
        final viewToggle = GenerationViewToggle(
          keyPrefix: 'library-view',
          value: controller.libraryViewMode,
          onChanged: (value) => unawaited(controller.setLibraryViewMode(value)),
        );
        final selectIcon = Icon(
          selecting ? Icons.close_rounded : Icons.check_box_outlined,
          size: 17,
        );
        // Narrow toolbars keep Select as an icon key; the bulk bar beneath
        // already spells out the selected count.
        final selectButton = wide
            ? OutlinedButton.icon(
                key: const ValueKey('library-select-button'),
                onPressed: () => onSelectingChanged(!selecting),
                icon: selectIcon,
                label: Text(
                  selecting && selectedCount > 0
                      ? '$selectedCount selected'
                      : 'Select',
                ),
              )
            : Tooltip(
                message: selecting ? 'Done selecting' : 'Select',
                child: OutlinedButton(
                  key: const ValueKey('library-select-button'),
                  onPressed: () => onSelectingChanged(!selecting),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: selectIcon,
                ),
              );

        if (wide) {
          // The segments keep their natural single line; the search field is
          // what gives up width first on narrower desktops.
          return Row(
            children: <Widget>[
              segments,
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: search,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              filterButton,
              const SizedBox(width: 8),
              viewToggle,
              const SizedBox(width: 8),
              selectButton,
            ],
          );
        }
        // Narrow: keep the three primary media facets on one clean line and
        // gather the secondary filters, view choice, and selection mode under
        // one More key. Search remains directly editable above them.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            search,
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(child: segments),
                const SizedBox(width: 6),
                SizedBox.square(
                  dimension: 44,
                  child: PopupMenuButton<_LibraryToolbarAction>(
                    key: const ValueKey('library-more-menu'),
                    tooltip: 'More library options',
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.more_horiz_rounded),
                    onSelected: (action) {
                      switch (action) {
                        case _LibraryToolbarAction.filters:
                          unawaited(
                            showLibraryFilterSheet(
                              context,
                              controller: controller,
                              collection: LibraryCollection.generated,
                            ),
                          );
                        case _LibraryToolbarAction.full:
                          unawaited(
                            controller.setLibraryViewMode(
                              GenerationViewMode.full,
                            ),
                          );
                        case _LibraryToolbarAction.mini:
                          unawaited(
                            controller.setLibraryViewMode(
                              GenerationViewMode.mini,
                            ),
                          );
                        case _LibraryToolbarAction.compact:
                          unawaited(
                            controller.setLibraryViewMode(
                              GenerationViewMode.compact,
                            ),
                          );
                        case _LibraryToolbarAction.select:
                          onSelectingChanged(!selecting);
                      }
                    },
                    itemBuilder: (context) =>
                        <PopupMenuEntry<_LibraryToolbarAction>>[
                          const PopupMenuItem<_LibraryToolbarAction>(
                            key: ValueKey('library-more-filters'),
                            value: _LibraryToolbarAction.filters,
                            child: ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.tune_rounded),
                              title: Text('Filters'),
                            ),
                          ),
                          const PopupMenuDivider(),
                          for (final entry
                              in const <
                                (
                                  GenerationViewMode,
                                  _LibraryToolbarAction,
                                  String,
                                )
                              >[
                                (
                                  GenerationViewMode.full,
                                  _LibraryToolbarAction.full,
                                  'Full cards',
                                ),
                                (
                                  GenerationViewMode.mini,
                                  _LibraryToolbarAction.mini,
                                  'Mini cards',
                                ),
                                (
                                  GenerationViewMode.compact,
                                  _LibraryToolbarAction.compact,
                                  'Compact list',
                                ),
                              ])
                            CheckedPopupMenuItem<_LibraryToolbarAction>(
                              value: entry.$2,
                              checked: controller.libraryViewMode == entry.$1,
                              child: Text(entry.$3),
                            ),
                          const PopupMenuDivider(),
                          PopupMenuItem<_LibraryToolbarAction>(
                            key: const ValueKey('library-more-select'),
                            value: _LibraryToolbarAction.select,
                            child: ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                selecting
                                    ? Icons.close_rounded
                                    : Icons.check_box_outlined,
                              ),
                              title: Text(
                                selecting && selectedCount > 0
                                    ? 'Done selecting ($selectedCount)'
                                    : selecting
                                    ? 'Done selecting'
                                    : 'Select films',
                              ),
                            ),
                          ),
                        ],
                  ),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
}

class _LibraryEmpty extends StatelessWidget {
  const _LibraryEmpty({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 55),
      child: Column(
        children: <Widget>[
          Icon(
            Icons.collections_outlined,
            size: 44,
            color: context.tokens.brass,
          ),
          const SizedBox(height: 14),
          Text(
            controller.generations.isEmpty
                ? 'No films just yet.'
                : 'Nothing in this view.',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            controller.generations.isEmpty
                ? 'Your first generation will arrive here with its settings and live status.'
                : 'Try another folder, media type, tag, status, or a broader search.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colors.onSurfaceVariant),
          ),
          if (controller.generations.isEmpty) ...<Widget>[
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () =>
                  unawaited(controller.navigate(AppSection.create)),
              icon: const Icon(Icons.auto_awesome_rounded),
              label: const Text('Create your first'),
            ),
          ],
        ],
      ),
    ),
  );
}

class _BulkActionBar extends StatelessWidget {
  const _BulkActionBar({
    required this.selectedCount,
    required this.visibleCount,
    required this.allVisibleSelected,
    required this.onSelectAll,
    required this.onMove,
    required this.onVisibility,
    required this.visibilityLabel,
    required this.onCancel,
  });

  final int selectedCount;
  final int visibleCount;
  final bool allVisibleSelected;
  final VoidCallback onSelectAll;
  final VoidCallback? onMove;
  final VoidCallback? onVisibility;
  final String visibilityLabel;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: context.colors.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$selectedCount selected',
            style: TextStyle(
              color: context.colors.onPrimaryContainer,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        TextButton.icon(
          onPressed: visibleCount == 0 ? null : onSelectAll,
          icon: Icon(
            allVisibleSelected
                ? Icons.deselect_rounded
                : Icons.select_all_rounded,
            size: 18,
          ),
          label: Text(
            allVisibleSelected ? 'Deselect visible' : 'Select visible',
          ),
        ),
        FilledButton.tonalIcon(
          key: const ValueKey('library-bulk-move'),
          onPressed: onMove,
          icon: const Icon(Icons.drive_file_move_outline, size: 18),
          label: const Text('Move'),
        ),
        OutlinedButton.icon(
          onPressed: onVisibility,
          icon: Icon(
            visibilityLabel == 'Hide'
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            size: 18,
          ),
          label: Text(visibilityLabel),
        ),
        TextButton(onPressed: onCancel, child: const Text('Done')),
      ],
    ),
  );
}

class _SelectableGenerationCard extends StatelessWidget {
  const _SelectableGenerationCard({
    required this.controller,
    required this.item,
    required this.viewMode,
    required this.selecting,
    required this.selected,
    required this.onSelected,
    this.dragData,
  });

  final AppController controller;
  final Generation item;
  final GenerationViewMode viewMode;
  final bool selecting;
  final bool selected;
  final VoidCallback onSelected;

  /// When set, the card can be dragged onto a folder row carrying this.
  final LibraryDragData? dragData;

  @override
  Widget build(BuildContext context) {
    final card = _card(context);
    if (dragData == null) return card;
    return LibraryDraggable(data: dragData!, child: card);
  }

  Widget _card(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: <Widget>[
      AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: selected ? context.tokens.brass : Colors.transparent,
            width: 2,
          ),
          boxShadow: selected
              ? <BoxShadow>[
                  BoxShadow(
                    color: context.tokens.brass.withValues(alpha: .22),
                    blurRadius: 14,
                  ),
                ]
              : const <BoxShadow>[],
        ),
        child: GenerationCard(
          controller: controller,
          item: item,
          viewMode: viewMode,
        ),
      ),
      if (selecting)
        Positioned(
          top: 7,
          left: 7,
          child: Material(
            elevation: 7,
            color: context.colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
              side: BorderSide(
                color: selected
                    ? context.tokens.brass
                    : context.colors.outlineVariant,
              ),
            ),
            child: InkWell(
              key: ValueKey('select-generation-${item.localId}'),
              onTap: onSelected,
              borderRadius: BorderRadius.circular(9),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  selected
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  color: selected
                      ? context.tokens.brass
                      : context.colors.onSurfaceVariant,
                  size: 24,
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class GenerationCard extends StatefulWidget {
  const GenerationCard({
    required this.controller,
    required this.item,
    super.key,
    this.viewMode = GenerationViewMode.full,
  });

  final AppController controller;
  final Generation item;
  final GenerationViewMode viewMode;

  @override
  State<GenerationCard> createState() => _GenerationCardState();
}

class _GenerationCardState extends State<GenerationCard> {
  bool saving = false;

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      await saveGenerationVideo(context, widget.controller, widget.item);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _remove() async {
    if (await confirmGenerationRecordRemoval(context)) {
      await widget.controller.deleteGeneration(widget.item.localId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    void move() => unawaited(
      showMoveToFolderDialog(
        context,
        FolderScope.generated(widget.controller),
        <String>{item.localId},
      ),
    );
    void tag() => unawaited(
      showGenerationTagDialog(
        context,
        controller: widget.controller,
        item: item,
      ),
    );
    void visibility() => unawaited(
      widget.controller.setGenerationsHidden(<String>{
        item.localId,
      }, !item.hidden),
    );
    final copyToDrive =
        item.storage == LibraryStorage.local &&
            widget.controller.googleDriveConnected
        ? () => unawaited(
            widget.controller.copyLocalLibraryToGoogleDrive(
              generationIds: <String>{item.localId},
            ),
          )
        : null;
    if (widget.viewMode == GenerationViewMode.compact) {
      return CompactGenerationRow(
        controller: widget.controller,
        item: item,
        onMove: move,
        onTag: tag,
        onVisibility: visibility,
        onDelete: () => unawaited(_remove()),
        onCopyToDrive: copyToDrive,
      );
    }
    if (widget.viewMode == GenerationViewMode.mini) {
      return MiniGenerationCard(
        controller: widget.controller,
        item: item,
        onMove: move,
        onTag: tag,
        onVisibility: visibility,
        onDelete: () => unawaited(_remove()),
        onCopyToDrive: copyToDrive,
      );
    }
    final folder = widget.controller.folderById(item.folderId);
    final hasMedia = item.resultAsset != null || item.resultUrl != null;
    final isGeneratingVideo = !hasMedia && item.isWorking && !item.isImage;
    final progressEstimate = widget.controller.generationProgress(item);
    final progress = progressEstimate.percentage;
    final preview = Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (hasMedia)
          GenerationMedia(
            controller: widget.controller,
            item: item,
            showTimelineOverlay: false,
          )
        else if (isGeneratingVideo)
          GenerationLoadingPlaceholder(
            item: item,
            style: widget.controller.generationPlaceholderStyle,
            progressEstimate: progressEstimate,
          )
        else if (GenerationErrorThumbnail.shouldShow(item))
          GenerationErrorThumbnail(item: item)
        else
          GenerationInputPreview(controller: widget.controller, item: item),
        // Status, storage, and age share the top-left corner so the card
        // body below keeps the full width for the prompt.
        Positioned(
          key: ValueKey('generation-meta-overlay-${item.localId}'),
          top: 10,
          left: 10,
          right: 48,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              if (StatusBadge.shouldShow(item)) StatusBadge(item: item),
              StorageBadge(
                storage: item.storage,
                compact: true,
                pendingUpload: generationPendingDriveUpload(item),
              ),
              MediaDurationBadge(text: relativeTime(item.createdAt)),
            ],
          ),
        ),
        GenerationThumbnailFooter(item: item),
        Positioned(
          top: 7,
          right: 7,
          child: IconButton.filledTonal(
            tooltip: item.favorite
                ? 'Remove from favorites'
                : 'Add to favorites',
            onPressed: () =>
                unawaited(widget.controller.toggleGenerationFavorite(item)),
            icon: Icon(
              item.favorite ? Icons.star_rounded : Icons.star_border_rounded,
              color: item.favorite ? context.tokens.brass : null,
            ),
          ),
        ),
        if (item.isWorking && !item.isStatusUnavailable)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              value: progress == null ? null : progress / 100,
              minHeight: 5,
              backgroundColor: Colors.white24,
              color: ClawnsoleColors.brassBright,
            ),
          ),
      ],
    );
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            child: isGeneratingVideo || hasMedia
                ? InlineVideoMediaBox(
                    playbackId: item.localId,
                    aspectRatio: generationAspectRatio(item.config.aspectRatio),
                    preview: preview,
                    idleChrome: hasMedia && !item.isImage
                        ? GenerationIdleChrome(
                            controller: widget.controller,
                            item: item,
                          )
                        : null,
                  )
                : Stack(
                    children: <Widget>[
                      StaticMediaBox(
                        aspectRatio: generationAspectRatio(
                          item.config.aspectRatio,
                        ),
                        reserveChrome: !item.isImage,
                        child: preview,
                      ),
                      // With no film to show, the media zone is dead space —
                      // the status panel lives there instead of stretching
                      // the card body past its delivered neighbors. A dead
                      // render skips the panel: its error already sits on the
                      // test-bars thumbnail band.
                      if (!GenerationErrorThumbnail.shouldShow(item) &&
                          GenerationStatusDetails.shouldShow(item))
                        Positioned.fill(
                          key: const ValueKey('generation-status-overlay'),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 52, 16, 16),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 520,
                                ),
                                child: GenerationStatusDetails(
                                  item: item,
                                  maxProblemLines: 6,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          // The body is the way into the film's detail modal; the buttons
          // and chips inside keep their own taps.
          InkWell(
            key: ValueKey<String>('generation-open-${item.localId}'),
            onTap: () => unawaited(
              showGenerationDetailModal(
                context,
                controller: widget.controller,
                item: item,
              ),
            ),
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(15),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (GenerationProvenance.applies(item)) ...<Widget>[
                    GenerationProvenance(
                      controller: widget.controller,
                      item: item,
                    ),
                    const SizedBox(height: 7),
                  ],
                  GenerationPrompt(
                    controller: widget.controller,
                    prompt: item.displayPrompt,
                    style: Theme.of(context).textTheme.titleLarge,
                    reserveCollapsedHeight: true,
                  ),
                  if (folder != null || item.tags.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 9),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: <Widget>[
                        if (folder != null)
                          ActionChip(
                            avatar: const Icon(Icons.folder_outlined, size: 14),
                            label: Text(folder.name),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => widget.controller
                                .setLibraryFolderView(folder.id),
                          ),
                        ...item.tags
                            .take(3)
                            .map(
                              (tag) => ActionChip(
                                label: Text('#$tag'),
                                visualDensity: VisualDensity.compact,
                                onPressed: () =>
                                    widget.controller.setLibraryTag(tag),
                              ),
                            ),
                        if (item.tags.length > 3)
                          Chip(
                            label: Text('+${item.tags.length - 3}'),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 11),
                  GenerationSpecChips(item: item),
                  if (item.config.keyframes?.isNotEmpty == true ||
                      item.config.references?.isNotEmpty == true ||
                      item.config.source != null) ...<Widget>[
                    const SizedBox(height: 9),
                    ReferenceInputsStrip(
                      controller: widget.controller,
                      item: item,
                    ),
                  ],
                  if (GenerationStatusDetails.shouldShow(item) &&
                      (hasMedia || isGeneratingVideo)) ...<Widget>[
                    const SizedBox(height: 9),
                    GenerationStatusDetails(item: item),
                  ],
                  if (item.deliveryExpired) ...<Widget>[
                    const SizedBox(height: 9),
                    Text(
                      'The provider’s delivery link expired before the film could be retained; the record stays so you can reuse its settings.',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 13),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: <Widget>[
                            if (item.resultAsset != null ||
                                item.resultUrl != null)
                              FilledButton.tonalIcon(
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(88, 40),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 15,
                                  ),
                                ),
                                onPressed: saving
                                    ? null
                                    : () => unawaited(_save()),
                                icon: saving
                                    ? const SizedBox.square(
                                        dimension: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.download_rounded,
                                        size: 16,
                                      ),
                                label: const Text('Save'),
                              ),
                            if (widget.controller.canReuse(item))
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(88, 40),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 15,
                                  ),
                                ),
                                onPressed: () =>
                                    unawaited(widget.controller.reuse(item)),
                                icon: const Icon(
                                  Icons.replay_rounded,
                                  size: 16,
                                ),
                                label: Text(
                                  item.isFailed && !item.hasDeliveredMedia
                                      ? 'Retry'
                                      : 'Reuse',
                                ),
                              ),
                            GenerationStatusButton(
                              controller: widget.controller,
                              item: item,
                            ),
                            GenerationCostChip(item: item),
                          ],
                        ),
                      ),
                      GenerationActionsMenu(
                        controller: widget.controller,
                        item: item,
                        includeSave: false,
                        includeReuse: false,
                        includeCheckStatus: false,
                        onMove: move,
                        onTag: tag,
                        onVisibility: visibility,
                        onDelete: () => unawaited(_remove()),
                        onCopyToDrive: copyToDrive,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks before a history record is dropped. Shared by the card menus and the
/// film modal so the wording never drifts.
Future<bool> confirmGenerationRecordRemoval(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Remove this record?'),
      content: const Text(
        'This removes the generation record and its unshared retained media. Media still used elsewhere is kept. It does not cancel work already submitted to the provider.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Keep it'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

Future<void> showGenerationTagDialog(
  BuildContext context, {
  required AppController controller,
  required Generation item,
}) async {
  final editor = _GenerationTagEditor(controller: controller, item: item);
  if (MediaQuery.sizeOf(context).width < 700) {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: SafeArea(top: false, child: editor),
      ),
    );
  } else {
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(padding: const EdgeInsets.all(24), child: editor),
        ),
      ),
    );
  }
}

class _GenerationTagEditor extends StatefulWidget {
  const _GenerationTagEditor({required this.controller, required this.item});

  final AppController controller;
  final Generation item;

  @override
  State<_GenerationTagEditor> createState() => _GenerationTagEditorState();
}

class _GenerationTagEditorState extends State<_GenerationTagEditor> {
  late List<String> tags;
  final tagController = TextEditingController();
  final tagFocusNode = FocusNode();
  bool saving = false;
  String? tagError;

  @override
  void initState() {
    super.initState();
    tags = List<String>.from(widget.item.tags);
  }

  @override
  void dispose() {
    tagController.dispose();
    tagFocusNode.dispose();
    super.dispose();
  }

  bool _hasTag(String value) =>
      tags.any((tag) => tag.toLowerCase() == value.toLowerCase());

  void _addTag([String? value]) {
    final input = (value ?? tagController.text)
        .trim()
        .replaceFirst(RegExp(r'^#+'), '')
        .trim();
    if (input.isEmpty) return;
    if (input.length > 28) {
      setState(() => tagError = 'Keep tags to 28 characters or fewer.');
      return;
    }
    if (tags.length >= 12 && !_hasTag(input)) {
      setState(() => tagError = 'A generation can have up to 12 tags.');
      return;
    }
    setState(() {
      if (!_hasTag(input)) tags.add(input);
      tagController.clear();
      tagError = null;
    });
  }

  Future<void> _save() async {
    if (tagController.text.trim().isNotEmpty) _addTag();
    if (tagError != null) return;
    setState(() => saving = true);
    final saved = await widget.controller.tagGeneration(
      widget.item.localId,
      tags,
    );
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('Tag film', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(
            widget.item.displayPrompt,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.colors.onSurfaceVariant),
          ),
          const SizedBox(height: 9),
          Align(
            alignment: Alignment.centerLeft,
            child: StorageBadge(
              storage: widget.item.storage,
              pendingUpload: generationPendingDriveUpload(widget.item),
            ),
          ),
          const SizedBox(height: 22),
          Text('Tags', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 9),
          if (tags.isNotEmpty) ...<Widget>[
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 145),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.colors.outlineVariant),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(10),
                  child: Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: tags
                        .map(
                          (tag) => InputChip(
                            label: Text('#$tag'),
                            onDeleted: saving
                                ? null
                                : () => setState(() => tags.remove(tag)),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          RawAutocomplete<String>(
            textEditingController: tagController,
            focusNode: tagFocusNode,
            displayStringForOption: (option) => option,
            optionsBuilder: (value) {
              final query = value.text.trim().toLowerCase();
              return widget.controller.libraryTags.where(
                (tag) =>
                    !_hasTag(tag) &&
                    (query.isEmpty || tag.toLowerCase().contains(query)),
              );
            },
            onSelected: _addTag,
            fieldViewBuilder: (context, fieldController, focusNode, onSubmit) =>
                TextField(
                  controller: fieldController,
                  focusNode: focusNode,
                  enabled: !saving,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'Add tags',
                    hintText: 'Type to find or create a tag',
                    prefixIcon: const Icon(Icons.sell_outlined),
                    suffixIcon: IconButton(
                      tooltip: 'Add tag',
                      onPressed: saving ? null : _addTag,
                      icon: const Icon(Icons.add_rounded),
                    ),
                    errorText: tagError,
                    helperText:
                        'Choose an existing tag or press Enter to create it.',
                  ),
                  onSubmitted: saving ? null : _addTag,
                ),
            optionsViewBuilder: (context, onSelected, options) => Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 10,
                borderRadius: BorderRadius.circular(12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 300,
                    maxWidth: 470,
                    maxHeight: 210,
                  ),
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    children: options
                        .map(
                          (tag) => ListTile(
                            dense: true,
                            leading: const Icon(Icons.sell_outlined, size: 18),
                            title: Text('#$tag'),
                            onTap: () => onSelected(tag),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: saving ? null : () => unawaited(_save()),
                icon: saving
                    ? const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
