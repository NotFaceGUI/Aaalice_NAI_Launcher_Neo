import 'dart:math' as math;

import '../../../data/models/storyboard/storyboard_fit_mode.dart';
import '../../../data/models/storyboard/storyboard_resolution.dart';
import '../nai_resolution_adapter.dart';

/// 自动分辨率相对版面尺寸做出的调整，供界面提示用户。
enum StoryboardResolutionNotice {
  /// 请求尺寸与版面尺寸一致（仍可能因 64 网格量化而略有差异）。
  none,

  /// 用户填的显式尺寸非法，已吸附到最近的合法分辨率。
  snappedToLegalSize,

  /// 版面尺寸超过单张生成上限，已按比例收敛。
  clampedToMaxArea,

  /// 版面尺寸低于质量下限，已放大生成后再缩回使用。
  upscaledForQuality,
}

/// 单个分镜的生成方案：请求尺寸、适配方式与推导过程中的调整提示。
///
/// [layoutWidth]/[layoutHeight] 是参与的版面尺寸（页面像素，已取整），
/// 与 [requestWidth]/[requestHeight] 一起交给界面显示——用户拉出的框和
/// 实际发出请求的尺寸几乎不会相同，两者必须同时可见。
class StoryboardPanelGenerationPlan {
  const StoryboardPanelGenerationPlan({
    required this.layoutWidth,
    required this.layoutHeight,
    required this.requestWidth,
    required this.requestHeight,
    required this.fit,
    required this.notice,
  });

  final int layoutWidth;
  final int layoutHeight;
  final int requestWidth;
  final int requestHeight;
  final StoryboardFitMode fit;
  final StoryboardResolutionNotice notice;

  int get requestArea => requestWidth * requestHeight;

  /// 请求尺寸相对版面尺寸的平均缩放比。
  double get scaleFactor {
    if (layoutWidth <= 0 || layoutHeight <= 0) return 1.0;
    return ((requestWidth / layoutWidth) + (requestHeight / layoutHeight)) / 2;
  }

  /// 请求尺寸是否与版面尺寸完全相同。
  bool get matchesLayout =>
      requestWidth == layoutWidth && requestHeight == layoutHeight;

  /// 请求宽高比相对版面宽高比的变化幅度（0 表示同比例）。
  double get aspectDeviation {
    if (layoutWidth <= 0 || layoutHeight <= 0 || requestHeight <= 0) return 0;
    final layoutAspect = layoutWidth / layoutHeight;
    final requestAspect = requestWidth / requestHeight;
    return ((requestAspect - layoutAspect) / layoutAspect).abs();
  }
}

/// 把分镜的版面尺寸与分辨率意图解析成可直接用于生成请求的尺寸。
///
/// NovelAI 只接受 64 倍数、单边不超过 4096、总像素不超过 3,145,728 的尺寸，
/// 而用户拉出的框几乎不可能是 64 倍数，所以这里统一做一次吸附；多边形分镜
/// 用外接矩形请求，因此同样走这条路径。
class StoryboardResolutionResolver {
  StoryboardResolutionResolver._();

  /// 自动模式的质量下限：版面面积低于免费档的 3/4 时，放大到免费档满额
  /// 面积出图（同比例放大后再缩回贴合分镜）——小图直出容易糊，而免费档内
  /// 的放大不产生 Anlas 消耗；更大的版面保持原样，不多花钱。
  static const int autoQualityFloorArea =
      StoryboardResolutionResolver.freeTierMaxPixels * 3 ~/ 4;

  /// 缓存容量；解析器会在面板拖动过程中被逐帧调用，但结果是纯函数。
  static const int _cacheCapacity = 512;

  static final Map<String, StoryboardPanelGenerationPlan> _cache = {};

