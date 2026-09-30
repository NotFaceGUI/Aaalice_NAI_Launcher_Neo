import 'package:flutter/material.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/camera_angle/camera_angle_preset.dart';
import '../../../themes/prompt_semantic_colors.dart';
import '../../common/translated_tag_text.dart';

/// 视角提示词片段的预览。
///
/// 第一行给出会被真实写入提示词的原文（含 NAI 数值强调），下方附带词表翻译；
/// 工具栏悬浮提示和编辑器都复用同一个组件，保证“看到什么就插入什么”。
class CameraAnglePromptPreview extends StatelessWidget {
  const CameraAnglePromptPreview({
    super.key,
    required this.preset,
    this.selectable = false,
    this.maxLines,
    this.allowDescription = true,
  });

  final CameraAnglePreset preset;

  /// 当前模型是否支持自然语言描述（V3 及更早只认标签）。
  final bool allowDescription;
  final bool selectable;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.promptSemanticColors.mainPrompt;
    final fragment = preset.promptFragment(allowDescription: allowDescription);

    if (fragment.isEmpty) {
      return Text(
        context.l10n.cameraAngle_promptEmpty,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return TranslatedPromptText(
      preset.plainTags.join(', '),
      originalText: fragment,
      selectable: selectable,
      maxLines: maxLines,
      style: theme.textTheme.bodyMedium?.copyWith(color: color, height: 1.4),
    );
  }
}
