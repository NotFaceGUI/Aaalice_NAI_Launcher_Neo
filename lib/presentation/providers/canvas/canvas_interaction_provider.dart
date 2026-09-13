import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'canvas_interaction_provider.g.dart';

/// 画布当前的交互模式。
enum CanvasInteractionMode {
  /// 选择与拖动节点
  select,

  /// 依次点击两个节点建立连线（触屏等价路径）
  link,
}

/// 正在拖拽中的连线草稿。
@immutable
class CanvasLinkDraft {
  const CanvasLinkDraft({
    required this.fromNodeId,
    required this.currentCanvasPoint,
    this.targetNodeId,
  });

  final String fromNodeId;
  final Offset currentCanvasPoint;
  final String? targetNodeId;

  CanvasLinkDraft copyWith({
    Offset? currentCanvasPoint,
    String? targetNodeId,
  }) => CanvasLinkDraft(
    fromNodeId: fromNodeId,
    currentCanvasPoint: currentCanvasPoint ?? this.currentCanvasPoint,
    targetNodeId: targetNodeId ?? this.targetNodeId,
  );
}

@immutable
class CanvasInteractionState {
  const CanvasInteractionState({
    this.mode = CanvasInteractionMode.select,
    this.selectedNodeId,
    this.selectedEdgeId,
    this.linkDraft,
    this.linkSourceNodeId,
  });

  final CanvasInteractionMode mode;
  final String? selectedNodeId;
  final String? selectedEdgeId;

  /// 指针拖拽中的连线草稿
  final CanvasLinkDraft? linkDraft;

  /// 连线模式下已选中的起点节点
  final String? linkSourceNodeId;

  bool isNodeSelected(String nodeId) => selectedNodeId == nodeId;
  bool isEdgeSelected(String edgeId) => selectedEdgeId == edgeId;

  CanvasInteractionState copyWith({
    CanvasInteractionMode? mode,
    String? selectedNodeId,
    bool clearSelectedNode = false,
    String? selectedEdgeId,
    bool clearSelectedEdge = false,
    CanvasLinkDraft? linkDraft,
    bool clearLinkDraft = false,
    String? linkSourceNodeId,
    bool clearLinkSource = false,
  }) {
    return CanvasInteractionState(
      mode: mode ?? this.mode,
      selectedNodeId: clearSelectedNode
          ? null
          : (selectedNodeId ?? this.selectedNodeId),
      selectedEdgeId: clearSelectedEdge
          ? null
          : (selectedEdgeId ?? this.selectedEdgeId),
      linkDraft: clearLinkDraft ? null : (linkDraft ?? this.linkDraft),
      linkSourceNodeId: clearLinkSource
          ? null
          : (linkSourceNodeId ?? this.linkSourceNodeId),
    );
  }
}

/// 画布选中、交互模式与连线草稿。
@riverpod
class CanvasInteraction extends _$CanvasInteraction {
  @override
  CanvasInteractionState build() => const CanvasInteractionState();

  void selectNode(String? nodeId) {
    state = state.copyWith(
      selectedNodeId: nodeId,
      clearSelectedNode: nodeId == null,
      clearSelectedEdge: true,
      linkSourceNodeId: null,
      clearLinkSource: true,
    );
  }

  void selectEdge(String? edgeId) {
    state = state.copyWith(
      selectedEdgeId: edgeId,
      clearSelectedEdge: edgeId == null,
      clearSelectedNode: true,
      linkSourceNodeId: null,
      clearLinkSource: true,
    );
  }

  void clearSelection() {
    state = state.copyWith(
      clearSelectedNode: true,
      clearSelectedEdge: true,
      clearLinkSource: true,
      clearLinkDraft: true,
    );
  }

  /// 切换连线模式；离开连线模式时清空未完成的连线状态。
  void setMode(CanvasInteractionMode mode) {
    if (state.mode == mode) return;
    state = CanvasInteractionState(
      mode: mode,
      selectedNodeId: mode == CanvasInteractionMode.select
          ? state.selectedNodeId
          : null,
      selectedEdgeId: mode == CanvasInteractionMode.select
          ? state.selectedEdgeId
          : null,
    );
  }

  void startLinkDraft({required String fromNodeId, required Offset fromPoint}) {
    state = state.copyWith(
      linkDraft: CanvasLinkDraft(
        fromNodeId: fromNodeId,
        currentCanvasPoint: fromPoint,
      ),
      clearSelectedEdge: true,
    );
  }

  void updateLinkDraft({
    required Offset currentCanvasPoint,
    String? targetNodeId,
  }) {
    final draft = state.linkDraft;
    if (draft == null) return;
    state = state.copyWith(
      linkDraft: CanvasLinkDraft(
        fromNodeId: draft.fromNodeId,
        currentCanvasPoint: currentCanvasPoint,
        targetNodeId: targetNodeId,
      ),
    );
  }

  void cancelLinkDraft() {
    if (state.linkDraft == null) return;
    state = state.copyWith(clearLinkDraft: true, clearLinkSource: true);
  }

  /// 连线模式下点击节点：第一次记录起点，第二次建立连线。
  ///
  /// 返回要建立的连线端点；为空表示这次点击只是选中了起点。
  ({String fromNodeId, String toNodeId})? registerLinkTap(String nodeId) {
    final source = state.linkSourceNodeId;
    if (source == null) {
      state = state.copyWith(linkSourceNodeId: nodeId, clearSelectedNode: true);
      return null;
    }
    state = state.copyWith(clearLinkSource: true);
    if (source == nodeId) return null;
    return (fromNodeId: source, toNodeId: nodeId);
  }

  /// 连线完成后同步选中新连线。
  void selectNewEdge(String edgeId) {
    state = state.copyWith(selectedEdgeId: edgeId, clearSelectedNode: true);
  }
}

/// 记录哪些指针已被节点认领。
///
/// 画布视口用原始指针事件实现平移与缩放（不参与手势竞技场），而节点上的
/// 拖动需要独占指针。指针在命中测试路径上由内向外派发，节点会先于视口收到
/// `PointerDown`，所以节点在此登记后，视口就知道该指针不属于自己。
@Riverpod(keepAlive: true)
CanvasPointerRegistry canvasPointerRegistry(Ref ref) => CanvasPointerRegistry();

class CanvasPointerRegistry {
  final Set<int> _ownedPointers = <int>{};

  void claim(int pointer) => _ownedPointers.add(pointer);

  void release(int pointer) => _ownedPointers.remove(pointer);

  bool isOwned(int pointer) => _ownedPointers.contains(pointer);

  void clear() => _ownedPointers.clear();
}

/// Single transient canvas-space rectangle shared by node layout and edges.
/// The document changes only when the gesture is committed.
@Riverpod(keepAlive: true)
CanvasDragTracker canvasDragTracker(Ref ref) {
  final tracker = CanvasDragTracker();
  ref.onDispose(tracker.dispose);
  return tracker;
}

class CanvasDragTracker extends ChangeNotifier {
  String? _nodeId;
  Rect? _previewRect;

  String? get nodeId => _nodeId;

  bool get isDragging => _nodeId != null;

  Rect rectFor(String nodeId, Rect persisted) =>
      _nodeId == nodeId ? (_previewRect ?? persisted) : persisted;

  void preview(String nodeId, Rect rect) {
    if (_nodeId == nodeId && _previewRect == rect) return;
    _nodeId = nodeId;
    _previewRect = rect;
    notifyListeners();
  }

  void end() {
    if (_nodeId == null) return;
    _nodeId = null;
    _previewRect = null;
    notifyListeners();
  }
}
