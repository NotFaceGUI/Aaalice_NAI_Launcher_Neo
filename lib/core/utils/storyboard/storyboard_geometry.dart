import 'dart:math' as math;
import 'dart:ui';

import '../../../data/models/storyboard/storyboard_page.dart';
import '../../../data/models/storyboard/storyboard_panel.dart';

/// 分镜页的纯几何计算：版面约束、多边形路径、命中测试与网格布局。
///
/// 全部函数不依赖 Flutter widget 与 provider，可在单测里直接验证。
/// 坐标约定：分镜矩形使用页面像素；多边形顶点使用相对该矩形的 0..1 归一化值。
class StoryboardGeometry {
  StoryboardGeometry._();

  /// 网格生成时单页允许的最大分镜数。
  static const int maxGridCells = 64;

  /// 网格行列数上限，与构图参考线的分档保持同一个量级。
  static const int maxGridDivisions = 12;

  /// 顶点与边的命中半径默认值（屏幕像素，由调用方按视口缩放换算）。
  static const double defaultVertexHitRadius = 12.0;

  // ==================== 版面矩形 ====================

  /// 把分镜矩形收进页面范围并保证最小边长。
  ///
  /// 尺寸先钳制到不超过页面，再钳制位置，保证结果一定完整落在页面内。
  static Rect normalizeRect(
    Rect rect, {
    required Size pageSize,
    double minSide = StoryboardPanel.minSide,
  }) {
    if (pageSize.width <= 0 || pageSize.height <= 0) {
      return Rect.fromLTWH(0, 0, math.max(minSide, 0), math.max(minSide, 0));
    }

    var width = rect.width.isFinite ? rect.width : minSide;
    var height = rect.height.isFinite ? rect.height : minSide;
    width = width.clamp(minSide, pageSize.width);
    height = height.clamp(minSide, pageSize.height);

    var left = rect.left.isFinite ? rect.left : 0.0;
    var top = rect.top.isFinite ? rect.top : 0.0;
    left = left.clamp(0.0, pageSize.width - width);
    top = top.clamp(0.0, pageSize.height - height);

    return Rect.fromLTWH(left, top, width, height);
  }

  /// 位置与尺寸之外的元数据是否需要随矩形变化重新计算。
  static bool rectsNearlyEqual(Rect a, Rect b, {double tolerance = 0.01}) {
    return (a.left - b.left).abs() <= tolerance &&
        (a.top - b.top).abs() <= tolerance &&
        (a.width - b.width).abs() <= tolerance &&
        (a.height - b.height).abs() <= tolerance;
  }

  // ==================== 多边形 ====================

