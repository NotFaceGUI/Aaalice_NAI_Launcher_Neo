/// 画布上两个节点之间的标注连线。
///
/// 连线只表达用户手动画出的关联，不携带业务派生语义；[label] 是可选的
/// 文字标注。方向由 [fromNodeId] 指向 [toNodeId]。
class CanvasEdge {
  final String id;
  final String fromNodeId;
  final String toNodeId;
  final String? label;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CanvasEdge({
    required this.id,
    required this.fromNodeId,
    required this.toNodeId,
    this.label,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 是否引用了给定节点集合之外的节点（引用完整性检查用）
  bool referencesOutside(Set<String> nodeIds) =>
      !nodeIds.contains(fromNodeId) || !nodeIds.contains(toNodeId);

  CanvasEdge copyWith({String? label, bool clearLabel = false}) {
    return CanvasEdge(
      id: id,
      fromNodeId: fromNodeId,
      toNodeId: toNodeId,
      label: clearLabel ? null : (label ?? this.label),
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'from': fromNodeId,
    'to': toNodeId,
    if (label != null && label!.isNotEmpty) 'label': label,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };

  static CanvasEdge fromJson(Map<String, dynamic> json) {
    int readInt(Object? value) => value is num ? value.toInt() : 0;
    final createdAt = readInt(json['createdAt']);
    final rawLabel = json['label'];

    return CanvasEdge(
      id: json['id'] is String ? json['id'] as String : '',
      fromNodeId: json['from'] is String ? json['from'] as String : '',
      toNodeId: json['to'] is String ? json['to'] as String : '',
      label: rawLabel is String && rawLabel.isNotEmpty ? rawLabel : null,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        readInt(json['updatedAt']) == 0
            ? createdAt
            : readInt(json['updatedAt']),
      ),
    );
  }
}
