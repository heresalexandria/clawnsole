import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../core/models.dart';

Future<void> showCharactersDialog(
  BuildContext context,
  AppController controller,
) => showDialog<void>(
  context: context,
  builder: (context) => _CharactersDialog(controller: controller),
);

class _CharactersDialog extends StatefulWidget {
  const _CharactersDialog({required this.controller});
  final AppController controller;
  @override
  State<_CharactersDialog> createState() => _CharactersDialogState();
}

class _CharactersDialogState extends State<_CharactersDialog> {
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
                'Cast the characters in this direction. Reference mappings are added as editable lines at the end.',
              ),
              const SizedBox(height: 16),
              if (characters.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Write a character name in your script, or add one below.',
                  ),
                ),
              for (final character in characters)
                ListTile(
                  contentPadding: EdgeInsets.zero,
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
    await showDialog<void>(
      context: context,
      builder: (context) => _CharacterMappingEditor(
        controller: widget.controller,
        character: character,
      ),
    );
    if (mounted) setState(() {});
  }
}

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
  late final TextEditingController _name = TextEditingController(
    text: widget.controller.characterMappingName(widget.character),
  );
  late final Set<String> _selected = widget.controller
      .characterMappingReferences(widget.character)
      .toSet();
  bool _renameScript = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final attached = {
      for (final ref in controller.form.references)
        if (ref.kind != MediaReferenceKind.audio)
          controller.referencePromptName(ref): ref.kind,
    };
    final available = {
      for (final ref in controller.savedReferences)
        if (!ref.hidden && ref.kind != MediaReferenceKind.audio)
          ref.name: ref.kind,
      ...attached,
    };
    final names = {...available.keys, ..._selected}.toList()..sort();
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
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 60,
                  decoration: const InputDecoration(
                    labelText: 'Character name',
                    hintText: 'ALEXANDRIA',
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
                          : () => setState(_selected.clear),
                      child: const Text('Remove all'),
                    ),
                  ],
                ),
                const Text(
                  'Choose one or more images or videos. Saved references will be attached to this direction.',
                ),
                const SizedBox(height: 8),
                if (names.isEmpty)
                  const Text(
                    'Add media in References, then return here to cast it.',
                  ),
                for (final name in names)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('@$name'),
                    subtitle: Text(
                      !available.containsKey(name)
                          ? 'Unavailable — remove or replace'
                          : '${available[name] == MediaReferenceKind.video ? 'Video' : 'Image'} · ${attached.containsKey(name) ? 'Attached' : 'Saved reference'}',
                    ),
                    value: _selected.contains(name),
                    onChanged: _saving
                        ? null
                        : (value) => setState(() {
                            if (value == true) {
                              _selected.add(name);
                            } else {
                              _selected.remove(name);
                            }
                          }),
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
}
