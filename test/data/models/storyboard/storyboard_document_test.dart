import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/storyboard/storyboard_document.dart';
import 'package:nai_launcher/data/models/storyboard/storyboard_fit_mode.dart';
import 'package:nai_launcher/data/models/storyboard/storyboard_page.dart';
import 'package:nai_launcher/data/models/storyboard/storyboard_page_background.dart';
import 'package:nai_launcher/data/models/storyboard/storyboard_panel.dart';
import 'package:nai_launcher/data/models/storyboard/storyboard_panel_shape.dart';
import 'package:nai_launcher/data/models/storyboard/storyboard_panel_status.dart';
import 'package:nai_launcher/data/models/storyboard/storyboard_resolution.dart';

void main() {
  final stamp = DateTime.fromMillisecondsSinceEpoch(1700000000000);

  StoryboardPanel panel({
    String id = 'panel-1',
    int order = 1,
    int zOrder = 0,
    StoryboardPanelShape shape = StoryboardPanelShape.rect,
    double x = 96,
    double y = 96,
    double width = 1120,
    double height = 1480,
    List<Offset> points = const [],
    StoryboardResolution resolution = const StoryboardResolution.auto(),
    StoryboardFitMode fit = StoryboardFitMode.cover,
    String prompt = '1girl, rooftop',
    List<String> images = const [],
    String? selectedImage,
    StoryboardPanelStatus status = StoryboardPanelStatus.empty,
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
      resolution: resolution,
      fit: fit,
      prompt: prompt,
      images: images,
      selectedImage: selectedImage,
      status: status,
      createdAt: stamp,
      updatedAt: stamp,
    );
  }

  StoryboardPage page({
    String id = 'page-1',
    String name = '第 1 页',
    int width = 2480,
    int height = 3508,
    StoryboardPageBackground background = const StoryboardPageBackground(),
    List<StoryboardPanel> panels = const [],
  }) {
    return StoryboardPage(
      id: id,
      name: name,
      width: width,
      height: height,
      background: background,
      panels: panels,
      createdAt: stamp,
      updatedAt: stamp,
    );
  }

  group('StoryboardDocument 往返', () {
    test('完整文档编解码后保持字段', () {
      final document = StoryboardDocument.singlePage(
        page(
          background: const StoryboardPageBackground(
            kind: StoryboardBackgroundKind.image,
            imagePath: 'storyboard/bg/page-1.png',
            fit: StoryboardFitMode.contain,
          ),
          panels: [
            panel(
              shape: StoryboardPanelShape.polygon,
              points: const [
                Offset(0, 0),
                Offset(1, 0),
                Offset(1, 1),
                Offset(0.5, 0.82),
                Offset(0, 1),
              ],
              resolution: const StoryboardResolution.explicit(
                width: 1088,
                height: 1472,
              ),
              images: const ['2026-09-29/123456.png'],
              selectedImage: '2026-09-29/123456.png',
              status: StoryboardPanelStatus.done,
            ),
          ],
        ),
      );

      final restored = StoryboardDocument.fromJson(document.toJson());

      expect(restored, isNotNull);
      expect(restored!.activePageId, 'page-1');
      final restoredPage = restored.activePage!;
      expect(restoredPage.width, 2480);
      expect(restoredPage.height, 3508);
      expect(restoredPage.background.kind, StoryboardBackgroundKind.image);
      expect(restoredPage.background.imagePath, 'storyboard/bg/page-1.png');
      expect(restoredPage.background.fit, StoryboardFitMode.contain);

      final restoredPanel = restoredPage.panels.single;
      expect(restoredPanel.shape, StoryboardPanelShape.polygon);
      expect(restoredPanel.points.length, 5);
      expect(restoredPanel.points.last, const Offset(0, 1));
      expect(restoredPanel.resolution.isAuto, isFalse);
      expect(restoredPanel.resolution.width, 1088);
      expect(restoredPanel.resolution.height, 1472);
      expect(restoredPanel.selectedImage, '2026-09-29/123456.png');
      expect(restoredPanel.status, StoryboardPanelStatus.done);
    });

    test('矩形分镜不写入 points', () {
      final document = StoryboardDocument.singlePage(
        page(panels: [panel()]),
      );
      final json = document.toJson();
      final panels = (json['pages'] as List).first['panels'] as List;
      expect((panels.first as Map).containsKey('points'), isFalse);
    });

    test('auto 分辨率只写 mode', () {
      const resolution = StoryboardResolution.auto();
      expect(resolution.toJson(), {'mode': 'auto'});
    });
  });

  group('StoryboardDocument 容错', () {
    test('未知版本返回 null', () {
      expect(
        StoryboardDocument.fromJson({
          'version': StoryboardDocument.currentVersion + 1,
          'pages': [
            {'id': 'p', 'width': 100, 'height': 100},
          ],
        }),
        isNull,
      );
    });

    test('缺少版本或非 Map 返回 null', () {
      expect(StoryboardDocument.fromJson(null), isNull);
      expect(StoryboardDocument.fromJson('nope'), isNull);
      expect(
        StoryboardDocument.fromJson({
          'pages': [
            {'id': 'p', 'width': 100, 'height': 100},
          ],
        }),
        isNull,
      );
    });

    test('没有可用页面时返回 null 而不是空文档', () {
      expect(
        StoryboardDocument.fromJson({
          'version': StoryboardDocument.currentVersion,
          'pages': [
            {'width': 100, 'height': 100},
          ],
        }),
        isNull,
      );
    });

    test('缺失或重复的页面 id 被丢弃', () {
      final document = StoryboardDocument.fromJson({
        'version': StoryboardDocument.currentVersion,
        'activePageId': 'missing',
        'pages': [
          {'id': 'a', 'width': 800, 'height': 600},
          {'id': 'a', 'width': 800, 'height': 600},
          {'id': 'b', 'width': 800, 'height': 600},
        ],
      });

      expect(document, isNotNull);
      expect(document!.pages.length, 2);
      // activePageId 指向不存在的页时回落到第一页。
      expect(document.activePageId, 'a');
    });

    test('页面尺寸低于下限时该页被丢弃', () {
      final document = StoryboardDocument.fromJson({
        'version': StoryboardDocument.currentVersion,
        'pages': [
          {'id': 'a', 'width': 10, 'height': 10},
          {'id': 'b', 'width': 640, 'height': 480},
        ],
      });
      expect(document!.pages.single.id, 'b');
    });

    test('页面尺寸超过上限时收敛到上限', () {
      final document = StoryboardDocument.fromJson({
        'version': StoryboardDocument.currentVersion,
        'pages': [
          {'id': 'a', 'width': 999999, 'height': 999999},
        ],
      });
      expect(document!.pages.single.width, StoryboardPage.maxSide);
    });

    test('旧文档缺少间距时按页面尺寸补默认比例', () {
      final document = StoryboardDocument.fromJson({
        'version': StoryboardDocument.currentVersion,
        'pages': [
          {'id': 'a', 'width': 2048, 'height': 2896},
        ],
      });
      final page = document!.pages.single;
      expect(page.margin, StoryboardPage.defaultMarginFor(2048, 2896));
      expect(page.gutter, StoryboardPage.defaultGutterFor(2048, 2896));
      expect(page.margin, greaterThan(0));
    });

    test('间距被钳在页面允许的比例内', () {
      final document = StoryboardDocument.fromJson({
        'version': StoryboardDocument.currentVersion,
        'pages': [
          {'id': 'a', 'width': 1000, 'height': 1000, 'margin': 9999, 'gutter': -5},
        ],
      });
      final page = document!.pages.single;
      expect(page.margin, 1000 * StoryboardPage.maxSpacingRatio);
      expect(page.gutter, 0);
    });
  });

  group('StoryboardPanel 容错', () {
    StoryboardPanel? readPanel(Object? value) =>
        StoryboardPanel.fromJson(value);

    test('缺少 id 的分镜返回 null', () {
      expect(readPanel({'width': 100, 'height': 100}), isNull);
      expect(readPanel('nope'), isNull);
    });

    test('顶点不足的多边形退回矩形', () {
      final parsed = readPanel({
        'id': 'p',
        'shape': 'polygon',
        'points': [
          [0, 0],
          [1, 1],
        ],
        'width': 100,
        'height': 100,
      });
      expect(parsed!.shape, StoryboardPanelShape.rect);
      expect(parsed.points, isEmpty);
    });

    test('顶点被钳制到归一化范围并丢弃非数值项', () {
      final parsed = readPanel({
        'id': 'p',
        'shape': 'polygon',
        'points': [
          [-1, 2],
          [1, 0],
          [1, 1],
          ['x', 0],
          [0, 1],
        ],
        'width': 100,
        'height': 100,
      });
      expect(parsed!.points.length, 4);
      expect(parsed.points.first, const Offset(0, 1));
    });

    test('越界与绝对路径的图片引用被丢弃', () {
      final parsed = readPanel({
        'id': 'p',
        'width': 100,
        'height': 100,
        'images': [
          '2026-09-29/ok.png',
          '/abs/escape.png',
          r'back\slash.png',
          '../escape.png',
          'C:/drive.png',
          '2026-09-29/ok.png',
        ],
      });
      expect(parsed!.images, ['2026-09-29/ok.png']);
    });

    test('selectedImage 不在 images 中时回落到最后一张', () {
      final parsed = readPanel({
        'id': 'p',
        'width': 100,
        'height': 100,
        'images': ['a.png', 'b.png'],
        'selectedImage': 'missing.png',
      });
      expect(parsed!.selectedImage, 'b.png');
    });

    test('尺寸低于下限时回到最小边长', () {
      final parsed = readPanel({'id': 'p', 'width': 2, 'height': -5});
      expect(parsed!.width, StoryboardPanel.minSide);
      expect(parsed.height, StoryboardPanel.minSide);
    });

    test('变体数量被钳制在合法区间', () {
      expect(
        readPanel({'id': 'p', 'width': 100, 'height': 100, 'variants': 999})!
            .variants,
        StoryboardPanel.maxVariants,
      );
      expect(
        readPanel({'id': 'p', 'width': 100, 'height': 100, 'variants': 0})!
            .variants,
        1,
      );
    });

    test('反斜杠与绝对路径的显式尺寸被拒绝', () {
      final parsed = readPanel({
        'id': 'p',
        'width': 100,
        'height': 100,
        'resolution': {'mode': 'explicit', 'width': -4, 'height': 'x'},
      });
      expect(parsed!.resolution.isAuto, isFalse);
      expect(parsed.resolution.hasExplicitSize, isFalse);
    });
  });

  group('StoryboardPageBackground 容错', () {
    test('背景图路径非法时退回无背景', () {
      final background = StoryboardPageBackground.fromJson({
        'kind': 'image',
        'imagePath': '/etc/passwd',
      });
      expect(background.kind, StoryboardBackgroundKind.none);
      expect(background.imagePath, isNull);
    });

    test('none 与 color 不写入 imagePath', () {
      expect(
        const StoryboardPageBackground().toJson(),
        {'kind': 'none'},
      );
      expect(
        const StoryboardPageBackground(
          kind: StoryboardBackgroundKind.color,
          colorArgb: 0xFF102030,
        ).toJson(),
        {'kind': 'color', 'colorArgb': 0xFF102030},
      );
    });

    test('背景提示词、种子与生成历史参与往返', () {
      const background = StoryboardPageBackground(
        kind: StoryboardBackgroundKind.image,
        imagePath: 'storyboard/backgrounds/bg.png',
        prompt: 'city skyline at dusk',
        seed: 4242,
        images: ['storyboard/backgrounds/bg.png'],
      );
      final restored = StoryboardPageBackground.fromJson(background.toJson());
      expect(restored.prompt, 'city skyline at dusk');
      expect(restored.seed, 4242);
      expect(restored.images, ['storyboard/backgrounds/bg.png']);
      expect(restored.imagePath, 'storyboard/backgrounds/bg.png');
    });

    test('背景生成历史里的越界路径被丢弃', () {
      final restored = StoryboardPageBackground.fromJson({
        'kind': 'none',
        'prompt': 'x',
        'images': ['ok.png', '/abs.png', r'back\slash.png', 'ok.png'],
      });
      expect(restored.images, ['ok.png']);
    });
  });

  group('StoryboardPanel 便捷操作', () {
    test('withGeneratedImage 去重、选中并置为完成', () {
      final base = panel();
      final first = base.withGeneratedImage('a.png');
      final second = first.withGeneratedImage('b.png');
      final repeated = second.withGeneratedImage('a.png');

      expect(second.images, ['a.png', 'b.png']);
      expect(second.selectedImage, 'b.png');
      expect(repeated.images, ['b.png', 'a.png']);
      expect(repeated.selectedImage, 'a.png');
      expect(repeated.status, StoryboardPanelStatus.done);
    });

    test('withGeneratedImage 拒绝非法路径', () {
      final base = panel();
      expect(base.withGeneratedImage('/abs.png').images, isEmpty);
    });

    test('上游列表被清空，不会无限增长', () {
      var current = panel();
      for (var i = 0; i < StoryboardPanel.maxImages + 5; i++) {
        current = current.withGeneratedImage('img-$i.png');
      }
      expect(current.images.length, StoryboardPanel.maxImages);
      expect(current.selectedImage, 'img-${StoryboardPanel.maxImages + 4}.png');
    });

    test('rect 与 aspectRatio 由版面尺寸推导', () {
      final value = panel(x: 10, y: 20, width: 400, height: 200);
      expect(value.rect, const Rect.fromLTWH(10, 20, 400, 200));
      expect(value.aspectRatio, 2);
    });

    test('矩形分镜的 effectivePoints 是四个角', () {
      expect(panel().effectivePoints, StoryboardPanel.rectCorners);
    });

    test('多边形分镜的 effectivePoints 使用自身顶点', () {
      final value = panel(
        shape: StoryboardPanelShape.polygon,
        points: const [Offset(0, 0), Offset(1, 0), Offset(0.5, 1)],
      );
      expect(value.effectivePoints.length, 3);
    });
  });

  group('StoryboardPage 便捷操作', () {
    test('panelsByZOrder 按叠放顺序稳定排序', () {
      final value = page(
        panels: [
          panel(id: 'c', order: 1, zOrder: 2),
          panel(id: 'a', order: 2, zOrder: 0),
          panel(id: 'b', order: 3, zOrder: 0),
        ],
      );
      expect(value.panelsByZOrder.map((p) => p.id), ['a', 'b', 'c']);
      expect(value.maxZOrder, 2);
    });

    test('nextOrder 在最大阅读序号之后', () {
      expect(page().nextOrder, 1);
      expect(page(panels: [panel(order: 4), panel(id: 'x', order: 9)]).nextOrder, 10);
    });

    test('withPanel 按 id 替换或追加', () {
      final base = page(panels: [panel(id: 'a', order: 1)]);
      final replaced = base.withPanel(panel(id: 'a', order: 7));
      expect(replaced.panels.single.order, 7);

      final appended = base.withPanel(panel(id: 'b', order: 2));
      expect(appended.panels.length, 2);
    });

    test('withoutPanel 移除不存在的 id 时原样返回', () {
      final base = page(panels: [panel(id: 'a')]);
      expect(identical(base.withoutPanel('missing'), base), isTrue);
      expect(base.withoutPanel('a').panels, isEmpty);
    });
  });
}
