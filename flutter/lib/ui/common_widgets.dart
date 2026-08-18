import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import '../core/models.dart';
import '../core/provider_catalog.dart';
import 'formatters.dart';
import 'generation_video.dart';
import 'video_save_sheet.dart';

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

/// A small on/off pill used for optional behaviors like auto duration.
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
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        _SpecChip(label: providerById(item.provider).shortName),
        _SpecChip(
          label: item.isImage
              ? (item.mode == VideoMode.i2v
                    ? 'Reference to image'
                    : 'Text to image')
              : item.provider == 'apple-local'
              ? 'Frame animation'
              : item.mode.label,
        ),
        _SpecChip(
          label: config.aspectRatio == 'auto' ? 'Auto' : config.aspectRatio,
          leading: _MiniRatioGlyph(ratio: config.aspectRatio),
        ),
        if (!item.isImage)
          _SpecChip(
            icon: Icons.timelapse_rounded,
            label: config.duration == 'auto' ? 'Auto' : '${config.duration} s',
          ),
        if (item.provider == 'apple-local' && !item.isImage)
          _SpecChip(
            icon: Icons.animation_rounded,
            label: '${config.frameRate} fps',
          ),
        _SpecChip(
          label: switch (config.resolution) {
            'fhd' => item.provider == 'apple-local' ? '768 px' : 'Full HD',
            'qhd' => '1440p',
            '4k' => '4K',
            _ => item.provider == 'apple-local' ? '512 px' : 'HD',
          },
        ),
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
    final source = item.config.source;
    if (frames.isEmpty && source == null) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        ...frames.map(
          (frame) => _ReferenceThumb(controller: controller, frame: frame),
        ),
        if (source != null)
          _SourceReferenceChip(
            controller: controller,
            source: source,
            mode: item.mode,
          ),
      ],
    );
  }
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
            color: ClawnsoleColors.plumInk,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.colors.outlineVariant),
          ),
          child: _bytes == null
              ? const Icon(
                  Icons.image_outlined,
                  size: 16,
                  color: ClawnsoleColors.creamMuted,
                )
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
                          color: ClawnsoleColors.creamMuted,
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
    required this.source,
    required this.mode,
  });

  final AppController controller;
  final AssetReference source;
  final VideoMode mode;

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
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: context.colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.colors.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              mode == VideoMode.draftEnhance
                  ? Icons.auto_fix_high_rounded
                  : Icons.movie_filter_rounded,
              size: 15,
              color: context.colors.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
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
                      onPressed: () =>
                          unawaited(launchUrl(Uri.parse(source.value))),
                      icon: const Icon(Icons.open_in_new_rounded, size: 15),
                      label: const Text('Open link'),
                    ),
                  if (source != null)
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        try {
                          await controller.saveReferenceImage(source);
                        } on Object catch (error) {
                          controller.showNotice(error.toString());
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
    title: Text(
      mode == VideoMode.draftEnhance ? 'Draft cache' : 'Starting video',
    ),
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
          onPressed: () => unawaited(launchUrl(Uri.parse(source.value))),
          icon: const Icon(Icons.open_in_new_rounded, size: 15),
          label: const Text('Open link'),
        ),
      FilledButton.tonalIcon(
        onPressed: () async {
          try {
            await controller.saveReferenceImage(source);
          } on Object catch (error) {
            controller.showNotice(error.toString());
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
      onPressed: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Generation details'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _GenerationDetailLine(
                    label: 'State',
                    value: item.statusLabel,
                  ),
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
                        border: Border.all(
                          color: context.colors.outlineVariant,
                        ),
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
      ),
      icon: const Icon(Icons.receipt_long_rounded, size: 15),
      label: const Text('View details'),
    );
  }
}

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
    _uri = widget.controller.generationMediaUri(widget.item);
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
    return FutureBuilder<Uri?>(
      future: _uri,
      builder: (context, snapshot) {
        if (snapshot.hasError ||
            (snapshot.connectionState == ConnectionState.done &&
                snapshot.data == null)) {
          return const _MediaPlaceholder(
            icon: Icons.link_off_rounded,
            label: 'Video unavailable',
          );
        }
        if (!snapshot.hasData) {
          return const _MediaPlaceholder(
            icon: Icons.hourglass_bottom_rounded,
            label: 'Loading film',
          );
        }
        return GenerationVideo(
          uri: snapshot.data!,
          supportsPhotos: widget.controller.supportsPhotoLibrarySave,
          onDownload: (destination) async {
            try {
              await widget.controller.saveMedia(
                widget.item,
                destination: destination,
              );
            } on Object catch (error) {
              widget.controller.showNotice(error.toString());
            }
          },
        );
      },
    );
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
  late AssetReference? _reference;
  Future<Uint8List>? _bytes;

  AssetReference? _findReference() {
    for (final frame
        in widget.item.config.keyframes ?? const <KeyframeLabel>[]) {
      if (frame.source != null) return frame.source;
    }
    return widget.item.config.source?.contentType?.startsWith('image/') == true
        ? widget.item.config.source
        : null;
  }

  void _load() {
    _reference = _findReference();
    _bytes = _reference == null
        ? null
        : widget.controller.gateway.readAsset(_reference!);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant GenerationInputPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_findReference()?.value != _reference?.value) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_reference == null || _bytes == null) {
      return const _MediaPlaceholder(
        icon: Icons.movie_creation_outlined,
        label: 'Saved generation',
      );
    }
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _MediaPlaceholder(
            icon: Icons.broken_image_outlined,
            label: 'Reference unavailable',
          );
        }
        if (!snapshot.hasData) {
          return const _MediaPlaceholder(
            icon: Icons.image_outlined,
            label: 'Loading reference',
          );
        }
        return Image.memory(snapshot.data!, fit: BoxFit.cover);
      },
    );
  }
}

class _MediaPlaceholder extends StatelessWidget {
  const _MediaPlaceholder({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    color: ClawnsoleColors.plumInk,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: ClawnsoleColors.creamMuted, size: 28),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: ClawnsoleColors.creamMuted,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    ),
  );
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
    final exact = item.cost != null;
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
                  '${exact ? 'Provider charge' : 'Estimated'} · '
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
                    ? providerById(item.provider).shortName
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
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: hasMedia ? 235 : 110,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(15),
                  ),
                  child: hasMedia
                      ? GenerationMedia(controller: controller, item: item)
                      : GenerationInputPreview(
                          controller: controller,
                          item: item,
                        ),
                ),
                Positioned(left: 8, top: 8, child: StatusBadge(item: item)),
              ],
            ),
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
                        prompt: item.prompt,
                        collapsedLines: 2,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
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
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: <Widget>[
                    if (hasMedia)
                      FilledButton.tonalIcon(
                        onPressed: () => unawaited(
                          saveGenerationVideo(context, controller, item),
                        ),
                        icon: const Icon(Icons.download_rounded, size: 15),
                        label: const Text('Save'),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => unawaited(controller.reuse(item)),
                      icon: const Icon(Icons.replay_rounded, size: 15),
                      label: Text(
                        item.isFailed ? 'Retry generation' : 'Reuse inputs',
                      ),
                    ),
                    GenerationStatusButton(
                      controller: controller,
                      item: item,
                      compact: true,
                    ),
                    GenerationDetailsButton(item: item),
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
