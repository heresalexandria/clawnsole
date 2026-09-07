/// The Characters half of the References desk: one console-key toolbar over a
/// card of character rows, then the references no character has claimed.
///
/// A character is the name a direction is matched against and the saved media
/// Create casts for it. The name assignment belongs to one saved reference
/// (the storage rule the whole feature is built on), while any saved file
/// already *called* that name is cast beside it — so a row can carry several
/// thumbnails and still edit one assignment. Per-draft casting stays on the
/// Create screen; nothing here touches a composer tab.
///
/// The toolbar follows the aesthetic tab exactly — facet-count segments, one
/// search field, the primary action key — so the three tabs read as one desk.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_controller_characters.dart';
import '../app/app_theme.dart';
import '../core/models.dart';
import '../core/screenplay.dart';
import 'cast_row.dart';
import 'common_widgets.dart';
import 'filter_menu.dart';
import 'hardware.dart';

/// The toolbar and the character rows, ready to drop into a scroll view.
class CharacterLibraryView extends StatefulWidget {
  const CharacterLibraryView({required this.controller, super.key});

  final AppController controller;

  @override
  State<CharacterLibraryView> createState() => _CharacterLibraryViewState();
}

class _CharacterLibraryViewState extends State<CharacterLibraryView> {
  /// Session-local, like the composer's tab rail: the desk has no room for
  /// another persisted filter, and a character search is a momentary thing.
  String _query = '';
  bool _unassignedOnly = false;

  AppController get controller => widget.controller;

  String get _normalizedQuery => _query.trim().toLowerCase();

  List<CharacterEntry> get _characters {
    final query = _normalizedQuery;
    return controller.characterLibrary
        .where(
          (entry) =>
              query.isEmpty ||
              entry.name.toLowerCase().contains(query) ||
              entry.cast.any((item) => item.name.toLowerCase().contains(query)),
        )
        .toList();
  }

  List<SavedReference> get _unassigned {
    final query = _normalizedQuery;
    return controller.unassignedCharacterReferences
        .where(
          (item) =>
              query.isEmpty ||
              item.name.toLowerCase().contains(query) ||
              (controller.characterFileNameFor(item) ?? '')
                  .toLowerCase()
                  .contains(query),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final characters = _characters;
      final unassigned = _unassigned;
      final nothingSaved =
          controller.characterLibrary.isEmpty &&
          controller.unassignedCharacterReferences.isEmpty;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _CharacterToolbar(
            controller: controller,
            unassignedOnly: _unassignedOnly,
            onSearch: (value) => setState(() => _query = value),
            onFacet: (value) => setState(() => _unassignedOnly = value),
          ),
          const SizedBox(height: 12),
          if (nothingSaved)
            _CharacterEmpty(controller: controller)
          else ...<Widget>[
            if (!_unassignedOnly)
              _CharacterList(
                controller: controller,
                characters: characters,
                filtered: _normalizedQuery.isNotEmpty,
                onResetFilters: _reset,
              ),
            if (!_unassignedOnly && unassigned.isNotEmpty)
              const SizedBox(height: 14),
            if (unassigned.isNotEmpty || _unassignedOnly)
              _UnassignedList(
                controller: controller,
                references: unassigned,
                filtered: _normalizedQuery.isNotEmpty,
                onResetFilters: _reset,
              ),
          ],
        ],
      );
    },
  );

  void _reset() => setState(() {
    _query = '';
    _unassignedOnly = false;
  });
}

class _CharacterToolbar extends StatelessWidget {
  const _CharacterToolbar({
    required this.controller,
    required this.unassignedOnly,
    required this.onSearch,
    required this.onFacet,
  });

