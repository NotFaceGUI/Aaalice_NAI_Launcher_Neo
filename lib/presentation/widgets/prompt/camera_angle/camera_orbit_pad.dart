import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/camera_angle/camera_angle_pose.dart';
import '../../../themes/core/layered_surface_style.dart';
import '../../../themes/design_tokens.dart';
import '../../../themes/prompt_semantic_colors.dart';
import '../../../themes/theme_extension.dart';
import 'camera_orbit_painter.dart';

/// 视角姿态的可视化画面。
///
/// 画面区域由 [sceneBuilder] 提供（应用内是加载开源角色模型的 three.js 视口，
/// 组件测试与不支持 WebView 的环境回落到画布内的矢量预览）；数值读数和操作
/// 提示固定排在画面下方，既保证图标与数字对齐，也避免被原生视图遮住。
/// 矢量预览路径保留拖动旋转、滚轮推拉、双击复位和方向键等价操作。
class CameraOrbitPad extends StatefulWidget {
  const CameraOrbitPad({
    super.key,
    required this.pose,
    required this.frameAspect,
    required this.onChanged,
    this.onReset,
  });

  final CameraAnglePose pose;

  /// 当前生成画幅（宽 / 高）。
  final double frameAspect;

  final ValueChanged<CameraAnglePose> onChanged;
  final VoidCallback? onReset;

  /// 方向键每次调整的角度比例。
  static const double _keyboardStep = 0.08;

  @override
  State<CameraOrbitPad> createState() => _CameraOrbitPadState();
}

class _CameraOrbitPadState extends State<CameraOrbitPad> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'camera-orbit-pad');
  double _lastScale = 1;
  bool _focused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _nudge({double? azimuth, double? elevation, double? distance}) {
    widget.onChanged(
      widget.pose.copyWith(
        azimuth: widget.pose.azimuth + (azimuth ?? 0),
        elevation: widget.pose.elevation + (elevation ?? 0),
        distance: widget.pose.distance + (distance ?? 0),
      ),
    );
  }

  Map<ShortcutActivator, VoidCallback> get _shortcuts => {
    const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
        _nudge(azimuth: -CameraOrbitPad._keyboardStep),
    const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
        _nudge(azimuth: CameraOrbitPad._keyboardStep),
    const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
        _nudge(elevation: CameraOrbitPad._keyboardStep),
    const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
        _nudge(elevation: -CameraOrbitPad._keyboardStep),
    const SingleActivator(LogicalKeyboardKey.minus): () =>
        _nudge(distance: -CameraOrbitPad._keyboardStep * 2),
    const SingleActivator(LogicalKeyboardKey.equal): () =>
        _nudge(distance: CameraOrbitPad._keyboardStep * 2),
    const SingleActivator(LogicalKeyboardKey.digit0): () =>
        widget.onReset?.call(),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return Semantics(
      label: l10n.cameraAngle_padLabel,
      hint: l10n.cameraAngle_padHint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 画面铺满可用区域：宽度由面板决定，取景比例由画布内的机位视锥体现。
          Expanded(child: _buildViewport(context, theme)),
          const SizedBox(height: DesignTokens.spacingXs),
          _ReadoutRow(pose: widget.pose),
          const SizedBox(height: DesignTokens.spacingXxs),
          Text(
            l10n.cameraAngle_dragHint,
            maxLines: 2,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// 画面本体：原生视口或矢量预览，外框与手势层在此统一维护。
  Widget _buildViewport(BuildContext context, ThemeData theme) {
    return Focus(
      focusNode: _focusNode,
      onFocusChange: (value) => setState(() => _focused = value),
      child: CallbackShortcuts(
        bindings: _shortcuts,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 手势灵敏度按画面本身换算。
            final canvasSize = Size(
              constraints.maxWidth,
              constraints.maxHeight,
            );
            return MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (_) {
                  if (!_focused) _focusNode.requestFocus();
                },
                onDoubleTap: widget.onReset,
                onScaleStart: (_) => _lastScale = 1,
                onScaleUpdate: (details) =>
                    _handleScaleUpdate(details, canvasSize),
                child: Listener(
                  onPointerSignal: _handlePointerSignal,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: controlSurfaceColor(theme.colorScheme),
                      borderRadius: BorderRadius.circular(
                        theme.appTheme.controlRadius,
                      ),
                      border: Border.all(
                        color: _focused
                            ? theme.promptSemanticColors.cameraAngle
                            : theme.colorScheme.outlineVariant.withValues(
                                alpha: 0.35,
                              ),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        theme.appTheme.controlRadius,
                      ),
                      child: CustomPaint(
                        painter: CameraOrbitPainter(
                          pose: widget.pose,
                          frameAspect: widget.frameAspect,
                          subjectOutline: theme.colorScheme.onSurface
                              .withValues(alpha: 0.55),
                          gridColor: theme.colorScheme.onSurface
                              .withValues(alpha: 0.13),
                          cameraColor:
                              theme.promptSemanticColors.cameraAngle,
                          detailColor:
                              theme.promptSemanticColors.cameraAngle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _handleScaleUpdate(ScaleUpdateDetails details, Size size) {
    if (details.pointerCount >= 2) {
      final delta = (_lastScale - details.scale) * 0.6;
      _lastScale = details.scale;
      if (delta == 0) return;
      _nudge(distance: delta);
      return;
    }
    if (size.isEmpty) return;
    final delta = details.focalPointDelta;
    if (delta == Offset.zero) return;
    widget.onChanged(
      widget.pose.copyWith(
        azimuth: widget.pose.azimuth + delta.dx / (size.width * 0.45),
        elevation: widget.pose.elevation - delta.dy / (size.height * 0.6),
      ),
    );
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    _nudge(distance: event.scrollDelta.dy * 0.0015);
  }
}

/// 画面下方的数值读数：图标与数字同一行居中，左右两侧对称。
class _ReadoutRow extends StatelessWidget {
  const _ReadoutRow({required this.pose});

  final CameraAnglePose pose;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: _Readout(
            icon: Icons.explore_outlined,
            label: l10n.cameraAngle_azimuthShort,
            value: _formatAngle(pose.azimuth * 180),
          ),
        ),
        const SizedBox(width: DesignTokens.spacingXxs),
        Expanded(
          child: _Readout(
            icon: Icons.straighten,
            label: l10n.cameraAngle_elevationShort,
            value: _formatAngle(pose.elevation * 72, signed: true),
            alignment: MainAxisAlignment.center,
          ),
        ),
        const SizedBox(width: DesignTokens.spacingXxs),
        Expanded(
          child: _Readout(
            icon: Icons.rotate_right,
            label: l10n.cameraAngle_rollShort,
            value: _formatAngle(pose.roll * 20, signed: true),
            alignment: MainAxisAlignment.end,
            emphasized: pose.tilts,
          ),
        ),
      ],
    );
  }

  static String _formatAngle(double degrees, {bool signed = false}) {
    final rounded = degrees.round();
    return signed && rounded > 0 ? '+$rounded°' : '$rounded°';
  }
}

class _Readout extends StatelessWidget {
  const _Readout({
    required this.icon,
    required this.label,
    required this.value,
    this.alignment = MainAxisAlignment.start,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final MainAxisAlignment alignment;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = emphasized
        ? theme.promptSemanticColors.cameraAngle
        : theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisAlignment: alignment,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            '$label $value',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              height: 1.2,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}
