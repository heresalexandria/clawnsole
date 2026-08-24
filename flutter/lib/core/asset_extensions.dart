/// A human-readable notice for a retained asset whose file is gone from disk.
/// Raw paths and exception details belong in logs, not in this message.
String missingLocalAssetMessage(String? contentType) {
  final normalized = contentType?.split(';').first.trim().toLowerCase() ?? '';
  final noun = normalized.startsWith('video/')
      ? 'video'
      : normalized.startsWith('image/')
      ? 'image'
      : normalized.startsWith('audio/')
      ? 'audio'
      : 'media';
  return "The saved $noun file is missing from this device's library storage. "
      'Check the library storage settings and your Google Drive connection.';
}

String retainedAssetExtension(String? contentType, String label) {
  final normalized = contentType?.split(';').first.trim().toLowerCase();
  return switch (normalized) {
    'video/mp4' => '.mp4',
    'video/quicktime' => '.mov',
    'video/webm' => '.webm',
    'image/png' => '.png',
    'image/jpeg' => '.jpg',
    'image/webp' => '.webp',
    'image/gif' => '.gif',
    'audio/mpeg' => '.mp3',
    'audio/mp4' => '.m4a',
    'audio/wav' || 'audio/x-wav' => '.wav',
    'audio/ogg' => '.ogg',
    _ => switch (label.toLowerCase()) {
      final value when value.endsWith('.mp4') => '.mp4',
      final value when value.endsWith('.mov') => '.mov',
      final value when value.endsWith('.webm') => '.webm',
      final value when value.endsWith('.png') => '.png',
      final value when value.endsWith('.jpg') || value.endsWith('.jpeg') =>
        '.jpg',
      final value when value.endsWith('.webp') => '.webp',
      final value when value.endsWith('.gif') => '.gif',
      final value when value.endsWith('.mp3') => '.mp3',
      final value when value.endsWith('.m4a') => '.m4a',
      final value when value.endsWith('.wav') => '.wav',
      final value when value.endsWith('.ogg') => '.ogg',
      _ => '.asset',
    },
  };
}

bool isRetainedVideoAsset(String? contentType, String label) => const <String>{
  '.mp4',
  '.mov',
  '.webm',
}.contains(retainedAssetExtension(contentType, label));
