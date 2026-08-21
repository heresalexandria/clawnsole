import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import '../core/models.dart';
import '../core/provider_catalog.dart';
import 'common_widgets.dart';
import 'formatters.dart';
import 'generation_loading_placeholder.dart';
import 'video_save_sheet.dart';

class GenerationViewToggle extends StatelessWidget {
  const GenerationViewToggle({
    required this.value,
    required this.onChanged,
    required this.keyPrefix,
    super.key,
  });

  final GenerationViewMode value;
  final ValueChanged<GenerationViewMode> onChanged;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => Material(
    color: context.colors.surfaceContainer,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(11),
      side: BorderSide(color: context.colors.outlineVariant),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: GenerationViewMode.values.map((mode) {
          final selected = value == mode;
          return Tooltip(
            message: _generationViewModeLabel(mode),
            child: Semantics(
              button: true,
              selected: selected,
              label: _generationViewModeLabel(mode),
              child: InkWell(
                key: ValueKey('$keyPrefix-${mode.name}'),
                onTap: selected ? null : () => onChanged(mode),
                borderRadius: BorderRadius.circular(8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: 34,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? context.colors.primaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    switch (mode) {
                      GenerationViewMode.compact => Icons.view_list_rounded,
                      GenerationViewMode.mini => Icons.grid_view_rounded,
                      GenerationViewMode.full => Icons.view_agenda_rounded,
                    },
                    size: 18,
                    color: selected
                        ? context.colors.onPrimaryContainer
                        : context.colors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    ),
  );
}

String _generationViewModeLabel(GenerationViewMode mode) => switch (mode) {
  GenerationViewMode.compact => 'Compact',
  GenerationViewMode.mini => 'Mini',
  GenerationViewMode.full => 'Full',
};

class MiniGenerationCard extends StatelessWidget {
  const MiniGenerationCard({
    required this.controller,
    required this.item,
    super.key,
    this.onOrganize,
    this.onDelete,
    this.onCopyToDrive,
  });

  final AppController controller;
  final Generation item;
  final VoidCallback? onOrganize;
  final VoidCallback? onDelete;
  final VoidCallback? onCopyToDrive;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    key: ValueKey('generation-mini-${item.localId}'),
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
          child: SizedBox(
            height: 118,
            child: _DenseGenerationPreview(controller: controller, item: item),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 7, 9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              GenerationPrompt(
                controller: controller,
                prompt: item.prompt,
                collapsedLines: 2,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 7),
              Text(
                _denseGenerationSummary(item),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  height: 1.35,
                  fontSize: 10.5,
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 7),
              Row(
                children: <Widget>[
                  StorageBadge(storage: item.storage, compact: true),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      relativeTime(item.createdAt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.5,
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  SizedBox.square(
                    dimension: 31,
                    child: IconButton(
                      tooltip: item.favorite
                          ? 'Remove from favorites'
                          : 'Add to favorites',
                      padding: EdgeInsets.zero,
                      onPressed: () =>
                          unawaited(controller.toggleGenerationFavorite(item)),
                      icon: Icon(
                        item.favorite
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        size: 18,
                        color: item.favorite ? context.tokens.brass : null,
                      ),
                    ),
                  ),
                  GenerationActionsMenu(
                    controller: controller,
                    item: item,
                    onOrganize: onOrganize,
                    onDelete: onDelete,
                    onCopyToDrive: onCopyToDrive,
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

class CompactGenerationRow extends StatelessWidget {
  const CompactGenerationRow({
    required this.controller,
    required this.item,
    super.key,
    this.onOrganize,
    this.onDelete,
    this.onCopyToDrive,
  });

  final AppController controller;
  final Generation item;
  final VoidCallback? onOrganize;
  final VoidCallback? onDelete;
  final VoidCallback? onCopyToDrive;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    key: ValueKey('generation-compact-${item.localId}'),
    padding: const EdgeInsets.all(7),
    child: Row(
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            key: ValueKey('generation-compact-thumbnail-${item.localId}'),
            width: 92,
            height: 68,
            child: _DenseGenerationPreview(controller: controller, item: item),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                item.prompt,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 5),
              Text(
                _denseGenerationSummary(item),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 5),
              Row(
                children: <Widget>[
                  StorageBadge(storage: item.storage, compact: true),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      relativeTime(item.createdAt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.5,
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox.square(
          dimension: 32,
          child: IconButton(
            tooltip: item.favorite
                ? 'Remove from favorites'
                : 'Add to favorites',
            padding: EdgeInsets.zero,
            onPressed: () =>
                unawaited(controller.toggleGenerationFavorite(item)),
            icon: Icon(
              item.favorite ? Icons.star_rounded : Icons.star_border_rounded,
              size: 18,
              color: item.favorite ? context.tokens.brass : null,
            ),
          ),
        ),
        GenerationActionsMenu(
          controller: controller,
          item: item,
          onOrganize: onOrganize,
          onDelete: onDelete,
          onCopyToDrive: onCopyToDrive,
        ),
      ],
    ),
  );
}

class _DenseGenerationPreview extends StatelessWidget {
  const _DenseGenerationPreview({required this.controller, required this.item});

  final AppController controller;
  final Generation item;

  @override
  Widget build(BuildContext context) {
    final hasMedia = item.resultAsset != null || item.resultUrl != null;
    final generatingVideo = !hasMedia && item.isWorking && !item.isImage;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (hasMedia)
          GenerationMedia(controller: controller, item: item)
        else if (generatingVideo)
          GenerationLoadingPlaceholder(item: item)
        else
          GenerationInputPreview(controller: controller, item: item),
        if (item.isWorking && !item.isStatusUnavailable)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              value: item.progress == null ? null : item.progress! / 100,
              minHeight: 4,
              backgroundColor: Colors.white24,
              color: ClawnsoleColors.brassBright,
            ),
          ),
      ],
    );
  }
}

enum _DenseGenerationAction {
  organize,
  save,
  enhance,
  reuse,
  copyToDrive,
  checkStatus,
  details,
  delete,
}

class GenerationActionsMenu extends StatelessWidget {
  const GenerationActionsMenu({
    required this.controller,
    required this.item,
    super.key,
    this.onOrganize,
    this.onDelete,
    this.onCopyToDrive,
    this.includeSave = true,
    this.includeReuse = true,
    this.includeCheckStatus = true,
  });

  final AppController controller;
  final Generation item;
  final VoidCallback? onOrganize;
  final VoidCallback? onDelete;
  final VoidCallback? onCopyToDrive;
  final bool includeSave;
  final bool includeReuse;
  final bool includeCheckStatus;

  List<_DenseGenerationAction> get _actions => <_DenseGenerationAction>[
    if (onOrganize != null) _DenseGenerationAction.organize,
    if (includeSave && (item.resultAsset != null || item.resultUrl != null))
      _DenseGenerationAction.save,
    if (item.draftCacheUrl != null) _DenseGenerationAction.enhance,
    if (includeReuse && controller.canReuse(item)) _DenseGenerationAction.reuse,
    if (onCopyToDrive != null) _DenseGenerationAction.copyToDrive,
    if (includeCheckStatus && item.canCheckStatus && !item.isReady)
      _DenseGenerationAction.checkStatus,
    if (item.hasProviderDetails) _DenseGenerationAction.details,
    if (onDelete != null) _DenseGenerationAction.delete,
  ];

  @override
  Widget build(BuildContext context) {
    final actions = _actions;
    if (actions.isEmpty) return const SizedBox.shrink();
    return SizedBox.square(
      dimension: 32,
      child: PopupMenuButton<_DenseGenerationAction>(
        tooltip: 'Generation actions',
        padding: EdgeInsets.zero,
        iconSize: 19,
        onSelected: (action) {
          switch (action) {
            case _DenseGenerationAction.organize:
              onOrganize?.call();
            case _DenseGenerationAction.save:
              unawaited(saveGenerationVideo(context, controller, item));
            case _DenseGenerationAction.enhance:
              controller.enhance(item);
            case _DenseGenerationAction.reuse:
              unawaited(controller.reuse(item));
            case _DenseGenerationAction.copyToDrive:
              onCopyToDrive?.call();
            case _DenseGenerationAction.checkStatus:
              unawaited(controller.checkStatus(item));
            case _DenseGenerationAction.details:
              unawaited(showGenerationDetails(context, item));
            case _DenseGenerationAction.delete:
              onDelete?.call();
          }
        },
        itemBuilder: (context) => actions.map((action) {
          final copying =
              action == _DenseGenerationAction.copyToDrive &&
              controller.isCopyingGeneration(item.localId);
          return PopupMenuItem<_DenseGenerationAction>(
            value: action,
            enabled: !copying,
            child: Row(
              children: <Widget>[
                Icon(_denseGenerationActionIcon(action), size: 18),
                const SizedBox(width: 10),
                Text(
                  copying
                      ? 'Copying to Drive…'
                      : _denseGenerationActionLabel(action, item),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

IconData _denseGenerationActionIcon(_DenseGenerationAction action) =>
    switch (action) {
      _DenseGenerationAction.organize => Icons.drive_file_move_outline,
      _DenseGenerationAction.save => Icons.download_rounded,
      _DenseGenerationAction.enhance => Icons.auto_fix_high_rounded,
      _DenseGenerationAction.reuse => Icons.replay_rounded,
      _DenseGenerationAction.copyToDrive => Icons.cloud_upload_outlined,
      _DenseGenerationAction.checkStatus => Icons.sync_rounded,
      _DenseGenerationAction.details => Icons.receipt_long_rounded,
      _DenseGenerationAction.delete => Icons.delete_outline_rounded,
    };

String _denseGenerationActionLabel(
  _DenseGenerationAction action,
  Generation item,
) => switch (action) {
  _DenseGenerationAction.organize => 'Organize',
  _DenseGenerationAction.save => item.isImage ? 'Save image' : 'Save video',
  _DenseGenerationAction.enhance => 'Enhance',
  _DenseGenerationAction.reuse => item.isFailed ? 'Retry generation' : 'Reuse',
  _DenseGenerationAction.copyToDrive => 'Copy to Drive',
  _DenseGenerationAction.checkStatus => 'Check status',
  _DenseGenerationAction.details => 'View details',
  _DenseGenerationAction.delete => 'Delete history record',
};

String _denseGenerationSummary(Generation item) {
  final duration = item.config.duration == 'auto'
      ? 'Auto duration'
      : '${item.config.duration}s';
  final kind = item.isImage
      ? 'Image'
      : item.provider == 'apple-local'
      ? 'Frame animation'
      : item.mode.shortLabel;
  return '${providerShortNameForHistory(item.provider)} · $kind · '
      '${item.config.aspectRatio} · $duration';
}
