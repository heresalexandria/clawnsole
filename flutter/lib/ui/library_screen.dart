import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import '../core/models.dart';
import 'common_widgets.dart';
import 'formatters.dart';
import 'video_save_sheet.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final padding = constraints.maxWidth < 620 ? 16.0 : 28.0;
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
                _LibraryToolbar(controller: controller),
                const SizedBox(height: 18),
                if (controller.filteredGenerations.isEmpty)
                  _LibraryEmpty(controller: controller)
                else
                  LayoutBuilder(
                    builder: (context, grid) {
                      final columns = grid.maxWidth >= 1180
                          ? 3
                          : grid.maxWidth >= 720
                          ? 2
                          : 1;
                      const gap = 16.0;
                      final width =
                          (grid.maxWidth - gap * (columns - 1)) / columns;
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
                                ),
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      );
    },
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
            const Eyebrow('Local history'),
            const SizedBox(height: 10),
            Text(
              'Your films.',
              style: Theme.of(context).textTheme.displayLarge,
            ),
            const SizedBox(height: 10),
            Text(
              'Generation settings, reference inputs, and completed videos stay together on this device.',
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
    LibraryFilter.all => controller.generations.length,
    LibraryFilter.working => controller.workingCount,
    LibraryFilter.ready => controller.readyCount,
    LibraryFilter.failed =>
      controller.generations.where((item) => item.isFailed).length,
  };

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.all(10),
    child: Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: LibraryFilter.values
              .map(
                (filter) => _FilterSegment(
                  filter: filter,
                  count: _count(filter),
                  selected: controller.libraryFilter == filter,
                  onTap: () => unawaited(controller.setLibraryFilter(filter)),
                ),
              )
              .toList(),
        ),
        SizedBox(
          width: 250,
          child: TextField(
            onChanged: controller.setSearch,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded, size: 18),
              hintText: 'Search prompts',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            style: const TextStyle(fontSize: 13),
          ),
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
        decoration: BoxDecoration(
          color: selected
              ? context.colors.primary
              : context.colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? context.colors.primary
                : context.colors.outlineVariant,
          ),
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
                : 'Nothing matches that view.',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            controller.generations.isEmpty
                ? 'Your first generation will arrive here with its settings and live status.'
                : 'Try another filter or a broader prompt search.',
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
  });

  final AppController controller;
  final Generation item;

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
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            child: SizedBox(
              height: 280,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  if (item.resultAsset != null || item.resultUrl != null)
                    GenerationMedia(controller: widget.controller, item: item)
                  else
                    GenerationInputPreview(
                      controller: widget.controller,
                      item: item,
                    ),
                  Positioned(top: 10, left: 10, child: StatusBadge(item: item)),
                  if (item.isWorking && !item.isStatusUnavailable)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: LinearProgressIndicator(
                        value: item.progress == null
                            ? null
                            : item.progress! / 100,
                        minHeight: 5,
                        backgroundColor: Colors.white24,
                        color: ClawnsoleColors.brassBright,
                      ),
                    ),
                ],
              ),
            ),
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
                const SizedBox(height: 11),
                GenerationSpecChips(item: item),
                if (item.config.keyframes?.isNotEmpty == true ||
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
                    OutlinedButton.icon(
                      onPressed: () => unawaited(widget.controller.reuse(item)),
                      icon: const Icon(Icons.replay_rounded, size: 16),
                      label: Text(item.isFailed ? 'Retry generation' : 'Reuse'),
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
