import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import '../core/aesthetic_reference.dart';
import 'aesthetic_icons.dart';
import 'hardware.dart';

export 'aesthetic_icons.dart';

/// The swatches an aesthetic can wear, in picker order: the original ten
/// mid-tones first, then a second dozen that stay legible on both paper and
/// espresso.
const aestheticSwatches = <int>[
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
  0xffcfa32b,
  0xffb85a32,
  0xffe0705a,
  0xffb3304f,
  0xff946243,
  0xff8c8c34,
  0xff4faa7f,
  0xff2f8f8f,
  0xff3f5b8f,
  0xff6f7d94,
  0xff9384d6,
  0xff7b4a7b,
];

/// A small brass eyebrow used inside the picker panel and the editor, where
/// the shared `Eyebrow` widget's letter spacing is a touch too generous.
class AestheticEyebrow extends StatelessWidget {
  const AestheticEyebrow(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label.toUpperCase(),
    style: TextStyle(
      color: context.tokens.brass,
      fontSize: 10,
      letterSpacing: 1.5,
      fontWeight: FontWeight.w800,
    ),
  );
}

/// The Create toolbar's aesthetic key: the current choice as icon + title,
/// opening a searchable anchored panel that lists starred aesthetics first.
class AestheticReferencePicker extends StatefulWidget {
  const AestheticReferencePicker({super.key, required this.controller});

  final AppController controller;

  @override
  State<AestheticReferencePicker> createState() =>
      _AestheticReferencePickerState();
}

class _AestheticReferencePickerState extends State<AestheticReferencePicker> {
  final MenuController _menu = MenuController();

  void _toggle() => _menu.isOpen ? _menu.close() : _menu.open();

  @override
  Widget build(BuildContext context) {
    final selected = widget.controller.selectedAestheticReference;
    final custom = widget.controller.hasCustomAestheticText;
    // A custom definition is named on one line like every other choice; the
    // aesthetic it grew out of is in the tooltip and in the panel, so the
    // toolbar keeps its single row at every width.
    final message = custom
        ? selected == null
              ? 'Aesthetic: Custom definition'
              : 'Aesthetic: Custom definition, edited from ${selected.title}'
        : selected == null
        ? 'Choose aesthetic reference'
        : 'Aesthetic: ${selected.title}';
    return MenuAnchor(
      key: const ValueKey('prompt-aesthetic-picker'),
      controller: _menu,
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll<Color>(context.colors.surface),
        elevation: const WidgetStatePropertyAll<double>(10),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.zero,
        ),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: context.colors.outlineVariant),
          ),
        ),
      ),
      menuChildren: <Widget>[
        _AestheticPickerPanel(controller: widget.controller, menu: _menu),
      ],
      // Exactly one tooltip: the toolbar tests find this key by tooltip.
      builder: (context, menu, _) => Tooltip(
        message: message,
        child: Semantics(
          container: true,
          button: true,
          label: message,
          child: InkWell(
            onTap: _toggle,
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (custom)
                      Icon(
                        Icons.edit_note_rounded,
                        size: 18,
                        color: context.tokens.brass,
                      )
                    else
                      AestheticIcon(
                        name: selected?.icon ?? 'palette',
                        color:
                            selected?.color ??
                            context.colors.primary.toARGB32(),
                        size: 18,
                      ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: Text(
                          widget.controller.aestheticDefinitionLabel ??
                              'Aesthetic',
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
            ),
          ),
        ),
      ),
    );
  }
}

/// The anchored panel behind the Create toolbar's aesthetic key. Its search
/// and tag choice are per-open: the overlay builds this state fresh each
/// time the menu opens.
class _AestheticPickerPanel extends StatefulWidget {
  const _AestheticPickerPanel({required this.controller, required this.menu});

  final AppController controller;
  final MenuController menu;

  @override
  State<_AestheticPickerPanel> createState() => _AestheticPickerPanelState();
}

class _AestheticPickerPanelState extends State<_AestheticPickerPanel> {
  final TextEditingController _search = TextEditingController();
  String? _tag;

  AppController get controller => widget.controller;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(AestheticReference item) {
    final needle = _search.text.trim().toLowerCase();
    final tag = _tag;
    if (tag != null && !item.hasTag(tag)) return false;
    if (needle.isEmpty) return true;
    return item.title.toLowerCase().contains(needle) ||
        item.text.toLowerCase().contains(needle) ||
        item.tags.any((value) => value.toLowerCase().contains(needle));
  }

