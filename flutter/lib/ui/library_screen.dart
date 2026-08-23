import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import '../core/models.dart';
import 'common_widgets.dart';
import 'filter_menu.dart';
import 'formatters.dart';
import 'generation_loading_placeholder.dart';
import 'generation_view_widgets.dart';
import 'inline_video.dart';
import 'video_save_sheet.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final padding = constraints.maxWidth < 620 ? 16.0 : 28.0;
      final desktop = constraints.maxWidth >= 960;
      return SingleChildScrollView(
        padding: EdgeInsets.all(padding),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _LibraryHeading(controller: controller),
                const SizedBox(height: 22),
                if (desktop)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SizedBox(
                        width: 228,
                        child: _FolderSidebar(controller: controller),
                      ),
                      const SizedBox(width: 18),
                      Expanded(child: _LibraryResults(controller: controller)),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _MobileFolderBar(controller: controller),
                      const SizedBox(height: 12),
                      _LibraryResults(controller: controller),
                    ],
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _LibraryResults extends StatefulWidget {
  const _LibraryResults({required this.controller});

  final AppController controller;

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
    final moved = await _showGenerationMoveDialog(
      context,
      controller: controller,
      localIds: selectedIds,
    );
    if (moved && mounted) _setSelecting(false);
  }

  Future<void> _setSelectedHidden(bool hidden) async {
    final saved = await controller.setGenerationsHidden(selectedIds, hidden);
    if (saved && mounted) _setSelecting(false);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = controller.filteredGenerations;
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
    );
    return InlineVideoRegistryScope(
      registry: _inlinePlayback,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
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
              children: filtered
                  .map(
                    (item) => Padding(
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
                  children: filtered
                      .map(
                        (item) => SizedBox(
                          width: layout.tileWidth,
                          child: selectable(item),
                        ),
                      )
                      .toList(),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _FolderSidebar extends StatelessWidget {
  const _FolderSidebar({required this.controller});

  final AppController controller;

  Map<LibraryStorageFilter, int> get _storageCounts =>
      <LibraryStorageFilter, int>{
        for (final filter in LibraryStorageFilter.values)
          filter: controller.generations
              .where((item) => filter.matches(item.storage))
              .length,
      };

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.all(10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        StorageSidebarSection(
          controller: controller,
          value: controller.libraryStorageFilter,
          counts: _storageCounts,
          onChanged: (value) =>
              unawaited(controller.setLibraryStorageFilter(value)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Folders',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'New folder',
                visualDensity: VisualDensity.compact,
                onPressed: () => unawaited(
                  _showFolderEditor(context, controller: controller),
                ),
                icon: const Icon(Icons.create_new_folder_outlined, size: 19),
              ),
            ],
          ),
        ),
        _FolderRow(
          icon: Icons.video_library_outlined,
          label: 'All films',
          count: controller.folderCount(AppController.libraryFolderAll),
          selected:
              controller.libraryFolderView == AppController.libraryFolderAll,
          onTap: () =>
              controller.setLibraryFolderView(AppController.libraryFolderAll),
        ),
        _FolderRow(
          icon: Icons.inbox_outlined,
          label: 'Unfiled',
          count: controller.folderCount(AppController.libraryFolderUnfiled),
          selected:
              controller.libraryFolderView ==
              AppController.libraryFolderUnfiled,
          onTap: () => controller.setLibraryFolderView(
            AppController.libraryFolderUnfiled,
          ),
        ),
        if (controller.folders.isNotEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Divider(height: 1),
          ),
        ...controller.folderTree.map(
          (folder) => _FolderRow(
            icon: Icons.folder_outlined,
            label: folder.name,
            count: controller.folderCount(folder.id),
            selected: controller.libraryFolderView == folder.id,
            onTap: () => controller.setLibraryFolderView(folder.id),
            depth: controller.folderDepth(folder.id),
            folder: folder,
            controller: controller,
          ),
        ),
        if (controller.folders.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
            child: Text(
              'Create a folder for a project, client, or collection.',
              style: TextStyle(
                height: 1.4,
                fontSize: 11.5,
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
      ],
    ),
  );
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.folder,
    this.controller,
    this.depth = 0,
  });

  final IconData icon;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final LibraryFolder? folder;
  final AppController? controller;
  final int depth;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Material(
      color: selected ? context.colors.primaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: EdgeInsets.fromLTRB(9 + depth * 14, 9, 9, 9),
          child: Row(
            children: <Widget>[
              Icon(
                icon,
                size: 18,
                color: selected
                    ? context.colors.primary
                    : context.colors.onSurfaceVariant,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? context.colors.onPrimaryContainer
                        : context.colors.onSurface,
                  ),
                ),
              ),
              if (folder != null) ...<Widget>[
                const SizedBox(width: 4),
                Tooltip(
                  message: folder!.storage.label,
                  child: Icon(
                    folder!.storage == LibraryStorage.drive
                        ? Icons.cloud_outlined
                        : Icons.devices_outlined,
                    size: 13,
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(width: 5),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 10.5,
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              if (folder != null && controller != null) ...<Widget>[
                const SizedBox(width: 2),
                SizedBox.square(
                  dimension: 25,
                  child: PopupMenuButton<String>(
                    tooltip: '${folder!.name} options',
                    padding: EdgeInsets.zero,
                    iconSize: 17,
                    onSelected: (value) {
                      if (value == 'subfolder') {
                        unawaited(
                          _showFolderEditor(
                            context,
                            controller: controller!,
                            parentId: folder!.id,
                          ),
                        );
                      } else if (value == 'rename') {
                        unawaited(
                          _showFolderEditor(
                            context,
                            controller: controller!,
                            folder: folder,
                          ),
                        );
                      } else {
                        unawaited(
                          _confirmFolderDelete(context, controller!, folder!),
                        );
                      }
                    },
                    itemBuilder: (context) => const <PopupMenuEntry<String>>[
                      PopupMenuItem(
                        value: 'subfolder',
                        child: Text('New subfolder'),
                      ),
                      PopupMenuItem(value: 'rename', child: Text('Rename')),
                      PopupMenuItem(value: 'delete', child: Text('Remove')),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _MobileFolderBar extends StatelessWidget {
  const _MobileFolderBar({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    child: Row(
      children: <Widget>[
        Expanded(
          child: InkWell(
            onTap: () => unawaited(_showFolderPicker(context, controller)),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
              child: Row(
                children: <Widget>[
                  Icon(
                    controller.libraryFolderView ==
                            AppController.libraryFolderAll
                        ? Icons.video_library_outlined
                        : Icons.folder_outlined,
                    color: context.colors.primary,
                    size: 19,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      controller.activeFolderLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    '${controller.folderCount(controller.libraryFolderView)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Icon(Icons.expand_more_rounded, size: 19),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'New folder',
          onPressed: () =>
              unawaited(_showFolderEditor(context, controller: controller)),
          icon: const Icon(Icons.create_new_folder_outlined, size: 20),
        ),
      ],
    ),
  );
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
        final wide = constraints.maxWidth >= 760;
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
        final selectButton = OutlinedButton.icon(
          key: const ValueKey('library-select-button'),
          onPressed: () => onSelectingChanged(!selecting),
          icon: Icon(
            selecting ? Icons.close_rounded : Icons.check_box_outlined,
            size: 17,
          ),
          label: Text(
            selecting && selectedCount > 0
                ? '$selectedCount selected'
                : 'Select',
          ),
        );

        if (wide) {
          return Row(
            children: <Widget>[
              Expanded(child: search),
              const SizedBox(width: 8),
              filterButton,
              const SizedBox(width: 8),
              viewToggle,
              const SizedBox(width: 8),
              selectButton,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            search,
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[filterButton, viewToggle, selectButton],
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
                : 'Try another folder, tag, status, or a broader search.',
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
  });

  final AppController controller;
  final Generation item;
  final GenerationViewMode viewMode;
  final bool selecting;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => Stack(
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this record?'),
        content: const Text(
          'This removes compact history only. It does not cancel work already submitted to the provider.',
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
    if (confirmed == true) {
      await widget.controller.deleteGeneration(widget.item.localId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    void move() => unawaited(
      _showGenerationMoveDialog(
        context,
        controller: widget.controller,
        localIds: <String>{item.localId},
      ),
    );
    void tag() => unawaited(
      _showGenerationTagDialog(
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
          GenerationMedia(controller: widget.controller, item: item)
        else if (isGeneratingVideo)
          GenerationLoadingPlaceholder(
            item: item,
            style: widget.controller.generationPlaceholderStyle,
            progressEstimate: progressEstimate,
          )
        else
          GenerationInputPreview(controller: widget.controller, item: item),
        Positioned(top: 10, left: 10, child: StatusBadge(item: item)),
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
                  )
                : SizedBox(height: 280, child: preview),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: GenerationPrompt(
                        controller: widget.controller,
                        prompt: item.displayPrompt,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(width: 8),
                    StorageBadge(storage: item.storage, compact: true),
                    const SizedBox(width: 7),
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        relativeTime(item.createdAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
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
                          onPressed: () =>
                              widget.controller.setLibraryFolderView(folder.id),
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
                const SizedBox(height: 11),
                GenerationCost(item: item),
                if (item.error != null ||
                    item.resultRetentionError != null ||
                    item.lastCheckError != null ||
                    item.lastCheckedAt != null ||
                    item.isLongRunning) ...<Widget>[
                  const SizedBox(height: 9),
                  GenerationStatusDetails(item: item),
                ],
                if (item.deliveryExpired) ...<Widget>[
                  const SizedBox(height: 9),
                  Text(
                    'The provider’s delivery link expired; the generation record remains.',
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
                                minimumSize: const Size(128, 40),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
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
                              label: Text(
                                item.isImage ? 'Save image' : 'Save video',
                              ),
                            ),
                          if (widget.controller.canReuse(item))
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(128, 40),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                              ),
                              onPressed: () =>
                                  unawaited(widget.controller.reuse(item)),
                              icon: const Icon(Icons.replay_rounded, size: 16),
                              label: Text(
                                item.isFailed ? 'Retry generation' : 'Reuse',
                              ),
                            ),
                          GenerationStatusButton(
                            controller: widget.controller,
                            item: item,
                          ),
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
        ],
      ),
    );
  }
}

Future<void> _showFolderPicker(
  BuildContext context,
  AppController controller,
) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * .72,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 10),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Choose a folder',
                      style: Theme.of(sheetContext).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'New folder',
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      unawaited(
                        _showFolderEditor(context, controller: controller),
                      );
                    },
                    icon: const Icon(Icons.create_new_folder_outlined),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 18),
                children: <Widget>[
                  ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) => StorageSidebarSection(
                      controller: controller,
                      value: controller.libraryStorageFilter,
                      counts: <LibraryStorageFilter, int>{
                        for (final filter in LibraryStorageFilter.values)
                          filter: controller.generations
                              .where((item) => filter.matches(item.storage))
                              .length,
                      },
                      onChanged: (value) {
                        unawaited(controller.setLibraryStorageFilter(value));
                        Navigator.pop(sheetContext);
                      },
                    ),
                  ),
                  _FolderPickerTile(
                    icon: Icons.video_library_outlined,
                    label: 'All films',
                    count: controller.folderCount(
                      AppController.libraryFolderAll,
                    ),
                    selected:
                        controller.libraryFolderView ==
                        AppController.libraryFolderAll,
                    onTap: () {
                      controller.setLibraryFolderView(
                        AppController.libraryFolderAll,
                      );
                      Navigator.pop(sheetContext);
                    },
                  ),
                  _FolderPickerTile(
                    icon: Icons.inbox_outlined,
                    label: 'Unfiled',
                    count: controller.folderCount(
                      AppController.libraryFolderUnfiled,
                    ),
                    selected:
                        controller.libraryFolderView ==
                        AppController.libraryFolderUnfiled,
                    onTap: () {
                      controller.setLibraryFolderView(
                        AppController.libraryFolderUnfiled,
                      );
                      Navigator.pop(sheetContext);
                    },
                  ),
                  const Divider(),
                  ...controller.folderTree.map(
                    (folder) => _FolderPickerTile(
                      icon: Icons.folder_outlined,
                      label: folder.name,
                      count: controller.folderCount(folder.id),
                      selected: controller.libraryFolderView == folder.id,
                      depth: controller.folderDepth(folder.id),
                      onTap: () {
                        controller.setLibraryFolderView(folder.id);
                        Navigator.pop(sheetContext);
                      },
                      trailing: PopupMenuButton<String>(
                        tooltip: '${folder.name} options',
                        onSelected: (value) {
                          Navigator.pop(sheetContext);
                          if (value == 'subfolder') {
                            unawaited(
                              _showFolderEditor(
                                context,
                                controller: controller,
                                parentId: folder.id,
                              ),
                            );
                          } else if (value == 'rename') {
                            unawaited(
                              _showFolderEditor(
                                context,
                                controller: controller,
                                folder: folder,
                              ),
                            );
                          } else {
                            unawaited(
                              _confirmFolderDelete(context, controller, folder),
                            );
                          }
                        },
                        itemBuilder: (context) =>
                            const <PopupMenuEntry<String>>[
                              PopupMenuItem(
                                value: 'subfolder',
                                child: Text('New subfolder'),
                              ),
                              PopupMenuItem(
                                value: 'rename',
                                child: Text('Rename'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Remove'),
                              ),
                            ],
                      ),
                    ),
                  ),
                  if (controller.folders.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: Text(
                        'No custom folders yet. Tap the folder + button to make one.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: sheetContext.colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _FolderPickerTile extends StatelessWidget {
  const _FolderPickerTile({
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.trailing,
    this.depth = 0,
  });

  final IconData icon;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;
  final int depth;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.only(left: 16 + depth * 18, right: 8),
    selected: selected,
    selectedTileColor: context.colors.primaryContainer,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
    leading: Icon(icon, size: 21),
    title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text('$count ${count == 1 ? 'film' : 'films'}'),
    trailing:
        trailing ??
        (selected
            ? Icon(Icons.check_rounded, color: context.colors.primary)
            : null),
    onTap: onTap,
  );
}

Future<bool?> _showFolderEditor(
  BuildContext context, {
  required AppController controller,
  LibraryFolder? folder,
  String? parentId,
}) async {
  final nameController = TextEditingController(text: folder?.name ?? '');
  var selectedParentId = folder?.parentId ?? parentId;
  var destination =
      folder?.storage ??
      controller.folderById(parentId)?.storage ??
      controller.effectiveStorage;
  final blockedParents = folder == null
      ? const <String>{}
      : controller.folderBranch(folder.id);
  var saving = false;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(folder == null ? 'New folder' : 'Edit folder'),
        content: SizedBox(
          width: 390,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (controller.supportsLocalLibrary &&
                  controller.supportsGoogleDrive &&
                  folder == null) ...<Widget>[
                DropdownButtonFormField<LibraryStorage>(
                  initialValue: destination,
                  decoration: const InputDecoration(
                    labelText: 'Save folder in',
                    prefixIcon: Icon(Icons.storage_outlined),
                  ),
                  items: LibraryStorage.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.label),
                        ),
                      )
                      .toList(),
                  onChanged: saving
                      ? null
                      : (value) => setState(() {
                          destination = value ?? destination;
                          selectedParentId = null;
                        }),
                ),
                const SizedBox(height: 8),
              ],
              TextField(
                controller: nameController,
                autofocus: true,
                maxLength: 48,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Folder name',
                  hintText: 'Campaign, favorites, client work…',
                  prefixIcon: Icon(Icons.folder_outlined),
                ),
                onSubmitted: saving
                    ? null
                    : (_) async {
                        setState(() => saving = true);
                        final saved = await controller.saveLibraryFolder(
                          nameController.text,
                          existing: folder,
                          parentId: selectedParentId,
                          storage: destination,
                        );
                        if (dialogContext.mounted && saved) {
                          Navigator.pop(dialogContext, true);
                        } else if (dialogContext.mounted) {
                          setState(() => saving = false);
                        }
                      },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: selectedParentId ?? '',
                decoration: const InputDecoration(
                  labelText: 'Inside',
                  prefixIcon: Icon(Icons.account_tree_outlined),
                ),
                items: <DropdownMenuItem<String>>[
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Library (top level)'),
                  ),
                  ...controller.folderTree
                      .where(
                        (candidate) =>
                            candidate.storage == destination &&
                            !blockedParents.contains(candidate.id),
                      )
                      .map(
                        (candidate) => DropdownMenuItem(
                          value: candidate.id,
                          child: Text(
                            controller.folderPath(candidate.id),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                ],
                onChanged: saving
                    ? null
                    : (value) => setState(
                        () => selectedParentId = value?.isEmpty == true
                            ? null
                            : value,
                      ),
              ),
            ],
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
                    final saved = await controller.saveLibraryFolder(
                      nameController.text,
                      existing: folder,
                      parentId: selectedParentId,
                      storage: destination,
                    );
                    if (dialogContext.mounted && saved) {
                      Navigator.pop(dialogContext, true);
                    } else if (dialogContext.mounted) {
                      setState(() => saving = false);
                    }
                  },
            icon: saving
                ? const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.folder_outlined, size: 18),
            label: Text(folder == null ? 'Create' : 'Save'),
          ),
        ],
      ),
    ),
  );
  nameController.dispose();
  return result;
}

Future<void> _confirmFolderDelete(
  BuildContext context,
  AppController controller,
  LibraryFolder folder,
) async {
  final directCount = controller.generations
      .where((item) => item.folderId == folder.id)
      .length;
  final childCount = controller.childFolders(folder.id).length;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Remove “${folder.name}”?'),
      content: Text(
        '${directCount == 0 ? 'No films' : '$directCount ${directCount == 1 ? 'film' : 'films'}'} directly inside will move to Unfiled. '
        '${childCount == 0 ? 'There are no subfolders.' : '$childCount ${childCount == 1 ? 'subfolder moves' : 'subfolders move'} up one level.'} Nothing will be deleted.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Keep folder'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Remove folder'),
        ),
      ],
    ),
  );
  if (confirmed == true) await controller.deleteLibraryFolder(folder.id);
}

Future<bool> _showGenerationMoveDialog(
  BuildContext context, {
  required AppController controller,
  required Iterable<String> localIds,
}) async {
  final ids = localIds.toSet();
  final items = controller.generations
      .where((item) => ids.contains(item.localId))
      .toList();
  if (items.isEmpty) return false;
  final storages = items.map((item) => item.storage).toSet();
  if (storages.length != 1) {
    controller.showNotice(
      'Bulk moves require items from the same storage. Filter by Local or Drive, then select again.',
    );
    return false;
  }
  final storage = storages.single;
  final currentFolders = items.map((item) => item.folderId).toSet();
  String? folderId = currentFolders.length == 1 ? currentFolders.single : null;
  var moving = false;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(
          items.length == 1 ? 'Move film' : 'Move ${items.length} films',
        ),
        content: SizedBox(
          width: 470,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  StorageBadge(storage: storage),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: moving
                        ? null
                        : () async {
                            await _showFolderEditor(
                              dialogContext,
                              controller: controller,
                              parentId: folderId,
                            );
                            if (dialogContext.mounted) setState(() {});
                          },
                    icon: const Icon(
                      Icons.create_new_folder_outlined,
                      size: 18,
                    ),
                    label: const Text('New folder'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Choose a destination',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) => DecoratedBox(
                    decoration: BoxDecoration(
                      color: context.colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: context.colors.outlineVariant),
                    ),
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(7),
                      children: <Widget>[
                        _MoveDestinationTile(
                          label: 'Unfiled',
                          icon: Icons.inbox_outlined,
                          selected: folderId == null,
                          onTap: moving
                              ? null
                              : () => setState(() => folderId = null),
                        ),
                        ...controller.folderTree
                            .where((folder) => folder.storage == storage)
                            .map(
                              (folder) => _MoveDestinationTile(
                                label: folder.name,
                                icon: Icons.folder_outlined,
                                depth: controller.folderDepth(folder.id),
                                selected: folderId == folder.id,
                                onTap: moving
                                    ? null
                                    : () =>
                                          setState(() => folderId = folder.id),
                                trailing: PopupMenuButton<String>(
                                  tooltip: '${folder.name} folder actions',
                                  onSelected: (value) async {
                                    if (value == 'subfolder') {
                                      await _showFolderEditor(
                                        dialogContext,
                                        controller: controller,
                                        parentId: folder.id,
                                      );
                                    } else {
                                      await _showFolderEditor(
                                        dialogContext,
                                        controller: controller,
                                        folder: folder,
                                      );
                                    }
                                    if (dialogContext.mounted) setState(() {});
                                  },
                                  itemBuilder: (context) =>
                                      const <PopupMenuEntry<String>>[
                                        PopupMenuItem(
                                          value: 'subfolder',
                                          child: Text('New subfolder'),
                                        ),
                                        PopupMenuItem(
                                          value: 'edit',
                                          child: Text('Rename or move folder'),
                                        ),
                                      ],
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: moving
                ? null
                : () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            key: const ValueKey('confirm-generation-move'),
            onPressed: moving
                ? null
                : () async {
                    setState(() => moving = true);
                    final moved = await controller.moveGenerations(
                      ids,
                      folderId: folderId,
                    );
                    if (dialogContext.mounted && moved) {
                      Navigator.pop(dialogContext, true);
                    } else if (dialogContext.mounted) {
                      setState(() => moving = false);
                    }
                  },
            icon: moving
                ? const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.drive_file_move_outline, size: 18),
            label: const Text('Move'),
          ),
        ],
      ),
    ),
  );
  return result == true;
}

class _MoveDestinationTile extends StatelessWidget {
  const _MoveDestinationTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.depth = 0,
    this.trailing,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;
  final int depth;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: ListTile(
      dense: true,
      contentPadding: EdgeInsets.only(left: 10 + depth * 20, right: 4),
      selected: selected,
      selectedTileColor: context.colors.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      leading: Icon(icon, size: 20),
      title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing:
          trailing ??
          (selected
              ? Icon(Icons.check_circle_rounded, color: context.colors.primary)
              : null),
      onTap: onTap,
    ),
  );
}

Future<void> _showGenerationTagDialog(
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
            child: StorageBadge(storage: widget.item.storage),
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
