import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:video_player/video_player.dart';

import '../app/app_theme.dart';
import '../app/app_controller.dart';
import 'video_controller.dart';
import 'video_frame_loader.dart';
import 'video_frame_timeline.dart';
import 'video_save_sheet.dart';

/// Opens the shared video player for a delivered generation or saved
/// reference.
///
/// Wide viewports get a dialog sized to the video's aspect ratio; narrow
/// (phone) viewports get a fullscreen route. Both players share the same
/// keyboard contract: Space toggles playback, Left/Right seek, and Escape
/// closes the surface it was pressed on.
Future<void> showVideoPlayerModal(
  BuildContext context, {
  Uri? uri,
  Future<Uri?>? deferredUri,
  required Future<void> Function(VideoSaveDestination destination) onDownload,
  bool supportsPhotos = false,
  double initialAspectRatio = 16 / 9,
  VideoPlayerController Function(Uri uri)? controllerFactory,
  VideoFrameLoader? frameLoader,
  ValueListenable<double?>? progress,
}) {
  assert(
    (uri == null) != (deferredUri == null),
    'Provide exactly one of uri or deferredUri.',
  );
  if (MediaQuery.sizeOf(context).width < 700) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (routeContext) => Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: uri != null
                ? GenerationVideo(
                    uri: uri,
                    onDownload: onDownload,
                    fullscreen: true,
                    autoplay: true,
                    onClose: () => Navigator.of(routeContext).pop(),
                    supportsPhotos: supportsPhotos,
                    controllerFactory: controllerFactory,
                    frameLoader: frameLoader,
                    progress: progress,
                  )
                : DeferredGenerationVideo(
                    uri: deferredUri!,
                    onDownload: onDownload,
                    fullscreen: true,
                    autoplay: true,
                    onClose: () => Navigator.of(routeContext).pop(),
                    supportsPhotos: supportsPhotos,
                    controllerFactory: controllerFactory,
                    frameLoader: frameLoader,
                    progress: progress,
                  ),
          ),
        ),
      ),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _VideoPlayerModal(
      uri: uri,
      deferredUri: deferredUri,
      onDownload: onDownload,
      supportsPhotos: supportsPhotos,
      initialAspectRatio: initialAspectRatio,
      controllerFactory: controllerFactory,
      frameLoader: frameLoader,
      progress: progress,
    ),
  );
}

/// Hosts [GenerationVideo] behind a still-resolving delivery, so the player
/// surface appears the moment the viewer taps play and the animated loading
/// placeholder (with byte progress when known) covers a slow retrieval, such
/// as a cold Google Drive download. A null URI reads as delivery being
/// unavailable rather than silently doing nothing.
class DeferredGenerationVideo extends StatelessWidget {
  const DeferredGenerationVideo({
    super.key,
    required this.uri,
    required this.onDownload,
    this.fullscreen = false,
    this.autoplay = false,
    this.autofocus = true,
    this.onClose,
    this.onAspectRatio,
    this.controllerFactory,
    this.frameLoader,
    this.supportsPhotos = false,
    this.progress,
  });

  final Future<Uri?> uri;
  final Future<void> Function(VideoSaveDestination destination) onDownload;
  final bool fullscreen;
  final bool autoplay;
  final bool autofocus;
  final VoidCallback? onClose;
  final ValueChanged<double>? onAspectRatio;
  final VideoPlayerController Function(Uri uri)? controllerFactory;
  final VideoFrameLoader? frameLoader;
  final bool supportsPhotos;
  final ValueListenable<double?>? progress;

  @override
  Widget build(BuildContext context) => FutureBuilder<Uri?>(
    future: uri,
    builder: (context, snapshot) {
      if (snapshot.hasError ||
          (snapshot.connectionState == ConnectionState.done &&
              snapshot.data == null)) {
        return _VideoPlaceholder(
          icon: Icons.link_off_rounded,
          label: 'Delivery unavailable',
          detail:
              'The film could not be retrieved from its storage. '
              'Use Save video to export the file.',
          onClose: onClose,
        );
      }
      final resolved = snapshot.data;
      if (resolved == null) {
        return _VideoLoadingPlaceholder(progress: progress, onClose: onClose);
      }
      return GenerationVideo(
        uri: resolved,
        onDownload: onDownload,
        fullscreen: fullscreen,
        autoplay: autoplay,
        autofocus: autofocus,
        onClose: onClose,
        onAspectRatio: onAspectRatio,
        controllerFactory: controllerFactory,
        frameLoader: frameLoader,
        supportsPhotos: supportsPhotos,
        progress: progress,
      );
    },
  );
}

