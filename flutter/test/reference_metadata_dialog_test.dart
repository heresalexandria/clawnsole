import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/ui/references_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

class _MetadataGateway implements AppGateway, ReferenceLibraryGateway {
  _MetadataGateway(this.snapshot);
  LocalSnapshot snapshot;
  @override
  bool get usesCompanion => false;
  @override
  bool get supportsPhotoLibrarySave => false;
  @override
  String get persistenceDescription => 'Memory';
  @override
  Future<LocalSnapshot> saveReference(
    SavedReference reference, {
    String? source,
  }) async => snapshot = snapshot.copyWith(savedReferences: [reference]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final action in ['Update', 'Cancel']) {
    testWidgets('reference metadata $action releases editors after dismissal', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final reference = SavedReference(
        id: 'photo',
        name: 'IMG_1234.png',
        kind: MediaReferenceKind.image,
        asset: const AssetReference(
          kind: 'local',
          value: 'photo',
          label: 'IMG_1234.png',
        ),
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final gateway = _MetadataGateway(
        LocalSnapshot(
          generations: const [],
          preferences: const AppPreferences(),
          hasApiKey: false,
          storage: const StorageStats(path: 'memory', bytes: 0, records: 0),
          savedReferences: [reference],
        ),
      );
      final controller = AppController(gateway: gateway)
        ..snapshot = gateway.snapshot;
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildClawnsoleTheme(
            Brightness.light,
          ).copyWith(platform: TargetPlatform.iOS),
          home: Scaffold(
            body: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => TextButton(
                onPressed: () => showReferenceMetadataDialog(
                  context,
                  controller,
                  reference: controller.savedReferences.single,
                ),
                child: const Text('Edit details'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Edit details'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == 'Name',
        ),
        'Alice.png',
      );
      await tester.enterText(
        find.byKey(const ValueKey('reference-character-name')),
        'ALICE',
      );
      await tester.tap(find.text(action));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      expect(find.text('Edit reference'), findsNothing);
      expect(tester.takeException(), isNull);
      if (action == 'Update') {
        expect(controller.savedReferences.single.name, 'Alice.png');
        expect(controller.savedReferences.single.characterName, 'ALICE');
        // Let the successful-update notice finish before teardown.
        await tester.pump(const Duration(seconds: 5));
      }
    });
  }
  for (final action in ['Save', 'Cancel']) {
    testWidgets('character assignment $action owns its editor until unmount', (
      tester,
    ) async {
      timeDilation = 5;
      addTearDown(() => timeDilation = 1);
      const draft = MediaReferenceDraft(
        id: 'photo',
        label: 'Alice.png',
        kind: MediaReferenceKind.image,
        source: 'https://example.invalid/Alice.png',
      );
      final gateway = _MetadataGateway(
        const LocalSnapshot(
          generations: [],
          preferences: AppPreferences(),
          hasApiKey: false,
          storage: StorageStats(path: 'memory', bytes: 0, records: 0),
        ),
      );
      final controller = AppController(gateway: gateway)
        ..snapshot = gateway.snapshot
        ..form.references = [draft];
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildClawnsoleTheme(Brightness.light),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showCharacterAssignmentDialog(context, controller, draft),
                child: const Text('Cast photo'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Cast photo'));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('character-name-field'));
      await tester.enterText(field, 'ALICE');
      await tester.tap(find.text(action));
      await tester.pump();
      // A slow closing animation keeps the field mounted beyond the old fixed
      // disposal delay. It still needs a usable controller until unmount.
      await tester.pump(const Duration(milliseconds: 300));
      expect(field, findsOneWidget);
      final editor = tester.widget<TextField>(field).controller!;
      void listener() {}
      expect(() => editor.addListener(listener), returnsNormally);
      editor.removeListener(listener);
      await tester.pumpAndSettle();
      timeDilation = 1;
      expect(field, findsNothing);
      expect(tester.takeException(), isNull);
      expect(
        controller.characterNameForDraft(draft),
        action == 'Save' ? 'ALICE' : '',
      );
    });
  }
}
