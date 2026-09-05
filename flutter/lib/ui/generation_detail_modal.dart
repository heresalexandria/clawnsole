import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import '../core/asset_extensions.dart';
import '../core/composer_tabs.dart';
import '../core/generation_timing.dart';
import '../core/models.dart';
import '../core/pricing.dart';
import '../core/provider_catalog.dart';
import 'common_widgets.dart';
import 'formatters.dart';
import 'generation_error_thumbnail.dart';
import 'generation_loading_placeholder.dart';
import 'generation_view_widgets.dart';
import 'inline_video.dart';
import 'library_folders.dart';
import 'library_screen.dart';
import 'prompt_rewrite_dialog.dart';
import 'video_save_sheet.dart';

/// Opens the film's detail modal: everything the card says, at nearly the
/// full viewport, so nothing has to be truncated — plus its lineage (the
/// film it was rewritten from and the films rewritten from it).
///
/// Every card body, the provenance "Rewrite of …" link, and the ⋯ menu open
/// this. Escape closes it, and the record is re-read from [controller] on
/// every notification so polling keeps the open film current.
Future<void> showGenerationDetailModal(
  BuildContext context, {
  required AppController controller,
  required Generation item,
}) => showDialog<void>(
  context: context,
  builder: (dialogContext) =>
      _GenerationDetailModal(controller: controller, item: item),
);

/// Below this width the modal is a page, not a dialog — the same threshold
/// the video player uses for its fullscreen route.
const double _pageWidth = 700;

/// Two columns only once the film and its readout both have room — a
/// 1024-wide window still qualifies, so a laptop never scrolls past the
/// film to reach its direction.
const double _twoColumnWidth = 900;

const double _maxDialogWidth = 1240;

class _GenerationDetailModal extends StatefulWidget {
  const _GenerationDetailModal({required this.controller, required this.item});

  final AppController controller;
  final Generation item;

  @override
  State<_GenerationDetailModal> createState() => _GenerationDetailModalState();
}

class _GenerationDetailModalState extends State<_GenerationDetailModal> {
  /// The films walked away from, so "← Back" retraces the chain one film at
  /// a time instead of closing the whole surface.
  final List<Generation> _trail = <Generation>[];
  final ScrollController _scroll = ScrollController();
  late Generation _item = widget.item;
  bool _providerDetailsOpen = false;
  bool _saving = false;

