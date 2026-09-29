import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../core/utils/storyboard/storyboard_geometry.dart';
import '../../../../data/models/storyboard/storyboard_page.dart';
import '../../../adaptive/adaptive_presenter.dart';
import '../../../adaptive/content_sized_adaptive_form.dart';
import '../../../providers/storyboard/storyboard_document_controller.dart';

/// 打开网格生成分镜的弹窗。
///
/// 走项目统一的 [AdaptivePresenter.showForm]：桌面居中弹窗、窄屏全屏，
/// 头部、关闭与响应式呈现都由共用壳层负责，这里只提供内容与底部操作。
///
/// 网格是布局生成器而不是常驻参考线：排完就结束，之后每个分镜各自编辑。
Future<void> showStoryboardGridDialog(
  BuildContext context,
  WidgetRef ref,
  StoryboardPage page,
) {
  return AdaptivePresenter.showForm<void>(
    context: context,
    title: context.l10n.storyboard_gridTitle,
    builder: (formContext, scrollController) =>
        _StoryboardGridContent(page: page, scrollController: scrollController),
  );
}

class _StoryboardGridContent extends ConsumerStatefulWidget {
  const _StoryboardGridContent({
    required this.page,
    required this.scrollController,
  });

  final StoryboardPage page;
  final ScrollController? scrollController;

  @override
  ConsumerState<_StoryboardGridContent> createState() =>
      _StoryboardGridContentState();
}

class _StoryboardGridContentState
    extends ConsumerState<_StoryboardGridContent> {
  late int _rows;
  late int _columns;
  late final TextEditingController _margin;
  late final TextEditingController _gutter;
  bool _replace = false;

  @override
  void initState() {
    super.initState();
    _rows = 2;
    _columns = 3;
    // 间距取自页面本身：换一次网格不必重新输一遍。
    _margin = TextEditingController(
      text: widget.page.margin.round().toString(),
    );
    _gutter = TextEditingController(
      text: widget.page.gutter.round().toString(),
    );
  }

  @override
  void dispose() {
    _margin.dispose();
    _gutter.dispose();
    super.dispose();
  }

  double get _marginValue => double.tryParse(_margin.text) ?? 0;

  double get _gutterValue => double.tryParse(_gutter.text) ?? 0;

  /// 预览实际会生成多少个分镜：页面容不下时提前变成空，用户不必先点一次才知道。
  List<Rect> get _preview => StoryboardGeometry.buildGridRects(
    pageSize: Size(
      widget.page.width.toDouble(),
      widget.page.height.toDouble(),
    ),
    rows: _rows,
    columns: _columns,
    margin: _marginValue,
    gutter: _gutterValue,
  );

  Future<void> _apply() async {
    final count = await ref
        .read(storyboardDocumentControllerProvider.notifier)
        .applyGrid(
          rows: _rows,
          columns: _columns,
          margin: _marginValue,
          gutter: _gutterValue,
          replace: _replace,
        );
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.of(context).pop();
    messenger?.showSnackBar(
      SnackBar(content: Text(context.l10n.storyboard_gridCreated(count))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final preview = _preview;
    final remaining = StoryboardPage.maxPanels - widget.page.panels.length;
    final capacity = _replace ? StoryboardPage.maxPanels : remaining;
    final fits = preview.isNotEmpty && preview.length <= capacity;

    return ContentSizedAdaptiveForm(
      scrollController: widget.scrollController,
      content: [
        _Stepper(
          label: l10n.storyboard_gridRows,
          value: _rows,
          onChanged: (value) => setState(() => _rows = value),
        ),
        _Stepper(
          label: l10n.storyboard_gridColumns,
          value: _columns,
          onChanged: (value) => setState(() => _columns = value),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _NumberField(
                controller: _margin,
                label: l10n.storyboard_gridMargin,
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _NumberField(
                controller: _gutter,
                label: l10n.storyboard_gridGutter,
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          value: _replace,
          onChanged: widget.page.panels.isEmpty
              ? null
              : (value) => setState(() => _replace = value),
          title: Text(l10n.storyboard_gridReplace),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        const SizedBox(height: 4),
        Text(
          fits
              ? l10n.storyboard_panelsLabel(preview.length)
              : l10n.storyboard_gridTooSmall,
          style: theme.textTheme.bodySmall?.copyWith(
            color: fits
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.error,
          ),
        ),
      ],
      footer: StoryboardDialogActions(
        onCancel: () => Navigator.of(context).pop(),
        onConfirm: fits ? _apply : null,
        confirmLabel: l10n.storyboard_gridApply,
      ),
    );
  }
}

/// 底部操作行；与项目其它表单弹窗一致：取消在左、主操作在右。
class StoryboardDialogActions extends StatelessWidget {
  const StoryboardDialogActions({
    super.key,
    required this.onCancel,
    required this.onConfirm,
    required this.confirmLabel,
  });

  final VoidCallback onCancel;
  final VoidCallback? onConfirm;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: onCancel,
            child: Text(context.l10n.common_cancel),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: onConfirm, child: Text(confirmLabel)),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        IconButton(
          icon: const Icon(Icons.remove_rounded),
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: 32,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_rounded),
          onPressed: value < StoryboardGeometry.maxGridDivisions
              ? () => onChanged(value + 1)
              : null,
        ),
      ],
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (value) => onChanged(int.tryParse(value) ?? 0),
      decoration: InputDecoration(labelText: label, isDense: true),
    );
  }
}
