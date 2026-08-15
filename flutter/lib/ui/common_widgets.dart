import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import '../core/models.dart';
import 'formatters.dart';

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
    _controller = VideoPlayerController.networkUrl(widget.uri);
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
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.all(12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 86,
          height: 72,
          decoration: BoxDecoration(
            color: ClawnsoleColors.forest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            children: <Widget>[
              const Center(
                child: Icon(
                  Icons.movie_creation_outlined,
                  color: ClawnsoleColors.sage,
                ),
              ),
              Positioned(left: 6, top: 6, child: StatusBadge(item: item)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
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
            ],
          ),
        ),
      ],
    ),
  );
}
