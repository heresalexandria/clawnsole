import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import '../core/asset_extensions.dart';
import '../core/models.dart';
import 'common_widgets.dart';
import 'aesthetic_references.dart';
import 'filter_menu.dart';
import 'formatters.dart';
import 'media_picker_source.dart';
import 'library_folders.dart';
import 'media_thumbnail.dart';
import 'video_frame_loader.dart';
import 'video_metadata_loader.dart';
import 'visual_reference_viewer.dart';

Future<Uint8List?> _loadReferenceVideoPreview(
  PickedAsset asset,
  String source,
) {
  final path = asset.path?.trim() ?? '';
  final parsed = path.isEmpty ? null : Uri.tryParse(path);
  final uri = path.isEmpty
      ? Uri.parse(source)
      : kIsWeb && parsed?.hasScheme == true
      ? parsed!
      : Uri.file(path);
  return loadVideoFrame(uri, const Duration(milliseconds: 250));
}

class ReferencesScreen extends StatefulWidget {
  const ReferencesScreen({required this.controller, super.key});

  final AppController controller;

  @override
  State<ReferencesScreen> createState() => _ReferencesScreenState();
}

class _ReferencesScreenState extends State<ReferencesScreen> {
  static const int _pageSize = 20;

  final ScrollController _scrollController = ScrollController();
  int _itemLimit = _pageSize;
  String? _listingSignature;
  bool _pageAdvancePending = false;

  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadMoreNearEnd);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _loadMoreNearEnd() {
    if (_scrollController.position.extentAfter < 720) _loadMore();
  }

  void _loadMore() {
    final items = controller.filteredSavedReferences;
    if (_pageAdvancePending || _itemLimit >= items.length) return;
    _pageAdvancePending = true;
    final previousLimit = _itemLimit;
    setState(() => _itemLimit += _pageSize);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pageAdvancePending = false;
    });
    controller.prefetchListedVideos(
      items
          .skip(previousLimit)
          .take(_pageSize)
          .where(
            (item) =>
                item.kind == MediaReferenceKind.video &&
                item.thumbnailAsset == null,
          )
          .map((item) => item.asset),
    );
  }

  void _syncListingPage() {
    final signature = <Object?>[
      controller.referenceStorageFilter,
      controller.referenceFavoriteFilter,
      controller.referenceVisibilityFilter,
      controller.referenceFolderView,
      controller.referenceTag,
      controller.referenceKind,
      controller.referenceSort,
      controller.referenceSearch,
    ].join('|');
    if (_listingSignature == signature) return;
    _listingSignature = signature;
    _itemLimit = _pageSize;
    _pageAdvancePending = false;
  }

  @override
  Widget build(BuildContext context) {
    _syncListingPage();
    final scope = FolderScope.references(controller);
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 960;
        final padding = constraints.maxWidth < 620 ? 16.0 : 28.0;
        // The whole library is a drop target: local files dropped anywhere on
        // this screen save into the current folder, sorted into their kind by
        // MIME type or extension.
        return ReferenceDropZone(
          label: 'Drop to save references',
          onDropFiles: (files) => controller.importDroppedReferenceFiles(
            files,
            folderId:
                controller.referenceFolderView ==
                        AppController.libraryFolderAll ||
                    controller.referenceFolderView ==
                        AppController.libraryFolderUnfiled
                ? null
                : controller.referenceFolderView,
            videoPreviewLoader: _loadReferenceVideoPreview,
          ),
          child: FolderRailLayout(
            heading: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ReferencesHeading(controller: controller),
                AestheticReferenceLibrary(controller: controller),
              ],
            ),
            rail: FolderRail(scope: scope),
            narrowRail: FolderDropdownBar(scope: scope),
            results: _ReferenceResults(
              controller: controller,
              itemLimit: _itemLimit,
              onLoadMore: _loadMore,
              dragToFolders: desktop,
            ),
            scrollController: _scrollController,
            desktop: desktop,
            padding: padding,
          ),
        );
      },
    );
  }
}

