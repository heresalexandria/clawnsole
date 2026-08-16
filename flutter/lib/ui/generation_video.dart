import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../app/app_theme.dart';
import '../app/app_controller.dart';
import 'video_controller.dart';
import 'video_frame_loader.dart';
import 'video_frame_timeline.dart';
import 'video_save_sheet.dart';

class GenerationVideo extends StatefulWidget {
  const GenerationVideo({
    required this.uri,
    required this.onDownload,
    super.key,
    this.fullscreen = false,
    this.initialPosition = Duration.zero,
    this.autoplay = false,
    this.controllerFactory,
    this.frameLoader,
    this.supportsPhotos = false,
  });

  final Uri uri;
  final Future<void> Function(VideoSaveDestination destination) onDownload;
  final bool fullscreen;
  final Duration initialPosition;
  final bool autoplay;
  final VideoPlayerController Function(Uri uri)? controllerFactory;
  final VideoFrameLoader? frameLoader;
  final bool supportsPhotos;

  @override
  State<GenerationVideo> createState() => _GenerationVideoState();
}

class _GenerationVideoState extends State<GenerationVideo> {
  late VideoPlayerController _controller;
  late Future<void> _initializing;
  final FocusNode _focusNode = FocusNode(debugLabel: 'Clawnsole video');
  bool _saving = false;

  VideoPlayerController _newController() =>
      widget.controllerFactory?.call(widget.uri) ??
      createVideoController(widget.uri);

  @override
  void initState() {
    super.initState();
    _createController();
  }

