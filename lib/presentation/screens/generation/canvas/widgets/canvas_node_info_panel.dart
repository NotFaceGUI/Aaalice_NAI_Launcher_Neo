import 'package:flutter/material.dart';

import '../../../../themes/core/layered_surface_style.dart';
import '../../../../themes/theme_extension.dart';

/// 节点信息浮层：hover 或选中时浮出的关键参数。
///
/// 只做绘制层的淡入与轻微上移，不改变节点布局，因此不会引起重排或命中区
/// 变化（`DESIGN.md` 的 hover 规则）。触屏没有 hover，选中时同样展示，
/// 保证信息在任何输入方式下都可获得。
class CanvasNodeInfoPanel extends StatelessWidget {
  const CanvasNodeInfoPanel({
    super.key,
    required this.visible,
    required this.entries,
  });

  final bool visible;

  /// 图标 + 文本的信息项，按行展示
  final List<({IconData icon, String text})> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion ? Duration.zero : theme.appTheme.fastDuration;

    return IgnorePointer(
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 0.06),
        duration: duration,
        curve: theme.appTheme.standardCurve,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: duration,
          curve: theme.appTheme.standardCurve,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(
                // Overlay 色面：图片内容不可控，必须自带足够不透明度
                color: overlaySurfaceColor(
                  theme.colorScheme,
                ).withValues(alpha: 0.94),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(10),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final entry in entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: Row(
                        children: [
                          Icon(
                            entry.icon,
                            size: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              entry.text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurface,
                                height: 1.25,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
