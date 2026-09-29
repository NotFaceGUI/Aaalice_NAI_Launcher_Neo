import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/localization_extension.dart';
import '../../../core/utils/storyboard/storyboard_resolution_resolver.dart';
import '../../../data/models/storyboard/storyboard_fit_mode.dart';
import '../../../data/models/storyboard/storyboard_panel.dart';
import '../../providers/generation/generation_center_mode_provider.dart';
import '../../providers/storyboard/storyboard_document_controller.dart';
import '../../providers/storyboard/storyboard_interaction_provider.dart';
import '../../themes/core/layered_surface_style.dart';
import '../common/collapsible_image_panel.dart';

/// 左侧参数面板里的「分镜设置」分组。
///
/// 复用 [CollapsibleImagePanel]：左侧的角色、反推、图生图、风格迁移、精准参考
/// 都是同一套圆角色面 + 折叠标题，分镜设置必须和它们长得一样，否则一眼就能
/// 看出是硬塞进来的。
///
/// 画幅大小实时反映"版面 → 实际请求"，因为两者几乎不会相同，用户必须随时看得到。
class StoryboardSettingsSection extends ConsumerStatefulWidget {
  const StoryboardSettingsSection({super.key});

  @override
  ConsumerState<StoryboardSettingsSection> createState() =>
      _StoryboardSettingsSectionState();
}

class _StoryboardSettingsSectionState
    extends ConsumerState<StoryboardSettingsSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(generationCenterModeControllerProvider);
    if (mode != GenerationCenterMode.storyboard) {
      return const SizedBox.shrink();
    }

    final page = ref
        .watch(storyboardDocumentControllerProvider)
        .valueOrNull
        ?.activePage;
    final interaction = ref.watch(storyboardInteractionProvider);
    final panel = page == null
        ? null
        : selectedPanelOf(interaction, page.panels);
    // 禁止收费的页面：显示钳制后的请求尺寸，与实际生成一致。
    final maxArea = page != null && page.freeOnly
        ? StoryboardResolutionResolver.freeTierMaxPixels
        : null;

    return CollapsibleImagePanel(
      title: context.l10n.storyboard_sectionTitle,
      icon: Icons.dashboard_customize_outlined,
      isExpanded: _expanded,
      onToggle: () => setState(() => _expanded = !_expanded),
      hasData: panel != null,
      summary: panel == null
          ? Text(context.l10n.storyboard_noSelection)
          : Text(_summaryFor(panel, maxArea)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 与其它分组一致：标题与内容之间一条分隔线。
            const Divider(height: 1),
            const SizedBox(height: 12),
            if (page == null || panel == null)
              _EmptySelection(pageAvailable: page != null)
            else
              _PanelSettings(panel: panel, maxArea: maxArea),
          ],
        ),
      ),
    );
  }

  /// 折叠时给出最关键的一条信息：本分镜实际会请求的尺寸。
  String _summaryFor(StoryboardPanel panel, int? maxArea) {
    final plan = StoryboardResolutionResolver.resolve(
      layoutWidth: panel.width,
      layoutHeight: panel.height,
      resolution: panel.resolution,
      fit: panel.fit,
      maxArea: maxArea,
    );
    return context.l10n.storyboard_requestLabel(
      plan.requestWidth,
      plan.requestHeight,
    );
  }
}

class _EmptySelection extends StatelessWidget {
  const _EmptySelection({required this.pageAvailable});

  final bool pageAvailable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.l10n.storyboard_noSelection,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),

      ],
    );
  }
}

class _PanelSettings extends ConsumerWidget {
  const _PanelSettings({required this.panel, required this.maxArea});

  final StoryboardPanel panel;

