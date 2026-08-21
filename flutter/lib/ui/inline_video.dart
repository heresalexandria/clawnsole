import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../app/app_controller.dart';
import 'generation_video.dart';
import 'video_frame_loader.dart';

/// Everything a full-view card needs to embed the shared player in place of
/// its preview: the media location plus the same delivery hooks the modal
/// player would have received.
class InlineVideoRequest {
  const InlineVideoRequest({
    required this.uri,
    required this.onDownload,
    this.supportsPhotos = false,
    this.controllerFactory,
    this.frameLoader,
  });

  final Uri uri;
  final Future<void> Function(VideoSaveDestination destination) onDownload;
  final bool supportsPhotos;
  final VideoPlayerController Function(Uri uri)? controllerFactory;
  final VideoFrameLoader? frameLoader;
}

/// Tracks which card's embedded player is active on a screen, so starting
/// playback on one card collapses whichever card was playing before it.
class InlineVideoRegistry extends ValueNotifier<String?> {
  InlineVideoRegistry() : super(null);
}

/// Hands an [InlineVideoRegistry] to every [InlineVideoMediaBox] below it.
/// Each listing surface (Library, Recent work, References) provides its own.
class InlineVideoRegistryScope extends InheritedNotifier<InlineVideoRegistry> {
  const InlineVideoRegistryScope({
    required InlineVideoRegistry registry,
    required super.child,
    super.key,
  }) : super(notifier: registry);

  static InlineVideoRegistry? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<InlineVideoRegistryScope>()
      ?.notifier;
}

/// Lets a video preview hand playback to the full-view card hosting it
/// instead of opening the shared modal. Mini and compact cards have no such
/// ancestor, so they keep the modal (or fullscreen route) behavior.
class InlineVideoPlayback extends InheritedWidget {
  const InlineVideoPlayback({
    required this.onPlay,
    required super.child,
    super.key,
  });

  final ValueChanged<InlineVideoRequest> onPlay;

  /// The playback hand-off for [context], or null when the preview should
  /// keep the modal. Narrow (phone) viewports always return null so the
  /// fullscreen route keeps serving them, matching [showVideoPlayerModal].
  static ValueChanged<InlineVideoRequest>? of(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 700) return null;
    return context.getInheritedWidgetOfExactType<InlineVideoPlayback>()?.onPlay;
  }

  @override
  bool updateShouldNotify(InlineVideoPlayback oldWidget) =>
      onPlay != oldWidget.onPlay;
}

/// A full-view card's media viewport.
///
/// Sizes the preview to the film's stored aspect ratio — fully visible, never
/// cropped to a strip — capping portrait films to a fraction of the viewport
/// height, and swaps in an embedded [GenerationVideo] when the preview asks
/// to play. The viewport stays dark, the design system's documented
/// exception for media surfaces.
class InlineVideoMediaBox extends StatefulWidget {
  const InlineVideoMediaBox({
    required this.playbackId,
    required this.aspectRatio,
    required this.preview,
    super.key,
    this.maxHeightFraction = .7,
  });

  /// Identifies this card in the screen's [InlineVideoRegistry].
  final String playbackId;

  /// The media's stored aspect ratio (width over height). Extreme values are
  /// clamped so unusual ratios still make a usable card.
  final double aspectRatio;

  final Widget preview;

  /// The media box never grows past this fraction of the viewport height, so
  /// a portrait film stays fully visible without a towering card.
  final double maxHeightFraction;

  @override
  State<InlineVideoMediaBox> createState() => _InlineVideoMediaBoxState();
}

class _InlineVideoMediaBoxState extends State<InlineVideoMediaBox> {
  InlineVideoRequest? _request;

  @override
  void didUpdateWidget(covariant InlineVideoMediaBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A reordered listing can hand this element a different film; its
    // player must not carry over.
    if (oldWidget.playbackId != widget.playbackId) _request = null;
  }

  /// Registry lookup for event handlers, which must not register an
  /// inherited-widget dependency the way the build-time lookup does.
  InlineVideoRegistry? _lookupRegistry() => context
      .getInheritedWidgetOfExactType<InlineVideoRegistryScope>()
      ?.notifier;

  void _play(InlineVideoRequest request) {
    setState(() => _request = request);
    _lookupRegistry()?.value = widget.playbackId;
  }

  void _stop() {
    setState(() => _request = null);
    final registry = _lookupRegistry();
    if (registry?.value == widget.playbackId) registry?.value = null;
  }

  @override
  Widget build(BuildContext context) {
    final registry = InlineVideoRegistryScope.of(context);
    if (_request != null &&
        registry != null &&
        registry.value != widget.playbackId) {
      // Another card started playing; this rebuild drops our player.
      _request = null;
    }
    final request = _request;
    final ratio = widget.aspectRatio.clamp(0.4, 2.5);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = math.max(
          180.0,
          MediaQuery.sizeOf(context).height * widget.maxHeightFraction,
        );
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 640.0;
        final mediaHeight = math.min(width / ratio, maxHeight);
        if (request != null) {
          return SizedBox(
            key: ValueKey('inline-video-${widget.playbackId}'),
            height: mediaHeight + GenerationVideo.chromeHeight,
            child: GenerationVideo(
              uri: request.uri,
              onDownload: request.onDownload,
              supportsPhotos: request.supportsPhotos,
              controllerFactory: request.controllerFactory,
              frameLoader: request.frameLoader,
              autoplay: true,
              autofocus: false,
              onClose: _stop,
            ),
          );
        }
        return SizedBox(
          height: mediaHeight,
          child: ColoredBox(
            color: Colors.black,
            child: Center(
              child: AspectRatio(
                aspectRatio: ratio,
                child: InlineVideoPlayback(
                  onPlay: _play,
                  child: widget.preview,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
