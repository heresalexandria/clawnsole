import 'dart:typed_data';
import 'dart:ui' as ui;

/// Builds the small persisted filmstrip and releases every native decode and
/// drawing resource, including when a frame or the final PNG cannot be read.
Future<Uint8List?> composeTimelineStrip(List<Uint8List> frames) async {
  if (frames.isEmpty) return null;
  final images = <ui.Image>[];
  final recorder = ui.PictureRecorder();
  ui.Picture? picture;
  ui.Image? strip;
  try {
    for (final bytes in frames) {
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        images.add((await codec.getNextFrame()).image);
      } finally {
        codec.dispose();
      }
    }
    const cellWidth = 160.0;
    const height = 90.0;
    final canvas = ui.Canvas(recorder);
    for (var index = 0; index < images.length; index += 1) {
      final image = images[index];
      final sourceAspect = image.width / image.height;
      final targetAspect = cellWidth / height;
      final source = sourceAspect > targetAspect
          ? ui.Rect.fromLTWH(
              (image.width - image.height * targetAspect) / 2,
              0,
              image.height * targetAspect,
              image.height.toDouble(),
            )
          : ui.Rect.fromLTWH(
              0,
              (image.height - image.width / targetAspect) / 2,
              image.width.toDouble(),
              image.width / targetAspect,
            );
      canvas.drawImageRect(
        image,
        source,
        ui.Rect.fromLTWH(index * cellWidth, 0, cellWidth, height),
        ui.Paint(),
      );
    }
    picture = recorder.endRecording();
    strip = await picture.toImage(
      (cellWidth * images.length).round(),
      height.round(),
    );
    final data = await strip.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } finally {
    strip?.dispose();
    picture?.dispose();
    if (recorder.isRecording) recorder.endRecording().dispose();
    for (final image in images) {
      image.dispose();
    }
  }
}
