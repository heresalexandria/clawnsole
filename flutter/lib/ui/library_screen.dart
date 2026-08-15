import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import '../core/models.dart';
import 'common_widgets.dart';
import 'formatters.dart';

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
            const Eyebrow('Local history', icon: Icons.video_library_rounded),
            const SizedBox(height: 10),
            Text(
              'Your films.',
              style: Theme.of(context).textTheme.displayLarge,
            ),
            const SizedBox(height: 10),
            const Text(
              'Generation metadata, reference inputs, and completed videos stay together on this device.',
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

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.all(11),
    child: Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: LibraryFilter.values
              .map(
                (filter) => ChoiceChip(
                  label: Text(_filterLabel(filter)),
                  selected: controller.libraryFilter == filter,
                  selectedColor: ClawnsoleColors.forest,
                  labelStyle: TextStyle(
                    color: controller.libraryFilter == filter
                        ? Colors.white
                        : ClawnsoleColors.ink,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                  side: BorderSide.none,
                  onSelected: (_) =>
                      unawaited(controller.setLibraryFilter(filter)),
                ),
              )
              .toList(),
        ),
        SizedBox(
          width: 260,
          child: TextField(
            onChanged: controller.setSearch,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded, size: 18),
              hintText: 'Search prompts',
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
        ),
      ],
    ),
  );
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
          const Icon(
            Icons.collections_outlined,
            size: 48,
            color: ClawnsoleColors.clay,
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
      await widget.controller.saveVideo(widget.item);
    } on Object catch (error) {
      widget.controller.showNotice(error.toString());
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
          'This removes compact history only. It does not cancel work already submitted to BFL.',
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
            borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
            child: SizedBox(
              height: 220,
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
                  if (item.isWorking)
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
                        color: ClawnsoleColors.mustard,
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
                  children: <Widget>[
                    Text(
                      item.mode.label.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 8,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w900,
                        color: ClawnsoleColors.clayDark,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      relativeTime(item.createdAt),
                      style: const TextStyle(fontSize: 9),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  item.prompt,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 11),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    _ConfigTag(item.config.aspectRatio),
                    _ConfigTag(
                      item.config.duration == 'auto'
                          ? 'Auto'
                          : '${item.config.duration}s',
                    ),
                    _ConfigTag(item.config.resolution.toUpperCase()),
                    if (item.config.generateAudio)
                      const _ConfigTag('Audio', icon: Icons.graphic_eq_rounded),
                  ],
                ),
                const SizedBox(height: 11),
                GenerationCost(item: item),
                if (item.error != null) ...<Widget>[
                  const SizedBox(height: 9),
                  Text(
                    item.error!,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ClawnsoleColors.danger,
                      fontSize: 9,
                    ),
                  ),
                ],
                if (item.deliveryExpired) ...<Widget>[
                  const SizedBox(height: 9),
                  const Text(
                    'BFL’s delivery link expired; the generation record remains.',
                    style: TextStyle(fontSize: 9, color: ClawnsoleColors.muted),
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
                      label: const Text('Reuse'),
                    ),
                    IconButton.outlined(
                      tooltip: 'Delete history record',
                      onPressed: () => unawaited(_remove()),
                      color: ClawnsoleColors.danger,
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

class _ConfigTag extends StatelessWidget {
  const _ConfigTag(this.label, {this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: ClawnsoleColors.cream,
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: ClawnsoleColors.line),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: 11),
          const SizedBox(width: 4),
        ],
        Text(
          label,
          style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}
