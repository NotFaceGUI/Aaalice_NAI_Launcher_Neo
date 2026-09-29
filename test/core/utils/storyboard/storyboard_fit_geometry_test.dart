import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/utils/storyboard/storyboard_fit_geometry.dart';
import 'package:nai_launcher/data/models/storyboard/storyboard_fit_mode.dart';

void main() {
  const dest = Rect.fromLTWH(100, 50, 200, 100);

  group('placementRect', () {
    test('stretch 铺满容器', () {
      expect(
        StoryboardFitGeometry.placementRect(
          imageSize: const Size(400, 300),
          dest: dest,
          fit: StoryboardFitMode.stretch,
        ),
        dest,
      );
    });

    test('contain 完整放入并居中', () {
      // 400×300 放进 200×100：按宽度缩小到 200×150 会超出高度，实际取高度。
      final fitted = StoryboardFitGeometry.placementRect(
        imageSize: const Size(400, 300),
        dest: dest,
        fit: StoryboardFitMode.contain,
      );

      expect(fitted.width, closeTo(133.333, 0.01));
      expect(fitted.height, closeTo(100, 0.01));
      expect(fitted.center, dest.center);
    });

    test('cover 放大到覆盖容器并居中，可以超出容器', () {
      final placement = StoryboardFitGeometry.placementRect(
        imageSize: const Size(100, 100),
        dest: dest,
        fit: StoryboardFitMode.cover,
      );

      expect(placement.width, closeTo(200, 0.01));
      expect(placement.height, closeTo(200, 0.01));
      expect(placement.center, dest.center);
      expect(placement.width >= dest.width && placement.height >= dest.height, isTrue);
    });

    test('退化尺寸返回容器自身', () {
      expect(
        StoryboardFitGeometry.placementRect(
          imageSize: Size.zero,
          dest: dest,
          fit: StoryboardFitMode.cover,
        ),
        dest,
      );
      expect(
        StoryboardFitGeometry.placementRect(
          imageSize: const Size(10, 10),
          dest: Rect.zero,
          fit: StoryboardFitMode.cover,
        ),
        Rect.zero,
      );
    });
  });

  group('fitRects', () {
    test('stretch 与 contain 不裁源图', () {
      for (final fit in [StoryboardFitMode.stretch, StoryboardFitMode.contain]) {
        final (src, target) = StoryboardFitGeometry.fitRects(
          imageSize: const Size(400, 300),
          dest: dest,
          fit: fit,
        );
        expect(src, const Rect.fromLTWH(0, 0, 400, 300));
        expect(target, StoryboardFitGeometry.placementRect(
          imageSize: const Size(400, 300),
          dest: dest,
          fit: fit,
        ));
      }
    });

    test('cover 按容器比例居中裁源图', () {
      // 100×400 的竖图覆盖 200×100：放大 2 倍到 200×800，纵向居中裁出 200×100。
      final (src, target) = StoryboardFitGeometry.fitRects(
        imageSize: const Size(100, 400),
        dest: dest,
        fit: StoryboardFitMode.cover,
      );

      expect(target, dest);
      expect(src.width, closeTo(100, 0.01));
      expect(src.height, closeTo(50, 0.01));
      expect(src.center, const Offset(50, 200));

      // 裁出来的源图比例必须与容器一致，否则 cover 会拉变形。
      expect(src.width / src.height, closeTo(dest.width / dest.height, 0.0001));
    });

    test('cover 的源裁切区不越过原图边界', () {
      final (src, _) = StoryboardFitGeometry.fitRects(
        imageSize: const Size(400, 500),
        dest: dest,
        fit: StoryboardFitMode.cover,
      );

      expect(src.left, greaterThanOrEqualTo(-0.01));
      expect(src.top, greaterThanOrEqualTo(-0.01));
      expect(src.right, lessThanOrEqualTo(400.01));
      expect(src.bottom, lessThanOrEqualTo(500.01));
    });
  });
}