  Future<void> _choose(String? id) async {
    // An edited definition is somebody's writing; replacing it with another
    // aesthetic's text asks once, and only when it would actually be lost.
    if (controller.hasCustomAestheticText &&
        id != null &&
        (controller.effectiveAestheticText ?? '').isNotEmpty) {
      final replacement = controller.aestheticReferences
          .where((item) => item.id == id)
          .firstOrNull;
      // The panel goes away with the menu, so the question is asked from the
      // navigator that outlives it.
      final navigator = Navigator.of(context, rootNavigator: true);
      widget.menu.close();
      if (replacement == null) return;
      final confirmed = await showDialog<bool>(
        context: navigator.context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Replace your custom definition?'),
          content: Text(
            'The definition you edited is replaced by '
            '“${replacement.title}”. Save it as its own aesthetic first if '
            'you want to keep it.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              key: const ValueKey('aesthetic-replace-confirm'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text('Use ${replacement.title}'),
            ),
          ],
        ),
      );
      if (confirmed == true) controller.selectAestheticReference(id);
      return;
    }
    controller.selectAestheticReference(id);
    widget.menu.close();
  }

  Widget _note(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
    child: Text(
      text,
      style: TextStyle(fontSize: 12.5, color: context.colors.onSurfaceVariant),
    ),
  );

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 340,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 460),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final all = controller.sortedAestheticReferences;
          final tags = controller.aestheticTags;
          final matches = all.where(_matches).toList();
          final favorites = matches.where((item) => item.favorite).toList();
          final rest = matches.where((item) => !item.favorite).toList();
          final grouped = favorites.isNotEmpty && rest.isNotEmpty;
          final selectedId = controller.selectedAestheticReference?.id;
          Widget option(AestheticReference item) => _AestheticPickerRow(
            rowKey: ValueKey('prompt-aesthetic-option-${item.id}'),
            label: item.title,
            reference: item,
            selected:
                !controller.hasCustomAestheticText && selectedId == item.id,
            onTap: () => unawaited(_choose(item.id)),
            onStar: () => controller.toggleAestheticFavorite(item.id),
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (all.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: TextField(
                    key: const ValueKey('prompt-aesthetic-search'),
                    controller: _search,
                    autofocus: true,
                    style: const TextStyle(fontSize: 13),
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded, size: 18),
                      hintText: 'Search aesthetics',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
              if (tags.isNotEmpty)
                SingleChildScrollView(
                  key: const ValueKey('prompt-aesthetic-tags'),
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: Row(
                    children: <Widget>[
                      FilterChip(
                        label: const Text('All tags'),
                        selected: _tag == null,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => setState(() => _tag = null),
                      ),
                      for (final tag in tags) ...<Widget>[
                        const SizedBox(width: 6),
                        FilterChip(
                          label: Text('#$tag'),
                          selected: _tag == tag,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) =>
                              setState(() => _tag = _tag == tag ? null : tag),
                        ),
                      ],
                    ],
                  ),
                ),
              Flexible(
                child: SingleChildScrollView(
                  primary: false,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (all.isEmpty)
                        _note(context, 'No aesthetics yet.')
                      else ...<Widget>[
                        if (controller.hasCustomAestheticText)
                          _AestheticPickerRow(
                            rowKey: const ValueKey('prompt-aesthetic-custom'),
                            label: 'Custom',
                            note: controller.selectedAestheticReference == null
                                ? 'Edited in the composer'
                                : 'Edited from '
                                      '${controller.selectedAestheticReference!.title}',
                            leading: Icons.edit_note_rounded,
                            selected: true,
                            onTap: widget.menu.close,
                          ),
                        _AestheticPickerRow(
                          rowKey: const ValueKey('prompt-aesthetic-none'),
                          label: 'No aesthetic',
                          selected:
                              selectedId == null &&
                              !controller.hasCustomAestheticText,
                          onTap: () => unawaited(_choose(null)),
                        ),
                        if (matches.isEmpty)
                          _note(context, 'No aesthetics match.'),
                        if (grouped)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 10, 16, 6),
                            child: AestheticEyebrow('Favorites'),
                          ),
                        ...favorites.map(option),
                        if (grouped)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 10, 16, 6),
                            child: AestheticEyebrow('All'),
                          ),
                        ...rest.map(option),
                      ],
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: context.colors.outlineVariant),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                  child: TextButton.icon(
                    key: const ValueKey('prompt-aesthetic-manage'),
                    onPressed: () {
                      widget.menu.close();
                      unawaited(controller.openAestheticLibrary());
                    },
                    icon: const Icon(Icons.tune_rounded, size: 16),
                    label: const Text('Manage aesthetics…'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _AestheticPickerRow extends StatelessWidget {
  const _AestheticPickerRow({
    required this.rowKey,
    required this.label,
    required this.selected,
    required this.onTap,
    this.reference,
    this.onStar,
    this.note,
    this.leading,
  });

  final Key rowKey;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// A quiet second line: what a Custom definition was edited from.
  final String? note;

  /// Replaces the aesthetic swatch for rows that stand for no saved record.
  final IconData? leading;

  /// The aesthetic this row stands for; null on the "No aesthetic" row.
  final AestheticReference? reference;
  final VoidCallback? onStar;

  @override
  Widget build(BuildContext context) {
    final item = reference;
    return InkWell(
      key: rowKey,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: isHardwareTouchPlatform ? kHardwareTouchTarget : 36,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Row(
            children: <Widget>[
              if (leading != null)
                Icon(leading, size: 18, color: context.tokens.brass)
              else if (item == null)
                Icon(
                  Icons.block_rounded,
                  size: 18,
                  color: context.colors.onSurfaceVariant,
                )
              else
                AestheticIcon(name: item.icon, color: item.color, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, height: 1.2),
                    ),
                    if (note != null)
                      Text(
                        note!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          height: 1.2,
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (item != null && onStar != null)
                IconButton(
                  key: ValueKey('prompt-aesthetic-star-${item.id}'),
                  tooltip: item.favorite ? 'Unstar' : 'Star',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  onPressed: onStar,
                  icon: Icon(
                    item.favorite
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: item.favorite
                        ? context.tokens.brass
                        : context.colors.onSurfaceVariant,
                  ),
                ),
              if (selected)
                Icon(
                  Icons.check_rounded,
                  size: 17,
                  color: context.colors.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the aesthetic editor, returning the id it saved (null when it was
/// cancelled or deleted). [initialText] seeds a brand-new aesthetic with a
/// definition written somewhere else — the Create composer's Aesthetic
/// Definition accordion.
Future<String?> showAestheticEditor(
  BuildContext context,
  AppController controller, {
  AestheticReference? reference,
  String? initialText,
}) => showDialog<String>(
  context: context,
  builder: (_) => _AestheticEditor(
    controller: controller,
    reference: reference,
    initialText: initialText,
  ),
);

class _AestheticEditor extends StatefulWidget {
  const _AestheticEditor({
    required this.controller,
    this.reference,
    this.initialText,
  });

  final AppController controller;
  final AestheticReference? reference;
  final String? initialText;

  @override
  State<_AestheticEditor> createState() => _AestheticEditorState();
}

class _AestheticEditorState extends State<_AestheticEditor> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.reference?.title);
  late final _text = TextEditingController(
    text: widget.reference?.text ?? widget.initialText,
  );
  late final _tags = TextEditingController(
    text: widget.reference?.tags.join(', ') ?? '',
  );
  late String _icon = widget.reference?.icon ?? 'sparkles';
  late int _color = widget.reference?.color ?? aestheticSwatches.first;
  late bool _favorite = widget.reference?.favorite ?? false;

  /// The icon grid is a finder's aid, not the point of an aesthetic, so it
  /// stays folded until asked for and never grows past a few rows.
  bool _iconPickerOpen = false;

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    _tags.dispose();
    super.dispose();
  }

  void _appendTag(String tag) {
    final tags = <String>[...parseAestheticTags(_tags.text), tag];
    setState(() => _tags.text = normalizeAestheticTags(tags).join(', '));
  }

  Future<void> _confirmDelete() async {
    final reference = widget.reference;
    if (reference == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete aesthetic?'),
        content: Text(
          '“${reference.title}” leaves every tab that uses it. Prompts keep '
          'whatever you already typed.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            key: const ValueKey('aesthetic-delete-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    widget.controller.deleteAestheticReference(reference.id);
    if (mounted) Navigator.pop(context);
  }

  Widget _section(String label, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      AestheticEyebrow(label),
      const SizedBox(height: 8),
      child,
    ],
  );

  @override
  Widget build(BuildContext context) {
    final typed = parseAestheticTags(
      _tags.text,
    ).map((tag) => tag.toLowerCase()).toSet();
    final suggestions = widget.controller.aestheticTags
        .where((tag) => !typed.contains(tag.toLowerCase()))
        .toList();
    return AlertDialog(
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
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('aesthetic-title'),
                        controller: _title,
                        decoration: const InputDecoration(labelText: 'Title'),
                        maxLength: 80,
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Enter a title.'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: IconButton(
                        key: const ValueKey('aesthetic-favorite-toggle'),
                        tooltip: _favorite ? 'Unstar' : 'Star',
                        isSelected: _favorite,
                        onPressed: () => setState(() => _favorite = !_favorite),
                        icon: Icon(
                          _favorite
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          color: _favorite
                              ? context.tokens.brass
                              : context.colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                _section(
                  'Icon & color',
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Tooltip(
                            message: _iconPickerOpen
                                ? 'Hide icons'
                                : 'Choose an icon',
                            child: InkWell(
                              key: const ValueKey('aesthetic-icon-picker'),
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => setState(
                                () => _iconPickerOpen = !_iconPickerOpen,
                              ),
                              child: Container(
                                width: 40,
                                height: 40,
                                alignment: Alignment.center,
                                decoration: consoleKeyDecoration(
                                  context,
                                  selected: _iconPickerOpen,
                                  radius: 10,
                                ),
                                child: AestheticIcon(
                                  name: _icon,
                                  color: _iconPickerOpen
                                      ? context.colors.onPrimary.toARGB32()
                                      : _color,
                                  size: 22,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          TextButton(
                            key: const ValueKey('aesthetic-icon-toggle'),
                            onPressed: () => setState(
                              () => _iconPickerOpen = !_iconPickerOpen,
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              textStyle: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            child: Text(
                              _iconPickerOpen ? 'Hide icons' : 'Change icon',
                            ),
                          ),
                        ],
                      ),
                      if (_iconPickerOpen) ...<Widget>[
                        const SizedBox(height: 8),
                        _IconGrid(
                          selected: _icon,
                          color: _color,
                          onSelected: (name) => setState(() {
                            _icon = name;
                            _iconPickerOpen = false;
                          }),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: <Widget>[
                          for (final color in aestheticSwatches)
                            Tooltip(
                              message:
                                  'Color #${color.toRadixString(16).substring(2)}',
                              child: InkWell(
                                key: ValueKey(
                                  'aesthetic-color-${color.toRadixString(16).substring(2)}',
                                ),
                                customBorder: const CircleBorder(),
                                onTap: () => setState(() => _color = color),
                                child: Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: Color(color),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: _color == color
                                          ? context.colors.onSurface
                                          : Colors.transparent,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: _color == color
                                      ? const Icon(
                                          Icons.check,
                                          size: 14,
                                          color: Colors.white,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('aesthetic-tags'),
                  controller: _tags,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Tags',
                    hintText: 'noir, 1970s, handheld',
                    helperText:
                        'Comma-separated. Filter the library and the Create picker by tag.',
                  ),
                ),
                if (suggestions.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      for (final tag in suggestions)
                        ActionChip(
                          key: ValueKey('aesthetic-tag-suggestion-$tag'),
                          label: Text('#$tag'),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _appendTag(tag),
                        ),
                    ],
                  ),
                ],
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
      actions: <Widget>[
        if (widget.reference != null)
          TextButton(
            key: const ValueKey('aesthetic-delete'),
            onPressed: () => unawaited(_confirmDelete()),
            child: const Text('Delete'),
          ),
        TextButton(
          key: const ValueKey('aesthetic-cancel'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('aesthetic-save'),
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            final saved = widget.controller.saveAestheticReference(
              id: widget.reference?.id,
              title: _title.text,
              text: _text.text,
              icon: _icon,
              color: _color,
              tags: parseAestheticTags(_tags.text),
              favorite: _favorite,
            );
            Navigator.pop(context, saved);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// The folded icon grid: every icon by group, capped at a few rows and
/// scrolling within itself so the dialog never grows to fit all of them.
class _IconGrid extends StatefulWidget {
  const _IconGrid({
    required this.selected,
    required this.color,
    required this.onSelected,
  });

  final String selected;
  final int color;
  final ValueChanged<String> onSelected;

  @override
  State<_IconGrid> createState() => _IconGridState();
}

class _IconGridState extends State<_IconGrid> {
  /// The grid owns its scroll position so the scrollbar can stay visible —
  /// the one hint that more icons wait below the fold.
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: context.colors.outlineVariant),
    ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 190),
      child: Scrollbar(
        controller: _scroll,
        thumbVisibility: true,
        child: SingleChildScrollView(
          key: const ValueKey('aesthetic-icon-sheet'),
          controller: _scroll,
          primary: false,
          padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final group in aestheticIconGroups.entries) ...<Widget>[
                Padding(
                  padding: const EdgeInsets.only(bottom: 5, top: 3),
                  child: AestheticEyebrow(group.key),
                ),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: <Widget>[
                    for (final name in group.value)
                      Tooltip(
                        message: name,
                        child: InkWell(
                          key: ValueKey('aesthetic-icon-$name'),
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => widget.onSelected(name),
                          child: Container(
                            width: 30,
                            height: 30,
                            alignment: Alignment.center,
                            decoration: consoleKeyDecoration(
                              context,
                              selected: name == widget.selected,
                              radius: 8,
                            ),
                            child: AestheticIcon(
                              name: name,
                              color: name == widget.selected
                                  ? context.colors.onPrimary.toARGB32()
                                  : widget.color,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
