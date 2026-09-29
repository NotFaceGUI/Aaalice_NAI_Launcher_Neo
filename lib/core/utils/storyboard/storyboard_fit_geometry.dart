import 'dart:math' as math;
import 'dart:ui';

import '../../../data/models/storyboard/storyboard_fit_mode.dart';

/// 分镜图与容器矩形之间的适配几何。
///
/// 整页合成（PNG）与分层导出（PSD）必须把同一张原图放在完全相同的位置，
/// 否则用户在 Photoshop 里看到的画面会和导出的 PNG 不同。两条路径都从这里
/// 取结果，不再各自实现一份 fit 数学。
///
/// 坐标约定：容器 [dest] 使用页面像素，图像尺寸使用原图像素。
class StoryboardFitGeometry {
  StoryboardFitGeometry._();

  /// 整张原图放好后占用的目标矩形（不裁源图）。
  ///
  /// contain 等比缩小到完整放入并居中、stretch 直接等于 [dest]；cover 等比
  /// 放大到刚好覆盖并居中，结果会大于 [dest]——合成时按 [dest] 裁源，分层
  /// 导出时交给分镜遮罩裁剪。
  static Rect placementRect({
    required Size imageSize,
    required Rect dest,
    required StoryboardFitMode fit,
  }) {
    if (dest.isEmpty || imageSize.isEmpty) return dest;
    switch (fit) {
      case StoryboardFitMode.stretch:
        return dest;
      case StoryboardFitMode.contain:
        return _centered(
          imageSize * _scale(imageSize, dest, largest: false),
          dest,
        );
      case StoryboardFitMode.cover:
        return _centered(
          imageSize * _scale(imageSize, dest, largest: true),
          dest,
        );
    }
  }

  /// 绘制用的一对矩形：（源图裁切区, 目标区）。
  ///
  /// 只有 cover 需要裁源——它把原图放大到覆盖 [dest] 后，取与 [dest] 同比例
  /// 的居中区域贴上去；其余两种方式原图完整落进目标区。
  static (Rect, Rect) fitRects({
    required Size imageSize,
    required Rect dest,
    required StoryboardFitMode fit,
  }) {
    final full = Offset.zero & imageSize;
    if (dest.isEmpty || imageSize.isEmpty) return (full, dest);
    final placement = placementRect(imageSize: imageSize, dest: dest, fit: fit);
    if (fit != StoryboardFitMode.cover) return (full, placement);
    final scale = placement.width / imageSize.width;
    final source = Rect.fromCenter(
      center: Offset(imageSize.width / 2, imageSize.height / 2),
      width: dest.width / scale,
      height: dest.height / scale,
    );
    return (source, dest);
  }

  /// 等比缩放的倍数；[largest] 为真时取覆盖容器所需的最大倍数。
  static double _scale(Size imageSize, Rect dest, {required bool largest}) {
    final horizontal = dest.width / imageSize.width;
    final vertical = dest.height / imageSize.height;
    return largest
        ? math.max(horizontal, vertical)
        : math.min(horizontal, vertical);
  }

  static Rect _centered(Size size, Rect dest) => Rect.fromLTWH(
    dest.left + (dest.width - size.width) / 2,
    dest.top + (dest.height - size.height) / 2,
    size.width,
    size.height,
  );
}
