import 'package:flutter/material.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/camera_angle/camera_angle_preset.dart';
import '../../../screens/settings/widgets/settings_card.dart';
import '../../../themes/design_tokens.dart';
import 'camera_angle_labels.dart';

/// 镜头语言分组：可叠加的取景与光学标签。
class CameraAngleEffectCard extends StatelessWidget {
  const CameraAngleEffectCard({
    super.key,
    required this.effects,
    required this.onToggle,
  });

  final Set<CameraLensEffect> effects;
  final ValueChanged<CameraLensEffect> onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SettingsCard(
      title: l10n.cameraAngle_effectsSection,
      description: l10n.cameraAngle_effectsDescription,
      icon: Icons.camera_outlined,
      child: Wrap(
        spacing: DesignTokens.spacingXs,
        runSpacing: DesignTokens.spacingXxs,
        children: [
          for (final effect in CameraLensEffect.values)
            Tooltip(
              message: effect.tag,
              child: FilterChip(
                label: Text(cameraEffectLabel(context, effect)),
                selected: effects.contains(effect),
                onSelected: (_) => onToggle(effect),
              ),
            ),
        ],
      ),
    );
  }
}