  final AppController controller;
  final bool unassignedOnly;
  final ValueChanged<String> onSearch;
  final ValueChanged<bool> onFacet;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.all(10),
    child: LayoutBuilder(
      builder: (context, constraints) {
        // The media toolbar's breakpoint, so all three tabs fold together.
        final wide = constraints.maxWidth >= 860;
        final keys = <Widget>[
          ConsoleFilterSegment(
            key: const ValueKey('character-filter-all'),
            label: 'All',
            semanticLabel: 'All characters',
            icon: Icons.groups_2_rounded,
            count: controller.characterLibrary.length,
            selected: !unassignedOnly,
            onTap: () => onFacet(false),
          ),
          ConsoleFilterSegment(
            key: const ValueKey('character-filter-unassigned'),
            label: 'Unassigned',
            semanticLabel: 'Unassigned references',
            icon: Icons.help_outline_rounded,
            count: controller.unassignedCharacterReferences.length,
            selected: unassignedOnly,
            onTap: () => onFacet(true),
          ),
        ];
        final segments = wide
            ? Wrap(spacing: 5, runSpacing: 5, children: keys)
            : ConsoleSegmentStrip(children: keys);
        final search = TextField(
          key: const ValueKey('character-library-search'),
          onChanged: onSearch,
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded, size: 18),
            hintText: 'Search characters and references',
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        );
        final add = wide
            ? FilledButton.icon(
                key: const ValueKey('new-character'),
                onPressed: () =>
                    unawaited(showCharacterSheet(context, controller)),
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: const Text('New character'),
              )
            : Tooltip(
                message: 'New character',
                child: FilledButton(
                  key: const ValueKey('new-character'),
                  onPressed: () =>
                      unawaited(showCharacterSheet(context, controller)),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Icon(Icons.person_add_alt_1_rounded, size: 18),
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
                add,
              ],
            ),
          ],
        );
      },
    ),
  );
}

class _CharacterList extends StatelessWidget {
  const _CharacterList({
    required this.controller,
    required this.characters,
    required this.filtered,
    required this.onResetFilters,
  });

  final AppController controller;
  final List<CharacterEntry> characters;
  final bool filtered;
  final VoidCallback onResetFilters;

  @override
  Widget build(BuildContext context) {
    if (characters.isEmpty) {
      return SurfaceCard(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              filtered ? 'No characters match.' : 'No characters yet.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              filtered
                  ? 'Try a different search, or clear it to see every '
                        'character.'
                  : 'Name a reference below and it becomes a character your '
                        'directions can cast.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: context.colors.onSurfaceVariant,
              ),
            ),
            if (filtered) ...<Widget>[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('character-empty-reset'),
                  onPressed: onResetFilters,
                  icon: const Icon(Icons.restart_alt_rounded, size: 16),
                  label: const Text('Reset filters'),
                ),
              ),
            ],
          ],
        ),
      );
    }
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (
            var index = 0;
            index < characters.length;
            index += 1
          ) ...<Widget>[
            if (index > 0)
              Divider(height: 1, color: context.colors.outlineVariant),
            _CharacterRow(controller: controller, entry: characters[index]),
          ],
        ],
      ),
    );
  }
}

class _CharacterRow extends StatelessWidget {
  const _CharacterRow({required this.controller, required this.entry});

  final AppController controller;
  final CharacterEntry entry;

  @override
  Widget build(BuildContext context) {
    final names = entry.cast.map((item) => '@${item.name}').join(' · ');
    return InkWell(
      key: ValueKey('character-row-${entry.name}'),
      onTap: () =>
          unawaited(showCharacterSheet(context, controller, character: entry)),
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
                child: CharacterThumbs(
                  controller: controller,
                  references: entry.cast
                      .map((item) => item.name)
                      .toList(growable: false),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_plural(entry.count)} · $names',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                    if (entry.matched.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        '${_plural(entry.matched.length)} cast by file name. '
                        'Rename the media to unlink it.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.3,
                          color: context.tokens.brass,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              _CharacterMenu(controller: controller, entry: entry),
            ],
          ),
        ),
      ),
    );
  }
}

class _CharacterMenu extends StatelessWidget {
  const _CharacterMenu({required this.controller, required this.entry});

  final AppController controller;
  final CharacterEntry entry;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    key: ValueKey('character-menu-${entry.name}'),
    tooltip: 'Actions for ${entry.name}',
    icon: const Icon(Icons.more_horiz_rounded, size: 20),
    onSelected: (value) => unawaited(_run(context, value)),
    itemBuilder: (context) => <PopupMenuEntry<String>>[
      const PopupMenuItem<String>(
        value: 'edit',
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: Icon(Icons.edit_outlined, size: 18),
          title: Text('Edit character'),
        ),
      ),
      for (final reference in entry.references)
        PopupMenuItem<String>(
          key: ValueKey('character-release-${reference.id}'),
          value: 'release:${reference.id}',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.link_off_rounded, size: 18),
            title: Text(
              'Release @${reference.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      PopupMenuItem<String>(
        key: ValueKey('character-delete-${entry.name}'),
        value: 'delete',
        child: const ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: Icon(Icons.person_remove_alt_1_outlined, size: 18),
          title: Text('Delete character'),
        ),
      ),
    ],
  );

  Future<void> _run(BuildContext context, String value) async {
    if (value == 'edit') {
      await showCharacterSheet(context, controller, character: entry);
      return;
    }
    if (value == 'delete') {
      await showDeleteCharacterDialog(context, controller, entry: entry);
      return;
    }
    await controller.unassignReference(value.substring('release:'.length));
  }
}

