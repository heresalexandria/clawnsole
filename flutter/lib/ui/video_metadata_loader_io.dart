import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/models.dart';
import 'video_controller.dart';

Future<VideoSourceMetadata?> loadVideoMetadata(Uri uri) async {
  // Windows registers media_kit as its video_player backend (main.dart), so
  // the player probe works there too. Only Linux has no backend; it goes
  // straight to the MP4 box parse. Without the probe, any video over the
  // parse's size cap would dead-end into an unreadable duration.
  if (!Platform.isLinux) {
    final playerMetadata = await _loadWithVideoPlayer(uri);
    if (playerMetadata != null) return playerMetadata;
  }
  try {
    return parseMp4Metadata(await _readMp4Bytes(uri));
  } on Object {
    return null;
  }
}

Future<VideoSourceMetadata?> _loadWithVideoPlayer(Uri uri) async {
  final controller = createVideoController(uri);
  try {
    await controller.initialize().timeout(const Duration(seconds: 15));
    final value = controller.value;
    final metadata = VideoSourceMetadata(
      width: value.size.width.round(),
      height: value.size.height.round(),
      durationSeconds:
          value.duration.inMicroseconds / Duration.microsecondsPerSecond,
    );
    return metadata.isUsable ? metadata : null;
  } on Object {
    return null;
  } finally {
    await controller.dispose();
  }
}

const _maximumSourceBytes = 50 * 1024 * 1024;

Future<Uint8List> _readMp4Bytes(Uri uri) async {
  if (uri.scheme == 'file') {
    final file = File(uri.toFilePath());
    if (await file.length() > _maximumSourceBytes) {
      throw const FormatException('Video exceeds the metadata read limit.');
    }
    return file.readAsBytes();
  }
  if (uri.scheme == 'data') {
    final bytes = uri.data?.contentAsBytes();
    if (bytes == null || bytes.length > _maximumSourceBytes) {
      throw const FormatException('Invalid video data URI.');
    }
    return bytes;
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    throw const FormatException('Unsupported video URI.');
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client
        .getUrl(uri)
        .timeout(const Duration(seconds: 12));
    final response = await request.close().timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Video metadata request failed with HTTP ${response.statusCode}.',
        uri: uri,
      );
    }
    if (response.contentLength > _maximumSourceBytes) {
      throw const FormatException('Video exceeds the metadata read limit.');
    }
    final builder = BytesBuilder(copy: false);
    var total = 0;
    await for (final chunk in response.timeout(const Duration(seconds: 20))) {
      total += chunk.length;
      if (total > _maximumSourceBytes) {
        throw const FormatException('Video exceeds the metadata read limit.');
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  } finally {
    client.close(force: true);
  }
}

VideoSourceMetadata? parseMp4Metadata(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final moov = _boxes(
    bytes,
    data,
    0,
    bytes.length,
  ).where((box) => box.type == 'moov').firstOrNull;
  if (moov == null) return null;

  var durationSeconds = 0.0;
  final movieHeader = _boxes(
    bytes,
    data,
    moov.payloadStart,
    moov.end,
  ).where((box) => box.type == 'mvhd').firstOrNull;
  if (movieHeader != null) {
    durationSeconds = _mediaDuration(data, movieHeader);
  }

  var width = 0;
  var height = 0;
  var trackDuration = 0.0;
  for (final track in _boxes(
    bytes,
    data,
    moov.payloadStart,
    moov.end,
  ).where((box) => box.type == 'trak')) {
    final trackHeader = _boxes(
      bytes,
      data,
      track.payloadStart,
      track.end,
    ).where((box) => box.type == 'tkhd').firstOrNull;
    if (trackHeader == null) continue;
    final dimensions = _trackDimensions(data, trackHeader);
    if (dimensions.width * dimensions.height <= width * height) continue;
    width = dimensions.width;
    height = dimensions.height;

    final media = _boxes(
      bytes,
      data,
      track.payloadStart,
      track.end,
    ).where((box) => box.type == 'mdia').firstOrNull;
    final mediaHeader = media == null
        ? null
        : _boxes(
            bytes,
            data,
            media.payloadStart,
            media.end,
          ).where((box) => box.type == 'mdhd').firstOrNull;
    trackDuration = mediaHeader == null ? 0 : _mediaDuration(data, mediaHeader);
  }

  final metadata = VideoSourceMetadata(
    width: width,
    height: height,
    durationSeconds: durationSeconds > 0 ? durationSeconds : trackDuration,
  );
  return metadata.isUsable ? metadata : null;
}

Iterable<_Mp4Box> _boxes(
  Uint8List bytes,
  ByteData data,
  int start,
  int end,
) sync* {
  var cursor = start;
  while (cursor + 8 <= end) {
    var size = data.getUint32(cursor);
    final type = ascii.decode(bytes.sublist(cursor + 4, cursor + 8));
    var headerSize = 8;
    if (size == 1) {
      if (cursor + 16 > end) return;
      size = data.getUint64(cursor + 8);
      headerSize = 16;
    } else if (size == 0) {
      size = end - cursor;
    }
    if (size < headerSize || cursor + size > end) return;
    yield _Mp4Box(type, cursor + headerSize, cursor + size);
    cursor += size;
  }
}

double _mediaDuration(ByteData data, _Mp4Box box) {
  if (box.payloadStart + 20 > box.end) return 0;
  final version = data.getUint8(box.payloadStart);
  final timescaleOffset = box.payloadStart + (version == 1 ? 20 : 12);
  final durationOffset = box.payloadStart + (version == 1 ? 24 : 16);
  final requiredBytes = version == 1 ? 8 : 4;
  if (durationOffset + requiredBytes > box.end) return 0;
  final timescale = data.getUint32(timescaleOffset);
  if (timescale == 0) return 0;
  final duration = version == 1
      ? data.getUint64(durationOffset)
      : data.getUint32(durationOffset);
  return duration / timescale;
}

({int width, int height}) _trackDimensions(ByteData data, _Mp4Box box) {
  if (box.payloadStart + 84 > box.end) return (width: 0, height: 0);
  final version = data.getUint8(box.payloadStart);
  final widthOffset = box.payloadStart + (version == 1 ? 88 : 76);
  if (widthOffset + 8 > box.end) return (width: 0, height: 0);
  return (
    width: (data.getUint32(widthOffset) / 65536).round(),
    height: (data.getUint32(widthOffset + 4) / 65536).round(),
  );
}

class _Mp4Box {
  const _Mp4Box(this.type, this.payloadStart, this.end);

  final String type;
  final int payloadStart;
  final int end;
}
