import 'package:flutter/services.dart';

import 'asset_extensions.dart';
import 'completion_notifications.dart';
import 'models.dart';

/// Hands a staged media file to the platform share sheet.
abstract interface class MediaShareSheet {
  /// Presents the sheet for the file at [path] and reports whether the user
  /// completed an activity — false when the sheet was dismissed or the
  /// platform has no share sheet. [subject] seeds Mail's subject line.
  Future<bool> share({required String path, required String subject});
}

class MethodChannelMediaShareSheet implements MediaShareSheet {
  MethodChannelMediaShareSheet();

  static const MethodChannel _channel = MethodChannel('ai.clawnsole/share');

  bool _unsupported = false;

  @override
  Future<bool> share({required String path, required String subject}) async {
    if (_unsupported) return false;
    try {
      return await _channel.invokeMethod<bool>('share', <String, Object?>{
            'path': path,
            'subject': subject,
          }) ??
          false;
    } on MissingPluginException {
      _unsupported = true;
      return false;
    } on PlatformException catch (error) {
      throw StateError(error.message ?? 'The share sheet could not open.');
    }
  }
}

/// The user-facing file name for a generation's media: the same
/// `clawnsole-<date>-<id>` stem the Save to Files and Save to Photos
/// destinations use, with the retained asset's real extension.
String generationMediaFileName(Generation item) {
  final asset = item.resultAsset;
  final extension = retainedAssetExtension(
    asset?.contentType,
    asset?.label ?? '',
  );
  final date = item.createdAt.toIso8601String().substring(0, 10);
  final id = item.localId.substring(0, item.localId.length.clamp(0, 6));
  final suffix = extension == '.asset'
      ? (item.isImage ? '.png' : '.mp4')
      : extension;
  return 'clawnsole-$date-$id$suffix';
}

/// The subject line offered to Mail and similar share activities.
String generationShareSubject(Generation item) {
  final noun = item.isImage ? 'image' : 'video';
  final excerpt = promptExcerpt(item.prompt, maxLength: 60);
  return excerpt.isEmpty ? 'Clawnsole $noun' : 'Clawnsole $noun: $excerpt';
}
