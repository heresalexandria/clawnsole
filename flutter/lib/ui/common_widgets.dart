import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import '../core/models.dart';
import 'formatters.dart';
import 'video_controller.dart';

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      if (icon != null) ...<Widget>[
        Icon(icon, size: 14, color: ClawnsoleColors.clay),
        const SizedBox(width: 7),
      ],
      Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: ClawnsoleColors.clayDark,
          fontSize: 10,
          letterSpacing: 1.6,
          fontWeight: FontWeight.w900,
        ),
      ),
    ],
  );
}

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(18),
    this.color = ClawnsoleColors.paper,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: ClawnsoleColors.line),
      boxShadow: const <BoxShadow>[
        BoxShadow(
          color: Color(0x0A20241F),
          blurRadius: 16,
          offset: Offset(0, 5),
        ),
      ],
    ),
    child: child,
  );
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({required this.item, super.key});

  final Generation item;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, label) = item.isWorking
        ? (const Color(0xFFE9D8A6), const Color(0xFF614B13), 'In progress')
        : item.isFailed
        ? (const Color(0xFFF6DCD5), ClawnsoleColors.danger, 'Needs attention')
        : (const Color(0xFFDCE9DE), ClawnsoleColors.forest, 'Ready');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (item.isWorking) ...<Widget>[
            SizedBox.square(
              dimension: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: foreground,
              ),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              color: foreground,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class GenerationVideo extends StatefulWidget {
  const GenerationVideo({required this.uri, super.key});

  final Uri uri;

  @override
  State<GenerationVideo> createState() => _GenerationVideoState();
}

class GenerationMedia extends StatefulWidget {
  const GenerationMedia({
    required this.controller,
    required this.item,
    super.key,
  });

  final AppController controller;
  final Generation item;

  @override
  State<GenerationMedia> createState() => _GenerationMediaState();
}

class _GenerationMediaState extends State<GenerationMedia> {
  late Future<Uri?> _uri;

  @override
  void initState() {
    super.initState();
    _uri = widget.controller.generationMediaUri(widget.item);
  }

  @override
  void didUpdateWidget(covariant GenerationMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.resultUrl != widget.item.resultUrl ||
        oldWidget.item.resultAsset?.value != widget.item.resultAsset?.value) {
      _uri = widget.controller.generationMediaUri(widget.item);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uri?>(
    future: _uri,
    builder: (context, snapshot) {
      if (snapshot.hasError ||
          (snapshot.connectionState == ConnectionState.done &&
              snapshot.data == null)) {
        return const _MediaPlaceholder(
          icon: Icons.link_off_rounded,
          label: 'Video unavailable',
        );
      }
      if (!snapshot.hasData) {
        return const _MediaPlaceholder(
          icon: Icons.hourglass_bottom_rounded,
          label: 'Loading film',
        );
      }
      return GenerationVideo(uri: snapshot.data!);
    },
  );
}

class GenerationInputPreview extends StatefulWidget {
  const GenerationInputPreview({
    required this.controller,
    required this.item,
    super.key,
  });

  final AppController controller;
  final Generation item;

  @override
  State<GenerationInputPreview> createState() => _GenerationInputPreviewState();
}

class _GenerationInputPreviewState extends State<GenerationInputPreview> {
  late AssetReference? _reference;
  Future<Uint8List>? _bytes;

  AssetReference? _findReference() {
    for (final frame
        in widget.item.config.keyframes ?? const <KeyframeLabel>[]) {
      if (frame.source != null) return frame.source;
    }
    return widget.item.config.source?.contentType?.startsWith('image/') == true
        ? widget.item.config.source
        : null;
  }

  void _load() {
    _reference = _findReference();
    _bytes = _reference == null
        ? null
        : widget.controller.gateway.readAsset(_reference!);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant GenerationInputPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_findReference()?.value != _reference?.value) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_reference == null || _bytes == null) {
      return const _MediaPlaceholder(
        icon: Icons.movie_creation_outlined,
        label: 'Saved generation',
      );
    }
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _MediaPlaceholder(
            icon: Icons.broken_image_outlined,
            label: 'Reference unavailable',
          );
        }
        if (!snapshot.hasData) {
          return const _MediaPlaceholder(
            icon: Icons.image_outlined,
            label: 'Loading reference',
          );
        }
        return Image.memory(snapshot.data!, fit: BoxFit.cover);
      },
    );
  }
}

class _GenerationVideoState extends State<GenerationVideo> {
  late VideoPlayerController _controller;
  Future<void>? _initializing;

