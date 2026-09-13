import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../data/models/canvas/canvas_node.dart';
import '../../../../../data/models/canvas/canvas_node_kind.dart';
import '../../../../../data/services/canvas/canvas_repository.dart';
import '../../../../providers/canvas/canvas_document_controller.dart';
import '../../../../providers/canvas/canvas_interaction_provider.dart';
import '../../../../providers/canvas/canvas_repository_provider.dart';
import '../../../../providers/canvas/canvas_generation_preview.dart';
import '../../../../adaptive/interaction_policy.dart';
import '../canvas_node_geometry.dart';
import 'canvas_image_node.dart';
import 'canvas_node_shell.dart';
import 'canvas_note_node.dart';
import 'canvas_seed_todo_node.dart';

/// 画布节点层：按 z 序铺开全部节点。
///
/// 坐标约定（重要）：这一层与它下面每个节点的布局盒都用**屏幕单位**——
/// 位置是 `(节点画布坐标 - 包围盒原点) × scale`，尺寸是 `节点尺寸 × scale`。
/// 缩放只作用在节点内容上（外壳内部再乘一次 scale 还原画布单位）。
///
/// 这样做是必需的：`Positioned` 给子节点的紧约束会被 `Transform` 原样传进
/// 画布空间，把"画布单位的盒子"压成 `包围盒 × scale`；缩放越小盒子越小于
/// 内容，`RenderBox.hitTest` 就会整片跳过节点——表现为缩小后无法拖拽。
/// 逐节点缩放让祖先盒与节点屏幕范围始终一致，命中测试在任何缩放都可到达。
class CanvasNodeLayer extends ConsumerWidget {
  const CanvasNodeLayer({super.key, required this.bounds, required this.scale});

  /// 内容包围盒（画布空间），已含拖动余量
  final Rect bounds;

  final double scale;

  /// 包围盒外扩量：节点拖到内容外时仍要保持可交互
  static const double boundsPadding = 1000;

  /// 由节点集合求内容包围盒；没有节点时返回 null。
  static Rect? resolveBounds(Iterable<CanvasNode> nodes) {
    Rect? union;
    for (final node in nodes) {
      final rect = Rect.fromLTWH(node.x, node.y, node.width, node.height);
      union = union == null ? rect : union.expandToInclude(rect);
    }
    if (union == null) return null;
    return union.inflate(boundsPadding);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final document = ref.watch(
      canvasDocumentControllerProvider.select((value) => value.valueOrNull),
    );
    if (document == null || document.nodes.isEmpty) {
      return const SizedBox.shrink();
    }
    final rootPath = ref.watch(canvasGalleryRootPathProvider).valueOrNull;
    final selectedNodeId = ref.watch(
      canvasInteractionProvider.select((state) => state.selectedNodeId),
    );
    final linkSourceNodeId = ref.watch(
      canvasInteractionProvider.select((state) => state.linkSourceNodeId),
    );

    final tracker = ref.watch(canvasDragTrackerProvider);
    final touch = context.interactionPolicy.touchAvailable;
    final children = <Widget>[];
    for (final node in document.nodesByZOrder) {
      final isImage = node.kind == CanvasNodeKind.image;
      final absolutePath = isImage
          ? _resolvePath(rootPath, node.imageRelativePath)
          : null;
      children.add(
        ListenableBuilder(
          key: ValueKey('layout-${node.id}'),
          listenable: tracker,
          builder: (context, _) {
            final rect = tracker.rectFor(
              node.id,
              Rect.fromLTWH(node.x, node.y, node.width, node.height),
            );
            final handles = CanvasNodeHandleLayout(
              rect.size * scale,
              touch: touch,
            );
            final inset = handles.inset;
            return Positioned(
              left: (rect.left - bounds.left) * scale - inset,
              top: (rect.top - bounds.top) * scale - inset,
              width: rect.width * scale + inset * 2,
              height: rect.height * scale + inset * 2,
              child: CanvasNodeShell(
                key: ValueKey(node.id),
                node: node,
                scale: scale,
                absolutePath: absolutePath,
                selected: selectedNodeId == node.id,
                linkSourceActive: linkSourceNodeId == node.id,
                resizable: true,
                aspectLocked: isImage,
                animateEntrance:
                    ref.read(canvasGenerationPreviewProvider).entry(node.id) ==
                    null,
                previewSize: rect.size,
                handleLayout: handles,
                onDoubleTap: _doubleTapAction(context, ref, node),
                contentBuilder: (context, hovered) => _buildContent(
                  context,
                  ref,
                  node,
                  hovered,
                  selectedNodeId == node.id,
                  absolutePath,
                ),
              ),
            );
          },
        ),
      );
    }

    return SizedBox.fromSize(
      size: Size(bounds.width * scale, bounds.height * scale),
      child: Stack(clipBehavior: Clip.none, children: children),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    CanvasNode node,
    bool hovered,
    bool selected,
    String? absolutePath,
  ) {
    switch (node.kind) {
      case CanvasNodeKind.image:
        final previews = ref.read(canvasGenerationPreviewProvider);
        return CanvasImageNode(
          node: node,
          absolutePath: absolutePath,
          hovered: hovered,
          selected: selected,
          onAspectResolved: (aspect) => _applyDetectedAspect(ref, node, aspect),
          onImageReady: () => previews.remove(node.id),
        );
      case CanvasNodeKind.seedTodo:
        return CanvasSeedTodoNode(
          node: node,
          hovered: hovered,
          selected: selected,
        );
      case CanvasNodeKind.note:
        return CanvasNoteNode(node: node);
    }
  }

  /// 便签双击进入编辑（图片与待办没有双击行为）
  static VoidCallback? _doubleTapAction(
    BuildContext context,
    WidgetRef ref,
    CanvasNode node,
  ) {
    if (node.kind != CanvasNodeKind.note) return null;
    return () => showCanvasNoteEditor(context: context, ref: ref, node: node);
  }

  /// 解码得到真实宽高比后把节点盒贴合到图片比例。
  ///
  /// 创建时若缺少可靠的尺寸信息（宽高为 0 的失败快照、非 NovelAI 图片），
  /// 节点会先按兜底比例落位，这里再纠正一次，避免画布上长期留着被拉伸的图。
  void _applyDetectedAspect(WidgetRef ref, CanvasNode node, double aspect) {
    if (!aspect.isFinite || aspect <= 0) return;
    final height = (node.width / aspect)
        .clamp(CanvasNode.minNodeHeight, CanvasNode.maxNodeHeight)
        .toDouble();
    ref
        .read(canvasDocumentControllerProvider.notifier)
        .resizeNode(node.id, width: node.width, height: height);
  }

  static String? _resolvePath(String? rootPath, String? relativePath) {
    if (rootPath == null || rootPath.isEmpty) return null;
    if (relativePath == null || relativePath.isEmpty) return null;
    if (!CanvasRepository.isValidReference(relativePath)) return null;
    return CanvasRepository.resolveAbsolutePath(rootPath, relativePath);
  }
}
