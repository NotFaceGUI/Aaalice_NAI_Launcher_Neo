import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/camera_angle/camera_angle_preset.dart';
import '../../../providers/image_generation_provider.dart';
import '../../common/horizontal_segmented_control.dart';
import '../../../screens/settings/widgets/settings_card.dart';
import '../../../themes/core/layered_surface_style.dart';
import '../../../themes/design_tokens.dart';
import '../../../themes/theme_extension.dart';
import 'camera_angle_prompt_preview.dart';

/// 提示词片段分组：强度、写入开关和将要插入的原文预览。
class CameraAnglePromptCard extends ConsumerWidget {
  const CameraAnglePromptCard({
    super.key,
    required this.preset,
    required this.onStrengthChanged,
    required this.onEnabledChanged,
    required this.onOutputModeChanged,
  });

  final CameraAnglePreset preset;
  final ValueChanged<double> onStrengthChanged;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<CameraAngleOutputMode> onOutputModeChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    // V3 及更早的模型只认标签，写入英文句子会白占 token。
    final allowDescription = ref.watch(
      generationParamsNotifierProvider.select(
        (params) => ImageModels.isV4Model(params.model),
      ),
    );

    return SettingsCard(
      title: l10n.cameraAngle_promptSection,
      description: l10n.cameraAngle_promptDescription,
      icon: Icons.text_fields_outlined,
      trailing: Switch(
        value: preset.enabled,
        onChanged: onEnabledChanged,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.cameraAngle_strengthLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${CameraAnglePreset.formatWeight(preset.strength)}×',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          Slider(
            value: preset.strength,
            min: CameraAnglePreset.minStrength,
            max: CameraAnglePreset.maxStrength,
            divisions: 15,
            label: '${CameraAnglePreset.formatWeight(preset.strength)}×',
            onChanged: onStrengthChanged,
          ),
          Text(
            l10n.cameraAngle_strengthHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: DesignTokens.spacingSm),
          Text(
            l10n.cameraAngle_outputMode,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: DesignTokens.spacingXxs),
          HorizontalSegmentedControl(
            child: SegmentedButton<CameraAngleOutputMode>(
              segments: [
                ButtonSegment(
                  value: CameraAngleOutputMode.tags,
                  label: Text(l10n.cameraAngle_outputTags),
                ),
                if (allowDescription) ...[
                  ButtonSegment(
                    value: CameraAngleOutputMode.tagsWithDescription,
                    label: Text(l10n.cameraAngle_outputTagsAndDescription),
                  ),
                  ButtonSegment(
                    value: CameraAngleOutputMode.description,
                    label: Text(l10n.cameraAngle_outputDescription),
                  ),
                ],
              ],
              selected: {
                allowDescription
                    ? preset.outputMode
                    : CameraAngleOutputMode.tags,
              },
              showSelectedIcon: false,
              onSelectionChanged: (values) =>
                  onOutputModeChanged(values.first),
            ),
          ),
          const SizedBox(height: DesignTokens.spacingXxs),
          Text(
            allowDescription
                ? l10n.cameraAngle_outputModeHint
                : l10n.cameraAngle_outputTagsOnlyHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: DesignTokens.spacingSm),
          Container(
            key: const ValueKey('camera-angle-prompt-preview'),
            padding: const EdgeInsets.all(DesignTokens.spacingSm),
            decoration: BoxDecoration(
              color: controlSurfaceColor(theme.colorScheme),
              borderRadius: BorderRadius.circular(theme.appTheme.controlRadius),
            ),
            child: CameraAnglePromptPreview(
              preset: preset,
              selectable: true,
              allowDescription: allowDescription,
            ),
          ),
        ],
      ),
    );
  }
}