  @override
  void initState() {
    super.initState();
    _createController();
  }

  @override
  void didUpdateWidget(covariant GenerationVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri) {
      unawaited(_controller.dispose());
      _createController();
    }
  }

  void _createController() {
    _controller = createVideoController(widget.uri);
    _initializing = _controller.initialize();
    _controller.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
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
        return const _MediaPlaceholder(
          icon: Icons.link_off_rounded,
          label: 'Delivery unavailable',
        );
      }
      if (snapshot.connectionState != ConnectionState.done) {
        return const _MediaPlaceholder(
          icon: Icons.hourglass_bottom_rounded,
          label: 'Loading film',
        );
      }
      return ColoredBox(
        color: Colors.black,
        child: Column(
          children: <Widget>[
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: VideoPlayer(_controller),
                ),
              ),
            ),
            VideoProgressIndicator(
              _controller,
              allowScrubbing: true,
              colors: const VideoProgressColors(
                playedColor: ClawnsoleColors.clay,
              ),
            ),
            Container(
              color: const Color(0xFF161A17),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: <Widget>[
                  IconButton(
                    color: Colors.white,
                    icon: Icon(
                      _controller.value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                    onPressed: () => _controller.value.isPlaying
                        ? _controller.pause()
                        : _controller.play(),
                  ),
                  const Text(
                    'Clawnsole preview',
                    style: TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _MediaPlaceholder extends StatelessWidget {
  const _MediaPlaceholder({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    color: ClawnsoleColors.forest,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: ClawnsoleColors.sage, size: 30),
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

class GenerationCost extends StatelessWidget {
  const GenerationCost({required this.item, super.key, this.compact = false});

  final Generation item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final minimum = item.cost ?? item.estimatedCreditsMin;
    final maximum = item.cost ?? item.estimatedCreditsMax;
    if (minimum == null || maximum == null) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.all(compact ? 9 : 12),
      decoration: BoxDecoration(
        color: item.cost != null
            ? const Color(0xFFE4EEE5)
            : const Color(0xFFF1E8D8),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.toll_rounded,
                size: compact ? 13 : 15,
                color: ClawnsoleColors.clayDark,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${item.cost != null ? 'BFL charge' : 'Estimated'} · '
                  '${formatCreditRange(minimum, maximum)} cr',
                  style: TextStyle(
                    fontSize: compact ? 10 : 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                formatUsdRange(minimum, maximum),
                style: TextStyle(
                  fontSize: compact ? 10 : 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          if (!compact &&
              item.creditsBefore != null &&
              item.creditsAfter != null) ...<Widget>[
            const SizedBox(height: 5),
            Text(
              '${formatCredits(item.creditsBefore!)} → ${formatCredits(item.creditsAfter!)} credits available',
              style: const TextStyle(fontSize: 9, color: ClawnsoleColors.muted),
            ),
          ],
        ],
      ),
    );
  }
}

class ActivityCard extends StatelessWidget {
  const ActivityCard({required this.controller, required this.item, super.key});

  final AppController controller;
  final Generation item;

  @override
  Widget build(BuildContext context) {
    final hasMedia = item.resultAsset != null || item.resultUrl != null;
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: hasMedia ? 180 : 110,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(17),
                  ),
                  child: hasMedia
                      ? GenerationMedia(controller: controller, item: item)
                      : GenerationInputPreview(
                          controller: controller,
                          item: item,
                        ),
                ),
                Positioned(left: 8, top: 8, child: StatusBadge(item: item)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      item.mode.label,
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      relativeTime(item.createdAt),
                      style: const TextStyle(fontSize: 9),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  item.prompt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                GenerationCost(item: item, compact: true),
                if (item.isWorking) ...<Widget>[
                  const SizedBox(height: 7),
                  LinearProgressIndicator(
                    value: item.progress == null ? null : item.progress! / 100,
                    minHeight: 5,
                    borderRadius: BorderRadius.circular(99),
                    backgroundColor: ClawnsoleColors.line,
                    color: ClawnsoleColors.clay,
                  ),
                ],
                const SizedBox(height: 9),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: <Widget>[
                    if (hasMedia)
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          try {
                            await controller.saveVideo(item);
                          } on Object catch (error) {
                            controller.showNotice(error.toString());
                          }
                        },
                        icon: const Icon(Icons.download_rounded, size: 15),
                        label: const Text('Save'),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => unawaited(controller.reuse(item)),
                      icon: const Icon(Icons.replay_rounded, size: 15),
                      label: const Text('Reuse inputs'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
