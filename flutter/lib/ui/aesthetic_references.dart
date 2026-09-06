import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../core/aesthetic_reference.dart';
import '../core/models.dart';
import 'aesthetic_icons.dart';

export 'aesthetic_icons.dart';

class AestheticReferencePicker extends StatelessWidget {
  const AestheticReferencePicker({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final selected = controller.selectedAestheticReference;
    return PopupMenuButton<String>(
      key: const ValueKey('prompt-aesthetic-picker'),
      tooltip: selected == null
          ? 'Choose aesthetic reference'
          : 'Aesthetic: ${selected.title}',
      onSelected: (id) {
        if (id == 'manage') {
          controller.navigate(AppSection.references);
        } else {
          controller.selectAestheticReference(id.isEmpty ? null : id);
        }
      },
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: '',
          checked: selected == null,
          child: const Text('No aesthetic'),
        ),
        for (final item in controller.aestheticReferences)
          CheckedPopupMenuItem(
            value: item.id,
            checked: selected?.id == item.id,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AestheticIcon(name: item.icon, color: item.color),
                const SizedBox(width: 10),
                Flexible(child: Text(item.title)),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'manage', child: Text('Manage aesthetics…')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AestheticIcon(
              name: selected?.icon ?? 'palette',
              color:
                  selected?.color ??
                  Theme.of(context).colorScheme.primary.toARGB32(),
              size: 18,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Text(
                  selected?.title ?? 'Aesthetic',
                  key: const ValueKey('prompt-aesthetic-label'),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }
}

class AestheticReferenceLibrary extends StatelessWidget {
  const AestheticReferenceLibrary({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Card(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              children: [
                Text(
                  'Aesthetic references',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                TextButton.icon(
                  key: const ValueKey('add-aesthetic-reference'),
                  onPressed: () => showAestheticEditor(context, controller),
                  icon: const Icon(Icons.add),
                  label: const Text('Add aesthetic'),
                ),
              ],
            ),
            const Text(
              'Reusable style direction. Choose one beside Characters in Create to append its text to your prompt.',
            ),
            for (final item in controller.aestheticReferences)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: AestheticIcon(name: item.icon, color: item.color),
                title: Text(item.title),
                subtitle: Text(
                  item.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () =>
                    showAestheticEditor(context, controller, reference: item),
                trailing: IconButton(
                  tooltip: 'Edit ${item.title}',
                  onPressed: () =>
                      showAestheticEditor(context, controller, reference: item),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

Future<void> showAestheticEditor(
  BuildContext context,
  AppController controller, {
  AestheticReference? reference,
}) => showDialog<void>(
  context: context,
  builder: (_) =>
      _AestheticEditor(controller: controller, reference: reference),
);

class _AestheticEditor extends StatefulWidget {
  const _AestheticEditor({required this.controller, this.reference});
  final AppController controller;
  final AestheticReference? reference;
  @override
  State<_AestheticEditor> createState() => _AestheticEditorState();
}

class _AestheticEditorState extends State<_AestheticEditor> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.reference?.title);
  late final _text = TextEditingController(text: widget.reference?.text);
  late String _icon = widget.reference?.icon ?? 'sparkles';
  late int _color = widget.reference?.color ?? 0xffaf853c;
  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.reference == null
          ? 'Add aesthetic reference'
          : 'Edit aesthetic reference',
    ),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const ValueKey('aesthetic-title'),
                controller: _title,
                decoration: const InputDecoration(labelText: 'Title'),
                maxLength: 80,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a title.'
                    : null,
              ),
              const SizedBox(height: 12),
              const Text('Icon'),
              Wrap(
                children: [
                  for (final name in aestheticIconPaths.keys)
                    IconButton(
                      tooltip: name,
                      isSelected: name == _icon,
                      style: IconButton.styleFrom(
                        backgroundColor: name == _icon
                            ? Theme.of(context).colorScheme.secondaryContainer
                            : null,
                      ),
                      onPressed: () => setState(() => _icon = name),
                      icon: AestheticIcon(name: name, color: _color),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('Color'),
              Wrap(
                children: [
                  for (final color in const [
                    0xffaf853c,
                    0xffd64c4c,
                    0xffd97732,
                    0xff738936,
                    0xff258573,
                    0xff3689bb,
                    0xff6262c9,
                    0xffaa55b5,
                    0xffc35c90,
                    0xff737373,
                  ])
                    IconButton(
                      tooltip: 'Color #${color.toRadixString(16).substring(2)}',
                      onPressed: () => setState(() => _color = color),
                      icon: CircleAvatar(
                        radius: 14,
                        backgroundColor: Color(color),
                        child: _color == color
                            ? const Icon(
                                Icons.check,
                                size: 18,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('aesthetic-text'),
                controller: _text,
                minLines: 4,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: 'Reference text',
                  helperText:
                      'Only this text is appended to the generation prompt.',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter aesthetic direction.'
                    : null,
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      if (widget.reference != null)
        TextButton(
          onPressed: () {
            widget.controller.deleteAestheticReference(widget.reference!.id);
            Navigator.pop(context);
          },
          child: const Text('Delete'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!_form.currentState!.validate()) return;
          widget.controller.saveAestheticReference(
            id: widget.reference?.id,
            title: _title.text,
            text: _text.text,
            icon: _icon,
            color: _color,
          );
          Navigator.pop(context);
        },
        child: const Text('Save'),
      ),
    ],
  );
}
