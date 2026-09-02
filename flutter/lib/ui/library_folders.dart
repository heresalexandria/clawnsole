/// The folder rail, tree, pickers, and drag-and-drop shared by the Library
/// and References screens.
///
/// Both collections keep one folder vocabulary: a pinned rail on wide
/// layouts (storage rows, then All / Unfiled, then a collapsible tree that
/// renames and creates folders in place and accepts dropped cards or folders),
/// a console-key dropdown that opens the same tree as a sheet on narrow
/// layouts, and one move dialog. [FolderScope] adapts the vocabulary to a
/// collection so the widgets never branch on it.
library;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import '../core/library_rules.dart';
import '../core/models.dart';
import 'common_widgets.dart';
import 'filter_menu.dart';
import 'hardware.dart';

/// One collection's folder vocabulary and controller hooks, so the rail,
/// pickers, and move dialog work identically for films and references.
class FolderScope {
  const FolderScope._(this.controller, this.collection);

  const FolderScope.generated(AppController controller)
    : this._(controller, LibraryCollection.generated);

  const FolderScope.references(AppController controller)
    : this._(controller, LibraryCollection.references);

  final AppController controller;
  final LibraryCollection collection;

  bool get isReferences => collection == LibraryCollection.references;

  String get allLabel => isReferences ? 'All references' : 'All films';
  IconData get allIcon => isReferences
      ? Icons.collections_bookmark_outlined
      : Icons.video_library_outlined;
  String get newFolderLabel =>
      isReferences ? 'New reference folder' : 'New folder';

  /// 'film' / 'films' or 'reference' / 'references' for [count].
  String noun(int count) => isReferences
      ? (count == 1 ? 'reference' : 'references')
      : (count == 1 ? 'film' : 'films');

  String get view => isReferences
      ? controller.referenceFolderView
      : controller.libraryFolderView;

  void setView(String id) => isReferences
      ? controller.setReferenceFolderView(id)
      : controller.setLibraryFolderView(id);

  String get activeLabel => isReferences
      ? controller.activeReferenceFolderLabel
      : controller.activeFolderLabel;

  int count(String view) => isReferences
      ? controller.referenceFolderCount(view)
      : controller.folderCount(view);

  LibraryStorageFilter get storageFilter => isReferences
      ? controller.referenceStorageFilter
      : controller.libraryStorageFilter;

  Future<void> setStorageFilter(LibraryStorageFilter value) => isReferences
      ? controller.setReferenceStorageFilter(value)
      : controller.setLibraryStorageFilter(value);

  Map<LibraryStorageFilter, int> get storageCounts {
    final storages = isReferences
        ? controller.savedReferences.map((item) => item.storage)
        : controller.generations.map((item) => item.storage);
    final counts = <LibraryStorageFilter, int>{
      for (final filter in LibraryStorageFilter.values) filter: 0,
    };
    for (final storage in storages) {
      for (final filter in LibraryStorageFilter.values) {
        if (filter.matches(storage)) counts[filter] = counts[filter]! + 1;
      }
    }
    return counts;
  }

  List<LibraryFolder> get folders => controller.foldersFor(collection);
  List<LibraryFolder> get tree => controller.folderTreeFor(collection);
  LibraryFolder? byId(String? id) =>
      controller.folderById(id, collection: collection);
  List<LibraryFolder> children(String? parentId) =>
      controller.childFolders(parentId, collection: collection);
  int depth(String id) => controller.folderDepth(id, collection: collection);
  String path(String id) => controller.folderPath(id, collection: collection);
  Set<String> branch(String id) =>
      controller.folderBranch(id, collection: collection);
  bool isHidden(String id) =>
      controller.isFolderHidden(id, collection: collection);

  /// Items filed directly inside [folderId].
  int directCount(String folderId) => isReferences
      ? controller.savedReferences
            .where((item) => item.folderId == folderId)
            .length
      : controller.generations
            .where((item) => item.folderId == folderId)
            .length;

  /// The storages the items with [ids] live in.
  Set<LibraryStorage> storagesOf(Set<String> ids) => isReferences
      ? controller.savedReferences
            .where((item) => ids.contains(item.id))
            .map((item) => item.storage)
            .toSet()
      : controller.generations
            .where((item) => ids.contains(item.localId))
            .map((item) => item.storage)
            .toSet();

  /// The folders the items with [ids] are filed in (null for unfiled).
  Set<String?> foldersOf(Set<String> ids) => isReferences
      ? controller.savedReferences
            .where((item) => ids.contains(item.id))
            .map((item) => byId(item.folderId)?.id)
            .toSet()
      : controller.generations
            .where((item) => ids.contains(item.localId))
            .map((item) => byId(item.folderId)?.id)
            .toSet();

  Future<bool> moveItems(Set<String> ids, {required String? folderId}) =>
      isReferences
      ? controller.moveReferences(ids, folderId: folderId)
      : controller.moveGenerations(ids, folderId: folderId);

  Future<bool> createFolder(
    String name, {
    String? parentId,
    LibraryStorage? storage,
  }) => controller.saveLibraryFolder(
    name,
    parentId: parentId,
    collection: collection,
    storage: storage,
  );

