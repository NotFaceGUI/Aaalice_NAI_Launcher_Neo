import 'package:flutter/material.dart';

import '../../../../../core/utils/localization_extension.dart';
import '../../../../../data/models/canvas/canvas_node.dart';
import 'canvas_node_info_panel.dart';

/// 种子待办节点内容：固定下来的种子与参数摘要，出图前先留个位置。
class CanvasSeedTodoNode extends StatelessWidget {
  const CanvasSeedTodoNode({
    super.key,
    required this.node,
    required this.hovered,
    required this.selected,
  });

  final CanvasNode node;
  final bool hovered;

  /// 触屏没有 hover，选中时同样展示信息
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    final seed = node.seed;
    final prompt = node.params?.prompt ?? '';
    final done = node.todoDone;

    return Stack(
      fit: StackFit.expand,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.push_pin_outlined,
                    size: 14,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      seed == null
                          ? l10n.infinite_canvas_nodeSeedTodo
                          : '$seed',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        decoration: done ? TextDecoration.lineThrough : null,
                        color: done ? scheme.onSurfaceVariant : null,
                      ),
                    ),
                  ),
                  _TodoStateBadge(done: done),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  prompt.isEmpty
                      ? l10n.infinite_canvas_todoLoadParamsHint
                      : prompt,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: prompt.isEmpty
                        ? scheme.onSurfaceVariant
                        : scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
        CanvasNodeInfoPanel(
          visible: hovered || selected,
          entries: _infoEntries(context),
        ),
      ],
    );
  }

  List<({IconData icon, String text})> _infoEntries(BuildContext context) {
    final l10n = context.l10n;
    final params = node.params;
    final entries = <({IconData icon, String text})>[
      (
        icon: Icons.tag_rounded,
        text: node.seed == null
            ? l10n.infinite_canvas_infoSeed
            : '${l10n.infinite_canvas_infoSeed} ${node.seed}',
      ),
    ];
    final model = params?.model;
    if (model != null && model.isNotEmpty) {
      entries.add((icon: Icons.memory_rounded, text: model));
    }
    final width = params?.width;
    final height = params?.height;
    if (width != null && height != null) {
      entries.add((
        icon: Icons.aspect_ratio_rounded,
        text: '${l10n.infinite_canvas_infoSize} $width × $height',
      ));
    }
    return entries;
  }
}

class _TodoStateBadge extends StatelessWidget {
  const _TodoStateBadge({required this.done});

  final bool done;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: done
            ? scheme.secondaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        done ? l10n.infinite_canvas_todoDone : l10n.infinite_canvas_todoPending,
        style: theme.textTheme.labelSmall?.copyWith(
          color: done ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
