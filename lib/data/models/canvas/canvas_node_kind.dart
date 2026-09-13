/// 无限画布节点类型。
///
/// storageValue 是数据库中的整数编码，已落盘的值不可重排。
enum CanvasNodeKind {
  /// 生成结果或本地图库图片节点
  image(0),

  /// 种子待办便签：只有种子与参数快照，尚未出图
  seedTodo(1),

  /// 纯文本标注便签
  note(2);

  const CanvasNodeKind(this.storageValue);

  final int storageValue;

  static CanvasNodeKind fromStorage(Object? value) {
    final raw = value is num ? value.toInt() : null;
    for (final kind in CanvasNodeKind.values) {
      if (kind.storageValue == raw) return kind;
    }
    return CanvasNodeKind.note;
  }

  /// 是否承载图片内容（需要解析相对路径与缩略图）
  bool get hasImage => this == CanvasNodeKind.image;
}
