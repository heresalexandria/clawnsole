import '../core/models.dart';
import 'video_metadata_loader_io.dart'
    if (dart.library.html) 'video_metadata_loader_web.dart'
    as platform;

typedef VideoMetadataLoader = Future<VideoSourceMetadata?> Function(Uri uri);

Future<VideoSourceMetadata?> loadVideoMetadata(Uri uri) =>
    platform.loadVideoMetadata(uri);
