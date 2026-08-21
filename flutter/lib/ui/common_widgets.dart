import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import '../core/models.dart';
import '../core/pricing.dart';
import '../core/provider_catalog.dart';
import '../core/shell_bridge.dart';
import 'formatters.dart';
import 'generation_loading_placeholder.dart';
import 'generation_video.dart';
import 'generation_view_widgets.dart';
import 'inline_video.dart';
import 'media_thumbnail.dart';
import 'video_frame_loader.dart';
import 'video_frame_timeline.dart';
import 'video_save_sheet.dart';

class StorageBadge extends StatelessWidget {
  const StorageBadge({required this.storage, super.key, this.compact = false});

  final LibraryStorage storage;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: compact ? 7 : 9,
      vertical: compact ? 3 : 5,
    ),
    decoration: BoxDecoration(
      color: storage == LibraryStorage.drive
          ? context.colors.primaryContainer.withValues(alpha: .72)
          : context.colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: context.colors.outlineVariant),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          storage == LibraryStorage.drive
              ? Icons.cloud_outlined
              : Icons.devices_outlined,
          size: compact ? 12 : 14,
        ),
        const SizedBox(width: 5),
        Text(
          storage.shortLabel,
          style: TextStyle(
            fontSize: compact ? 9.5 : 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

/// Reloads the connected Google Drive library from its source of truth.
///
/// Screens keep this action near their primary controls so work changed on a
/// second device can be pulled in without detouring through Settings.
class DriveRefreshButton extends StatelessWidget {
  const DriveRefreshButton({
    required this.controller,
    required this.keyPrefix,
    super.key,
    this.compact = false,
  });

  final AppController controller;
  final String keyPrefix;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final configured = controller.googleDriveConnection.isConfigured;
    final busy = controller.googleDriveBusy;
    final callback = configured && !busy
        ? () => unawaited(controller.refreshGoogleDrive())
        : null;
    final tooltip = configured
        ? 'Refresh from Google Drive'
        : 'Connect Google Drive in Settings to refresh';
    final icon = busy
        ? const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.refresh_rounded, size: 18);
    if (compact) {
      return IconButton.outlined(
        key: ValueKey('$keyPrefix-drive-refresh'),
        tooltip: tooltip,
        onPressed: callback,
        icon: icon,
      );
    }
    return Tooltip(
      message: tooltip,
      child: OutlinedButton.icon(
        key: ValueKey('$keyPrefix-drive-refresh'),
        onPressed: callback,
        icon: icon,
        label: const Text('Refresh'),
      ),
    );
  }
}

class StorageFilterChips extends StatelessWidget {
  const StorageFilterChips({
    required this.value,
    required this.onChanged,
    super.key,
    this.showLocal = true,
  });

  final LibraryStorageFilter value;
  final ValueChanged<LibraryStorageFilter> onChanged;
  final bool showLocal;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: LibraryStorageFilter.values
        .where((filter) => showLocal || filter != LibraryStorageFilter.local)
        .map(
          (filter) => FilterChip(
            avatar: Icon(switch (filter) {
              LibraryStorageFilter.all => Icons.layers_outlined,
              LibraryStorageFilter.local => Icons.devices_outlined,
              LibraryStorageFilter.drive => Icons.cloud_outlined,
            }, size: 15),
            label: Text(switch (filter) {
              LibraryStorageFilter.all => 'All storage',
              LibraryStorageFilter.local => 'Local',
              LibraryStorageFilter.drive => 'Drive',
            }),
            selected: value == filter,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => onChanged(filter),
          ),
        )
        .toList(),
  );
}

class StorageDestinationButton extends StatelessWidget {
  const StorageDestinationButton({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final destination = controller.effectiveStorage;
    return PopupMenuButton<LibraryStorage>(
      tooltip: 'Choose where new items are saved',
      onSelected: (value) => unawaited(controller.setDefaultStorage(value)),
      itemBuilder: (context) => <PopupMenuEntry<LibraryStorage>>[
        if (controller.supportsLocalLibrary)
          const PopupMenuItem<LibraryStorage>(
            value: LibraryStorage.local,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.devices_outlined),
              title: Text('On this device'),
              subtitle: Text('Private to this installation'),
            ),
          ),
        if (controller.supportsGoogleDrive)
          PopupMenuItem<LibraryStorage>(
            value: LibraryStorage.drive,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.cloud_outlined),
              title: const Text('Google Drive'),
              subtitle: Text(
                controller.googleDriveConnected
                    ? 'Available across connected devices'
                    : 'Connect Drive in Settings first',
              ),
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: context.colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.colors.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              destination == LibraryStorage.drive
                  ? Icons.cloud_outlined
                  : Icons.devices_outlined,
              size: 17,
              color: context.colors.primary,
            ),
            const SizedBox(width: 7),
            Text(
              'Save to ${destination.shortLabel}',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more_rounded, size: 17),
          ],
        ),
      ),
    );
  }
}