/// The saved media beside a character's name: overlapping previews, or a ghost
/// when the assignment outlived its media. The Cast row's look, one size up
/// for a library row.
class CharacterThumbs extends StatelessWidget {
  const CharacterThumbs({
    required this.controller,
    required this.references,
    super.key,
  });

  final AppController controller;
  final List<String> references;

  static const double _size = 34;
  static const double _step = 20;

  @override
  Widget build(BuildContext context) {
    final shown = references.take(3).toList();
    return SizedBox(
      width: _size + _step * 2,
      height: _size,
      child: shown.isEmpty
          ? CharacterReferenceThumb(
              controller: controller,
              referenceName: '',
              size: _size,
            )
          : Stack(
              children: <Widget>[
                for (var index = shown.length - 1; index >= 0; index -= 1)
                  Positioned(
                    left: index * _step,
                    child: CharacterReferenceThumb(
                      controller: controller,
                      referenceName: shown[index],
                      size: _size,
                    ),
                  ),
              ],
            ),
    );
  }
}

class _UnassignedList extends StatelessWidget {
  const _UnassignedList({
    required this.controller,
    required this.references,
    required this.filtered,
    required this.onResetFilters,
  });

  final AppController controller;
  final List<SavedReference> references;
  final bool filtered;
  final VoidCallback onResetFilters;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Eyebrow('Unassigned', icon: Icons.help_outline_rounded),
              const SizedBox(height: 6),
              Text(
                'Saved media no character has claimed. Naming one makes it a '
                'character your directions can cast.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (references.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  filtered
                      ? 'No unassigned reference matches.'
                      : 'Every saved reference has a character.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
                if (filtered)
                  TextButton.icon(
                    key: const ValueKey('unassigned-empty-reset'),
                    onPressed: onResetFilters,
                    icon: const Icon(Icons.restart_alt_rounded, size: 16),
                    label: const Text('Reset filters'),
                  ),
              ],
            ),
          )
        else
          for (final reference in references) ...<Widget>[
            Divider(height: 1, color: context.colors.outlineVariant),
            _UnassignedRow(
              key: ValueKey('unassigned-row-${reference.id}'),
              controller: controller,
              reference: reference,
            ),
          ],
      ],
    ),
  );
}

class _UnassignedRow extends StatelessWidget {
  const _UnassignedRow({
    required this.controller,
    required this.reference,
    super.key,
  });

  final AppController controller;
  final SavedReference reference;

  @override
  Widget build(BuildContext context) {
    // A file already called VINNY is cast as VINNY whether or not anything
    // carries the assignment, so the row offers to make that official.
    final implied = controller.characterFileNameFor(reference);
    final free =
        implied != null && controller.characterNameHolder(implied) == null;
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: isHardwareTouchPlatform ? kHardwareTouchTarget : 0,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        child: Row(
          children: <Widget>[
            CharacterReferenceThumb(
              controller: controller,
              referenceName: reference.name,
              size: 34,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '@${reference.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (implied != null) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      free
                          ? 'Cast as $implied by its file name.'
                          : 'Its file name says $implied, which already names '
                                'another reference.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.3,
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (free)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 190),
                child: CharacterBusyButton(
                  buttonKey: ValueKey('unassigned-adopt-${reference.id}'),
                  label: 'Name $implied',
                  icon: Icons.bolt_rounded,
                  filled: false,
                  onPressed: () => controller.assignReferencesToCharacter(
                    implied,
                    <String>[reference.id],
                  ),
                ),
              ),
            IconButton(
              key: ValueKey('unassigned-name-${reference.id}'),
              tooltip: 'Name a character for ${reference.name}',
              iconSize: 18,
              onPressed: () => unawaited(
                showCharacterSheet(context, controller, seed: reference),
              ),
              icon: const Icon(Icons.person_add_alt_1_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

class _CharacterEmpty extends StatelessWidget {
  const _CharacterEmpty({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Eyebrow('Characters', icon: Icons.groups_2_rounded),
        const SizedBox(height: 10),
        Text(
          'No characters yet.',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          'Save an image or video on the Media tab, then name it here. A named '
          'reference is cast wherever its character appears in a direction.',
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
            key: const ValueKey('new-first-character'),
            onPressed: () => unawaited(showCharacterSheet(context, controller)),
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
            label: const Text('New character'),
          ),
        ),
      ],
    ),
  );
}

/// A button that runs one library write and says so while it runs: 14 px,
/// stroke 2, disabled until the write lands — the trim dialog's spinner.
class CharacterBusyButton extends StatefulWidget {
  const CharacterBusyButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    super.key,
    this.buttonKey,
    this.filled = true,
  });

  final String label;
  final IconData icon;
  final Future<void> Function() onPressed;
  final Key? buttonKey;
  final bool filled;

  @override
  State<CharacterBusyButton> createState() => _CharacterBusyButtonState();
}

class _CharacterBusyButtonState extends State<CharacterBusyButton> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      await widget.onPressed();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = _busy
        ? const SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(widget.icon, size: 17);
    final label = Text(
      widget.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    if (widget.filled) {
      return FilledButton.icon(
        key: widget.buttonKey,
        onPressed: _busy ? null : () => unawaited(_run()),
        icon: icon,
        label: label,
      );
    }
    return TextButton.icon(
      key: widget.buttonKey,
      onPressed: _busy ? null : () => unawaited(_run()),
      icon: icon,
      label: label,
    );
  }
}