  Future<bool> rename(LibraryFolder folder, String name) =>
      controller.renameFolder(folder, name);

  Future<bool> moveFolder(LibraryFolder folder, {required String? parentId}) =>
      controller.moveFolder(folder, parentId: parentId);

  bool canMoveFolder(LibraryFolder folder, {required String? parentId}) =>
      controller.canMoveFolder(folder, parentId: parentId);

  Future<bool> delete(LibraryFolder folder) =>
      controller.deleteLibraryFolder(folder.id);

  /// Whether a brand-new top-level folder may choose between device and
  /// Drive storage.
  bool get canChooseStorage =>
      controller.supportsLocalLibrary && controller.supportsGoogleDrive;

  /// The storage a new folder lands in: its parent's, else the narrowed
  /// storage filter, else the default destination.
  LibraryStorage newFolderStorage({String? parentId}) =>
      byId(parentId)?.storage ??
      switch (storageFilter) {
        LibraryStorageFilter.local => LibraryStorage.local,
        LibraryStorageFilter.drive => LibraryStorage.drive,
        LibraryStorageFilter.all => controller.effectiveStorage,
      };
}

/// What a drag carries: a set of library items or one folder, all from one
/// storage, on their way to a folder row.
class LibraryDragData {
  const LibraryDragData({
    required this.collection,
    required this.storage,
    required this.label,
    this.itemIds = const <String>{},
    this.folder,
  });

  LibraryDragData.forFolder(LibraryFolder folder)
    : this(
        collection: folder.collection,
        storage: folder.storage,
        label: 'Move “${folder.name}”',
        folder: folder,
      );

  final LibraryCollection collection;
  final LibraryStorage storage;
  final String label;
  final Set<String> itemIds;
  final LibraryFolder? folder;

  bool get isFolder => folder != null;
}

/// Makes a card or folder row draggable onto folder rows.
///
/// A mouse starts the drag after the usual slop; touch and pen wait for a
/// long press so a finger can still scroll a list of cards. [mouseOnly]
/// leaves fingers out entirely, for rows whose long press already means
/// something else (the folder rows' context menu).
class LibraryDraggable extends StatelessWidget {
  const LibraryDraggable({
    required this.data,
    required this.child,
    super.key,
    this.enabled = true,
    this.mouseOnly = false,
  });

  final LibraryDragData data;
  final Widget child;
  final bool enabled;
  final bool mouseOnly;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return _PointerKindDraggable<LibraryDragData>(
      data: data,
      mouseOnly: mouseOnly,
      maxSimultaneousDrags: 1,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _DragFeedback(data: data),
      childWhenDragging: Opacity(opacity: .45, child: child),
      onDragStarted: () {
        if (isHardwareTouchPlatform) {
          unawaited(HapticFeedback.selectionClick());
        }
      },
      child: child,
    );
  }
}

class _PointerKindDraggable<T extends Object> extends Draggable<T> {
  const _PointerKindDraggable({
    required super.child,
    required super.feedback,
    required this.mouseOnly,
    super.data,
    super.childWhenDragging,
    super.dragAnchorStrategy,
    super.maxSimultaneousDrags,
    super.onDragStarted,
  });

  final bool mouseOnly;

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) => _PointerKindDragRecognizer(
    debugOwner: this,
    supportedDevices: mouseOnly
        ? const <PointerDeviceKind>{PointerDeviceKind.mouse}
        : null,
  )..onStart = onStart;
}

/// Immediate for a mouse, long-press for everything else.
class _PointerKindDragRecognizer extends MultiDragGestureRecognizer {
  _PointerKindDragRecognizer({
    required super.debugOwner,
    super.supportedDevices,
  }) : super(allowedButtonsFilter: _primaryButtonOnly);

  static bool _primaryButtonOnly(int buttons) => buttons == kPrimaryButton;

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) =>
      event.kind == PointerDeviceKind.mouse
      ? _ImmediateDragState(event.position, event.kind, gestureSettings)
      : _DelayedDragState(
          event.position,
          event.kind,
          gestureSettings,
          kLongPressTimeout,
        );

  @override
  String get debugDescription => 'pointer-kind multidrag';
}

class _ImmediateDragState extends MultiDragPointerState {
  _ImmediateDragState(super.initialPosition, super.kind, super.gestureSettings);

  @override
  void checkForResolutionAfterMove() {
    if (pendingDelta!.distance > computeHitSlop(kind, gestureSettings)) {
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) {
    starter(initialPosition);
  }
}

class _DelayedDragState extends MultiDragPointerState {
  _DelayedDragState(
    super.initialPosition,
    super.kind,
    super.gestureSettings,
    Duration delay,
  ) {
    _timer = Timer(delay, _delayPassed);
  }

  Timer? _timer;
  GestureMultiDragStartCallback? _starter;

  void _delayPassed() {
    _timer = null;
    if (_starter != null) {
      _starter!(initialPosition);
      _starter = null;
    } else {
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) {
    if (_timer == null) {
      starter(initialPosition);
    } else {
      _starter = starter;
    }
  }

  @override
  void checkForResolutionAfterMove() {
    if (_timer == null) return;
    if (pendingDelta!.distance > computeHitSlop(kind, gestureSettings)) {
      resolve(GestureDisposition.rejected);
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}

/// The chip that rides under the pointer while dragging.
class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.data});

