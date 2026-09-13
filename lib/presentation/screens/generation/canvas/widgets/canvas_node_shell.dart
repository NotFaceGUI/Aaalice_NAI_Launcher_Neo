import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/localization_extension.dart';
import '../../../../../data/models/canvas/canvas_node.dart';
import '../../../../../data/models/canvas/canvas_node_kind.dart';
import '../../../../adaptive/interaction_policy.dart';
import '../../../../providers/canvas/canvas_document_controller.dart';
import '../../../../providers/canvas/canvas_interaction_provider.dart';
import '../../../../themes/core/layered_surface_style.dart';
import '../../../../themes/theme_extension.dart';
import '../../../../widgets/common/pro_context_menu.dart';
import '../canvas_actions.dart';
import '../canvas_node_geometry.dart';
import 'canvas_node_entrance.dart';
import 'canvas_menu.dart';
import 'canvas_node_handles.dart';

export '../canvas_node_geometry.dart' show CanvasNodeCorner, CanvasNodeSide;

/// 画布节点外壳：定位、选中、hover、拖动、四角缩放与四边连线。
///
/// 坐标契约：本组件的布局盒由节点层按**屏幕单位**给出（`节点尺寸 × scale`
/// 再向四周扩出 [handleInset]）。手柄区内缩回去的位置才是节点正文，正文
/// 内部再乘一次 scale 还原画布单位。这样祖先盒与节点的屏幕范围一致，
/// 命中测试在任何缩放级别都能到达节点，手柄的命中区也不随缩放变小。
///
/// 拖动与缩放共享一个画布空间预览矩形，节点层和连线层同时消费；结束时
/// 原子提交位置与尺寸，取消时清空预览。全局指针位移只转换一次。
class CanvasNodeShell extends ConsumerStatefulWidget {
  const CanvasNodeShell({
    super.key,
    required this.node,
    required this.scale,
    required this.selected,
    required this.linkSourceActive,
    required this.resizable,
    required this.aspectLocked,
    this.absolutePath,
    this.onDoubleTap,
    this.previewSize,
    this.handleLayout,
    this.animateEntrance = true,
    required this.contentBuilder,
  });

  final CanvasNode node;

  /// 当前视口缩放；层已经按它算好盒子尺寸，这里用它换算指针位移与正文缩放
  final double scale;
  final Size? previewSize;
  final CanvasNodeHandleLayout? handleLayout;
  final bool animateEntrance;

  /// 图片节点的磁盘路径，供菜单按需解析提示词
  final String? absolutePath;

  final bool selected;

  /// 连线模式下已被选为起点
  final bool linkSourceActive;

  /// 是否提供四角缩放手柄
  final bool resizable;

  /// 缩放时是否锁定宽高比（图片节点必须按原图比例缩放）
  final bool aspectLocked;

  /// 双击节点（便签用它进入编辑）
  final VoidCallback? onDoubleTap;

  final Widget Function(BuildContext context, bool hovered) contentBuilder;

  static const double cornerRadius = 12;

  /// 常规鼠标布局的基础外扩；小节点与触屏使用 handleLayout 的实际外扩。
  static const double handleInset = 14;

  @override
  ConsumerState<CanvasNodeShell> createState() => _CanvasNodeShellState();
}

class _CanvasNodeShellState extends ConsumerState<CanvasNodeShell> {
  Rect? _gestureStartRect;
  Offset? _gestureStartPointer;
  double _gestureScale = 1;
  String? _gestureBoardId;
  int _gestureEpoch = 0;
  String? _linkBoardId;
  CanvasNodeCorner? _resizeCorner;
  bool _hovered = false;
  bool _hoveringHandle = false;

  /// 拖动广播器与指针登记表都在 initState 取好。
  ///
  /// 指针回调来自原始 `Listener`（不参与手势竞技场），事件可能迟到到元素
  /// 已经销毁之后；在这些回调里读 `ref` 会抛 "Cannot use ref after the
  /// widget was disposed"。握住稳定句柄后就不再依赖元素存活。
  late final CanvasDragTracker _dragTracker;
  late final CanvasPointerRegistry _pointerRegistry;

