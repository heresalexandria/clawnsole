import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import '../core/models.dart';
import 'common_widgets.dart';
import 'formatters.dart';
import 'generation_loading_placeholder.dart';
import 'generation_view_widgets.dart';
import 'hardware.dart';
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

class _LibraryResults extends StatelessWidget {
  const _LibraryResults({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      _LibraryToolbar(controller: controller),
      if (controller.libraryTags.isNotEmpty) ...<Widget>[
        const SizedBox(height: 12),
        _TagFilters(controller: controller),
      ],
      const SizedBox(height: 18),
      if (controller.filteredGenerations.isEmpty)
        _LibraryEmpty(controller: controller)
      else if (controller.libraryViewMode == GenerationViewMode.compact)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: controller.filteredGenerations
              .map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: GenerationCard(
                    controller: controller,
                    item: item,
                    viewMode: GenerationViewMode.compact,
                  ),
                ),
              )
              .toList(),
        )
      else
        LayoutBuilder(
          builder: (context, grid) {
            final fullColumns = grid.maxWidth >= 1120
                ? 3
                : grid.maxWidth >= 650
                ? 2
                : 1;
            const gap = 16.0;
            final columns =
                controller.libraryViewMode == GenerationViewMode.full
                ? fullColumns
                : ((grid.maxWidth + gap) / (160 + gap)).floor().clamp(
                    1,
                    fullColumns * 2,
                  );
            final width = (grid.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: controller.filteredGenerations
                  .map(
                    (item) => SizedBox(
                      width: width,
                      child: GenerationCard(
                        controller: controller,
                        item: item,
                        viewMode: controller.libraryViewMode,
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
    ],
  );
}

class _FolderSidebar extends StatelessWidget {
  const _FolderSidebar({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.all(10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
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

class _TagFilters extends StatelessWidget {
  const _TagFilters({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 35,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: controller.libraryTags.length + 1,
      separatorBuilder: (_, _) => const SizedBox(width: 7),
      itemBuilder: (context, index) {
        final tag = index == 0 ? null : controller.libraryTags[index - 1];
        return FilterChip(
          avatar: index == 0 ? const Icon(Icons.sell_outlined, size: 15) : null,
          label: Text(
            tag == null ? 'All tags' : '#$tag · ${controller.tagCount(tag)}',
          ),
          selected: controller.libraryTag == tag,
          onSelected: (_) => controller.setLibraryTag(tag),
          visualDensity: VisualDensity.compact,
        );
      },
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
      FilledButton.icon(
        onPressed: () => unawaited(controller.navigate(AppSection.create)),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New generation'),
      ),
    ],
  );
}

class _LibraryToolbar extends StatelessWidget {
  const _LibraryToolbar({required this.controller});

  final AppController controller;

  int _count(LibraryFilter filter) => switch (filter) {
    LibraryFilter.all =>
      controller.generations
          .where(
            (item) => controller.libraryStorageFilter.matches(item.storage),
          )
          .length,
    LibraryFilter.working =>
      controller.generations
          .where(
            (item) =>
                controller.libraryStorageFilter.matches(item.storage) &&
                item.isWorking,
          )
          .length,
    LibraryFilter.ready =>
      controller.generations
          .where(
            (item) =>
                controller.libraryStorageFilter.matches(item.storage) &&
                item.isReady,
          )
          .length,
    LibraryFilter.failed =>
      controller.generations
          .where(
            (item) =>
                controller.libraryStorageFilter.matches(item.storage) &&
                item.isFailed,
          )
          .length,
  };

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.all(10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Align(
          alignment: Alignment.centerRight,
          child: GenerationViewToggle(
            keyPrefix: 'library-view',
            value: controller.libraryViewMode,
            onChanged: (value) =>
                unawaited(controller.setLibraryViewMode(value)),
          ),
        ),
        const SizedBox(height: 9),
        if (controller.supportsLocalLibrary) ...<Widget>[
          StorageFilterChips(
            value: controller.libraryStorageFilter,
            showLocal: true,
            onChanged: (value) =>
                unawaited(controller.setLibraryStorageFilter(value)),
          ),
          const SizedBox(height: 9),
        ],
        FavoriteFilterChips(
          value: controller.libraryFavoriteFilter,
          onChanged: controller.setLibraryFavoriteFilter,
        ),
        const SizedBox(height: 9),
        LayoutBuilder(
          builder: (context, constraints) {
            final filters = Wrap(
              spacing: 5,
              runSpacing: 5,
              children: LibraryFilter.values
                  .map(
                    (filter) => _FilterSegment(
                      filter: filter,
                      count: _count(filter),
                      selected: controller.libraryFilter == filter,
                      onTap: () =>
                          unawaited(controller.setLibraryFilter(filter)),
                    ),
                  )
                  .toList(),
            );
            final search = TextField(
              key: const ValueKey('generation-library-search'),
              onChanged: controller.setSearch,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded, size: 18),
                hintText: 'Search prompts, tags, folders',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              style: const TextStyle(fontSize: 13),
            );

            if (constraints.maxWidth >= 760) {
              return Row(
                children: <Widget>[
                  Expanded(child: filters),
                  const SizedBox(width: 16),
                  SizedBox(width: 320, child: search),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[filters, const SizedBox(height: 10), search],
            );
          },
        ),
      ],
    ),
  );
}

class _FilterSegment extends StatelessWidget {
  const _FilterSegment({
    required this.filter,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final LibraryFilter filter;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  static const _icons = <LibraryFilter, IconData>{
    LibraryFilter.all: Icons.grid_view_rounded,
    LibraryFilter.working: Icons.autorenew_rounded,
    LibraryFilter.ready: Icons.check_circle_outline_rounded,
    LibraryFilter.failed: Icons.error_outline_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? context.colors.onPrimary
        : context.colors.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: consoleKeyDecoration(
          context,
          selected: selected,
          radius: 10,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(_icons[filter], size: 14, color: foreground),
            const SizedBox(width: 6),
            Text(
              _filterLabel(filter),
              style: TextStyle(
                color: selected
                    ? context.colors.onPrimary
                    : context.colors.onSurface,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (count > 0) ...<Widget>[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5.5,
                  vertical: 1.5,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? context.colors.onPrimary.withValues(alpha: .18)
                      : context.colors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: selected
                        ? context.colors.onPrimary
                        : context.colors.onSurfaceVariant,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _filterLabel(LibraryFilter filter) => switch (filter) {
  LibraryFilter.all => 'All',
  LibraryFilter.working => 'In progress',
  LibraryFilter.ready => 'Ready',
  LibraryFilter.failed => 'Needs attention',
};

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
    void organize() => unawaited(
      _showGenerationOrganizer(
        context,
        controller: widget.controller,
        item: item,
      ),
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
        onOrganize: organize,
        onDelete: () => unawaited(_remove()),
        onCopyToDrive: copyToDrive,
      );
    }
    if (widget.viewMode == GenerationViewMode.mini) {
      return MiniGenerationCard(
        controller: widget.controller,
        item: item,
        onOrganize: organize,
        onDelete: () => unawaited(_remove()),
        onCopyToDrive: copyToDrive,
      );
    }
    final folder = widget.controller.folderById(item.folderId);
    final hasMedia = item.resultAsset != null || item.resultUrl != null;
    final isGeneratingVideo = !hasMedia && item.isWorking && !item.isImage;
    final preview = Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (hasMedia)
          GenerationMedia(controller: widget.controller, item: item)
        else if (isGeneratingVideo)
          GenerationLoadingPlaceholder(
            item: item,
            style: widget.controller.generationPlaceholderStyle,
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
              value: item.progress == null ? null : item.progress! / 100,
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
            child: isGeneratingVideo
                ? AspectRatio(
                    aspectRatio: generationAspectRatio(item.config.aspectRatio),
                    child: preview,
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
                        prompt: item.prompt,
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
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: () => unawaited(
                        _showGenerationOrganizer(
                          context,
                          controller: widget.controller,
                          item: item,
                        ),
                      ),
                      icon: const Icon(Icons.drive_file_move_outline, size: 16),
                      label: const Text('Organize'),
                    ),
                    if (item.resultAsset != null || item.resultUrl != null)
                      FilledButton.tonalIcon(
                        onPressed: saving ? null : () => unawaited(_save()),
                        icon: saving
                            ? const SizedBox.square(
                                dimension: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.download_rounded, size: 16),
                        label: const Text('Save video'),
                      ),
                    if (item.draftCacheUrl != null)
                      OutlinedButton.icon(
                        onPressed: () => widget.controller.enhance(item),
                        icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                        label: const Text('Enhance'),
                      ),
                    if (widget.controller.canReuse(item))
                      OutlinedButton.icon(
                        onPressed: () =>
                            unawaited(widget.controller.reuse(item)),
                        icon: const Icon(Icons.replay_rounded, size: 16),
                        label: Text(
                          item.isFailed ? 'Retry generation' : 'Reuse',
                        ),
                      ),
                    if (item.storage == LibraryStorage.local &&
                        widget.controller.googleDriveConnected)
                      OutlinedButton.icon(
                        onPressed:
                            widget.controller.isCopyingGeneration(item.localId)
                            ? null
                            : () => unawaited(
                                widget.controller.copyLocalLibraryToGoogleDrive(
                                  generationIds: <String>{item.localId},
                                ),
                              ),
                        icon:
                            widget.controller.isCopyingGeneration(item.localId)
                            ? const SizedBox.square(
                                dimension: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.cloud_upload_outlined, size: 16),
                        label: Text(
                          widget.controller.isCopyingGeneration(item.localId)
                              ? 'Copying…'
                              : 'Copy to Drive',
                        ),
                      ),
                    GenerationStatusButton(
                      controller: widget.controller,
                      item: item,
                    ),
                    GenerationDetailsButton(item: item),
                    IconButton.outlined(
                      tooltip: 'Delete history record',
                      onPressed: () => unawaited(_remove()),
                      color: context.colors.error,
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
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

Future<void> _showGenerationOrganizer(
  BuildContext context, {
  required AppController controller,
  required Generation item,
}) async {
  final editor = _GenerationOrganizer(controller: controller, item: item);
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

class _GenerationOrganizer extends StatefulWidget {
  const _GenerationOrganizer({required this.controller, required this.item});

  final AppController controller;
  final Generation item;

  @override
  State<_GenerationOrganizer> createState() => _GenerationOrganizerState();
}

class _GenerationOrganizerState extends State<_GenerationOrganizer> {
  late String? folderId;
  late List<String> tags;
  final tagController = TextEditingController();
  bool saving = false;
  String? tagError;

  @override
  void initState() {
    super.initState();
    folderId = widget.controller.folderById(widget.item.folderId)?.id;
    tags = List<String>.from(widget.item.tags);
  }

  @override
  void dispose() {
    tagController.dispose();
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
    final saved = await widget.controller.organizeGeneration(
      widget.item.localId,
      folderId: folderId,
      tags: tags,
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
    final suggestions = widget.controller.libraryTags
        .where((tag) => !_hasTag(tag))
        .take(8)
        .toList();
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Organize film',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(
            widget.item.prompt,
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
          DropdownButtonFormField<String>(
            initialValue: folderId ?? '',
            decoration: const InputDecoration(
              labelText: 'Folder',
              prefixIcon: Icon(Icons.folder_outlined),
            ),
            items: <DropdownMenuItem<String>>[
              const DropdownMenuItem(value: '', child: Text('Unfiled')),
              ...widget.controller.folderTree
                  .where((folder) => folder.storage == widget.item.storage)
                  .map(
                    (folder) => DropdownMenuItem(
                      value: folder.id,
                      child: Text(
                        widget.controller.folderPath(folder.id),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
            ],
            onChanged: saving
                ? null
                : (value) => setState(
                    () => folderId = value?.isEmpty == true ? null : value,
                  ),
          ),
          const SizedBox(height: 22),
          Text('Tags', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 9),
          if (tags.isNotEmpty) ...<Widget>[
            Wrap(
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
            const SizedBox(height: 10),
          ],
          TextField(
            controller: tagController,
            enabled: !saving,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: 'Add a tag',
              prefixIcon: const Icon(Icons.sell_outlined),
              suffixIcon: IconButton(
                tooltip: 'Add tag',
                onPressed: saving ? null : _addTag,
                icon: const Icon(Icons.add_rounded),
              ),
              errorText: tagError,
              helperText:
                  'Use short labels like client, favorite, or vertical.',
            ),
            onSubmitted: saving ? null : _addTag,
          ),
          if (suggestions.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              'Used elsewhere',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: context.colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 7),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: suggestions
                  .map(
                    (tag) => ActionChip(
                      avatar: const Icon(Icons.add_rounded, size: 14),
                      label: Text('#$tag'),
                      onPressed: saving ? null : () => _addTag(tag),
                    ),
                  )
                  .toList(),
            ),
          ],
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
