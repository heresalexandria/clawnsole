import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../app/app_controller.dart';
import '../core/aesthetic_reference.dart';
import '../core/models.dart';

// Small original SVG line drawings, stored by stable names in the library.
const aestheticIconPaths = <String, String>{
  'sparkles': '<path d="m12 2 3 7 7 3-7 3-3 7-3-7-7-3 7-3Z"/>',
  'sun':
      '<circle cx="12" cy="12" r="4"/><path d="M12 1v3m0 16v3M1 12h3m16 0h3M4 4l2 2m12 12 2 2M4 20l2-2M18 6l2-2"/>',
  'moon': '<path d="M20 15A9 9 0 0 1 9 3a9 9 0 1 0 11 12Z"/>',
  'star': '<path d="m12 2 3 6 7 1-5 5 1 7-6-3-6 3 1-7-5-5 7-1Z"/>',
  'camera':
      '<rect x="2" y="6" width="20" height="15" rx="3"/><circle cx="12" cy="13" r="4"/><path d="m7 6 2-4h6l2 4"/>',
  'film':
      '<rect x="3" y="2" width="18" height="20" rx="2"/><path d="M7 2v20M17 2v20M3 7h4m-4 5h4m-4 5h4M17 7h4m-4 5h4m-4 5h4"/>',
  'mountain': '<path d="m2 21 8-17 5 10 3-6 5 13Zm5-10 3 2 3-2"/>',
  'leaf': '<path d="M3 21 18 6M4 17C-2 6 12 2 22 2c0 10-3 20-14 17"/>',
  'flower':
      '<circle cx="12" cy="12" r="3"/><path d="M9 9C1 2 12-2 12 7c0-9 11-5 3 2 8-7 12 4 3 3 9 0 5 11-3 3 8 8-3 12-3 3 0 9-11 5-3-3-8 8-12-3-3-3-9 1-5-10 3-3Z"/>',
  'waves':
      '<path d="M2 6q5-5 10 0t10 0M2 12q5-5 10 0t10 0M2 18q5-5 10 0t10 0"/>',
  'flame':
      '<path d="M13 2c2 8-7 7-5 13 3 0 5-4 5-6 10 9 4 14-2 13C0 21 3 11 7 8c0 5 2 5 2 5-2-5 3-7 4-11Z"/>',
  'cloud': '<path d="M6 19a5 5 0 0 1-1-10 7 7 0 0 1 13-1 6 6 0 0 1 0 11Z"/>',
  'diamond': '<path d="m2 8 5-6h10l5 6-10 14Zm0 0h20M7 2l5 20 5-20"/>',
  'eye':
      '<path d="M1 12Q12-3 23 12 12 27 1 12Z"/><circle cx="12" cy="12" r="3"/>',
  'palette':
      '<path d="M12 2a10 10 0 1 0 0 20c5 0-2-6 3-6 9 0 9-14-3-14Z"/><circle cx="7" cy="9" r="1"/><circle cx="12" cy="6" r="1"/><circle cx="17" cy="9" r="1"/>',
  'bolt': '<path d="m14 1-12 13h9l-1 9L22 9h-9Z"/>',
};

class AestheticIcon extends StatelessWidget {
  const AestheticIcon({
    super.key,
    required this.name,
    required this.color,
    this.size = 22,
  });
  final String name;
  final int color;
  final double size;
  @override
  Widget build(BuildContext context) => SvgPicture.string(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">${aestheticIconPaths[name] ?? aestheticIconPaths['sparkles']}</svg>',
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(Color(color), BlendMode.srcIn),
  );
}

class AestheticReferencePicker extends StatelessWidget {
  const AestheticReferencePicker({
    super.key,
    required this.controller,
    this.compact = false,
  });
  final AppController controller;
  final bool compact;
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
            if (!compact)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Text(
                  selected?.title ?? 'Aesthetic',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
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