/// Names a character and chooses the reference that carries the name. An empty
/// [character] adds a new one; [seed] preselects a reference and proposes the
/// name its file name implies.
Future<void> showCharacterSheet(
  BuildContext context,
  AppController controller, {
  CharacterEntry? character,
  SavedReference? seed,
}) => showDialog<void>(
  context: context,
  builder: (context) =>
      _CharacterSheet(controller: controller, character: character, seed: seed),
);

Future<void> showDeleteCharacterDialog(
  BuildContext context,
  AppController controller, {
  required CharacterEntry entry,
}) => showDialog<void>(
  context: context,
  builder: (context) =>
      _DeleteCharacterDialog(controller: controller, entry: entry),
);

class _CharacterSheet extends StatefulWidget {
  const _CharacterSheet({required this.controller, this.character, this.seed});

  final AppController controller;
  final CharacterEntry? character;
  final SavedReference? seed;

  @override
  State<_CharacterSheet> createState() => _CharacterSheetState();
}

class _CharacterSheetState extends State<_CharacterSheet> {
  late final TextEditingController _name;
  late final TextEditingController _search;
  late final Set<String> _selected;
  bool _saving = false;
  String? _error;

  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    final seed = widget.seed;
    _name = TextEditingController(
      text:
          widget.character?.name ??
          (seed == null ? '' : controller.characterFileNameFor(seed) ?? ''),
    );
    _selected = <String>{
      ...?widget.character?.references.map((item) => item.id),
      if (seed != null) seed.id,
    };
    _search = TextEditingController();
    _name.addListener(_refresh);
    _search.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _name
      ..removeListener(_refresh)
      ..dispose();
    _search
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  /// Everything castable, the current members first, then the files whose own
  /// name matches what is being typed, then the rest alphabetically.
  List<SavedReference> get _candidates {
    final typed = normalizeCharacterName(_name.text);
    final query = _search.text.trim().toLowerCase();
    final visible =
        controller.savedReferences
            .where(
              (item) =>
                  !item.hidden &&
                  item.kind != MediaReferenceKind.audio &&
                  (query.isEmpty || item.name.toLowerCase().contains(query)),
            )
            .toList()
          ..sort((a, b) {
            final rank = _rank(a, typed).compareTo(_rank(b, typed));
            return rank != 0
                ? rank
                : a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });
    return visible;
  }

  int _rank(SavedReference reference, String typed) {
    if (_selected.contains(reference.id)) return 0;
    if (typed.isNotEmpty &&
        normalizeCharacterName(characterReferenceBaseName(reference.name)) ==
            typed) {
      return 1;
    }
    if (normalizeCharacterName(reference.characterName ?? '').isEmpty) return 2;
    return 3;
  }

