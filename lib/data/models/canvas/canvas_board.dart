import 'canvas_edge.dart';
import 'canvas_node.dart';

/// 一块无限画布：自带节点与连线，等价于一个"项目"。
///
/// 节点坐标只在本画布内有意义，画布之间互不影响；画布列表整体存在图库根
/// 目录的同一个 sidecar 文件里，仍然是一次原子写。
class CanvasBoard {
  final String id;
  final String name;
  final List<CanvasNode> nodes;
  final List<CanvasEdge> edges;

  /// 新节点落位时与既有节点保留的画布空间间隙
  static const double placementGap = 24.0;

  /// 落点环形扫描的最大圈数，避免极端拥挤时无限循环
  static const int maxPlacementRing = 24;

  final DateTime createdAt;
  final DateTime updatedAt;

  const CanvasBoard({
    required this.id,
    required this.name,
    required this.nodes,
    required this.edges,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isEmpty => nodes.isEmpty && edges.isEmpty;

  CanvasNode? nodeById(String id) {
    for (final node in nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  /// 节点按 z 序升序（先画的在下层）
  List<CanvasNode> get nodesByZOrder {
    final sorted = [...nodes];
    sorted.sort((a, b) {
      final byZ = a.zOrder.compareTo(b.zOrder);
      return byZ != 0 ? byZ : a.createdAt.compareTo(b.createdAt);
    });
    return sorted;
  }

  int get maxZOrder =>
      nodes.fold(0, (max, node) => node.zOrder > max ? node.zOrder : max);

  /// 与指定节点相连的全部连线
  List<CanvasEdge> edgesFor(String nodeId) => [
    for (final edge in edges)
      if (edge.fromNodeId == nodeId || edge.toNodeId == nodeId) edge,
  ];

  CanvasBoard copyWith({
    String? name,
    List<CanvasNode>? nodes,
    List<CanvasEdge>? edges,
    DateTime? updatedAt,
  }) {
    return CanvasBoard(
      id: id,
      name: name ?? this.name,
      nodes: nodes ?? this.nodes,
      edges: edges ?? this.edges,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// 为新节点找一个不与既有节点重叠的落点。
  ///
  /// 优先使用 [nearX]/[nearY]，被占用时以该点为中心逐圈向外扫描。
  ({double x, double y}) findFreePosition({
    required double width,
    required double height,
    required double nearX,
    required double nearY,
  }) {
    bool isFree(double x, double y) {
      for (final node in nodes) {
        final separated =
            x >= node.right + placementGap ||
            x + width <= node.x - placementGap ||
            y >= node.bottom + placementGap ||
            y + height <= node.y - placementGap;
        if (!separated) return false;
      }
      return true;
    }

    if (isFree(nearX, nearY)) return (x: nearX, y: nearY);

    final stepX = width + placementGap;
    final stepY = height + placementGap;
    for (var ring = 1; ring <= maxPlacementRing; ring++) {
      for (var dx = -ring; dx <= ring; dx++) {
        for (var dy = -ring; dy <= ring; dy++) {
          if (dx.abs() != ring && dy.abs() != ring) continue;
          final x = nearX + dx * stepX;
          final y = nearY + dy * stepY;
          if (isFree(x, y)) return (x: x, y: y);
        }
      }
    }
    return (x: nearX, y: nearY + stepY * (maxPlacementRing + 1));
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'nodes': [for (final node in nodes) node.toJson()],
    'edges': [for (final edge in edges) edge.toJson()],
  };

  /// 解析一块画布；损坏条目、重复 id 与引用缺失节点的连线会被丢弃，
  /// 保证内存中始终是自洽的图。
  static CanvasBoard? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    final rawName = json['name'];
    final createdAt = (json['createdAt'] as num?)?.toInt() ?? 0;

    final nodes = <CanvasNode>[];
    final seenNodeIds = <String>{};
    final rawNodes = json['nodes'];
    if (rawNodes is List) {
      for (final item in rawNodes) {
        if (item is! Map) continue;
        final node = CanvasNode.fromJson(
          Map<String, dynamic>.from(item),
          fallbackZ: nodes.length,
        );
        if (node.id.isEmpty || !seenNodeIds.add(node.id)) continue;
        nodes.add(node);
      }
    }

    final edges = <CanvasEdge>[];
    final seenEdgeIds = <String>{};
    final rawEdges = json['edges'];
    if (rawEdges is List) {
      for (final item in rawEdges) {
        if (item is! Map) continue;
        final edge = CanvasEdge.fromJson(Map<String, dynamic>.from(item));
        if (edge.id.isEmpty || !seenEdgeIds.add(edge.id)) continue;
        if (edge.fromNodeId == edge.toNodeId) continue;
        if (edge.referencesOutside(seenNodeIds)) continue;
        edges.add(edge);
      }
    }

    return CanvasBoard(
      id: id,
      name: rawName is String && rawName.isNotEmpty ? rawName : '',
      nodes: nodes,
      edges: edges,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['updatedAt'] as num?)?.toInt() ?? createdAt,
      ),
    );
  }
}