class _VideoPlayerModal extends StatefulWidget {
  const _VideoPlayerModal({
    required this.uri,
    required this.deferredUri,
    required this.onDownload,
    required this.supportsPhotos,
    required this.initialAspectRatio,
    this.controllerFactory,
    this.frameLoader,
    this.progress,
  }) : assert(
         (uri == null) != (deferredUri == null),
         'Provide exactly one of uri or deferredUri.',
       );

  final Uri? uri;
  final Future<Uri?>? deferredUri;
  final Future<void> Function(VideoSaveDestination destination) onDownload;
  final bool supportsPhotos;
  final double initialAspectRatio;
  final VideoPlayerController Function(Uri uri)? controllerFactory;
  final VideoFrameLoader? frameLoader;
  final ValueListenable<double?>? progress;

  @override
  State<_VideoPlayerModal> createState() => _VideoPlayerModalState();
}

class _VideoPlayerModalState extends State<_VideoPlayerModal> {
  late double _aspect = widget.initialAspectRatio.clamp(0.2, 5.0);

  void _adoptAspect(double value) {
    if ((value - _aspect).abs() > .001 && value > 0) {
      setState(() => _aspect = value.clamp(0.2, 5.0));
    }
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    const chrome = GenerationVideo.chromeHeight;
    final maxWidth = math.min(screen.width - 96, 1080.0);
    final maxVideoHeight = math.max(180.0, screen.height * .86 - chrome);
    final width = math
        .min(maxWidth, maxVideoHeight * _aspect)
        .clamp(380.0, maxWidth);
    return Dialog(
      key: const ValueKey('video-player-modal'),
      backgroundColor: Colors.black,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      insetPadding: const EdgeInsets.all(28),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: SizedBox(
          key: const ValueKey('video-modal-frame'),
          width: width,
          height: math.min(width / _aspect, maxVideoHeight) + chrome,
          child: widget.uri != null
              ? GenerationVideo(
                  uri: widget.uri!,
                  onDownload: widget.onDownload,
                  autoplay: true,
                  onClose: () => Navigator.of(context).pop(),
                  onAspectRatio: _adoptAspect,
                  supportsPhotos: widget.supportsPhotos,
                  controllerFactory: widget.controllerFactory,
                  frameLoader: widget.frameLoader,
                  progress: widget.progress,
                )
              : DeferredGenerationVideo(
                  uri: widget.deferredUri!,
                  onDownload: widget.onDownload,
                  autoplay: true,
                  onClose: () => Navigator.of(context).pop(),
                  onAspectRatio: _adoptAspect,
                  supportsPhotos: widget.supportsPhotos,
                  controllerFactory: widget.controllerFactory,
                  frameLoader: widget.frameLoader,
                  progress: widget.progress,
                ),
        ),
      ),
    );
  }
}

class GenerationVideo extends StatefulWidget {
  const GenerationVideo({
    required this.uri,
    required this.onDownload,
    super.key,
    this.fullscreen = false,
    this.initialPosition = Duration.zero,
    this.autoplay = false,
    this.autofocus = true,
    this.onClose,
    this.onAspectRatio,
    this.controllerFactory,
    this.frameLoader,
    this.supportsPhotos = false,
    this.progress,
  });

  /// Height of the frame timeline plus the transport bar rendered under the
  /// video surface, so hosts can size themselves around a known video height.
  static const double chromeHeight = 46.0 + 48.0;

  final Uri uri;
  final Future<void> Function(VideoSaveDestination destination) onDownload;
  final bool fullscreen;
  final Duration initialPosition;
  final bool autoplay;

  /// Whether the player claims keyboard focus as soon as it appears. Modal
  /// and fullscreen hosts keep the default; players embedded in a card grid
  /// pass false and gain focus when the viewer interacts with them.
  final bool autofocus;

  /// Closes the surface hosting this player (modal dialog or a standalone
  /// fullscreen route). Escape triggers it and a close control is shown.
  final VoidCallback? onClose;

