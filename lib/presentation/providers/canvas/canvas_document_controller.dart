import 'dart:async';
import 'dart:ui';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../data/models/canvas/canvas_board.dart';
import '../../../data/models/canvas/canvas_document.dart';
import '../../../data/models/canvas/canvas_edge.dart';
import '../../../data/models/canvas/canvas_node.dart';
import '../../../data/models/canvas/canvas_node_kind.dart';
import '../../../data/models/canvas/canvas_node_params.dart';
import '../../../data/services/canvas/canvas_repository.dart';
import 'canvas_repository_provider.dart';
import 'canvas_view_controller.dart';
import 'canvas_generation_preview.dart';

part 'canvas_document_controller.g.dart';

/// 无限画布文档状态：多块画布 + 当前画布。
///
/// 全部修改先在内存里乐观生效再异步落盘，拖动等高频操作由调用方在手势
/// 结束时才提交，因此这里用一个短防抖把连续修改合并成一次写入。
///
/// 所有修改方法都会先等待首次加载完成，避免文档还没读回来就把内存里的
/// 空文档写回磁盘。
///
/// keepAlive：画布关闭后仍要保持文档（提示词区的固定种子入口、结果卡片都
/// 可能在画布未打开时写入），生命周期与应用一致。
@Riverpod(keepAlive: true)
class CanvasDocumentController extends _$CanvasDocumentController {
  /// 连续修改合并成一次写入的等待时间
  static const Duration persistDebounce = Duration(milliseconds: 300);

  late final CanvasRepository _repository;
  late final CanvasViewController _viewport;
  Timer? _persistTimer;

  @override
  Future<CanvasDocument> build() async {
    _repository = ref.watch(canvasRepositoryProvider);
    _viewport = ref.read(canvasViewControllerProvider);
    ref.onDispose(() {
      _persistTimer?.cancel();
      _persistTimer = null;
    });
    return await _repository.load() ?? CanvasDocument.loading;
  }

  /// 当前文档；首次加载完成前是占位文档。
  CanvasDocument get document => state.valueOrNull ?? CanvasDocument.loading;

  bool get isReady => state.hasValue;

  /// 当前正在查看的画布。
  CanvasBoard? get activeBoard => document.activeBoard;

  /// 立即落盘；关闭画布或离开页面前调用，避免丢掉防抖窗口内的修改。
  Future<void> flush() async {
    if (!isReady) return;
    _persistTimer?.cancel();
    _persistTimer = null;
    await _repository.save(document);
  }

  // ==================== 画布管理 ====================

  /// 新建一块画布并切换过去，返回画布 id。
  Future<String> createBoard(String name) async {
    await future;
    final id = _newId();
    final now = DateTime.now();
    final board = CanvasBoard(
      id: id,
      name: name.trim(),
      nodes: const [],
      edges: const [],
      createdAt: now,
      updatedAt: now,
    );
    _commit(
      document.copyWith(boards: [...document.boards, board], activeBoardId: id),
    );
    return id;
  }

  Future<void> renameBoard(String id, String name) async {
    await future;
    final board = document.boardById(id);
    final trimmed = name.trim();
    if (board == null || trimmed.isEmpty || trimmed == board.name) return;
    _commit(
      document.withBoard(
        board.copyWith(name: trimmed, updatedAt: DateTime.now()),
      ),
    );
  }

  /// 删除一块画布；至少保留一块，删掉当前画布时切到剩下第一块。
  Future<void> deleteBoard(String id) async {
    await future;
    final doc = document;
    if (doc.boards.length <= 1) return;
    final next = [
      for (final board in doc.boards)
        if (board.id != id) board,
    ];
    if (next.length == doc.boards.length) return;
    _commit(
      doc.copyWith(
        boards: next,
        activeBoardId: doc.activeBoardId == id
            ? next.first.id
            : doc.activeBoardId,
      ),
    );
  }

  Future<void> selectBoard(String id) async {
    await future;
    final doc = document;
    if (doc.activeBoardId == id || doc.boardById(id) == null) return;
    _commit(doc.copyWith(activeBoardId: id));
  }

  // ==================== 新增节点 ====================

  /// Complete a reserved preview in its original board and position.
  Future<bool> addGeneratedImageNode({
    required String boardId,
    required String id,
    required Rect rect,
    required String imageRelativePath,
    int? seed,
    CanvasNodeParams? params,
  }) async {
    await future;
    final board = document.boardById(boardId);
    if (board == null || board.nodeById(id) != null) return false;
    final now = DateTime.now();
    final node = CanvasNode(
      id: id,
      kind: CanvasNodeKind.image,
      x: rect.left,
      y: rect.top,
      width: rect.width,
      height: rect.height,
      zOrder: board.maxZOrder + 1,
      imageRelativePath: imageRelativePath,
      seed: seed,
      params: params,
      createdAt: now,
      updatedAt: now,
    );
    _commit(
      document.withBoard(
        board.copyWith(nodes: [...board.nodes, node], updatedAt: now),
      ),
    );
    return true;
  }

