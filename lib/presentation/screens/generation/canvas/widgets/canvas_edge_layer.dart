import 'package:flutter/material.dart';

import '../../../../../data/models/canvas/canvas_edge.dart';
import '../canvas_edge_math.dart';

/// 一条连线在画布空间的几何信息（端点矩形取自它连接的两个节点）。
@immutable
class CanvasEdgeGeometry {
  const CanvasEdgeGeometry({
    required this.edge,
    required this.route,
    required this.selected,
  });

  final CanvasEdge edge;
  final CanvasEdgeRoute route;
  final bool selected;
}

/// 正在拖拽的连线草稿（画布空间）。
@immutable
class CanvasLinkDraftGeometry {
  const CanvasLinkDraftGeometry({
    required this.fromRect,
    required this.currentPoint,
    required this.targetRect,
  });

  final Rect fromRect;
  final Offset currentPoint;

  /// 指针当前悬停的目标节点；为空表示尚未落到可连接节点上
  final Rect? targetRect;

  bool get hasValidTarget => targetRect != null;

  /// 目标确定时复用正式路由，未确定时从矩形边界朝指针方向出线。
  CanvasEdgeRoute resolve() {
    final target = targetRect;
    if (target != null) return CanvasEdgeMath.route(fromRect, target);
    final start = CanvasEdgeMath.anchorOnRect(fromRect, currentPoint);
    final delta = currentPoint - fromRect.center;
    return CanvasEdgeRoute(
      start: start,
      end: currentPoint,
      horizontal: delta.dx.abs() >= delta.dy.abs(),
    );
  }
}

/// 连线层：一层 CustomPaint 画完全部连线。
class CanvasEdgeLayer extends StatelessWidget {
  const CanvasEdgeLayer({
    super.key,
    required this.edges,
    required this.offsetX,
    required this.offsetY,
    required this.scale,
    required this.lineColor,
    required this.selectedColor,
    required this.labelSurfaceColor,
    required this.labelTextColor,
    this.draft,
    this.revealEdgeId,
    this.revealProgress = 1,
  });

  final List<CanvasEdgeGeometry> edges;
  final double offsetX;
  final double offsetY;
  final double scale;
  final Color lineColor;
  final Color selectedColor;
  final Color labelSurfaceColor;
  final Color labelTextColor;
  final CanvasLinkDraftGeometry? draft;
  final String? revealEdgeId;
  final double revealProgress;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: CanvasEdgePainter(
          edges: edges,
          offsetX: offsetX,
          offsetY: offsetY,
          scale: scale,
          lineColor: lineColor,
          selectedColor: selectedColor,
          labelSurfaceColor: labelSurfaceColor,
          labelTextColor: labelTextColor,
          textDirection: Directionality.of(context),
          draft: draft,
          revealEdgeId: revealEdgeId,
          revealProgress: revealProgress,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class CanvasEdgePainter extends CustomPainter {
  const CanvasEdgePainter({
    required this.edges,
    required this.offsetX,
    required this.offsetY,
    required this.scale,
    required this.lineColor,
    required this.selectedColor,
    required this.labelSurfaceColor,
    required this.labelTextColor,
    required this.textDirection,
    this.draft,
    this.revealEdgeId,
    this.revealProgress = 1,
  });

  static const double baseStrokeWidth = 2;
  static const double baseArrowSize = 10;

  final List<CanvasEdgeGeometry> edges;
  final double offsetX;
  final double offsetY;
  final double scale;
  final Color lineColor;
  final Color selectedColor;
  final Color labelSurfaceColor;
  final Color labelTextColor;
  final TextDirection textDirection;
  final CanvasLinkDraftGeometry? draft;
  final String? revealEdgeId;
  final double revealProgress;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !scale.isFinite || scale <= 0) return;
    canvas.clipRect(Offset.zero & size);

    for (final geometry in edges) {
      final progress = geometry.edge.id == revealEdgeId
          ? revealProgress.clamp(0.0, 1.0)
          : 1.0;
      if (progress <= 0) continue;
      _paintEdge(canvas, geometry, progress);
    }

    final draftGeometry = draft;
    if (draftGeometry != null) _paintDraft(canvas, draftGeometry);
  }

