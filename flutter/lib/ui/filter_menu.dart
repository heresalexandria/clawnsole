import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import '../core/models.dart';
import 'common_widgets.dart';
import 'hardware.dart';

/// A console-key segment used for the always-visible primary filter rows
/// (generation status, reference media kind).
class ConsoleFilterSegment extends StatelessWidget {
  const ConsoleFilterSegment({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
    this.icon,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? context.colors.onPrimary
        : context.colors.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: consoleKeyDecoration(
          context,
          selected: selected,
          radius: 10,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 14, color: foreground),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? context.colors.onPrimary
                    : context.colors.onSurface,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (count != null && count! > 0) ...<Widget>[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5.5,
                  vertical: 1.5,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? context.colors.onPrimary.withValues(alpha: .18)
                      : context.colors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: selected
                        ? context.colors.onPrimary
                        : context.colors.onSurfaceVariant,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A single scrolling line of console keys for narrow toolbars, where a
/// wrapped stack of segments would grow too tall.
class ConsoleSegmentStrip extends StatelessWidget {
  const ConsoleSegmentStrip({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: <Widget>[
        for (var index = 0; index < children.length; index += 1) ...<Widget>[
          if (index > 0) const SizedBox(width: 5),
          children[index],
        ],
      ],
    ),
  );
}

/// One "Filters" console key that gathers the secondary library filters —
/// storage, favorites, and tags — into an anchored panel so the toolbar
/// stays a single quiet row. Lights up with a count while filters narrow
/// the view.
class LibraryFilterButton extends StatefulWidget {
  const LibraryFilterButton({
    required this.controller,
    required this.collection,
    super.key,
    this.compact = false,
  });

  final AppController controller;
  final LibraryCollection collection;

  /// Hides the text label so the key fits narrow toolbars.
  final bool compact;

  @override
  State<LibraryFilterButton> createState() => _LibraryFilterButtonState();
}

class _LibraryFilterButtonState extends State<LibraryFilterButton> {
  final MenuController _menu = MenuController();

  bool get _references => widget.collection == LibraryCollection.references;

  FavoriteFilter get _favorite => _references
      ? widget.controller.referenceFavoriteFilter
      : widget.controller.libraryFavoriteFilter;

  String? get _tag => _references
      ? widget.controller.referenceTag
      : widget.controller.libraryTag;

  List<String> get _tags => _references
      ? widget.controller.referenceTags
      : widget.controller.libraryTags;

  int get _activeCount =>
      (_favorite != FavoriteFilter.all ? 1 : 0) + (_tag != null ? 1 : 0);

  void _reset() {
    if (_references) {
      widget.controller
        ..setReferenceFavoriteFilter(FavoriteFilter.all)
        ..setReferenceTag(null);
    } else {
      widget.controller
        ..setLibraryFavoriteFilter(FavoriteFilter.all)
        ..setLibraryTag(null);
    }
  }

  Widget _section(BuildContext context, String label, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(
        label.toUpperCase(),
        style: TextStyle(
          color: context.tokens.brass,
          fontSize: 10,
          letterSpacing: 1.6,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 8),
      child,
    ],
  );

  Widget _panel(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final tags = _tags;
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 316, maxHeight: 420),
        child: SingleChildScrollView(
          primary: false,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _section(
                context,
                'Favorites',
                FavoriteFilterChips(
                  value: _favorite,
                  onChanged: (value) => _references
                      ? widget.controller.setReferenceFavoriteFilter(value)
                      : widget.controller.setLibraryFavoriteFilter(value),
                ),
              ),
              if (tags.isNotEmpty) ...<Widget>[
                const SizedBox(height: 14),
                _section(
                  context,
                  'Tags',
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      FilterChip(
                        label: const Text('All tags'),
                        selected: _tag == null,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => _references
                            ? widget.controller.setReferenceTag(null)
                            : widget.controller.setLibraryTag(null),
                      ),
                      ...tags.map(
                        (tag) => FilterChip(
                          label: Text(
                            '#$tag · ${_references ? widget.controller.referenceTagCount(tag) : widget.controller.tagCount(tag)}',
                          ),
                          selected: _tag == tag,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) => _references
                              ? widget.controller.setReferenceTag(tag)
                              : widget.controller.setLibraryTag(tag),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_activeCount > 0) ...<Widget>[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: ValueKey('${_keyPrefix()}-filter-reset'),
                    onPressed: _reset,
                    icon: const Icon(Icons.restart_alt_rounded, size: 16),
                    label: const Text('Reset filters'),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );

  String _keyPrefix() => _references ? 'reference' : 'library';

  @override
  Widget build(BuildContext context) {
    final active = _activeCount;
    final foreground = active > 0
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
        message: 'Storage, favorites, and tags',
        child: InkWell(
          key: ValueKey('${_keyPrefix()}-filter-button'),
          borderRadius: BorderRadius.circular(10),
          onTap: () => menu.isOpen ? menu.close() : menu.open(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: consoleKeyDecoration(
              context,
              selected: active > 0,
              radius: 10,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.tune_rounded, size: 15, color: foreground),
                if (!widget.compact) ...<Widget>[
                  const SizedBox(width: 6),
                  Text(
                    'Filters',
                    style: TextStyle(
                      color: foreground,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (active > 0) ...<Widget>[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5.5,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: context.colors.onPrimary.withValues(alpha: .2),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$active',
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
    );
  }
}

/// The storage filter as sidebar rows, living beside the folder tree so
/// Local and Google Drive stay one glance away. The Drive row also carries
/// the connection state and a reconnect action, so a signed-out session can
/// never silently look like missing work.
class StorageSidebarSection extends StatelessWidget {
  const StorageSidebarSection({
    required this.controller,
    required this.value,
    required this.onChanged,
    required this.counts,
    super.key,
    this.trailingDivider = true,
  });

  final AppController controller;
  final LibraryStorageFilter value;
  final ValueChanged<LibraryStorageFilter> onChanged;
  final Map<LibraryStorageFilter, int> counts;
  final bool trailingDivider;

  bool get _driveSignedOut =>
      controller.supportsGoogleDrive &&
      controller.googleDriveConnection.isConfigured &&
      !controller.googleDriveConnected;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
        child: Text('Storage', style: Theme.of(context).textTheme.titleMedium),
      ),
      _StorageRow(
        icon: Icons.layers_outlined,
        label: 'All storage',
        count: counts[LibraryStorageFilter.all] ?? 0,
        selected: value == LibraryStorageFilter.all,
        onTap: () => onChanged(LibraryStorageFilter.all),
      ),
      if (controller.supportsLocalLibrary)
        _StorageRow(
          icon: Icons.devices_outlined,
          label: 'On this device',
          count: counts[LibraryStorageFilter.local] ?? 0,
          selected: value == LibraryStorageFilter.local,
          onTap: () => onChanged(LibraryStorageFilter.local),
        ),
      _StorageRow(
        icon: _driveSignedOut ? Icons.cloud_off_rounded : Icons.cloud_outlined,
        label: 'Google Drive',
        count: counts[LibraryStorageFilter.drive] ?? 0,
        selected: value == LibraryStorageFilter.drive,
        onTap: () => onChanged(LibraryStorageFilter.drive),
        trailing: controller.googleDriveBusy
            ? const SizedBox.square(
                dimension: 13,
                child: CircularProgressIndicator(strokeWidth: 1.6),
              )
            : _driveSignedOut
            ? InkWell(
                key: const ValueKey('storage-drive-reconnect'),
                borderRadius: BorderRadius.circular(999),
                onTap: () => unawaited(controller.refreshGoogleDrive()),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: Text(
                    'Reconnect',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: context.tokens.brass,
                    ),
                  ),
                ),
              )
            : null,
      ),
      if (trailingDivider)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Divider(height: 1),
        ),
    ],
  );
}

class _StorageRow extends StatelessWidget {
  const _StorageRow({
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Material(
      color: selected ? context.colors.primaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(9, 9, 9, 9),
          child: Row(
            children: <Widget>[
              Icon(
                icon,
                size: 18,
                color: selected
                    ? context.colors.primary
                    : context.colors.onSurfaceVariant,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? context.colors.onPrimaryContainer
                        : context.colors.onSurface,
                  ),
                ),
              ),
              if (trailing != null) ...<Widget>[
                trailing!,
                const SizedBox(width: 5),
              ],
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 10.5,
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// A quiet inline card shown when Drive was connected before but the current
/// session is signed out, so hidden Drive work is explained instead of
/// looking lost.
class DriveReconnectNotice extends StatelessWidget {
  const DriveReconnectNotice({
    required this.controller,
    required this.subject,
    super.key,
  });

  final AppController controller;

  /// What this screen hides while signed out, e.g. 'films' or 'references'.
  final String subject;

  /// Whether the notice applies right now.
  static bool needed(AppController controller) =>
      controller.supportsGoogleDrive &&
      controller.googleDriveConnection.isConfigured &&
      !controller.googleDriveConnected;

  @override
  Widget build(BuildContext context) {
    final busy = controller.googleDriveBusy;
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: <Widget>[
          Icon(
            busy ? Icons.cloud_sync_outlined : Icons.cloud_off_rounded,
            size: 18,
            color: context.tokens.brass,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              busy
                  ? 'Reconnecting to Google Drive…'
                  : 'Google Drive is signed out, so Drive $subject are hidden. They are safe in your Drive folder.',
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (busy)
            const SizedBox.square(
              dimension: 15,
              child: CircularProgressIndicator(strokeWidth: 1.8),
            )
          else
            FilledButton.tonal(
              key: ValueKey('drive-reconnect-$subject'),
              onPressed: () => unawaited(controller.refreshGoogleDrive()),
              child: const Text('Reconnect'),
            ),
        ],
      ),
    );
  }
}

/// The reference sort order as a compact menu key instead of a raw dropdown.
class ReferenceSortButton extends StatelessWidget {
  const ReferenceSortButton({
    required this.controller,
    super.key,
    this.compact = false,
  });

  final AppController controller;
  final bool compact;

  static String sortLabel(ReferenceSort sort) => switch (sort) {
    ReferenceSort.newest => 'Newest',
    ReferenceSort.oldest => 'Oldest',
    ReferenceSort.name => 'Name',
    ReferenceSort.kind => 'Media type',
  };

  @override
  Widget build(BuildContext context) => PopupMenuButton<ReferenceSort>(
    key: const ValueKey('reference-library-sort'),
    tooltip: 'Sort references',
    initialValue: controller.referenceSort,
    onSelected: controller.setReferenceSort,
    itemBuilder: (context) => ReferenceSort.values
        .map(
          (sort) => PopupMenuItem<ReferenceSort>(
            value: sort,
            child: Row(
              children: <Widget>[
                Icon(
                  sort == controller.referenceSort ? Icons.check_rounded : null,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(sortLabel(sort)),
              ],
            ),
          ),
        )
        .toList(),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: consoleKeyDecoration(context, selected: false, radius: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.swap_vert_rounded,
            size: 15,
            color: context.colors.onSurfaceVariant,
          ),
          if (!compact) ...<Widget>[
            const SizedBox(width: 6),
            Text(
              sortLabel(controller.referenceSort),
              style: TextStyle(
                color: context.colors.onSurface,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
