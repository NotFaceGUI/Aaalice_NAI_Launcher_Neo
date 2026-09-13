import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/canvas/canvas_edge.dart';
import 'package:nai_launcher/data/models/canvas/canvas_node.dart';
import 'package:nai_launcher/presentation/screens/generation/canvas/canvas_edge_math.dart';
import 'package:nai_launcher/presentation/screens/generation/canvas/canvas_node_geometry.dart';
import 'package:nai_launcher/presentation/screens/generation/canvas/widgets/canvas_edge_layer.dart';

class _PathCanvas extends Fake implements Canvas {
  final paths = <Path>[];

  @override
  void clipRect(
    Rect rect, {
    ClipOp clipOp = ClipOp.intersect,
    bool doAntiAlias = true,
  }) {}

  @override
  void drawPath(Path path, Paint paint) => paths.add(path);
}

void main() {
  for (final touch in [false, true]) {
    for (final scale in [0.1, 0.25, 0.5, 1.0, 2.0, 4.0]) {
      test('handles remain contained and disjoint at $scale, touch=$touch', () {
        final layout = CanvasNodeHandleLayout(
          const Size(200, 120) * scale,
          touch: touch,
        );
        final rects = [
          for (final corner in CanvasNodeCorner.values)
            layout.cornerRect(corner),
          for (final side in CanvasNodeSide.values) layout.sideRect(side),
        ];
        final bounds = Offset.zero & layout.size;
        for (var i = 0; i < rects.length; i++) {
          expect(bounds.intersect(rects[i]), rects[i]);
          if (touch) expect(rects[i].shortestSide, greaterThanOrEqualTo(44));
          for (var j = i + 1; j < rects.length; j++) {
            expect(
              rects[i].overlaps(rects[j]),
              isFalse,
              reason: '$i overlaps $j',
            );
          }
        }
      });
    }
  }

  for (final corner in CanvasNodeCorner.values) {
    for (final delta in [
      const Offset(0, 80),
      const Offset(80, 0),
      const Offset(10000, 10000),
      const Offset(-10000, -10000),
    ]) {
      test(
        'aspect ratio and opposite anchor survive ${corner.name}: $delta',
        () {
          const start = Rect.fromLTWH(4200, 3100, 200, 300);
          final rect = resizeCanvasNodeRect(
            corner,
            start,
            delta,
            scale: 0.5,
            aspectLocked: true,
          );
          expect(rect.width / rect.height, closeTo(2 / 3, 1e-9));
          expect(
            rect.width,
            inInclusiveRange(CanvasNode.minNodeWidth, CanvasNode.maxNodeWidth),
          );
          expect(
            rect.height,
            inInclusiveRange(
              CanvasNode.minNodeHeight,
              CanvasNode.maxNodeHeight,
            ),
          );
          expect(
            corner.isLeft ? rect.right : rect.left,
            corner.isLeft ? start.right : start.left,
          );
          expect(
            corner.isTop ? rect.bottom : rect.top,
            corner.isTop ? start.bottom : start.top,
          );
          expect(rect.size, isNot(start.size));
        },
      );
    }
  }

  for (final scale in [0.25, 0.5, 1.0, 2.0]) {
    test('edge curve and arrow use viewport coordinates at $scale', () {
      const route = CanvasEdgeRoute(
        start: Offset(4400, 3100),
        end: Offset(4700, 3200),
        horizontal: true,
      );
      const offset = Offset(-1000, -700);
      final canvas = _PathCanvas();
      final stamp = DateTime.fromMillisecondsSinceEpoch(1);
      final painter = CanvasEdgePainter(
        edges: [
          CanvasEdgeGeometry(
            edge: CanvasEdge(
              id: 'e',
              fromNodeId: 'a',
              toNodeId: 'b',
              createdAt: stamp,
              updatedAt: stamp,
            ),
            route: route,
            selected: false,
          ),
        ],
        offsetX: offset.dx,
        offsetY: offset.dy,
        scale: scale,
        lineColor: const Color(0xff999999),
        selectedColor: const Color(0xffaaaaaa),
        labelSurfaceColor: const Color(0xff222222),
        labelTextColor: const Color(0xffffffff),
        textDirection: TextDirection.ltr,
      );
      painter.paint(canvas, const Size(10000, 10000));
      final expected = CanvasEdgeMath.path(
        route.start * scale + offset,
        route.end * scale + offset,
        horizontal: true,
      );
      expect(canvas.paths.first.getBounds(), expected.getBounds());
      expect(canvas.paths, hasLength(2));
      expect(
        canvas.paths.last
            .getBounds()
            .inflate(25)
            .contains(route.end * scale + offset),
        isTrue,
      );
    });
  }
}
