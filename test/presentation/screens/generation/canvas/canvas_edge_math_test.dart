import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/screens/generation/canvas/canvas_edge_math.dart';

void main() {
  group('端点落在矩形边界上', () {
    test('目标在右侧时从左缘出发', () {
      const rect = Rect.fromLTWH(0, 0, 100, 100);
      final anchor = CanvasEdgeMath.anchorOnRect(rect, const Offset(400, 50));
      expect(anchor.dx, closeTo(100, 1e-9));
      expect(anchor.dy, closeTo(50, 1e-9));
    });

    test('目标在上方时从顶缘出发', () {
      const rect = Rect.fromLTWH(0, 0, 100, 100);
      final anchor = CanvasEdgeMath.anchorOnRect(rect, const Offset(50, -400));
      expect(anchor.dx, closeTo(50, 1e-9));
      expect(anchor.dy, closeTo(0, 1e-9));
    });

    test('目标与中心重合时退化为中心点', () {
      const rect = Rect.fromLTWH(0, 0, 100, 100);
      expect(CanvasEdgeMath.anchorOnRect(rect, rect.center), rect.center);
    });

    test('端点始终在矩形边界上', () {
      const rect = Rect.fromLTWH(10, 20, 80, 60);
      for (final target in const [
        Offset(500, 50),
        Offset(50, -500),
        Offset(-500, 50),
        Offset(50, 500),
        Offset(-500, -500),
        Offset(500, 500),
      ]) {
        final anchor = CanvasEdgeMath.anchorOnRect(rect, target);
        final onVerticalEdge =
            (anchor.dx - rect.left).abs() < 1e-9 ||
            (anchor.dx - rect.right).abs() < 1e-9;
        final onHorizontalEdge =
            (anchor.dy - rect.top).abs() < 1e-9 ||
            (anchor.dy - rect.bottom).abs() < 1e-9;
        expect(
          onVerticalEdge || onHorizontalEdge,
          isTrue,
          reason: '目标 $target 的端点 $anchor 不在边界上',
        );
      }
    });
  });

  group('路径', () {
    test('水平方向相近时用水平入出控制点', () {
      final path = CanvasEdgeMath.path(
        const Offset(0, 0),
        const Offset(200, 20),
      );
      final metric = path.computeMetrics().first;
      expect(metric.length, greaterThan(200));
      expect(metric.length, lessThan(260));
    });

    test('垂直方向相近时用垂直入出控制点', () {
      final path = CanvasEdgeMath.path(
        const Offset(0, 0),
        const Offset(20, 200),
      );
      final metric = path.computeMetrics().first;
      expect(metric.length, greaterThan(200));
      expect(metric.length, lessThan(260));
    });

    test('标签锚点落在曲线中点附近', () {
      final anchor = CanvasEdgeMath.labelAnchor(
        const Offset(0, 0),
        const Offset(100, 0),
      );
      expect(anchor.dx, closeTo(50, 1));
      expect(anchor.dy, closeTo(0, 1));
    });
  });

  group('命中距离', () {
    test('直线上与线外点的距离可区分', () {
      const start = Offset(0, 0);
      const end = Offset(100, 0);
      expect(
        CanvasEdgeMath.distanceTo(const Offset(50, 0), start, end),
        lessThan(1),
      );
      expect(
        CanvasEdgeMath.distanceTo(const Offset(50, 30), start, end),
        closeTo(30, 1),
      );
    });

    test('远离路径的点距离显著更大', () {
      const start = Offset(0, 0);
      const end = Offset(100, 0);
      final near = CanvasEdgeMath.distanceTo(const Offset(50, 5), start, end);
      final far = CanvasEdgeMath.distanceTo(const Offset(50, 200), start, end);
      expect(far, greaterThan(near * 10));
    });
  });
}
