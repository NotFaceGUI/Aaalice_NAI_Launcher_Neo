import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

/// 无限点阵背景。
///
/// 在屏幕空间按视口偏移取模绘制，因此画布可以无限延伸而不需要任何
/// 有限的画布尺寸；缩放时按 2 的幂调整点距，保证屏幕上的密度稳定、
/// 既不糊成一片也不稀疏到失去参照。
class CanvasGridPainter extends CustomPainter {
  const CanvasGridPainter({
    required this.offsetX,
    required this.offsetY,
    required this.scale,
    required this.dotColor,
  });

  /// 100% 缩放时的点距（画布空间）
  static const double baseSpacing = 32;

  /// 屏幕空间上允许的点距区间
  static const double minScreenSpacing = 20;
  static const double maxScreenSpacing = 72;

  static const double dotRadius = 1;

  final double offsetX;
  final double offsetY;
  final double scale;
  final Color dotColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !scale.isFinite || scale <= 0) return;

    var spacing = baseSpacing * scale;
    if (!spacing.isFinite || spacing <= 0) return;
    while (spacing < minScreenSpacing) {
      spacing *= 2;
    }
    while (spacing > maxScreenSpacing) {
      spacing /= 2;
    }

    final points = <Offset>[];
    final startX = offsetX % spacing;
    final startY = offsetY % spacing;
    for (var x = startX; x <= size.width; x += spacing) {
      for (var y = startY; y <= size.height; y += spacing) {
        points.add(Offset(x, y));
      }
    }
    if (points.isEmpty) return;

    canvas.drawPoints(
      PointMode.points,
      points,
      Paint()
        ..color = dotColor
        ..strokeWidth = dotRadius * 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant CanvasGridPainter oldDelegate) =>
      oldDelegate.offsetX != offsetX ||
      oldDelegate.offsetY != offsetY ||
      oldDelegate.scale != scale ||
      oldDelegate.dotColor != dotColor;

  /// 背景只作参照，不参与命中。
  ///
  /// CustomPaint 带 painter 时 hitTestSelf 默认返回 true，会让网格吃掉指针
  /// 事件、遮住它下面的图层；这里显式让出。
  @override
  bool? hitTest(Offset position) => false;
}
