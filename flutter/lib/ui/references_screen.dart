import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import '../core/models.dart';
import 'common_widgets.dart';

class ReferencesScreen extends StatelessWidget {
  const ReferencesScreen({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 960;
      final padding = constraints.maxWidth < 620 ? 16.0 : 28.0;
      return SingleChildScrollView(
        padding: EdgeInsets.all(padding),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _ReferencesHeading(controller: controller),
                const SizedBox(height: 22),
                if (desktop)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SizedBox(
                        width: 228,
                        child: _ReferenceFolderSidebar(controller: controller),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: _ReferenceResults(controller: controller),
                      ),
                    ],
                  )
                else ...<Widget>[
                  _ReferenceFolderPicker(controller: controller),
                  const SizedBox(height: 12),
                  _ReferenceResults(controller: controller),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _ReferencesHeading extends StatelessWidget {
  const _ReferencesHeading({required this.controller});

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
              'Keep reusable images, videos, and audio organized locally, then attach them from Create in a few clicks.',
              style: TextStyle(color: context.colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
      PopupMenuButton<MediaReferenceKind>(
        onSelected: (kind) => unawaited(
          controller.importSavedReferences(
            kind,
            folderId:
                controller.referenceFolderView ==
                        AppController.libraryFolderAll ||
                    controller.referenceFolderView ==
                        AppController.libraryFolderUnfiled
                ? null
                : controller.referenceFolderView,
          ),
        ),
        itemBuilder: (context) => MediaReferenceKind.values
            .map(
              (kind) => PopupMenuItem<MediaReferenceKind>(
                value: kind,
                child: Row(
                  children: <Widget>[
                    Icon(_kindIcon(kind), size: 18),
                    const SizedBox(width: 10),
                    Text('Add ${kind.pluralLabel}'),
                  ],
                ),
              ),
            )
            .toList(),
        child: const FilledButtonIconVisual(
          icon: Icons.add_rounded,
          label: 'Add references',
        ),
      ),
    ],
  );
}

class FilledButtonIconVisual extends StatelessWidget {
  const FilledButtonIconVisual({
    required this.icon,
    required this.label,
    super.key,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: FilledButton.icon(
      onPressed: () {},
      icon: Icon(icon),
      label: Text(label),
    ),
  );
}

class _ReferenceResults extends StatelessWidget {
  const _ReferenceResults({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      _ReferenceToolbar(controller: controller),
      if (controller.referenceTags.isNotEmpty) ...<Widget>[
        const SizedBox(height: 12),
        SizedBox(
          height: 35,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: controller.referenceTags.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 7),
            itemBuilder: (context, index) {
              final tag = index == 0
                  ? null
                  : controller.referenceTags[index - 1];
              return FilterChip(
                label: Text(
                  tag == null
                      ? 'All tags'
                      : '#$tag · ${controller.referenceTagCount(tag)}',
                ),
                selected: controller.referenceTag == tag,
                onSelected: (_) => controller.setReferenceTag(tag),
                visualDensity: VisualDensity.compact,
              );
            },
          ),
        ),
      ],
      const SizedBox(height: 18),
      if (controller.filteredSavedReferences.isEmpty)
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
              children: controller.filteredSavedReferences
                  .map(
                    (item) => SizedBox(
                      width: width,
                      child: _ReferenceCard(
                        controller: controller,
                        reference: item,
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
    ],
  );
}

class _ReferenceToolbar extends StatelessWidget {
  const _ReferenceToolbar({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.all(10),
    child: Wrap(
      spacing: 9,
      runSpacing: 9,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: <Widget>[
            _KindChip(
              label: 'All',
              icon: Icons.grid_view_rounded,
              selected: controller.referenceKind == null,
              onTap: () => controller.setReferenceKind(null),
            ),
            ...MediaReferenceKind.values.map(
              (kind) => _KindChip(
                label: kind.label,
                icon: _kindIcon(kind),
                selected: controller.referenceKind == kind,
                onTap: () => controller.setReferenceKind(kind),
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            SizedBox(
              width: 245,
              child: TextField(
                key: const ValueKey('reference-library-search'),
                onChanged: controller.setReferenceSearch,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded, size: 18),
                  hintText: 'Search names, tags, folders',
                  isDense: true,
                ),
              ),
            ),
            DropdownButton<ReferenceSort>(
              value: controller.referenceSort,
              onChanged: (value) {
                if (value != null) controller.setReferenceSort(value);
              },
              items: ReferenceSort.values
                  .map(
                    (sort) => DropdownMenuItem(
                      value: sort,
                      child: Text(_sortLabel(sort)),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ],
    ),
  );
}

class _KindChip extends StatelessWidget {
  const _KindChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    avatar: Icon(icon, size: 15),
    label: Text(label),
    selected: selected,
    onSelected: (_) => onTap(),
    showCheckmark: false,
  );
}

class _ReferenceCard extends StatelessWidget {
  const _ReferenceCard({required this.controller, required this.reference});

  final AppController controller;
  final SavedReference reference;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: reference.kind == MediaReferenceKind.image
                ? FutureBuilder(
                    future: controller.gateway.readAsset(reference.asset),
                    builder: (context, snapshot) => snapshot.hasData
                        ? Image.memory(snapshot.data!, fit: BoxFit.cover)
                        : _MediaPlaceholder(kind: reference.kind),
                  )
                : _MediaPlaceholder(kind: reference.kind),
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
                    Text(
                      reference.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${reference.kind.label}${reference.folderId == null ? '' : ' · ${controller.folderPath(reference.folderId!, collection: LibraryCollection.references)}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                    if (reference.tags.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 7),
                      Text(
                        reference.tags.map((tag) => '#$tag').join('  '),
                        maxLines: 2,
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
                  } else {
                    unawaited(
                      _confirmReferenceDelete(context, controller, reference),
                    );
                  }
                },
                itemBuilder: (context) => const <PopupMenuEntry<String>>[
                  PopupMenuItem(value: 'edit', child: Text('Rename and file')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _MediaPlaceholder extends StatelessWidget {
  const _MediaPlaceholder({required this.kind});

  final MediaReferenceKind kind;

  @override
  Widget build(BuildContext context) => Container(
    color: ClawnsoleColors.plumInk,
    child: Center(
      child: Icon(_kindIcon(kind), size: 42, color: ClawnsoleColors.creamMuted),
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

class _ReferenceFolderSidebar extends StatelessWidget {
  const _ReferenceFolderSidebar({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.all(10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Folders',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'New reference folder',
                onPressed: () =>
                    unawaited(_showReferenceFolderEditor(context, controller)),
                icon: const Icon(Icons.create_new_folder_outlined, size: 19),
              ),
            ],
          ),
        ),
        _ReferenceFolderRow(
          controller: controller,
          label: 'All references',
          id: AppController.libraryFolderAll,
          icon: Icons.collections_bookmark_outlined,
        ),
        _ReferenceFolderRow(
          controller: controller,
          label: 'Unfiled',
          id: AppController.libraryFolderUnfiled,
          icon: Icons.inbox_outlined,
        ),
        if (controller.referenceFolders.isNotEmpty) const Divider(height: 11),
        ...controller.referenceFolderTree.map(
          (folder) => _ReferenceFolderRow(
            controller: controller,
            label: folder.name,
            id: folder.id,
            icon: Icons.folder_outlined,
            folder: folder,
            depth: controller.folderDepth(
              folder.id,
              collection: LibraryCollection.references,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ReferenceFolderRow extends StatelessWidget {
  const _ReferenceFolderRow({
    required this.controller,
    required this.label,
    required this.id,
    required this.icon,
    this.folder,
    this.depth = 0,
  });

  final AppController controller;
  final String label;
  final String id;
  final IconData icon;
  final LibraryFolder? folder;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final selected = controller.referenceFolderView == id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: selected ? context.colors.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => controller.setReferenceFolderView(id),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: EdgeInsets.fromLTRB(9 + depth * 14, 8, 6, 8),
            child: Row(
              children: <Widget>[
                Icon(icon, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  '${controller.referenceFolderCount(id)}',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
                if (folder != null)
                  SizedBox.square(
                    dimension: 26,
                    child: PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      onSelected: (value) {
                        if (value == 'subfolder') {
                          unawaited(
                            _showReferenceFolderEditor(
                              context,
                              controller,
                              parentId: folder!.id,
                            ),
                          );
                        } else if (value == 'rename') {
                          unawaited(
                            _showReferenceFolderEditor(
                              context,
                              controller,
                              folder: folder,
                            ),
                          );
                        } else {
                          unawaited(
                            _confirmFolderDelete(context, controller, folder!),
                          );
                        }
                      },
                      itemBuilder: (context) => const <PopupMenuEntry<String>>[
                        PopupMenuItem(
                          value: 'subfolder',
                          child: Text('New subfolder'),
                        ),
                        PopupMenuItem(value: 'rename', child: Text('Rename')),
                        PopupMenuItem(value: 'delete', child: Text('Remove')),
                      ],
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

class _ReferenceFolderPicker extends StatelessWidget {
  const _ReferenceFolderPicker({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    child: Row(
      children: <Widget>[
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: controller.referenceFolderView,
              isExpanded: true,
              onChanged: (value) {
                if (value != null) controller.setReferenceFolderView(value);
              },
              items: <DropdownMenuItem<String>>[
                const DropdownMenuItem(
                  value: AppController.libraryFolderAll,
                  child: Text('All references'),
                ),
                const DropdownMenuItem(
                  value: AppController.libraryFolderUnfiled,
                  child: Text('Unfiled'),
                ),
                ...controller.referenceFolderTree.map(
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
            ),
          ),
        ),
        IconButton(
          tooltip: 'New reference folder',
          onPressed: () =>
              unawaited(_showReferenceFolderEditor(context, controller)),
          icon: const Icon(Icons.create_new_folder_outlined),
        ),
      ],
    ),
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
  var folderId = reference?.folderId;
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(reference == null ? 'Save reference' : 'Edit reference'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextField(
                controller: name,
                autofocus: true,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String?>(
                initialValue: folderId,
                decoration: const InputDecoration(labelText: 'Folder'),
                items: <DropdownMenuItem<String?>>[
                  const DropdownMenuItem(value: null, child: Text('Unfiled')),
                  ...controller.referenceFolderTree.map(
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
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final values = tags.text.split(',');
              final success = reference == null
                  ? await controller.saveDraftReference(
                          draft!,
                          name: name.text,
                          folderId: folderId,
                          tags: values,
                        ) !=
                        null
                  : await controller.updateSavedReference(
                      reference,
                      name: name.text,
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
  return saved == true;
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
              .where((item) => item.kind == widget.kind)
              .map(
                (item) => ReferenceCandidate(
                  id: item.id,
                  name: item.name,
                  kind: item.kind,
                  asset: item.asset,
                  createdAt: item.createdAt,
                  folderId: item.folderId,
                  tags: item.tags,
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

  @override
  Widget build(BuildContext context) {
    final values = candidates;
    return AlertDialog(
      title: Text('Add saved ${widget.kind.pluralLabel}'),
      content: SizedBox(
        width: 660,
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
                            widget.controller.folderPath(
                              folder.id,
                              collection: generated
                                  ? LibraryCollection.generated
                                  : LibraryCollection.references,
                            ),
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
                  : ListView.separated(
                      itemCount: values.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = values[index];
                        final active = selected.containsKey(item.id);
                        final full = selected.length >= widget.maximum;
                        return CheckboxListTile(
                          value: active,
                          onChanged: !active && full
                              ? null
                              : (_) => setState(() {
                                  active
                                      ? selected.remove(item.id)
                                      : selected[item.id] = item;
                                }),
                          secondary: Icon(_kindIcon(item.kind)),
                          title: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            <String>[
                              if (item.folderId != null)
                                widget.controller.folderPath(
                                  item.folderId!,
                                  collection: generated
                                      ? LibraryCollection.generated
                                      : LibraryCollection.references,
                                ),
                              ...item.tags.map((tag) => '#$tag'),
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
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

Future<void> _showReferenceFolderEditor(
  BuildContext context,
  AppController controller, {
  LibraryFolder? folder,
  String? parentId,
}) async {
  final name = TextEditingController(text: folder?.name ?? '');
  var selectedParent = folder?.parentId ?? parentId;
  final excluded = folder == null
      ? const <String>{}
      : controller.folderBranch(
          folder.id,
          collection: LibraryCollection.references,
        );
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(folder == null ? 'New reference folder' : 'Rename folder'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: name,
                autofocus: true,
                maxLength: 48,
                decoration: const InputDecoration(labelText: 'Folder name'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                initialValue: selectedParent,
                decoration: const InputDecoration(labelText: 'Inside'),
                items: <DropdownMenuItem<String?>>[
                  const DropdownMenuItem(value: null, child: Text('Top level')),
                  ...controller.referenceFolderTree
                      .where((item) => !excluded.contains(item.id))
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(
                            controller.folderPath(
                              item.id,
                              collection: LibraryCollection.references,
                            ),
                          ),
                        ),
                      ),
                ],
                onChanged: (value) => setState(() => selectedParent = value),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final saved = await controller.saveLibraryFolder(
                name.text,
                existing: folder,
                parentId: selectedParent,
                collection: LibraryCollection.references,
              );
              if (saved && context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  name.dispose();
}

Future<void> _confirmFolderDelete(
  BuildContext context,
  AppController controller,
  LibraryFolder folder,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Remove “${folder.name}”?'),
      content: const Text(
        'Saved references become unfiled. Direct subfolders move up one level.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Remove folder'),
        ),
      ],
    ),
  );
  if (confirmed == true) await controller.deleteLibraryFolder(folder.id);
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

IconData _kindIcon(MediaReferenceKind kind) => switch (kind) {
  MediaReferenceKind.image => Icons.image_rounded,
  MediaReferenceKind.video => Icons.video_library_rounded,
  MediaReferenceKind.audio => Icons.graphic_eq_rounded,
};

String _sortLabel(ReferenceSort sort) => switch (sort) {
  ReferenceSort.newest => 'Newest',
  ReferenceSort.oldest => 'Oldest',
  ReferenceSort.name => 'Name',
  ReferenceSort.kind => 'Media type',
};
