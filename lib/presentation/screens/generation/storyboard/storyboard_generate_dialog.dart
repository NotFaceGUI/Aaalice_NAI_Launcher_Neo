import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/storyboard/storyboard_page.dart';
import '../../../../data/services/storyboard/storyboard_generation_planner.dart';
import '../../../providers/generation/generation_anlas_estimator_provider.dart';
import '../../../providers/generation/generation_params_notifier.dart';
import '../../../providers/storyboard/storyboard_generation_runner.dart';

/// 生成范围。
enum StoryboardGenerateScope { all, ungenerated, selected, background }

/// 打开分镜批量生成的确认对话框。
///
/// 批量生成是付费操作，产品要求成本在执行前可见并取得确认，因此这里先算清
/// "几次请求、多少 Anlas"再让用户决定。
Future<void> showStoryboardGenerateDialog(
  BuildContext context,
  WidgetRef ref,
  StoryboardPage page, {
  String? selectedPanelId,
  bool backgroundSelected = false,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _StoryboardGenerateDialog(
      page: page,
      selectedPanelId: selectedPanelId,
      backgroundSelected: backgroundSelected,
    ),
  );
}

class _StoryboardGenerateDialog extends ConsumerStatefulWidget {
  const _StoryboardGenerateDialog({
    required this.page,
    required this.selectedPanelId,
    required this.backgroundSelected,
  });

  final StoryboardPage page;
  final String? selectedPanelId;
  final bool backgroundSelected;

  @override
  ConsumerState<_StoryboardGenerateDialog> createState() =>
      _StoryboardGenerateDialogState();
}

class _StoryboardGenerateDialogState
    extends ConsumerState<_StoryboardGenerateDialog> {
  late StoryboardGenerateScope _scope;

  @override
  void initState() {
    super.initState();
    // 默认跟随当前选中：选中背景就生成背景，选中分镜就只画它，
    // 什么都没选时补齐还没出图的分镜——三种都是最常见的意图。
    if (widget.backgroundSelected) {
      _scope = StoryboardGenerateScope.background;
    } else if (widget.selectedPanelId != null) {
      _scope = StoryboardGenerateScope.selected;
    } else {
      _scope = StoryboardGenerateScope.ungenerated;
    }
  }

  bool get _isBackground => _scope == StoryboardGenerateScope.background;

  List<StoryboardPanelRequest> get _requests {
    final base = ref.read(generationParamsNotifierProvider);
    if (_isBackground) {
      return StoryboardGenerationPlanner.planBackground(
        page: widget.page,
        base: base,
      );
    }
    return StoryboardGenerationPlanner.planPage(
      page: widget.page,
      base: base,
      onlyPanelIds: _scope == StoryboardGenerateScope.selected
          ? [widget.selectedPanelId ?? '']
          : null,
      selectedImageOnly: _scope == StoryboardGenerateScope.ungenerated,
    );
  }

  /// 逐条计价再求和：每条请求的样本数与尺寸都可能不同，合并计价会失真。
  int _estimate(List<StoryboardPanelRequest> requests) {
    if (requests.isEmpty) return 0;
    final estimator = ref.read(generationAnlasEstimatorProvider);
    var total = 0;
    for (final request in requests) {
      final cost = estimator.estimate(request.params, requestCount: 1);
      if (cost < 0) return cost;
      total += cost;
    }
    return total;
  }

  Future<void> _start(List<StoryboardPanelRequest> requests) async {
    Navigator.of(context).pop();
    await ref
        .read(storyboardGenerationRunnerProvider.notifier)
        .start(
          page: widget.page,
          base: ref.read(generationParamsNotifierProvider),
          onlyPanelIds: _scope == StoryboardGenerateScope.selected
              ? [widget.selectedPanelId ?? '']
              : null,
          selectedImageOnly: _scope == StoryboardGenerateScope.ungenerated,
          background: _isBackground,
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final requests = _requests;
    final estimate = _estimate(requests);
    final canStart = requests.isNotEmpty && estimate >= 0;

    return AlertDialog(
      title: Text(l10n.storyboard_generate),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final scope in StoryboardGenerateScope.values)
                  ChoiceChip(
                    label: Text(_scopeLabel(scope)),
                    selected: _scope == scope,
                    onSelected: (selected) {
                      if (!selected) return;
                      setState(() => _scope = scope);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _summary(requests, estimate),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: canStart
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.error,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.common_cancel),
        ),
        FilledButton(
          onPressed: canStart ? () => _start(requests) : null,
          child: Text(l10n.storyboard_generateConfirm),
        ),
      ],
    );
  }

  String _scopeLabel(StoryboardGenerateScope scope) {
    final l10n = context.l10n;
    switch (scope) {
      case StoryboardGenerateScope.all:
        return l10n.storyboard_generateScopeAll;
      case StoryboardGenerateScope.ungenerated:
        return l10n.storyboard_generateScopeUngenerated;
      case StoryboardGenerateScope.selected:
        return l10n.storyboard_generateScopeSelected;
      case StoryboardGenerateScope.background:
        return l10n.storyboard_selectionBackground;
    }
  }

  String _summary(List<StoryboardPanelRequest> requests, int estimate) {
    final l10n = context.l10n;
    if (requests.isEmpty) {
      if (_isBackground) return l10n.storyboard_generateNoPrompt;
      return widget.page.panels.isEmpty
          ? l10n.storyboard_generateNoPrompt
          : l10n.storyboard_generateNothingToDo;
    }
    if (estimate < 0) return l10n.common_error;
    if (estimate == 0) {
      return l10n.storyboard_generateFree(requests.length);
    }
    return l10n.storyboard_generateSummary(requests.length, estimate);
  }
}
