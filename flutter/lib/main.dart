import 'package:flutter/material.dart';
import 'package:video_player_media_kit/video_player_media_kit.dart';

import 'app/clawnsole_app.dart';
import 'app/renderer_diagnostics.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Keep initialization and runApp in the same zone. Error reporting observes
  // the existing handlers without swallowing failures or resetting state.
  final diagnostics = RendererDiagnostics()..install();
  // video_player has no first-party Windows or Linux backend, and
  // video_player_win renders through a Media Foundation shared-handle texture
  // that silently shows black frames (with working audio) on some machines.
  // media_kit's renderer falls back to software rendering when GPU surface
  // sharing fails. Linux uses the distribution's libmpv through the same
  // adapter; mobile and the internal web renderer keep their native backends.
  VideoPlayerMediaKit.ensureInitialized(windows: true, linux: true);
  runApp(
    RendererDiagnosticsScope(
      diagnostics: diagnostics,
      child: const ClawnsoleApp(),
    ),
  );
}
