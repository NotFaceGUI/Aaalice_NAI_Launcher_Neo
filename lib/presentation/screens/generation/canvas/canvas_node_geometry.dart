import 'dart:math' as math;
import 'dart:ui';

import '../../../../data/models/canvas/canvas_node.dart';

/// 节点四角，决定缩放方向与锚定边。
enum CanvasNodeCorner {
  topLeft(isTop: true, isLeft: true),
  topRight(isTop: true, isLeft: false),
  bottomLeft(isTop: false, isLeft: true),
  bottomRight(isTop: false, isLeft: false);

  const CanvasNodeCorner({required this.isTop, required this.isLeft});

  final bool isTop;
  final bool isLeft;
}

/// 节点四边，决定从哪一侧拉出连线。
enum CanvasNodeSide { top, bottom, left, right }

/// Screen-space controls share the same bounds used by the node's parent.
class CanvasNodeHandleLayout {
  CanvasNodeHandleLayout(this.bodySize, {bool touch = false})
    : extent = touch ? 48 : 28;

  final Size bodySize;
  final double extent;

  bool get separated => bodySize.shortestSide < extent * 2;
  double get inset => separated ? extent * 1.5 : extent / 2;
  Size get size =>
      Size(bodySize.width + inset * 2, bodySize.height + inset * 2);

  Rect cornerRect(CanvasNodeCorner corner) => Rect.fromLTWH(
    corner.isLeft ? 0 : size.width - extent,
    corner.isTop ? 0 : size.height - extent,
    extent,
    extent,
  );

  Rect sideRect(CanvasNodeSide side) => Rect.fromLTWH(
    switch (side) {
      CanvasNodeSide.left => 0,
      CanvasNodeSide.right => size.width - extent,
      _ => (size.width - extent) / 2,
    },
    switch (side) {
      CanvasNodeSide.top => 0,
      CanvasNodeSide.bottom => size.height - extent,
      _ => (size.height - extent) / 2,
    },
    extent,
    extent,
  );
}

/// 由起始矩形与累计指针位移（屏幕单位）推导预览矩形。
///
/// 拖动角对面的边保持不动，所以左上/右上角会同时改变节点位置。
Rect resizeCanvasNodeRect(
  CanvasNodeCorner corner,
  Rect start,
  Offset pointerDelta, {
  required double scale,
  required bool aspectLocked,
}) {
  final d = pointerDelta / scale;
  var left = start.left;
  var top = start.top;
  var right = start.right;
  var bottom = start.bottom;

  if (corner.isLeft) {
    left = math.min(start.left + d.dx, start.right - CanvasNode.minNodeWidth);
  } else {
    right = math.max(start.right + d.dx, start.left + CanvasNode.minNodeWidth);
  }
  if (corner.isTop) {
    top = math.min(start.top + d.dy, start.bottom - CanvasNode.minNodeHeight);
  } else {
    bottom = math.max(
      start.bottom + d.dy,
      start.top + CanvasNode.minNodeHeight,
    );
  }

  var width = (right - left)
      .clamp(CanvasNode.minNodeWidth, CanvasNode.maxNodeWidth)
      .toDouble();
  var height = (bottom - top)
      .clamp(CanvasNode.minNodeHeight, CanvasNode.maxNodeHeight)
      .toDouble();

  if (aspectLocked) {
    // Project onto the aspect diagonal; either pointer axis can resize.
    final dx = corner.isLeft ? -d.dx : d.dx;
    final dy = corner.isTop ? -d.dy : d.dy;
    final minFactor = math.max(
      CanvasNode.minNodeWidth / start.width,
      CanvasNode.minNodeHeight / start.height,
    );
    final maxFactor = math.min(
      CanvasNode.maxNodeWidth / start.width,
      CanvasNode.maxNodeHeight / start.height,
    );
    final factor =
        (1 +
                (dx * start.width + dy * start.height) /
                    (start.width * start.width + start.height * start.height))
            .clamp(minFactor, maxFactor);
    width = start.width * factor;
    height = start.height * factor;
  }

  // 锚定角对面的边：左侧角固定右边缘，上侧角固定下边缘
  final anchorX = corner.isLeft ? start.right : start.left;
  final anchorY = corner.isTop ? start.bottom : start.top;
  return Rect.fromLTWH(
    corner.isLeft ? anchorX - width : anchorX,
    corner.isTop ? anchorY - height : anchorY,
    width,
    height,
  );
}
