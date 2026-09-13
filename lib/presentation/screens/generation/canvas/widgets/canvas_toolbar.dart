import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/localization_extension.dart';
import '../../../../../data/models/canvas/canvas_document.dart';
import '../../../../adaptive/interaction_policy.dart';
import '../../../../providers/canvas/canvas_document_controller.dart';
import '../../../../providers/canvas/canvas_interaction_provider.dart';
import '../../../../providers/canvas/canvas_generation_preview.dart';
import '../../../../providers/canvas/canvas_view_controller.dart';
import '../../../../providers/canvas/canvas_visibility_provider.dart';
import '../../../../themes/core/layered_surface_style.dart';
import '../../../../widgets/common/app_toast.dart';
import '../../../../widgets/common/themed_confirm_dialog.dart';
import '../canvas_boards.dart';

/// 画布工具条：缩放、适应内容、新建便签、连线模式、自动加入与退出。
class CanvasToolbar extends ConsumerWidget {
  const CanvasToolbar({super.key, required this.reduceMotion});

  final bool reduceMotion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final controller = ref.watch(canvasViewControllerProvider);
    final linkMode = ref.watch(
      canvasInteractionProvider.select(
        (state) => state.mode == CanvasInteractionMode.link,
      ),
    );
    final autoImport = ref.watch(canvasAutoImportProvider);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Material(
        color: sectionSurfaceColor(theme.colorScheme),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        // 窄屏（手机竖屏 / 分屏）放不下时整条横向滚动，不压缩命中区也不隐藏操作
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _CanvasBoardButton(),
              const _ToolbarDivider(),
              _ToolbarButton(
                icon: Icons.remove_rounded,
                tooltip: context.l10n.infinite_canvas_zoomOut,
                onPressed: () => controller.zoomBy(1 / 1.25),
              ),
              _ZoomLabel(
                scale: controller.scale,
                onPressed: () => controller.resetZoom(animate: !reduceMotion),
              ),
              _ToolbarButton(
                icon: Icons.add_rounded,
                tooltip: context.l10n.infinite_canvas_zoomIn,
                onPressed: () => controller.zoomBy(1.25),
              ),
              const _ToolbarDivider(),
              _ToolbarButton(
                icon: Icons.fit_screen_outlined,
                tooltip: context.l10n.infinite_canvas_fitContent,
                onPressed: () => _fitContent(context, ref),
              ),
              const _ToolbarDivider(),
              _ToolbarButton(
                icon: Icons.sticky_note_2_outlined,
                tooltip: context.l10n.infinite_canvas_newNote,
                onPressed: () => _addNote(ref),
              ),
              _ToolbarButton(
                icon: Icons.polyline_outlined,
                tooltip: linkMode
                    ? context.l10n.infinite_canvas_linkModeHint
                    : context.l10n.infinite_canvas_linkMode,
                selected: linkMode,
                onPressed: () => ref
                    .read(canvasInteractionProvider.notifier)
                    .setMode(
                      linkMode
                          ? CanvasInteractionMode.select
                          : CanvasInteractionMode.link,
                    ),
              ),
              _ToolbarButton(
                icon: Icons.auto_awesome_motion_outlined,
                tooltip:
                    '${context.l10n.infinite_canvas_autoImport}\n'
                    '${context.l10n.infinite_canvas_autoImportHint}',
                selected: autoImport,
                onPressed: () =>
                    ref.read(canvasAutoImportProvider.notifier).toggle(),
              ),
              const _ToolbarDivider(),
              _ToolbarButton(
                icon: Icons.delete_sweep_outlined,
                tooltip: context.l10n.infinite_canvas_clearCanvas,
                onPressed: () => _clearCanvas(context, ref),
              ),
              const _ToolbarDivider(),
              _ToolbarButton(
                icon: Icons.close_fullscreen_rounded,
                tooltip: context.l10n.infinite_canvas_close,
                onPressed: () async {
                  await ref
                      .read(canvasDocumentControllerProvider.notifier)
                      .flush();
                  if (!context.mounted) return;
                  ref.read(infiniteCanvasVisibilityProvider.notifier).close();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _fitContent(BuildContext context, WidgetRef ref) {
    final document = ref.read(canvasDocumentControllerProvider).valueOrNull;
    final controller = ref.read(canvasViewControllerProvider);
    controller.fitToContent([
      ..._nodeRects(document),
      for (final entry in ref.read(canvasGenerationPreviewProvider).entries)
        if (entry.boardId == document?.activeBoardId) entry.rect,
    ], animate: !reduceMotion);
  }

  Future<void> _clearCanvas(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final confirmed = await ThemedConfirmDialog.show(
      context: context,
      title: l10n.infinite_canvas_clearCanvas,
      content: l10n.infinite_canvas_clearCanvasHint,
      type: ThemedConfirmDialogType.warning,
    );
    if (!confirmed || !context.mounted) return;
    ref.read(canvasInteractionProvider.notifier).clearSelection();
    await ref.read(canvasDocumentControllerProvider.notifier).clear();
    if (!context.mounted) return;
    AppToast.success(context, l10n.infinite_canvas_clearCanvasDone);
  }

  Future<void> _addNote(WidgetRef ref) async {
    final documents = ref.read(canvasDocumentControllerProvider.notifier);
    final nodeId = await documents.addNoteNode();
    ref.read(canvasInteractionProvider.notifier).selectNode(nodeId);
  }

  static Iterable<Rect> _nodeRects(CanvasDocument? document) => [
    for (final node in document?.nodes ?? const [])
      Rect.fromLTWH(node.x, node.y, node.width, node.height),
  ];
}

/// 当前画布入口：显示画布名称，点开画布列表（切换/新建/重命名/删除）。
class _CanvasBoardButton extends ConsumerWidget {
  const _CanvasBoardButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final board = ref.watch(
      canvasDocumentControllerProvider.select(
        (value) => value.valueOrNull?.activeBoard,
      ),
    );
    final label = board == null
        ? context.l10n.infinite_canvas_boards
        : canvasBoardLabel(context, board);
    return Tooltip(
      message: context.l10n.infinite_canvas_boards,
      child: TextButton.icon(
        onPressed: () => showCanvasBoardsDialog(context: context, ref: ref),
        icon: const Icon(Icons.dashboard_outlined, size: 16),
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 150),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium,
          ),
        ),
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          foregroundColor: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

class _ZoomLabel extends StatelessWidget {
  const _ZoomLabel({required this.scale, required this.onPressed});

  final double scale;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: context.l10n.infinite_canvas_zoomReset,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          minimumSize: const Size(52, 36),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          foregroundColor: theme.colorScheme.onSurface,
        ),
        child: Text(
          '${(scale * 100).round()}%',
          style: theme.textTheme.labelMedium,
        ),
      ),
    );
  }
}

class _ToolbarDivider extends StatelessWidget {
  const _ToolbarDivider();

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 20,
    child: VerticalDivider(
      width: 9,
      thickness: 1,
      color: Theme.of(context).dividerColor,
    ),
  );
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final extent = context.interactionPolicy.minimumControlExtent;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        constraints: BoxConstraints.tightFor(
          width: extent.clamp(36, 48),
          height: extent.clamp(36, 48),
        ),
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          // 静止时透明，只有激活状态保留底色（DESIGN.md 的按钮层级）
          backgroundColor: selected
              ? scheme.primary.withValues(alpha: 0.16)
              : Colors.transparent,
          foregroundColor: selected ? scheme.primary : scheme.onSurfaceVariant,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}
