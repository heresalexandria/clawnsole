/// The aesthetic half of the References desk: one console-key toolbar over a
/// single card of aesthetic rows.
///
/// Aesthetics are text-only, so they get their own tab rather than sharing
/// the media folder rail. The toolbar follows the library pattern exactly —
/// facet-count segments, one search field, an anchored Tags popover, and the
/// primary action key — so the two tabs read as one desk.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import '../core/aesthetic_reference.dart';
import 'aesthetic_references.dart';
import 'common_widgets.dart';
import 'filter_menu.dart';
import 'hardware.dart';

/// The toolbar and the list of aesthetics, ready to drop into a scroll view.
class AestheticLibraryView extends StatelessWidget {
  const AestheticLibraryView({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _AestheticToolbar(controller: controller),
        const SizedBox(height: 12),
        if (controller.aestheticReferences.isEmpty)
          _AestheticEmpty(controller: controller)
        else
          _AestheticList(controller: controller),
      ],
    ),
  );
}

class _AestheticToolbar extends StatelessWidget {
  const _AestheticToolbar({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.all(10),
    child: LayoutBuilder(
      builder: (context, constraints) {
        // Same breakpoint as the media toolbar, so both tabs fold at once.
        final wide = constraints.maxWidth >= 860;
        // Starred is the always-visible facet; its counts honour the search
        // and tag filters so the two keys describe the same view.
        final keys = <Widget>[
          ConsoleFilterSegment(
            key: const ValueKey('aesthetic-filter-all'),
            label: 'All',
            semanticLabel: 'All aesthetics',
            icon: Icons.grid_view_rounded,
            count: controller.aestheticCount(),
            selected: !controller.aestheticFavoritesOnly,
            onTap: () => controller.setAestheticFavoritesOnly(false),
          ),
          ConsoleFilterSegment(
            key: const ValueKey('aesthetic-filter-starred'),
            label: 'Starred',
            semanticLabel: 'Starred aesthetics',
            icon: Icons.star_rounded,
            count: controller.aestheticCount(favoritesOnly: true),
            selected: controller.aestheticFavoritesOnly,
            onTap: () => controller.setAestheticFavoritesOnly(true),
          ),
        ];
        final segments = wide
            ? Wrap(spacing: 5, runSpacing: 5, children: keys)
            : ConsoleSegmentStrip(children: keys);
        final search = TextField(
          key: const ValueKey('aesthetic-library-search'),
          onChanged: controller.setAestheticSearch,
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded, size: 18),
            hintText: 'Search titles, text, tags',
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        );
        final tagButton = AestheticTagButton(
          controller: controller,
          compact: !wide,
        );
        final add = wide
            ? FilledButton.icon(
                key: const ValueKey('add-aesthetic-reference'),
                onPressed: () =>
                    unawaited(showAestheticEditor(context, controller)),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add aesthetic'),
              )
            : Tooltip(
                message: 'Add aesthetic',
                child: FilledButton(
                  key: const ValueKey('add-aesthetic-reference'),
                  onPressed: () =>
                      unawaited(showAestheticEditor(context, controller)),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Icon(Icons.add_rounded, size: 18),
                ),
              );
        if (wide) {
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
              tagButton,
              const SizedBox(width: 8),
              add,
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
                tagButton,
                const SizedBox(width: 8),
                add,
              ],
            ),
          ],
        );
      },
    ),
  );
}

/// One "Tags" console key that gathers the aesthetic tag filter into an
/// anchored panel, matching `LibraryFilterButton` on the media tab.
class AestheticTagButton extends StatefulWidget {
  const AestheticTagButton({
    required this.controller,
    super.key,
    this.compact = false,
  });

  final AppController controller;

  /// Hides the text label so the key fits narrow toolbars.
  final bool compact;

  @override
  State<AestheticTagButton> createState() => _AestheticTagButtonState();
}

class _AestheticTagButtonState extends State<AestheticTagButton> {
  final MenuController _menu = MenuController();

  AppController get controller => widget.controller;

