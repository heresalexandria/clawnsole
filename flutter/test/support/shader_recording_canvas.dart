import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A canvas that keeps every shader and mask filter a painter hands it, so a
/// test can check allocation discipline without rendering pixels:
///
/// * a *temporary* shader is one the painter builds for a single frame and
///   must dispose before the frame ends;
/// * a *reused* shader is one the painter keeps across frames — the same
///   object turns up again on the next paint.
///
/// [paintTwice] runs a painter two frames in a row at one size and reports
/// what the second frame created that the first had not.
class ShaderRecordingCanvas implements Canvas {
  ShaderRecordingCanvas({this.throwOnShader = false});

  final bool throwOnShader;
  final List<ui.Shader> shaders = <ui.Shader>[];
  final List<ui.MaskFilter> maskFilters = <ui.MaskFilter>[];
  final List<ui.Path> paths = <ui.Path>[];
  int drawCalls = 0;

  void _record(Paint paint) {
    drawCalls += 1;
    final mask = paint.maskFilter;
    if (mask != null) maskFilters.add(mask);
    final shader = paint.shader;
    if (shader == null) return;
    shaders.add(shader);
    if (throwOnShader) throw StateError('Synthetic canvas failure');
  }

  /// Distinct shader objects seen so far.
  Set<ui.Shader> get distinctShaders =>
      Set<ui.Shader>.identity()..addAll(shaders);

  @override
  void drawRect(Rect rect, Paint paint) => _record(paint);

  @override
  void drawRRect(RRect rrect, Paint paint) => _record(paint);

  @override
  void drawDRRect(RRect outer, RRect inner, Paint paint) => _record(paint);

  @override
  void drawCircle(Offset c, double radius, Paint paint) => _record(paint);

  @override
  void drawOval(Rect rect, Paint paint) => _record(paint);

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) => _record(paint);

  @override
  void drawPath(Path path, Paint paint) {
    paths.add(path);
    _record(paint);
  }

  @override
  void drawPoints(ui.PointMode pointMode, List<Offset> points, Paint paint) =>
      _record(paint);

  @override
  void drawImage(ui.Image image, Offset offset, Paint paint) => _record(paint);

  @override
  void drawImageRect(ui.Image image, Rect src, Rect dst, Paint paint) =>
      _record(paint);

  @override
  void drawArc(
    Rect rect,
    double startAngle,
    double sweepAngle,
    bool useCenter,
    Paint paint,
  ) => _record(paint);

  @override
  void saveLayer(Rect? bounds, Paint paint) => _record(paint);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// The outcome of painting a painter twice at the same size.
class PaintTwiceReport {
  const PaintTwiceReport({
    required this.first,
    required this.second,
    required this.newOnSecond,
    required this.leakedOnSecond,
  });

  /// Every shader the first frame used.
  final Set<ui.Shader> first;

  /// Every shader the second frame used.
  final Set<ui.Shader> second;

  /// Shaders the second frame created that the first frame never had.
  final Set<ui.Shader> newOnSecond;

  /// Of [newOnSecond], the ones still alive after the frame: neither reused
  /// nor released — exactly what the web engine cannot reclaim in time.
  final Set<ui.Shader> leakedOnSecond;
}

/// Paints [paint] twice on fresh recording canvases at [size].
PaintTwiceReport paintTwice(
  void Function(Canvas canvas, Size size) paint,
  Size size,
) {
  final one = ShaderRecordingCanvas();
  paint(one, size);
  final two = ShaderRecordingCanvas();
  paint(two, size);
  final first = one.distinctShaders;
  final second = two.distinctShaders;
  final fresh = second.difference(first);
  return PaintTwiceReport(
    first: first,
    second: second,
    newOnSecond: fresh,
    leakedOnSecond: fresh.where((shader) => !shader.debugDisposed).toSet(),
  );
}