class FavoriteFilterChips extends StatelessWidget {
  const FavoriteFilterChips({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final FavoriteFilter value;
  final ValueChanged<FavoriteFilter> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: FavoriteFilter.values
        .map(
          (filter) => FilterChip(
            avatar: Icon(
              filter == FavoriteFilter.starred
                  ? Icons.star_rounded
                  : filter == FavoriteFilter.unstarred
                  ? Icons.star_border_rounded
                  : Icons.select_all_rounded,
              size: 15,
            ),
            label: Text(filter.label),
            selected: value == filter,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => onChanged(filter),
          ),
        )
        .toList(),
  );
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      if (icon != null) ...<Widget>[
        Icon(icon, size: 14, color: context.tokens.brass),
        const SizedBox(width: 7),
      ],
      Text(
        text.toUpperCase(),
        style: TextStyle(
          color: context.tokens.brass,
          fontSize: 10.5,
          letterSpacing: 2,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(18),
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color ?? context.colors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.colors.outlineVariant),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: context.colors.shadow.withValues(alpha: .06),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
}

/// A small on/off pill used for optional behaviors like exact timing.
class TogglePill extends StatelessWidget {
  const TogglePill({
    required this.label,
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return Opacity(
      opacity: enabled ? 1 : .45,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: enabled ? () => onChanged!(!selected) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? context.colors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? context.colors.primary
                  : context.colors.outline.withValues(alpha: .6),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                selected
                    ? Icons.check_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 13,
                color: selected
                    ? context.colors.onPrimary
                    : context.colors.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
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
  }
}

/// A generation's prompt with a one-tap copy action; long prompts collapse
/// and expand in place so the whole direction is always reachable.
class GenerationPrompt extends StatefulWidget {
  const GenerationPrompt({
    required this.controller,
    required this.prompt,
    super.key,
    this.collapsedLines = 3,
    this.style,
  });

  final AppController controller;
  final String prompt;
  final int collapsedLines;
  final TextStyle? style;

  @override
  State<GenerationPrompt> createState() => _GenerationPromptState();
}

class _GenerationPromptState extends State<GenerationPrompt> {
  bool _expanded = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.prompt));
    widget.controller.showNotice('Prompt copied to the clipboard.');
  }

  @override
  Widget build(BuildContext context) {
    final style =
        widget.style ??
        Theme.of(context).textTheme.titleMedium ??
        const TextStyle();
    final linkColor = Theme.of(context).brightness == Brightness.dark
        ? context.colors.tertiary
        : context.colors.primary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = (constraints.maxWidth - 36).clamp(
          0.0,
          double.infinity,
        );
        final painter = TextPainter(
          text: TextSpan(text: widget.prompt, style: style),
          maxLines: widget.collapsedLines,
          textDirection: TextDirection.ltr,
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: available);
        final truncated = painter.didExceedMaxLines;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    widget.prompt,
                    maxLines: _expanded ? null : widget.collapsedLines,
                    overflow: _expanded ? null : TextOverflow.ellipsis,
                    style: style,
                  ),
                  if (truncated || _expanded)
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => setState(() => _expanded = !_expanded),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          _expanded ? 'Show less' : 'Show full prompt',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: linkColor,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Copy prompt',
              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
              padding: EdgeInsets.zero,
              onPressed: () => unawaited(_copy()),
              icon: Icon(
                Icons.copy_rounded,
                size: 15,
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
        );
      },
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({required this.item, super.key});

  final Generation item;

  @override
  Widget build(BuildContext context) {
    // A delivered thumbnail already says "ready" — no chip needed.
    if (item.isReady) return const SizedBox.shrink();
    final (background, foreground) = item.isStatusUnavailable
        ? (context.colors.errorContainer, context.colors.onErrorContainer)
        : item.isWorking
        ? (
            context.colors.secondaryContainer,
            context.colors.onSecondaryContainer,
          )
        : item.isFailed
        ? (context.colors.errorContainer, context.colors.onErrorContainer)
        : item.isReady
        ? (context.colors.primaryContainer, context.colors.onPrimaryContainer)
        : (
            context.colors.tertiaryContainer,
            context.colors.onTertiaryContainer,
          );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5.5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (item.isStatusUnavailable) ...<Widget>[
            Icon(Icons.cloud_off_rounded, size: 12, color: foreground),
            const SizedBox(width: 5),
          ] else if (item.isWorking) ...<Widget>[
            SizedBox.square(
              dimension: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: foreground,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            item.statusLabel,
            style: TextStyle(
              fontSize: 10,
              letterSpacing: .3,
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Every setting used for a generation, shown as compact chips.
class GenerationSpecChips extends StatelessWidget {
  const GenerationSpecChips({required this.item, super.key});

  final Generation item;

  @override
  Widget build(BuildContext context) {
    final config = item.config;
    final upscaling = item.mode == VideoMode.upscale;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        _SpecChip(label: providerNameForHistory(item.provider)),
        _SpecChip(
          label: item.isImage
              ? (item.mode == VideoMode.i2v
                    ? 'Reference to image'
                    : 'Text to image')
              : item.provider == 'apple-local'
              ? 'Retired frame animation'
              : item.mode.label,
        ),
        if (!upscaling && config.referenceTask != MediaReferenceTask.reference)
          _SpecChip(
            icon: config.referenceTask == MediaReferenceTask.edit
                ? Icons.auto_fix_high_rounded
                : Icons.more_time_rounded,
            label: config.referenceTask.label,
          ),
        if (!upscaling)
          _SpecChip(
            label: config.aspectRatio == 'auto' ? 'Auto' : config.aspectRatio,
            leading: _MiniRatioGlyph(ratio: config.aspectRatio),
          ),
        if (!item.isImage && !upscaling)
          _SpecChip(
            icon: Icons.timelapse_rounded,
            label: config.duration == 'auto' ? 'Auto' : '${config.duration} s',
          ),
        if (item.provider == 'apple-local' && !item.isImage)
          _SpecChip(
            icon: Icons.animation_rounded,
            label: '${config.frameRate} fps',
          ),
        if (!upscaling)
          _SpecChip(
            label: switch (config.resolution) {
              'fhd' => item.provider == 'apple-local' ? '768 px' : 'Full HD',
              'qhd' => '1440p',
              '4k' => '4K',
              _ => item.provider == 'apple-local' ? '512 px' : 'HD',
            },
          ),
        if (upscaling) ...<Widget>[
          _SpecChip(
            icon: Icons.zoom_out_map_rounded,
            label:
                '${config.upscaleFactor == config.upscaleFactor.roundToDouble() ? config.upscaleFactor.toStringAsFixed(0) : config.upscaleFactor.toStringAsFixed(1)}×',
          ),
          _SpecChip(
            icon: config.upscaleCreativity == 0
                ? Icons.center_focus_strong_rounded
                : Icons.auto_awesome_rounded,
            label: config.upscaleCreativity == 0 ? 'Precise' : 'Creative',
          ),
          const _SpecChip(
            icon: Icons.graphic_eq_rounded,
            label: 'Audio preserved',
          ),
        ],
        if (config.generateAudio)
          const _SpecChip(icon: Icons.graphic_eq_rounded, label: 'Audio'),
        if (config.draft)
          const _SpecChip(icon: Icons.bolt_rounded, label: 'Draft tier'),
        if (config.exactTiming)
          const _SpecChip(icon: Icons.schedule_rounded, label: 'Timed'),
      ],
    );
  }
}

class _SpecChip extends StatelessWidget {
  const _SpecChip({required this.label, this.icon, this.leading});

  final String label;
  final IconData? icon;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: context.colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: context.colors.outlineVariant),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (leading != null) ...<Widget>[
          leading!,
          const SizedBox(width: 5),
        ] else if (icon != null) ...<Widget>[
          Icon(icon, size: 12, color: context.colors.onSurfaceVariant),
          const SizedBox(width: 4),
        ],
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: context.colors.onSurface.withValues(alpha: .85),
          ),
        ),
      ],
    ),
  );
}

