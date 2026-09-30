import 'package:flutter/material.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/camera_angle/camera_angle_pose.dart';
import '../../../themes/core/layered_surface_style.dart';
import '../../../themes/design_tokens.dart';
import '../../../themes/theme_extension.dart';
import 'camera_orbit_pad.dart';

/// 摄像机画面面板。
///
/// 结构与分组卡片一致（Section 色面、无描边），但正文是填满整块高度的画面，
/// 因此在宽屏里它能独占整个左侧工作区，参数面板放在右列。
class CameraAngleScenePanel extends StatelessWidget {
  const CameraAngleScenePanel({
    super.key,
    required this.pose,
    required this.frameAspect,
    required this.onChanged,
    required this.onReset,
  });

  final CameraAnglePose pose;
  final double frameAspect;
  final ValueChanged<CameraAnglePose> onChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: sectionSurfaceColor(theme.colorScheme),
        borderRadius: BorderRadius.circular(theme.appTheme.cardRadius),
      ),
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spacingMd,
        DesignTokens.spacingSm,
        DesignTokens.spacingMd,
        DesignTokens.spacingSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.videocam_outlined,
                size: DesignTokens.iconSm,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: DesignTokens.spacingXs),
              Expanded(
                child: Text(
                  context.l10n.cameraAngle_sceneSection,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignTokens.spacingXs),
          Expanded(
            child: CameraOrbitPad(
              pose: pose,
              frameAspect: frameAspect,
              onChanged: onChanged,
              onReset: onReset,
            ),
          ),
        ],
      ),
    );
  }
}