  /// 新增图片节点，返回节点 id。
  ///
  /// [aspectRatio] 为图片宽高比（宽 / 高）；[imageRelativePath] 必须已经由
  /// `CanvasImageImporter` 准备成图库相对路径。
  Future<String> addImageNode({
    required String imageRelativePath,
    required double aspectRatio,
    int? seed,
    CanvasNodeParams? params,
  }) async {
    await future;
    const width = CanvasNode.defaultImageWidth;
    final safeAspect = aspectRatio.isFinite && aspectRatio > 0
        ? aspectRatio
        : 1.0;
    final height = (width / safeAspect)
        .clamp(CanvasNode.minNodeHeight, CanvasNode.maxNodeHeight)
        .toDouble();
    final now = DateTime.now();
    return _appendNode(
      CanvasNode(
        id: _newId(),
        kind: CanvasNodeKind.image,
        x: 0,
        y: 0,
        width: width,
        height: height,
        imageRelativePath: imageRelativePath,
        seed: seed,
        params: params,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// 新增种子待办节点（尚未出图，只记录种子与参数快照）。
  Future<String> addSeedTodoNode({
    required int seed,
    CanvasNodeParams? params,
  }) async {
    await future;
    final now = DateTime.now();
    return _appendNode(
      CanvasNode(
        id: _newId(),
        kind: CanvasNodeKind.seedTodo,
        x: 0,
        y: 0,
        width: CanvasNode.defaultSeedTodoWidth,
        height: CanvasNode.defaultSeedTodoHeight,
        seed: seed,
        params: params,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// 新增文本便签节点。
  Future<String> addNoteNode({String text = ''}) async {
    await future;
    final now = DateTime.now();
    return _appendNode(
      CanvasNode(
        id: _newId(),
        kind: CanvasNodeKind.note,
        x: 0,
        y: 0,
        width: CanvasNode.defaultNoteWidth,
        height: CanvasNode.defaultNoteHeight,
        noteText: text,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  // ==================== 节点编辑 ====================

  /// Gesture geometry is committed together, never as separate move/resize writes.
  Future<void> setNodeRect(
    String id,
    Rect rect, {
    required String boardId,
  }) async {
    await future;
    if (document.activeBoardId != boardId || !rect.isFinite || rect.isEmpty) {
      return;
    }
    _updateNode(
      id,
      (node) => node.copyWith(
        x: rect.left,
        y: rect.top,
        width: rect.width
            .clamp(CanvasNode.minNodeWidth, CanvasNode.maxNodeWidth)
            .toDouble(),
        height: rect.height
            .clamp(CanvasNode.minNodeHeight, CanvasNode.maxNodeHeight)
            .toDouble(),
      ),
    );
  }

  Future<void> moveNode(
    String id, {
    required double x,
    required double y,
  }) async {
    await future;
    _updateNode(id, (node) => node.copyWith(x: x, y: y));
  }

  Future<void> resizeNode(
    String id, {
    required double width,
    required double height,
  }) async {
    await future;
    _updateNode(
      id,
      (node) => node.copyWith(
        width: width
            .clamp(CanvasNode.minNodeWidth, CanvasNode.maxNodeWidth)
            .toDouble(),
        height: height
            .clamp(CanvasNode.minNodeHeight, CanvasNode.maxNodeHeight)
            .toDouble(),
      ),
    );
  }

  Future<void> setNoteText(String id, String text) async {
    await future;
    _updateNode(id, (node) => node.copyWith(noteText: text));
  }

  Future<void> setTodoDone(String id, {required bool done}) async {
    await future;
    _updateNode(id, (node) => node.copyWith(todoDone: done));
  }

  /// 把节点移到最上层，避免被其它节点压住
  Future<void> bringNodeToFront(String id) async {
    await future;
    final board = document.activeBoard;
    if (board == null) return;
    final current = board.nodeById(id);
    if (current == null) return;
    final nextZ = board.maxZOrder + 1;
    if (current.zOrder == nextZ - 1) return;
    _updateNode(id, (node) => node.copyWith(zOrder: nextZ));
  }

  /// 删除节点及与之相连的全部连线
  Future<void> removeNode(String id) async {
    await future;
    _updateActiveBoard((board) {
      if (board.nodeById(id) == null) return board;
      return board.copyWith(
        nodes: [
          for (final node in board.nodes)
            if (node.id != id) node,
        ],
        edges: [
          for (final edge in board.edges)
            if (edge.fromNodeId != id && edge.toNodeId != id) edge,
        ],
        updatedAt: DateTime.now(),
      );
    });
  }

  /// 清空当前画布：移除全部节点与连线；图库里的图片文件不受影响。
  Future<void> clear() async {
    await future;
    _updateActiveBoard((board) {
      if (board.isEmpty) return board;
      return board.copyWith(
        nodes: const [],
        edges: const [],
        updatedAt: DateTime.now(),
      );
    });
  }

  // ==================== 连线 ====================

  /// 建立连线；自连、重复连线或端点不存在时返回 null。
  Future<String?> addEdge({
    required String fromNodeId,
    required String toNodeId,
  }) async {
    final requestedBoardId = state.valueOrNull?.activeBoardId;
    await future;
    if (requestedBoardId != null &&
        document.activeBoardId != requestedBoardId) {
      return null;
    }
    if (fromNodeId == toNodeId) return null;
    final board = document.activeBoard;
    if (board == null) return null;
    if (board.nodeById(fromNodeId) == null ||
        board.nodeById(toNodeId) == null) {
      return null;
    }
    for (final edge in board.edges) {
      if (edge.fromNodeId == fromNodeId && edge.toNodeId == toNodeId) {
        return null;
      }
    }
    final now = DateTime.now();
    final edge = CanvasEdge(
      id: _newId(),
      fromNodeId: fromNodeId,
      toNodeId: toNodeId,
      createdAt: now,
      updatedAt: now,
    );
    _updateActiveBoard(
      (board) => board.copyWith(edges: [...board.edges, edge], updatedAt: now),
    );
    return edge.id;
  }

  Future<void> setEdgeLabel(String id, String? label) async {
    await future;
    final trimmed = label?.trim();
    final normalized = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    _updateActiveBoard((board) {
      final edges = <CanvasEdge>[];
      var changed = false;
      for (final edge in board.edges) {
        if (edge.id != id) {
          edges.add(edge);
          continue;
        }
        changed = true;
        edges.add(
          normalized == null
              ? edge.copyWith(clearLabel: true)
              : edge.copyWith(label: normalized),
        );
      }
      if (!changed) return board;
      return board.copyWith(edges: edges, updatedAt: DateTime.now());
    });
  }

  Future<void> removeEdge(String id) async {
    await future;
    _updateActiveBoard((board) {
      if (!board.edges.any((edge) => edge.id == id)) return board;
      return board.copyWith(
        edges: [
          for (final edge in board.edges)
            if (edge.id != id) edge,
        ],
        updatedAt: DateTime.now(),
      );
    });
  }

  // ==================== 内部 ====================

  String _appendNode(CanvasNode node) {
    final board = document.activeBoard;
    if (board == null) return node.id;
    final position = _nextPosition(
      board,
      width: node.width,
      height: node.height,
    );
    final placed = node.copyWith(
      x: position.x,
      y: position.y,
      zOrder: board.maxZOrder + 1,
    );
    _updateActiveBoard(
      (current) => current.copyWith(
        nodes: [...current.nodes, placed],
        updatedAt: DateTime.now(),
      ),
    );
    return placed.id;
  }

  void _updateNode(String id, CanvasNode Function(CanvasNode node) transform) {
    _updateActiveBoard((board) {
      final nodes = <CanvasNode>[];
      var changed = false;
      for (final node in board.nodes) {
        if (node.id != id) {
          nodes.add(node);
          continue;
        }
        changed = true;
        nodes.add(transform(node).copyWith(updatedAt: DateTime.now()));
      }
      if (!changed) return board;
      return board.copyWith(nodes: nodes, updatedAt: DateTime.now());
    });
  }

  /// 在当前画布上做一次修改；返回同一实例表示没有变化，不产生写入。
  void _updateActiveBoard(CanvasBoard Function(CanvasBoard board) transform) {
    final board = document.activeBoard;
    if (board == null) return;
    final next = transform(board);
    if (identical(next, board)) return;
    _commit(document.withBoard(next));
  }

  /// 新节点落点：以当前视口中心为首选位置，重叠时向外扫描。
  ({double x, double y}) _nextPosition(
    CanvasBoard board, {
    required double width,
    required double height,
  }) {
    final center = _viewport.viewportCenterInCanvas;
    final occupied = board.copyWith(
      nodes: [
        ...board.nodes,
        for (final preview in ref.read(canvasGenerationPreviewProvider).entries)
          if (preview.boardId == board.id) preview.placeholder,
      ],
    );
    return occupied.findFreePosition(
      width: width,
      height: height,
      nearX: center.dx - width / 2,
      nearY: center.dy - height / 2,
    );
  }

  void _commit(CanvasDocument next) {
    state = AsyncData(next);
    _persistTimer?.cancel();
    _persistTimer = Timer(persistDebounce, () {
      _persistTimer = null;
      unawaited(_repository.save(document));
    });
  }

  static String _newId() => const Uuid().v4();
}