class _MiniRatioGlyph extends StatelessWidget {
  const _MiniRatioGlyph({required this.ratio});

  final String ratio;

  @override
  Widget build(BuildContext context) {
    final color = context.colors.onSurfaceVariant;
    if (ratio == 'auto') {
      return Icon(Icons.crop_free_rounded, size: 12, color: color);
    }
    final parts = ratio.split(':');
    final aspect =
        (double.tryParse(parts.first) ?? 1) /
        (double.tryParse(parts.last) ?? 1);
    final width = aspect >= 1 ? 15.0 : 10.0 * aspect;
    final height = aspect >= 1 ? 15.0 / aspect : 10.0;
    return Container(
      width: width,
      height: height.clamp(5, 10),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1.2),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// Thumbnails of the reference inputs a generation was made from. Tapping a
/// frame opens it at full resolution with a download action.
class ReferenceInputsStrip extends StatelessWidget {
  const ReferenceInputsStrip({
    required this.controller,
    required this.item,
    super.key,
  });

  final AppController controller;
  final Generation item;

  @override
  Widget build(BuildContext context) {
    final frames = item.config.keyframes ?? const <KeyframeLabel>[];
    final references = item.config.references ?? const <MediaReferenceLabel>[];
    final source = item.config.source;
    if (frames.isEmpty && references.isEmpty && source == null) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        ...frames.map(
          (frame) => _ReferenceThumb(controller: controller, frame: frame),
        ),
        ...references.map(
          (media) => _MediaReferenceChip(
            controller: controller,
            item: item,
            media: media,
          ),
        ),
        if (source != null)
          _SourceReferenceChip(
            controller: controller,
            item: item,
            source: source,
            mode: item.mode,
            thumbnailAsset: item.config.sourceThumbnailAsset,
          ),
      ],
    );
  }
}

class _MediaReferenceChip extends StatelessWidget {
  const _MediaReferenceChip({
    required this.controller,
    required this.item,
    required this.media,
  });

  final AppController controller;
  final Generation item;
  final MediaReferenceLabel media;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: '${media.kind.label} reference · ${media.label}',
    child: Container(
      height: 44,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox.square(
            dimension: 42,
            child: MediaThumbnail(
              gateway: controller.gateway,
              kind: media.kind,
              reference: media.source,
              thumbnailReference: media.thumbnailAsset,
              semanticsLabel: '${media.label} reference thumbnail',
              onThumbnail:
                  media.kind == MediaReferenceKind.video && media.source != null
                  ? (bytes) => unawaited(
                      controller.cacheGenerationInputPreview(
                        item,
                        media.source!,
                        bytes,
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 110),
            child: Text(
              media.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
      ),
    ),
  );
}

class _ReferenceThumb extends StatefulWidget {
  const _ReferenceThumb({required this.controller, required this.frame});

  final AppController controller;
  final KeyframeLabel frame;

  @override
  State<_ReferenceThumb> createState() => _ReferenceThumbState();
}

class _ReferenceThumbState extends State<_ReferenceThumb> {
  Future<Uint8List>? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _ReferenceThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.frame.source?.value != widget.frame.source?.value) _load();
  }

  void _load() {
    final source = widget.frame.source;
    _bytes = source == null
        ? null
        : widget.controller.gateway.readAsset(source);
  }

  @override
  Widget build(BuildContext context) {
    final frame = widget.frame;
    final timing = frame.seconds == null
        ? ''
        : ' · at ${frame.seconds!.toStringAsFixed(frame.seconds! % 1 == 0 ? 0 : 1)} s';
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ghostForeground = dark
        ? ClawnsoleColors.creamMuted
        : context.colors.onSurfaceVariant;
    return Tooltip(
      message: '${frame.role.label}$timing — tap to view',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => unawaited(
          showReferenceFrameViewer(context, widget.controller, frame),
        ),
        child: Container(
          width: 44,
          height: 44,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: dark
                ? ClawnsoleColors.plumInk
                : context.colors.surfaceContainer,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.colors.outlineVariant),
          ),
          child: _bytes == null
              ? Icon(Icons.image_outlined, size: 16, color: ghostForeground)
              : FutureBuilder<Uint8List>(
                  future: _bytes,
                  builder: (context, snapshot) => snapshot.hasData
                      ? Image.memory(
                          snapshot.data!,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        )
                      : Icon(
                          snapshot.hasError
                              ? Icons.broken_image_outlined
                              : Icons.image_outlined,
                          size: 16,
                          color: ghostForeground,
                        ),
                ),
        ),
      ),
    );
  }
}

class _SourceReferenceChip extends StatelessWidget {
  const _SourceReferenceChip({
    required this.controller,
    required this.item,
    required this.source,
    required this.mode,
    required this.thumbnailAsset,
  });