  void _paintEdge(Canvas canvas, CanvasEdgeGeometry geometry, double progress) {
    final route = geometry.route;
    final start = _toScreen(route.start);
    final end = _toScreen(route.end);
    if ((end - start).distance < 0.5) return;

    final strokeWidth = (baseStrokeWidth * scale).clamp(1.0, 6.0);
    final color = geometry.selected ? selectedColor : lineColor;
    final paint = Paint()
      ..color = color.withValues(alpha: geometry.selected ? 0.95 : 0.75)
      ..strokeWidth = geometry.selected ? strokeWidth * 1.6 : strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = CanvasEdgeMath.path(start, end, horizontal: route.horizontal);
    final visible = progress >= 1 ? path : _extractProgress(path, progress);
    canvas.drawPath(visible, paint);

    // 箭头只在连线完整呈现后出现，避免生长过程里箭头先到终点
    if (progress >= 1) {
      _paintArrowHead(canvas, route, start, end, paint, strokeWidth);
    }

    final label = geometry.edge.label;
    if (label != null && label.isNotEmpty && progress >= 1) {
      // 标签与中点箭头同处一段，按曲线法线让开，避免压在一起
      final arrow = CanvasEdgeMath.midArrow(
        start,
        end,
        horizontal: route.horizontal,
      );
      final normal = Offset(-arrow.direction.dy, arrow.direction.dx);
      final clearance =
          (baseArrowSize * scale).clamp(5.0, 20.0) * 0.5 +
          (12 * scale).clamp(8.0, 40.0) +
          4 * scale;
      _paintLabel(canvas, arrow.position + normal * clearance, label);
    }
  }

  void _paintDraft(Canvas canvas, CanvasLinkDraftGeometry geometry) {
    final route = geometry.resolve();
    final start = _toScreen(route.start);
    final end = _toScreen(route.end);

    final strokeWidth = (baseStrokeWidth * scale).clamp(1.0, 6.0);
    final paint = Paint()
      ..color = selectedColor.withValues(
        alpha: geometry.hasValidTarget ? 0.95 : 0.6,
      )
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = CanvasEdgeMath.path(start, end, horizontal: route.horizontal);
    _drawDashed(canvas, path, paint);
    canvas.drawCircle(
      end,
      (strokeWidth * 1.8).clamp(2.5, 7.0),
      Paint()..color = paint.color,
    );
  }

  void _paintArrowHead(
    Canvas canvas,
    CanvasEdgeRoute route,
    Offset start,
    Offset end,
    Paint paint,
    double strokeWidth,
  ) {
    final size = (baseArrowSize * scale).clamp(5.0, 20.0);
    // 画在线段中点并取该处切线方向：曲线中段往往已经转向，
    // 用中点切线才能让箭头符合这一段实际的走向
    final arrow = CanvasEdgeMath.midArrow(
      start,
      end,
      horizontal: route.horizontal,
    );
    final direction = arrow.direction;
    if (direction == Offset.zero) return;
    final normal = Offset(-direction.dy, direction.dx);
    final tip = arrow.position + direction * (size * 0.5);
    final base = tip - direction * size;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(
        base.dx + normal.dx * size * 0.5,
        base.dy + normal.dy * size * 0.5,
      )
      ..lineTo(
        base.dx - normal.dx * size * 0.5,
        base.dy - normal.dy * size * 0.5,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = paint.color);
  }

  void _paintLabel(Canvas canvas, Offset anchor, String label) {
    final fontSize = (12 * scale).clamp(8.0, 40.0);
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: labelTextColor,
          fontSize: fontSize,
          height: 1.2,
        ),
      ),
      textDirection: textDirection,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: (220 * scale).clamp(80.0, 320.0));

    final padding = EdgeInsets.symmetric(
      horizontal: (6 * scale).clamp(4.0, 14.0),
      vertical: (3 * scale).clamp(2.0, 8.0),
    );
    final rect = Rect.fromCenter(
      center: anchor,
      width: painter.width + padding.horizontal,
      height: painter.height + padding.vertical,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect,
        Radius.circular((6 * scale).clamp(3.0, 12.0)),
      ),
      Paint()..color = labelSurfaceColor,
    );
    painter.paint(
      canvas,
      Offset(rect.left + padding.left, rect.top + padding.top),
    );
  }

  Path _extractProgress(Path path, double progress) {
    final result = Path();
    for (final metric in path.computeMetrics()) {
      result.addPath(
        metric.extractPath(0, metric.length * progress),
        Offset.zero,
      );
    }
    return result;
  }

  void _drawDashed(Canvas canvas, Path path, Paint paint) {
    final dash = (8 * scale).clamp(4.0, 16.0);
    final gap = (6 * scale).clamp(3.0, 12.0);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  Offset _toScreen(Offset canvasPoint) => Offset(
    canvasPoint.dx * scale + offsetX,
    canvasPoint.dy * scale + offsetY,
  );

  @override
  bool shouldRepaint(covariant CanvasEdgePainter oldDelegate) =>
      oldDelegate.edges != edges ||
      oldDelegate.offsetX != offsetX ||
      oldDelegate.offsetY != offsetY ||
      oldDelegate.scale != scale ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.selectedColor != selectedColor ||
      oldDelegate.labelSurfaceColor != labelSurfaceColor ||
      oldDelegate.labelTextColor != labelTextColor ||
      oldDelegate.draft != draft ||
      oldDelegate.revealEdgeId != revealEdgeId ||
      oldDelegate.revealProgress != revealProgress;
}
