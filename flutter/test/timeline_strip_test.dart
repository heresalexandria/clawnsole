import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:clawnsole/ui/timeline_strip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final frame = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lE'
    'QVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );

  test(
    'filmstrip releases pictures and decoded images after encoding',
    () async {
      final images = <ui.Image>[];
      final pictures = <ui.Picture>[];
      final previousImage = ui.Image.onCreate;
      final previousPicture = ui.Picture.onCreate;
      ui.Image.onCreate = (image) {
        images.add(image);
        previousImage?.call(image);
      };
      ui.Picture.onCreate = (picture) {
        pictures.add(picture);
        previousPicture?.call(picture);
      };
      try {
        final bytes = await composeTimelineStrip([frame, frame]);
        expect(bytes, isNotEmpty);
        expect(pictures, hasLength(1));
        expect(pictures.single.debugDisposed, isTrue);
        expect(images, hasLength(3));
        expect(images.every((image) => image.debugDisposed), isTrue);
      } finally {
        ui.Image.onCreate = previousImage;
        ui.Picture.onCreate = previousPicture;
      }
    },
  );

  test('failed frame decode releases earlier decoded frames', () async {
    final images = <ui.Image>[];
    final previous = ui.Image.onCreate;
    ui.Image.onCreate = (image) {
      images.add(image);
      previous?.call(image);
    };
    try {
      await expectLater(
        composeTimelineStrip([
          frame,
          Uint8List.fromList([0, 1, 2]),
        ]),
        throwsA(isA<Exception>()),
      );
      expect(images, hasLength(1));
      expect(images.single.debugDisposed, isTrue);
    } finally {
      ui.Image.onCreate = previous;
    }
  });
}
