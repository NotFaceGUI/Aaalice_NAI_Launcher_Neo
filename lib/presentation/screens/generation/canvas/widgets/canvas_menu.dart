import 'package:flutter/material.dart';

import '../../../../adaptive/adaptive_presenter.dart';
import '../../../../adaptive/interaction_policy.dart';
import '../../../../widgets/common/image_card_context_menu.dart';
import '../../../../widgets/common/pro_context_menu.dart';

/// 画布的上下文菜单入口。
///
/// 精确指针走悬浮菜单，触屏走自适应面板，两条路径共用同一份
/// [ProMenuItem] 列表，保证能力与分组一致（`DESIGN.md` 的 Capability
/// Parity）。菜单本身只负责选择，动作由调用方在选中后执行。
Future<void> showCanvasMenu({
  required BuildContext context,
  required Offset position,
  required String title,
  required List<ProMenuItem> items,
}) async {
  final hasAction = items.any((item) => !item.isDivider);
  if (!hasAction) return;

  final ProMenuItem? selected;
  if (context.interactionPolicy.prefersTouchPresentation) {
    selected = await AdaptivePresenter.showPanel<ProMenuItem>(
      context: context,
      title: title,
      initialChildSize: 0.6,
      minChildSize: 0.32,
      maxChildSize: 0.92,
      builder: (panelContext, scrollController) => ListView(
        controller: scrollController,
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          for (final item in items)
            if (item.isDivider)
              const Divider(height: 1)
            else
              ListTile(
                enabled: item.enabled,
                minVerticalPadding: 12,
                leading: Icon(
                  item.icon,
                  color: item.isDanger
                      ? Theme.of(panelContext).colorScheme.error
                      : null,
                ),
                title: Text(
                  item.label,
                  style: item.isDanger
                      ? TextStyle(
                          color: Theme.of(panelContext).colorScheme.error,
                        )
                      : null,
                ),
                subtitle: item.disabledReason == null
                    ? null
                    : Text(item.disabledReason!),
                onTap: item.enabled
                    ? () => Navigator.of(panelContext).pop(item)
                    : null,
              ),
        ],
      ),
    );
  } else {
    final route = ImageCardContextMenuRoute(position: position, items: items);
    selected = await Navigator.of(context).push<ProMenuItem>(route);
    await route.completed;
  }

  await selected?.onTap?.call();
}
