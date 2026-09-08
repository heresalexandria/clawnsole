import 'package:flutter/material.dart';
import 'package:video_player_media_kit/video_player_media_kit.dart';

import 'app/clawnsole_app.dart';
import 'app/renderer_diagnostics.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Keep initialization and runApp in the same zone. Error reporting observes
  // the existing handlers without swallowing failures or resetting state.
  final diagnostics = RendererDiagnostics()..install();
  // Windows exception: video_player has no first-party Windows backend, and
  // video_player_win renders through a Media Foundation shared-handle texture
  // that silently shows black frames (with working audio) on some machines.
  // media_kit's renderer falls back to software rendering when GPU surface
  // sharing fails, so Windows registers it as the video_player implementation
  // while every other platform keeps its native backend.
  VideoPlayerMediaKit.ensureInitialized(windows: true);
  runApp(
    RendererDiagnosticsScope(
      diagnostics: diagnostics,
      child: const ClawnsoleApp(),
    ),
  );
}
