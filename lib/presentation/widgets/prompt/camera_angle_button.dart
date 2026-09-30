import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/localization_extension.dart';
import '../../../data/models/camera_angle/camera_angle_preset.dart';
import '../common/delayed_rich_tooltip.dart';
import '../common/rich_tooltip_surface.dart';
import '../../providers/camera_angle_provider.dart';
import '../../themes/prompt_semantic_colors.dart';
import 'camera_angle/camera_angle_editor_sheet.dart';
import 'camera_angle/camera_angle_prompt_preview.dart';
import 'prompt_control_button.dart';
import 'prompt_tag_count_badge.dart';

/// 视角控制入口。
///
/// 按钮本身显示当前是否已写入提示词，悬浮提示直接给出将要插入的提示词片段，
/// 点击打开可视化机位编辑器。
class CameraAngleButton extends ConsumerWidget {
  const CameraAngleButton({
    super.key,
    this.compact = false,
    this.iconOnly = false,
    this.maxLabelWidth,
  });

  final bool compact;
  final bool iconOnly;
  final double? maxLabelWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(cameraAnglePresetNotifierProvider);
    final preset = state.preset;
    final color = theme.promptSemanticColors.cameraAngle;

    return DelayedRichTooltip(
      content: RichTooltipSurface(
        maxWidth: 360,
        child: _CameraAngleTooltip(preset: preset),
      ),
      child: PromptControlButton(
        key: const Key('camera-angle-button-surface'),
        color: color,
        active: preset.enabled,
        onPressed: () => CameraAngleEditorSheet.show(context),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 4 : 6,
        ),
        builder: (colors) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              preset.enabled ? Icons.videocam : Icons.videocam_outlined,
              size: compact ? 15 : 16,
              color: colors.accent,
            ),
            if (!iconOnly) ...[
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: maxLabelWidth ?? double.infinity,
                ),
                child: Text(
                  context.l10n.cameraAngle_buttonLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 11 : 12,
                    fontWeight: preset.enabled
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: colors.foreground,
                  ),
                ),
              ),
              if (preset.enabled) ...[
                const SizedBox(width: 5),
                PromptTagCountBadge(
                  count: preset.promptTags.length,
                  selected: preset.enabled,
                  color: color,
                  compact: compact,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _CameraAngleTooltip extends StatelessWidget {
  const _CameraAngleTooltip({required this.preset});

  final CameraAnglePreset preset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final color = theme.promptSemanticColors.cameraAngle;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.videocam_outlined, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.cameraAngle_title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              preset.enabled
                  ? l10n.cameraAngle_statusOn
                  : l10n.cameraAngle_statusOff,
              style: theme.textTheme.labelSmall?.copyWith(
                color: preset.enabled
                    ? color
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          l10n.cameraAngle_promptPreviewLabel,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 6),
        CameraAnglePromptPreview(preset: preset),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(
              Icons.touch_app_rounded,
              size: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                l10n.cameraAngle_openEditorHint,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
