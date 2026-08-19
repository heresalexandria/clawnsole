@TestOn('browser')
library;

import 'package:clawnsole/app/text_context_menu.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.contextMenu,
          (_) => Future<void>.value(),
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') {
            return <String, Object>{'text': 'pasted by context menu'};
          }
          return null;
        });
    await configureTextContextMenus();
  });
  tearDownAll(() async {
    await BrowserContextMenu.enableContextMenu();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.contextMenu, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('right click shows Flutter paste controls on web', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TextField(controller: controller)),
      ),
    );

    final field = find.byType(TextField);
    await tester.tap(field, kind: PointerDeviceKind.mouse);
    await tester.tapAt(
      tester.getCenter(field),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(BrowserContextMenu.enabled, isFalse);
    expect(find.text('Paste'), findsOneWidget);
    await tester.tap(find.text('Paste'), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(controller.text, 'pasted by context menu');
  });
}
