import 'package:flutter/widgets.dart';

import '../../../core/utils/localization_extension.dart';
import '../../../data/models/character/character_interaction.dart';

/// 角色互动的本地化文案。
///
/// 动作的提示词标签保持 Danbooru 原文（英文），界面只翻译展示名，避免把本地化
/// 文案当成提示词内容写进角色提示词。

/// 互动身份名称。
String interactionRoleLabel(
  BuildContext context,
  CharacterInteractionRole role,
) => switch (role) {
  CharacterInteractionRole.source => context.l10n.characterInteraction_roleSource,
  CharacterInteractionRole.target => context.l10n.characterInteraction_roleTarget,
  CharacterInteractionRole.mutual => context.l10n.characterInteraction_roleMutual,
};

/// 互动动作名称。
String interactionActionLabel(
  BuildContext context,
  CharacterInteractionAction action,
) => switch (action) {
  CharacterInteractionAction.lookingAtAnother =>
    context.l10n.characterInteraction_actionLookingAtAnother,
  CharacterInteractionAction.hug => context.l10n.characterInteraction_actionHug,
  CharacterInteractionAction.holdingHands =>
    context.l10n.characterInteraction_actionHoldingHands,
  CharacterInteractionAction.kiss => context.l10n.characterInteraction_actionKiss,
  CharacterInteractionAction.eyeContact =>
    context.l10n.characterInteraction_actionEyeContact,
  CharacterInteractionAction.hugFromBehind =>
    context.l10n.characterInteraction_actionHugFromBehind,
  CharacterInteractionAction.headpat =>
    context.l10n.characterInteraction_actionHeadpat,
  CharacterInteractionAction.frenchKiss =>
    context.l10n.characterInteraction_actionFrenchKiss,
  CharacterInteractionAction.princessCarry =>
    context.l10n.characterInteraction_actionPrincessCarry,
  CharacterInteractionAction.feeding =>
    context.l10n.characterInteraction_actionFeeding,
  CharacterInteractionAction.lapPillow =>
    context.l10n.characterInteraction_actionLapPillow,
  CharacterInteractionAction.piggyback =>
    context.l10n.characterInteraction_actionPiggyback,
  CharacterInteractionAction.teasing =>
    context.l10n.characterInteraction_actionTeasing,
  CharacterInteractionAction.tickling =>
    context.l10n.characterInteraction_actionTickling,
  CharacterInteractionAction.cheekPinching =>
    context.l10n.characterInteraction_actionCheekPinching,
  CharacterInteractionAction.sharedUmbrella =>
    context.l10n.characterInteraction_actionSharedUmbrella,
  CharacterInteractionAction.comforting =>
    context.l10n.characterInteraction_actionComforting,
};