  final AppController controller;
  final Generation item;
  final AssetReference source;
  final VideoMode mode;
  final AssetReference? thumbnailAsset;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: source.label,
    child: InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => unawaited(
        showSourceReferenceSheet(context, controller, source, mode),
      ),
      child: Container(
        height: 44,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: context.colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.colors.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox.square(
              dimension: 42,
              child: mode == VideoMode.v2v || mode == VideoMode.upscale
                  ? MediaThumbnail(
                      gateway: controller.gateway,
                      kind: MediaReferenceKind.video,
                      reference: source,
                      thumbnailReference: thumbnailAsset,
                      semanticsLabel: mode == VideoMode.upscale
                          ? 'Video to upscale thumbnail'
                          : 'Starting video thumbnail',
                      onThumbnail: (bytes) => unawaited(
                        controller.cacheGenerationInputPreview(
                          item,
                          source,
                          bytes,
                        ),
                      ),
                    )
                  : Icon(
                      Icons.auto_fix_high_rounded,
                      size: 17,
                      color: context.colors.onSurfaceVariant,
                    ),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Text(
                source.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
        ),
      ),
    ),
  );
}

Future<void> showReferenceFrameViewer(
  BuildContext context,
  AppController controller,
  KeyframeLabel frame,
) {
  final source = frame.source;
  final timing = frame.seconds == null
      ? null
      : 'at ${frame.seconds!.toStringAsFixed(frame.seconds! % 1 == 0 ? 0 : 1)} s';
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 8, 12),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Eyebrow(
                          timing == null
                              ? frame.role.label
                              : '${frame.role.label} · $timing',
                        ),
                        const SizedBox(height: 4),
                        Text(
                          frame.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: Container(
                color: ClawnsoleColors.plumInk,
                constraints: const BoxConstraints(minHeight: 220),
                child: source == null
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(30),
                          child: Text(
                            'This frame was submitted inline and was not retained.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: ClawnsoleColors.creamMuted),
                          ),
                        ),
                      )
                    : _FullResReference(controller: controller, source: source),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: <Widget>[
                  if (source != null && !source.isLocal)
                    OutlinedButton.icon(
                      onPressed: () => unawaited(
                        openExternalUrl(
                          Uri.parse(source.value),
                          purpose: ExternalUrlPurpose.media,
                        ),
                      ),
                      icon: const Icon(Icons.open_in_new_rounded, size: 15),
                      label: const Text('Open link'),
                    ),
                  if (source != null)
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        try {
                          await controller.saveReferenceImage(source);
                        } on Object catch (error) {
                          controller.showErrorNotice(error);
                        }
                      },
                      icon: const Icon(Icons.download_rounded, size: 16),
                      label: const Text('Download'),
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

class _FullResReference extends StatefulWidget {
  const _FullResReference({required this.controller, required this.source});

  final AppController controller;
  final AssetReference source;

  @override
  State<_FullResReference> createState() => _FullResReferenceState();
}

class _FullResReferenceState extends State<_FullResReference> {
  late final Future<Uint8List> _bytes = widget.controller.gateway.readAsset(
    widget.source,
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _bytes,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: Text(
              'The full-resolution file could not be loaded.',
              style: TextStyle(color: ClawnsoleColors.creamMuted),
            ),
          ),
        );
      }
      if (!snapshot.hasData) {
        return const SizedBox(
          height: 220,
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return InteractiveViewer(
        maxScale: 5,
        child: Image.memory(snapshot.data!, fit: BoxFit.contain),
      );
    },
  );
}

