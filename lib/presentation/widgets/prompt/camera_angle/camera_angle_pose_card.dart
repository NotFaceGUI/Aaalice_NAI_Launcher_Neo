import 'package:flutter/material.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/camera_angle/camera_angle_pose.dart';
import '../../../screens/settings/widgets/settings_card.dart';
import '../../../themes/design_tokens.dart';
import '../../common/horizontal_segmented_control.dart';
import 'camera_angle_labels.dart';

/// 视角姿态分组：距离与倾斜滑条，以及方位、俯仰快捷档位。
///
/// 可视化画面由 [CameraAngleSceneCard] 单独承载，便于在宽屏把画面固定在右列。
class CameraAnglePoseCard extends StatelessWidget {
  const CameraAnglePoseCard({
    super.key,
    required this.pose,
    required this.onChanged,
    required this.onReset,
  });

  final CameraAnglePose pose;
  final ValueChanged<CameraAnglePose> onChanged;
  final VoidCallback onReset;

  /// 档位按钮落在各自分档区间的代表值上，方便用键盘或触屏直接切档。
  static const double _sideAzimuth = 0.45;
  static const double _backAzimuth = 1;
  static const double _tiltedElevation = 0.6;

  static const double _maxRollDegrees = 20;

  double _representativeAzimuth(CameraAzimuth azimuth) => switch (azimuth) {
    CameraAzimuth.front => 0,
    CameraAzimuth.left => -_sideAzimuth,
    CameraAzimuth.right => _sideAzimuth,
    CameraAzimuth.back => pose.azimuth.isNegative
        ? -_backAzimuth
        : _backAzimuth,
  };

  double _representativeElevation(CameraElevation elevation) =>
      switch (elevation) {
        CameraElevation.above => _tiltedElevation,
        CameraElevation.eye => 0,
        CameraElevation.below => -_tiltedElevation,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return SettingsCard(
      title: l10n.cameraAngle_poseSection,
      description: l10n.cameraAngle_poseDescription,
      icon: Icons.videocam_outlined,
      trailing: TextButton.icon(
        onPressed: onReset,
        icon: const Icon(Icons.restart_alt, size: DesignTokens.iconSm),
        label: Text(l10n.cameraAngle_reset),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SliderHeader(
            label: l10n.cameraAngle_distanceLabel,
            value: cameraShotLabel(context, pose.shotBucket),
          ),
          Slider(
            value: pose.distance,
            min: -1,
            max: 1,
            divisions: 12,
            label: cameraShotLabel(context, pose.shotBucket),
            onChanged: (value) => onChanged(pose.copyWith(distance: value)),
          ),
          const SizedBox(height: DesignTokens.spacingXs),
          _SliderHeader(
            label: l10n.cameraAngle_rollLabel,
            value: '${(pose.roll * _maxRollDegrees).round()}°',
          ),
          Slider(
            value: pose.roll,
            min: -1,
            max: 1,
            divisions: 20,
            label: '${(pose.roll * _maxRollDegrees).round()}°',
            onChanged: (value) => onChanged(pose.copyWith(roll: value)),
            secondaryTrackValue: 0,
          ),
          const SizedBox(height: DesignTokens.spacingSm),
          _GroupLabel(label: l10n.cameraAngle_azimuthLabel),
          HorizontalSegmentedControl(
            child: SegmentedButton<CameraAzimuth>(
              segments: [
                for (final value in CameraAzimuth.values)
                  ButtonSegment(
                    value: value,
                    label: Text(cameraAzimuthLabel(context, value)),
                  ),
              ],
              selected: {pose.azimuthBucket},
              showSelectedIcon: false,
              onSelectionChanged: (values) => onChanged(
                pose.copyWith(azimuth: _representativeAzimuth(values.first)),
              ),
            ),
          ),
          const SizedBox(height: DesignTokens.spacingSm),
          _GroupLabel(label: l10n.cameraAngle_elevationLabel),
          HorizontalSegmentedControl(
            child: SegmentedButton<CameraElevation>(
              segments: [
                for (final value in CameraElevation.values)
                  ButtonSegment(
                    value: value,
                    label: Text(cameraElevationLabel(context, value)),
                  ),
              ],
              selected: {pose.elevationBucket},
              showSelectedIcon: false,
              onSelectionChanged: (values) => onChanged(
                pose.copyWith(
                  elevation: _representativeElevation(values.first),
                ),
              ),
            ),
          ),
          const SizedBox(height: DesignTokens.spacingXs),
          Text(
            l10n.cameraAngle_sideNote,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 滑条上方的标签行，右侧显示当前档位。
class _SliderHeader extends StatelessWidget {
  const _SliderHeader({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 组内小节标题，用于在同一个分组卡片里划分职责。
class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignTokens.spacingXxs),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