  /// Files Create would also cast under the typed name, whoever carries it.
  List<SavedReference> get _byFileName {
    final typed = normalizeCharacterName(_name.text);
    if (typed.isEmpty) return const <SavedReference>[];
    return controller.savedReferences
        .where(
          (item) =>
              !_selected.contains(item.id) &&
              controller.characterFileNameFor(item) == typed,
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final adding = widget.character == null;
    final candidates = _candidates;
    final alsoCast = _byFileName;
    final typed = normalizeCharacterName(_name.text);
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(adding ? 'New character' : 'Edit character'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextField(
                  key: const ValueKey('character-name-field'),
                  controller: _name,
                  autofocus: adding,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 60,
                  decoration: const InputDecoration(
                    labelText: 'Character name',
                    hintText: 'ALEXANDRIA',
                    helperText:
                        'Directions cast this name wherever it appears.',
                    helperMaxLines: 2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Reference',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'One saved reference carries the name. Saved media already '
                  'called the same thing is cast beside it.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
                if (alsoCast.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    'Also cast as $typed by file name: '
                    '${alsoCast.map((item) => '@${item.name}').join(' · ')}',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: context.tokens.brass,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                TextField(
                  key: const ValueKey('character-reference-search'),
                  controller: _search,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Search references',
                    prefixIcon: Icon(Icons.search_rounded, size: 18),
                  ),
                ),
                const SizedBox(height: 8),
                if (candidates.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      controller.savedReferences.isEmpty
                          ? 'Save an image or video on the Media tab, then '
                                'return here to name it.'
                          : 'No reference matches that search.',
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: SingleChildScrollView(
                      primary: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          for (final reference in candidates)
                            _referenceTile(reference),
                        ],
                      ),
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(color: context.colors.error),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            key: const ValueKey('save-character'),
            onPressed: _saving ? null : () => unawaited(_save()),
            icon: _saving
                ? const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded, size: 17),
            label: Text(_saving ? 'Saving…' : 'Save character'),
          ),
        ],
      ),
    );
  }

  Widget _referenceTile(SavedReference reference) {
    final held = normalizeCharacterName(reference.characterName ?? '');
    final selected = _selected.contains(reference.id);
    return CheckboxListTile(
      key: ValueKey('character-reference-${reference.id}'),
      contentPadding: EdgeInsets.zero,
      secondary: CharacterReferenceThumb(
        controller: controller,
        referenceName: reference.name,
        size: 44,
      ),
      title: Text(
        '@${reference.name}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        held.isEmpty
            ? '${reference.kind == MediaReferenceKind.video ? 'Video' : 'Image'} · No character'
            : '${reference.kind == MediaReferenceKind.video ? 'Video' : 'Image'} · $held',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      value: selected,
      onChanged: _saving
          ? null
          // One name, one reference: choosing another moves the assignment
          // rather than dead-ending on the storage rule at save time.
          : (value) => setState(() {
              _selected.clear();
              if (value == true) _selected.add(reference.id);
              _error = null;
            }),
    );
  }

  Future<void> _save() async {
    final previous = widget.character?.name ?? '';
    final typed = normalizeCharacterName(_name.text);
    if (typed.isEmpty) {
      setState(() => _error = 'Enter a character name.');
      return;
    }
    final problem = screenplayCharacterNameProblem(typed);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    if (_selected.isEmpty && widget.character == null) {
      setState(
        () => _error =
            'Choose a reference. A character appears here once saved media '
            'carries its name — until then there is nothing to cast.',
      );
      return;
    }
    final current = <String>{
      ...controller.characterReferencesNamed(previous).map((item) => item.id),
      ...controller.characterReferencesNamed(typed).map((item) => item.id),
    };
    final holder = controller.characterNameHolder(
      typed,
      allowedIds: <String>{..._selected, ...current},
    );
    if (holder != null) {
      setState(
        () => _error =
            '$typed already names “${holder.name}”. A character name belongs '
            'to one reference — release that one first, or choose another '
            'name.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final saved = await controller.saveCharacter(
      name: typed,
      previousName: previous,
      referenceIds: _selected,
    );
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() => _saving = false);
    }
  }
}

class _DeleteCharacterDialog extends StatefulWidget {
  const _DeleteCharacterDialog({required this.controller, required this.entry});

  final AppController controller;
  final CharacterEntry entry;

  @override
  State<_DeleteCharacterDialog> createState() => _DeleteCharacterDialogState();
}

class _DeleteCharacterDialogState extends State<_DeleteCharacterDialog> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text('Delete ${widget.entry.name}?'),
      content: Text(
        'The name is cleared from '
        '${_plural(widget.entry.references.length)}. The media itself stays in '
        'References, and any draft already casting it keeps its cast.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          key: const ValueKey('confirm-delete-character'),
          onPressed: _saving ? null : () => unawaited(_delete()),
          icon: _saving
              ? const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.person_remove_alt_1_outlined, size: 17),
          label: Text(_saving ? 'Deleting…' : 'Delete character'),
        ),
      ],
    ),
  );

  Future<void> _delete() async {
    setState(() => _saving = true);
    await widget.controller.deleteCharacter(widget.entry.name);
    if (mounted) Navigator.pop(context);
  }
}

String _plural(int value) => value == 1 ? '1 reference' : '$value references';
