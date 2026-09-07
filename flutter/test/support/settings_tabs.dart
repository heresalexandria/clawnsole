import 'package:clawnsole/core/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Brings one Settings desk to the front.
///
/// Settings is a tabbed screen, so a test that wants a card outside the
/// General desk taps its way there first. The rail scrolls horizontally on a
/// phone, so the tab is dragged into view before it is tapped.
Future<void> openSettingsTab(WidgetTester tester, SettingsTab tab) async {
  final key = find.byKey(ValueKey<String>(tab.tabKey));
  expect(
    key,
    findsOneWidget,
    reason: 'the ${tab.label} desk is missing from the Settings rail',
  );
  await tester.ensureVisible(key);
  await tester.pumpAndSettle();
  await tester.tap(key);
  await tester.pumpAndSettle();
}