  @override
  void initState() {
    super.initState();
    _dragTracker = ref.read(canvasDragTrackerProvider);
    _pointerRegistry = ref.read(canvasPointerRegistryProvider);
  }

  @override
  void dispose() {
    // 拖动被外部销毁打断时，清掉广播出去的位移。
    //
    // 必须延到微任务：dispose 发生在 finalizeTree 的锁定阶段，此时同步通知
    // 会让监听它的连线层 setState 并抛 "widget tree was locked"。
    if (_dragTracker.nodeId == widget.node.id) {
      final tracker = _dragTracker;
      final id = widget.node.id;
      scheduleMicrotask(() {
        if (tracker.nodeId == id) tracker.end();
      });
    }
    super.dispose();
  }

  double get _scale => widget.scale;
  CanvasNodeHandleLayout get _handles =>
      widget.handleLayout ??
      CanvasNodeHandleLayout(
        Size(widget.node.width, widget.node.height) * _scale,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final node = widget.node;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final touchPresentation =
        context.interactionPolicy.prefersTouchPresentation;
    final isLinkSource =
        widget.linkSourceActive ||
        ref.watch(
          canvasInteractionProvider.select(
            (state) =>
                state.linkSourceNodeId == node.id ||
                state.linkDraft?.fromNodeId == node.id,
          ),
        );
    final highlighted = widget.selected || isLinkSource;
    final showHandles = _hovered || highlighted || touchPresentation;

    final previewSize = widget.previewSize ?? Size(node.width, node.height);
    final inset = _handles.inset;
    // 手柄按预览尺寸摆放，缩放过程中跟随指针；提交后由节点层重新给出盒子
    final bodyWidth = previewSize.width * _scale;
    final bodyHeight = previewSize.height * _scale;

    return Listener(
      behavior: HitTestBehavior.deferToChild,
      onPointerDown: (event) {
        _pointerRegistry.claim(event.pointer);
        // 按下即选中：如果等 onTap，存在双击识别时单击要等满双击超时，
        // 选中会明显延迟；画布上"先选中再操作"才是主流程
        _handlePointerSelect();
      },
      onPointerUp: (event) => _pointerRegistry.release(event.pointer),
      onPointerCancel: (event) {
        _pointerRegistry.release(event.pointer);
        _cancelGeometry();
        if (mounted) {
          ref.read(canvasInteractionProvider.notifier).cancelLinkDraft();
        }
      },
      child: MouseRegion(
        hitTestBehavior: HitTestBehavior.deferToChild,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: inset,
              top: inset,
              width: bodyWidth,
              height: bodyHeight,
              child: _buildBody(
                context,
                theme,
                node,
                previewSize,
                highlighted: highlighted,
                reduceMotion: reduceMotion,
                touchPresentation: touchPresentation,
              ),
            ),
            if (showHandles && widget.resizable)
              ..._buildCornerHandles(faded: !highlighted && !_hoveringHandle),
            if (showHandles)
              ..._buildEdgeHandles(faded: !highlighted && !_hoveringHandle),
          ],
        ),
      ),
    );
  }

  /// 正文：把手柄区的紧约束放开，让内容保持画布单位再整体缩放。
  ///
  /// `OverflowBox` 在这里是必需的：它给子树的是宽松约束，子盒才能保持
  /// 画布尺寸；否则 `SizedBox(node.size)` 会被压成 `node.size × scale`，
  /// 再乘一次 scale 就变成二次缩小。
  Widget _buildBody(
    BuildContext context,
    ThemeData theme,
    CanvasNode node,
    Size previewSize, {
    required bool highlighted,
    required bool reduceMotion,
    required bool touchPresentation,
  }) {
    final scheme = theme.colorScheme;
    return OverflowBox(
      alignment: Alignment.topLeft,
      minWidth: 0,
      maxWidth: double.infinity,
      minHeight: 0,
      maxHeight: double.infinity,
      child: Transform.scale(
        scale: _scale,
        alignment: Alignment.topLeft,
        child: SizedBox.fromSize(
          size: previewSize,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            // 选中在按下时处理（见 Listener），这里只管双击与拖动
            onDoubleTap: widget.onDoubleTap,
            onSecondaryTapUp: (details) => _openMenu(details.globalPosition),
            onLongPressStart: (details) => _openMenu(details.globalPosition),
            onPanStart: (details) => _beginGeometry(details.globalPosition),
            onPanUpdate: (details) => _updateGeometry(details.globalPosition),
            onPanEnd: (_) => _commitGeometry(),
            onPanCancel: _cancelGeometry,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: AnimatedContainer(
                    duration: reduceMotion
                        ? Duration.zero
                        : theme.appTheme.fastDuration,
                    curve: theme.appTheme.standardCurve,
                    decoration: BoxDecoration(
                      color: sectionSurfaceColor(scheme),
                      borderRadius: BorderRadius.circular(
                        CanvasNodeShell.cornerRadius,
                      ),
                      boxShadow: _hovered && !touchPresentation
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.16),
                                blurRadius: 14,
                                offset: const Offset(0, 6),
                              ),
                            ]
                          : null,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: CanvasNodeEntrance(
                      enabled: widget.animateEntrance && !reduceMotion,
                      child: widget.contentBuilder(context, _hovered),
                    ),
                  ),
                ),
                // 选中/连线起点指示画在上层，不参与布局，也不改变内容尺寸
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          CanvasNodeShell.cornerRadius,
                        ),
                        border: Border.all(
                          color: highlighted
                              ? scheme.primary
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==================== 四角缩放 ====================

  List<Widget> _buildCornerHandles({required bool faded}) {
    return [
      for (final corner in CanvasNodeCorner.values)
        Positioned.fromRect(
          rect: _handles.cornerRect(corner),
          child: CanvasResizeCornerHandle(
            key: ValueKey('resize-${widget.node.id}-${corner.name}'),
            corner: corner,
            faded: faded,
            onHoverChanged: _setHoveringHandle,
            onStart: (point) => _beginGeometry(point, corner: corner),
            onUpdate: _updateGeometry,
            onEnd: _commitGeometry,
            onCancel: _cancelGeometry,
          ),
        ),
    ];
  }

  // ==================== 四边连线 ====================

  List<Widget> _buildEdgeHandles({required bool faded}) {
    return [
      for (final side in CanvasNodeSide.values)
        Positioned.fromRect(
          rect: _handles.sideRect(side),
          child: CanvasLinkEdgeHandle(
            key: ValueKey('link-${widget.node.id}-${side.name}'),
            side: side,
            faded: faded,
            onHoverChanged: _setHoveringHandle,
            onStart: _handleLinkStart,
            onUpdate: _handleLinkUpdate,
            onEnd: _handleLinkEnd,
            onCancel: () =>
                ref.read(canvasInteractionProvider.notifier).cancelLinkDraft(),
          ),
        ),
    ];
  }

  void _handleLinkStart(Offset globalPosition) {
    if (!mounted || _dragTracker.isDragging) return;
    _linkBoardId = ref
        .read(canvasDocumentControllerProvider)
        .valueOrNull
        ?.activeBoardId;
    final point = _toCanvasPoint(globalPosition);
    ref
        .read(canvasInteractionProvider.notifier)
        .startLinkDraft(fromNodeId: widget.node.id, fromPoint: point);
  }

  void _handleLinkUpdate(Offset globalPosition) {
    if (!mounted || _linkBoardId == null) return;
    final point = _toCanvasPoint(globalPosition);
    ref
        .read(canvasInteractionProvider.notifier)
        .updateLinkDraft(
          currentCanvasPoint: point,
          targetNodeId: _nodeAt(point),
        );
  }

  void _handleLinkEnd() {
    if (!mounted || _linkBoardId == null) return;
    final boardId = _linkBoardId;
    _linkBoardId = null;
    final interaction = ref.read(canvasInteractionProvider.notifier);
    final draft = ref.read(canvasInteractionProvider).linkDraft;
    interaction.cancelLinkDraft();
    final targetId = draft?.targetNodeId;
    if (draft == null ||
        targetId == null ||
        ref.read(canvasDocumentControllerProvider).valueOrNull?.activeBoardId !=
            boardId) {
      return;
    }
    _createEdge(draft.fromNodeId, targetId);
  }

  Future<void> _createEdge(String fromNodeId, String toNodeId) async {
    final interaction = ref.read(canvasInteractionProvider.notifier);
    final boardId = ref
        .read(canvasDocumentControllerProvider)
        .valueOrNull
        ?.activeBoardId;
    final edgeId = await ref
        .read(canvasDocumentControllerProvider.notifier)
        .addEdge(fromNodeId: fromNodeId, toNodeId: toNodeId);
    if (!mounted ||
        edgeId == null ||
        ref.read(canvasDocumentControllerProvider).valueOrNull?.activeBoardId !=
            boardId) {
      return;
    }
    interaction.selectNewEdge(edgeId);
  }

  /// 全局坐标 -> 画布坐标。
  ///
  /// 本组件布局盒的左上角对应画布坐标 `节点左上角 - 手柄区`，用它反推，
  /// 避免把视口 RenderBox 层层传下来。
  Offset _toCanvasPoint(Offset globalPosition) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize || _scale <= 0) {
      return Offset.zero;
    }
    final originGlobal = renderObject.localToGlobal(Offset.zero);
    final node = widget.node;
    final insetCanvas = _handles.inset / _scale;
    return Offset(node.x - insetCanvas, node.y - insetCanvas) +
        (globalPosition - originGlobal) / _scale;
  }

  String? _nodeAt(Offset canvasPoint) {
    final document = ref.read(canvasDocumentControllerProvider).valueOrNull;
    if (document == null) return null;
    for (final node in document.nodesByZOrder.reversed) {
      if (node.id == widget.node.id) continue;
      if (node.intersects(
        canvasPoint.dx,
        canvasPoint.dy,
        canvasPoint.dx + 1,
        canvasPoint.dy + 1,
      )) {
        return node.id;
      }
    }
    return null;
  }

  // ==================== 拖动与选中 ====================

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  void _setHoveringHandle(bool value) {
    if (_hoveringHandle == value) return;
    setState(() => _hoveringHandle = value);
  }

  /// 按下节点：连线模式下记录端点，否则直接选中。
  void _handlePointerSelect() {
    // 原始指针事件可能迟到到元素已销毁之后
    if (!mounted) return;
    final interaction = ref.read(canvasInteractionProvider.notifier);
    if (ref.read(canvasInteractionProvider).mode ==
        CanvasInteractionMode.link) {
      final endpoints = interaction.registerLinkTap(widget.node.id);
      if (endpoints == null) return;
      _createEdge(endpoints.fromNodeId, endpoints.toNodeId);
      return;
    }
    interaction.selectNode(widget.node.id);
  }

  void _beginGeometry(Offset globalPosition, {CanvasNodeCorner? corner}) {
    if (!mounted ||
        _dragTracker.isDragging ||
        ref.read(canvasInteractionProvider).mode ==
            CanvasInteractionMode.link) {
      return;
    }
    final node = widget.node;
    _gestureEpoch++;
    _gestureStartRect = Rect.fromLTWH(node.x, node.y, node.width, node.height);
    _gestureStartPointer = globalPosition;
    _gestureScale = _scale;
    _gestureBoardId = ref
        .read(canvasDocumentControllerProvider)
        .valueOrNull
        ?.activeBoardId;
    _resizeCorner = corner;
    _dragTracker.preview(node.id, _gestureStartRect!);
    unawaited(
      ref
          .read(canvasDocumentControllerProvider.notifier)
          .bringNodeToFront(node.id),
    );
  }

  void _updateGeometry(Offset globalPosition) {
    final start = _gestureStartRect;
    final pointer = _gestureStartPointer;
    if (!mounted || start == null || pointer == null) return;
    if (ref.read(canvasDocumentControllerProvider).valueOrNull?.activeBoardId !=
        _gestureBoardId) {
      _cancelGeometry();
      return;
    }
    final delta = globalPosition - pointer;
    final corner = _resizeCorner;
    final rect = corner == null
        ? start.shift(delta / _gestureScale)
        : resizeCanvasNodeRect(
            corner,
            start,
            delta,
            scale: _gestureScale,
            aspectLocked: widget.aspectLocked,
          );
    _dragTracker.preview(widget.node.id, rect);
  }

  Future<void> _commitGeometry() async {
    final start = _gestureStartRect;
    final boardId = _gestureBoardId;
    if (!mounted || start == null || boardId == null) return;
    final rect = _dragTracker.rectFor(widget.node.id, start);
    final epoch = _gestureEpoch;
    _gestureStartRect = null;
    _gestureStartPointer = null;
    try {
      if (rect != start) {
        await ref
            .read(canvasDocumentControllerProvider.notifier)
            .setNodeRect(widget.node.id, rect, boardId: boardId);
      }
    } finally {
      if (mounted &&
          epoch == _gestureEpoch &&
          _dragTracker.nodeId == widget.node.id) {
        _dragTracker.end();
      }
    }
  }

  void _cancelGeometry() {
    _gestureEpoch++;
    _gestureStartRect = null;
    _gestureStartPointer = null;
    if (_dragTracker.nodeId == widget.node.id) _dragTracker.end();
  }

  // ==================== 菜单 ====================

  Future<void> _openMenu(Offset globalPosition) async {
    final l10n = context.l10n;
    final node = widget.node;
    final documents = ref.read(canvasDocumentControllerProvider.notifier);
    final interaction = ref.read(canvasInteractionProvider.notifier);
    final snapshot = node.params;
    final hasSnapshot = snapshot != null && !snapshot.isEmpty;
    final isTodo = node.kind == CanvasNodeKind.seedTodo;

    await showCanvasMenu(
      context: context,
      position: globalPosition,
      title: canvasNodeTitle(context, node.kind),
      items: [
        if (node.kind == CanvasNodeKind.image)
          ProMenuItem(
            id: 'viewPrompt',
            label: l10n.infinite_canvas_viewPrompt,
            icon: Icons.subject_rounded,
            onTap: () => showCanvasPromptDialog(
              context: context,
              ref: ref,
              node: node,
              absolutePath: widget.absolutePath,
            ),
          ),
        if (hasSnapshot || node.seed != null)
          ProMenuItem(
            id: 'loadParams',
            label: l10n.infinite_canvas_todoLoadParams,
            icon: Icons.input_rounded,
            onTap: () => showCanvasLoadParamsDialog(
              context: context,
              ref: ref,
              node: node,
              absolutePath: widget.absolutePath,
            ),
          ),
        if (isTodo)
          ProMenuItem(
            id: 'toggleTodo',
            label: node.todoDone
                ? l10n.infinite_canvas_todoMarkPending
                : l10n.infinite_canvas_todoMarkDone,
            icon: node.todoDone
                ? Icons.radio_button_unchecked
                : Icons.check_circle_outline,
            onTap: () => documents.setTodoDone(node.id, done: !node.todoDone),
          ),
        if (node.kind == CanvasNodeKind.image ||
            hasSnapshot ||
            node.seed != null ||
            isTodo)
          const ProMenuItem.divider(),
        ProMenuItem(
          id: 'bringToFront',
          label: l10n.infinite_canvas_nodeBringToFront,
          icon: Icons.flip_to_front_outlined,
          onTap: () => documents.bringNodeToFront(node.id),
        ),
        const ProMenuItem.divider(),
        ProMenuItem(
          id: 'remove',
          label: l10n.infinite_canvas_nodeRemove,
          icon: Icons.delete_outline,
          isDanger: true,
          onTap: () async {
            interaction.clearSelection();
            await documents.removeNode(node.id);
          },
        ),
      ],
    );
  }
}
