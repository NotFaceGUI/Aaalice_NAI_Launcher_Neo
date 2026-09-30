import 'package:flutter/material.dart';

import '../../themes/prompt_control_colors.dart';

/// 提示词入口上的数量徽标。
///
/// 模式切换、视角控制等入口都用同一个胶囊形计数，字号与选中色跟随入口语义色，
/// 数字使用等宽字形，避免数量变化时按钮宽度抖动。
class PromptTagCountBadge extends StatelessWidget {
  const PromptTagCountBadge({
    super.key,
    required this.count,
    required this.selected,
    required this.color,
    this.compact = false,
  });

  final int count;
  final bool selected;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = PromptControlColors(
      Theme.of(context),
      color,
      active: selected,
    );
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 5, vertical: 1),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w600,
          color: colors.foreground,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
