import 'package:flutter/material.dart';

import '../../../core/utils/localization_extension.dart';
import '../../../data/models/character/character_interaction.dart';
import '../../themes/design_tokens.dart';
import '../../themes/prompt_semantic_colors.dart';
import '../../themes/theme_extension.dart';
import '../common/horizontal_action_strip.dart';
import '../common/horizontal_segmented_control.dart';
import 'character_interaction_labels.dart';

/// 角色互动栏：用可视化选择代替手写 `source#` / `target#` / `mutual#` 语法。
///
/// 互动标签写在**各个角色自己的提示词**里，因此这里只编辑单个角色：先选身份
/// （主动/承受/互相）再点动作，标签就会写进该角色提示词的最前面；重新选择会
/// 替换原有标签，[onChanged] 传 null 表示清除。
///
/// 这里不套独立卡片：它嵌在角色编辑器已有的分组色面里，只用小节标题、留白与
/// 控件表达归属。
class CharacterInteractionBar extends StatefulWidget {
  const CharacterInteractionBar({
    super.key,
    required this.interaction,
    required this.onChanged,
    this.compact = false,
  });

  /// 卡内编辑器用单行可横向滚动的动作条，避免把卡片撑高。
  final bool compact;

  /// 当前角色提示词里已有的互动声明；没有则为 null。
  final CharacterInteraction? interaction;

  /// 写入新的互动声明；null 表示清除。
  final ValueChanged<CharacterInteraction?> onChanged;

  @override
  State<CharacterInteractionBar> createState() => _CharacterInteractionBarState();
}

class _CharacterInteractionBarState extends State<CharacterInteractionBar> {
  /// 还没写入标签前，用户先在界面上选好的身份。
  CharacterInteractionRole? _pendingRole;

  /// 默认收起：角色编辑器常放在固定高度容器里，收起后只占一行。
  bool _expanded = false;

  /// 自定义动作输入框；已写入自定义动作时回填原文。
  late final TextEditingController _customController = TextEditingController(
    text: widget.interaction?.isCustomAction == true
        ? widget.interaction!.action
        : '',
  );

  @override
  void initState() {
    super.initState();
    _customController.addListener(_onCustomChanged);
  }

  @override
  void dispose() {
    _customController.removeListener(_onCustomChanged);
    _customController.dispose();
    super.dispose();
  }

  void _onCustomChanged() => setState(() {});

  /// 写入自定义动作；允许直接粘贴 `target#pointing at another` 这类完整标签。
  void _submitCustom() {
    final action = CharacterInteractionAction.normalizeAction(
      _customController.text,
    );
    if (action.isEmpty) return;
    widget.onChanged(CharacterInteraction(role: _role, action: action));
  }

  @override
  void didUpdateWidget(CharacterInteractionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.interaction != oldWidget.interaction) {
      _pendingRole = null;
      // 切换成别的自定义动作时同步输入框，避免显示过期内容。
      final custom = widget.interaction?.isCustomAction == true
          ? widget.interaction!.action
          : '';
      if (_customController.text != custom) _customController.text = custom;
    }
  }

  CharacterInteractionRole get _role =>
      widget.interaction?.role ??
      _pendingRole ??
      CharacterInteractionRole.source;

  void _selectRole(CharacterInteractionRole role) {
    final current = widget.interaction;
    if (current == null) {
      // 还没选动作，先只记住身份，不往提示词里写东西。
      setState(() => _pendingRole = role);
      return;
    }
    widget.onChanged(CharacterInteraction(role: role, action: current.action));
  }

  Widget get chips {
    final selectedAction = widget.interaction == null
        ? null
        : CharacterInteractionAction.fromTag(widget.interaction!.action);
    final items = [
      for (final action in CharacterInteractionAction.values)
        Tooltip(
          message: action.tag,
          child: FilterChip(
            label: Text(interactionActionLabel(context, action)),
            selected: selectedAction == action,
            onSelected: (selected) => widget.onChanged(
              selected
                  ? CharacterInteraction(role: _role, action: action.tag)
                  : null,
            ),
          ),
        ),
    ];
    if (!widget.compact) {
      return Wrap(
        spacing: DesignTokens.spacingXs,
        runSpacing: DesignTokens.spacingXxs,
        children: items,
      );
    }
    return HorizontalActionStrip(
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: DesignTokens.spacingXs),
            items[i],
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final current = widget.interaction;
    final selectedAction = current == null
        ? null
        : CharacterInteractionAction.fromTag(current.action);
    // 自定义动作不在词表里，摘要直接显示标签原文。
    final summary = current == null
        ? l10n.characterInteraction_notSet
        : '${interactionRoleLabel(context, current.role)} · '
              '${selectedAction == null ? current.action : interactionActionLabel(context, selectedAction)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(theme.appTheme.controlRadius),
          child: Row(
            children: [
              Icon(
                Icons.groups_outlined,
                size: DesignTokens.iconSm,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: DesignTokens.spacingXs),
              Text(
                l10n.characterInteraction_title,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: DesignTokens.spacingXs),
              Expanded(
                child: Text(
                  summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: current == null
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.promptSemanticColors.cameraAngle,
                  ),
                ),
              ),
              if (current != null)
                IconButton(
                  onPressed: () => widget.onChanged(null),
                  tooltip: l10n.characterInteraction_clear,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: DesignTokens.iconSm),
                ),
              IconButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                tooltip: _expanded
                    ? l10n.characterInteraction_collapse
                    : l10n.characterInteraction_expand,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: DesignTokens.iconSm,
                ),
              ),
            ],
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: DesignTokens.spacingXs),
          Text(
            l10n.characterInteraction_roleLabel,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: DesignTokens.spacingXxs),
        HorizontalSegmentedControl(
          child: SegmentedButton<CharacterInteractionRole>(
            segments: [
              for (final role in CharacterInteractionRole.values)
                ButtonSegment(
                  value: role,
                  label: Text(interactionRoleLabel(context, role)),
                ),
            ],
            selected: {_role},
            showSelectedIcon: false,
            onSelectionChanged: (values) => _selectRole(values.first),
          ),
        ),
        const SizedBox(height: DesignTokens.spacingXs),
        chips,
        const SizedBox(height: DesignTokens.spacingXs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('character-interaction-custom-action'),
                controller: _customController,
                onSubmitted: (_) => _submitCustom(),
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: l10n.characterInteraction_customLabel,
                  hintText: l10n.characterInteraction_customHint,
                ),
              ),
            ),
            const SizedBox(width: DesignTokens.spacingXs),
            TextButton(
              onPressed:
                  CharacterInteractionAction.normalizeAction(
                    _customController.text,
                  ).isEmpty
                  ? null
                  : _submitCustom,
              child: Text(l10n.characterInteraction_customApply),
            ),
          ],
        ),
        const SizedBox(height: DesignTokens.spacingXs),
        Text(
          l10n.characterInteraction_hint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        ],
      ],
    );
  }
}
