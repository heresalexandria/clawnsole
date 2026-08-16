import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import '../core/models.dart';
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
        Icon(icon, size: 14, color: context.colors.primary),
        const SizedBox(width: 7),
      ],
      Text(
        text.toUpperCase(),
        style: TextStyle(
          color: context.colors.primary,
          fontSize: 10,
          letterSpacing: 1.6,
          fontWeight: FontWeight.w900,
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
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: context.colors.outlineVariant),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: context.colors.shadow.withValues(alpha: .07),
          blurRadius: 16,
          offset: Offset(0, 5),
        ),
      ],
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
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
            const SizedBox(width: 5),
          ],
          Text(
            item.statusLabel,
            style: TextStyle(
              fontSize: 9,
              color: foreground,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

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
      padding: const EdgeInsets.all(10),
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
                      ? context.colors.error
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
                      fontSize: 9,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
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
                fontSize: 9,
                height: 1.35,
              ),
            ),
          ],
          if (item.isStatusUnavailable) ...<Widget>[
            if (problem != null) const SizedBox(height: 6),
            Text(
              'The provider has not confirmed that this generation is still in progress. Retry the status check below.',
              style: TextStyle(
                color: context.colors.onSurfaceVariant,
                fontSize: 9,
                height: 1.35,
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
                    ? context.colors.onErrorContainer.withValues(alpha: .72)
                    : context.colors.onSurfaceVariant,
                fontSize: 8,
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
          : const Icon(Icons.sync_rounded, size: 16),
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
                          fontSize: 10,
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
      icon: const Icon(Icons.receipt_long_rounded, size: 16),
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
          width: 112,
          child: Text(
            label,
            style: TextStyle(
              color: context.colors.onSurfaceVariant,
              fontSize: 10,
              fontWeight: FontWeight.w800,
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

  @override
  void initState() {
    super.initState();
    _uri = widget.controller.generationMediaUri(widget.item);
  }

  @override
  void didUpdateWidget(covariant GenerationMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.resultUrl != widget.item.resultUrl ||
        oldWidget.item.resultAsset?.value != widget.item.resultAsset?.value) {
      _uri = widget.controller.generationMediaUri(widget.item);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uri?>(
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
            await widget.controller.saveVideo(
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
    color: ClawnsoleColors.rail,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: ClawnsoleColors.railMuted, size: 30),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
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
    final minimum = item.cost ?? item.estimatedCreditsMin;
    final maximum = item.cost ?? item.estimatedCreditsMax;
    if (minimum == null || maximum == null) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.all(compact ? 9 : 12),
      decoration: BoxDecoration(
        color: item.cost != null
            ? context.colors.primaryContainer
            : context.colors.secondaryContainer,
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
                color: context.colors.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${item.cost != null ? 'Provider charge' : 'Estimated'} · '
                  '${formatCreditRange(minimum, maximum)} cr',
                  style: TextStyle(
                    fontSize: compact ? 10 : 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                formatUsdRange(minimum, maximum),
                style: TextStyle(
                  fontSize: compact ? 10 : 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          if (!compact &&
              item.creditsBefore != null &&
              item.creditsAfter != null) ...<Widget>[
            const SizedBox(height: 5),
            Text(
              '${formatCredits(item.creditsBefore!)} → ${formatCredits(item.creditsAfter!)} credits available',
              style: TextStyle(
                fontSize: 9,
                color: context.colors.onSurfaceVariant,
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
                    top: Radius.circular(17),
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
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      item.mode.label,
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      relativeTime(item.createdAt),
                      style: const TextStyle(fontSize: 9),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  item.prompt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                GenerationCost(item: item, compact: true),
                if (item.isWorking && !item.isStatusUnavailable) ...<Widget>[
                  const SizedBox(height: 7),
                  LinearProgressIndicator(
                    value: item.progress == null ? null : item.progress! / 100,
                    minHeight: 5,
                    borderRadius: BorderRadius.circular(99),
                    backgroundColor: context.colors.outlineVariant,
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
                const SizedBox(height: 9),
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
