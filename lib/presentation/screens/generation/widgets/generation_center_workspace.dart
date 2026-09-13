import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../adaptive/interaction_policy.dart';
import '../../../providers/canvas/canvas_visibility_provider.dart';
import '../../../themes/core/layered_surface_style.dart';
import '../../../themes/theme_extension.dart';
import '../canvas/infinite_canvas_view.dart';
import 'image_preview.dart';

/// 生成页中央工作区：图像预览与无限画布在此切换。
///
/// 进入画布时预览向左退出、画布自右进入，退出时反向，两端都保持子树存活
/// （`Offstage + TickerMode`），因此视口、选中、滚动与提示词编辑状态都不会
/// 因为来回切换而丢失。桌面经典布局、官网式布局与移动端共用这一个容器。
class GenerationCenterWorkspace extends ConsumerStatefulWidget {
  const GenerationCenterWorkspace({super.key});

  @override
  ConsumerState<GenerationCenterWorkspace> createState() =>
      _GenerationCenterWorkspaceState();
}

class _GenerationCenterWorkspaceState
    extends ConsumerState<GenerationCenterWorkspace>
    with SingleTickerProviderStateMixin {
  /// 0 = 预览，1 = 无限画布
  late final AnimationController _transition;
  late bool _canvasMounted;

  @override
  void initState() {
    super.initState();
    final canvasOpen = ref.read(infiniteCanvasVisibilityProvider);
    _canvasMounted = canvasOpen;
    _transition = AnimationController(vsync: this, value: canvasOpen ? 1 : 0);
  }

  @override
  void dispose() {
    _transition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final canvasOpen = ref.watch(infiniteCanvasVisibilityProvider);
    if (canvasOpen) _canvasMounted = true;

    ref.listen<bool>(infiniteCanvasVisibilityProvider, (previous, next) {
      if (!mounted || previous == next) return;
      if (next) _canvasMounted = true;
      final target = next ? 1.0 : 0.0;
      if (reduceMotion) {
        _transition.value = target;
        return;
      }
      _transition.duration = theme.appTheme.normalDuration;
      _transition.animateTo(
        target,
        curve: next ? theme.appTheme.enterCurve : theme.appTheme.exitCurve,
      );
    });

    return AnimatedBuilder(
      animation: _transition,
      // 两个子树都用稳定实例传进 builder，切换动画不会重建预览或画布
      child: const ImagePreviewWidget(),
      builder: (context, preview) {
        final progress = _transition.value;
        return Stack(
          children: [
            _buildSlotted(
              child: preview!,
              // 预览关闭后整体让位：t=1 时向左移出一个宽度
              horizontalOffset: -progress,
              visibility: 1 - progress,
            ),
            if (_canvasMounted)
              _buildSlotted(
                child: const InfiniteCanvasView(),
                horizontalOffset: 1 - progress,
                visibility: progress,
              ),
            if (progress < 1)
              Positioned(
                top: 12,
                left: 12,
                child: _CanvasToggleButton(progress: progress),
              ),
          ],
        );
      },
    );
  }

  Widget _buildSlotted({
    required Widget child,
    required double horizontalOffset,
    required double visibility,
  }) {
    final visible = visibility > 0.001;
    return Offstage(
      offstage: !visible,
      child: TickerMode(
        enabled: visible,
        child: IgnorePointer(
          ignoring: !visible,
          child: FractionalTranslation(
            translation: Offset(horizontalOffset, 0),
            child: Opacity(
              opacity: visibility.clamp(0.0, 1.0),
              child: SizedBox.expand(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// 打开无限画布的入口：浮在中央工作区左上角，不参与布局。
class _CanvasToggleButton extends ConsumerWidget {
  const _CanvasToggleButton({required this.progress});

  /// 预览独占（0）时完全可见，切换过程中淡出，避免与画布工具条并存
  final double progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final extent = context.interactionPolicy.minimumControlExtent;
    return Opacity(
      opacity: (1 - progress * 2).clamp(0.0, 1.0),
      child: Material(
        color: sectionSurfaceColor(theme.colorScheme),
        borderRadius: BorderRadius.circular(10),
        child: Tooltip(
          message: context.l10n.infinite_canvas_open,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () =>
                ref.read(infiniteCanvasVisibilityProvider.notifier).open(),
            child: SizedBox(
              width: extent.clamp(36, 48),
              height: extent.clamp(36, 48),
              child: Icon(
                Icons.auto_awesome_motion_outlined,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