  final LibraryDragData data;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: Transform.translate(
      offset: const Offset(14, 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: context.colors.primary,
          borderRadius: BorderRadius.circular(10),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: .28),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              data.isFolder
                  ? Icons.folder_rounded
                  : Icons.drive_file_move_outline,
              size: 16,
              color: context.colors.onPrimary,
            ),
            const SizedBox(width: 8),
            Text(
              data.label,
              style: TextStyle(
                color: context.colors.onPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The two-column library shell.
///
/// Wide layouts pin the heading and the folder rail while the results scroll
/// on their own, so folders never drift off-screen while a long library
/// scrolls — and a card can always be dragged to one. Narrow layouts fold
/// the rail into a dropdown above the results and scroll as one page.
class FolderRailLayout extends StatelessWidget {
  const FolderRailLayout({
    required this.heading,
    required this.rail,
    required this.narrowRail,
    required this.results,
    required this.scrollController,
    required this.desktop,
    required this.padding,
    super.key,
  });

  static const double railWidth = 228;

  final Widget heading;
  final Widget rail;
  final Widget narrowRail;
  final Widget results;
  final ScrollController scrollController;
  final bool desktop;
  final double padding;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (!desktop || !constraints.hasBoundedHeight) {
        return SingleChildScrollView(
          controller: scrollController,
          padding: EdgeInsets.all(padding),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  heading,
                  const SizedBox(height: 22),
                  if (desktop)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SizedBox(width: railWidth, child: rail),
                        const SizedBox(width: 18),
                        Expanded(child: results),
                      ],
                    )
                  else ...<Widget>[
                    narrowRail,
                    const SizedBox(height: 12),
                    results,
                  ],
                ],
              ),
            ),
          ),
        );
      }
      return Padding(
        padding: EdgeInsets.fromLTRB(padding, padding, padding, 0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                heading,
                const SizedBox(height: 22),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SizedBox(
                        width: railWidth,
                        child: SingleChildScrollView(
                          key: const ValueKey('folder-rail-scroll'),
                          primary: false,
                          padding: EdgeInsets.only(bottom: padding),
                          child: rail,
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: SingleChildScrollView(
                          key: const ValueKey('library-results-scroll'),
                          controller: scrollController,
                          padding: EdgeInsets.only(bottom: padding),
                          child: results,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// The wide-layout rail: storage rows, then the folder tree with a
/// new-folder key that opens an editor row in place.
class FolderRail extends StatefulWidget {
  const FolderRail({required this.scope, super.key});

  final FolderScope scope;

  @override
  State<FolderRail> createState() => _FolderRailState();
}

class _FolderRailState extends State<FolderRail> {
  final GlobalKey<FolderTreeState> _tree = GlobalKey<FolderTreeState>();

  @override
  Widget build(BuildContext context) {
    final scope = widget.scope;
    return SurfaceCard(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          StorageSidebarSection(
            controller: scope.controller,
            value: scope.storageFilter,
            counts: scope.storageCounts,
            onChanged: (value) => unawaited(scope.setStorageFilter(value)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Folders',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  key: const ValueKey('folder-rail-new'),
                  tooltip: scope.newFolderLabel,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _tree.currentState?.startCreate(),
                  icon: const Icon(Icons.create_new_folder_outlined, size: 19),
                ),
              ],
            ),
          ),
          FolderTree(
            key: _tree,
            scope: scope,
            selectedId: scope.view,
            onSelect: scope.setView,
            emptyHint:
                'Create a folder for a project, client, or collection. Drag ${scope.noun(2)} or folders here to file them.',
          ),
        ],
      ),
    );
  }
}

/// The narrow-layout folder control: one console-key dropdown that hugs its
/// label and opens the folder sheet, plus a new-folder key.
class FolderDropdownBar extends StatelessWidget {
  const FolderDropdownBar({required this.scope, super.key});

  final FolderScope scope;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Flexible(
        child: Tooltip(
          message: 'Choose a storage or folder view',
          child: InkWell(
            key: const ValueKey('mobile-folder-dropdown'),
            onTap: () => unawaited(showFolderPickerSheet(context, scope)),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: consoleKeyDecoration(
                context,
                selected: false,
                radius: 10,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    scope.view == AppController.libraryFolderAll
                        ? scope.allIcon
                        : scope.view == AppController.libraryFolderUnfiled
                        ? Icons.inbox_outlined
                        : Icons.folder_outlined,
                    color: context.colors.primary,
                    size: 17,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      scope.activeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    '${scope.count(scope.view)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.expand_more_rounded,
                    size: 17,
                    color: context.colors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      const SizedBox(width: 4),
      IconButton(
        key: const ValueKey('mobile-folder-new'),
        tooltip: scope.newFolderLabel,
        onPressed: () =>
            unawaited(showFolderPickerSheet(context, scope, startCreate: true)),
        icon: const Icon(Icons.create_new_folder_outlined, size: 20),
      ),
    ],
  );
}

/// The narrow-layout folder sheet: storage rows and the same folder tree,
/// where a tap chooses the view and closes the sheet.
Future<void> showFolderPickerSheet(
  BuildContext context,
  FolderScope scope, {
  bool startCreate = false,
}) async {
  final tree = GlobalKey<FolderTreeState>();
  if (startCreate) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      tree.currentState?.startCreate();
    });
  }
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .72,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 10),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Choose a folder',
                        style: Theme.of(sheetContext).textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('folder-sheet-new'),
                      tooltip: scope.newFolderLabel,
                      onPressed: () => tree.currentState?.startCreate(),
                      icon: const Icon(Icons.create_new_folder_outlined),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 18),
                  children: <Widget>[
                    ListenableBuilder(
                      listenable: scope.controller,
                      builder: (context, _) => StorageSidebarSection(
                        controller: scope.controller,
                        value: scope.storageFilter,
                        counts: scope.storageCounts,
                        onChanged: (value) {
                          unawaited(scope.setStorageFilter(value));
                          Navigator.pop(sheetContext);
                        },
                      ),
                    ),
                    FolderTree(
                      key: tree,
                      scope: scope,
                      selectedId: scope.view,
                      onSelect: (id) {
                        scope.setView(id);
                        Navigator.pop(sheetContext);
                      },
                      dropTargets: false,
                      emptyHint:
                          'No custom folders yet. Tap the folder + key to make one.',
                    ),
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

enum _FolderAction { subfolder, rename, move, remove }

class _FolderEdit {
  const _FolderEdit.create({required this.parentId, required this.storage})
    : folder = null;

  const _FolderEdit.rename(LibraryFolder this.folder)
    : parentId = null,
      storage = null;

  final LibraryFolder? folder;
  final String? parentId;
  final LibraryStorage? storage;

  bool get isCreate => folder == null;
}

/// The All / Unfiled rows and the folder tree: collapsible branches, in-place
/// create and rename, hover-revealed row menus with right-click and
/// long-press equivalents, and folder drop targets for cards and folders.
class FolderTree extends StatefulWidget {
  const FolderTree({
    required this.scope,
    required this.selectedId,
    required this.onSelect,
    super.key,
    this.showAll = true,
    this.showUnfiled = true,
    this.unfiledLabel = 'Unfiled',
    this.unfiledIcon = Icons.inbox_outlined,
    this.storage,
    this.excludeBranchOf,
    this.dropTargets = true,
    this.rowMenus = true,
    this.emptyHint,
  });

  final FolderScope scope;

  /// The active view id: [AppController.libraryFolderAll],
  /// [AppController.libraryFolderUnfiled], or a folder id.
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final bool showAll;
  final bool showUnfiled;
  final String unfiledLabel;
  final IconData unfiledIcon;

  /// Limits the tree to one storage (a move dialog for items of that
  /// storage).
  final LibraryStorage? storage;

  /// Hides a folder and its descendants (a folder cannot move into itself).
  final String? excludeBranchOf;

  /// Whether rows accept dropped cards and folders.
  final bool dropTargets;

  /// Whether rows carry the subfolder / rename / move / remove menu.
  final bool rowMenus;

  /// Shown under the built-in rows when no folder exists yet.
  final String? emptyHint;

  @override
  State<FolderTree> createState() => FolderTreeState();
}

class FolderTreeState extends State<FolderTree> {
  final TextEditingController _editText = TextEditingController();
  final FocusNode _editFocus = FocusNode(debugLabel: 'folder editor');
  _FolderEdit? _edit;
  bool _saving = false;

  FolderScope get scope => widget.scope;

  @override
  void initState() {
    super.initState();
    _editFocus.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _editFocus
      ..removeListener(_handleFocusChange)
      ..dispose();
    _editText.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    // Losing focus commits like a desktop file manager; an empty or unchanged
    // name simply closes the editor.
    if (!_editFocus.hasFocus && _edit != null && !_saving) {
      unawaited(commitEdit(fromBlur: true));
    }
  }

  /// Opens an editor row for a new folder under [parentId] (null = top
  /// level) in [storage] or the scope's default for that spot.
  void startCreate({String? parentId, LibraryStorage? storage}) {
    if (parentId != null) {
      scope.controller.setFolderCollapsed(parentId, false);
    }
    setState(() {
      _edit = _FolderEdit.create(
        parentId: parentId,
        storage:
            storage ??
            widget.storage ??
            scope.newFolderStorage(parentId: parentId),
      );
      _saving = false;
    });
    _editText.text = '';
    _editFocus.requestFocus();
  }

  /// Turns [folder]'s row into a name editor with the name pre-selected.
  void startRename(LibraryFolder folder) {
    setState(() {
      _edit = _FolderEdit.rename(folder);
      _saving = false;
    });
    _editText
      ..text = folder.name
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: folder.name.length,
      );
    _editFocus.requestFocus();
  }

  void cancelEdit() {
    if (_edit == null) return;
    setState(() {
      _edit = null;
      _saving = false;
    });
  }

  /// Saves the editor row. A blur that fails validation closes the editor
  /// instead of trapping focus; an explicit submit keeps it open to fix.
  Future<void> commitEdit({bool fromBlur = false}) async {
    final edit = _edit;
    if (edit == null || _saving) return;
    final name = _editText.text.trim();
    if (name.isEmpty || (!edit.isCreate && name == edit.folder!.name)) {
      cancelEdit();
      return;
    }
    setState(() => _saving = true);
    final saved = edit.isCreate
        ? await scope.createFolder(
            name,
            parentId: edit.parentId,
            storage: edit.storage,
          )
        : await scope.rename(edit.folder!, name);
    if (!mounted) return;
    if (saved || fromBlur) {
      setState(() {
        _edit = null;
        _saving = false;
      });
      return;
    }
    setState(() => _saving = false);
    _editFocus.requestFocus();
  }

  void _select(String id) {
    if (_edit != null) unawaited(commitEdit(fromBlur: true));
    widget.onSelect(id);
  }

  void _handleAction(_FolderAction action, LibraryFolder folder) {
    switch (action) {
      case _FolderAction.subfolder:
        startCreate(parentId: folder.id);
      case _FolderAction.rename:
        startRename(folder);
      case _FolderAction.move:
        unawaited(showFolderMoveDialog(context, scope, folder));
      case _FolderAction.remove:
        unawaited(confirmFolderDelete(context, scope, folder));
    }
  }

  Future<void> _acceptDrop(LibraryDragData data, String? folderId) async {
    if (data.isFolder) {
      await scope.moveFolder(data.folder!, parentId: folderId);
    } else {
      await scope.moveItems(data.itemIds, folderId: folderId);
    }
  }

  bool _accepts(LibraryDragData data, LibraryFolder? target) {
    if (data.collection != scope.collection) return false;
    if (data.isFolder) {
      final folder = data.folder!;
      if (folder.id == target?.id || folder.parentId == target?.id) {
        return false;
      }
      return scope.canMoveFolder(folder, parentId: target?.id);
    }
    if (target != null && target.storage != data.storage) return false;
    final current = scope.foldersOf(data.itemIds);
    return current.length != 1 || current.single != target?.id;
  }

  Widget _editorRow(int depth, {required IconData icon}) {
    final edit = _edit!;
    final showStorage =
        edit.isCreate && edit.parentId == null && scope.canChooseStorage;
    final storage = edit.storage ?? LibraryStorage.local;
    return Padding(
      key: const ValueKey('folder-editor-row'),
      padding: EdgeInsets.fromLTRB(4 + depth * 14, 2, 4, 5),
      child: Row(
        children: <Widget>[
          const SizedBox(width: 20),
          Icon(icon, size: 18, color: context.colors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: CallbackShortcuts(
              bindings: <ShortcutActivator, VoidCallback>{
                const SingleActivator(LogicalKeyboardKey.escape): cancelEdit,
              },
              child: TextField(
                key: const ValueKey('folder-editor-field'),
                controller: _editText,
                focusNode: _editFocus,
                enabled: !_saving,
                autofocus: true,
                maxLength: maxLibraryFolderNameLength,
                buildCounter:
                    (
                      _, {
                      required currentLength,
                      required isFocused,
                      maxLength,
                    }) => null,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: edit.isCreate ? 'Folder name' : 'Rename',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 7,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onSubmitted: (_) => unawaited(commitEdit()),
              ),
            ),
          ),
          if (showStorage)
            IconButton(
              key: const ValueKey('folder-editor-storage'),
              tooltip:
                  'Saving in ${storage.label}. Switch to ${storage == LibraryStorage.local ? LibraryStorage.drive.label : LibraryStorage.local.label}',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 26, height: 26),
              iconSize: 15,
              onPressed: _saving
                  ? null
                  : () => setState(() {
                      _edit = _FolderEdit.create(
                        parentId: null,
                        storage: storage == LibraryStorage.local
                            ? LibraryStorage.drive
                            : LibraryStorage.local,
                      );
                    }),
              icon: Icon(
                storage == LibraryStorage.drive
                    ? Icons.cloud_outlined
                    : Icons.devices_outlined,
                color: context.colors.onSurfaceVariant,
              ),
            ),
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 1.8),
              ),
            )
          else
            IconButton(
              key: const ValueKey('folder-editor-cancel'),
              tooltip: 'Cancel',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 26, height: 26),
              iconSize: 16,
              onPressed: cancelEdit,
              icon: Icon(
                Icons.close_rounded,
                color: context.colors.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: scope.controller,
    builder: (context, _) => _buildTree(context),
  );

  Widget _buildTree(BuildContext context) {
    final excluded = widget.excludeBranchOf == null
        ? const <String>{}
        : scope.branch(widget.excludeBranchOf!);
    final rows = <Widget>[];
    if (widget.showAll) {
      rows.add(
        _FolderRow(
          key: const ValueKey('folder-row-all'),
          scope: scope,
          icon: scope.allIcon,
          label: scope.allLabel,
          count: scope.count(AppController.libraryFolderAll),
          selected: widget.selectedId == AppController.libraryFolderAll,
          onTap: () => _select(AppController.libraryFolderAll),
        ),
      );
    }
    if (widget.showUnfiled) {
      rows.add(
        _FolderRow(
          key: const ValueKey('folder-row-unfiled'),
          scope: scope,
          icon: widget.unfiledIcon,
          label: widget.unfiledLabel,
          count: scope.count(AppController.libraryFolderUnfiled),
          selected: widget.selectedId == AppController.libraryFolderUnfiled,
          onTap: () => _select(AppController.libraryFolderUnfiled),
          dropTarget: widget.dropTargets,
          accepts: (data) => _accepts(data, null),
          onDrop: (data) => unawaited(_acceptDrop(data, null)),
        ),
      );
    }
    var listedFolders = 0;
    for (final folder in scope.tree) {
      if (widget.storage != null && folder.storage != widget.storage) continue;
      if (excluded.contains(folder.id) || scope.isHidden(folder.id)) continue;
      listedFolders += 1;
      final depth = scope.depth(folder.id);
      if (_edit?.folder?.id == folder.id) {
        rows.add(_editorRow(depth, icon: Icons.folder_outlined));
      } else {
        final children = scope.children(folder.id);
        rows.add(
          _FolderRow(
            key: ValueKey('folder-row-${folder.id}'),
            scope: scope,
            icon: Icons.folder_outlined,
            label: folder.name,
            count: scope.count(folder.id),
            selected: widget.selectedId == folder.id,
            depth: depth,
            folder: folder,
            hasChildren: children.any(
              (child) =>
                  widget.storage == null || child.storage == widget.storage,
            ),
            collapsed: scope.controller.isFolderCollapsed(folder.id),
            onTap: () => _select(folder.id),
            onAction: widget.rowMenus
                ? (action) => _handleAction(action, folder)
                : null,
            dropTarget: widget.dropTargets,
            draggable: widget.dropTargets,
            accepts: (data) => _accepts(data, folder),
            onDrop: (data) => unawaited(_acceptDrop(data, folder.id)),
          ),
        );
      }
      if (_edit != null && _edit!.isCreate && _edit!.parentId == folder.id) {
        rows.add(_editorRow(depth + 1, icon: Icons.create_new_folder_outlined));
      }
    }
    if (_edit != null && _edit!.isCreate && _edit!.parentId == null) {
      rows.add(_editorRow(0, icon: Icons.create_new_folder_outlined));
    }
    final hasBuiltIns = widget.showAll || widget.showUnfiled;
    final hasFolderRows = listedFolders > 0 || _edit != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ...rows.take(
          hasBuiltIns
              ? (widget.showAll ? 1 : 0) + (widget.showUnfiled ? 1 : 0)
              : 0,
        ),
        if (hasBuiltIns && hasFolderRows)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Divider(height: 1),
          ),
        ...rows.skip((widget.showAll ? 1 : 0) + (widget.showUnfiled ? 1 : 0)),
        if (!hasFolderRows && widget.emptyHint != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
            child: Text(
              widget.emptyHint!,
              style: TextStyle(
                height: 1.4,
                fontSize: 11.5,
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// One row of the tree: built-in view or folder, with chevron, count, the
/// hover-revealed menu, and drop highlighting.
class _FolderRow extends StatefulWidget {
  const _FolderRow({
    required this.scope,
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    super.key,
    this.depth = 0,
    this.folder,
    this.hasChildren = false,
    this.collapsed = false,
    this.onAction,
    this.dropTarget = false,
    this.draggable = false,
    this.accepts,
    this.onDrop,
  });

  final FolderScope scope;
  final IconData icon;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final int depth;
  final LibraryFolder? folder;
  final bool hasChildren;
  final bool collapsed;
  final ValueChanged<_FolderAction>? onAction;
  final bool dropTarget;
  final bool draggable;
  final bool Function(LibraryDragData data)? accepts;
  final ValueChanged<LibraryDragData>? onDrop;

  @override
  State<_FolderRow> createState() => _FolderRowState();
}

class _FolderRowState extends State<_FolderRow> {
  bool _hovered = false;
  bool _menuFocused = false;
  bool _dragOver = false;
  Timer? _expandTimer;

  @override
  void dispose() {
    _expandTimer?.cancel();
    super.dispose();
  }

  List<PopupMenuEntry<_FolderAction>> _menuItems() =>
      const <PopupMenuEntry<_FolderAction>>[
        PopupMenuItem(
          value: _FolderAction.subfolder,
          child: Text('New subfolder'),
        ),
        PopupMenuItem(value: _FolderAction.rename, child: Text('Rename')),
        PopupMenuItem(value: _FolderAction.move, child: Text('Move to…')),
        PopupMenuItem(value: _FolderAction.remove, child: Text('Remove')),
      ];

  Future<void> _showContextMenu(Offset position) async {
    if (widget.onAction == null) return;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final action = await showMenu<_FolderAction>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        overlay == null ? Rect.zero : Offset.zero & overlay.size,
      ),
      items: _menuItems(),
    );
    if (action != null && mounted) widget.onAction!(action);
  }

  void _toggleCollapse() {
    hardwareSelectionFeedback();
    widget.scope.controller.setFolderCollapsed(
      widget.folder!.id,
      !widget.collapsed,
    );
  }

  bool _willAccept(DragTargetDetails<LibraryDragData> details) {
    final accepted = widget.accepts?.call(details.data) ?? false;
    if (!accepted) return false;
    setState(() => _dragOver = true);
    // Hovering a closed branch opens it so a drop can reach its children.
    if (widget.folder != null && widget.collapsed && widget.hasChildren) {
      _expandTimer?.cancel();
      _expandTimer = Timer(const Duration(milliseconds: 650), () {
        if (mounted) {
          widget.scope.controller.setFolderCollapsed(widget.folder!.id, false);
        }
      });
    }
    return true;
  }

  void _leave() {
    _expandTimer?.cancel();
    _expandTimer = null;
    if (_dragOver && mounted) setState(() => _dragOver = false);
  }

  @override
  Widget build(BuildContext context) {
    final folder = widget.folder;
    final selected = widget.selected;
    final touch = isHardwareTouchPlatform;
    // The menu key shows on hover, selection, keyboard focus, and always on
    // touch; assistive technology can always reach it.
    final showMenu =
        widget.onAction != null &&
        (touch || _hovered || selected || _menuFocused);
    final foreground = selected
        ? context.colors.onPrimaryContainer
        : context.colors.onSurface;
    final chevron = SizedBox(
      width: 20,
      height: 24,
      child: widget.hasChildren && folder != null
          ? IconButton(
              key: ValueKey('folder-toggle-${folder.id}'),
              tooltip: widget.collapsed
                  ? 'Expand ${folder.name}'
                  : 'Collapse ${folder.name}',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 20, height: 24),
              iconSize: 17,
              onPressed: _toggleCollapse,
              icon: Icon(
                widget.collapsed
                    ? Icons.chevron_right_rounded
                    : Icons.expand_more_rounded,
                color: context.colors.onSurfaceVariant,
              ),
            )
          : null,
    );
    // The row speaks once — name, storage, count — while the chevron and
    // menu keep their own buttons; the drawn text and icons stay silent.
    Widget row = Semantics(
      container: true,
      button: true,
      selected: selected,
      label: folder == null
          ? widget.label
          : '${widget.label}, ${folder.storage.label}',
      value: '${widget.count}',
      onTap: widget.onTap,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onSecondaryTapUp: widget.onAction == null
              ? null
              : (details) =>
                    unawaited(_showContextMenu(details.globalPosition)),
          onLongPressStart: widget.onAction == null || !touch
              ? null
              : (details) =>
                    unawaited(_showContextMenu(details.globalPosition)),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _dragOver ? context.colors.primary : Colors.transparent,
                width: 1.5,
              ),
              color: _dragOver
                  ? context.colors.primary.withValues(alpha: .12)
                  : selected
                  ? context.colors.primaryContainer
                  : Colors.transparent,
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: widget.onTap,
                // The labelled row above already carries the tap action.
                excludeFromSemantics: true,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    3 + widget.depth * 14,
                    touch ? 9 : 6,
                    3,
                    touch ? 9 : 6,
                  ),
                  child: Row(
                    children: <Widget>[
                      chevron,
                      ExcludeSemantics(
                        child: Icon(
                          widget.icon,
                          size: 18,
                          color: selected
                              ? context.colors.primary
                              : context.colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ExcludeSemantics(
                          child: Text(
                            widget.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: foreground,
                            ),
                          ),
                        ),
                      ),
                      if (folder != null) ...<Widget>[
                        const SizedBox(width: 4),
                        ExcludeSemantics(
                          child: Tooltip(
                            message: folder.storage.label,
                            child: Icon(
                              folder.storage == LibraryStorage.drive
                                  ? Icons.cloud_outlined
                                  : Icons.devices_outlined,
                              size: 13,
                              color: context.colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 5),
                      ExcludeSemantics(
                        child: Text(
                          '${widget.count}',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (widget.onAction != null && folder != null)
                        SizedBox(
                          width: 26,
                          height: 24,
                          child: Focus(
                            canRequestFocus: false,
                            skipTraversal: true,
                            onFocusChange: (focused) =>
                                setState(() => _menuFocused = focused),
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 120),
                              opacity: showMenu ? 1 : 0,
                              alwaysIncludeSemantics: true,
                              child: IgnorePointer(
                                ignoring: !showMenu,
                                child: PopupMenuButton<_FolderAction>(
                                  key: ValueKey('folder-menu-${folder.id}'),
                                  tooltip: '${folder.name} options',
                                  padding: EdgeInsets.zero,
                                  iconSize: 17,
                                  onSelected: widget.onAction,
                                  itemBuilder: (_) => _menuItems(),
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        const SizedBox(width: 4),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    row = Padding(padding: const EdgeInsets.only(bottom: 2), child: row);
    if (widget.dropTarget && widget.accepts != null) {
      // Capture the finished row by value: the builder runs later, after
      // `row` has become the DragTarget itself.
      final content = row;
      row = DragTarget<LibraryDragData>(
        onWillAcceptWithDetails: _willAccept,
        onLeave: (_) => _leave(),
        onAcceptWithDetails: (details) {
          _leave();
          widget.onDrop?.call(details.data);
        },
        builder: (context, _, _) => content,
      );
    }
    if (folder != null && widget.draggable) {
      // Fingers long-press a row for its menu, so only a mouse drags one.
      row = LibraryDraggable(
        data: LibraryDragData.forFolder(folder),
        mouseOnly: true,
        child: row,
      );
    }
    return row;
  }
}

/// Picks a new parent for [folder]: the same tree, limited to the folder's
/// storage and without its own branch.
Future<bool> showFolderMoveDialog(
  BuildContext context,
  FolderScope scope,
  LibraryFolder folder,
) async {
  String? parentId = folder.parentId;
  var moving = false;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('Move “${folder.name}”'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Choose where this folder lives. Subfolders and ${scope.noun(2)} move with it.',
                style: TextStyle(color: context.colors.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              _DialogTreeFrame(
                child: FolderTree(
                  scope: scope,
                  showAll: false,
                  unfiledLabel: 'Top level',
                  unfiledIcon: Icons.home_outlined,
                  storage: folder.storage,
                  excludeBranchOf: folder.id,
                  dropTargets: false,
                  rowMenus: false,
                  selectedId: parentId ?? AppController.libraryFolderUnfiled,
                  onSelect: (id) => setState(
                    () => parentId = id == AppController.libraryFolderUnfiled
                        ? null
                        : id,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: moving
                ? null
                : () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            key: const ValueKey('confirm-folder-move'),
            onPressed: moving
                ? null
                : () async {
                    setState(() => moving = true);
                    final moved = await scope.moveFolder(
                      folder,
                      parentId: parentId,
                    );
                    if (dialogContext.mounted && moved) {
                      Navigator.pop(dialogContext, true);
                    } else if (dialogContext.mounted) {
                      setState(() => moving = false);
                    }
                  },
            icon: moving
                ? const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.drive_file_move_outline, size: 18),
            label: const Text('Move'),
          ),
        ],
      ),
    ),
  );
  return result == true;
}

/// Moves the items with [ids] into a folder chosen from the tree, which can
/// also grow a new folder in place. Refuses mixed-storage selections.
Future<bool> showMoveToFolderDialog(
  BuildContext context,
  FolderScope scope,
  Set<String> ids,
) async {
  final storages = scope.storagesOf(ids);
  if (storages.isEmpty) return false;
  if (storages.length != 1) {
    scope.controller.showNotice(
      'Bulk moves require items from the same storage. Filter by Local or Drive, then select again.',
    );
    return false;
  }
  final storage = storages.single;
  final current = scope.foldersOf(ids);
  String? folderId = current.length == 1 ? current.single : null;
  final tree = GlobalKey<FolderTreeState>();
  var moving = false;
  final count = ids.length;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(
          count == 1
              ? 'Move ${scope.noun(1)}'
              : 'Move $count ${scope.noun(count)}',
        ),
        content: SizedBox(
          width: 470,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  StorageBadge(storage: storage),
                  const Spacer(),
                  TextButton.icon(
                    key: const ValueKey('move-dialog-new-folder'),
                    onPressed: moving
                        ? null
                        : () => tree.currentState?.startCreate(
                            parentId: folderId,
                            storage: storage,
                          ),
                    icon: const Icon(
                      Icons.create_new_folder_outlined,
                      size: 18,
                    ),
                    label: const Text('New folder'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Choose a destination',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              _DialogTreeFrame(
                child: FolderTree(
                  key: tree,
                  scope: scope,
                  showAll: false,
                  storage: storage,
                  dropTargets: false,
                  rowMenus: false,
                  selectedId: folderId ?? AppController.libraryFolderUnfiled,
                  onSelect: (id) => setState(
                    () => folderId = id == AppController.libraryFolderUnfiled
                        ? null
                        : id,
                  ),
                  emptyHint:
                      'No folders in this storage yet. New folder adds one right here.',
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: moving
                ? null
                : () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            key: ValueKey(
              scope.isReferences
                  ? 'confirm-reference-move'
                  : 'confirm-generation-move',
            ),
            onPressed: moving
                ? null
                : () async {
                    setState(() => moving = true);
                    final moved = await scope.moveItems(
                      ids,
                      folderId: folderId,
                    );
                    if (dialogContext.mounted && moved) {
                      Navigator.pop(dialogContext, true);
                    } else if (dialogContext.mounted) {
                      setState(() => moving = false);
                    }
                  },
            icon: moving
                ? const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.drive_file_move_outline, size: 18),
            label: const Text('Move'),
          ),
        ],
      ),
    ),
  );
  return result == true;
}

class _DialogTreeFrame extends StatelessWidget {
  const _DialogTreeFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 360),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(7),
        children: <Widget>[child],
      ),
    ),
  );
}

/// Explains exactly what removing [folder] does before doing it: nothing is
/// deleted, direct items go to Unfiled, subfolders move up one level.
Future<void> confirmFolderDelete(
  BuildContext context,
  FolderScope scope,
  LibraryFolder folder,
) async {
  final directCount = scope.directCount(folder.id);
  final childCount = scope.children(folder.id).length;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Remove “${folder.name}”?'),
      content: Text(
        '${directCount == 0 ? 'No ${scope.noun(2)}' : '$directCount ${scope.noun(directCount)}'} directly inside will move to Unfiled. '
        '${childCount == 0 ? 'There are no subfolders.' : '$childCount ${childCount == 1 ? 'subfolder moves' : 'subfolders move'} up one level.'} Nothing will be deleted.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Keep folder'),
        ),
        FilledButton(
          key: const ValueKey('confirm-folder-remove'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Remove folder'),
        ),
      ],
    ),
  );
  if (confirmed == true) await scope.delete(folder);
}
