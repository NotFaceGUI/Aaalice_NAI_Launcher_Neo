import 'dart:math' as math;
import 'dart:ui';

/// 一条连线的路由结果：两个端点与走向轴。
///
/// 端点固定取矩形相对侧的边中点（而不是"中心连线与边界的交点"），这样
/// 线与节点的接触点可预测，箭头方向也始终沿出线方向，不会出现斜切着插
/// 进节点、或箭头指向与曲线不一致的情况。
class CanvasEdgeRoute {
  const CanvasEdgeRoute({
    required this.start,
    required this.end,
    required this.horizontal,
  });

  final Offset start;
  final Offset end;

  /// true 表示左右出线（水平三次贝塞尔），false 表示上下出线
  final bool horizontal;
}

/// 连线路径的纯几何计算。
///
/// 绘制、箭头方向与命中测试共用同一套公式，避免"看到的线"与"点得到的线"
/// 不一致。
class CanvasEdgeMath {
  CanvasEdgeMath._();

  /// 命中测试的容差（画布空间，调用方按缩放折算后传入更合适）
  static const double defaultHitTolerance = 8;

  /// 按两个矩形的相对位置决定出入边中点。
  static CanvasEdgeRoute route(Rect from, Rect to) {
    final dx = to.center.dx - from.center.dx;
    final dy = to.center.dy - from.center.dy;
    if (dx.abs() >= dy.abs()) {
      // 左右为主：从右缘出、左缘入（或反向）
      final goesRight = dx >= 0;
      return CanvasEdgeRoute(
        start: Offset(goesRight ? from.right : from.left, from.center.dy),
        end: Offset(goesRight ? to.left : to.right, to.center.dy),
        horizontal: true,
      );
    }
    final goesDown = dy >= 0;
    return CanvasEdgeRoute(
      start: Offset(from.center.dx, goesDown ? from.bottom : from.top),
      end: Offset(to.center.dx, goesDown ? to.top : to.bottom),
      horizontal: false,
    );
  }

  /// 从矩形边界朝 [towards] 射出时的交点；拖拽预览用（目标还不确定）。
  static Offset anchorOnRect(Rect rect, Offset towards) {
    final center = rect.center;
    final dx = towards.dx - center.dx;
    final dy = towards.dy - center.dy;
    if (dx == 0 && dy == 0) return center;
    final halfWidth = rect.width / 2;
    final halfHeight = rect.height / 2;
    if (dx == 0) return Offset(center.dx, center.dy + halfHeight * dy.sign);
    if (dy == 0) return Offset(center.dx + halfWidth * dx.sign, center.dy);
    final scaleX = halfWidth / dx.abs();
    final scaleY = halfHeight / dy.abs();
    final t = math.min(scaleX, scaleY);
    return Offset(center.dx + dx * t, center.dy + dy * t);
  }

  /// 与走向轴一致的三次贝塞尔。
  static Path pathForRoute(CanvasEdgeRoute route) =>
      path(route.start, route.end, horizontal: route.horizontal);

  /// 三次贝塞尔路径；[horizontal] 为空时按两点位移推断走向。
  static Path path(Offset start, Offset end, {bool? horizontal}) {
    final delta = end - start;
    final useHorizontal = horizontal ?? delta.dx.abs() >= delta.dy.abs();
    final path = Path()..moveTo(start.dx, start.dy);
    if (useHorizontal) {
      final handle = delta.dx * 0.5;
      path.cubicTo(
        start.dx + handle,
        start.dy,
        end.dx - handle,
        end.dy,
        end.dx,
        end.dy,
      );
    } else {
      final handle = delta.dy * 0.5;
      path.cubicTo(
        start.dx,
        start.dy + handle,
        end.dx,
        end.dy - handle,
        end.dx,
        end.dy,
      );
    }
    return path;
  }

  /// 曲线中点，用于放置标签。
  static Offset labelAnchor(Offset start, Offset end, {bool? horizontal}) {
    final metric = path(
      start,
      end,
      horizontal: horizontal,
    ).computeMetrics().first;
    final tangent = metric.getTangentForOffset(metric.length / 2);
    return tangent?.position ?? Offset.lerp(start, end, 0.5)!;
  }

  /// 末端切线方向（单位向量）。
  ///
  /// 用曲线自身的走向而不是两点连线：直线弦方向与曲线末端切线不一致时，
  /// 箭头会指向错误的方向。
  static Offset endTangent(Offset start, Offset end, {bool? horizontal}) {
    final delta = end - start;
    final useHorizontal = horizontal ?? delta.dx.abs() >= delta.dy.abs();
    final direction = useHorizontal
        ? Offset(delta.dx.sign, 0)
        : Offset(0, delta.dy.sign);
    if (direction == Offset.zero) {
      final length = delta.distance;
      return length == 0 ? Offset.zero : delta / length;
    }
    return direction;
  }

  /// [point] 到连线的最近距离（画布空间）。
  static double distanceTo(
    Offset point,
    Offset start,
    Offset end, {
    bool? horizontal,
  }) {
    var nearest = double.infinity;
    final metric = path(
      start,
      end,
      horizontal: horizontal,
    ).computeMetrics().first;
    const samples = 24;
    for (var i = 0; i <= samples; i++) {
      final metricPoint = metric
          .getTangentForOffset(metric.length * i / samples)
          ?.position;
      if (metricPoint == null) continue;
      final distance = (metricPoint - point).distance;
      if (distance < nearest) nearest = distance;
    }
    return nearest;
  }
}
