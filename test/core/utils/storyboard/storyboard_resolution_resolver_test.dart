import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/utils/nai_resolution_adapter.dart';
import 'package:nai_launcher/core/utils/storyboard/storyboard_resolution_resolver.dart';
import 'package:nai_launcher/data/models/storyboard/storyboard_fit_mode.dart';
import 'package:nai_launcher/data/models/storyboard/storyboard_resolution.dart';

void main() {
  setUp(StoryboardResolutionResolver.resetCacheForTesting);
  tearDown(StoryboardResolutionResolver.resetCacheForTesting);

  StoryboardPanelGenerationPlan resolve({
    double layoutWidth = 832,
    double layoutHeight = 1216,
    StoryboardResolution resolution = const StoryboardResolution.auto(),
    StoryboardFitMode fit = StoryboardFitMode.cover,
    int? maxArea,
  }) {
    return StoryboardResolutionResolver.resolve(
      layoutWidth: layoutWidth,
      layoutHeight: layoutHeight,
      resolution: resolution,
      fit: fit,
      maxArea: maxArea,
    );
  }

  /// 所有解析结果都必须是可以直接发请求的合法尺寸。
  void expectGenerationCompatible(StoryboardPanelGenerationPlan plan) {
    expect(
      NaiResolutionAdapter.isGenerationCompatible(
        plan.requestWidth,
        plan.requestHeight,
      ),
      isTrue,
      reason:
          '请求尺寸 ${plan.requestWidth}x${plan.requestHeight} 不是合法生成分辨率',
    );
    expect(plan.requestWidth % 64, 0);
    expect(plan.requestHeight % 64, 0);
    expect(plan.requestWidth, lessThanOrEqualTo(4096));
    expect(plan.requestHeight, lessThanOrEqualTo(4096));
    expect(
      plan.requestArea,
      lessThanOrEqualTo(NaiResolutionAdapter.officialMaxPixels),
    );
  }

  group('自动模式', () {
    test('版面尺寸本身合法时原样使用', () {
      final plan = resolve();
      expect(plan.requestWidth, 832);
      expect(plan.requestHeight, 1216);
      expect(plan.matchesLayout, isTrue);
      expect(plan.notice, StoryboardResolutionNotice.none);
      expect(plan.scaleFactor, closeTo(1, 0.0001));
      expect(plan.aspectDeviation, closeTo(0, 0.0001));
      expectGenerationCompatible(plan);
    });

    test('版面尺寸非 64 倍数时吸附到最近的合法分辨率', () {
      final plan = resolve(layoutWidth: 1120, layoutHeight: 1480);
      expectGenerationCompatible(plan);
      expect(plan.notice, StoryboardResolutionNotice.none);
      // 吸附不应明显改变宽高比。
      expect(plan.aspectDeviation, lessThan(0.05));
      expect(plan.layoutWidth, 1120);
      expect(plan.layoutHeight, 1480);
    });

    test('版面过小时放大到质量下限', () {
      final plan = resolve(layoutWidth: 416, layoutHeight: 608);
      expect(plan.notice, StoryboardResolutionNotice.upscaledForQuality);
      expect(plan.requestArea, greaterThan(416 * 608));
      expectGenerationCompatible(plan);
    });

    test('小分镜放大到免费档满额面积出图，放大保持免费', () {
      final plan = resolve(layoutWidth: 496, layoutHeight: 493);
      expect(plan.notice, StoryboardResolutionNotice.upscaledForQuality);
      // 免费档满额：显著大于版面，但不超出免费上限（0 Anlas）。
      expect(
        plan.requestArea,
        lessThanOrEqualTo(StoryboardResolutionResolver.freeTierMaxPixels),
        reason: '请求 ${plan.requestWidth}x${plan.requestHeight} 超出免费档',
      );
      expect(plan.requestArea, greaterThanOrEqualTo(900 * 1000));
      expect(plan.aspectDeviation, lessThan(0.05));
      expectGenerationCompatible(plan);
    });

    test('版面已接近免费档时不再强行放大', () {
      // 960×832 = 798,720 > autoQualityFloorArea（免费档的 3/4）。
      final plan = resolve(layoutWidth: 960, layoutHeight: 832);
      expect(plan.notice, StoryboardResolutionNotice.none);
      expect(plan.matchesLayout, isTrue);
      expectGenerationCompatible(plan);
    });

    test('版面超过单张上限时按比例收敛', () {
      final plan = resolve(layoutWidth: 4000, layoutHeight: 4000);
      expect(plan.notice, StoryboardResolutionNotice.clampedToMaxArea);
      expectGenerationCompatible(plan);
      expect(plan.requestArea, lessThanOrEqualTo(NaiResolutionAdapter.officialMaxPixels));
    });

    test('极端宽高比不会产生非法或不收敛的结果', () {
      final wide = resolve(layoutWidth: 2000, layoutHeight: 10);
      expectGenerationCompatible(wide);

      final tall = resolve(layoutWidth: 10, layoutHeight: 4000);
      expectGenerationCompatible(tall);
    });

    test('零与负数版面尺寸不抛异常', () {
      for (final layout in [
        const (0.0, 0.0),
        (0.0, 500.0),
        (-10.0, 300.0),
      ]) {
        final plan = resolve(layoutWidth: layout.$1, layoutHeight: layout.$2);
        expectGenerationCompatible(plan);
      }
    });

    test('适配方式原样透传', () {
      expect(
        resolve(fit: StoryboardFitMode.contain).fit,
        StoryboardFitMode.contain,
      );
      expect(resolve(fit: StoryboardFitMode.stretch).fit, StoryboardFitMode.stretch);
    });
  });

  group('显式模式', () {
    test('合法显式尺寸原样使用', () {
      final plan = resolve(
        resolution: const StoryboardResolution.explicit(width: 832, height: 1216),
      );
      expect(plan.requestWidth, 832);
      expect(plan.requestHeight, 1216);
      expect(plan.notice, StoryboardResolutionNotice.none);
      expectGenerationCompatible(plan);
    });

    test('非 64 倍数的显式尺寸被吸附并标记', () {
      final plan = resolve(
        resolution: const StoryboardResolution.explicit(width: 800, height: 1500),
      );
      expect(plan.notice, StoryboardResolutionNotice.snappedToLegalSize);
      expectGenerationCompatible(plan);
    });

    test('超过单张上限的显式尺寸被收敛', () {
      final plan = resolve(
        resolution: const StoryboardResolution.explicit(
          width: 4096,
          height: 4096,
        ),
      );
      expect(plan.notice, StoryboardResolutionNotice.snappedToLegalSize);
      expectGenerationCompatible(plan);
    });

    test('显式小尺寸同样被放大到质量下限，不出小图', () {
      final plan = resolve(
        resolution: const StoryboardResolution.explicit(
          width: 448,
          height: 640,
        ),
      );
      expect(plan.notice, StoryboardResolutionNotice.upscaledForQuality);
      expect(
        plan.requestArea,
        lessThanOrEqualTo(StoryboardResolutionResolver.freeTierMaxPixels),
      );
      expect(plan.requestArea, greaterThanOrEqualTo(900 * 1000));
      expect(plan.aspectDeviation, lessThan(0.05));
      expectGenerationCompatible(plan);
    });

    test('尺寸不完整时退回自动推导', () {
      final plan = resolve(
        resolution: const StoryboardResolution.explicit(width: 832, height: 0),
      );
      expect(plan.notice, StoryboardResolutionNotice.none);
      expect(plan.requestWidth, 832);
      expect(plan.requestHeight, 1216);
    });

    test('显式尺寸与版面尺寸解耦，版面尺寸只作展示', () {
      final plan = resolve(
        layoutWidth: 1120,
        layoutHeight: 1480,
        resolution: const StoryboardResolution.explicit(width: 832, height: 1216),
      );
      expect(plan.layoutWidth, 1120);
      expect(plan.layoutHeight, 1480);
      expect(plan.requestWidth, 832);
      expect(plan.requestHeight, 1216);
      expect(plan.matchesLayout, isFalse);
    });
  });

  group('禁止收费（clampToArea）', () {
    test('面积超限时收敛到免费档以内', () {
      final plan = StoryboardResolutionResolver.resolve(
        layoutWidth: 2048,
        layoutHeight: 2896,
        resolution: const StoryboardResolution.auto(),
        fit: StoryboardFitMode.cover,
      );
      final clamped = StoryboardResolutionResolver.clampToArea(
        plan,
        StoryboardResolutionResolver.freeTierMaxPixels,
      );
      expect(
        clamped.requestArea,
        lessThanOrEqualTo(StoryboardResolutionResolver.freeTierMaxPixels),
      );
      expect(
        NaiResolutionAdapter.isGenerationCompatible(
          clamped.requestWidth,
          clamped.requestHeight,
        ),
        isTrue,
      );
    });

    test('吸附后仍超限时继续收敛，不会把面积顶回上限之上', () {
      // 1,015,000 附近的面积经 64 网格吸附后很容易超过免费档。
      const plan = StoryboardPanelGenerationPlan(
        layoutWidth: 1015,
        layoutHeight: 1015,
        requestWidth: 1015,
        requestHeight: 1015,
        fit: StoryboardFitMode.cover,
        notice: StoryboardResolutionNotice.none,
      );
      final clamped = StoryboardResolutionResolver.clampToArea(
        plan,
        StoryboardResolutionResolver.freeTierMaxPixels,
      );
      expect(
        clamped.requestArea,
        lessThanOrEqualTo(StoryboardResolutionResolver.freeTierMaxPixels),
      );
    });

    test('面积本就在免费档内时原样返回', () {
      const plan = StoryboardPanelGenerationPlan(
        layoutWidth: 832,
        layoutHeight: 1216,
        requestWidth: 832,
        requestHeight: 1216,
        fit: StoryboardFitMode.cover,
        notice: StoryboardResolutionNotice.none,
      );
      final clamped = StoryboardResolutionResolver.clampToArea(
        plan,
        StoryboardResolutionResolver.freeTierMaxPixels,
      );
      expect(identical(clamped, plan), isTrue);
    });
  });

  group('禁止收费（resolve maxArea 一体化）', () {
    test('版面 1358×1520 钳制后落在免费档内且保持宽高比', () {
      final free = resolve(
        layoutWidth: 1358,
        layoutHeight: 1520,
        maxArea: StoryboardResolutionResolver.freeTierMaxPixels,
      );
      expect(
        free.requestArea,
        lessThanOrEqualTo(StoryboardResolutionResolver.freeTierMaxPixels),
        reason: '请求 ${free.requestWidth}x${free.requestHeight} 仍会产生 Anlas 消耗',
      );
      expectGenerationCompatible(free);
      expect(free.notice, StoryboardResolutionNotice.clampedToMaxArea);
      // 同比例收敛：64 网格吸附允许小幅偏差，但不得明显变形。
      expect(free.aspectDeviation, lessThan(0.05));
    });

    test('不传 maxArea 时同样版面仍按版面尺寸请求（会计费）', () {
      final paid = resolve(layoutWidth: 1358, layoutHeight: 1520);
      expect(paid.requestWidth, 1344);
      expect(paid.requestHeight, 1536);
      expect(paid.requestArea, greaterThan(StoryboardResolutionResolver.freeTierMaxPixels));
      expect(paid.notice, StoryboardResolutionNotice.none);
    });

    test('显式尺寸超过免费档时同样被钳制', () {
      final free = resolve(
        resolution: const StoryboardResolution.explicit(
          width: 1344,
          height: 1536,
        ),
        maxArea: StoryboardResolutionResolver.freeTierMaxPixels,
      );
      expect(
        free.requestArea,
        lessThanOrEqualTo(StoryboardResolutionResolver.freeTierMaxPixels),
      );
      expect(free.notice, StoryboardResolutionNotice.clampedToMaxArea);
      expectGenerationCompatible(free);
    });

    test('免费档内的版面传 maxArea 后原样返回', () {
      final plan = resolve(maxArea: StoryboardResolutionResolver.freeTierMaxPixels);
      expect(plan.requestWidth, 832);
      expect(plan.requestHeight, 1216);
      expect(plan.notice, StoryboardResolutionNotice.none);
      expectGenerationCompatible(plan);
    });

    test('maxArea 参与缓存键，不同上限不复用结果', () {
      final free = resolve(
        layoutWidth: 1358,
        layoutHeight: 1520,
        maxArea: StoryboardResolutionResolver.freeTierMaxPixels,
      );
      final paid = resolve(layoutWidth: 1358, layoutHeight: 1520);
      expect(identical(free, paid), isFalse);
    });
  });

  group('缓存与聚合', () {
    test('相同输入返回同一实例', () {
      final first = resolve(layoutWidth: 1120, layoutHeight: 1480);
      final second = resolve(layoutWidth: 1120, layoutHeight: 1480);
      expect(identical(first, second), isTrue);
    });

    test('不同输入不复用结果', () {
      final first = resolve(layoutWidth: 1120, layoutHeight: 1480);
      final second = resolve(layoutWidth: 1200, layoutHeight: 1480);
      expect(identical(first, second), isFalse);
    });

    test('小数版面尺寸按取整后缓存，不产生重复条目', () {
      final a = resolve(layoutWidth: 1120.2, layoutHeight: 1480.4);
      final b = resolve(layoutWidth: 1120.4, layoutHeight: 1480.1);
      expect(identical(a, b), isTrue);
    });

    test('totalRequestArea 累加各面板请求面积', () {
      final plans = [
        resolve(),
        resolve(layoutWidth: 416, layoutHeight: 608),
      ];
      expect(
        StoryboardResolutionResolver.totalRequestArea(plans),
        plans[0].requestArea + plans[1].requestArea,
      );
    });
  });
}
