import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/canvas/canvas_document.dart';
import '../../../../data/models/canvas/canvas_edge.dart';
import '../../../../data/models/canvas/canvas_node.dart';
import '../../../providers/canvas/canvas_document_controller.dart';
import '../../../providers/canvas/canvas_generation_bridge.dart';
import '../../../providers/canvas/canvas_generation_preview.dart';
import '../../../providers/canvas/canvas_interaction_provider.dart';
import '../../../providers/canvas/canvas_view_controller.dart';
import 'canvas_edge_math.dart';
import 'widgets/canvas_edge_layer.dart';
import 'widgets/canvas_generation_preview_layer.dart';
import 'widgets/canvas_grid_painter.dart';
import 'widgets/canvas_node_layer.dart';
import 'widgets/canvas_toolbar.dart';

/// 无限画布视图。
///
/// 手势分工：视口用原始指针事件实现平移/缩放（不参与手势竞技场），节点与
/// 连接手柄在自身上报"这个指针归我"（见 [CanvasPointerRegistry]），因此从
/// 节点上开始的拖动永远不会带动画布。指针在命中路径上由内向外派发，节点
/// 通常先于视口收到按下事件；移动时再次核对归属，避免双重处理。
class InfiniteCanvasView extends ConsumerStatefulWidget {
  const InfiniteCanvasView({super.key});

  @override
  ConsumerState<InfiniteCanvasView> createState() => _InfiniteCanvasViewState();
}

