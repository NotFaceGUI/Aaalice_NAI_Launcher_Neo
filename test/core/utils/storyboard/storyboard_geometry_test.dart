import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/utils/storyboard/storyboard_geometry.dart';
import 'package:nai_launcher/data/models/storyboard/storyboard_panel.dart';
import 'package:nai_launcher/data/models/storyboard/storyboard_panel_shape.dart';

void main() {
  final stamp = DateTime.fromMillisecondsSinceEpoch(1700000000000);

  StoryboardPanel panel({
    required String id,
    StoryboardPanelShape shape = StoryboardPanelShape.rect,
    double x = 0,
    double y = 0,
    double width = 100,
    double height = 100,
    List<Offset> points = const [],
    int zOrder = 0,
    int order = 1,
  }) {
    return StoryboardPanel(
      id: id,
      order: order,
      zOrder: zOrder,
      shape: shape,
      x: x,
      y: y,
      width: width,
      height: height,
      points: points,
      createdAt: stamp,
      updatedAt: stamp,
    );
  }

  /// 顺时针的 L 形凹多边形，用于验证射线法在凹角处的行为。
  const lShape = [
    Offset(0, 0),
    Offset(1, 0),
    Offset(1, 0.5),
    Offset(0.5, 0.5),
    Offset(0.5, 1),
    Offset(0, 1),
  ];

  group('normalizeRect', () {
    test('把超出页面的尺寸收进页面', () {
      final rect = StoryboardGeometry.normalizeRect(
        const Rect.fromLTWH(-50, -50, 2000, 2000),
        pageSize: const Size(1000, 800),
      );
      expect(rect, const Rect.fromLTWH(0, 0, 1000, 800));
    });

    test('保证最小边长', () {
      final rect = StoryboardGeometry.normalizeRect(
        const Rect.fromLTWH(10, 10, 1, 1),
        pageSize: const Size(1000, 800),
      );
      expect(rect.width, StoryboardPanel.minSide);
      expect(rect.height, StoryboardPanel.minSide);
    });

    test('位置被钳制在页面内', () {
      final rect = StoryboardGeometry.normalizeRect(
        const Rect.fromLTWH(990, 790, 100, 100),
        pageSize: const Size(1000, 800),
      );
      expect(rect.right, lessThanOrEqualTo(1000));
      expect(rect.bottom, lessThanOrEqualTo(800));
    });

    test('非有限输入退回最小矩形而不是产生 NaN', () {
      final rect = StoryboardGeometry.normalizeRect(
        const Rect.fromLTWH(double.nan, double.infinity, double.nan, 0),
        pageSize: const Size(1000, 800),
      );
      expect(rect.left.isFinite, isTrue);
      expect(rect.top.isFinite, isTrue);
      expect(rect.width, StoryboardPanel.minSide);
    });

    test('页面尺寸非法时仍返回可用矩形', () {
      final rect = StoryboardGeometry.normalizeRect(
        const Rect.fromLTWH(0, 0, 100, 100),
        pageSize: Size.zero,
      );
      expect(rect.width, StoryboardPanel.minSide);
    });
  });

  group('多边形归一化', () {
    test('由像素顶点反推外接矩形与归一化顶点', () {
      final result = StoryboardGeometry.fitPolygonToPixelBounds(const [
        Offset(100, 200),
        Offset(300, 200),
        Offset(200, 400),
      ]);
      expect(result.rect, const Rect.fromLTWH(100, 200, 200, 200));
      expect(result.points[0], const Offset(0, 0));
      expect(result.points[1], const Offset(1, 0));
      expect(result.points[2], const Offset(0.5, 1));
    });

    test('退化顶点用最小边长撑开，避免除零', () {
      final result = StoryboardGeometry.fitPolygonToPixelBounds(const [
        Offset(50, 50),
        Offset(50, 50),
        Offset(50, 50),
      ]);
      expect(result.rect.width, StoryboardPanel.minSide);
      for (final point in result.points) {
        expect(point.dx.isFinite, isTrue);
        expect(point.dy.isFinite, isTrue);
      }
    });

    test('顶点不足时返回空顶点', () {
      final result = StoryboardGeometry.fitPolygonToPixelBounds(const [
        Offset(0, 0),
        Offset(1, 1),
      ]);
      expect(result.points, isEmpty);
    });

    test('归一化顶点可按矩形还原到像素空间', () {
      final pixels = StoryboardGeometry.toPixelPoints(
        const [Offset(0, 0), Offset(0.5, 0.5), Offset(1, 1)],
        const Rect.fromLTWH(100, 200, 400, 600),
      );
      expect(pixels[0], const Offset(100, 200));
      expect(pixels[1], const Offset(300, 500));
      expect(pixels[2], const Offset(500, 800));
    });
  });

  group('面板路径', () {
    test('矩形分镜生成矩形路径', () {
      final path = StoryboardGeometry.buildPanelPath(
        rect: const Rect.fromLTWH(10, 20, 100, 50),
        points: const [],
        polygon: false,
      );
      expect(path.getBounds(), const Rect.fromLTWH(10, 20, 100, 50));
    });

    test('多边形分镜生成顶点路径', () {
      final path = StoryboardGeometry.buildPanelPath(
        rect: const Rect.fromLTWH(0, 0, 100, 100),
        points: const [Offset(0, 0), Offset(1, 0), Offset(0.5, 1)],
        polygon: true,
      );
      expect(path.getBounds(), const Rect.fromLTRB(0, 0, 100, 100));
    });

    test('多边形顶点不足时退回矩形路径', () {
      final path = StoryboardGeometry.buildPanelPath(
        rect: const Rect.fromLTWH(0, 0, 100, 100),
        points: const [Offset(0, 0), Offset(1, 1)],
        polygon: true,
      );
      expect(path.getBounds(), const Rect.fromLTWH(0, 0, 100, 100));
    });
  });

  group('命中测试', () {
    test('矩形分镜按矩形命中', () {
      final hit = StoryboardGeometry.containsPoint(
        const [],
        const Rect.fromLTWH(0, 0, 100, 100),
        const Offset(50, 50),
      );
      expect(hit, isTrue);
      expect(
        StoryboardGeometry.containsPoint(
          const [],
          const Rect.fromLTWH(0, 0, 100, 100),
          const Offset(150, 50),
        ),
        isFalse,
      );
    });

    test('凹多边形的凹角区域不算命中', () {
      const rect = Rect.fromLTWH(0, 0, 100, 100);
      expect(
        StoryboardGeometry.containsPoint(lShape, rect, const Offset(25, 75)),
        isTrue,
      );
      expect(
        StoryboardGeometry.containsPoint(lShape, rect, const Offset(75, 75)),
        isFalse,
      );
    });

    test('顶点命中返回最近的下标', () {
      const rect = Rect.fromLTWH(0, 0, 100, 100);
      const points = [Offset(0, 0), Offset(1, 0), Offset(0.5, 1)];
      expect(
        StoryboardGeometry.hitTestVertex(
          normalizedPoints: points,
          rect: rect,
          point: const Offset(2, 2),
        ),
        0,
      );
      expect(
        StoryboardGeometry.hitTestVertex(
          normalizedPoints: points,
          rect: rect,
          point: const Offset(48, 98),
        ),
        2,
      );
      expect(
        StoryboardGeometry.hitTestVertex(
          normalizedPoints: points,
          rect: rect,
          point: const Offset(50, 50),
        ),
        -1,
      );
    });

    test('边命中返回插入下标与投影点', () {
      const rect = Rect.fromLTWH(0, 0, 100, 100);
      const points = [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)];
      final hit = StoryboardGeometry.hitTestEdge(
        normalizedPoints: points,
        rect: rect,
        point: const Offset(50, 2),
      );
      expect(hit, isNotNull);
      expect(hit!.insertIndex, 1);
      expect(hit.point.dx, closeTo(0.5, 0.0001));
      expect(hit.point.dy, closeTo(0, 0.0001));
    });

    test('边命中在超过半径时返回 null', () {
      const rect = Rect.fromLTWH(0, 0, 100, 100);
      const points = [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)];
      expect(
        StoryboardGeometry.hitTestEdge(
          normalizedPoints: points,
          rect: rect,
          point: const Offset(50, 50),
        ),
        isNull,
      );
    });

    test('投影点被钳制在线段内', () {
      expect(
        StoryboardGeometry.projectPointOnSegment(
          const Offset(150, 0),
          const Offset(0, 0),
          const Offset(100, 0),
        ),
        const Offset(100, 0),
      );
      expect(
        StoryboardGeometry.projectPointOnSegment(
          const Offset(5, 5),
          const Offset(5, 5),
          const Offset(5, 5),
        ),
        const Offset(5, 5),
      );
    });

    test('hitTestPanels 按传入顺序优先命中上层', () {
      final panels = [
        panel(id: 'top', x: 0, y: 0, width: 100, height: 100, zOrder: 1),
        panel(id: 'bottom', x: 50, y: 50, width: 100, height: 100),
      ];
      expect(StoryboardGeometry.hitTestPanels(panels, const Offset(60, 60)), 'top');
      expect(StoryboardGeometry.hitTestPanels(panels, const Offset(10, 10)), 'top');
      expect(
        StoryboardGeometry.hitTestPanels(panels, const Offset(140, 140)),
        'bottom',
      );
      expect(
        StoryboardGeometry.hitTestPanels(panels, const Offset(500, 500)),
        isNull,
      );
    });

    test('hitTestPanels 对多边形分镜使用顶点形状', () {
      final panels = [
        panel(
          id: 'triangle',
          shape: StoryboardPanelShape.polygon,
          x: 0,
          y: 0,
          width: 100,
          height: 100,
          points: const [Offset(0, 0), Offset(1, 0), Offset(0, 1)],
        ),
      ];
      // (90, 10) 在三角形之外，但仍在外接矩形之内。
      expect(
        StoryboardGeometry.hitTestPanels(panels, const Offset(90, 90)),
        isNull,
      );
      expect(
        StoryboardGeometry.hitTestPanels(panels, const Offset(10, 10)),
        'triangle',
      );
    });
  });

  group('buildGridRects', () {
    test('按阅读顺序生成等分矩形', () {
      final rects = StoryboardGeometry.buildGridRects(
        pageSize: const Size(1000, 600),
        rows: 2,
        columns: 3,
        margin: 10,
        gutter: 10,
      );
      expect(rects.length, 6);
      expect(rects.first, const Rect.fromLTWH(10, 10, 320, 285));
      expect(rects[1].left, 340);
      expect(rects[2].left, 670);
      expect(rects[3].top, 305);
      // 最后一行最后一列贴住右下边距。
      expect(rects.last.right, closeTo(990, 0.0001));
      expect(rects.last.bottom, closeTo(590, 0.0001));
    });

    test('单元格小于最小边长时返回空列表', () {
      expect(
        StoryboardGeometry.buildGridRects(
          pageSize: const Size(100, 100),
          rows: 2,
          columns: 2,
          margin: 60,
          gutter: 10,
        ),
        isEmpty,
      );
    });

    test('超过单元格上限时返回空列表', () {
      expect(
        StoryboardGeometry.buildGridRects(
          pageSize: const Size(4000, 4000),
          rows: 12,
          columns: 12,
          margin: 0,
          gutter: 0,
        ),
        isEmpty,
      );
    });

    test('行列数被钳制到合法区间', () {
      final single = StoryboardGeometry.buildGridRects(
        pageSize: const Size(1000, 800),
        rows: 0,
        columns: -3,
        margin: 0,
        gutter: 0,
      );
      expect(single.length, 1);
      expect(single.single, const Rect.fromLTWH(0, 0, 1000, 800));
    });

    test('负边距与负间隔被归零', () {
      final rects = StoryboardGeometry.buildGridRects(
        pageSize: const Size(1000, 800),
        rows: 2,
        columns: 2,
        margin: -100,
        gutter: -50,
      );
      expect(rects.length, 4);
      expect(rects.first, const Rect.fromLTWH(0, 0, 500, 400));
    });

    test('页面尺寸非法时返回空列表', () {
      expect(
        StoryboardGeometry.buildGridRects(
          pageSize: Size.zero,
          rows: 1,
          columns: 1,
          margin: 0,
          gutter: 0,
        ),
        isEmpty,
      );
    });
  });

  group('rectsNearlyEqual', () {
    test('在容差内视为相等', () {
      expect(
        StoryboardGeometry.rectsNearlyEqual(
          const Rect.fromLTWH(0, 0, 100, 100),
          const Rect.fromLTWH(0.005, 0, 100.005, 100),
        ),
        isTrue,
      );
      expect(
        StoryboardGeometry.rectsNearlyEqual(
          const Rect.fromLTWH(0, 0, 100, 100),
          const Rect.fromLTWH(0.5, 0, 100, 100),
        ),
        isFalse,
      );
    });
  });

  group('间距约束', () {
    const pageSize = Size(1000, 1000);

    StoryboardSpacingRules rules({
      double margin = 20,
      double gutter = 10,
      List<Rect> occupied = const [],
    }) => StoryboardSpacingRules(
      pageSize: pageSize,
      margin: margin,
      gutter: gutter,
      occupied: occupied,
    );

    test('页边距以内允许，贴边也允许', () {
      final subject = rules();
      expect(subject.allows(const Rect.fromLTWH(20, 20, 100, 100)), isTrue);
      expect(subject.allows(const Rect.fromLTWH(0, 0, 100, 100)), isFalse);
      expect(subject.allows(const Rect.fromLTWH(0, 20, 100, 100)), isFalse);
      expect(
        subject.allows(const Rect.fromLTWH(890, 890, 100, 100)),
        isFalse,
      );
    });

    test('与其它分镜必须留出分镜间距', () {
      final subject = rules(occupied: const [Rect.fromLTWH(500, 20, 100, 100)]);
      // 空隙正好等于 gutter：允许
      expect(subject.allows(const Rect.fromLTWH(390, 20, 100, 100)), isTrue);
      // 空隙小于 gutter：拒绝
      expect(subject.allows(const Rect.fromLTWH(395, 20, 100, 100)), isFalse);
      // 重叠：拒绝
      expect(subject.allows(const Rect.fromLTWH(550, 20, 100, 100)), isFalse);
    });

    test('合法位置直接采用候选值', () {
      final subject = rules();
      const lastValid = Rect.fromLTWH(100, 100, 100, 100);
      const candidate = Rect.fromLTWH(200, 200, 100, 100);
      expect(subject.resolve(candidate: candidate, lastValid: lastValid), candidate);
    });

    test('越界时退回上一个合法位置', () {
      final subject = rules();
      const lastValid = Rect.fromLTWH(20, 20, 100, 100);
      const candidate = Rect.fromLTWH(-50, -50, 100, 100);
      expect(subject.resolve(candidate: candidate, lastValid: lastValid), lastValid);
    });

    test('沿单个轴仍然可移动，方便贴着边界滑行', () {
      final subject = rules();
      const lastValid = Rect.fromLTWH(20, 100, 100, 100);
      // x 越界、y 合法：只采用 y 方向的位移
      const candidate = Rect.fromLTWH(-80, 300, 100, 100);
      final resolved = subject.resolve(
        candidate: candidate,
        lastValid: lastValid,
      );
      expect(resolved.left, lastValid.left);
      expect(resolved.top, 300);
    });

    group('缩放约束（clampResize）', () {
      test('被拖动的边可以向内收，不只是放大', () {
        // 右边缘往左收 200：必须允许。
        final clamped = rules().clampResize(
          candidate: const Rect.fromLTRB(100, 100, 300, 400),
          movingLeft: false,
          movingTop: false,
        );
        expect(clamped.right, 300);
        expect(clamped.left, 100);
        expect(clamped.bottom, 400);
      });

      test('对面两条边保持不动', () {
        final clamped = rules().clampResize(
          candidate: const Rect.fromLTRB(60, 80, 500, 450),
          movingLeft: true,
          movingTop: true,
        );
        expect(clamped.right, 500);
        expect(clamped.bottom, 450);
      });

      test('被拖动的边被夹在页边距以内', () {
        final clamped = rules().clampResize(
          candidate: const Rect.fromLTRB(-200, -100, 500, 400),
          movingLeft: true,
          movingTop: true,
        );
        expect(clamped.left, 20);
        expect(clamped.top, 20);
      });

      test('起始位置已压着邻居时不再收缩，允许放大', () {
        // 分镜彼此相邻是常态：此时按间距收缩只会越缩越小。
        final subject = rules(occupied: const [Rect.fromLTWH(290, 100, 200, 200)]);
        final clamped = subject.clampResize(
          candidate: const Rect.fromLTRB(150, 100, 300, 300),
          reference: const Rect.fromLTWH(100, 100, 200, 200),
          movingLeft: false,
          movingTop: false,
        );
        // 允许向右放大，不被左侧已贴合的邻居挡住。
        expect(clamped.right, 300);
        expect(clamped.left, 150);
      });

      test('分镜间距也钳缩放：被拖的边压进邻居时被挡住', () {
        // 分镜 [120,300]，邻居在左侧 [60,180]，间距 10 → 挡块右缘 189.5。
        final subject = rules(occupied: const [Rect.fromLTWH(60, 100, 120, 200)]);
        final clamped = subject.clampResize(
          candidate: const Rect.fromLTRB(120, 100, 300, 300),
          movingLeft: true,
          movingTop: false,
        );
        expect(clamped.left, closeTo(189.5, 0.5));
        // 对面那条边不动。
        expect(clamped.right, 300);
      });

      test('向远离邻居的方向缩放不受影响', () {
        final subject = rules(occupied: const [Rect.fromLTWH(-100, 100, 200, 200)]);
        final clamped = subject.clampResize(
          candidate: const Rect.fromLTRB(150, 100, 300, 300),
          movingLeft: true,
          movingTop: false,
        );
        expect(clamped.left, 150);
      });

      test('最小边长防止翻转', () {
        final clamped = rules().clampResize(
          candidate: const Rect.fromLTRB(100, 100, 105, 400),
          movingLeft: false,
          movingTop: false,
        );
        expect(clamped.right - clamped.left, greaterThanOrEqualTo(8));
      });
    });

    test('快速拖动时收敛到边界，而不是卡在禁区之前', () {
      final subject = rules();
      // 一帧就从合法区跨到页外：必须收敛到页边距处，而不是退回原位。
      final clamped = subject.clamp(const Rect.fromLTWH(-500, -500, 100, 100));
      expect(clamped.left, 20);
      expect(clamped.top, 20);
      expect(clamped.width, 100);
    });

    test('被其它分镜挡住时贴着它停住', () {
      final subject = rules(occupied: const [Rect.fromLTWH(300, 20, 100, 100)]);
      // 从左侧快速压过去，应停在分镜间距之外。
      final clamped = subject.clamp(const Rect.fromLTWH(280, 20, 100, 100));
      expect(clamped.right, lessThanOrEqualTo(300 - 10 + 0.5));
      expect(clamped.top, 20);
    });

    test('按来向停住：拖过挡块中心也不会横穿或来回跳', () {
      final subject = rules(occupied: const [Rect.fromLTWH(300, 20, 100, 100)]);
      const fromLeft = Rect.fromLTWH(200, 20, 80, 80);
      // 候选已经越过挡块中心（本该翻到右侧），但来向是左，必须仍停在左侧。
      final clamped = subject.clamp(
        const Rect.fromLTWH(340, 20, 80, 80),
        reference: fromLeft,
      );
      expect(clamped.right, closeTo(300 - 10 + 0.5, 1.0));
    });

    test('从右侧接近时停在挡块右边', () {
      final subject = rules(occupied: const [Rect.fromLTWH(300, 20, 100, 100)]);
      const fromRight = Rect.fromLTWH(420, 20, 80, 80);
      final clamped = subject.clamp(
        const Rect.fromLTWH(310, 20, 80, 80),
        reference: fromRight,
      );
      expect(clamped.left, greaterThanOrEqualTo(400 - 0.5));
    });

    test('缩放变大时同样按来向停住', () {
      final subject = rules(occupied: const [Rect.fromLTWH(400, 20, 100, 100)]);
      // 从左往右放大：参考更小但仍在左侧，必须停在左边而不是翻过去。
      const growing = Rect.fromLTWH(100, 20, 200, 200);
      final clamped = subject.clamp(
        const Rect.fromLTWH(100, 20, 320, 200),
        reference: growing,
      );
      expect(clamped.right, closeTo(400 - 10 + 0.5, 1.0));
    });

    test('缩放越界同样收敛到页边距', () {
      final subject = rules();
      final clamped = subject.clamp(const Rect.fromLTWH(20, 20, 5000, 5000));
      expect(clamped.left, 20);
      expect(clamped.top, 20);
    });

    test('当前位置本就违规时放行，避免分镜被永久卡死', () {
      final subject = rules(
        occupied: const [Rect.fromLTWH(0, 0, 1000, 1000)],
      );
      const stuck = Rect.fromLTWH(100, 100, 100, 100);
      const candidate = Rect.fromLTWH(400, 400, 100, 100);
      expect(subject.resolve(candidate: candidate, lastValid: stuck), candidate);
    });
  });
}