  Widget _panel(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final tags = controller.aestheticTags;
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 316, maxHeight: 420),
        child: SingleChildScrollView(
          primary: false,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (controller.hasAestheticFilters) ...<Widget>[
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: const ValueKey('aesthetic-filter-reset'),
                    onPressed: controller.resetAestheticFilters,
                    icon: const Icon(Icons.restart_alt_rounded, size: 16),
                    label: const Text('Reset filters'),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              const AestheticEyebrow('Tags'),
              const SizedBox(height: 8),
              if (tags.isEmpty)
                Text(
                  'No tags yet. Add comma-separated tags while editing an '
                  'aesthetic.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: context.colors.onSurfaceVariant,
                  ),
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    FilterChip(
                      key: const ValueKey('aesthetic-tag-all'),
                      label: const Text('All tags'),
                      selected: controller.aestheticTag == null,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => controller.setAestheticTag(null),
                    ),
                    for (final tag in tags)
                      FilterChip(
                        key: ValueKey('aesthetic-tag-$tag'),
                        label: Text(
                          '#$tag · ${controller.aestheticTagCount(tag)}',
                        ),
                        selected: controller.aestheticTag == tag,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => controller.setAestheticTag(
                          controller.aestheticTag == tag ? null : tag,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final active = controller.aestheticTag != null;
    final foreground = active
        ? context.colors.onPrimary
        : context.colors.onSurface;
    return MenuAnchor(
      controller: _menu,
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll<Color>(context.colors.surface),
        elevation: const WidgetStatePropertyAll<double>(10),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: context.colors.outlineVariant),
          ),
        ),
      ),
      menuChildren: <Widget>[_panel(context)],
      builder: (context, menu, _) => Tooltip(
        message: 'Filter aesthetics by tag',
        child: Semantics(
          container: true,
          button: true,
          label: 'Tags',
          value: active ? '1 active' : null,
          child: HardwareTouchTarget(
            onTap: () => menu.isOpen ? menu.close() : menu.open(),
            child: InkWell(
              key: const ValueKey('aesthetic-tag-button'),
              borderRadius: BorderRadius.circular(10),
              onTap: () => menu.isOpen ? menu.close() : menu.open(),
              child: ExcludeSemantics(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 8,
                  ),
                  decoration: consoleKeyDecoration(
                    context,
                    selected: active,
                    radius: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.sell_outlined, size: 15, color: foreground),
                      if (!widget.compact) ...<Widget>[
                        const SizedBox(width: 6),
                        Text(
                          'Tags',
                          style: TextStyle(
                            color: foreground,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      if (active) ...<Widget>[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5.5,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: context.colors.onPrimary.withValues(
                              alpha: .2,
                            ),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '1',
                            style: TextStyle(
                              color: context.colors.onPrimary,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AestheticList extends StatelessWidget {
  const _AestheticList({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final items = controller.filteredAestheticReferences;
    if (items.isEmpty) {
      return SurfaceCard(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'No aesthetics match.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Try a different search, or clear the tag and starred filters.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: context.colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('aesthetic-empty-reset'),
                onPressed: controller.resetAestheticFilters,
                icon: const Icon(Icons.restart_alt_rounded, size: 16),
                label: const Text('Reset filters'),
              ),
            ),
          ],
        ),
      );
    }
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (var index = 0; index < items.length; index += 1) ...<Widget>[
            if (index > 0)
              Divider(height: 1, color: context.colors.outlineVariant),
            _AestheticRow(controller: controller, item: items[index]),
          ],
        ],
      ),
    );
  }
}

class _AestheticRow extends StatelessWidget {
  const _AestheticRow({required this.controller, required this.item});

  final AppController controller;
  final AestheticReference item;

  @override
  Widget build(BuildContext context) {
    // Four pills read at a glance; the rest collapse into a +n counter so a
    // heavily tagged aesthetic never pushes its title off the row.
    const shown = 4;
    final extra = item.tags.length - shown;
    return InkWell(
      key: ValueKey('aesthetic-row-${item.id}'),
      onTap: () =>
          unawaited(showAestheticEditor(context, controller, reference: item)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: isHardwareTouchPlatform ? kHardwareTouchTarget : 0,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: AestheticIcon(
                  name: item.icon,
                  color: item.color,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          key: ValueKey('aesthetic-favorite-${item.id}'),
                          tooltip: item.favorite ? 'Unstar' : 'Star',
                          visualDensity: VisualDensity.compact,
                          iconSize: 18,
                          onPressed: () =>
                              controller.toggleAestheticFavorite(item.id),
                          icon: Icon(
                            item.favorite
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            color: item.favorite
                                ? context.tokens.brass
                                : context.colors.onSurfaceVariant,
                          ),
                        ),
                        if (item.tags.isNotEmpty)
                          Flexible(
                            child: Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: <Widget>[
                                for (final tag in item.tags.take(shown))
                                  _TagPill(label: '#$tag'),
                                if (extra > 0) _TagPill(label: '+$extra'),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                key: ValueKey('edit-aesthetic-${item.id}'),
                tooltip: 'Edit ${item.title}',
                iconSize: 18,
                onPressed: () => unawaited(
                  showAestheticEditor(context, controller, reference: item),
                ),
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TagPill extends StatelessWidget {
  const _TagPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: context.colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        color: context.colors.onSurfaceVariant,
      ),
    ),
  );
}

class _AestheticEmpty extends StatelessWidget {
  const _AestheticEmpty({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Eyebrow('Aesthetics', icon: Icons.palette_outlined),
        const SizedBox(height: 10),
        Text(
          'No aesthetics yet.',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          'Add reusable style direction, then choose it from the Aesthetic key '
          'beside Characters in Create.',
          style: TextStyle(
            fontSize: 12.5,
            height: 1.4,
            color: context.colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const ValueKey('add-first-aesthetic-reference'),
            onPressed: () =>
                unawaited(showAestheticEditor(context, controller)),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add aesthetic'),
          ),
        ),
      ],
    ),
  );
}
