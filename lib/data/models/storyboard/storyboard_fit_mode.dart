/// 分镜图与容器矩形（或页面背景）的适配方式。
///
/// 生成分辨率与版面矩形几乎不可能完全一致：64 网格量化会改变宽高比，
/// 显式分辨率也可能由用户指定成另一种比例。适配方式决定这部分差异
/// 由谁来吸收。
enum StoryboardFitMode {
  /// 等比放大到刚好覆盖容器，溢出部分裁掉。分镜的默认值，画面不留白。
  cover,

  /// 等比缩小到完整放入容器，多余方向露出页面背景。
  contain,

  /// 拉伸到容器尺寸，不保持比例。会把画面压扁或拉长，只在用户明确需要时使用。
  stretch;

  static StoryboardFitMode fromStorage(
    Object? value, {
    StoryboardFitMode fallback = StoryboardFitMode.cover,
  }) {
    if (value is! String) return fallback;
    for (final mode in values) {
      if (mode.name == value) return mode;
    }
    return fallback;
  }
}
