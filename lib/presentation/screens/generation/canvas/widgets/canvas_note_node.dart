import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart' as md;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/localization_extension.dart';
import '../../../../../data/models/canvas/canvas_node.dart';
import '../../../../adaptive/adaptive_presenter.dart';
import '../../../../adaptive/content_sized_adaptive_form.dart';
import '../../../../providers/canvas/canvas_document_controller.dart';

/// 文本标注便签内容，支持 Markdown。
///
/// 便签本体不承载可编辑控件：画布上单击用于选择、拖动与连线，双击节点进入
/// 编辑（由外壳的 `onDoubleTap` 触发），所以不需要额外的编辑图标。
class CanvasNoteNode extends StatelessWidget {
  const CanvasNoteNode({super.key, required this.node});

  final CanvasNode node;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = node.noteText ?? '';

    if (text.trim().isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Align(
          alignment: Alignment.topLeft,
          child: Text(
            context.l10n.infinite_canvas_notePlaceholder,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    // 便签尺寸由用户控制，内容超出时在节点内滚动而不是撑破节点
    return Padding(
      padding: const EdgeInsets.all(10),
      child: SingleChildScrollView(
        primary: false,
        child: md.MarkdownBody(
          data: text,
          // 不可选中：可选择文本会抢走单击与拖动，而画布上节点正文要用来
          // 选择/移动/拉线；需要选中复制时在编辑弹窗里操作
          selectable: false,
          shrinkWrap: true,
          styleSheet: _styleSheet(theme),
        ),
      ),
    );
  }

  static md.MarkdownStyleSheet _styleSheet(ThemeData theme) {
    final base = theme.textTheme.bodySmall ?? const TextStyle();
    final heading = theme.textTheme.titleSmall ?? const TextStyle();
    return md.MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: base.copyWith(height: 1.35),
      pPadding: const EdgeInsets.only(bottom: 4),
      h1: heading,
      h1Padding: const EdgeInsets.only(bottom: 4),
      h2: heading,
      h2Padding: const EdgeInsets.only(bottom: 4),
      h3: heading,
      h3Padding: const EdgeInsets.only(bottom: 4),
      listBullet: base,
      listBulletPadding: const EdgeInsets.only(right: 4),
      code: base.copyWith(
        fontFamily: 'monospace',
        backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.6,
        ),
      ),
      codeblockDecoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      blockquoteDecoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}

/// 打开便签编辑表单；确认后写回画布文档。
Future<void> showCanvasNoteEditor({
  required BuildContext context,
  required WidgetRef ref,
  required CanvasNode node,
}) async {
  final controller = TextEditingController(text: node.noteText ?? '');
  final result = await AdaptivePresenter.showForm<String>(
    context: context,
    title: context.l10n.infinite_canvas_noteEdit,
    builder: (formContext, scrollController) => ContentSizedAdaptiveForm(
      scrollController: scrollController,
      content: [
        TextField(
          controller: controller,
          autofocus: true,
          minLines: 6,
          maxLines: 14,
          maxLength: 2000,
          style: const TextStyle(fontFamily: 'monospace'),
          decoration: InputDecoration(
            hintText: formContext.l10n.infinite_canvas_notePlaceholder,
            helperText: formContext.l10n.infinite_canvas_noteMarkdownHint,
            border: const OutlineInputBorder(),
          ),
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
  if (result == null) return;
  await ref
      .read(canvasDocumentControllerProvider.notifier)
      .setNoteText(node.id, result);
}