  /// 解析生成方案。[layoutWidth]/[layoutHeight] 为分镜版面尺寸（页面像素）。
  ///
  /// [maxArea] 非空时把结果收敛进该面积内（保持宽高比），「禁止收费」页面
  /// 传 [freeTierMaxPixels]，让界面显示、编辑器同步与实际生成共用同一份
  /// 钳制后的尺寸。
  static StoryboardPanelGenerationPlan resolve({
    required double layoutWidth,
    required double layoutHeight,
    required StoryboardResolution resolution,
    required StoryboardFitMode fit,
    int? maxArea,
  }) {
    final layoutW = _roundLayoutSide(layoutWidth);
    final layoutH = _roundLayoutSide(layoutHeight);

    final key =
        '$layoutW:$layoutH:${resolution.mode.name}:'
        '${resolution.width ?? 0}:${resolution.height ?? 0}:${fit.name}:'
        '$maxArea';
    final cached = _cache[key];
    if (cached != null) return cached;

    var plan = _resolveUncached(
      layoutWidth: layoutW,
      layoutHeight: layoutH,
      resolution: resolution,
      fit: fit,
    );
    // 任何模式都不出小图：低于质量下限的请求（含显式分辨率与版面推导）
    // 同比例放大到免费档满额面积——Opus 下依旧 0 Anlas，画质明显更实。
    if (plan.requestArea < autoQualityFloorArea) {
      plan = _upscaleToFreeTier(plan);
    }
    if (maxArea != null) plan = clampToArea(plan, maxArea);
    if (_cache.length >= _cacheCapacity) _cache.clear();
    _cache[key] = plan;
    return plan;
  }

  /// Opus 免费档的单张像素上限；超过即产生 Anlas 消耗。
  static const int freeTierMaxPixels = 1024 * 1024;

  /// Opus 免费档的步数上限。
  static const int freeTierMaxSteps = 28;

  /// 把请求面积收敛到 [maxArea] 以内，保持宽高比并重新吸附到 64 网格。
  ///
  /// 用于「禁止收费」：自定义画幅经常超过免费档，与其让用户为一次排版实验
  /// 付 Anlas，不如在免费范围内出图、再由界面的适配方式缩放贴合分镜。
  static StoryboardPanelGenerationPlan clampToArea(
    StoryboardPanelGenerationPlan plan,
    int maxArea,
  ) {
    if (plan.requestArea <= maxArea) return plan;

    // 按 64 网格吸附可能把面积又顶回上限之上（例如目标 1015×1015 吸附成
    // 1088×1024），所以吸附后必须校验，超了就把较长的一边再收一格重试。
    var width = plan.requestWidth;
    var height = plan.requestHeight;
    for (var attempt = 0; attempt < 32; attempt++) {
      final ratio = math.sqrt(maxArea / (width * height));
      final snapped = NaiResolutionAdapter.findClosestResolution(
        _clampCandidateSide(width * ratio),
        _clampCandidateSide(height * ratio),
      );
      if (snapped.width * snapped.height <= maxArea) {
        return StoryboardPanelGenerationPlan(
          layoutWidth: plan.layoutWidth,
          layoutHeight: plan.layoutHeight,
          requestWidth: snapped.width,
          requestHeight: snapped.height,
          fit: plan.fit,
          notice: StoryboardResolutionNotice.clampedToMaxArea,
        );
      }
      if (snapped.width >= snapped.height) {
        width = snapped.width - 64;
      } else {
        height = snapped.height - 64;
      }
      if (width < 64 || height < 64) break;
    }

    // 兜底：直接取免费档内该宽高比能容纳的最大尺寸。
    final aspect = plan.requestHeight > 0
        ? plan.requestWidth / plan.requestHeight
        : 1.0;
    final freeHeight = math.sqrt(maxArea / aspect);
    final fallback = NaiResolutionAdapter.findClosestResolution(
      _clampCandidateSide(freeHeight * aspect),
      _clampCandidateSide(freeHeight),
    );
    return StoryboardPanelGenerationPlan(
      layoutWidth: plan.layoutWidth,
      layoutHeight: plan.layoutHeight,
      requestWidth: fallback.width,
      requestHeight: fallback.height,
      fit: plan.fit,
      notice: StoryboardResolutionNotice.clampedToMaxArea,
    );
  }

  /// 面板列表的总请求面积，供生成前的成本与耗时预估使用。
  static int totalRequestArea(Iterable<StoryboardPanelGenerationPlan> plans) {
    var total = 0;
    for (final plan in plans) {
      total += plan.requestArea;
    }
    return total;
  }

  /// 清空解析缓存；测试用。
  static void resetCacheForTesting() => _cache.clear();

