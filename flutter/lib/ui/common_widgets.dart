import 'dart:async';
import 'dart:ui' as ui;
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import '../core/models.dart';
import '../core/generation_timing.dart';
import '../core/loading_timing.dart';
import '../core/pricing.dart';
import '../core/provider_catalog.dart';
import '../core/shell_bridge.dart';
import 'estimated_progress_bar.dart';
import 'formatters.dart';
import 'generation_loading_placeholder.dart';
import 'generation_video.dart';
import 'generation_view_widgets.dart';
import 'inline_video.dart';
import 'media_thumbnail.dart';
import 'video_frame_loader.dart';
import 'video_frame_timeline.dart';
import 'video_save_sheet.dart';
import 'visual_reference_viewer.dart';

/// Accepts local files dragged from the OS anywhere over [child] and hands
/// their bytes to [onDropFiles]. A themed overlay confirms the target while a
/// drag hovers. Inert on platforms without OS file drops (iPhone): the drag
/// events simply never fire and [child] renders untouched.
class ReferenceDropZone extends StatefulWidget {
  const ReferenceDropZone({
    required this.onDropFiles,
    required this.label,
    required this.child,
    this.enabled = true,
    super.key,
  });

  final Future<void> Function(List<DroppedFile> files) onDropFiles;
  final String label;
  final bool enabled;
  final Widget child;

  @override
  State<ReferenceDropZone> createState() => _ReferenceDropZoneState();
}

class _ReferenceDropZoneState extends State<ReferenceDropZone> {
  bool _hovering = false;

  Future<void> _handleDrop(DropDoneDetails details) async {
    final files = <DroppedFile>[];
    for (final item in details.files) {
      try {
        files.add(
          DroppedFile(
            name: item.name,
            bytes: await item.readAsBytes(),
            path: item.path.isEmpty ? null : item.path,
          ),
        );
      } on Object {
        // An unreadable item (a folder, a permission failure) is skipped;
        // every readable file in the same drop still lands.
      }
    }
    await widget.onDropFiles(files);
  }