  /// 禁止收费页面的面积上限；null 表示不钳制。
  final int? maxArea;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final interaction = ref.watch(storyboardInteractionProvider);
    final document = ref.read(storyboardDocumentControllerProvider.notifier);
    final plan = StoryboardResolutionResolver.resolve(
      layoutWidth: panel.width,
      layoutHeight: panel.height,
      resolution: panel.resolution,
      fit: panel.fit,
      maxArea: maxArea,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 画幅大小：版面是用户拉的框，请求是实际发给服务端的尺寸。
        Text(
          l10n.storyboard_frameSize,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${l10n.storyboard_layoutLabel(plan.layoutWidth, plan.layoutHeight)}'
          '  →  '
          '${l10n.storyboard_requestLabel(plan.requestWidth, plan.requestHeight)}',
          style: theme.textTheme.bodySmall,
        ),
        if (plan.notice != StoryboardResolutionNotice.none) ...[
          const SizedBox(height: 2),
          Text(
            _noticeText(context, plan.notice),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.tertiary,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          l10n.storyboard_fit,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final entry in {
              StoryboardFitMode.cover: l10n.storyboard_fitCover,
              StoryboardFitMode.contain: l10n.storyboard_fitContain,
              StoryboardFitMode.stretch: l10n.storyboard_fitStretch,
            }.entries)
              _Chip(
                label: entry.value,
                selected: entry.key == panel.fit,
                onTap: () => document.setPanelFit(panel.id, entry.key),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _Section(
          title: l10n.storyboard_shape,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (!panel.isPolygon)
                  _Chip(
                    label: l10n.storyboard_convertToPolygon,
                    icon: Icons.pentagon_outlined,
                    onTap: () => _convertToPolygon(ref),
                  )
                else ...[
                  _Chip(
                    label: l10n.storyboard_editVertices,
                    icon: Icons.timeline_outlined,
                    selected: interaction.polygonEditing,
                    onTap: () => ref
                        .read(storyboardInteractionProvider.notifier)
                        .setPolygonEditing(!interaction.polygonEditing),
                  ),
                  _Chip(
                    label: l10n.storyboard_resetShape,
                    icon: Icons.crop_square_outlined,
                    onTap: () => document.resetPanelShape(panel.id),
                  ),
                ],
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Section(
          title: l10n.storyboard_panelSettings,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _Chip(
                  label: l10n.storyboard_lock,
                  selected: panel.locked,
                  onTap: () =>
                      document.setPanelLocked(panel.id, !panel.locked),
                ),
                _Chip(
                  label: l10n.storyboard_ignoreSpacing,
                  selected: panel.ignoreSpacing,
                  onTap: () => document.setPanelIgnoreSpacing(
                    panel.id,
                    !panel.ignoreSpacing,
                  ),
                ),
                _Chip(
                  label: l10n.storyboard_duplicate,
                  icon: Icons.copy_all_outlined,
                  onTap: () async {
                    final id = await document.duplicatePanel(panel.id);
                    if (id.isEmpty) return;
                    ref
                        .read(storyboardInteractionProvider.notifier)
                        .select(id);
                  },
                ),
                _Chip(
                  label: l10n.common_delete,
                  icon: Icons.delete_outline,
                  danger: true,
                  onTap: () {
                    document.beginGesture();
                    document.removePanel(panel.id);
                    ref.read(storyboardInteractionProvider.notifier).clear();
                  },
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  String _noticeText(BuildContext context, StoryboardResolutionNotice notice) {
    final l10n = context.l10n;
    switch (notice) {
      case StoryboardResolutionNotice.none:
        return '';
      case StoryboardResolutionNotice.snappedToLegalSize:
        return l10n.storyboard_noticeSnapped;
      case StoryboardResolutionNotice.clampedToMaxArea:
        return l10n.storyboard_noticeClamped;
      case StoryboardResolutionNotice.upscaledForQuality:
        return l10n.storyboard_noticeUpscaled;
    }
  }

  /// 把矩形转成多边形：以切掉一个角作为起点，用户随后自己拖顶点。
  void _convertToPolygon(WidgetRef ref) {
    final rect = panel.rect;
    const cut = 0.22;
    ref.read(storyboardDocumentControllerProvider.notifier).setPanelPolygon(
      panel.id,
      [
        Offset(rect.left + rect.width * cut, rect.top),
        Offset(rect.right, rect.top),
        Offset(rect.right, rect.bottom),
        Offset(rect.left, rect.bottom),
        Offset(rect.left, rect.top + rect.height * cut),
      ],
    );
    ref.read(storyboardInteractionProvider.notifier).setPolygonEditing(true);
  }
}

/// 带标题的分组色面。
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: controlSurfaceColor(theme.colorScheme),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.labelLarge),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

/// 小动作按钮；选中态用 primary 容器色。
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.onTap,
    this.icon,
    this.selected = false,
    this.danger = false,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool selected;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final background = selected
        ? scheme.primary
        : controlSurfaceColor(scheme);
    final foreground = selected
        ? scheme.onPrimary
        : danger
        ? scheme.error
        : scheme.onSurfaceVariant;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: foreground),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