  @override
  void didUpdateWidget(covariant GenerationVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri) {
      _controller.removeListener(_refresh);
      unawaited(_controller.dispose());
      _createController();
    }
  }

  void _createController() {
    _controller = _newController()..addListener(_refresh);
    _initializing = _initializeController(_controller);
  }

  Future<void> _initializeController(VideoPlayerController controller) async {
    await controller.initialize();
    if (!mounted || !identical(controller, _controller)) return;
    final position = _clampPosition(
      widget.initialPosition,
      controller.value.duration,
    );
    if (position > Duration.zero) await controller.seekTo(position);
    if (widget.autoplay) await controller.play();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _togglePlayback() async {
    if (!_controller.value.isInitialized) return;
    _focusNode.requestFocus();
    if (_controller.value.isPlaying) {
      await _controller.pause();
    } else {
      await _controller.play();
    }
  }

  Future<void> _seek(double fraction) async {
    if (!_controller.value.isInitialized) return;
    _focusNode.requestFocus();
    final clamped = fraction.clamp(0.0, 1.0);
    final position = Duration(
      microseconds: (_controller.value.duration.inMicroseconds * clamped)
          .round(),
    );
    await _controller.seekTo(position);
  }

  Future<void> _download() async {
    if (_saving) return;
    final destination = await chooseVideoSaveDestination(
      context,
      supportsPhotos: widget.supportsPhotos,
    );
    if (destination == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.onDownload(destination);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openFullscreen() async {
    final wasPlaying = _controller.value.isPlaying;
    final position = _controller.value.position;
    await _controller.pause();
    if (!mounted) return;
    final result = await Navigator.of(context).push<_VideoPlaybackSnapshot>(
      MaterialPageRoute<_VideoPlaybackSnapshot>(
        fullscreenDialog: true,
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: GenerationVideo(
              uri: widget.uri,
              onDownload: widget.onDownload,
              fullscreen: true,
              initialPosition: position,
              autoplay: wasPlaying,
              controllerFactory: widget.controllerFactory,
              frameLoader: widget.frameLoader,
              supportsPhotos: widget.supportsPhotos,
            ),
          ),
        ),
      ),
    );
    if (!mounted || result == null) return;
    await _controller.seekTo(
      _clampPosition(result.position, _controller.value.duration),
    );
    if (result.wasPlaying) await _controller.play();
    _focusNode.requestFocus();
  }

  void _exitFullscreen() {
    Navigator.of(context).pop(
      _VideoPlaybackSnapshot(
        position: _controller.value.position,
        wasPlaying: _controller.value.isPlaying,
      ),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!node.hasFocus || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.space) {
      unawaited(_togglePlayback());
      return KeyEventResult.handled;
    }
    if (widget.fullscreen && event.logicalKey == LogicalKeyboardKey.escape) {
      _exitFullscreen();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _initializing,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const _VideoPlaceholder(
          icon: Icons.link_off_rounded,
          label: 'Delivery unavailable',
        );
      }
      if (snapshot.connectionState != ConnectionState.done) {
        return const _VideoPlaceholder(
          icon: Icons.hourglass_bottom_rounded,
          label: 'Loading film',
        );
      }

      final value = _controller.value;
      return Focus(
        focusNode: _focusNode,
        autofocus: widget.fullscreen,
        onKeyEvent: _handleKeyEvent,
        child: ColoredBox(
          color: Colors.black,
          child: Column(
            children: <Widget>[
              Expanded(
                child: Semantics(
                  button: true,
                  label: value.isPlaying ? 'Pause video' : 'Play video',
                  onTap: () => unawaited(_togglePlayback()),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      key: const ValueKey('video-play-surface'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => unawaited(_togglePlayback()),
                      child: Stack(
                        fit: StackFit.expand,
                        children: <Widget>[
                          Center(
                            child: AspectRatio(
                              aspectRatio: value.aspectRatio,
                              child: VideoPlayer(_controller),
                            ),
                          ),
                          if (!value.isPlaying)
                            Center(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: .58),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white38),
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.all(11),
                                  child: Icon(
                                    Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 30,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              VideoFrameTimeline(
                key: ValueKey<String>('video-timeline-${widget.uri}'),
                uri: widget.uri,
                duration: value.duration,
                position: value.position,
                fullscreen: widget.fullscreen,
                frameLoader: widget.frameLoader ?? loadVideoFrame,
                onSeek: (fraction) => unawaited(_seek(fraction)),
                onInteract: _focusNode.requestFocus,
              ),
              _VideoControls(
                value: value,
                fullscreen: widget.fullscreen,
                saving: _saving,
                onTogglePlayback: () => unawaited(_togglePlayback()),
                onDownload: () => unawaited(_download()),
                onFullscreen: widget.fullscreen
                    ? _exitFullscreen
                    : () => unawaited(_openFullscreen()),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _VideoControls extends StatelessWidget {
  const _VideoControls({
    required this.value,
    required this.fullscreen,
    required this.saving,
    required this.onTogglePlayback,
    required this.onDownload,
    required this.onFullscreen,
  });

  final VideoPlayerValue value;
  final bool fullscreen;
  final bool saving;
  final VoidCallback onTogglePlayback;
  final VoidCallback onDownload;
  final VoidCallback onFullscreen;

  @override
  Widget build(BuildContext context) => Container(
    color: ClawnsoleColors.rail,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Row(
      children: <Widget>[
        IconButton(
          tooltip: value.isPlaying
              ? 'Pause video (Space)'
              : 'Play video (Space)',
          color: Colors.white,
          icon: Icon(
            value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          ),
          onPressed: onTogglePlayback,
        ),
        Expanded(
          child: Text(
            '${formatVideoTime(value.position)} / '
            '${formatVideoTime(value.duration)} · Space to play or pause',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
        ),
        IconButton(
          tooltip: 'Download video…',
          color: Colors.white,
          onPressed: saving ? null : onDownload,
          icon: saving
              ? const SizedBox.square(
                  dimension: 17,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.download_rounded),
        ),
        IconButton(
          tooltip: fullscreen ? 'Exit fullscreen (Esc)' : 'Enter fullscreen',
          color: Colors.white,
          onPressed: onFullscreen,
          icon: Icon(
            fullscreen
                ? Icons.fullscreen_exit_rounded
                : Icons.fullscreen_rounded,
          ),
        ),
      ],
    ),
  );
}

class _VideoPlaceholder extends StatelessWidget {
  const _VideoPlaceholder({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    color: ClawnsoleColors.rail,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: ClawnsoleColors.railMuted, size: 30),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    ),
  );
}

Duration _clampPosition(Duration position, Duration duration) {
  if (position < Duration.zero) return Duration.zero;
  if (position > duration) return duration;
  return position;
}

class _VideoPlaybackSnapshot {
  const _VideoPlaybackSnapshot({
    required this.position,
    required this.wasPlaying,
  });

  final Duration position;
  final bool wasPlaying;
}