Future<void> showSourceReferenceSheet(
  BuildContext context,
  AppController controller,
  AssetReference source,
  VideoMode mode,
) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(switch (mode) {
      VideoMode.draftEnhance => 'Draft cache',
      VideoMode.upscale => 'Video to upscale',
      _ => 'Starting video',
    }),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(source.label),
        if (source.bytes != null) ...<Widget>[
          const SizedBox(height: 5),
          Text(
            formatBytes(source.bytes!),
            style: TextStyle(
              fontSize: 11.5,
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ],
      ],
    ),
    actions: <Widget>[
      if (!source.isLocal)
        OutlinedButton.icon(
          onPressed: () => unawaited(
            openExternalUrl(
              Uri.parse(source.value),
              purpose: ExternalUrlPurpose.media,
            ),
          ),
          icon: const Icon(Icons.open_in_new_rounded, size: 15),
          label: const Text('Open link'),
        ),
      FilledButton.tonalIcon(
        onPressed: () async {
          try {
            await controller.saveReferenceImage(source);
          } on Object catch (error) {
            controller.showErrorNotice(error);
          }
        },
        icon: const Icon(Icons.download_rounded, size: 16),
        label: const Text('Download'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  ),
);

class GenerationStatusDetails extends StatelessWidget {
  const GenerationStatusDetails({required this.item, super.key});

  final Generation item;

  @override
  Widget build(BuildContext context) {
    final problem = item.error ?? item.lastCheckError;
    final isTerminal = item.error != null || item.isFailed;
    final checked = item.lastCheckedAt;
    if (problem == null && checked == null && !item.isLongRunning) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: isTerminal
            ? context.colors.errorContainer
            : context.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isTerminal
              ? context.colors.error.withValues(alpha: .28)
              : context.colors.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (problem != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  isTerminal
                      ? Icons.error_outline_rounded
                      : Icons.sync_problem_rounded,
                  size: 15,
                  color: isTerminal
                      ? context.colors.onErrorContainer
                      : context.colors.onSurfaceVariant,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    problem,
                    style: TextStyle(
                      color: isTerminal
                          ? context.colors.onErrorContainer
                          : context.colors.onSurfaceVariant,
                      fontSize: 11,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          if (item.isLongRunning) ...<Widget>[
            if (problem != null) const SizedBox(height: 6),
            Text(
              'This render has been in progress for more than 30 minutes. You can ask the provider for a fresh status below.',
              style: TextStyle(
                color: context.colors.onSurfaceVariant,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
          if (item.isStatusUnavailable) ...<Widget>[
            if (problem != null) const SizedBox(height: 6),
            Text(
              'The provider has not confirmed that this generation is still in progress. Retry the status check below.',
              style: TextStyle(
                color: context.colors.onSurfaceVariant,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
          if (checked != null) ...<Widget>[
            if (problem != null || item.isLongRunning)
              const SizedBox(height: 6),
            Text(
              'Provider checked ${relativeTime(checked)} · ${item.statusCheckCount} ${item.statusCheckCount == 1 ? 'check' : 'checks'}',
              style: TextStyle(
                color: isTerminal
                    ? context.colors.onErrorContainer.withValues(alpha: .75)
                    : context.colors.onSurfaceVariant,
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class GenerationStatusButton extends StatelessWidget {
  const GenerationStatusButton({
    required this.controller,
    required this.item,
    super.key,
    this.compact = false,
  });

  final AppController controller;
  final Generation item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!item.canCheckStatus || item.isReady) return const SizedBox.shrink();
    final checking = controller.isCheckingStatus(item.localId);
    return OutlinedButton.icon(
      onPressed: checking
          ? null
          : () => unawaited(controller.checkStatus(item)),
      icon: checking
          ? const SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.sync_rounded, size: 15),
      label: Text(
        checking
            ? 'Checking…'
            : item.lastCheckError != null
            ? 'Retry status'
            : item.isFailed
            ? 'Retry status'
            : compact
            ? 'Check now'
            : 'Check status',
      ),
    );
  }
}

class GenerationDetailsButton extends StatelessWidget {
  const GenerationDetailsButton({required this.item, super.key});

  final Generation item;

  @override
  Widget build(BuildContext context) {
    if (!item.hasProviderDetails) return const SizedBox.shrink();
    return OutlinedButton.icon(
      onPressed: () => showGenerationDetails(context, item),
      icon: const Icon(Icons.receipt_long_rounded, size: 15),
      label: const Text('View details'),
    );
  }
}

Future<void> showGenerationDetails(BuildContext context, Generation item) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Generation details'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _GenerationDetailLine(label: 'State', value: item.statusLabel),
                _GenerationDetailLine(
                  label: 'Provider',
                  value: item.provider.toUpperCase(),
                ),
                _GenerationDetailLine(label: 'Model', value: item.model),
                if (item.requestId != null)
                  _GenerationDetailLine(
                    label: 'Request ID',
                    value: item.requestId!,
                  ),
                if (item.lastProviderStatusCode != null)
                  _GenerationDetailLine(
                    label: 'HTTP status',
                    value: item.lastProviderStatusCode.toString(),
                  ),
                if (item.lastProviderResponseAt != null)
                  _GenerationDetailLine(
                    label: 'Response received',
                    value: formatTimestamp(item.lastProviderResponseAt!),
                  ),
                if (item.error != null) ...<Widget>[
                  const SizedBox(height: 14),
                  const Eyebrow('Error', icon: Icons.error_outline_rounded),
                  const SizedBox(height: 7),
                  SelectableText(item.error!),
                ],
                if (item.lastCheckError != null) ...<Widget>[
                  const SizedBox(height: 14),
                  const Eyebrow(
                    'Last status-check error',
                    icon: Icons.sync_problem_rounded,
                  ),
                  const SizedBox(height: 7),
                  SelectableText(item.lastCheckError!),
                ],
                if (item.lastProviderResponse != null) ...<Widget>[
                  const SizedBox(height: 14),
                  const Eyebrow(
                    'Provider response',
                    icon: Icons.data_object_rounded,
                  ),
                  const SizedBox(height: 7),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: context.colors.outlineVariant),
                    ),
                    child: SelectableText(
                      item.lastProviderResponse!,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );

class _GenerationDetailLine extends StatelessWidget {
  const _GenerationDetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: TextStyle(
              color: context.colors.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(child: SelectableText(value)),
      ],
    ),
  );
}

class GenerationMedia extends StatefulWidget {
  const GenerationMedia({
    required this.controller,
    required this.item,
    super.key,
  });

  final AppController controller;
  final Generation item;

  @override
  State<GenerationMedia> createState() => _GenerationMediaState();
}

class _GenerationMediaState extends State<GenerationMedia> {
  late Future<Uri?> _uri;
  Future<Uint8List>? _imageBytes;

  void _load() {
    // Resolving a Drive-stored film downloads the whole file on native
    // surfaces, so the URI future is deferred: work starts on the first
    // await (a play tap), never at listing build for every visible card.
    final item = widget.item;
    _uri = _DeferredFuture<Uri?>(
      () => widget.controller.generationMediaUri(item),
    );
    _imageBytes = widget.item.isImage
        ? widget.item.resultAsset != null
              ? widget.controller.gateway.readAsset(widget.item.resultAsset!)
              : widget.item.resultUrl != null
              ? widget.controller.gateway.downloadMedia(widget.item.resultUrl!)
              : null
        : null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant GenerationMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.resultUrl != widget.item.resultUrl ||
        oldWidget.item.resultAsset?.value != widget.item.resultAsset?.value) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.item.isImage) {
      final bytes = _imageBytes;
      if (bytes == null) {
        return const _MediaPlaceholder(
          icon: Icons.broken_image_outlined,
          label: 'Image unavailable',
        );
      }
      return FutureBuilder<Uint8List>(
        future: bytes,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const _MediaPlaceholder(
              icon: Icons.broken_image_outlined,
              label: 'Image unavailable',
            );
          }
          if (!snapshot.hasData) {
            return const _MediaPlaceholder(
              icon: Icons.hourglass_bottom_rounded,
              label: 'Loading image',
            );
          }
          return Image.memory(snapshot.data!, fit: BoxFit.contain);
        },
      );
    }
    return _CachedVideoPreview(
      controller: widget.controller,
      item: widget.item,
      uri: _uri,
    );
  }
}

final Map<String, Future<Uint8List>> _previewAssetBytes =
    <String, Future<Uint8List>>{};
final Map<String, Future<_GeneratedVideoPreview?>> _previewJobs =
    <String, Future<_GeneratedVideoPreview?>>{};

class _GeneratedVideoPreview {
  const _GeneratedVideoPreview({required this.thumbnail, this.timeline});

  final Uint8List thumbnail;
  final Uint8List? timeline;
}

class _CachedVideoPreview extends StatefulWidget {
  const _CachedVideoPreview({
    required this.controller,
    required this.item,
    required this.uri,
  });

  final AppController controller;
  final Generation item;
  final Future<Uri?> uri;

  @override
  State<_CachedVideoPreview> createState() => _CachedVideoPreviewState();
}

class _CachedVideoPreviewState extends State<_CachedVideoPreview> {
  Future<_GeneratedVideoPreview?>? _preview;

  String get _jobKey =>
      '${widget.item.storage.name}:${widget.item.localId}:${widget.item.resultAsset?.value ?? widget.item.resultUrl}';

  Future<Uint8List> _read(AssetReference reference) {
    final key = '${reference.kind}:${reference.value}';
    final existing = _previewAssetBytes[key];
    if (existing != null) return existing;
    late final Future<Uint8List> job;
    job = widget.controller.gateway.readAsset(reference).catchError((
      Object error,
    ) {
      if (identical(_previewAssetBytes[key], job)) {
        _previewAssetBytes.remove(key);
      }
      throw error;
    });
    _previewAssetBytes[key] = job;
    return job;
  }

  Future<_GeneratedVideoPreview?> _previewJob(String key) {
    final existing = _previewJobs[key];
    if (existing != null) return existing;
    late final Future<_GeneratedVideoPreview?> job;
    job = _generateAndCache().then((preview) {
      if (preview == null && identical(_previewJobs[key], job)) {
        _previewJobs.remove(key);
      }
      return preview;
    });
    _previewJobs[key] = job;
    return job;
  }

  void _load() {
    final thumbnail = widget.item.thumbnailAsset;
    if (thumbnail != null) {
      _preview = Future<_GeneratedVideoPreview?>(() async {
        try {
          final thumbnailBytes = await _read(thumbnail);
          Uint8List? timelineBytes;
          final timeline = widget.item.timelineThumbnailAsset;
          if (timeline != null) {
            try {
              timelineBytes = await _read(timeline);
            } on Object {
              // A missing timeline strip must not hide the main thumbnail.
            }
          }
          return _GeneratedVideoPreview(
            thumbnail: thumbnailBytes,
            timeline: timelineBytes,
          );
        } on Object {
          return await _previewJob('$_jobKey:regenerate');
        }
      });
      return;
    }
    _preview = _previewJob(_jobKey);
  }

  Future<_GeneratedVideoPreview?> _generateAndCache() async {
    try {
      // Frame extraction must never force a full Drive download for a card
      // that is merely visible: ask only for a cheap source (cached file,
      // local file, or companion URL). A cold Drive film keeps its
      // tap-to-play placeholder until the cache warms up.
      final uri = await widget.controller.generationPreviewSourceUri(
        widget.item,
      );
      if (uri == null) return null;
      final configured = widget.item.config.duration;
      final seconds = configured is num ? configured.toDouble() : 8.0;
      final duration = Duration(
        milliseconds: (seconds.clamp(1, 120) * 1000).round(),
      );
      final positions = videoTimelinePositions(duration, 6);
      final frames = <Uint8List>[];
      for (final position in positions) {
        final frame = await loadVideoFrame(uri, position);
        if (frame != null) frames.add(frame);
      }
      if (frames.isEmpty) return null;
      final timeline = frames.length > 1
          ? await _composeTimelineStrip(frames)
          : null;
      final preview = _GeneratedVideoPreview(
        thumbnail: frames.first,
        timeline: timeline,
      );
      await widget.controller.cacheGenerationPreviews(
        widget.item,
        thumbnailBytes: preview.thumbnail,
        timelineBytes: preview.timeline,
      );
      return preview;
    } on Object {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _CachedVideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.thumbnailAsset?.value !=
            widget.item.thumbnailAsset?.value ||
        oldWidget.item.timelineThumbnailAsset?.value !=
            widget.item.timelineThumbnailAsset?.value ||
        oldWidget.item.resultAsset?.value != widget.item.resultAsset?.value ||
        oldWidget.item.resultUrl != widget.item.resultUrl) {
      _load();
    }
  }

  Future<void> _download(VideoSaveDestination destination) async {
    try {
      await widget.controller.saveMedia(widget.item, destination: destination);
    } on Object catch (error) {
      widget.controller.showErrorNotice(error);
    }
  }

  Future<void> _open() async {
    // The player surface opens immediately and resolves the delivery inside
    // it, so a cold Drive download animates the loading placeholder (with
    // byte progress) instead of leaving the tap apparently ignored.
    final delivery = widget.controller.generationMediaDelivery(widget.item);
    // A hosting full-view card plays the film in place; previews without one
    // (mini and compact cards, narrow viewports) keep the shared modal.
    final inline = InlineVideoPlayback.of(context);
    if (inline != null) {
      inline(
        InlineVideoRequest(
          deferredUri: delivery.uri,
          progress: delivery.progress,
          onDownload: _download,
          supportsPhotos: widget.controller.supportsPhotoLibrarySave,
        ),
      );
      return;
    }
    await showVideoPlayerModal(
      context,
      deferredUri: delivery.uri,
      progress: delivery.progress,
      supportsPhotos: widget.controller.supportsPhotoLibrarySave,
      initialAspectRatio: generationAspectRatio(widget.item.config.aspectRatio),
      onDownload: _download,
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_GeneratedVideoPreview?>(
    future: _preview,
    builder: (context, snapshot) {
      final preview = snapshot.data;
      if (preview == null) {
        return InkWell(
          onTap: () => unawaited(_open()),
          child: _MediaPlaceholder(
            icon: snapshot.connectionState == ConnectionState.done
                ? Icons.movie_outlined
                : Icons.hourglass_bottom_rounded,
            label: snapshot.connectionState == ConnectionState.done
                ? 'Tap to play video'
                : 'Caching preview',
          ),
        );
      }
      return Semantics(
        button: true,
        label: 'Play generated video',
        child: InkWell(
          onTap: () => unawaited(_open()),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // The filmstrip band scales with its box; short boxes (compact
              // rows and other sub-110px thumbnails) read best as a clean
              // cover frame, so the band disappears there.
              final boxHeight = constraints.maxHeight;
              final showTimeline =
                  preview.timeline != null &&
                  boxHeight.isFinite &&
                  boxHeight >= 110;
              return Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  Image.memory(
                    preview.thumbnail,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                  if (showTimeline)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: (boxHeight * .18).clamp(24.0, 48.0),
                      child: DecoratedBox(
                        key: const ValueKey('generation-video-filmstrip'),
                        decoration: const BoxDecoration(
                          border: Border(
                            top: BorderSide(color: Colors.white30),
                          ),
                        ),
                        child: Image.memory(
                          preview.timeline!,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                  Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .62),
                        shape: BoxShape.circle,
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    },
  );
}

/// A [Future] whose computation starts on the first await/then, not at
/// construction. Lets listing cards hold a playable-URI future without
/// triggering the Drive download it may represent until someone plays it.
class _DeferredFuture<T> implements Future<T> {
  _DeferredFuture(this._compute);

  final Future<T> Function() _compute;
  Future<T>? _started;

  Future<T> get _future => _started ??= _compute();

  @override
  Stream<T> asStream() => _future.asStream();

  @override
  Future<T> catchError(Function onError, {bool Function(Object)? test}) =>
      _future.catchError(onError, test: test);

  @override
  Future<R> then<R>(FutureOr<R> Function(T) onValue, {Function? onError}) =>
      _future.then(onValue, onError: onError);

  @override
  Future<T> timeout(Duration timeLimit, {FutureOr<T> Function()? onTimeout}) =>
      _future.timeout(timeLimit, onTimeout: onTimeout);

  @override
  Future<T> whenComplete(FutureOr<void> Function() action) =>
      _future.whenComplete(action);
}

Future<Uint8List?> _composeTimelineStrip(List<Uint8List> frames) async {
  if (frames.isEmpty) return null;
  final images = <ui.Image>[];
  try {
    for (final bytes in frames) {
      final codec = await ui.instantiateImageCodec(bytes);
      images.add((await codec.getNextFrame()).image);
      codec.dispose();
    }
    const cellWidth = 160.0;
    const height = 90.0;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    for (var index = 0; index < images.length; index += 1) {
      final image = images[index];
      final sourceAspect = image.width / image.height;
      final targetAspect = cellWidth / height;
      final source = sourceAspect > targetAspect
          ? ui.Rect.fromLTWH(
              (image.width - image.height * targetAspect) / 2,
              0,
              image.height * targetAspect,
              image.height.toDouble(),
            )
          : ui.Rect.fromLTWH(
              0,
              (image.height - image.width / targetAspect) / 2,
              image.width.toDouble(),
              image.width / targetAspect,
            );
      canvas.drawImageRect(
        image,
        source,
        ui.Rect.fromLTWH(index * cellWidth, 0, cellWidth, height),
        ui.Paint(),
      );
    }
    final strip = await recorder.endRecording().toImage(
      (cellWidth * images.length).round(),
      height.round(),
    );
    final data = await strip.toByteData(format: ui.ImageByteFormat.png);
    strip.dispose();
    return data?.buffer.asUint8List();
  } finally {
    for (final image in images) {
      image.dispose();
    }
  }
}

class GenerationInputPreview extends StatefulWidget {
  const GenerationInputPreview({
    required this.controller,
    required this.item,
    super.key,
  });

  final AppController controller;
  final Generation item;

  @override
  State<GenerationInputPreview> createState() => _GenerationInputPreviewState();
}

class _GenerationInputPreviewState extends State<GenerationInputPreview> {
  late (MediaReferenceKind, AssetReference, AssetReference?)? _media;

  (MediaReferenceKind, AssetReference, AssetReference?)? _findMedia() {
    for (final media
        in widget.item.config.references ?? const <MediaReferenceLabel>[]) {
      if (media.kind != MediaReferenceKind.audio && media.source != null) {
        return (media.kind, media.source!, media.thumbnailAsset);
      }
    }
    for (final frame
        in widget.item.config.keyframes ?? const <KeyframeLabel>[]) {
      if (frame.source != null) {
        return (MediaReferenceKind.image, frame.source!, null);
      }
    }
    final source = widget.item.config.source;
    if (source == null) return null;
    return (
      source.contentType?.startsWith('image/') == true
          ? MediaReferenceKind.image
          : MediaReferenceKind.video,
      source,
      widget.item.config.sourceThumbnailAsset,
    );
  }

  void _load() {
    _media = _findMedia();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant GenerationInputPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _findMedia();
    if (next?.$2.value != _media?.$2.value ||
        next?.$3?.value != _media?.$3?.value) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = _media;
    if (media == null) {
      return const _MediaPlaceholder(
        icon: Icons.movie_creation_outlined,
        label: 'Saved generation',
      );
    }
    return MediaThumbnail(
      gateway: widget.controller.gateway,
      kind: media.$1,
      reference: media.$2,
      thumbnailReference: media.$3,
      semanticsLabel: 'Generation input thumbnail',
      onThumbnail: media.$1 == MediaReferenceKind.video
          ? (bytes) => unawaited(
              widget.controller.cacheGenerationInputPreview(
                widget.item,
                media.$2,
                bytes,
              ),
            )
          : null,
    );
  }
}

class _MediaPlaceholder extends StatelessWidget {
  const _MediaPlaceholder({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = dark
        ? ClawnsoleColors.creamMuted
        : context.colors.onSurfaceVariant;
    return Container(
      color: dark ? ClawnsoleColors.plumInk : context.colors.surfaceContainer,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: foreground, size: 28),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(color: foreground, fontSize: 11.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GenerationCost extends StatelessWidget {
  const GenerationCost({required this.item, super.key, this.compact = false});

  final Generation item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (item.billingUnit == 'local') return const SizedBox.shrink();
    final minimum = item.cost ?? item.estimatedCreditsMin;
    final maximum = item.cost ?? item.estimatedCreditsMax;
    if (minimum == null || maximum == null) return const SizedBox.shrink();
    final realizedUsd = recordedRealizedCostUsd(item);
    // A failed generation only carries a realized charge when the terminal
    // poll confirmed it; a submit-time observation stays estimate wording.
    final unconfirmedFailure = item.isFailed && !countsTowardSpend(item);
    final exact = realizedUsd != null && !unconfirmedFailure;
    final usesUsd = item.billingUnit == 'usd';
    final background = exact
        ? context.colors.primaryContainer
        : context.colors.secondaryContainer;
    final foreground = exact
        ? context.colors.onPrimaryContainer
        : context.colors.onSecondaryContainer;
    return Container(
      padding: EdgeInsets.all(compact ? 9 : 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.toll_rounded,
                size: compact ? 13 : 15,
                color: foreground,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${exact ? 'Realized cost' : 'Estimated'} · '
                  '${usesUsd ? formatUsdAmountRange(minimum, maximum) : '${formatCreditRange(minimum, maximum)} cr'}',
                  style: TextStyle(
                    fontSize: compact ? 11 : 12,
                    fontWeight: FontWeight.w700,
                    color: foreground,
                  ),
                ),
              ),
              Text(
                usesUsd
                    ? providerNameForHistory(item.provider)
                    : formatUsdRange(minimum, maximum),
                style: TextStyle(
                  fontSize: compact ? 11 : 12,
                  fontWeight: FontWeight.w700,
                  color: foreground,
                ),
              ),
            ],
          ),
          if (!compact &&
              item.creditsBefore != null &&
              item.creditsAfter != null) ...<Widget>[
            const SizedBox(height: 5),
            Text(
              usesUsd
                  ? '${formatUsdAmount(item.creditsBefore!)} → ${formatUsdAmount(item.creditsAfter!)} available'
                  : '${formatCredits(item.creditsBefore!)} → ${formatCredits(item.creditsAfter!)} credits available',
              style: TextStyle(
                fontSize: 10.5,
                color: foreground.withValues(alpha: .8),
              ),
            ),
          ],
          if (!compact &&
              exact &&
              item.quotedCostUsdMin != null &&
              item.quotedCostUsdMax != null) ...<Widget>[
            const SizedBox(height: 5),
            Text(
              'Quoted ${formatUsdAmountRange(item.quotedCostUsdMin!, item.quotedCostUsdMax!)} · '
              'realized ${formatUsdAmount(realizedUsd)}'
              '${item.realizedCostSource == null ? '' : ' · ${item.realizedCostSource!.replaceAll('-', ' ')}'}',
              style: TextStyle(
                fontSize: 10.5,
                color: foreground.withValues(alpha: .8),
              ),
            ),
          ],
          if (!compact &&
              unconfirmedFailure &&
              realizedUsd != null) ...<Widget>[
            const SizedBox(height: 5),
            Text(
              'No confirmed charge · submit-time estimate '
              '${formatUsdAmount(realizedUsd)}',
              style: TextStyle(
                fontSize: 10.5,
                color: foreground.withValues(alpha: .8),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ActivityCard extends StatelessWidget {
  const ActivityCard({required this.controller, required this.item, super.key});

  final AppController controller;
  final Generation item;

  @override
  Widget build(BuildContext context) {
    final hasMedia = item.resultAsset != null || item.resultUrl != null;
    final isGeneratingVideo = !hasMedia && item.isWorking && !item.isImage;
    final preview = Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (hasMedia)
          GenerationMedia(controller: controller, item: item)
        else if (isGeneratingVideo)
          GenerationLoadingPlaceholder(
            item: item,
            style: controller.generationPlaceholderStyle,
          )
        else
          GenerationInputPreview(controller: controller, item: item),
        Positioned(left: 8, top: 8, child: StatusBadge(item: item)),
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
                : SizedBox(height: 110, child: preview),
          ),
          Padding(
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: GenerationPrompt(
                        controller: controller,
                        prompt: item.displayPrompt,
                        collapsedLines: 2,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(width: 6),
                    StorageBadge(storage: item.storage, compact: true),
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        relativeTime(item.createdAt),
                        style: TextStyle(
                          fontSize: 10.5,
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                GenerationSpecChips(item: item),
                if (item.config.keyframes?.isNotEmpty == true ||
                    item.config.references?.isNotEmpty == true ||
                    item.config.source != null) ...<Widget>[
                  const SizedBox(height: 8),
                  ReferenceInputsStrip(controller: controller, item: item),
                ],
                const SizedBox(height: 9),
                GenerationCost(item: item, compact: true),
                if (item.isWorking && !item.isStatusUnavailable) ...<Widget>[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: item.progress == null ? null : item.progress! / 100,
                    minHeight: 5,
                    borderRadius: BorderRadius.circular(99),
                    backgroundColor: context.colors.surfaceContainerHigh,
                    color: context.colors.primary,
                  ),
                ],
                if (item.error != null ||
                    item.lastCheckError != null ||
                    item.lastCheckedAt != null ||
                    item.isLongRunning) ...<Widget>[
                  const SizedBox(height: 8),
                  GenerationStatusDetails(item: item),
                ],
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: <Widget>[
                          if (hasMedia)
                            FilledButton.tonalIcon(
                              onPressed: () => unawaited(
                                saveGenerationVideo(context, controller, item),
                              ),
                              icon: const Icon(
                                Icons.download_rounded,
                                size: 15,
                              ),
                              label: const Text('Save'),
                            ),
                          if (controller.canReuse(item))
                            OutlinedButton.icon(
                              onPressed: () =>
                                  unawaited(controller.reuse(item)),
                              icon: const Icon(Icons.replay_rounded, size: 15),
                              label: Text(
                                item.isFailed
                                    ? 'Retry generation'
                                    : 'Reuse inputs',
                              ),
                            ),
                          GenerationStatusButton(
                            controller: controller,
                            item: item,
                            compact: true,
                          ),
                        ],
                      ),
                    ),
                    GenerationActionsMenu(
                      controller: controller,
                      item: item,
                      includeSave: false,
                      includeReuse: false,
                      includeCheckStatus: false,
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