class _InfiniteCanvasViewState extends ConsumerState<InfiniteCanvasView>
    with TickerProviderStateMixin {
  static const double _edgeTapTolerance = 10;

  late final CanvasViewController _viewport;
  late final AnimationController _edgeReveal;

  final Map<int, Offset> _activePointers = <int, Offset>{};
  double? _pinchLastDistance;
  Offset? _pinchLastFocal;
  bool _pointerMoved = false;
  Offset? _pressPosition;
  int? _pressPointer;

  final Set<String> _knownEdgeIds = <String>{};
  bool _edgesSeeded = false;
  String? _revealEdgeId;

  Size? _reportedViewportSize;
  bool _didInitialFit = false;

  /// 上一次渲染的画布 id；用于在切换画布时重置选中与视口
  String? _lastBoardId;

  /// 拖动中的节点位移；连线层靠它实时跟随
  CanvasDragTracker get _dragTracker => ref.read(canvasDragTrackerProvider);

  @override
  void initState() {
    super.initState();
    // 视口控制器活在 provider 里，这里只借用生命周期的 vsync
    _viewport = ref.read(canvasViewControllerProvider);
    _viewport.attachTicker(this);
    _edgeReveal = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
  }

  @override
  void dispose() {
    _viewport.detachTicker();
    _edgeReveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    // 画布打开时才开始把新生成的结果送到画布上
    ref.watch(canvasGenerationBridgeProvider);

    final documentAsync = ref.watch(canvasDocumentControllerProvider);
    final document = documentAsync.valueOrNull;
    final interaction = ref.watch(canvasInteractionProvider);
    _syncEdgeReveal(document);
    _syncBoardSwitch(document);

    if (documentAsync.isLoading && document == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final contentBounds = CanvasNodeLayer.resolveBounds(
      document?.nodes ?? const <CanvasNode>[],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        _reportViewportSize(
          Size(constraints.maxWidth, constraints.maxHeight),
          document,
        );
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _handlePointerDown,
          onPointerMove: _handlePointerMove,
          onPointerUp: _handlePointerUp,
          onPointerCancel: _handlePointerCancel,
          onPointerSignal: _handlePointerSignal,
          child: MouseRegion(
            cursor: SystemMouseCursors.basic,
            child: Stack(
              children: [
                // 画布内容一律裁在中央工作区内，绝不画到参数栏/历史面板上面；
                // 网格、连线与节点共用这一层裁剪
                Positioned.fill(
                  child: ClipRect(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ListenableBuilder(
                            listenable: _viewport,
                            builder: (context, _) => CustomPaint(
                              painter: CanvasGridPainter(
                                offsetX: _viewport.offsetX,
                                offsetY: _viewport.offsetY,
                                scale: _viewport.scale,
                                dotColor: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.16),
                              ),
                              size: Size.infinite,
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: ListenableBuilder(
                            listenable: Listenable.merge([
                              _viewport,
                              _edgeReveal,
                              // 节点拖动时连线要实时跟随
                              _dragTracker,
                            ]),
                            builder: (context, _) => CanvasEdgeLayer(
                              edges: _edgeGeometries(document, interaction),
                              offsetX: _viewport.offsetX,
                              offsetY: _viewport.offsetY,
                              scale: _viewport.scale,
                              lineColor: theme.colorScheme.onSurfaceVariant,
                              selectedColor: theme.colorScheme.primary,
                              labelSurfaceColor:
                                  theme.colorScheme.surfaceContainerHigh,
                              labelTextColor: theme.colorScheme.onSurface,
                              draft: _draftGeometry(document, interaction),
                              revealEdgeId: _revealEdgeId,
                              revealProgress: _edgeReveal.value,
                            ),
                          ),
                        ),
                        // 节点层：整层的定位盒与节点都用屏幕单位，缩放作用在
                        // 节点内容上（见 CanvasNodeLayer 的坐标约定）。
                        //
                        // 这里刻意不放层级的 Transform：紧约束会被它原样传进
                        // 画布空间，把画布单位的盒子压成 `包围盒 × scale`，
                        // 缩小后祖先盒就会小于节点范围，命中测试整片跳过节点
                        // （表现为缩小到 50% 就拖不动）。盒子尺寸与约束一致后，
                        // 任意缩放级别都能命中。
                        if (contentBounds != null)
                          ListenableBuilder(
                            listenable: _viewport,
                            builder: (context, _) => Positioned(
                              left:
                                  _viewport.offsetX +
                                  contentBounds.left * _viewport.scale,
                              top:
                                  _viewport.offsetY +
                                  contentBounds.top * _viewport.scale,
                              width: contentBounds.width * _viewport.scale,
                              height: contentBounds.height * _viewport.scale,
                              // 必须在这里构建：ListenableBuilder 的 child 参数
                              // 在视图构建时就固定了，而缩放会在其后改变（自动
                              // 定位、滚轮缩放），拿旧 scale 布局会让节点与连线
                              // 相对定位盒整体错位。
                              child: CanvasNodeLayer(
                                key: ValueKey(document?.activeBoardId),
                                bounds: contentBounds,
                                scale: _viewport.scale,
                              ),
                            ),
                          ),
                        const Positioned.fill(
                          child: CanvasGenerationPreviewLayer(),
                        ),
                      ],
                    ),
                  ),
                ),
                if (document != null &&
                    document.isEmpty &&
                    !documentAsync.isLoading)
                  Positioned.fill(
                    child: _CanvasEmptyState(onAddNote: _addNote),
                  ),
                Positioned(
                  top: 8,
                  left: 8,
                  right: 8,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Listener(
                      onPointerDown: (event) => ref
                          .read(canvasPointerRegistryProvider)
                          .claim(event.pointer),
                      onPointerUp: (event) => ref
                          .read(canvasPointerRegistryProvider)
                          .release(event.pointer),
                      onPointerCancel: (event) => ref
                          .read(canvasPointerRegistryProvider)
                          .release(event.pointer),
                      onPointerSignal: (event) {
                        GestureBinding.instance.pointerSignalResolver.register(
                          event,
                          (_) {},
                        );
                      },
                      child: CanvasToolbar(reduceMotion: reduceMotion),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==================== 视口尺寸与初次定位 ====================

  void _reportViewportSize(Size size, CanvasDocument? document) {
    if (_reportedViewportSize == size) return;
    _reportedViewportSize = size;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _viewport.setViewportSize(size);
      if (_didInitialFit) return;
      _didInitialFit = true;
      // 首次进入且没有上次视口时，自动把已有内容放进视野
      if (!_viewport.restoredFromStorage) {
        _viewport.fitToContent(_nodeRects(document), animate: false);
      }
    });
  }

  // ==================== 平移与缩放 ====================

  void _handlePointerDown(PointerDownEvent event) {
    if (ref.read(canvasPointerRegistryProvider).isOwned(event.pointer)) return;
    _activePointers[event.pointer] = event.position;
    if (_activePointers.length == 1) {
      _pressPointer = event.pointer;
      _pressPosition = event.position;
      _pointerMoved = false;
    } else {
      _pressPointer = null;
      _pressPosition = null;
      _beginPinch();
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    // Ownership may change as an interaction is claimed after pointer down.
    if (ref.read(canvasPointerRegistryProvider).isOwned(event.pointer)) {
      _activePointers.remove(event.pointer);
      return;
    }
    final previous = _activePointers[event.pointer];
    if (previous == null) return;
    _activePointers[event.pointer] = event.position;

    final pressPosition = _pressPosition;
    if (!_pointerMoved &&
        pressPosition != null &&
        (event.position - pressPosition).distance > kTouchSlop) {
      _pointerMoved = true;
    }

    if (_activePointers.length >= 2) {
      _updatePinch();
      return;
    }
    _viewport.panBy(event.position - previous);
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (!_activePointers.containsKey(event.pointer)) return;
    _activePointers.remove(event.pointer);
    if (_activePointers.isEmpty) {
      _endGesture(event.position);
      return;
    }
    if (_activePointers.length == 1) {
      _pinchLastDistance = null;
      _pinchLastFocal = null;
      _pointerMoved = true;
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _activePointers.remove(event.pointer);
    if (_activePointers.isEmpty) _endGesture(null);
  }

  void _endGesture(Offset? position) {
    final wasTap = !_pointerMoved && _pressPointer != null;
    _pressPointer = null;
    _pressPosition = null;
    _pinchLastDistance = null;
    _pinchLastFocal = null;

    if (wasTap && position != null) _handleCanvasTap(position);
    _viewport.commitViewport();
  }

  /// 空白处点击：命中连线则选中连线，否则清空选择。
  void _handleCanvasTap(Offset screenPosition) {
    final interaction = ref.read(canvasInteractionProvider.notifier);
    final box = context.findRenderObject()! as RenderBox;
    final canvasPoint = _viewport.screenToCanvas(
      box.globalToLocal(screenPosition),
    );
    final edgeId = _edgeAt(canvasPoint);
    if (edgeId != null) {
      interaction.selectEdge(edgeId);
      return;
    }
    interaction.clearSelection();
  }

  String? _edgeAt(Offset canvasPoint) {
    final document = ref.read(canvasDocumentControllerProvider).valueOrNull;
    if (document == null) return null;
    final rects = {for (final node in document.nodes) node.id: _rectOf(node)};
    final tolerance = _edgeTapTolerance / math.max(_viewport.scale, 0.01);
    for (final edge in document.edges.reversed) {
      final from = rects[edge.fromNodeId];
      final to = rects[edge.toNodeId];
      if (from == null || to == null) continue;
      final route = CanvasEdgeMath.route(from, to);
      if (CanvasEdgeMath.distanceTo(
            canvasPoint,
            route.start,
            route.end,
            horizontal: route.horizontal,
          ) <=
          tolerance) {
        return edge.id;
      }
    }
    return null;
  }

  void _beginPinch() {
    final points = _activePointers.values.toList();
    if (points.length < 2) return;
    _pinchLastDistance = (points[0] - points[1]).distance;
    _pinchLastFocal = (points[0] + points[1]) / 2;
  }

  void _updatePinch() {
    final points = _activePointers.values.toList();
    if (points.length < 2) return;
    final distance = (points[0] - points[1]).distance;
    final focal = (points[0] + points[1]) / 2;
    final lastDistance = _pinchLastDistance;
    final lastFocal = _pinchLastFocal;

    if (lastDistance != null && lastDistance > 0 && distance > 0) {
      final box = context.findRenderObject()! as RenderBox;
      _viewport.zoomBy(
        distance / lastDistance,
        focalScreen: box.globalToLocal(lastFocal ?? focal),
      );
    }
    if (lastFocal != null) _viewport.panBy(focal - lastFocal);

    _pinchLastDistance = distance;
    _pinchLastFocal = focal;
  }

  /// 滚轮直接缩放（不要求修饰键），Shift + 滚轮横向平移。
  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (_dragTracker.isDragging ||
        ref.read(canvasInteractionProvider).linkDraft != null) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(
      event,
      (_) => _applyScroll(event),
    );
  }

  void _applyScroll(PointerScrollEvent event) {
    final shiftPressed = HardwareKeyboard.instance.isShiftPressed;
    if (shiftPressed && !HardwareKeyboard.instance.isControlPressed) {
      _viewport.panBy(Offset(-event.scrollDelta.dy, 0));
    } else {
      // 以指针为焦点连续缩放；向前滚动为放大
      _viewport.zoomBy(
        math.exp(-event.scrollDelta.dy / 400),
        focalScreen: event.localPosition,
      );
    }
    _viewport.commitViewport();
  }

  // ==================== 几何与动画 ====================

  List<Rect> _nodeRects(CanvasDocument? document) => [
    for (final node in document?.nodes ?? const <CanvasNode>[]) _rectOf(node),
    for (final entry in ref.read(canvasGenerationPreviewProvider).entries)
      if (entry.boardId == document?.activeBoardId) entry.rect,
  ];

  /// 节点当前的画布矩形；拖动中的节点带上未提交的位移，
  /// 这样连线与"适应内容"都跟着指针实时更新。
  Rect _rectOf(CanvasNode node) {
    return _dragTracker.rectFor(
      node.id,
      Rect.fromLTWH(node.x, node.y, node.width, node.height),
    );
  }

  List<CanvasEdgeGeometry> _edgeGeometries(
    CanvasDocument? document,
    CanvasInteractionState interaction,
  ) {
    if (document == null || document.edges.isEmpty) return const [];
    final rects = {for (final node in document.nodes) node.id: _rectOf(node)};
    final selectedEdgeId = interaction.selectedEdgeId;
    final result = <CanvasEdgeGeometry>[];
    for (final CanvasEdge edge in document.edges) {
      final from = rects[edge.fromNodeId];
      final to = rects[edge.toNodeId];
      if (from == null || to == null) continue;
      result.add(
        CanvasEdgeGeometry(
          edge: edge,
          route: CanvasEdgeMath.route(from, to),
          selected: edge.id == selectedEdgeId,
        ),
      );
    }
    return result;
  }

  CanvasLinkDraftGeometry? _draftGeometry(
    CanvasDocument? document,
    CanvasInteractionState interaction,
  ) {
    final draft = interaction.linkDraft;
    if (draft == null || document == null) return null;
    final fromNode = document.nodeById(draft.fromNodeId);
    if (fromNode == null) return null;
    final targetId = draft.targetNodeId;
    final targetNode = targetId == null ? null : document.nodeById(targetId);
    return CanvasLinkDraftGeometry(
      fromRect: _rectOf(fromNode),
      currentPoint: draft.currentCanvasPoint,
      targetRect: targetNode == null ? null : _rectOf(targetNode),
    );
  }

  /// 新出现的连线播放一次生长动画；首次加载的连线不播放。
  void _syncEdgeReveal(CanvasDocument? document) {
    if (document == null) return;
    final ids = {for (final edge in document.edges) edge.id};
    if (!_edgesSeeded) {
      _edgesSeeded = true;
      _knownEdgeIds
        ..clear()
        ..addAll(ids);
      return;
    }
    final added = ids.difference(_knownEdgeIds);
    _knownEdgeIds
      ..clear()
      ..addAll(ids);
    if (added.isEmpty) return;
    final revealId = added.last;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _revealEdgeId = revealId);
      _edgeReveal.forward(from: 0);
    });
  }

  /// 切换画布后清掉上一块画布的选中，并把新画布的内容放进视野。
  ///
  /// 选中 id 只在本画布内有意义；视口不跟随就会停在旧坐标，看起来像画布空了。
  void _syncBoardSwitch(CanvasDocument? document) {
    final boardId = document?.activeBoardId;
    if (boardId == null || boardId == _lastBoardId) return;
    final isFirst = _lastBoardId == null;
    _lastBoardId = boardId;
    if (isFirst) return;

    _edgesSeeded = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(canvasInteractionProvider.notifier).clearSelection();
      _dragTracker.end();
      _activePointers.clear();
      _viewport.fitToContent(_nodeRects(document), animate: true);
    });
  }

  Future<void> _addNote() async {
    final documents = ref.read(canvasDocumentControllerProvider.notifier);
    final nodeId = await documents.addNoteNode();
    ref.read(canvasInteractionProvider.notifier).selectNode(nodeId);
  }
}

class _CanvasEmptyState extends ConsumerWidget {
  const _CanvasEmptyState({required this.onAddNote});

  final VoidCallback onAddNote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final previews = ref.watch(canvasGenerationPreviewProvider);
    final boardId = ref
        .watch(canvasDocumentControllerProvider)
        .valueOrNull
        ?.activeBoardId;
    return ListenableBuilder(
      listenable: previews,
      builder: (context, child) =>
          previews.entries.any((entry) => entry.boardId == boardId)
          ? const SizedBox.shrink()
          : child!,
      child: IgnorePointer(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_awesome_motion_outlined,
                  size: 40,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.infinite_canvas_emptyTitle,
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.infinite_canvas_emptyHint,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
