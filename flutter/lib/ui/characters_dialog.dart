import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../core/models.dart';
import '../core/screenplay.dart';
import 'cast_row.dart';
import 'filter_menu.dart';

Future<void> showCharactersDialog(
  BuildContext context,
  AppController controller,
) {
  controller.syncScreenplayCharacterMappings();
  return showDialog<void>(
    context: context,
    builder: (context) => _CharactersDialog(controller: controller),
  );
}

/// Casts one character. An empty [character] adds a new one.
///
/// Opened from the Characters dialog and from a chip in the composer's Cast
/// row, so both routes edit the same record.
Future<void> showCharacterMappingEditor(
  BuildContext context,
  AppController controller, {
  required String character,
}) => showDialog<void>(
  context: context,
  builder: (context) =>
      _CharacterMappingEditor(controller: controller, character: character),
);

/// The mapped media beside a character's name: overlapping previews, or a
/// ghost when nothing is cast yet.
class _CastThumbs extends StatelessWidget {
  const _CastThumbs({required this.controller, required this.references});

  final AppController controller;
  final List<String> references;

  static const double _size = 30;
  static const double _step = 18;

  @override
  Widget build(BuildContext context) {
    final shown = references.take(2).toList();
    return SizedBox(
      width: _size + _step,
      height: _size,
      child: shown.isEmpty
          ? CharacterReferenceThumb(
              controller: controller,
              referenceName: '',
              size: _size,
            )
          : Stack(
              children: <Widget>[
                for (var index = 0; index < shown.length; index += 1)
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

class _CharactersDialog extends StatefulWidget {
  const _CharactersDialog({required this.controller});
  final AppController controller;
  @override
  State<_CharactersDialog> createState() => _CharactersDialogState();
}

class _CharactersDialogState extends State<_CharactersDialog> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final characters = controller.scriptCharacterNames;
    return AlertDialog(
      title: const Text('Characters'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Cast the characters in this direction. The casting is kept '
                'out of the prompt box and sent with it.',
              ),
              const SizedBox(height: 16),
              if (characters.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Add any character below, even before writing the script. Matching references are selected automatically; you can change them.',
                  ),
                ),
              for (final character in characters)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _CastThumbs(
                    controller: controller,
                    references: controller.characterMappingReferences(
                      character,
                    ),
                  ),
                  title: Text(controller.characterMappingName(character)),
                  subtitle: Text(
                    [
                      if (controller.characterMappingName(character) !=
                          character)
                        'In script: $character',
                      if (controller
                          .characterMappingReferences(character)
                          .isEmpty)
                        'No references'
                      else
                        controller
                            .characterMappingReferences(character)
                            .map((name) => '@$name')
                            .join(' · '),
                    ].join('\n'),
                  ),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _edit(character),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _edit(''),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Add character'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }

  Future<void> _edit(String character) async {
    await showCharacterMappingEditor(
      context,
      widget.controller,
      character: character,
    );
    if (mounted) setState(() {});
  }
}

/// One choosable reference. [kind] is null when the name is still cast but no
/// longer names anything in the library or this direction.
typedef _CastCandidate = ({
  String name,
  MediaReferenceKind? kind,
  bool attached,
  String characterName,
});

enum _CastKindFilter { all, image, video }

class _CharacterMappingEditor extends StatefulWidget {
  const _CharacterMappingEditor({
    required this.controller,
    required this.character,
  });
  final AppController controller;
  final String character;
  @override
  State<_CharacterMappingEditor> createState() =>
      _CharacterMappingEditorState();
}

class _CharacterMappingEditorState extends State<_CharacterMappingEditor> {
  late final TextEditingController _name;
  late final TextEditingController _search;
  late final Set<String> _selected;
  _CastKindFilter _kind = _CastKindFilter.all;
  bool _selectionEdited = false;
  bool _renameScript = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.controller.characterMappingName(widget.character),
    );
    _search = TextEditingController();
    _selected = widget.controller
        .characterMappingReferences(widget.character)
        .toSet();
    _name.addListener(_refresh);
    _search.addListener(_refresh);
    widget.controller.addListener(_refresh);
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      // Naming a new character suggests matching media until the user makes
      // a selection. Renaming an existing cast keeps its selected references.
      if (widget.character.isEmpty && !_selectionEdited && !_saving) {
        _selected
          ..clear()
          ..addAll(widget.controller.characterMappingReferences(_name.text));
      }
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    _name.removeListener(_refresh);
    _search.removeListener(_refresh);
    _name.dispose();
    _search.dispose();
    super.dispose();
  }

  /// Every reference this character could be cast from: what is attached to
  /// the direction, the visible library, and any name still cast but gone.
  List<_CastCandidate> get _candidates {
    final controller = widget.controller;
    final result = <String, _CastCandidate>{};
    for (final saved in controller.savedReferences) {
      if (saved.hidden || saved.kind == MediaReferenceKind.audio) continue;
      result[saved.name] = (
        name: saved.name,
        kind: saved.kind,
        attached: false,
        characterName: saved.characterName ?? '',
      );
    }
    for (final draft in controller.form.references) {
      if (draft.kind == MediaReferenceKind.audio) continue;
      final name = controller.referencePromptName(draft);
      result[name] = (
        name: name,
        kind: draft.kind,
        attached: true,
        characterName: controller.characterNameForDraft(draft),
      );
    }
    for (final name in _selected) {
      result.putIfAbsent(
        name,
        () => (name: name, kind: null, attached: false, characterName: ''),
      );
    }
    return result.values.toList();
  }

  bool _matchesName(_CastCandidate candidate) {
    final typed = normalizeCharacterName(_name.text);
    if (typed.isEmpty) return false;
    return normalizeCharacterName(candidate.characterName) == typed ||
        normalizeCharacterName(characterReferenceBaseName(candidate.name)) ==
            typed;
  }

  bool _matchesSearch(_CastCandidate candidate) {
    final query = _search.text.trim().toLowerCase();
    return query.isEmpty || candidate.name.toLowerCase().contains(query);
  }

  int _rank(_CastCandidate candidate) {
    if (_matchesName(candidate)) return 0;
    if (_selected.contains(candidate.name)) return 1;
    if (candidate.attached) return 2;
    return 3;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final typed = normalizeCharacterName(_name.text);
    final searched = _candidates.where(_matchesSearch).toList();
    final visible =
        searched
            .where(
              (candidate) => switch (_kind) {
                _CastKindFilter.all => true,
                _CastKindFilter.image =>
                  candidate.kind == MediaReferenceKind.image,
                _CastKindFilter.video =>
                  candidate.kind == MediaReferenceKind.video,
              },
            )
            .toList()
          ..sort((a, b) {
            final rank = _rank(a).compareTo(_rank(b));
            return rank != 0
                ? rank
                : a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });
    final matches = visible.where(_matchesName).length;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(
          widget.character.isEmpty ? 'Add character' : 'Edit character',
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const ValueKey('mapping-character-name'),
                  controller: _name,
                  // A new character starts with its name; an existing one
                  // usually opens to recast, so it keeps the focus quiet.
                  autofocus: widget.character.isEmpty,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 60,
                  decoration: const InputDecoration(
                    labelText: 'Character name',
                    hintText: 'ALEXANDRIA',
                    helperText: 'Any name, with or without a speaking role.',
                    helperMaxLines: 2,
                  ),
                ),
                if (widget.character.isNotEmpty)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Also rename in direction'),
                    subtitle: Text(
                      'Replace occurrences of ${widget.character} in the script.',
                    ),
                    value: _renameScript,
                    onChanged: _saving
                        ? null
                        : (value) =>
                              setState(() => _renameScript = value ?? false),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Expanded(child: Text('References')),
                    TextButton(
                      onPressed: _saving || _selected.isEmpty
                          ? null
                          : () => setState(() {
                              _selectionEdited = true;
                              _selected.clear();
                            }),
                      child: const Text('Remove all'),
                    ),
                  ],
                ),
                const Text(
                  'Matching names come first, preselected. Saved references '
                  'are attached to this direction.',
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const ValueKey('mapping-reference-search'),
                  controller: _search,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Search references',
                    prefixIcon: Icon(Icons.search_rounded, size: 18),
                  ),
                ),
                const SizedBox(height: 8),
                // A Wrap, not a Row: three keys plus their counts do not fit a
                // phone-width dialog on one line.
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final entry in <(_CastKindFilter, String, String)>[
                      (_CastKindFilter.all, 'All', 'mapping-kind-all'),
                      (_CastKindFilter.image, 'Images', 'mapping-kind-image'),
                      (_CastKindFilter.video, 'Videos', 'mapping-kind-video'),
                    ])
                      ConsoleFilterSegment(
                        key: ValueKey(entry.$3),
                        label: entry.$2,
                        semanticLabel: '${entry.$2} references',
                        compact: true,
                        selected: _kind == entry.$1,
                        count: switch (entry.$1) {
                          _CastKindFilter.all => searched.length,
                          _CastKindFilter.image =>
                            searched
                                .where(
                                  (item) =>
                                      item.kind == MediaReferenceKind.image,
                                )
                                .length,
                          _CastKindFilter.video =>
                            searched
                                .where(
                                  (item) =>
                                      item.kind == MediaReferenceKind.video,
                                )
                                .length,
                        },
                        onTap: () => setState(() => _kind = entry.$1),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                if (visible.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _candidates.isEmpty
                          ? 'Add media in References, then return here to cast it.'
                          : 'No reference matches that search.',
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    // A Column rather than a lazy list: the dialog is small,
                    // and every row stays findable for ensureVisible.
                    child: SingleChildScrollView(
                      primary: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (
                            var index = 0;
                            index < visible.length;
                            index += 1
                          ) ...<Widget>[
                            if (index == 0 && matches > 0)
                              _SectionEyebrow(label: 'Matches $typed'),
                            if (index == matches && matches > 0)
                              const _SectionEyebrow(label: 'Other references'),
                            _referenceTile(controller, visible[index]),
                          ],
                        ],
                      ),
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('save-character-mapping'),
            onPressed: _saving
                ? null
                : () async {
                    setState(() {
                      _saving = true;
                      _error = null;
                    });
                    final error = await controller.saveCharacterMapping(
                      scriptName: widget.character.isEmpty
                          ? _name.text.trim().toUpperCase()
                          : widget.character,
                      name: _name.text,
                      referenceNames: _selected.toList(),
                      renameInScript: _renameScript,
                    );
                    if (!context.mounted) return;
                    if (error == null) {
                      Navigator.pop(context);
                    } else {
                      setState(() {
                        _saving = false;
                        _error = error;
                      });
                    }
                  },
            child: Text(_saving ? 'Saving…' : 'Save mapping'),
          ),
        ],
      ),
    );
  }

  Widget _referenceTile(
    AppController controller,
    _CastCandidate candidate,
  ) => CheckboxListTile(
    contentPadding: EdgeInsets.zero,
    secondary: CharacterReferenceThumb(
      controller: controller,
      referenceName: candidate.name,
      size: 44,
    ),
    title: Text('@${candidate.name}'),
    subtitle: Text(
      candidate.kind == null
          ? 'Unavailable — remove or replace'
          : '${candidate.kind == MediaReferenceKind.video ? 'Video' : 'Image'} · ${candidate.attached ? 'Attached' : 'Saved reference'}',
    ),
    value: _selected.contains(candidate.name),
    onChanged: _saving
        ? null
        : (value) => setState(() {
            _selectionEdited = true;
            if (value == true) {
              _selected.add(candidate.name);
            } else {
              _selected.remove(candidate.name);
            }
          }),
  );
}

class _SectionEyebrow extends StatelessWidget {
  const _SectionEyebrow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 2),
    child: Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 10.5,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
