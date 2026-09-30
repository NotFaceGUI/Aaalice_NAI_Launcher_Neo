import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/camera_angle/camera_angle_pose.dart';
import '../../../adaptive/adaptive_presenter.dart';
import '../../../providers/camera_angle_provider.dart';
import '../../../providers/image_generation_provider.dart';
import '../../../themes/design_tokens.dart';
import 'camera_angle_effect_card.dart';
import 'camera_angle_pose_card.dart';
import 'camera_angle_prompt_card.dart';
import 'camera_angle_scene_panel.dart';

/// 视角控制编辑器。
///
/// 宽屏是一个工作区：左侧摄像机画面占满剩余空间，右侧是参数列并独立滚动；
/// 窄屏纵向排列，画面固定在上方，参数在下方滚动。只修改
/// [cameraAnglePresetNotifierProvider]，把片段写进提示词由生成页的提示词
/// 同步统一处理，因此编辑器和工具栏开关的结果一致。
class CameraAngleEditorSheet extends ConsumerWidget {
  const CameraAngleEditorSheet({super.key, required this.scrollController});

  final ScrollController scrollController;

  /// 低于该宽度改成上下排列：双列会把画面和参数都压到不可用。
  static const double _twoColumnBreakpoint = 720;

  /// 宽屏参数列宽度。
  static const double _parametersWidth = 360;

  /// 窄屏画面最多占工作区高度的比例，其余留给参数列。
  static const double _compactSceneRatio = 0.55;

  /// 工作区高度上限，避免超长屏幕把对话框拉满。
  static const double _maxWorkspaceHeight = 520;

  /// 取景框没有可用尺寸时回落到 2:3 竖幅。
  static const double _fallbackAspect = 2 / 3;

  /// 以自适应面板打开：宽屏居中 Dialog，窄屏底部 sheet。
  static Future<void> show(BuildContext context) => AdaptivePresenter.showForm<
    void
  >(
    context: context,
    title: context.l10n.cameraAngle_title,
    dialogWidth: 960,
    builder: (context, scrollController) =>
        CameraAngleEditorSheet(scrollController: scrollController),
  );

  /// 当前生成画幅，作为画面与取景框的比例。
  static double _resolveFrameAspect(WidgetRef ref) {
    final size = ref.watch(
      generationParamsNotifierProvider.select(
        (params) => (width: params.width, height: params.height),
      ),
    );
    if (size.width <= 0 || size.height <= 0) return _fallbackAspect;
    return size.width / size.height;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(cameraAnglePresetNotifierProvider);
    final notifier = ref.read(cameraAnglePresetNotifierProvider.notifier);
    final preset = state.preset;
    final frameAspect = _resolveFrameAspect(ref);
    void resetPose() => notifier.setPose(CameraAnglePose.neutral);

    final scene = CameraAngleScenePanel(
      pose: preset.pose,
      frameAspect: frameAspect,
      onChanged: notifier.setPose,
      onReset: resetPose,
    );
    final parameters = <Widget>[
      CameraAnglePoseCard(
        pose: preset.pose,
        onChanged: notifier.setPose,
        onReset: resetPose,
      ),
      const SizedBox(height: DesignTokens.spacingMd),
      CameraAngleEffectCard(
        effects: preset.effects,
        onToggle: notifier.toggleEffect,
      ),
      const SizedBox(height: DesignTokens.spacingMd),
      CameraAnglePromptCard(
        preset: preset,
        onStrengthChanged: notifier.setStrength,
        onEnabledChanged: notifier.setEnabled,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spacingMd,
        DesignTokens.spacingMd,
        DesignTokens.spacingMd,
        DesignTokens.spacingXs,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : _maxWorkspaceHeight;
          final workspaceHeight = available.clamp(320.0, _maxWorkspaceHeight);
          final workspaceAspect = frameAspect.clamp(0.5, 2.0);
          if (constraints.maxWidth < _twoColumnBreakpoint) {
            // 画面按画幅取高，但不超过工作区的一半多一点，参数列始终有位置。
            final sceneHeight = (constraints.maxWidth / workspaceAspect).clamp(
              0.0,
              workspaceHeight * _compactSceneRatio,
            );
            return SizedBox(
              height: workspaceHeight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: sceneHeight, child: scene),
                  const SizedBox(height: DesignTokens.spacingMd),
                  Expanded(
                    child: _ParameterColumn(
                      scrollController: scrollController,
                      children: parameters,
                    ),
                  ),
                ],
              ),
            );
          }
          return SizedBox(
            height: workspaceHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 左列画面占满剩余空间，参数固定在右列。
                Expanded(child: scene),
                const SizedBox(width: DesignTokens.spacingMd),
                SizedBox(
                  width: _parametersWidth,
                  child: _ParameterColumn(
                    scrollController: scrollController,
                    children: parameters,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 参数列：编辑器里唯一的纵向滚动容器。
class _ParameterColumn extends StatelessWidget {
  const _ParameterColumn({
    required this.scrollController,
    required this.children,
  });

  final ScrollController scrollController;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      ListView(controller: scrollController, padding: EdgeInsets.zero, children: children);
}