  @override
  Widget build(BuildContext context) => DropTarget(
    key: const ValueKey('reference-drop-zone'),
    enable: widget.enabled,
    onDragEntered: (_) => setState(() => _hovering = true),
    onDragExited: (_) => setState(() => _hovering = false),
    onDragDone: (details) {
      setState(() => _hovering = false);
      unawaited(_handleDrop(details));
    },
    child: Stack(
      children: <Widget>[
        widget.child,
        if (_hovering)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.colors.primaryContainer.withValues(alpha: .3),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.colors.primary, width: 2),
                ),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: context.colors.surface.withValues(alpha: .92),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: context.colors.outlineVariant),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.file_download_outlined,
                          size: 17,
                          color: context.colors.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.label,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class ReferenceUploadIndicator extends StatelessWidget {
  const ReferenceUploadIndicator({
    required this.controller,
    this.margin = const EdgeInsets.only(top: 8),
    super.key,
  });

  final AppController controller;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final status = controller.referenceUploadStatus;
      if (!controller.referenceUploadInProgress || status == null) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: margin,
        child: Semantics(
          liveRegion: true,
          label: status,
          child: Container(
            key: const ValueKey('reference-upload-progress'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: context.colors.primaryContainer.withValues(alpha: .42),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: context.colors.outlineVariant),
            ),
            child: Row(
              children: <Widget>[
                const SizedBox.square(
                  dimension: 17,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    status,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class StorageBadge extends StatelessWidget {
  const StorageBadge({
    required this.storage,
    super.key,
    this.compact = false,
    this.pendingUpload = false,
  });

  final LibraryStorage storage;
  final bool compact;

  /// The record is Drive-tagged but its media is still staged on this device
  /// waiting for the background upload pass to publish it.
  final bool pendingUpload;

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
          pendingUpload
              ? Icons.cloud_upload_outlined
              : storage == LibraryStorage.drive
              ? Icons.cloud_outlined
              : Icons.devices_outlined,
          size: compact ? 12 : 14,
        ),
        const SizedBox(width: 5),
        Text(
          pendingUpload ? 'Syncing…' : storage.shortLabel,
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
    this.reserveCollapsedHeight = false,
  });

  final AppController controller;
  final String prompt;
  final int collapsedLines;
  final TextStyle? style;

  /// Occupy the full collapsed block (all [collapsedLines] plus the toggle
  /// row) even for short prompts, so sibling cards in a grid stay level.
  final bool reserveCollapsedHeight;

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
        final promptText = Text(
          widget.prompt,
          maxLines: _expanded ? null : widget.collapsedLines,
          overflow: _expanded ? null : TextOverflow.ellipsis,
          style: style,
        );
        final toggleRow = InkWell(
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
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  widget.reserveCollapsedHeight && !_expanded
                      ? ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight:
                                painter.preferredLineHeight *
                                widget.collapsedLines,
                          ),
                          child: promptText,
                        )
                      : promptText,
                  if (truncated || _expanded)
                    toggleRow
                  else if (widget.reserveCollapsedHeight)
                    // An invisible twin of the toggle row keeps short-prompt
                    // cards level with their truncated neighbors.
                    IgnorePointer(child: Opacity(opacity: 0, child: toggleRow)),
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

  /// A delivered thumbnail already says "ready" — no chip needed. The same
  /// goes for a delivered film whose record picked up a late failure status
  /// (an expired provider job, or a cross-device merge): the film is proof.
  static bool shouldShow(Generation item) =>
      !item.isReady && !(item.hasDeliveredMedia && !item.isWorking);

  @override
  Widget build(BuildContext context) {
    if (!shouldShow(item)) {
      return const SizedBox.shrink();
    }
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

/// Duration pill overlaid on a media thumbnail, shared by reference and
/// generation cards.
class MediaDurationBadge extends StatelessWidget {
  const MediaDurationBadge({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .78),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );
}

/// The duration to overlay on a generation thumbnail, or null when duration
/// does not apply (images, upscales that keep their source's length).
String? generationDurationLabel(Generation item) {
  if (item.isImage || item.mode == VideoMode.upscale) return null;
  final duration = item.config.duration;
  return duration == 'auto' ? 'Auto' : '$duration s';
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
              ? 'Apple image sequence'
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
        if (item.provider == 'apple-local' && !item.isImage)
          _SpecChip(icon: Icons.animation_rounded, label: '1 frame / s'),
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
    message:
        '${media.kind.label} reference · ${media.label}'
        '${media.durationSeconds == null ? '' : ' · ${formatMediaDuration(media.durationSeconds!)}'}'
        ' — tap to view',
    child: InkWell(
      key: ValueKey('view-generation-reference-${item.localId}-${media.label}'),
      borderRadius: BorderRadius.circular(8),
      onTap: media.kind == MediaReferenceKind.audio
          ? null
          : () => unawaited(
              showVisualReferenceViewer(
                context,
                controller: controller,
                kind: media.kind,
                label: media.label,
                reference: media.source,
                thumbnailReference: media.thumbnailAsset,
              ),
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
              child: MediaThumbnail(
                gateway: controller.gateway,
                kind: media.kind,
                reference: media.source,
                thumbnailReference: media.thumbnailAsset,
                semanticsLabel: '${media.label} reference thumbnail',
                onThumbnail:
                    media.kind == MediaReferenceKind.video &&
                        media.source != null
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
                media.durationSeconds == null
                    ? media.label
                    : '${media.label} · ${formatMediaDuration(media.durationSeconds!)}',
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
                      : snapshot.hasError
                      ? Icon(
                          Icons.broken_image_outlined,
                          size: 16,
                          color: ghostForeground,
                        )
                      : const Center(
                          child: SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(strokeWidth: 1.7),
                          ),
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
        showVisualReferenceViewer(
          context,
          controller: controller,
          kind: MediaReferenceKind.video,
          label: source.label,
          reference: source,
          thumbnailReference: thumbnailAsset,
        ),
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
  if (source != null) {
    return showVisualReferenceViewer(
      context,
      controller: controller,
      kind: MediaReferenceKind.image,
      label: frame.label,
      reference: source,
    );
  }
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
  const GenerationStatusDetails({
    required this.item,
    super.key,
    this.maxProblemLines,
  });

  final Generation item;

  /// Clamp for the problem message when the panel overlays a bounded media
  /// zone; the full text stays available in the details dialog. Null keeps
  /// the message unclamped for in-body placements.
  final int? maxProblemLines;

  /// Whether the status panel has anything worth saying for [item]. A
  /// delivered film is its own proof of success: stale poll metadata or a
  /// late failure status must not dress a playable card in error colors.
  static bool shouldShow(Generation item) {
    if (item.hasDeliveredMedia && !item.needsResultRetention) return false;
    final problem =
        item.error ?? item.resultRetentionError ?? item.lastCheckError;
    if (problem != null || item.isLongRunning || item.needsResultRetention) {
      return true;
    }
    // Otherwise only in-flight records surface their polling cadence.
    return item.isWorking && item.lastCheckedAt != null;
  }

  @override
  Widget build(BuildContext context) {
    final problem =
        item.error ?? item.resultRetentionError ?? item.lastCheckError;
    final isTerminal = item.error != null || item.isFailed;
    final checked = item.lastCheckedAt;
    if (!shouldShow(item)) {
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
                    maxLines: maxProblemLines,
                    overflow: maxProblemLines == null
                        ? null
                        : TextOverflow.ellipsis,
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
          if (item.needsResultRetention) ...<Widget>[
            if (problem != null) const SizedBox(height: 6),
            Text(
              'The provider finished this generation, but Clawnsole has not safely retained the result yet. Retrieval will keep retrying across the app and after resume.',
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
    if (!item.canCheckStatus ||
        (item.hasDeliveredMedia &&
            !item.needsResultRetention &&
            !item.isWorking) ||
        (item.isReady && !item.needsResultRetention)) {
      return const SizedBox.shrink();
    }
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
            : item.isReady
            ? 'Retry retrieval'
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
  const GenerationDetailsButton({
    required this.item,
    super.key,
    this.progressEstimate,
  });

  final Generation item;
  final GenerationProgressEstimate? progressEstimate;

  @override
  Widget build(BuildContext context) {
    if (!item.hasProviderDetails) return const SizedBox.shrink();
    return OutlinedButton.icon(
      onPressed: () => showGenerationDetails(
        context,
        item,
        progressEstimate: progressEstimate,
      ),
      icon: const Icon(Icons.receipt_long_rounded, size: 15),
      label: const Text('View details'),
    );
  }
}

Future<void> showGenerationDetails(
  BuildContext context,
  Generation item, {
  GenerationProgressEstimate? progressEstimate,
}) => showDialog<void>(
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
            _GenerationDetailLine(
              label: 'Submitted',
              value: formatTimestamp(item.createdAt),
            ),
            if (item.providerAcceptedAt != null)
              _GenerationDetailLine(
                label: 'Provider accepted',
                value: formatTimestamp(item.providerAcceptedAt!),
              ),
            if (item.providerCompletedAt != null)
              _GenerationDetailLine(
                label: 'Completed',
                value: formatTimestamp(item.providerCompletedAt!),
              ),
            if (observedGenerationDuration(item) case final elapsed?)
              _GenerationDetailLine(
                label: 'Generation time',
                value: formatElapsedDuration(elapsed),
              ),
            if (item.isWorking && progressEstimate?.expectedDuration != null)
              _GenerationDetailLine(
                label: 'Estimated total',
                value: formatElapsedDuration(
                  progressEstimate!.expectedDuration!,
                ),
              ),
            if (item.isWorking &&
                progressEstimate != null &&
                progressEstimate.isEstimated)
              _GenerationDetailLine(
                label: 'Estimate basis',
                value:
                    progressEstimate.basis == GenerationProgressBasis.historical
                    ? '${progressEstimate.sampleCount} similar personal ${progressEstimate.sampleCount == 1 ? 'generation' : 'generations'} + benchmark'
                    : 'Built-in Seedance 2.5 benchmark',
              ),
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
            if (item.resultRetentionError != null) ...<Widget>[
              const SizedBox(height: 14),
              const Eyebrow(
                'Last result-retrieval error',
                icon: Icons.cloud_download_outlined,
              ),
              const SizedBox(height: 7),
              SelectableText(item.resultRetentionError!),
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
    this.showTimelineOverlay = true,
  });

  final AppController controller;
  final Generation item;

  /// Whether the cached filmstrip may overlay the bottom of the thumbnail.
  /// Cards that render [GenerationIdleChrome] show the strip below the frame
  /// instead, so they pass false to avoid doubling it.
  final bool showTimelineOverlay;

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
              ? widget.controller.readPreviewAsset(widget.item.resultAsset!)
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
        initialData: widget.controller.cachedAssetBytes(
          widget.item.resultAsset,
        ),
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
              loading: true,
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
      showTimelineOverlay: widget.showTimelineOverlay,
    );
  }
}

final Map<String, _GeneratedVideoPreviewJob> _previewJobs =
    <String, _GeneratedVideoPreviewJob>{};
final LoadingTimingEstimator _previewTimings = LoadingTimingEstimator();

String _generationPreviewJobKey(Generation item) =>
    '${item.storage.name}:${item.localId}:${item.resultAsset?.value ?? item.resultUrl}';

/// The idle chrome bar a full video card renders under its film: the cached
/// filmstrip occupies the exact band the player's live timeline will use, and
/// a static transport row sits where the controls will appear — so starting
/// playback replaces content without resizing the card.
class GenerationIdleChrome extends StatefulWidget {
  const GenerationIdleChrome({
    required this.controller,
    required this.item,
    super.key,
  });

  final AppController controller;
  final Generation item;

  @override
  State<GenerationIdleChrome> createState() => _GenerationIdleChromeState();
}

class _GenerationIdleChromeState extends State<GenerationIdleChrome> {
  Future<Uint8List?>? _timeline;
  Uint8List? _restoredTimeline;
  late int _sourceRevision;

  bool get _playable =>
      widget.item.resultAsset != null || widget.item.resultUrl != null;

  void _load() {
    _sourceRevision = widget.controller.videoPreviewSourceRevision;
    final asset = widget.item.timelineThumbnailAsset;
    _restoredTimeline = widget.controller.cachedAssetBytes(asset);
    if (_restoredTimeline != null) {
      _timeline = null;
      return;
    }
    if (asset != null) {
      _timeline = widget.controller
          .readPreviewAsset(asset)
          .then<Uint8List?>((bytes) => bytes)
          .catchError((Object _) => null);
      return;
    }
    // The thumbnail preview above shares its extraction job; piggyback on it
    // instead of running a second frame pass for the same film.
    _timeline = _previewJobs[_generationPreviewJobKey(widget.item)]?.future
        .then((preview) => preview?.timeline);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant GenerationIdleChrome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_sourceRevision != widget.controller.videoPreviewSourceRevision ||
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

  Future<void> _play() async {
    final delivery = widget.controller.generationMediaDelivery(widget.item);
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
  Widget build(BuildContext context) => InkWell(
    // The thumbnail's play button is the affordance; the strip just accepts
    // the same tap. The filmstrip fills the whole reserved chrome zone, so
    // playback (timeline + transport) still swaps in at an equal height.
    onTap: _playable ? () => unawaited(_play()) : null,
    child: SizedBox.expand(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Colors.white30)),
        ),
        child: FutureBuilder<Uint8List?>(
          future: _timeline,
          initialData: _restoredTimeline,
          builder: (context, snapshot) {
            final bytes = snapshot.data;
            if (bytes == null) return const SizedBox.expand();
            return Image.memory(
              bytes,
              key: const ValueKey('generation-idle-filmstrip'),
              fit: BoxFit.cover,
              gaplessPlayback: true,
            );
          },
        ),
      ),
    ),
  );
}

class _GeneratedVideoPreview {
  const _GeneratedVideoPreview({required this.thumbnail, this.timeline});

  final Uint8List thumbnail;
  final Uint8List? timeline;
}

class _GeneratedVideoPreviewJob {
  const _GeneratedVideoPreviewJob({
    required this.future,
    required this.startedAt,
    required this.expectedDuration,
  });

  final Future<_GeneratedVideoPreview?> future;
  final DateTime startedAt;
  final Duration expectedDuration;
}

class _CachedVideoPreview extends StatefulWidget {
  const _CachedVideoPreview({
    required this.controller,
    required this.item,
    required this.uri,
    this.showTimelineOverlay = true,
  });

  final AppController controller;
  final Generation item;
  final Future<Uri?> uri;
  final bool showTimelineOverlay;

  @override
  State<_CachedVideoPreview> createState() => _CachedVideoPreviewState();
}

class _CachedVideoPreviewState extends State<_CachedVideoPreview> {
  Future<_GeneratedVideoPreview?>? _preview;
  _GeneratedVideoPreview? _initialPreview;
  late int _sourceRevision;
  late DateTime _previewStartedAt;
  late Duration _previewExpectedDuration;

  String get _jobKey => _generationPreviewJobKey(widget.item);

  Future<Uint8List> _read(AssetReference reference) =>
      widget.controller.readPreviewAsset(reference);

  _GeneratedVideoPreviewJob _previewJob(String key) {
    final existing = _previewJobs[key];
    if (existing != null) return existing;
    final startedAt = DateTime.now();
    final stopwatch = Stopwatch()..start();
    final expectedDuration = _previewTimings.expected(
      LoadingOperation.generationPreviewBuild,
    );
    late final _GeneratedVideoPreviewJob job;
    final future = _generateAndCache().then((preview) {
      stopwatch.stop();
      if (preview == null && identical(_previewJobs[key], job)) {
        _previewJobs.remove(key);
      } else if (preview != null) {
        _previewTimings.record(
          LoadingOperation.generationPreviewBuild,
          stopwatch.elapsed,
        );
      }
      return preview;
    });
    job = _GeneratedVideoPreviewJob(
      future: future,
      startedAt: startedAt,
      expectedDuration: expectedDuration,
    );
    _previewJobs[key] = job;
    return job;
  }

  void _load() {
    _initialPreview = null;
    _sourceRevision = widget.controller.videoPreviewSourceRevision;
    final thumbnail = widget.item.thumbnailAsset;
    if (thumbnail != null) {
      final restoredThumbnail = widget.controller.cachedAssetBytes(thumbnail);
      if (restoredThumbnail != null) {
        _initialPreview = _GeneratedVideoPreview(
          thumbnail: restoredThumbnail,
          timeline: widget.controller.cachedAssetBytes(
            widget.item.timelineThumbnailAsset,
          ),
        );
      }
      _previewStartedAt = DateTime.now();
      _previewExpectedDuration = _previewTimings.expected(
        LoadingOperation.generationPreviewRead,
      );
      final stopwatch = Stopwatch()..start();
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
          final preview = _GeneratedVideoPreview(
            thumbnail: thumbnailBytes,
            timeline: timelineBytes,
          );
          stopwatch.stop();
          _previewTimings.record(
            LoadingOperation.generationPreviewRead,
            stopwatch.elapsed,
          );
          return preview;
        } on Object {
          final job = _previewJob('$_jobKey:regenerate');
          return await job.future;
        }
      });
      return;
    }
    final job = _previewJob(_jobKey);
    _previewStartedAt = job.startedAt;
    _previewExpectedDuration = job.expectedDuration;
    _preview = job.future;
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
    final sourceBecameAvailable =
        _sourceRevision != widget.controller.videoPreviewSourceRevision;
    if (sourceBecameAvailable ||
        oldWidget.item.thumbnailAsset?.value !=
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
    initialData: _initialPreview,
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
                : widget.item.thumbnailAsset == null
                ? 'Caching preview'
                : 'Loading preview',
            loading: snapshot.connectionState != ConnectionState.done,
            expectedDuration: _previewExpectedDuration,
            startedAt: _previewStartedAt,
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
                  widget.showTimelineOverlay &&
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
    return Semantics(
      button: true,
      label: 'View generation input full screen',
      child: InkWell(
        key: ValueKey('view-generation-input-${widget.item.localId}'),
        onTap: () => unawaited(
          showVisualReferenceViewer(
            context,
            controller: widget.controller,
            kind: media.$1,
            label: media.$2.label,
            reference: media.$2,
            thumbnailReference: media.$3,
          ),
        ),
        child: MediaThumbnail(
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
        ),
      ),
    );
  }
}

class _MediaPlaceholder extends StatelessWidget {
  const _MediaPlaceholder({
    required this.icon,
    required this.label,
    this.loading = false,
    this.expectedDuration,
    this.startedAt,
  });

  final IconData icon;
  final String label;
  final bool loading;
  final Duration? expectedDuration;
  final DateTime? startedAt;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = dark
        ? ClawnsoleColors.creamMuted
        : context.colors.onSurfaceVariant;
    final duration = expectedDuration;
    final start = startedAt;
    return Semantics(
      label: label,
      liveRegion: loading,
      child: Container(
        color: dark ? ClawnsoleColors.plumInk : context.colors.surfaceContainer,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (loading)
                SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.3,
                    color: foreground,
                  ),
                )
              else
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
              if (loading && duration != null && start != null) ...<Widget>[
                const SizedBox(height: 10),
                SizedBox(
                  width: 84,
                  child: EstimatedProgressBar(
                    key: const ValueKey('media-loading-estimated-progress'),
                    expectedDuration: duration,
                    startedAt: start,
                    color: foreground,
                    backgroundColor: foreground.withValues(alpha: .18),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class GenerationCost extends StatefulWidget {
  const GenerationCost({required this.item, super.key, this.compact = false});

  final Generation item;
  final bool compact;

  @override
  State<GenerationCost> createState() => _GenerationCostState();
}

class _GenerationCostState extends State<GenerationCost> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final compact = widget.compact;
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
    final detailStyle = TextStyle(
      fontSize: 10.5,
      color: foreground.withValues(alpha: .8),
    );
    final details = <Widget>[
      if (item.creditsBefore != null && item.creditsAfter != null)
        Text(
          usesUsd
              ? '${formatUsdAmount(item.creditsBefore!)} → ${formatUsdAmount(item.creditsAfter!)} available'
              : '${formatCredits(item.creditsBefore!)} → ${formatCredits(item.creditsAfter!)} credits available',
          style: detailStyle,
        ),
      if (exact &&
          item.quotedCostUsdMin != null &&
          item.quotedCostUsdMax != null)
        Text(
          'Quoted ${formatUsdAmountRange(item.quotedCostUsdMin!, item.quotedCostUsdMax!)} · '
          'realized ${formatUsdAmount(realizedUsd)}'
          '${item.realizedCostSource == null ? '' : ' · ${item.realizedCostSource!.replaceAll('-', ' ')}'}',
          style: detailStyle,
        ),
      if (unconfirmedFailure && realizedUsd != null)
        Text(
          'No confirmed charge · submit-time estimate '
          '${formatUsdAmount(realizedUsd)}',
          style: detailStyle,
        ),
    ];
    // At a glance a card only needs the realized figure; the balance and
    // quote trail sit behind the chevron.
    final expandable = !compact && details.isNotEmpty;
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        key: expandable ? const ValueKey('generation-cost-toggle') : null,
        borderRadius: BorderRadius.circular(11),
        onTap: expandable ? () => setState(() => _expanded = !_expanded) : null,
        child: Padding(
          padding: EdgeInsets.all(compact ? 9 : 12),
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
                  if (expandable) ...<Widget>[
                    const SizedBox(width: 4),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 17,
                      color: foreground.withValues(alpha: .8),
                    ),
                  ],
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: !(_expanded && expandable)
                    ? const SizedBox(width: double.infinity)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          for (final line in details) ...<Widget>[
                            const SizedBox(height: 5),
                            line,
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
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
    final progressEstimate = controller.generationProgress(item);
    final progress = progressEstimate.percentage;
    final preview = Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (hasMedia)
          GenerationMedia(controller: controller, item: item)
        else if (isGeneratingVideo)
          GenerationLoadingPlaceholder(
            item: item,
            style: controller.generationPlaceholderStyle,
            progressEstimate: progressEstimate,
          )
        else
          GenerationInputPreview(controller: controller, item: item),
        Positioned(left: 8, top: 8, child: StatusBadge(item: item)),
        if (generationDurationLabel(item) != null)
          Positioned(
            left: 8,
            bottom: 8,
            child: MediaDurationBadge(text: generationDurationLabel(item)!),
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
                        reserveCollapsedHeight: true,
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
                    value: progress == null ? null : progress / 100,
                    minHeight: 5,
                    borderRadius: BorderRadius.circular(99),
                    backgroundColor: context.colors.surfaceContainerHigh,
                    color: context.colors.primary,
                  ),
                ],
                if (GenerationStatusDetails.shouldShow(item)) ...<Widget>[
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
                                item.isFailed && !item.hasDeliveredMedia
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
