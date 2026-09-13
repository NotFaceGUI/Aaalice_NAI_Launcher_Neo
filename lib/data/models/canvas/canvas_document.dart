import 'canvas_board.dart';
import 'canvas_edge.dart';
import 'canvas_node.dart';

/// 无限画布文档：全部画布与当前正在查看的画布。
///
/// 画布是按整篇文档读写的小型数据集，这里同时承载落点计算等纯几何逻辑，
/// 便于脱离 UI 单独测试。节点/连线相关的便捷读取都代理到当前画布，
/// 调用方不需要各自判断"哪块画布"。
class CanvasDocument {
  /// 文档格式版本。
  ///
  /// v1 是单画布格式（顶层直接放 nodes/edges），v2 起为多画布；
  /// [fromJson] 会把 v1 文件迁移成一块默认画布。
  static const int currentVersion = 2;

  /// 加载完成前的占位文档；只在首帧使用，视图此时显示加载态。
  static final CanvasDocument loading = CanvasDocument(
    boards: [
      CanvasBoard(
        id: 'default',
        name: '',
        nodes: const [],
        edges: const [],
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      ),
    ],
    activeBoardId: 'default',
  );

  final List<CanvasBoard> boards;
  final String activeBoardId;

  const CanvasDocument({required this.boards, required this.activeBoardId});

  /// 由一块画布构成的文档；降级路径与测试用。
  factory CanvasDocument.singleBoard({
    String boardId = 'default',
    String name = '',
    List<CanvasNode> nodes = const [],
    List<CanvasEdge> edges = const [],
  }) {
    final now = DateTime.now();
    return CanvasDocument(
      boards: [
        CanvasBoard(
          id: boardId,
          name: name,
          nodes: nodes,
          edges: edges,
          createdAt: now,
          updatedAt: now,
        ),
      ],
      activeBoardId: boardId,
    );
  }

  CanvasBoard? get activeBoard {
    for (final board in boards) {
      if (board.id == activeBoardId) return board;
    }
    return boards.isEmpty ? null : boards.first;
  }

  CanvasBoard? boardById(String id) {
    for (final board in boards) {
      if (board.id == id) return board;
    }
    return null;
  }

  // ==================== 当前画布的便捷读取 ====================

  List<CanvasNode> get nodes => activeBoard?.nodes ?? const [];
  List<CanvasEdge> get edges => activeBoard?.edges ?? const [];
  List<CanvasNode> get nodesByZOrder => activeBoard?.nodesByZOrder ?? const [];
  int get maxZOrder => activeBoard?.maxZOrder ?? 0;
  bool get isEmpty => activeBoard?.isEmpty ?? true;

  CanvasNode? nodeById(String id) => activeBoard?.nodeById(id);

  /// 以某块画布替换同 id 的画布；未找到时追加。
  CanvasDocument withBoard(CanvasBoard board) {
    final next = <CanvasBoard>[];
    var replaced = false;
    for (final existing in boards) {
      if (existing.id == board.id) {
        next.add(board);
        replaced = true;
      } else {
        next.add(existing);
      }
    }
    if (!replaced) next.add(board);
    return CanvasDocument(boards: next, activeBoardId: activeBoardId);
  }

  CanvasDocument copyWith({List<CanvasBoard>? boards, String? activeBoardId}) =>
      CanvasDocument(
        boards: boards ?? this.boards,
        activeBoardId: activeBoardId ?? this.activeBoardId,
      );

  /// 迁移或写入用：把顶层 nodes/edges 包成一块画布。
  static CanvasDocument fromLegacyBoard({
    required String boardId,
    required String boardName,
    required List<CanvasNode> nodes,
    required List<CanvasEdge> edges,
  }) {
    final now = DateTime.now();
    return CanvasDocument(
      boards: [
        CanvasBoard(
          id: boardId,
          name: boardName,
          nodes: nodes,
          edges: edges,
          createdAt: now,
          updatedAt: now,
        ),
      ],
      activeBoardId: boardId,
    );
  }

  Map<String, dynamic> toJson() => {
    'version': currentVersion,
    'activeBoardId': activeBoardId,
    'boards': [for (final board in boards) board.toJson()],
  };

  /// 解析文档。
  ///
  /// 未知版本返回 null（由调用方决定是否覆盖）；v1 单画布文件会迁移成一块
  /// 未命名画布（名称由界面按语言兜底显示），迁移只发生在内存里，
  /// 下一次写入即落成新格式。
  static CanvasDocument? fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    if (version is! num || version > currentVersion) return null;

    if (version < 2) return _migrateV1(json);

    final boards = <CanvasBoard>[];
    final seenIds = <String>{};
    final rawBoards = json['boards'];
    if (rawBoards is List) {
      for (final item in rawBoards) {
        if (item is! Map) continue;
        final board = CanvasBoard.fromJson(Map<String, dynamic>.from(item));
        if (board == null || !seenIds.add(board.id)) continue;
        boards.add(board);
      }
    }
    if (boards.isEmpty) return null;

    final rawActive = json['activeBoardId'];
    final activeBoardId = rawActive is String && seenIds.contains(rawActive)
        ? rawActive
        : boards.first.id;
    return CanvasDocument(boards: boards, activeBoardId: activeBoardId);
  }

  /// v1（单画布）-> v2：顶层 nodes/edges 成为第一块画布。
  static CanvasDocument? _migrateV1(Map<String, dynamic> json) {
    final migrated = CanvasBoard.fromJson({
      'id': 'legacy',
      // 名称留空，界面按当前语言显示"未命名画布"
      'name': '',
      'nodes': json['nodes'],
      'edges': json['edges'],
    });
    if (migrated == null) return null;
    return CanvasDocument(boards: [migrated], activeBoardId: migrated.id);
  }
}
