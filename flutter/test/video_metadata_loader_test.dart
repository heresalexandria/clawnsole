import 'dart:convert';
import 'dart:typed_data';

import 'package:clawnsole/ui/video_metadata_loader_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MP4 fallback reads source dimensions and duration', () {
    final movieHeader = Uint8List(20);
    ByteData.sublistView(movieHeader)
      ..setUint32(12, 1000)
      ..setUint32(16, 12500);

    final trackHeader = Uint8List(84);
    ByteData.sublistView(trackHeader)
      ..setUint32(76, 1920 << 16)
      ..setUint32(80, 1080 << 16);

    final mediaHeader = Uint8List(20);
    ByteData.sublistView(mediaHeader)
      ..setUint32(12, 48000)
      ..setUint32(16, 600000);

    final bytes = _box('moov', <int>[
      ..._box('mvhd', movieHeader),
      ..._box('trak', <int>[
        ..._box('tkhd', trackHeader),
        ..._box('mdia', <int>[..._box('mdhd', mediaHeader)]),
      ]),
    ]);

    final metadata = parseMp4Metadata(bytes);

    expect(metadata?.width, 1920);
    expect(metadata?.height, 1080);
    expect(metadata?.durationSeconds, 12.5);
  });

  test('MP4 fallback rejects a source without usable video metadata', () {
    expect(parseMp4Metadata(_box('moov', const <int>[])), isNull);
    expect(parseMp4Metadata(Uint8List(0)), isNull);
  });
}

Uint8List _box(String type, List<int> payload) {
  final bytes = Uint8List(8 + payload.length);
  ByteData.sublistView(bytes).setUint32(0, bytes.length);
  bytes
    ..setRange(4, 8, ascii.encode(type))
    ..setRange(8, bytes.length, payload);
  return bytes;
}
