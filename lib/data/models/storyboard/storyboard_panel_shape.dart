/// 分镜的版面形状。
///
/// NovelAI 只能输出矩形，所以两种形状在生成阶段没有区别：多边形分镜
/// 同样按外接矩形请求，区别只发生在合成时——多边形会把矩形结果裁到
/// 顶点围成的区域内。
enum StoryboardPanelShape {
  /// 矩形分镜：直接使用 [StoryboardPanel] 的矩形。
  rect,

  /// 多边形分镜：使用归一化顶点描述的形状，矩形是其外接矩形。
  polygon;

  bool get isPolygon => this == StoryboardPanelShape.polygon;

  static StoryboardPanelShape fromStorage(
    Object? value, {
    StoryboardPanelShape fallback = StoryboardPanelShape.rect,
  }) {
    if (value is! String) return fallback;
    for (final shape in values) {
      if (shape.name == value) return shape;
    }
    return fallback;
  }
}