  /// 归一化顶点在像素空间的包围盒。
  static Rect pixelBounds(List<Offset> pixelPoints) {
    if (pixelPoints.isEmpty) return Rect.zero;
    var minX = pixelPoints.first.dx;
    var maxX = pixelPoints.first.dx;
    var minY = pixelPoints.first.dy;
    var maxY = pixelPoints.first.dy;
    for (final point in pixelPoints) {
      minX = math.min(minX, point.dx);
      maxX = math.max(maxX, point.dx);
      minY = math.min(minY, point.dy);
      maxY = math.max(maxY, point.dy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// 由像素空间顶点反推矩形与外接矩形内的归一化顶点。
  ///
  /// 顶点退化（共线、重合）导致外接矩形没有面积时，用最小边长撑开，
  /// 否则归一化会出现除零并产生 NaN 顶点。
  static ({Rect rect, List<Offset> points}) fitPolygonToPixelBounds(
    List<Offset> pixelPoints, {
    double minSide = StoryboardPanel.minSide,
  }) {
    if (pixelPoints.length < StoryboardPanel.minPolygonPoints) {
      return (rect: Rect.fromLTWH(0, 0, minSide, minSide), points: const []);
    }

    final bounds = pixelBounds(pixelPoints);
    final width = math.max(bounds.width, minSide);
    final height = math.max(bounds.height, minSide);
    final rect = Rect.fromLTWH(bounds.left, bounds.top, width, height);

    final points = <Offset>[
      for (final point in pixelPoints)
        Offset(
          ((point.dx - rect.left) / width).clamp(0.0, 1.0),
          ((point.dy - rect.top) / height).clamp(0.0, 1.0),
        ),
    ];
    return (rect: rect, points: points);
  }

  /// 归一化顶点展开到页面像素坐标。
  static List<Offset> toPixelPoints(List<Offset> normalizedPoints, Rect rect) {
    return [
      for (final point in normalizedPoints)
        Offset(
          rect.left + point.dx * rect.width,
          rect.top + point.dy * rect.height,
        ),
    ];
  }

  /// 构建分镜的绘制路径；矩形分镜或顶点不足时退回矩形路径。
  static Path buildPanelPath({
    required Rect rect,
    required List<Offset> points,
    required bool polygon,
  }) {
    final path = Path();
    if (!polygon || points.length < StoryboardPanel.minPolygonPoints) {
      path.addRect(rect);
      return path;
    }
    path.addPolygon(toPixelPoints(points, rect), true);
    return path;
  }

  /// 页面像素坐标下的多边形命中测试（射线法，适用于任意简单多边形）。
  static bool containsPoint(
    List<Offset> normalizedPoints,
    Rect rect,
    Offset point,
  ) {
    if (normalizedPoints.length < StoryboardPanel.minPolygonPoints) {
      return rect.contains(point);
    }
    return containsPixelPoint(toPixelPoints(normalizedPoints, rect), point);
  }

  /// 顶点已是页面像素坐标时的命中测试。
  static bool containsPixelPoint(List<Offset> polygon, Offset point) {
    if (polygon.length < 3) return false;
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final current = polygon[i];
      final previous = polygon[j];
      // 水平跨越判断同时排除了除零：顶点分居点上下时 dy 必然不同。
      if ((current.dy > point.dy) != (previous.dy > point.dy) &&
          point.dx <
              (previous.dx - current.dx) *
                      (point.dy - current.dy) /
                      (previous.dy - current.dy) +
                  current.dx) {
        inside = !inside;
      }
    }
    return inside;
  }

  /// 命中多边形顶点，返回顶点下标；未命中返回 -1。
  ///
  /// 从后往前比较，让后加入（绘制在上层）的顶点在重叠时优先被选中。
  static int hitTestVertex({
    required List<Offset> normalizedPoints,
    required Rect rect,
    required Offset point,
    double radius = defaultVertexHitRadius,
  }) {
    var bestIndex = -1;
    var bestDistance = radius;
    for (var i = normalizedPoints.length - 1; i >= 0; i--) {
      final pixel = toPixelPoints([normalizedPoints[i]], rect).first;
      final distance = (pixel - point).distance;
      if (distance <= bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  /// 命中多边形边，返回插入下标与投影后的归一化顶点；未命中返回 null。
  ///
  /// 插入下标表示新顶点应插到该下标之前，保持原有顶点顺序。
  static ({int insertIndex, Offset point})? hitTestEdge({
    required List<Offset> normalizedPoints,
    required Rect rect,
    required Offset point,
    double radius = defaultVertexHitRadius,
  }) {
    if (normalizedPoints.length < StoryboardPanel.minPolygonPoints) return null;
    final polygon = toPixelPoints(normalizedPoints, rect);

    var bestIndex = -1;
    var bestDistance = radius;
    Offset? bestPoint;
    for (var i = 0; i < polygon.length; i++) {
      final start = polygon[i];
      final end = polygon[(i + 1) % polygon.length];
      final projected = projectPointOnSegment(point, start, end);
      final distance = (projected - point).distance;
      if (distance <= bestDistance) {
        bestDistance = distance;
        bestIndex = i + 1;
        bestPoint = projected;
      }
    }
    if (bestIndex < 0 || bestPoint == null) return null;
    if (rect.width <= 0 || rect.height <= 0) return null;

    final normalized = Offset(
      ((bestPoint.dx - rect.left) / rect.width).clamp(0.0, 1.0),
      ((bestPoint.dy - rect.top) / rect.height).clamp(0.0, 1.0),
    );
    return (insertIndex: bestIndex, point: normalized);
  }

  /// 点在线段上的投影；线段退化时返回端点。
  static Offset projectPointOnSegment(Offset point, Offset start, Offset end) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final lengthSquared = dx * dx + dy * dy;
    if (lengthSquared <= 0) return start;
    final rawT =
        ((point.dx - start.dx) * dx + (point.dy - start.dy) * dy) /
        lengthSquared;
    final t = rawT.clamp(0.0, 1.0);
    return Offset(start.dx + dx * t, start.dy + dy * t);
  }

  // ==================== 网格布局 ====================

  /// 按行列生成等分分镜矩形，顺序为从左到右、从上到下（阅读顺序）。
  ///
  /// 单元格小于最小边长、或页面容不下所要求的边距与间隔时返回空列表，
  /// 由调用方提示用户而不是生成一批退化分镜。
  static List<Rect> buildGridRects({
    required Size pageSize,
    required int rows,
    required int columns,
    required double margin,
    required double gutter,
  }) {
    if (pageSize.width <= 0 || pageSize.height <= 0) return const [];

    final safeRows = rows.clamp(1, maxGridDivisions);
    final safeColumns = columns.clamp(1, maxGridDivisions);
    if (safeRows * safeColumns > maxGridCells) return const [];

    final safeMargin = margin.isFinite ? math.max(0.0, margin) : 0.0;
    final safeGutter = gutter.isFinite ? math.max(0.0, gutter) : 0.0;

    final availableWidth =
        pageSize.width - safeMargin * 2 - safeGutter * (safeColumns - 1);
    final availableHeight =
        pageSize.height - safeMargin * 2 - safeGutter * (safeRows - 1);
    if (availableWidth <= 0 || availableHeight <= 0) return const [];

    final cellWidth = availableWidth / safeColumns;
    final cellHeight = availableHeight / safeRows;
    if (cellWidth < StoryboardPanel.minSide ||
        cellHeight < StoryboardPanel.minSide) {
      return const [];
    }

    final rects = <Rect>[];
    for (var row = 0; row < safeRows; row++) {
      for (var column = 0; column < safeColumns; column++) {
        rects.add(
          Rect.fromLTWH(
            safeMargin + column * (cellWidth + safeGutter),
            safeMargin + row * (cellHeight + safeGutter),
            cellWidth,
            cellHeight,
          ),
        );
      }
    }
    return rects;
  }

  /// 在给定区域内找出最大的空白矩形（考虑页边距与分镜间距）。
  ///
  /// 用"最大内接空矩形"的经典扫描：以每条水平分界线为底，向两侧扩张。
  /// 分镜数量通常只有几个到几十个，这个量级下毫秒级完成。
  /// 找出包含 [pointer] 的最大空白矩形（考虑页边距与分镜间距）。
  ///
  /// [pointer] 为空时返回全页能容纳的最大空白。有鼠标位置时只返回包含鼠标
  /// 的那个空白带——鼠标在哪，预览就出现在哪，而不是永远找全局最大的那块。
  static Rect largestEmptyRect({
    required Size pageSize,
    required double margin,
    required double gutter,
    required List<Rect> occupied,
    Offset? pointer,
  }) {
    final pageRect = Rect.fromLTWH(
      margin,
      margin,
      math.max(0, pageSize.width - margin * 2),
      math.max(0, pageSize.height - margin * 2),
    );
    if (pageRect.isEmpty) return pageRect;

    // 收集所有可能作为空白矩形上下边的 y 值。
    final ys = <double>{pageRect.top, pageRect.bottom};
    for (final rect in occupied) {
      ys.add(rect.top - gutter);
      ys.add(rect.bottom + gutter);
    }
    final sortedY = ys.toList()..sort();

    // 收集所有可能作为空白矩形左右边的 x 值。
    final xs = <double>{pageRect.left, pageRect.right};
    for (final rect in occupied) {
      xs.add(rect.left - gutter);
      xs.add(rect.right + gutter);
    }
    final sortedX = xs.toList()..sort();

    // 枚举所有空白带组合，找包含鼠标的、面积最大的那个。
    Rect best = pageRect;
    var bestArea = 0.0;
    for (var yi = 0; yi < sortedY.length - 1; yi++) {
      final top = sortedY[yi];
      final bottom = sortedY[yi + 1];
      if (bottom - top < 1) continue;

      for (var xi = 0; xi < sortedX.length - 1; xi++) {
        final left = sortedX[xi];
        final right = sortedX[xi + 1];
        if (right - left < 1) continue;

        final candidate = Rect.fromLTRB(left, top, right, bottom);
        // 空白矩形：不能与任何分镜的外扩矩形相交。
        var isClear = true;
        for (final rect in occupied) {
          if (candidate.overlaps(rect.inflate(gutter))) {
            isClear = false;
            break;
          }
        }
        if (!isClear) continue;

        // 有鼠标位置时只返回包含鼠标的那个。
        if (pointer != null &&
            !candidate.contains(pointer)) {
          continue;
        }

        final area = candidate.width * candidate.height;
        if (area > bestArea) {
          best = candidate;
          bestArea = area;
        }
      }
    }

    return best;
  }

  /// 让 [rect] 的指定边贴齐到 [anchor]（占用其余空白）。
  ///
  /// 用于「占满剩余空间」：以选中分镜的边为锚，把矩形一直延伸到页边距或
  /// 邻居边缘，中间的空白全部归入选中分镜。
  static Rect extendToAnchor({
    required Rect rect,
    required Rect anchor,
    required bool left,
    required bool top,
    required bool right,
    required bool bottom,
  }) {
    var result = rect;
    if (left) {
      result = Rect.fromLTRB(anchor.left, result.top, result.right, result.bottom);
    }
    if (top) {
      result = Rect.fromLTRB(result.left, anchor.top, result.right, result.bottom);
    }
    if (right) {
      result = Rect.fromLTRB(result.left, result.top, anchor.right, result.bottom);
    }
    if (bottom) {
      result = Rect.fromLTRB(result.left, result.top, result.right, anchor.bottom);
    }
    return result;
  }

  /// 让 [rect] 的指定边贴齐到 [anchor]（占用其余空白）。
  ///
  /// 用于「占满剩余空间」：以选中分镜的边为锚，把矩形一直延伸到页边距或
    /// 页面坐标下的点落在哪个分镜上。  /// 页面坐标下的点落在哪个分镜上。
  ///
  /// 按传入顺序（通常是叠放顺序的倒序）返回第一个命中的分镜 id，
  /// 让上层分镜优先被选中。
  static String? hitTestPanels(
    List<StoryboardPanel> panelsInHitOrder,
    Offset point,
  ) {
    for (final panel in panelsInHitOrder) {
      if (panel.isPolygon) {
        if (containsPoint(panel.points, panel.rect, point)) return panel.id;
      } else if (panel.rect.contains(point)) {
        return panel.id;
      }
    }
    return null;
  }
}

/// 间距约束下的拖拽边界。
///
/// 页边距决定分镜能贴到离页边多近，分镜间距决定两块之间至少要留多大空隙。
/// 它们是**拖拽的限制**而不是排版生成器：拖动与缩放时不允许越过，
/// 已经摆好的版面不会因为改间距而被自动重排。
class StoryboardSpacingRules {
  const StoryboardSpacingRules({
    required this.pageSize,
    required this.margin,
    required this.gutter,
    required this.occupied,
  });

  /// 浮点误差容忍度：刚好贴着边界时不应被判成越界。
  static const double tolerance = 0.5;

  final Size pageSize;
  final double margin;
  final double gutter;

  /// 其它分镜的矩形；不含正在被拖动的那一个。
  final List<Rect> occupied;

  /// 矩形是否完全落在页边距以内，并与其它分镜保持足够的空隙。
  bool allows(Rect rect) {
    if (rect.left < margin - tolerance) return false;
    if (rect.top < margin - tolerance) return false;
    if (rect.right > pageSize.width - margin + tolerance) return false;
    if (rect.bottom > pageSize.height - margin + tolerance) return false;

    for (final other in occupied) {
      // inflate(gutter) 后仍相交，说明两块之间的空隙小于 gutter。
      if (rect.overlaps(other.inflate(gutter - tolerance))) return false;
    }
    return true;
  }

  /// 求一个既尽量贴近 [candidate] 又满足约束的位置。
  ///
  /// 越界时先尝试只沿一个轴移动，这样沿着边界或另一个分镜滑动仍然顺手；
  /// 两个轴都不行就退回上一个合法位置，表现为"被边界挡住"。
  ///
  /// [lastValid] 本身已经违规时（例如新建后被别的分镜压住）直接放行，
  /// 否则分镜会被永久卡死在原地。
  Rect resolve({required Rect candidate, required Rect lastValid}) {
    if (!allows(lastValid)) return candidate;
    if (allows(candidate)) return candidate;
    if (StoryboardGeometry.rectsNearlyEqual(candidate, lastValid)) {
      return lastValid;
    }

    final xOnly = Rect.fromLTWH(
      candidate.left,
      lastValid.top,
      candidate.width,
      candidate.height,
    );
    if (allows(xOnly)) return xOnly;

    final yOnly = Rect.fromLTWH(
      lastValid.left,
      candidate.top,
      candidate.width,
      candidate.height,
    );
    if (allows(yOnly)) return yOnly;

    return lastValid;
  }

  /// 把矩形收敛到最近的合法位置。
  ///
  /// [reference] 是上一帧的合法位置，用来判断"从哪一侧接近挡块"。必须按来向
  /// 判定而不是按"哪边推得更近"：后者在拖过挡块中心时会把最近侧从左翻到右，
  /// 分镜一帧内横穿挡块；候选停在中心附近时更会逐帧来回翻，表现为闪烁。
  Rect clamp(Rect candidate, {Rect? reference}) {
    var rect = _clampToMargins(candidate);
    for (final other in occupied) {
      final blocked = other.inflate(gutter - tolerance);
      if (!rect.overlaps(blocked)) continue;
      rect = _stopAt(rect, blocked, reference);
    }
    return rect;
  }

  /// 缩放约束：**每条被拖动的边独立收敛**，互不牵连。
  ///
  /// 拖一个角等于同时移动两条边；它们是两个独立的轴。一条边碰壁时只停那
  /// 一条边，另一条必须继续跟手——把整个矩形交给一个约束去平移，会让没碰壁
  /// 的边也被拖着走，这就是之前"越缩越乱、四条边都卡住"的根源。
  ///
  /// 页边距是每条边的硬边界；分镜间距只在"这条边正在朝那个邻居压过去"时把
  /// 边停住，且按来向判定，不会翻面。
  Rect clampResize({
    required Rect candidate,
    Rect? reference,
    required bool movingLeft,
    required bool movingTop,
  }) {
    var left = candidate.left;
    var top = candidate.top;
    var right = candidate.right;
    var bottom = candidate.bottom;

    // ---- 页边距：每条边独立的硬边界 ----
    final maxRight = math.max(margin, pageSize.width - margin);
    final maxBottom = math.max(margin, pageSize.height - margin);
    if (movingLeft) {
      left = left.clamp(margin, maxRight);
    } else {
      right = right.clamp(margin, maxRight);
    }
    if (movingTop) {
      top = top.clamp(margin, maxBottom);
    } else {
      bottom = bottom.clamp(margin, maxBottom);
    }

    // ---- 分镜间距：只挡正在靠近的那个方向，按来向判定不翻面 ----
    for (final other in occupied) {
      final blocked = other.inflate(gutter - tolerance);
      if (!candidate.overlaps(blocked)) continue;
      // 参考位置本就压着这个邻居时不要再去"纠正"：分镜彼此相邻是常态，
      // 若按间距收缩只会越缩越小；先允许拖出去，之后自然满足约束。
      if (reference != null && reference.overlaps(blocked)) continue;

      if (movingLeft &&
          facing(candidate, other, true) &&
          blocked.right <= right + tolerance &&
          left < blocked.right) {
        left = blocked.right;
      }
      if (!movingLeft &&
          facing(candidate, other, true) &&
          blocked.left >= left - tolerance &&
          right > blocked.left) {
        right = blocked.left;
      }

      if (movingTop &&
          facing(candidate, other, false) &&
          blocked.bottom <= bottom + tolerance &&
          top < blocked.bottom) {
        top = blocked.bottom;
      }
      if (!movingTop &&
          facing(candidate, other, false) &&
          blocked.top >= top - tolerance &&
          bottom > blocked.top) {
        bottom = blocked.top;
      }
    }

    // ---- 最小边长：把被拖动的边停住，不允许翻转 ----
    const minSide = 8.0;
    if (right - left < minSide) {
      if (movingLeft) {
        left = right - minSide;
      } else {
        right = left + minSide;
      }
    }
    if (bottom - top < minSide) {
      if (movingTop) {
        top = bottom - minSide;
      } else {
        bottom = top + minSide;
      }
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// 收进页边距以内；页面容不下时退回页边距位置，避免产生负尺寸。
  Rect _clampToMargins(Rect rect) {
    if (pageSize.width <= 0 || pageSize.height <= 0) return rect;
    final maxLeft = pageSize.width - margin - rect.width;
    final maxTop = pageSize.height - margin - rect.height;
    final left = rect.left.clamp(
      margin,
      maxLeft < margin ? margin : maxLeft,
    );
    final top = rect.top.clamp(margin, maxTop < margin ? margin : maxTop);
    return Rect.fromLTWH(left, top, rect.width, rect.height);
  }

  /// 让矩形停在 [blocked] 的哪一侧。
  ///
  /// 优先按 [reference] 的来向判定；参考位置缺失或本身已重叠时，退回最近的一侧。
  Rect _stopAt(Rect rect, Rect blocked, Rect? reference) {
    // 不要求参考矩形与当前矩形同尺寸：缩放时尺寸每帧都在变，一旦要求相同，
    // 判断就会永远失败并退回"最近一侧"，把翻面问题重新引回来。
    if (reference != null) {
      if (reference.right <= blocked.left + tolerance) {
        return _clampToMargins(
          Rect.fromLTWH(blocked.left - rect.width, rect.top, rect.width, rect.height),
        );
      }
      if (reference.left >= blocked.right - tolerance) {
        return _clampToMargins(
          Rect.fromLTWH(blocked.right, rect.top, rect.width, rect.height),
        );
      }
      if (reference.bottom <= blocked.top + tolerance) {
        return _clampToMargins(
          Rect.fromLTWH(rect.left, blocked.top - rect.height, rect.width, rect.height),
        );
      }
      if (reference.top >= blocked.bottom - tolerance) {
        return _clampToMargins(
          Rect.fromLTWH(rect.left, blocked.bottom, rect.width, rect.height),
        );
      }
    }
    return _nearestSide(rect, blocked);
  }

  /// 参考位置不可用时的兜底：推到最近的一侧。
  Rect _nearestSide(Rect rect, Rect blocked) {
    final leftDelta = blocked.left - rect.width - rect.left;
    final rightDelta = blocked.right - rect.left;
    final topDelta = blocked.top - rect.height - rect.top;
    final bottomDelta = blocked.bottom - rect.top;

    final horizontal = leftDelta.abs() <= rightDelta.abs()
        ? leftDelta
        : rightDelta;
    final vertical = topDelta.abs() <= bottomDelta.abs() ? topDelta : bottomDelta;

    final moved = horizontal.abs() <= vertical.abs()
        ? rect.shift(Offset(horizontal, 0))
        : rect.shift(Offset(0, vertical));
    return _clampToMargins(moved);
  }

  /// 斜对角的邻居不该挡路。
  ///
  /// 上方分镜可能只与当前分镜的顶部重叠一条几十像素的缝，若只按"相交"判定，
  /// 拖动或缩放当前分镜的左边缘时会被这条缝拦住——而那一大片区域其实是空白。
  /// 要求垂直于拖动方向的投影重叠达到面板自身跨度的 50%，才算真正正对的邻居。
  static const double facingThreshold = 0.5;

  /// [other] 是否正对着 [rect] 的这条边。
  ///
  /// [horizontalDrag] 为真表示在拖左/右边缘，此时看垂直方向的投影重叠。
  bool facing(Rect rect, Rect other, bool horizontalDrag) {
    final overlapTop = math.max(rect.top, other.top);
    final overlapBottom = math.min(rect.bottom, other.bottom);
    final overlapLeft = math.max(rect.left, other.left);
    final overlapRight = math.min(rect.right, other.right);
    final overlap = horizontalDrag
        ? overlapBottom - overlapTop
        : overlapRight - overlapLeft;
    if (overlap <= 0) return false;

    final span = horizontalDrag ? rect.height : rect.width;
    return span > 0 && overlap >= span * facingThreshold;
  }

  /// 与当前页面对应的约束；[excludeId] 用于排除正在拖动的分镜。
  static StoryboardSpacingRules forPage({
    required StoryboardPage page,
    required String? excludeId,
  }) {
    return StoryboardSpacingRules(
      pageSize: Size(page.width.toDouble(), page.height.toDouble()),
      margin: page.margin,
      gutter: page.gutter,
      occupied: [
        for (final panel in page.panels)
          if (panel.id != excludeId) panel.rect,
      ],
    );
  }
}