  static StoryboardPanelGenerationPlan _resolveUncached({
    required int layoutWidth,
    required int layoutHeight,
    required StoryboardResolution resolution,
    required StoryboardFitMode fit,
  }) {
    if (resolution.hasExplicitSize) {
      final width = resolution.width!;
      final height = resolution.height!;
      if (NaiResolutionAdapter.isGenerationCompatible(width, height)) {
        return StoryboardPanelGenerationPlan(
          layoutWidth: layoutWidth,
          layoutHeight: layoutHeight,
          requestWidth: width,
          requestHeight: height,
          fit: fit,
          notice: StoryboardResolutionNotice.none,
        );
      }
      final snapped = NaiResolutionAdapter.findClosestResolution(width, height);
      return StoryboardPanelGenerationPlan(
        layoutWidth: layoutWidth,
        layoutHeight: layoutHeight,
        requestWidth: snapped.width,
        requestHeight: snapped.height,
        fit: fit,
        notice: StoryboardResolutionNotice.snappedToLegalSize,
      );
    }

    final aspect = layoutWidth / layoutHeight;
    var targetArea = layoutWidth.toDouble() * layoutHeight;
    var notice = StoryboardResolutionNotice.none;

    final maxArea = NaiResolutionAdapter.officialMaxPixels.toDouble();
    if (targetArea > maxArea) {
      targetArea = maxArea;
      notice = StoryboardResolutionNotice.clampedToMaxArea;
    }

    // 由面积与宽高比反推目标边长，再交给适配器吸附到最近的合法分辨率。
    // 小尺寸的统一放大由 resolve() 的质量下限负责，这里不再重复。
    final targetHeight = math.sqrt(targetArea / aspect);
    final targetWidth = targetHeight * aspect;
    final snapped = NaiResolutionAdapter.findClosestResolution(
      _clampCandidateSide(targetWidth),
      _clampCandidateSide(targetHeight),
    );

    return StoryboardPanelGenerationPlan(
      layoutWidth: layoutWidth,
      layoutHeight: layoutHeight,
      requestWidth: snapped.width,
      requestHeight: snapped.height,
      fit: fit,
      notice: notice,
    );
  }

  /// 把请求尺寸同比例放大到免费档满额面积。
  ///
  /// 64 网格吸附可能把面积顶回上限之上，超了就再收一格，保证放大始终免费；
  /// 提示保留为「放大」而不是「收敛」，因为触发原因是质量下限。
  static StoryboardPanelGenerationPlan _upscaleToFreeTier(
    StoryboardPanelGenerationPlan plan,
  ) {
    final aspect = plan.requestHeight > 0
        ? plan.requestWidth / plan.requestHeight
        : 1.0;
    final targetHeight = math.sqrt(freeTierMaxPixels / aspect);
    final snapped = NaiResolutionAdapter.findClosestResolution(
      _clampCandidateSide(targetHeight * aspect),
      _clampCandidateSide(targetHeight),
    );
    var next = StoryboardPanelGenerationPlan(
      layoutWidth: plan.layoutWidth,
      layoutHeight: plan.layoutHeight,
      requestWidth: snapped.width,
      requestHeight: snapped.height,
      fit: plan.fit,
      notice: StoryboardResolutionNotice.upscaledForQuality,
    );
    if (next.requestArea > freeTierMaxPixels) {
      final clamped = clampToArea(next, freeTierMaxPixels);
      next = StoryboardPanelGenerationPlan(
        layoutWidth: next.layoutWidth,
        layoutHeight: next.layoutHeight,
        requestWidth: clamped.requestWidth,
        requestHeight: clamped.requestHeight,
        fit: next.fit,
        notice: StoryboardResolutionNotice.upscaledForQuality,
      );
    }
    return next;
  }

  static int _roundLayoutSide(double value) {
    if (!value.isFinite || value <= 0) return 1;
    final rounded = value.round();
    return rounded < 1 ? 1 : rounded;
  }

  /// 适配器只接受正整数；极端宽高比下反推值可能越界或取整为 0。
  static int _clampCandidateSide(double value) {
    if (!value.isFinite || value <= 0) return 1;
    final rounded = value.round();
    if (rounded < 1) return 1;
    const maxSide = NaiResolutionAdapter.generationMaxSide;
    return rounded > maxSide ? maxSide : rounded;
  }
}