class _ReferencesHeading extends StatelessWidget {
  const _ReferencesHeading({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Wrap(
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
                Text(
                  'REFERENCE LIBRARY',
                  style: TextStyle(
                    color: context.tokens.brass,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Your creative ingredients.',
                  style: Theme.of(context).textTheme.displayLarge,
                ),
                const SizedBox(height: 10),
                Text(
                  controller.supportsLocalLibrary
                      ? 'Keep reusable images, videos, and audio on this device or in Drive, then attach them from Create in a few clicks.'
                      : 'Keep reusable images, videos, and audio in Drive, then attach them from Create in a few clicks.',
                  style: TextStyle(color: context.colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              // Imports run on the background work queue, so the button stays
              // available while earlier files are still processing.
              final uploading = controller.referenceUploadInProgress;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  if (controller.supportsGoogleDrive)
                    DriveRefreshButton(
                      controller: controller,
                      keyPrefix: 'references',
                    ),
                  PopupMenuButton<MediaReferenceKind>(
                    tooltip: 'Add references',
                    onSelected: (kind) => unawaited(() async {
                      final source = await chooseMediaPickerSource(
                        context,
                        kind,
                      );
                      if (source == null) return;
                      await controller.importSavedReferences(
                        kind,
                        source: source,
                        previewLoader: kind == MediaReferenceKind.video
                            ? _loadReferenceVideoPreview
                            : null,
                        folderId:
                            controller.referenceFolderView ==
                                    AppController.libraryFolderAll ||
                                controller.referenceFolderView ==
                                    AppController.libraryFolderUnfiled
                            ? null
                            : controller.referenceFolderView,
                      );
                    }()),
                    itemBuilder: (context) => MediaReferenceKind.values
                        .map(
                          (kind) => PopupMenuItem<MediaReferenceKind>(
                            value: kind,
                            child: Row(
                              children: <Widget>[
                                Icon(mediaKindIcon(kind), size: 18),
                                const SizedBox(width: 10),
                                Text('Add ${kind.pluralLabel}'),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                    child: FilledButtonIconVisual(
                      icon: Icons.add_rounded,
                      label: 'Add references',
                      loading: uploading,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      ReferenceUploadIndicator(
        controller: controller,
        margin: const EdgeInsets.only(top: 12),
      ),
    ],
  );
}

class FilledButtonIconVisual extends StatelessWidget {
  const FilledButtonIconVisual({
    required this.icon,
    required this.label,
    this.loading = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool loading;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: FilledButton.icon(
      onPressed: loading ? null : () {},
      icon: loading
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon),
      label: Text(label),
    ),
  );
}

class _ReferenceResults extends StatefulWidget {
  const _ReferenceResults({
    required this.controller,
    required this.itemLimit,
    required this.onLoadMore,
    required this.dragToFolders,
  });

  final AppController controller;
  final int itemLimit;
  final VoidCallback onLoadMore;

  /// Whether cards can be dragged onto the folder rail (wide layouts only).
  final bool dragToFolders;

  @override
  State<_ReferenceResults> createState() => _ReferenceResultsState();
}

class _ReferenceResultsState extends State<_ReferenceResults> {
  final Set<String> selectedIds = <String>{};
  bool selecting = false;

  AppController get controller => widget.controller;

  void _setSelecting(bool value) => setState(() {
    selecting = value;
    if (!value) selectedIds.clear();
  });

  void _toggle(String id) => setState(() {
    if (!selectedIds.add(id)) selectedIds.remove(id);
  });

  /// What dragging [item] carries: the whole selection when the card is part
  /// of one (and the selection shares a storage), otherwise the card alone.
  LibraryDragData _dragDataFor(SavedReference item) {
    var ids = selecting && selectedIds.contains(item.id)
        ? Set<String>.of(selectedIds)
        : <String>{item.id};
    final storages = controller.savedReferences
        .where((candidate) => ids.contains(candidate.id))
        .map((candidate) => candidate.storage)
        .toSet();
    if (storages.length != 1) ids = <String>{item.id};
    return LibraryDragData(
      collection: LibraryCollection.references,
      storage: item.storage,
      itemIds: ids,
      label:
          'Move ${ids.length} ${ids.length == 1 ? 'reference' : 'references'}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = controller.filteredSavedReferences;
    final imports = controller.filteredReferenceImports;
    final shown = filtered.take(widget.itemLimit).toList();
    final selected = controller.savedReferences
        .where((item) => selectedIds.contains(item.id))
        .toList();
    final selectedAreHidden =
        selected.isNotEmpty && selected.every((item) => item.hidden);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _ReferenceToolbar(
          controller: controller,
          selecting: selecting,
          selectedCount: selected.length,
          onSelectingChanged: _setSelecting,
        ),
        if (DriveReconnectNotice.needed(controller)) ...<Widget>[
          const SizedBox(height: 12),
          DriveReconnectNotice(controller: controller, subject: 'references'),
        ],
        if (selecting) ...<Widget>[
          const SizedBox(height: 10),
          _ReferenceBulkActions(
            selectedCount: selected.length,
            allVisibleSelected:
                filtered.isNotEmpty &&
                filtered.every((item) => selectedIds.contains(item.id)),
            onSelectAll: () => setState(() {
              final ids = filtered.map((item) => item.id).toSet();
              if (ids.every(selectedIds.contains)) {
                selectedIds.removeAll(ids);
              } else {
                selectedIds.addAll(ids);
              }
            }),
            onMove: selected.isEmpty
                ? null
                : () async {
                    final moved = await showMoveToFolderDialog(
                      context,
                      FolderScope.references(controller),
                      Set<String>.of(selectedIds),
                    );
                    if (moved && mounted) _setSelecting(false);
                  },
            onVisibility: selected.isEmpty
                ? null
                : () async {
                    final saved = await controller.setReferencesHidden(
                      selectedIds,
                      !selectedAreHidden,
                    );
                    if (saved && mounted) _setSelecting(false);
                  },
            visibilityLabel: selectedAreHidden ? 'Unhide' : 'Hide',
            onDone: () => _setSelecting(false),
          ),
        ],
        const SizedBox(height: 18),
        if (filtered.isEmpty && imports.isEmpty)
          _ReferenceEmpty(controller: controller)
        else
          LayoutBuilder(
            builder: (context, grid) {
              final columns = grid.maxWidth >= 1120
                  ? 4
                  : grid.maxWidth >= 760
                  ? 3
                  : grid.maxWidth >= 480
                  ? 2
                  : 1;
              const gap = 16.0;
              final width = (grid.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: <Widget>[
                  ...imports.map(
                    (item) => SizedBox(
                      width: width,
                      child: _ReferenceImportCard(import: item),
                    ),
                  ),
                  ...shown.map(
                    (item) => SizedBox(
                      width: width,
                      child: LibraryDraggable(
                        data: _dragDataFor(item),
                        enabled: widget.dragToFolders,
                        child: Stack(
                          children: <Widget>[
                            _ReferenceCard(
                              controller: controller,
                              reference: item,
                            ),
                            if (selecting)
                              Positioned(
                                top: 8,
                                left: 8,
                                child: Material(
                                  elevation: 7,
                                  color: context.colors.surface,
                                  borderRadius: BorderRadius.circular(9),
                                  child: IconButton(
                                    key: ValueKey(
                                      'select-reference-${item.id}',
                                    ),
                                    tooltip: selectedIds.contains(item.id)
                                        ? 'Deselect ${item.name}'
                                        : 'Select ${item.name}',
                                    onPressed: () => _toggle(item.id),
                                    icon: Icon(
                                      selectedIds.contains(item.id)
                                          ? Icons.check_box_rounded
                                          : Icons
                                                .check_box_outline_blank_rounded,
                                      color: selectedIds.contains(item.id)
                                          ? context.tokens.brass
                                          : null,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        if (shown.length < filtered.length) ...<Widget>[
          const SizedBox(height: 14),
          Center(
            child: TextButton.icon(
              key: const ValueKey('references-load-more'),
              onPressed: widget.onLoadMore,
              icon: const Icon(Icons.expand_more_rounded),
              label: Text(
                'Load ${((filtered.length - shown.length).clamp(0, 20))} more',
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ReferenceImportCard extends StatelessWidget {
  const _ReferenceImportCard({required this.import});

  final ReferenceImportProgress import;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: '${import.name}: ${import.statusLabel}',
    child: SurfaceCard(
      key: ValueKey('reference-import-${import.id}'),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AspectRatio(
            aspectRatio: 16 / 9,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.colors.surfaceContainerLow,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  Icon(
                    mediaKindIcon(import.kind),
                    size: 46,
                    color: context.colors.onSurfaceVariant.withValues(
                      alpha: .34,
                    ),
                  ),
                  const SizedBox.square(
                    dimension: 34,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  import.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 7),
                Row(
                  children: <Widget>[
                    const SizedBox.square(
                      dimension: 13,
                      child: CircularProgressIndicator(strokeWidth: 1.8),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        import.statusLabel,
                        key: ValueKey('reference-import-status-${import.id}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _ReferenceToolbar extends StatelessWidget {
  const _ReferenceToolbar({
    required this.controller,
    required this.selecting,
    required this.selectedCount,
    required this.onSelectingChanged,
  });

  final AppController controller;
  final bool selecting;
  final int selectedCount;
  final ValueChanged<bool> onSelectingChanged;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.all(10),
    child: LayoutBuilder(
      builder: (context, constraints) {
        // Wide enough for one line of segments, a usable search field, and
        // the keys; a 1280-px window with the side rail lands just above.
        final wide = constraints.maxWidth >= 860;
        // Media kind is the always-visible facet; its counts reflect every
        // other active filter so they describe the folder in view.
        final keys = <Widget>[
          ConsoleFilterSegment(
            key: const ValueKey('reference-kind-all'),
            label: 'All',
            semanticLabel: 'All references',
            icon: Icons.grid_view_rounded,
            count: controller.referenceKindCount(null),
            selected: controller.referenceKind == null,
            onTap: () => controller.setReferenceKind(null),
          ),
          ...MediaReferenceKind.values.map(
            (kind) => ConsoleFilterSegment(
              key: ValueKey('reference-kind-${kind.name}'),
              label: kind.label,
              icon: mediaKindIcon(kind),
              count: controller.referenceKindCount(kind),
              selected: controller.referenceKind == kind,
              onTap: () => controller.setReferenceKind(kind),
            ),
          ),
        ];
        final segments = wide
            ? Wrap(spacing: 5, runSpacing: 5, children: keys)
            : ConsoleSegmentStrip(children: keys);
        final search = TextField(
          key: const ValueKey('reference-library-search'),
          onChanged: controller.setReferenceSearch,
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded, size: 18),
            hintText: 'Search names, tags, folders',
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        );
        final sortButton = ReferenceSortButton(
          controller: controller,
          compact: !wide,
        );
        final filterButton = LibraryFilterButton(
          controller: controller,
          collection: LibraryCollection.references,
          compact: !wide,
        );
        final selectIcon = Icon(
          selecting ? Icons.close_rounded : Icons.check_box_outlined,
          size: 17,
        );
        // Narrow toolbars keep Select as an icon key; the bulk bar beneath
        // already spells out the selected count.
        final selectButton = wide
            ? OutlinedButton.icon(
                key: const ValueKey('reference-select-button'),
                onPressed: () => onSelectingChanged(!selecting),
                icon: selectIcon,
                label: Text(
                  selecting && selectedCount > 0
                      ? '$selectedCount selected'
                      : 'Select',
                ),
              )
            : Tooltip(
                message: selecting ? 'Done selecting' : 'Select',
                child: OutlinedButton(
                  key: const ValueKey('reference-select-button'),
                  onPressed: () => onSelectingChanged(!selecting),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: selectIcon,
                ),
              );
        if (wide) {
          // The segments keep their natural single line; the search field is
          // what gives up width first on narrower desktops.
          return Row(
            children: <Widget>[
              segments,
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: search,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              sortButton,
              const SizedBox(width: 8),
              filterButton,
              const SizedBox(width: 8),
              selectButton,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            search,
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(child: segments),
                const SizedBox(width: 8),
                sortButton,
                const SizedBox(width: 8),
                filterButton,
                const SizedBox(width: 8),
                selectButton,
              ],
            ),
          ],
        );
      },
    ),
  );
}

class _ReferenceBulkActions extends StatelessWidget {
  const _ReferenceBulkActions({
    required this.selectedCount,
    required this.allVisibleSelected,
    required this.onSelectAll,
    required this.onMove,
    required this.onVisibility,
    required this.visibilityLabel,
    required this.onDone,
  });

  final int selectedCount;
  final bool allVisibleSelected;
  final VoidCallback onSelectAll;
  final VoidCallback? onMove;
  final VoidCallback? onVisibility;
  final String visibilityLabel;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: context.colors.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$selectedCount selected',
            style: TextStyle(
              color: context.colors.onPrimaryContainer,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        TextButton.icon(
          onPressed: onSelectAll,
          icon: Icon(
            allVisibleSelected
                ? Icons.deselect_rounded
                : Icons.select_all_rounded,
            size: 18,
          ),
          label: Text(
            allVisibleSelected ? 'Deselect visible' : 'Select visible',
          ),
        ),
        FilledButton.tonalIcon(
          key: const ValueKey('reference-bulk-move'),
          onPressed: onMove,
          icon: const Icon(Icons.drive_file_move_outline, size: 18),
          label: const Text('Move'),
        ),
        OutlinedButton.icon(
          onPressed: onVisibility,
          icon: Icon(
            visibilityLabel == 'Hide'
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            size: 18,
          ),
          label: Text(visibilityLabel),
        ),
        TextButton(onPressed: onDone, child: const Text('Done')),
      ],
    ),
  );
}

class _ReferenceCard extends StatelessWidget {
  const _ReferenceCard({required this.controller, required this.reference});

  final AppController controller;
  final SavedReference reference;

  @override
  Widget build(BuildContext context) {
    final isVideo = reference.kind == MediaReferenceKind.video;
    final restored = isVideo
        ? controller.cachedReferencePreview(reference)
        : controller.cachedAssetBytes(reference.asset);
    final thumbnail = MediaThumbnail(
      gateway: controller.gateway,
      kind: reference.kind,
      bytes: isVideo ? null : restored,
      reference: reference.asset,
      thumbnailReference: reference.thumbnailAsset,
      thumbnailBytes: isVideo ? restored : null,
      mediaUriLoader: isVideo
          ? () => controller.referencePreviewSourceUri(reference)
          : null,
      mediaUriRevision: isVideo ? controller.videoPreviewSourceRevision : null,
      semanticsLabel: '${reference.name} thumbnail',
      onThumbnail: isVideo
          ? (bytes) =>
                unawaited(controller.cacheReferencePreview(reference, bytes))
          : null,
      onVideoMetadata: isVideo
          ? (metadata) {
              if (!metadata.isUsable) return;
              unawaited(
                controller.rememberSavedReferenceDuration(
                  reference,
                  metadata.durationSeconds,
                ),
              );
            }
          : null,
      onMediaDuration: reference.kind == MediaReferenceKind.audio
          ? (seconds) => unawaited(
              controller.rememberSavedReferenceDuration(reference, seconds),
            )
          : null,
    );
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Semantics(
                button: reference.kind != MediaReferenceKind.audio,
                label: 'View ${reference.name} full screen',
                child: InkWell(
                  key: ValueKey('view-saved-reference-${reference.id}'),
                  onTap: reference.kind == MediaReferenceKind.audio
                      ? null
                      : () => unawaited(
                          showSavedReferenceViewer(
                            context,
                            controller,
                            reference,
                          ),
                        ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      thumbnail,
                      if (isVideo && restored != null)
                        const Center(
                          child: Icon(
                            Icons.play_circle_fill_rounded,
                            size: 46,
                            color: Colors.white,
                            shadows: <Shadow>[
                              Shadow(color: Colors.black54, blurRadius: 12),
                            ],
                          ),
                        ),
                      if (reference.durationSeconds != null)
                        Positioned(
                          left: 8,
                          bottom: 8,
                          child: MediaDurationBadge(
                            text: formatMediaDuration(
                              reference.durationSeconds!,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 12, 8, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      InkWell(
                        key: ValueKey('rename-saved-reference-${reference.id}'),
                        borderRadius: BorderRadius.circular(5),
                        onTap: () => unawaited(
                          showReferenceMetadataDialog(
                            context,
                            controller,
                            reference: reference,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            reference.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${reference.kind.label}${reference.durationSeconds == null ? '' : ' · ${formatMediaDuration(reference.durationSeconds!)}'} · ${reference.storage.shortLabel}${savedReferencePendingDriveUpload(reference) ? ' · Syncing…' : ''}${reference.folderId == null ? '' : ' · ${controller.folderPath(reference.folderId!, collection: LibraryCollection.references)}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                      if (reference.characterName?.isNotEmpty == true)
                        Text(
                          'Character · ${reference.characterName}',
                          style: TextStyle(
                            color: context.colors.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      if (reference.tags.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 7),
                        Text(
                          reference.tags.map((tag) => '#$tag').join('  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: context.colors.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                TextButton(
                  key: ValueKey('reference-details-${reference.id}'),
                  onPressed: () => unawaited(
                    showReferenceDetails(context, controller, reference),
                  ),
                  child: const Text('Details'),
                ),
                IconButton(
                  tooltip: reference.favorite
                      ? 'Remove from favorites'
                      : 'Add to favorites',
                  onPressed: () =>
                      unawaited(controller.toggleReferenceFavorite(reference)),
                  icon: Icon(
                    reference.favorite
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: reference.favorite ? context.tokens.brass : null,
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: '${reference.name} options',
                  onSelected: (value) {
                    if (value == 'edit') {
                      unawaited(
                        showReferenceMetadataDialog(
                          context,
                          controller,
                          reference: reference,
                        ),
                      );
                    } else if (value == 'move') {
                      unawaited(
                        showMoveToFolderDialog(
                          context,
                          FolderScope.references(controller),
                          <String>{reference.id},
                        ),
                      );
                    } else if (value == 'trim') {
                      unawaited(
                        showReferenceTrimDialog(context, controller, reference),
                      );
                    } else if (value == 'tag') {
                      unawaited(
                        _showReferenceTagDialog(context, controller, reference),
                      );
                    } else if (value == 'visibility') {
                      unawaited(
                        controller.setReferencesHidden(<String>{
                          reference.id,
                        }, !reference.hidden),
                      );
                    } else if (value == 'copy') {
                      unawaited(
                        controller.copyLocalLibraryToGoogleDrive(
                          referenceIds: <String>{reference.id},
                        ),
                      );
                    } else {
                      unawaited(
                        _confirmReferenceDelete(context, controller, reference),
                      );
                    }
                  },
                  itemBuilder: (context) => <PopupMenuEntry<String>>[
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('Edit details'),
                    ),
                    if (reference.kind == MediaReferenceKind.video)
                      const PopupMenuItem(
                        value: 'trim',
                        child: Text('Trim as new reference'),
                      ),
                    const PopupMenuItem(value: 'move', child: Text('Move')),
                    const PopupMenuItem(value: 'tag', child: Text('Tag')),
                    PopupMenuItem(
                      value: 'visibility',
                      child: Text(reference.hidden ? 'Unhide' : 'Hide'),
                    ),
                    if (reference.storage == LibraryStorage.local &&
                        controller.googleDriveConnected)
                      PopupMenuItem(
                        value: 'copy',
                        enabled: !controller.isCopyingReference(reference.id),
                        child: Row(
                          children: <Widget>[
                            if (controller.isCopyingReference(
                              reference.id,
                            )) ...<Widget>[
                              const SizedBox.square(
                                dimension: 15,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Text(
                              controller.isCopyingReference(reference.id)
                                  ? 'Copying to Google Drive…'
                                  : 'Copy to Google Drive',
                            ),
                          ],
                        ),
                      ),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
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

Future<void> showReferenceDetails(
  BuildContext context,
  AppController controller,
  SavedReference reference,
) => Navigator.of(context).push<void>(
  MaterialPageRoute<void>(
    builder: (context) =>
        ReferenceDetailsScreen(controller: controller, reference: reference),
  ),
);

class ReferenceDetailsScreen extends StatefulWidget {
  const ReferenceDetailsScreen({
    required this.controller,
    required this.reference,
    super.key,
  });

  final AppController controller;
  final SavedReference reference;

  @override
  State<ReferenceDetailsScreen> createState() => _ReferenceDetailsScreenState();
}

class _ReferenceDetailsScreenState extends State<ReferenceDetailsScreen> {
  AppController get controller => widget.controller;

  SavedReference get reference =>
      controller.savedReferences
          .where((item) => item.id == widget.reference.id)
          .firstOrNull ??
      widget.reference;

  @override
  void initState() {
    super.initState();
    controller.addListener(_refresh);
  }

  @override
  void dispose() {
    controller.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final reference = this.reference;
    final usages = controller.generationsUsingReference(reference);
    final folder = reference.folderId == null
        ? null
        : controller.folderPath(
            reference.folderId!,
            collection: LibraryCollection.references,
          );
    return Scaffold(
      key: ValueKey('reference-details-screen-${reference.id}'),
      appBar: AppBar(title: const Text('Reference details')),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width < 620 ? 16 : 28,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  reference.name,
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  '${reference.kind.label} · ${reference.storage.label}'
                  '${reference.durationSeconds == null ? '' : ' · ${formatMediaDuration(reference.durationSeconds!)}'}'
                  '${folder == null ? '' : ' · $folder'}',
                  style: TextStyle(color: context.colors.onSurfaceVariant),
                ),
                const SizedBox(height: 18),
                SurfaceCard(
                  padding: EdgeInsets.zero,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Semantics(
                      button: reference.kind != MediaReferenceKind.audio,
                      label: 'View ${reference.name} full screen',
                      child: InkWell(
                        key: ValueKey(
                          'view-reference-details-media-${reference.id}',
                        ),
                        onTap: reference.kind == MediaReferenceKind.audio
                            ? null
                            : () => unawaited(
                                showSavedReferenceViewer(
                                  context,
                                  controller,
                                  reference,
                                ),
                              ),
                        child: SizedBox(
                          height: 360,
                          child: Stack(
                            fit: StackFit.expand,
                            children: <Widget>[
                              ColoredBox(
                                color: Colors.black,
                                child: MediaThumbnail(
                                  gateway: controller.gateway,
                                  kind: reference.kind,
                                  bytes:
                                      reference.kind == MediaReferenceKind.image
                                      ? controller.cachedAssetBytes(
                                          reference.asset,
                                        )
                                      : null,
                                  reference: reference.asset,
                                  thumbnailReference: reference.thumbnailAsset,
                                  thumbnailBytes:
                                      reference.kind == MediaReferenceKind.video
                                      ? controller.cachedReferencePreview(
                                          reference,
                                        )
                                      : null,
                                  mediaUriLoader:
                                      reference.kind == MediaReferenceKind.video
                                      ? () => controller
                                            .referencePreviewSourceUri(
                                              reference,
                                            )
                                      : null,
                                  mediaUriRevision:
                                      reference.kind == MediaReferenceKind.video
                                      ? controller.videoPreviewSourceRevision
                                      : null,
                                  fit: BoxFit.contain,
                                  semanticsLabel:
                                      '${reference.name} reference preview',
                                  onThumbnail:
                                      reference.kind == MediaReferenceKind.video
                                      ? (bytes) => unawaited(
                                          controller.cacheReferencePreview(
                                            reference,
                                            bytes,
                                          ),
                                        )
                                      : null,
                                  onVideoMetadata:
                                      reference.kind == MediaReferenceKind.video
                                      ? (metadata) => unawaited(
                                          controller
                                              .rememberSavedReferenceDuration(
                                                reference,
                                                metadata.durationSeconds,
                                              ),
                                        )
                                      : null,
                                  onMediaDuration:
                                      reference.kind == MediaReferenceKind.audio
                                      ? (seconds) => unawaited(
                                          controller
                                              .rememberSavedReferenceDuration(
                                                reference,
                                                seconds,
                                              ),
                                        )
                                      : null,
                                ),
                              ),
                              if (reference.kind == MediaReferenceKind.video &&
                                  controller.cachedReferencePreview(
                                        reference,
                                      ) !=
                                      null)
                                const Center(
                                  child: Icon(
                                    Icons.play_circle_fill_rounded,
                                    size: 64,
                                    color: Colors.white,
                                    shadows: <Shadow>[
                                      Shadow(
                                        color: Colors.black54,
                                        blurRadius: 14,
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (reference.kind == MediaReferenceKind.video) ...<Widget>[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      key: ValueKey('trim-reference-details-${reference.id}'),
                      onPressed: () => unawaited(
                        showReferenceTrimDialog(context, controller, reference),
                      ),
                      icon: const Icon(Icons.content_cut_rounded, size: 18),
                      label: const Text('Trim as new reference'),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SurfaceCard(
                  child: Wrap(
                    spacing: 24,
                    runSpacing: 12,
                    children: <Widget>[
                      _ReferenceDetailFact(
                        label: 'Added',
                        value: formatTimestamp(reference.createdAt),
                      ),
                      _ReferenceDetailFact(
                        label: 'Updated',
                        value: formatTimestamp(reference.updatedAt),
                      ),
                      if (reference.durationSeconds != null)
                        _ReferenceDetailFact(
                          label: 'Duration',
                          value: formatMediaDuration(
                            reference.durationSeconds!,
                          ),
                        ),
                      if (reference.tags.isNotEmpty)
                        _ReferenceDetailFact(
                          label: 'Tags',
                          value: reference.tags
                              .map((tag) => '#$tag')
                              .join('  '),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  usages.length == 1
                      ? 'Used in 1 generation'
                      : 'Used in ${usages.length} generations',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 10),
                if (usages.isEmpty)
                  SurfaceCard(
                    child: Text(
                      'No saved generations use this reference yet.',
                      style: TextStyle(color: context.colors.onSurfaceVariant),
                    ),
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 840 ? 2 : 1;
                      const gap = 16.0;
                      final width =
                          (constraints.maxWidth - gap * (columns - 1)) /
                          columns;
                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: usages
                            .map(
                              (item) => SizedBox(
                                width: width,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: <Widget>[
                                    ActivityCard(
                                      controller: controller,
                                      item: item,
                                    ),
                                    const SizedBox(height: 6),
                                    OutlinedButton.icon(
                                      key: ValueKey(
                                        'reference-generation-details-${item.localId}',
                                      ),
                                      onPressed: () => unawaited(
                                        showGenerationDetails(
                                          context,
                                          item,
                                          progressEstimate: controller
                                              .generationProgress(item),
                                        ),
                                      ),
                                      icon: const Icon(
                                        Icons.receipt_long_rounded,
                                        size: 16,
                                      ),
                                      label: const Text(
                                        'View generation details',
                                      ),
                                    ),
                                  ],
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
      ),
    );
  }
}

class _ReferenceDetailFact extends StatelessWidget {
  const _ReferenceDetailFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 360),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: context.tokens.brass,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(value),
      ],
    ),
  );
}

class _ReferenceEmpty extends StatelessWidget {
  const _ReferenceEmpty({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 55, horizontal: 20),
      child: Column(
        children: <Widget>[
          Icon(
            Icons.collections_bookmark_outlined,
            size: 46,
            color: context.tokens.brass,
          ),
          const SizedBox(height: 14),
          Text(
            controller.savedReferences.isEmpty
                ? 'No saved references yet.'
                : 'Nothing in this view.',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            controller.savedReferences.isEmpty
                ? 'Upload media here, or bookmark an input from the Create screen.'
                : 'Try another folder, type, tag, sort, or a broader search.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colors.onSurfaceVariant),
          ),
        ],
      ),
    ),
  );
}

Future<void> _showReferenceTagDialog(
  BuildContext context,
  AppController controller,
  SavedReference reference,
) => showDialog<void>(
  context: context,
  builder: (context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _ReferenceTagEditor(
          controller: controller,
          reference: reference,
        ),
      ),
    ),
  ),
);

class _ReferenceTagEditor extends StatefulWidget {
  const _ReferenceTagEditor({
    required this.controller,
    required this.reference,
  });

  final AppController controller;
  final SavedReference reference;

  @override
  State<_ReferenceTagEditor> createState() => _ReferenceTagEditorState();
}

class _ReferenceTagEditorState extends State<_ReferenceTagEditor> {
  late final List<String> tags = List<String>.from(widget.reference.tags);
  final tagController = TextEditingController();
  final tagFocusNode = FocusNode();
  String? error;
  bool saving = false;

  bool _hasTag(String value) =>
      tags.any((tag) => tag.toLowerCase() == value.toLowerCase());

  void _add([String? value]) {
    final clean = (value ?? tagController.text)
        .trim()
        .replaceFirst(RegExp(r'^#+'), '')
        .trim();
    if (clean.isEmpty) return;
    if (clean.length > 28 || (tags.length >= 12 && !_hasTag(clean))) {
      setState(
        () => error = clean.length > 28
            ? 'Keep tags to 28 characters or fewer.'
            : 'A reference can have up to 12 tags.',
      );
      return;
    }
    setState(() {
      if (!_hasTag(clean)) tags.add(clean);
      tagController.clear();
      error = null;
    });
  }

  @override
  void dispose() {
    tagController.dispose();
    tagFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Text('Tag reference', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 6),
      Text(
        widget.reference.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: context.colors.onSurfaceVariant),
      ),
      const SizedBox(height: 18),
      if (tags.isNotEmpty) ...<Widget>[
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 145),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: context.colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.colors.outlineVariant),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(10),
              child: Wrap(
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
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
      RawAutocomplete<String>(
        textEditingController: tagController,
        focusNode: tagFocusNode,
        optionsBuilder: (value) {
          final query = value.text.trim().toLowerCase();
          return widget.controller.referenceTags.where(
            (tag) =>
                !_hasTag(tag) &&
                (query.isEmpty || tag.toLowerCase().contains(query)),
          );
        },
        onSelected: _add,
        fieldViewBuilder: (context, fieldController, focusNode, onSubmit) =>
            TextField(
              controller: fieldController,
              focusNode: focusNode,
              enabled: !saving,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Add tags',
                hintText: 'Type to find or create a tag',
                prefixIcon: const Icon(Icons.sell_outlined),
                suffixIcon: IconButton(
                  onPressed: saving ? null : _add,
                  icon: const Icon(Icons.add_rounded),
                ),
                errorText: error,
                helperText:
                    'Choose an existing tag or press Enter to create it.',
              ),
              onSubmitted: saving ? null : _add,
            ),
        optionsViewBuilder: (context, onSelected, options) => Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 10,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 470, maxHeight: 210),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 6),
                children: options
                    .map(
                      (tag) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.sell_outlined, size: 18),
                        title: Text('#$tag'),
                        onTap: () => onSelected(tag),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 22),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: saving
                ? null
                : () async {
                    if (tagController.text.trim().isNotEmpty) _add();
                    if (error != null) return;
                    setState(() => saving = true);
                    final saved = await widget.controller.tagReference(
                      widget.reference.id,
                      tags,
                    );
                    if (saved && context.mounted) {
                      Navigator.pop(context);
                    } else if (mounted) {
                      setState(() => saving = false);
                    }
                  },
            icon: saving
                ? const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded, size: 18),
            label: const Text('Save tags'),
          ),
        ],
      ),
    ],
  );
}

Future<bool> showReferenceMetadataDialog(
  BuildContext context,
  AppController controller, {
  SavedReference? reference,
  MediaReferenceDraft? draft,
}) async {
  assert(reference != null || draft != null);
  final name = TextEditingController(text: reference?.name ?? draft!.label);
  final tags = TextEditingController(text: reference?.tags.join(', ') ?? '');
  final character = TextEditingController(
    text:
        reference?.characterName ??
        (draft == null ? '' : controller.characterNameForDraft(draft)),
  );
  String? characterError;
  var folderId = reference?.folderId;
  var destination = reference?.storage ?? controller.effectiveStorage;
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(reference == null ? 'Save reference' : 'Edit reference'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (reference == null &&
                    controller.supportsLocalLibrary &&
                    controller.supportsGoogleDrive) ...<Widget>[
                  DropdownButtonFormField<LibraryStorage>(
                    initialValue: destination,
                    decoration: const InputDecoration(
                      labelText: 'Save in',
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
                    onChanged: (value) => setState(() {
                      destination = value ?? destination;
                      folderId = null;
                    }),
                  ),
                  const SizedBox(height: 10),
                ] else ...<Widget>[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: StorageBadge(storage: destination),
                  ),
                  const SizedBox(height: 10),
                ],
                if ((reference?.durationSeconds ?? draft?.durationSeconds) !=
                    null) ...<Widget>[
                  Text(
                    'Duration · ${formatMediaDuration((reference?.durationSeconds ?? draft!.durationSeconds)!)}',
                    style: TextStyle(
                      color: context.colors.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(
                  controller: name,
                  autofocus: true,
                  maxLength: 80,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 10),
                if ((reference?.kind ?? draft?.kind) !=
                    MediaReferenceKind.audio) ...[
                  TextField(
                    key: const ValueKey('reference-character-name'),
                    controller: character,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 60,
                    decoration: InputDecoration(
                      labelText: 'Character name',
                      hintText: 'ALEXANDRIA',
                      errorText: characterError,
                      helperText:
                          'Optional, unique. Used to cast this reference in a screenplay.',
                      helperMaxLines: 2,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                DropdownButtonFormField<String?>(
                  initialValue: folderId,
                  decoration: const InputDecoration(labelText: 'Folder'),
                  items: <DropdownMenuItem<String?>>[
                    const DropdownMenuItem(value: null, child: Text('Unfiled')),
                    ...controller.referenceFolderTree
                        .where((folder) => folder.storage == destination)
                        .map(
                          (folder) => DropdownMenuItem(
                            value: folder.id,
                            child: Text(
                              controller.folderPath(
                                folder.id,
                                collection: LibraryCollection.references,
                              ),
                            ),
                          ),
                        ),
                  ],
                  onChanged: (value) => setState(() => folderId = value),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: tags,
                  decoration: const InputDecoration(
                    labelText: 'Tags',
                    hintText: 'character, product, motion',
                    helperText: 'Separate tags with commas',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final problem = controller.characterNameProblem(
                character.text,
                excludeDraftId: draft?.id,
                excludeSavedReferenceId:
                    reference?.id ?? draft?.savedReferenceId,
              );
              if (problem != null) {
                setState(() => characterError = problem);
                return;
              }
              final values = tags.text.split(',');
              final success = reference == null
                  ? await controller.saveDraftReference(
                          draft!,
                          name: name.text,
                          characterName: character.text,
                          folderId: folderId,
                          tags: values,
                          storage: destination,
                        ) !=
                        null
                  : await controller.updateSavedReference(
                      reference,
                      name: name.text,
                      characterName: character.text,
                      folderId: folderId,
                      tags: values,
                    );
              if (success && context.mounted) Navigator.pop(context, true);
            },
            child: Text(reference == null ? 'Save' : 'Update'),
          ),
        ],
      ),
    ),
  );
  name.dispose();
  tags.dispose();
  character.dispose();
  return saved == true;
}

Future<bool> showReferenceTrimDialog(
  BuildContext context,
  AppController controller,
  SavedReference reference,
) async =>
    (await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          _ReferenceTrimDialog(controller: controller, reference: reference),
    )) ==
    true;

class _ReferenceTrimDialog extends StatefulWidget {
  const _ReferenceTrimDialog({
    required this.controller,
    required this.reference,
  });

  final AppController controller;
  final SavedReference reference;

  @override
  State<_ReferenceTrimDialog> createState() => _ReferenceTrimDialogState();
}

class _ReferenceTrimDialogState extends State<_ReferenceTrimDialog> {
  late final TextEditingController _name;
  double? _duration;
  double _startSeconds = 0;
  double? _endSeconds;
  bool _saving = false;
  bool _loadingDuration = false;
  bool _durationFailed = false;
  ValueListenable<double?>? _downloadProgress;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.controller.suggestedTrimmedReferenceName(widget.reference),
    );
    _duration = widget.reference.durationSeconds;
    _endSeconds = _duration;
    if (_duration == null) unawaited(_loadDuration());
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Reads the video duration deliberately instead of waiting on the
  /// thumbnail's silent best-effort probe: a Drive-backed video shows its
  /// download progress here, and any failure surfaces as a Retry instead of
  /// an endless spinner.
  Future<void> _loadDuration() async {
    if (_loadingDuration || _duration != null) return;
    final delivery = widget.controller.referenceMediaDelivery(widget.reference);
    setState(() {
      _loadingDuration = true;
      _durationFailed = false;
      _downloadProgress = delivery.progress;
    });
    try {
      final uri = await delivery.uri;
      if (uri == null) {
        throw StateError('The reference video is unavailable.');
      }
      final metadata = await loadVideoMetadata(uri);
      if (metadata == null || !metadata.isUsable) {
        throw StateError('The video duration could not be read.');
      }
      _rememberMetadata(metadata);
    } on Object {
      if (mounted && _duration == null) {
        setState(() => _durationFailed = true);
      }
    } finally {
      if (mounted) setState(() => _loadingDuration = false);
    }
  }

  void _rememberMetadata(VideoSourceMetadata metadata) {
    if (!metadata.isUsable) return;
    unawaited(
      widget.controller.rememberSavedReferenceDuration(
        widget.reference,
        metadata.durationSeconds,
      ),
    );
    if (_duration != null || !mounted) return;
    setState(() {
      _duration = metadata.durationSeconds;
      _endSeconds = metadata.durationSeconds;
      _durationFailed = false;
    });
  }

  Future<void> _save() async {
    final end = _endSeconds;
    if (_saving || _duration == null || end == null) return;
    setState(() => _saving = true);
    final saved = await widget.controller.trimSavedReference(
      widget.reference,
      name: _name.text,
      startSeconds: _startSeconds,
      endSeconds: end,
    );
    if (!mounted) return;
    if (saved != null) {
      Navigator.pop(context, true);
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final duration = _duration;
    final end = _endSeconds;
    final selectedDuration = end == null ? null : end - _startSeconds;
    final changed =
        duration != null &&
        end != null &&
        (_startSeconds >= .001 || (end - duration).abs() >= .001);
    return AlertDialog(
      key: ValueKey('trim-reference-dialog-${widget.reference.id}'),
      title: const Text('Trim as new reference'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      InkWell(
                        onTap: () => unawaited(
                          showSavedReferenceViewer(
                            context,
                            widget.controller,
                            widget.reference,
                          ),
                        ),
                        child: MediaThumbnail(
                          gateway: widget.controller.gateway,
                          kind: MediaReferenceKind.video,
                          reference: widget.reference.asset,
                          thumbnailReference: widget.reference.thumbnailAsset,
                          thumbnailBytes: widget.controller.cachedAssetBytes(
                            widget.reference.thumbnailAsset,
                          ),
                          fit: BoxFit.cover,
                          semanticsLabel:
                              '${widget.reference.name} trim preview',
                          onVideoMetadata: _rememberMetadata,
                        ),
                      ),
                      const Center(
                        child: IgnorePointer(
                          child: Icon(
                            Icons.play_circle_fill_rounded,
                            size: 52,
                            color: Colors.white,
                            shadows: <Shadow>[
                              Shadow(color: Colors.black54, blurRadius: 12),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('trim-reference-name'),
                controller: _name,
                enabled: !_saving,
                onChanged: (_) => setState(() {}),
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'New reference name',
                ),
              ),
              const SizedBox(height: 6),
              if (duration == null || end == null)
                _durationFailed
                    ? Row(
                        key: const ValueKey('trim-duration-failed'),
                        children: <Widget>[
                          Icon(
                            Icons.error_outline_rounded,
                            size: 17,
                            color: context.colors.error,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'The video duration could not be read.',
                            ),
                          ),
                          TextButton(
                            key: const ValueKey('trim-duration-retry'),
                            onPressed: () => unawaited(_loadDuration()),
                            child: const Text('Retry'),
                          ),
                        ],
                      )
                    : Row(
                        children: <Widget>[
                          const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ValueListenableBuilder<double?>(
                              valueListenable:
                                  _downloadProgress ??
                                  const AlwaysStoppedAnimation<double?>(null),
                              builder: (context, fraction, _) => Text(
                                fraction == null
                                    ? 'Reading video duration…'
                                    : 'Downloading video · '
                                          '${(fraction * 100).round()}%',
                              ),
                            ),
                          ),
                        ],
                      )
              else ...<Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Beginning · ${formatMediaDuration(_startSeconds)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      'Ending · ${formatMediaDuration(end)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                RangeSlider(
                  key: const ValueKey('trim-reference-range'),
                  min: 0,
                  max: duration,
                  values: RangeValues(_startSeconds, end),
                  labels: RangeLabels(
                    formatMediaDuration(_startSeconds),
                    formatMediaDuration(end),
                  ),
                  onChanged: _saving
                      ? null
                      : (range) {
                          if (range.end - range.start < .1) return;
                          setState(() {
                            _startSeconds = range.start;
                            _endSeconds = range.end;
                          });
                        },
                ),
                Text(
                  'New duration · ${formatMediaDuration(selectedDuration!)} '
                  'of ${formatMediaDuration(duration)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.colors.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'The original reference stays unchanged. The selected range is encoded as a separate MP4 in the same folder and storage.',
                style: TextStyle(
                  color: context.colors.onSurfaceVariant,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          key: const ValueKey('save-trimmed-reference'),
          onPressed: !_saving && changed && _name.text.trim().isNotEmpty
              ? _save
              : null,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.content_cut_rounded, size: 17),
          label: Text(_saving ? 'Trimming…' : 'Save new reference'),
        ),
      ],
    );
  }
}

Future<List<ReferenceCandidate>?> showReferencePicker(
  BuildContext context,
  AppController controller, {
  required MediaReferenceKind kind,
  required int maximum,
}) => showDialog<List<ReferenceCandidate>>(
  context: context,
  builder: (context) => _ReferencePickerDialog(
    controller: controller,
    kind: kind,
    maximum: maximum,
  ),
);

class _ReferencePickerDialog extends StatefulWidget {
  const _ReferencePickerDialog({
    required this.controller,
    required this.kind,
    required this.maximum,
  });

  final AppController controller;
  final MediaReferenceKind kind;
  final int maximum;

  @override
  State<_ReferencePickerDialog> createState() => _ReferencePickerDialogState();
}

class _ReferencePickerDialogState extends State<_ReferencePickerDialog> {
  bool generated = false;
  String query = '';
  String folderView = AppController.libraryFolderAll;
  final Map<String, ReferenceCandidate> selected =
      <String, ReferenceCandidate>{};

  List<LibraryFolder> get folders => widget.controller.foldersFor(
    generated ? LibraryCollection.generated : LibraryCollection.references,
  );

  List<ReferenceCandidate> get candidates {
    final collection = generated
        ? LibraryCollection.generated
        : LibraryCollection.references;
    final values = generated
        ? widget.controller.generatedReferenceCandidates(widget.kind)
        : widget.controller.savedReferences
              .where((item) => !item.hidden && item.kind == widget.kind)
              .map(
                (item) => ReferenceCandidate(
                  id: item.id,
                  name: item.name,
                  kind: item.kind,
                  asset: item.asset,
                  thumbnailAsset: item.thumbnailAsset,
                  createdAt: item.createdAt,
                  folderId: item.folderId,
                  tags: item.tags,
                  storage: item.storage,
                  durationSeconds: item.durationSeconds,
                ),
              )
              .toList();
    final normalized = query.trim().toLowerCase();
    final branch =
        folderView != AppController.libraryFolderAll &&
            folderView != AppController.libraryFolderUnfiled
        ? widget.controller.folderBranch(folderView, collection: collection)
        : const <String>{};
    final filtered = values.where((item) {
      final folderName = item.folderId == null
          ? ''
          : widget.controller
                .folderPath(item.folderId!, collection: collection)
                .toLowerCase();
      if (normalized.isNotEmpty &&
          !item.name.toLowerCase().contains(normalized) &&
          !folderName.contains(normalized) &&
          !item.tags.any((tag) => tag.toLowerCase().contains(normalized))) {
        return false;
      }
      if (folderView == AppController.libraryFolderUnfiled) {
        return widget.controller.folderById(
              item.folderId,
              collection: collection,
            ) ==
            null;
      }
      return folderView == AppController.libraryFolderAll ||
          branch.contains(item.folderId);
    }).toList();
    filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return filtered;
  }

  void _toggle(ReferenceCandidate item) {
    final active = selected.containsKey(item.id);
    if (!active && selected.length >= widget.maximum) return;
    setState(() {
      active ? selected.remove(item.id) : selected[item.id] = item;
    });
  }

  void _cacheThumbnail(ReferenceCandidate item, Uint8List bytes) {
    if (item.generated) {
      for (final generation in widget.controller.generations) {
        if (generation.localId != item.id) continue;
        unawaited(
          widget.controller.cacheGenerationPreviews(
            generation,
            thumbnailBytes: bytes,
          ),
        );
        return;
      }
      return;
    }
    for (final reference in widget.controller.savedReferences) {
      if (reference.id != item.id) continue;
      unawaited(widget.controller.cacheReferencePreview(reference, bytes));
      return;
    }
  }

  void _rememberDuration(ReferenceCandidate item, double seconds) {
    if (item.generated) return;
    final reference = widget.controller.savedReferences
        .where((reference) => reference.id == item.id)
        .firstOrNull;
    if (reference == null) return;
    unawaited(() async {
      await widget.controller.rememberSavedReferenceDuration(
        reference,
        seconds,
      );
      if (!mounted) return;
      setState(() {
        final refreshed = candidates
            .where((candidate) => candidate.id == item.id)
            .firstOrNull;
        if (refreshed != null && selected.containsKey(item.id)) {
          selected[item.id] = refreshed;
        }
      });
    }());
  }

  @override
  Widget build(BuildContext context) {
    final values = candidates;
    return AlertDialog(
      title: Text('Add saved ${widget.kind.pluralLabel}'),
      content: SizedBox(
        width: 820,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SegmentedButton<bool>(
              segments: const <ButtonSegment<bool>>[
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.collections_bookmark_outlined),
                  label: Text('References'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.video_library_outlined),
                  label: Text('Generated'),
                ),
              ],
              selected: <bool>{generated},
              onSelectionChanged: (value) => setState(() {
                generated = value.single;
                folderView = AppController.libraryFolderAll;
                selected.clear();
              }),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    autofocus: true,
                    onChanged: (value) => setState(() => query = value),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Search names, prompts, tags, folders',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<String>(
                    initialValue: folderView,
                    isExpanded: true,
                    decoration: const InputDecoration(isDense: true),
                    items: <DropdownMenuItem<String>>[
                      const DropdownMenuItem(
                        value: AppController.libraryFolderAll,
                        child: Text('All folders'),
                      ),
                      const DropdownMenuItem(
                        value: AppController.libraryFolderUnfiled,
                        child: Text('Unfiled'),
                      ),
                      ...folders.map(
                        (folder) => DropdownMenuItem(
                          value: folder.id,
                          child: Text(
                            '${widget.controller.folderPath(folder.id, collection: generated ? LibraryCollection.generated : LibraryCollection.references)} · ${folder.storage.shortLabel}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(() {
                      folderView = value ?? AppController.libraryFolderAll;
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: values.isEmpty
                  ? Center(
                      child: Text(
                        generated && widget.kind == MediaReferenceKind.audio
                            ? 'Generated audio outputs are not available.'
                            : 'No matching ${widget.kind.pluralLabel}.',
                        style: TextStyle(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, grid) {
                        final columns = grid.maxWidth >= 640
                            ? 3
                            : grid.maxWidth >= 420
                            ? 2
                            : 1;
                        const gap = 12.0;
                        final cardWidth =
                            (grid.maxWidth - gap * (columns - 1)) / columns;
                        return GridView.builder(
                          key: const ValueKey('reference-picker-card-grid'),
                          itemCount: values.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                crossAxisSpacing: gap,
                                mainAxisSpacing: gap,
                                mainAxisExtent: cardWidth * 9 / 16 + 86,
                              ),
                          itemBuilder: (context, index) {
                            final item = values[index];
                            final active = selected.containsKey(item.id);
                            final enabled =
                                active || selected.length < widget.maximum;
                            return _ReferenceCandidateCard(
                              controller: widget.controller,
                              item: item,
                              active: active,
                              enabled: enabled,
                              onTap: () => _toggle(item),
                              onThumbnail: item.kind == MediaReferenceKind.video
                                  ? (bytes) => _cacheThumbnail(item, bytes)
                                  : null,
                              onDuration: (seconds) =>
                                  _rememberDuration(item, seconds),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        Text(
          '${selected.length}/${widget.maximum} selected',
          style: TextStyle(color: context.colors.onSurfaceVariant),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: selected.isEmpty
              ? null
              : () => Navigator.pop(context, selected.values.toList()),
          child: Text('Add ${selected.length}'),
        ),
      ],
    );
  }
}

class _ReferenceCandidateCard extends StatelessWidget {
  const _ReferenceCandidateCard({
    required this.controller,
    required this.item,
    required this.active,
    required this.enabled,
    required this.onTap,
    this.onThumbnail,
    this.onDuration,
  });

  final AppController controller;
  final ReferenceCandidate item;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;
  final ValueChanged<Uint8List>? onThumbnail;
  final ValueChanged<double>? onDuration;

  String get details {
    final collection = item.generated
        ? LibraryCollection.generated
        : LibraryCollection.references;
    final values = <String>[
      if (item.durationSeconds != null)
        formatMediaDuration(item.durationSeconds!),
      if (item.folderId != null)
        controller.folderPath(item.folderId!, collection: collection),
      ...item.tags.map((tag) => '#$tag'),
    ];
    return values.isEmpty
        ? '${item.generated ? 'Generated' : 'Saved'} ${item.kind.label.toLowerCase()}'
        : values.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final outline = active
        ? scheme.primary
        : scheme.outlineVariant.withValues(alpha: .7);
    return Semantics(
      button: true,
      selected: active,
      enabled: enabled,
      label: '${active ? 'Deselect' : 'Select'} ${item.name}',
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: enabled ? 1 : .48,
        child: Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          color: active
              ? scheme.secondaryContainer.withValues(alpha: .42)
              : scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: BorderSide(color: outline, width: active ? 2 : 1),
          ),
          child: InkWell(
            key: ValueKey('reference-picker-card-${item.id}'),
            onTap: enabled ? onTap : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      MediaThumbnail(
                        gateway: controller.gateway,
                        kind: item.kind,
                        bytes: item.kind == MediaReferenceKind.image
                            ? controller.cachedAssetBytes(item.asset)
                            : null,
                        reference: item.asset,
                        thumbnailReference: item.thumbnailAsset,
                        thumbnailBytes: item.kind == MediaReferenceKind.video
                            ? controller.cachedAssetBytes(item.thumbnailAsset)
                            : null,
                        semanticsLabel: '${item.name} thumbnail',
                        onThumbnail: onThumbnail,
                        onVideoMetadata:
                            item.kind == MediaReferenceKind.video &&
                                !item.generated
                            ? (metadata) =>
                                  onDuration?.call(metadata.durationSeconds)
                            : null,
                        onMediaDuration:
                            item.kind == MediaReferenceKind.audio &&
                                !item.generated
                            ? onDuration
                            : null,
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: AnimatedContainer(
                          key: ValueKey(
                            'reference-picker-selection-${item.id}',
                          ),
                          duration: const Duration(milliseconds: 160),
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: active
                                ? scheme.primary
                                : scheme.surface.withValues(alpha: .9),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: active
                                  ? scheme.primary
                                  : scheme.outline.withValues(alpha: .8),
                            ),
                            boxShadow: const <BoxShadow>[
                              BoxShadow(
                                color: Color(0x42000000),
                                blurRadius: 5,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            active ? Icons.check_rounded : Icons.add_rounded,
                            size: 19,
                            color: active ? scheme.onPrimary : scheme.onSurface,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: StorageBadge(
                          storage: item.storage,
                          compact: true,
                        ),
                      ),
                      if (item.kind != MediaReferenceKind.audio)
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: Material(
                            color: scheme.surface.withValues(alpha: .9),
                            shape: const CircleBorder(),
                            child: IconButton(
                              key: ValueKey('view-reference-picker-${item.id}'),
                              tooltip: 'View ${item.name} full screen',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => unawaited(
                                showVisualReferenceViewer(
                                  context,
                                  controller: controller,
                                  kind: item.kind,
                                  label: item.name,
                                  reference: item.asset,
                                  thumbnailReference: item.thumbnailAsset,
                                ),
                              ),
                              icon: const Icon(
                                Icons.fullscreen_rounded,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            height: 1.18,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          details,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _confirmReferenceDelete(
  BuildContext context,
  AppController controller,
  SavedReference reference,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete “${reference.name}”?'),
      content: const Text(
        'This removes it from saved references. Existing generation history is unchanged.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await controller.deleteSavedReference(reference.id);
  }
}

Future<void> showCharacterAssignmentDialog(
  BuildContext context,
  AppController controller,
  MediaReferenceDraft reference,
) async {
  final name = TextEditingController(
    text: controller.characterNameForDraft(reference),
  );
  String? error;
  bool saving = false;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Cast a character'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('@${controller.referencePromptName(reference)}'),
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('character-name-field'),
                  controller: name,
                  autofocus: true,
                  maxLength: 60,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'Character name',
                    hintText: 'ALEXANDRIA',
                    errorText: error,
                    helperText:
                        'Use this name in your screenplay to link this reference. Clear it to remove the assignment.',
                    helperMaxLines: 3,
                  ),
                ),
                if (controller.screenplayCharacterNames.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    children: controller.screenplayCharacterNames
                        .map(
                          (character) => ActionChip(
                            label: Text(character),
                            onPressed: () => name.text = character,
                          ),
                        )
                        .toList(),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('save-character-name'),
            onPressed: saving
                ? null
                : () async {
                    final problem = controller.characterNameProblem(
                      name.text,
                      excludeDraftId: reference.id,
                      excludeSavedReferenceId: reference.savedReferenceId,
                    );
                    if (problem != null) {
                      setState(() => error = problem);
                      return;
                    }
                    setState(() => saving = true);
                    final saved = await controller.setDraftCharacterName(
                      reference.id,
                      name.text,
                    );
                    if (!context.mounted) return;
                    if (saved) {
                      Navigator.pop(context);
                    } else {
                      setState(() => saving = false);
                    }
                  },
            child: Text(saving ? 'Saving…' : 'Save'),
          ),
        ],
      ),
    ),
  );
  // Dialog exit animations retain the field for one more frame.
  await Future<void>.delayed(const Duration(milliseconds: 250));
  name.dispose();
}
