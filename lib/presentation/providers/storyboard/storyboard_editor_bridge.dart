import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/storyboard/storyboard_resolution_resolver.dart';
import '../../../../data/models/character/character_prompt.dart';
import '../../../../data/models/storyboard/storyboard_panel.dart';
import '../../../../data/models/storyboard/storyboard_panel_character.dart';
import '../../../../data/models/storyboard/storyboard_panel_generation.dart';
import '../../../../data/models/storyboard/storyboard_resolution.dart';
import '../character_prompt_provider.dart';
import '../generation/generation_params_notifier.dart';
import 'storyboard_document_controller.dart';

/// 左侧参数面板（编辑器）与分镜快照的双向搬运。
///
/// 分镜模式下编辑器承载的是「当前选中分镜」的参数快照：选中时载入，离开或
/// **生成前**写回——生成前不写回，用户刚改过的提示词、画幅、角色就进不了
/// 本次请求。画布拖拽期间编辑器不动分镜文档，写回统一走这里。
class StoryboardEditorBridge {
  StoryboardEditorBridge(this._ref);

  final Ref _ref;

  /// 编辑器载入当前分镜时的请求尺寸基准（宽, 高）。
  ///
  /// 写回时只有与基准不同（用户在左侧改过尺寸）才固化为显式分辨率；
  /// 拖拽矩形只会让自动推导值偏离编辑器里的旧值，不能据此冻结分辨率，
  /// 否则请求大小就再也不跟随版面变化。
  (int, int)? _sizeBaseline;

  (int, int)? get sizeBaseline => _sizeBaseline;

  void markEditorSize(int width, int height) => _sizeBaseline = (width, height);

  void clearBaseline() => _sizeBaseline = null;

  /// 「禁止收费」页面的面积上限；解析结果与实际生成保持同一份钳制尺寸。
  int? get _freeOnlyMaxArea {
    final page = _ref
        .read(storyboardDocumentControllerProvider)
        .valueOrNull
        ?.activePage;
    if (page == null || !page.freeOnly) return null;
    return StoryboardResolutionResolver.freeTierMaxPixels;
  }

  StoryboardPanelGenerationPlan planFor(StoryboardPanel panel) =>
      StoryboardResolutionResolver.resolve(
        layoutWidth: panel.width,
        layoutHeight: panel.height,
        resolution: panel.resolution,
        fit: panel.fit,
        maxArea: _freeOnlyMaxArea,
      );

  /// 把编辑器当前状态写回分镜：字段与快照分别落位。
  Future<void> captureIntoPanel(String panelId) async {
    final document = _ref.read(storyboardDocumentControllerProvider.notifier);
    final params = _ref.read(generationParamsNotifierProvider);
    await document.setPanelPrompt(panelId, params.prompt);
    await document.setPanelNegativePrompt(panelId, params.negativePrompt);
    await document.setPanelSeed(panelId, params.seed < 0 ? null : params.seed);
    await document.setPanelCharacters(
      panelId,
      [
        for (final character
            in _ref.read(characterPromptNotifierProvider).characters)
          if (character.enabled && character.prompt.trim().isNotEmpty)
            StoryboardPanelCharacter(
              prompt: character.prompt,
              negativePrompt: character.negativePrompt,
            ),
      ],
    );
    // 画幅：只有用户在左侧改过尺寸才记为这个分镜的显式分辨率；载入后
    // 没动过就保持自动匹配，请求大小继续跟随版面矩形。
    final baseline = _sizeBaseline;
    if (baseline == null ||
        params.width != baseline.$1 ||
        params.height != baseline.$2) {
      await document.setPanelResolution(
        panelId,
        StoryboardResolution.explicit(
          width: params.width,
          height: params.height,
        ),
      );
    }

    await document.setPanelGeneration(
      panelId,
      StoryboardPanelGeneration(
        model: params.model,
        sampler: params.sampler,
        steps: params.steps,
        scale: params.scale,
        smea: params.smea,
        smeaDyn: params.smeaDyn,
        strength: params.sourceImage == null ? null : params.strength,
        noise: params.sourceImage == null ? null : params.noise,
      ),
    );
  }

  /// 背景选中时，左侧提示词就是背景提示词；写回只落提示词。
  Future<void> captureBackground() async {
    final params = _ref.read(generationParamsNotifierProvider);
    await _ref
        .read(storyboardDocumentControllerProvider.notifier)
        .setBackgroundPrompt(params.prompt);
  }

  /// 把分镜快照载入编辑器。
  ///
  /// 逐项写入而非整体替换：模型切换会带着一串跟随默认值，用
  /// `followDefaults: false` 保留分镜自己记录的步数与 CFG。
  Future<void> applyPanelToEditor(StoryboardPanel panel) async {
    final notifier = _ref.read(generationParamsNotifierProvider.notifier);
    final characters = _ref.read(characterPromptNotifierProvider.notifier);
    final snapshot = panel.generation;

    notifier.updatePrompt(panel.prompt);
    notifier.updateNegativePrompt(panel.negativePrompt ?? '');

    if (snapshot.model != null) {
      notifier.updateModel(snapshot.model!, followDefaults: false);
    }
    if (snapshot.sampler != null) notifier.updateSampler(snapshot.sampler!);
    if (snapshot.steps != null) notifier.updateSteps(snapshot.steps!);
    if (snapshot.scale != null) notifier.updateScale(snapshot.scale!);
    if (snapshot.smea != null) notifier.updateSmea(snapshot.smea!);
    if (snapshot.smeaDyn != null) notifier.updateSmeaDyn(snapshot.smeaDyn!);

    final plan = planFor(panel);
    notifier.updateSize(plan.requestWidth, plan.requestHeight);
    _sizeBaseline = (plan.requestWidth, plan.requestHeight);
    notifier.updateSeed(panel.seed ?? -1);

    if (panel.characters.isEmpty) {
      characters.clearAllCharacters();
    } else {
      characters.replaceAll([
        for (final character in panel.characters)
          CharacterPrompt(
            id: '${panel.id}-${character.prompt.hashCode}',
            name: character.prompt,
            prompt: character.prompt,
            negativePrompt: character.negativePrompt,
          ),
      ]);
    }
  }
}

/// 编辑器桥；非 autoDispose，尺寸基准跨选中切换存活。
final storyboardEditorBridgeProvider = Provider<StoryboardEditorBridge>(
  (ref) => StoryboardEditorBridge(ref),
);