  /// Reports the intrinsic aspect ratio once the video initializes so a
  /// hosting modal can match its size to the film.
  final ValueChanged<double>? onAspectRatio;
  final VideoPlayerController Function(Uri uri)? controllerFactory;
  final VideoFrameLoader? frameLoader;
  final bool supportsPhotos;

  /// Live delivery progress rendered while the film is still loading. A null
  /// fraction (or a null listenable) keeps the loader indeterminate.
  final ValueListenable<double?>? progress;

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
    final aspect = controller.value.aspectRatio;
    if (aspect > 0) widget.onAspectRatio?.call(aspect);
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

  /// Arrow-key seeking steps 5% of the film, kept between one and five
  /// seconds so short clips stay precise and long ones stay quick.
  Duration get _seekStep {
    final duration = _controller.value.duration;
    final step = duration.inMilliseconds ~/ 20;
    return Duration(milliseconds: step.clamp(1000, 5000));
  }

  Future<void> _seekBy(Duration offset) async {
    if (!_controller.value.isInitialized) return;
    final duration = _controller.value.duration;
    if (duration <= Duration.zero) return;
    final target = _clampPosition(
      _controller.value.position + offset,
      duration,
    );
    await _controller.seekTo(target);
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
              progress: widget.progress,
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

  void _handleEscape() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else if (widget.fullscreen) {
      _exitFullscreen();
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!node.hasFocus || event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.space) {
      if (event is KeyDownEvent) unawaited(_togglePlayback());
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      unawaited(_seekBy(-_seekStep));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      unawaited(_seekBy(_seekStep));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape &&
        (widget.fullscreen || widget.onClose != null)) {
      if (event is KeyDownEvent) _handleEscape();
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
        return _VideoPlaceholder(
          icon: Icons.link_off_rounded,
          label: 'Delivery unavailable',
          detail:
              'Playback failed on this device. '
              'Use Save video to export the file.',
          onClose: widget.onClose,
        );
      }
      if (snapshot.connectionState != ConnectionState.done) {
        return _VideoLoadingPlaceholder(
          progress: widget.progress,
          onClose: widget.onClose,
        );
      }

      final value = _controller.value;
      return Focus(
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        onKeyEvent: _handleKeyEvent,
        child: ColoredBox(
          color: Colors.black,
          child: Column(
            children: <Widget>[
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    Center(
                      child: AspectRatio(
                        aspectRatio: value.aspectRatio,
                        child: VideoPlayer(
                          _controller,
                          key: const ValueKey('video-platform-view'),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: PointerInterceptor(
                        key: const ValueKey('video-pointer-interceptor'),
                        // Electron renders Flutter web, whose HTML video
                        // platform view otherwise consumes clicks before
                        // Flutter's gesture system sees them.
                        intercepting: kIsWeb,
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
                                  if (!value.isPlaying)
                                    Center(
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(
                                            alpha: .58,
                                          ),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white38,
                                          ),
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
                                  if (widget.fullscreen &&
                                      widget.onClose != null)
                                    Positioned(
                                      top: 6,
                                      left: 6,
                                      child: IconButton(
                                        key: const ValueKey(
                                          'video-close-overlay',
                                        ),
                                        tooltip: 'Close (Esc)',
                                        color: Colors.white,
                                        style: IconButton.styleFrom(
                                          backgroundColor: Colors.black
                                              .withValues(alpha: .45),
                                        ),
                                        onPressed: widget.onClose,
                                        icon: const Icon(Icons.close_rounded),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
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
                // In a standalone fullscreen player the close control already
                // dismisses the route, so the fullscreen toggle is hidden.
                onFullscreen: widget.fullscreen
                    ? (widget.onClose == null ? _exitFullscreen : null)
                    : () => unawaited(_openFullscreen()),
                onClose: widget.fullscreen ? null : widget.onClose,
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
    this.onClose,
  });

  final VideoPlayerValue value;
  final bool fullscreen;
  final bool saving;
  final VoidCallback onTogglePlayback;
  final VoidCallback onDownload;
  final VoidCallback? onFullscreen;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => Container(
    color: ClawnsoleColors.plumInk,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Row(
      children: <Widget>[
        IconButton(
          tooltip: value.isPlaying ? 'Pause (Space)' : 'Play (Space)',
          color: Colors.white,
          icon: Icon(
            value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          ),
          onPressed: onTogglePlayback,
        ),
        Expanded(
          child: Text(
            '${formatVideoTime(value.position)} / '
            '${formatVideoTime(value.duration)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 10.5),
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
        if (onFullscreen != null)
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
        if (onClose != null)
          IconButton(
            key: const ValueKey('video-close-button'),
            tooltip: 'Close (Esc)',
            color: Colors.white,
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
      ],
    ),
  );
}

/// The loading surface shown while a film is fetched and initialized: a
/// gently flipping hourglass over the plum panel, with a determinate progress
/// bar whenever byte progress is known and a quiet indeterminate sweep
/// otherwise. No spinner, no default blue.
class _VideoLoadingPlaceholder extends StatefulWidget {
  const _VideoLoadingPlaceholder({this.progress, this.onClose});

  final ValueListenable<double?>? progress;
  final VoidCallback? onClose;

  @override
  State<_VideoLoadingPlaceholder> createState() =>
      _VideoLoadingPlaceholderState();
}

class _VideoLoadingPlaceholderState extends State<_VideoLoadingPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flipper = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  // Two half-turns per cycle with a rest between them, like an hourglass
  // being turned over on a desk; each cycle ends upright so the loop never
  // visibly snaps.
  late final Animation<double> _turns = _flipper.drive(
    TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(
          begin: 0,
          end: .5,
        ).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 22,
      ),
      TweenSequenceItem<double>(tween: ConstantTween<double>(.5), weight: 28),
      TweenSequenceItem<double>(
        tween: Tween<double>(
          begin: .5,
          end: 1,
        ).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 22,
      ),
      TweenSequenceItem<double>(tween: ConstantTween<double>(1), weight: 28),
    ]),
  );

  @override
  void dispose() {
    _flipper.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    color: ClawnsoleColors.plumInk,
    child: Stack(
      children: <Widget>[
        Center(
          child: ValueListenableBuilder<double?>(
            valueListenable:
                widget.progress ?? const AlwaysStoppedAnimation<double?>(null),
            builder: (context, fraction, _) {
              // A transfer can reach 100% before the video player finishes
              // opening the file. At that point byte progress no longer
              // describes the remaining work, so return to an indeterminate
              // preparation state instead of displaying a stuck 100%.
              final transferFraction = fraction != null && fraction < 1
                  ? fraction.clamp(0.0, 1.0)
                  : null;
              final preparing = fraction != null && fraction >= 1;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  RotationTransition(
                    turns: _turns,
                    child: const Icon(
                      Icons.hourglass_bottom_rounded,
                      color: ClawnsoleColors.creamMuted,
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    preparing ? 'Preparing film' : 'Loading film',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: 190,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        key: const ValueKey('video-loading-progress'),
                        value: transferFraction,
                        minHeight: 4,
                        backgroundColor: Colors.white12,
                        color: ClawnsoleColors.creamMuted,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 22,
                    child: transferFraction == null
                        ? null
                        : Center(
                            child: Text(
                              '${(transferFraction * 100).round()}%',
                              key: const ValueKey('video-loading-percent'),
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 10,
                                fontFeatures: <FontFeature>[
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                  ),
                ],
              );
            },
          ),
        ),
        if (widget.onClose != null)
          Positioned(
            top: 6,
            right: 6,
            child: IconButton(
              tooltip: 'Close (Esc)',
              color: Colors.white70,
              onPressed: widget.onClose,
              icon: const Icon(Icons.close_rounded),
            ),
          ),
      ],
    ),
  );
}

class _VideoPlaceholder extends StatelessWidget {
  const _VideoPlaceholder({
    required this.icon,
    required this.label,
    this.detail,
    this.onClose,
  });

  final IconData icon;
  final String label;
  final String? detail;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => Container(
    color: ClawnsoleColors.plumInk,
    child: Stack(
      children: <Widget>[
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, color: ClawnsoleColors.creamMuted, size: 30),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
              if (detail != null) ...<Widget>[
                const SizedBox(height: 5),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    detail!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 10.5,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (onClose != null)
          Positioned(
            top: 6,
            right: 6,
            child: IconButton(
              tooltip: 'Close (Esc)',
              color: Colors.white70,
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded),
            ),
          ),
      ],
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
