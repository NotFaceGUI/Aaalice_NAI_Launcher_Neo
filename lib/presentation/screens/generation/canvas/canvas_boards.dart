import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/canvas/canvas_board.dart';
import '../../../adaptive/adaptive_presenter.dart';
import '../../../adaptive/content_sized_adaptive_form.dart';
import '../../../providers/canvas/canvas_document_controller.dart';

/// 画布名称；未命名时按当前语言兜底显示，避免历史数据出现空标题。
String canvasBoardLabel(BuildContext context, CanvasBoard board) =>
    board.name.trim().isEmpty
    ? context.l10n.infinite_canvas_boardUntitled
    : board.name;

/// 新建画布的默认名称：按现有数量顺序编号。
String defaultCanvasBoardName(BuildContext context, int existingCount) =>
    '${context.l10n.infinite_canvas_boardNamePrefix} ${existingCount + 1}';

/// 画布管理弹窗：切换、新建、重命名、删除。
///
/// 桌面与触屏共用同一个自适应表单（列表 + 每行操作），不另做鼠标专属菜单，
/// 保证两端能力一致。
Future<void> showCanvasBoardsDialog({
  required BuildContext context,
  required WidgetRef ref,
}) {
  return AdaptivePresenter.showForm<void>(
    context: context,
    title: context.l10n.infinite_canvas_boards,
    builder: (formContext, scrollController) =>
        _CanvasBoardsContent(scrollController: scrollController),
  );
}

class _CanvasBoardsContent extends ConsumerWidget {
  const _CanvasBoardsContent({required this.scrollController});

  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final document = ref.watch(canvasDocumentControllerProvider).valueOrNull;
    final boards = document?.boards ?? const <CanvasBoard>[];
    final activeId = document?.activeBoardId;
    final controller = ref.read(canvasDocumentControllerProvider.notifier);

    return ContentSizedAdaptiveForm(
      scrollController: scrollController,
      content: [
        for (final board in boards)
          ListTile(
            leading: Icon(
              board.id == activeId
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: board.id == activeId
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            title: Text(
              canvasBoardLabel(context, board),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              l10n.infinite_canvas_boardNodeCount(board.nodes.length),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip: l10n.infinite_canvas_boardRename,
                  onPressed: () => _renameBoard(context, ref, board),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  tooltip: l10n.infinite_canvas_boardDelete,
                  // 至少保留一块画布，最后一块不可删
                  onPressed: boards.length <= 1
                      ? null
                      : () => _deleteBoard(context, ref, board),
                ),
              ],
            ),
            onTap: () {
              controller.selectBoard(board.id);
              Navigator.of(context).pop();
            },
          ),
      ],
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(
          children: [
            FilledButton.tonalIcon(
              onPressed: () => _createBoard(context, ref, boards.length),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(l10n.infinite_canvas_boardNew),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.common_close),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createBoard(
    BuildContext context,
    WidgetRef ref,
    int existingCount,
  ) async {
    final name = await _promptBoardName(
      context: context,
      title: context.l10n.infinite_canvas_boardNew,
      initialValue: defaultCanvasBoardName(context, existingCount),
    );
    if (name == null) return;
    await ref.read(canvasDocumentControllerProvider.notifier).createBoard(name);
  }

  Future<void> _renameBoard(
    BuildContext context,
    WidgetRef ref,
    CanvasBoard board,
  ) async {
    final name = await _promptBoardName(
      context: context,
      title: context.l10n.infinite_canvas_boardRename,
      initialValue: canvasBoardLabel(context, board),
    );
    if (name == null) return;
    await ref
        .read(canvasDocumentControllerProvider.notifier)
        .renameBoard(board.id, name);
  }

  Future<void> _deleteBoard(
    BuildContext context,
    WidgetRef ref,
    CanvasBoard board,
  ) async {
    final l10n = context.l10n;
    final confirmed = await AdaptivePresenter.showForm<bool>(
      context: context,
      title: l10n.infinite_canvas_boardDelete,
      builder: (formContext, scrollController) => ContentSizedAdaptiveForm(
        scrollController: scrollController,
        content: [Text(l10n.infinite_canvas_boardDeleteHint)],
        footer: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(formContext).pop(false),
                child: Text(l10n.common_cancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(formContext).colorScheme.error,
                  foregroundColor: Theme.of(formContext).colorScheme.onError,
                ),
                onPressed: () => Navigator.of(formContext).pop(true),
                child: Text(l10n.common_delete),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(canvasDocumentControllerProvider.notifier)
        .deleteBoard(board.id);
  }

  Future<String?> _promptBoardName({
    required BuildContext context,
    required String title,
    required String initialValue,
  }) async {
    final controller = TextEditingController(text: initialValue);
    final result = await AdaptivePresenter.showForm<String>(
      context: context,
      title: title,
      builder: (formContext, scrollController) => ContentSizedAdaptiveForm(
        scrollController: scrollController,
        content: [
          TextField(
            controller: controller,
            autofocus: true,
            maxLength: 60,
            decoration: InputDecoration(
              hintText: formContext.l10n.infinite_canvas_boardNamePrefix,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (value) => Navigator.of(formContext).pop(value),
          ),
        ],
        footer: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(formContext).pop(),
                child: Text(formContext.l10n.common_cancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => Navigator.of(formContext).pop(controller.text),
                child: Text(formContext.l10n.common_confirm),
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();
    final trimmed = result?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}