  AppController get _controller => widget.controller;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _open(Generation film) {
    setState(() {
      _trail.add(_item);
      _item = film;
      _providerDetailsOpen = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _back() {
    if (_trail.isEmpty) return;
    setState(() {
      _item = _trail.removeLast();
      _providerDetailsOpen = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _save(Generation item) async {
    setState(() => _saving = true);
    try {
      await saveGenerationVideo(context, _controller, item);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Reuse and the library filters both take the director somewhere else;
  /// the modal steps out of the way first.
  void _leaveFor(VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }

  /// Removing the record from inside its own modal closes the modal too;
  /// there is nothing left to show.
  Future<void> _delete(Generation item) async {
    if (!await confirmGenerationRecordRemoval(context)) return;
    await _controller.deleteGeneration(item.localId);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final page = size.width < _pageWidth;
    final body = AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => _build(context),
    );
    if (page) {
      return Dialog.fullscreen(
        backgroundColor: context.colors.surface,
        child: SafeArea(child: body),
      );
    }
    const inset = 24.0;
    final width = math.min(_maxDialogWidth, size.width - inset * 2);
    return Dialog(
      insetPadding: const EdgeInsets.all(inset),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: size.height - inset * 2),
        child: SizedBox(width: width, child: body),
      ),
    );
  }

  Widget _build(BuildContext context) {
    // Polling can finish, retain, or fail the film while it is open, so the
    // record is re-read every build. An empty library means this surface was
    // handed a film directly rather than from the listing; only a populated
    // library can prove a record is gone.
    final live = _controller.generationById(_item.localId);
    final removed = live == null && _controller.generations.isNotEmpty;
    final item = live ?? _item;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _header(context, item),
        Divider(height: 1, thickness: 1, color: context.colors.outlineVariant),
        Flexible(
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (removed) ...<Widget>[
                  Text(
                    'This film was removed from the library.',
                    key: const ValueKey('detail-removed'),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                LayoutBuilder(
                  builder: (context, constraints) {
                    final left = _mediaColumn(context, item);
                    final right = _readoutColumn(context, item);
                    if (constraints.maxWidth < _twoColumnWidth) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          left,
                          const SizedBox(height: 22),
                          right,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(flex: 58, child: left),
                        const SizedBox(width: 24),
                        Expanded(flex: 42, child: right),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── header ────────────────────────────────────────────────────────────

  Widget _header(BuildContext context, Generation item) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
    child: Row(
      children: <Widget>[
        if (_trail.isNotEmpty) ...<Widget>[
          TextButton.icon(
            key: const ValueKey('detail-back'),
            onPressed: _back,
            style: TextButton.styleFrom(minimumSize: const Size(64, 44)),
            icon: const Icon(Icons.arrow_back_rounded, size: 16),
            label: const Text('Back'),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            composerTabTitle(item.title, item.displayPrompt),
            key: ValueKey<String>('detail-title-${item.localId}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        const SizedBox(width: 10),
        IconButton(
          tooltip: item.favorite ? 'Remove from favorites' : 'Add to favorites',
          onPressed: () =>
              unawaited(_controller.toggleGenerationFavorite(item)),
          icon: Icon(
            item.favorite ? Icons.star_rounded : Icons.star_border_rounded,
            color: item.favorite ? context.tokens.brass : null,
          ),
        ),
        IconButton(
          key: const ValueKey('detail-close'),
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    ),
  );

  // ── left column: the film itself ──────────────────────────────────────

  Widget _mediaColumn(BuildContext context, Generation item) {
    final iterations = _iterations(context, item);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _media(context, item),
        if (iterations != null) ...<Widget>[
          const SizedBox(height: 18),
          iterations,
        ],
      ],
    );
  }

  Widget _media(BuildContext context, Generation item) {
    final hasMedia = item.hasDeliveredMedia;
    final rendering = !hasMedia && item.isWorking && !item.isImage;
    final estimate = _controller.generationProgress(item);
    final progress = estimate.percentage;
    final preview = Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (hasMedia)
          GenerationMedia(
            controller: _controller,
            item: item,
            showTimelineOverlay: false,
          )
        else if (rendering)
          GenerationLoadingPlaceholder(
            item: item,
            style: _controller.generationPlaceholderStyle,
            progressEstimate: estimate,
          )
        else if (GenerationErrorThumbnail.shouldShow(item))
          GenerationErrorThumbnail(item: item)
        else
          GenerationInputPreview(controller: _controller, item: item),
        GenerationThumbnailFooter(item: item),
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
    final ratio = generationAspectRatio(item.config.aspectRatio);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: hasMedia || rendering
          ? InlineVideoMediaBox(
              key: ValueKey<String>('detail-media-${item.localId}'),
              playbackId: 'detail-${item.localId}',
              aspectRatio: ratio,
              maxHeightFraction: .6,
              preview: preview,
              idleChrome: hasMedia && !item.isImage
                  ? GenerationIdleChrome(controller: _controller, item: item)
                  : null,
            )
          : StaticMediaBox(
              key: ValueKey<String>('detail-media-${item.localId}'),
              aspectRatio: ratio,
              maxHeightFraction: .6,
              reserveChrome: !item.isImage,
              child: preview,
            ),
    );
  }

  // ── iterations ────────────────────────────────────────────────────────

  /// The rewrite chain around [item]: what it came from, itself, and every
  /// film written from it. Null when the film has no lineage at all.
  Widget? _iterations(BuildContext context, Generation item) {
    final rewrites = _controller.rewritesOf(item).reversed.toList();
    if (item.rewriteOfLocalId == null && rewrites.isEmpty) return null;
    final source = _controller.rewriteSourceOf(item);
    return Column(
      key: const ValueKey('detail-iterations'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Eyebrow('Iterations', icon: Icons.auto_awesome),
        const SizedBox(height: 9),
        SizedBox(
          height: 174,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            children: <Widget>[
              if (source != null)
                _IterationCard(
                  controller: _controller,
                  film: source,
                  label: 'Rewritten from',
                  summary: item.rewriteSummary,
                  onOpen: () => _open(source),
                )
              else if (item.rewriteOfLocalId != null)
                const _MissingSourceChip(),
              _IterationCard(
                controller: _controller,
                film: item,
                label: 'This film',
                current: true,
              ),
              for (final rewrite in rewrites)
                _IterationCard(
                  controller: _controller,
                  film: rewrite,
                  label: 'Rewrite',
                  summary: rewrite.rewriteSummary,
                  onOpen: () => _open(rewrite),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ── right column: everything the card says, written out ───────────────

  Widget _readoutColumn(BuildContext context, Generation item) {
    final folder = _controller.folderById(item.folderId);
    final chips = <Widget>[
      if (folder != null)
        ActionChip(
          avatar: const Icon(Icons.folder_outlined, size: 14),
          label: Text(folder.name),
          visualDensity: VisualDensity.compact,
          onPressed: () =>
              _leaveFor(() => _controller.setLibraryFolderView(folder.id)),
        ),
      for (final tag in item.tags)
        ActionChip(
          label: Text('#$tag'),
          visualDensity: VisualDensity.compact,
          onPressed: () => _leaveFor(() => _controller.setLibraryTag(tag)),
        ),
    ];
    final inputs = _inputsSummary(item);
    final cost = _cost(context, item);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _meta(context, item),
        const SizedBox(height: 18),
        _direction(context, item),
        if (chips.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          Wrap(spacing: 6, runSpacing: 6, children: chips),
        ],
        const SizedBox(height: 18),
        const Eyebrow('Settings', icon: Icons.tune_rounded),
        const SizedBox(height: 9),
        GenerationSpecChips(item: item),
        if (inputs != null) ...<Widget>[
          const SizedBox(height: 18),
          const Eyebrow('Inputs', icon: Icons.photo_library_outlined),
          const SizedBox(height: 7),
          Text(
            inputs,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.4,
              color: context.colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 9),
          ReferenceInputsStrip(controller: _controller, item: item),
        ],
        if (GenerationStatusDetails.shouldShow(item)) ...<Widget>[
          const SizedBox(height: 18),
          GenerationStatusDetails(item: item),
        ],
        if (item.deliveryExpired) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            'The provider’s delivery link expired before the film could be retained; the record stays so you can reuse its settings.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.4,
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ],
        if (cost != null) cost,
        const SizedBox(height: 18),
        _actions(context, item),
        const SizedBox(height: 18),
        _providerDetails(context, item),
      ],
    );
  }

  Widget _meta(BuildContext context, Generation item) {
    final badges = <Widget>[
      if (StatusBadge.shouldShow(item)) StatusBadge(item: item),
      StorageBadge(
        storage: item.storage,
        compact: true,
        pendingUpload: generationPendingDriveUpload(item),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 7,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: badges,
        ),
        const SizedBox(height: 8),
        Text(
          '${providerNameForHistory(item.provider)} · ${item.model} · '
          '${relativeTime(item.createdAt)}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            height: 1.4,
            fontWeight: FontWeight.w600,
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// The whole direction, selectable, in the typewriter voice — the point of
  /// the modal is that nothing here is cut short.
  Widget _direction(BuildContext context, Generation item) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Row(
        children: <Widget>[
          const Expanded(
            child: Eyebrow('Direction', icon: Icons.edit_note_rounded),
          ),
          SizedBox.square(
            dimension: 32,
            child: IconButton(
              key: const ValueKey('detail-copy-prompt'),
              tooltip: 'Copy prompt',
              padding: EdgeInsets.zero,
              onPressed: () => unawaited(_copyPrompt(item)),
              icon: Icon(
                Icons.copy_rounded,
                size: 16,
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      SelectableText(
        item.displayPrompt,
        key: ValueKey<String>('detail-prompt-${item.localId}'),
        style: TextStyle(
          fontFamily: promptFontFamily,
          fontSize: 13.5,
          height: 1.5,
          color: context.colors.onSurface,
        ),
      ),
    ],
  );

  Future<void> _copyPrompt(Generation item) async {
    await Clipboard.setData(ClipboardData(text: item.displayPrompt));
    _controller.showNotice('Prompt copied to the clipboard.');
  }

  /// "2 keyframes · 1 reference · a source video" — the strip's tooltips
  /// said in words, since the modal has the room for them.
  String? _inputsSummary(Generation item) {
    final frames = item.config.keyframes ?? const <KeyframeLabel>[];
    final references = item.config.references ?? const <MediaReferenceLabel>[];
    final source = item.config.source;
    if (frames.isEmpty && references.isEmpty && source == null) return null;
    final parts = <String>[
      for (final frame in frames)
        frame.seconds == null
            ? frame.role.label
            : '${frame.role.label} at '
                  '${frame.seconds!.toStringAsFixed(frame.seconds! % 1 == 0 ? 0 : 1)} s',
      for (final reference in references)
        '${reference.kind.label} reference “${reference.label}”',
      if (source != null)
        item.mode == VideoMode.upscale
            ? 'the source film being upscaled'
            : item.mode == VideoMode.draftEnhance
            ? 'the draft being finished'
            : 'the film being continued',
    ];
    return parts.join(' · ');
  }

  /// The cost the card keeps behind a popover, said in full.
  Widget? _cost(BuildContext context, Generation item) {
    if (item.billingUnit == 'local') return null;
    final minimum = item.cost ?? item.estimatedCreditsMin;
    final maximum = item.cost ?? item.estimatedCreditsMax;
    if (minimum == null || maximum == null) return null;
    final realizedUsd = recordedRealizedCostUsd(item);
    final accountObservation = isAccountBalanceCostSource(
      item.realizedCostSource,
    );
    final exact = realizedUsd != null && countsTowardSpend(item);
    final usesUsd = item.billingUnit == 'usd';
    final amount = usesUsd
        ? formatUsdAmountRange(minimum, maximum)
        : '${formatCreditRange(minimum, maximum)} cr';
    final detailStyle = TextStyle(
      fontSize: 11,
      height: 1.45,
      color: context.colors.onSurfaceVariant,
    );
    return Column(
      key: const ValueKey('detail-cost'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 18),
        const Eyebrow('Cost', icon: Icons.toll_rounded),
        const SizedBox(height: 9),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: exact
                ? context.colors.primaryContainer
                : context.colors.secondaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.toll_rounded,
                size: 14,
                color: exact
                    ? context.colors.onPrimaryContainer
                    : context.colors.onSecondaryContainer,
              ),
              const SizedBox(width: 7),
              Text(
                '${exact
                    ? 'Realized'
                    : accountObservation
                    ? 'Account activity'
                    : 'Estimated'} $amount',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: exact
                      ? context.colors.onPrimaryContainer
                      : context.colors.onSecondaryContainer,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          usesUsd
              ? exact
                    ? 'Billed by ${providerNameForHistory(item.provider)} in US dollars.'
                    : 'Amounts shown in US dollars for ${providerNameForHistory(item.provider)}.'
              : 'About ${formatUsdRange(minimum, maximum)} at the published credit rate.',
          style: detailStyle,
        ),
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
        if (accountObservation)
          Text(
            'This balance change can include other jobs, deposits, or refunds. '
            'Task charge unconfirmed.',
            style: detailStyle,
          )
        else if (!exact && realizedUsd != null)
          Text(
            'Task charge unconfirmed · estimate '
            '${formatUsdAmount(realizedUsd)}',
            style: detailStyle,
          ),
      ],
    );
  }

  Widget _actions(BuildContext context, Generation item) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Expanded(
        child: Wrap(
          spacing: 7,
          runSpacing: 7,
          children: <Widget>[
            if (item.hasDeliveredMedia)
              FilledButton.tonalIcon(
                key: const ValueKey('detail-save'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(88, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                ),
                onPressed: _saving ? null : () => unawaited(_save(item)),
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_rounded, size: 16),
                label: const Text('Save'),
              ),
            if (_controller.canReuse(item))
              OutlinedButton.icon(
                key: const ValueKey('detail-reuse'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(88, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                ),
                onPressed: () =>
                    _leaveFor(() => unawaited(_controller.reuse(item))),
                icon: const Icon(Icons.replay_rounded, size: 16),
                label: Text(
                  item.isFailed && !item.hasDeliveredMedia ? 'Retry' : 'Reuse',
                ),
              ),
            if (_controller.canRewrite(item))
              OutlinedButton.icon(
                key: const ValueKey('detail-rewrite'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(88, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                ),
                onPressed: () => unawaited(
                  showPromptRewriteDialog(
                    context,
                    controller: _controller,
                    item: item,
                  ),
                ),
                icon: const Icon(Icons.auto_awesome_outlined, size: 16),
                label: const Text('AI Rewrite'),
              ),
            GenerationStatusButton(controller: _controller, item: item),
          ],
        ),
      ),
      const SizedBox(width: 4),
      // The card's ⋯ menu, minus the actions already on the row and minus
      // "Open film" — this is where that leads.
      GenerationActionsMenu(
        controller: _controller,
        item: item,
        includeSave: false,
        includeReuse: false,
        includeRewrite: false,
        includeCheckStatus: false,
        includeDetails: false,
        onMove: () => unawaited(
          showMoveToFolderDialog(
            context,
            FolderScope.generated(_controller),
            <String>{item.localId},
          ),
        ),
        onTag: () => unawaited(
          showGenerationTagDialog(context, controller: _controller, item: item),
        ),
        onVisibility: () => unawaited(
          _controller.setGenerationsHidden(<String>{
            item.localId,
          }, !item.hidden),
        ),
        onCopyToDrive:
            item.storage == LibraryStorage.local &&
                _controller.googleDriveConnected
            ? () => unawaited(
                _controller.copyLocalLibraryToGoogleDrive(
                  generationIds: <String>{item.localId},
                ),
              )
            : null,
        onDelete: () => unawaited(_delete(item)),
      ),
    ],
  );

  // ── provider details ──────────────────────────────────────────────────

  Widget _providerDetails(BuildContext context, Generation item) {
    final estimate = _controller.generationProgress(item);
    final lines = <Widget>[
      _DetailLine(label: 'State', value: item.statusLabel),
      _DetailLine(label: 'Provider', value: item.provider.toUpperCase()),
      _DetailLine(label: 'Model', value: item.model),
      _DetailLine(label: 'Submitted', value: formatTimestamp(item.createdAt)),
      if (item.providerAcceptedAt != null)
        _DetailLine(
          label: 'Provider accepted',
          value: formatTimestamp(item.providerAcceptedAt!),
        ),
      if (item.providerCompletedAt != null)
        _DetailLine(
          label: 'Completed',
          value: formatTimestamp(item.providerCompletedAt!),
        ),
      if (observedGenerationDuration(item) case final elapsed?)
        _DetailLine(
          label: 'Generation time',
          value: formatElapsedDuration(elapsed),
        ),
      if (item.isWorking && estimate.expectedDuration != null)
        _DetailLine(
          label: 'Estimated total',
          value: formatElapsedDuration(estimate.expectedDuration!),
        ),
      if (item.isWorking && estimate.isEstimated)
        _DetailLine(
          label: 'Estimate basis',
          value: estimate.basis == GenerationProgressBasis.historical
              ? '${estimate.sampleCount} similar personal ${estimate.sampleCount == 1 ? 'generation' : 'generations'} + benchmark'
              : 'Built-in Seedance 2.5 benchmark',
        ),
      if (item.requestId != null)
        _DetailLine(label: 'Request ID', value: item.requestId!),
      if (item.lastProviderStatusCode != null)
        _DetailLine(
          label: 'HTTP status',
          value: item.lastProviderStatusCode.toString(),
        ),
      if (item.lastProviderResponseAt != null)
        _DetailLine(
          label: 'Response received',
          value: formatTimestamp(item.lastProviderResponseAt!),
        ),
      if (item.error != null)
        _DetailBlock(
          label: 'Error',
          icon: Icons.error_outline_rounded,
          value: item.error!,
        ),
      if (item.resultRetentionError != null)
        _DetailBlock(
          label: 'Last result-retrieval error',
          icon: Icons.cloud_download_outlined,
          value: item.resultRetentionError!,
        ),
      if (item.lastCheckError != null)
        _DetailBlock(
          label: 'Last status-check error',
          icon: Icons.sync_problem_rounded,
          value: item.lastCheckError!,
        ),
      if (item.lastProviderResponse != null)
        _DetailBlock(
          label: 'Provider response',
          icon: Icons.data_object_rounded,
          value: item.lastProviderResponse!,
          monospace: true,
        ),
    ];
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            key: const ValueKey('detail-provider-toggle'),
            onTap: () =>
                setState(() => _providerDetailsOpen = !_providerDetailsOpen),
            child: Padding(
              // A 44 px row, so the accordion is a finger-sized target.
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.receipt_long_rounded,
                    size: 15,
                    color: context.tokens.brass,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Provider details',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.3,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _providerDetailsOpen ? .5 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: Icon(
                      Icons.expand_more_rounded,
                      size: 18,
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_providerDetailsOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: lines,
              ),
            ),
        ],
      ),
    );
  }
}

/// One label/value row of the provider readout.
class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            color: context.colors.onSurfaceVariant,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        SelectableText(value, style: const TextStyle(fontSize: 12)),
      ],
    ),
  );
}

/// A long value that gets its own eyebrow: an error, or the raw response.
class _DetailBlock extends StatelessWidget {
  const _DetailBlock({
    required this.label,
    required this.icon,
    required this.value,
    this.monospace = false,
  });

  final String label;
  final IconData icon;
  final String value;
  final bool monospace;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Eyebrow(label, icon: icon),
        const SizedBox(height: 7),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: context.colors.surfaceContainer,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: context.colors.outlineVariant),
          ),
          child: SelectableText(
            value,
            style: TextStyle(
              fontFamily: monospace ? 'monospace' : null,
              fontSize: monospace ? 11 : 12,
              height: 1.45,
            ),
          ),
        ),
      ],
    ),
  );
}

/// One film in the iterations strip: its frame, its first line, its age.
class _IterationCard extends StatelessWidget {
  const _IterationCard({
    required this.controller,
    required this.film,
    required this.label,
    this.summary,
    this.current = false,
    this.onOpen,
  });

  final AppController controller;
  final Generation film;
  final String label;

  /// The model's one-line account of the rewrite, when there is one.
  final String? summary;

  /// The film the modal is already showing: lit plum, and not a link.
  final bool current;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final accent = current
        ? context.colors.primary
        : context.colors.onSurfaceVariant;
    final card = Container(
      width: 168,
      margin: const EdgeInsets.only(right: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: current
            ? context.colors.primaryContainer.withValues(alpha: .35)
            : context.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: current
              ? context.colors.primary
              : context.colors.outlineVariant,
          width: current ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: 92,
            child: ColoredBox(
              color: Colors.black,
              child: film.hasDeliveredMedia
                  ? GenerationMedia(
                      controller: controller,
                      item: film,
                      showTimelineOverlay: false,
                    )
                  : GenerationErrorThumbnail.shouldShow(film)
                  ? GenerationErrorThumbnail(item: film, dense: true)
                  : GenerationInputPreview(controller: controller, item: film),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  composerTabTitle(film.title, film.displayPrompt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: context.colors.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  relativeTime(film.createdAt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    final open = onOpen;
    final body = open == null
        ? card
        : Stack(
            children: <Widget>[
              card,
              Positioned.fill(
                right: 10,
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    key: ValueKey<String>('detail-iteration-${film.localId}'),
                    onTap: open,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          );
    final message = summary?.trim() ?? '';
    return Tooltip(
      message: message.isNotEmpty
          ? message
          : current
          ? 'The film this modal is showing'
          : 'Open this film',
      child: body,
    );
  }
}

/// The source film is gone, but the record still remembers being a rewrite.
class _MissingSourceChip extends StatelessWidget {
  const _MissingSourceChip();

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('detail-iteration-missing'),
    width: 168,
    margin: const EdgeInsets.only(right: 10),
    padding: const EdgeInsets.all(12),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: context.colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: context.colors.outlineVariant),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(
          Icons.history_toggle_off_rounded,
          size: 18,
          color: context.colors.onSurfaceVariant,
        ),
        const SizedBox(height: 8),
        Text(
          'Rewritten from a removed film',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}
