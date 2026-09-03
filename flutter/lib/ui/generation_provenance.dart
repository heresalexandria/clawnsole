import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import '../core/composer_tabs.dart';
import '../core/models.dart';
import 'generation_detail_modal.dart';

/// Where a film came from, said above its prompt: the name of the tab it was
/// rendered from (only when the director named that tab) and, for an AI
/// Rewrite iteration, a link back to the film it was rewritten from.
///
/// Renders nothing for an ordinary film, so cards without provenance keep
/// their exact shape.
class GenerationProvenance extends StatelessWidget {
  const GenerationProvenance({
    required this.controller,
    required this.item,
    super.key,
    this.compact = false,
  });

  final AppController controller;
  final Generation item;

  /// Dense cards get one line with smaller type.
  final bool compact;

  /// Whether [item] has anything to say here.
  static bool applies(Generation item) =>
      (item.title?.trim().isNotEmpty ?? false) || item.rewriteOfLocalId != null;

  @override
  Widget build(BuildContext context) {
    final title = item.title?.trim() ?? '';
    final sourceId = item.rewriteOfLocalId;
    if (title.isEmpty && sourceId == null) return const SizedBox.shrink();
    final source = controller.rewriteSourceOf(item);
    final size = compact ? 10.5 : 12.0;
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        if (title.isNotEmpty)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.tab_rounded,
                size: compact ? 11 : 13,
                color: context.tokens.brass,
              ),
              const SizedBox(width: 5),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  title,
                  key: ValueKey<String>('generation-title-${item.localId}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: size,
                    fontWeight: FontWeight.w700,
                    color: context.colors.onSurface,
                  ),
                ),
              ),
            ],
          ),
        if (sourceId != null)
          _RewriteLink(
            controller: controller,
            item: item,
            source: source,
            size: size,
            compact: compact,
          ),
      ],
    );
  }
}

/// "Rewrite of …": opens the source film's detail modal, so iterations can
/// be walked back one film at a time.
class _RewriteLink extends StatelessWidget {
  const _RewriteLink({
    required this.controller,
    required this.item,
    required this.source,
    required this.size,
    required this.compact,
  });

  final AppController controller;
  final Generation item;
  final Generation? source;
  final double size;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final target = source;
    final label = target == null
        ? 'Rewrite of a removed film'
        : 'Rewrite of ${composerTabTitle(target.title, target.prompt)}';
    final color = target == null
        ? context.colors.onSurfaceVariant
        : context.colors.primary;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          Icons.auto_awesome,
          size: compact ? 11 : 12,
          color: context.tokens.brass,
        ),
        const SizedBox(width: 5),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: size,
              fontWeight: FontWeight.w600,
              color: color,
              decoration: target == null ? null : TextDecoration.underline,
              decorationColor: color,
            ),
          ),
        ),
        if (target != null) ...<Widget>[
          const SizedBox(width: 2),
          Icon(Icons.chevron_right_rounded, size: 14, color: color),
        ],
      ],
    );
    if (target == null) return row;
    return Tooltip(
      message: item.rewriteSummary?.trim().isNotEmpty == true
          ? item.rewriteSummary!.trim()
          : 'Open the film this was rewritten from',
      child: InkWell(
        key: ValueKey<String>('generation-rewrite-source-${item.localId}'),
        onTap: () => unawaited(
          showGenerationDetailModal(
            context,
            controller: controller,
            item: target,
          ),
        ),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: row,
        ),
      ),
    );
  }
}
