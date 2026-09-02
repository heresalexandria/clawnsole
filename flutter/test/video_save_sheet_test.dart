import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/ui/video_save_sheet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A phone-sized surface: the default 800x600 test window caps a modal bottom
/// sheet below the three destinations' natural height, so the sheet scrolls
/// and the last row would sit off screen.
Future<void> _usePhoneSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Widget _harness({
  required List<VideoSaveDestination?> results,
  Future<void> Function()? onShare,
}) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          results.add(
            await chooseVideoSaveDestination(
              context,
              supportsPhotos: true,
              onShare: onShare,
            ),
          );
        },
        child: const Text('open'),
      ),
    ),
  ),
);

void main() {
  testWidgets('iOS offers Share… after the save destinations', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await _usePhoneSurface(tester);
      final results = <VideoSaveDestination?>[];
      var shared = 0;
      await tester.pumpWidget(
        _harness(results: results, onShare: () async => shared += 1),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Save to Photos'), findsOneWidget);
      expect(find.text('Save to Files'), findsOneWidget);
      expect(find.text('Share…'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Share…')).dy,
        greaterThan(tester.getTopLeft(find.text('Save to Files')).dy),
      );

      await tester.tap(find.text('Share…'));
      await tester.pumpAndSettle();

      expect(shared, 1);
      expect(results, <VideoSaveDestination?>[
        null,
      ], reason: 'sharing chooses no save destination');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Share… needs a callback', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await _usePhoneSurface(tester);
      final results = <VideoSaveDestination?>[];
      await tester.pumpWidget(_harness(results: results));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Share…'), findsNothing);

      await tester.tap(find.text('Save to Files'));
      await tester.pumpAndSettle();
      expect(results, <VideoSaveDestination?>[VideoSaveDestination.files]);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Share… stays off other platforms', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await _usePhoneSurface(tester);
      final results = <VideoSaveDestination?>[];
      await tester.pumpWidget(_harness(results: results, onShare: () async {}));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Share…'), findsNothing);

      await tester.tap(find.text('Save to Photos'));
      await tester.pumpAndSettle();
      expect(results, <VideoSaveDestination?>[VideoSaveDestination.photos]);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
