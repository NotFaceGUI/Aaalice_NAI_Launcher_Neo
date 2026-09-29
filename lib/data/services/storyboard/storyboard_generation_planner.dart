// CharacterPrompt 由 image_params.dart 一并导出，直接用它的形状：
// 只有提示词与一个可选的归一化位置，没有生成页角色那套 id/名称/网格定位。
import 'dart:math' as math;
import '../../models/image/image_params.dart';
import '../../models/storyboard/storyboard_page.dart';
import '../../models/storyboard/storyboard_panel.dart';
import '../../models/storyboard/storyboard_panel_character.dart';
import '../../models/storyboard/storyboard_panel_generation.dart';
import '../../models/storyboard/storyboard_resolution.dart';
import '../../../core/utils/storyboard/storyboard_resolution_resolver.dart';

/// 一次生成请求：某个分镜的一部分变体。
///
/// 单个分镜的变体数可能超过单次请求的上限，因此一个分镜会展开成多条请求；
/// [panelId] 把它们重新归到一起。
class StoryboardPanelRequest {
  const StoryboardPanelRequest({
    required this.panelId,
    required this.panelOrder,
    required this.params,
    required this.plan,
  });

  final String panelId;
  final int panelOrder;
  final ImageParams params;
  final StoryboardPanelGenerationPlan plan;

  int get requestWidth => plan.requestWidth;
  int get requestHeight => plan.requestHeight;
}

/// 逐分镜的提示词装配：把生成页的固定词、质量标签预设与 UC 预设套到每个
/// 分镜最终使用的提示词上。与生成页的装配链保持一致；测试可传 null 跳过。
class StoryboardPromptAssembly {
  const StoryboardPromptAssembly({required this.apply});

  /// 返回（正面提示词, 负面提示词）。
  final (String, String) Function(String prompt, String negative) apply;
}

/// 把分镜页展开成可以逐条发送的生成请求。
///
/// 纯函数，不接触网络、队列与存储：调用方拿到请求后自己决定怎么发。
class StoryboardGenerationPlanner {
  StoryboardGenerationPlanner._();

  /// 单次请求允许的样本数上限，与生成页的"每次请求张数"设置保持一致。
  static const int maxSamplesPerRequest = 4;

  /// 为整页分镜规划请求。
  ///
  /// [base] 是生成页当前的参数，提供模型、采样器、步数、CFG、角色与参考等
  /// 共用部分；分镜只覆盖提示词、尺寸、种子与张数。
  ///
  /// 没有自己的提示词、且 [base] 也没有提示词的分镜会被跳过——没有内容可画，
  /// 提交它只会浪费一次请求。
  static List<StoryboardPanelRequest> planPage({
    required StoryboardPage page,
    required ImageParams base,
    String? pageNegativePrompt,
    Iterable<String>? onlyPanelIds,
    bool selectedImageOnly = false,
    StoryboardPromptAssembly? assembly,
  }) {
    final wanted = onlyPanelIds?.toSet();
    final requests = <StoryboardPanelRequest>[];

    for (final panel in page.panelsByReadingOrder) {
      if (wanted != null && !wanted.contains(panel.id)) continue;
      if (!panel.enabled) continue;
      if (selectedImageOnly && panel.hasImage) continue;

      final built = planPanel(
        panel: panel,
        base: base,
        pageNegativePrompt: pageNegativePrompt,
        freeOnly: page.freeOnly,
        assembly: assembly,
      );
      requests.addAll(built);
    }
    return requests;
  }

  /// 规划页面背景的请求；背景提示词为空时返回空列表。
  ///
  /// 背景没有"版面框"，用整页尺寸作为目标：解析器会把它收敛到单张生成上限
  /// （3,145,728 像素）以内，出图后再由背景的适配方式铺满页面。
  static List<StoryboardPanelRequest> planBackground({
    required StoryboardPage page,
    required ImageParams base,
    StoryboardPromptAssembly? assembly,
  }) {
    final prompt = page.background.prompt.trim();
    if (prompt.isEmpty) return const [];

    final plan = StoryboardResolutionResolver.resolve(
      layoutWidth: page.width.toDouble(),
      layoutHeight: page.height.toDouble(),
      resolution: const StoryboardResolution.auto(),
      fit: page.background.fit,
      // 禁止收费：背景同样不许超出免费档，否则整页背景必然计费。
      maxArea: page.freeOnly
          ? StoryboardResolutionResolver.freeTierMaxPixels
          : null,
    );
    final seed = page.background.seed;

    return [
      StoryboardPanelRequest(
        // 背景不属于任何分镜；空 id 表示回填到页面背景。
        panelId: backgroundRequestId,
        panelOrder: 0,
        plan: plan,
        params: _buildParams(
          base: base,
          prompt: prompt,
          negativePrompt: base.negativePrompt,
          characters: null,
          generation: StoryboardPanelGeneration.empty,
          freeOnly: page.freeOnly,
          plan: plan,
          samples: 1,
          seed: seed,
          assembly: assembly,
        ),
      ),
    ];
  }

  /// 背景请求使用的保留 id；真实分镜 id 是 UUID，不会与它冲突。
  static const String backgroundRequestId = '@background';

  /// 规划单个分镜的请求；提示词为空时返回空列表。
  static List<StoryboardPanelRequest> planPanel({
    required StoryboardPanel panel,
    required ImageParams base,
    String? pageNegativePrompt,
    bool freeOnly = false,
    StoryboardPromptAssembly? assembly,
  }) {
    final prompt = panel.hasPrompt ? panel.prompt.trim() : base.prompt.trim();
    if (prompt.isEmpty) return const [];

    final plan = StoryboardResolutionResolver.resolve(
      layoutWidth: panel.width,
      layoutHeight: panel.height,
      resolution: panel.resolution,
      fit: panel.fit,
      // 禁止收费：超出免费档就在免费范围内出图，出图后再缩放贴合分镜。
      maxArea: freeOnly
          ? StoryboardResolutionResolver.freeTierMaxPixels
          : null,
    );

    final negativePrompt =
        panel.negativePrompt ?? pageNegativePrompt ?? base.negativePrompt;
    final variants = panel.variants.clamp(1, StoryboardPanel.maxVariants);
    final seed = panel.seed;

    final requests = <StoryboardPanelRequest>[];
    final characters = _mapCharacters(characters: panel.characters);
    var produced = 0;
    while (produced < variants) {
      final samples = (variants - produced).clamp(1, maxSamplesPerRequest);
      requests.add(
        StoryboardPanelRequest(
          panelId: panel.id,
          panelOrder: panel.order,
          plan: plan,
          params: _buildParams(
            base: base,
            prompt: prompt,
            negativePrompt: negativePrompt,
            characters: characters,
            generation: panel.generation,
            freeOnly: freeOnly,
            plan: plan,
            samples: samples,
            seed: seed == null ? null : seed + produced,
            assembly: assembly,
          ),
        ),
      );
      produced += samples;
    }
    return requests;
  }

  /// 分镜一律从零生成：不继承生成页的图生图源图或蒙版。
  ///
  /// 共用的是风格与角色（模型、采样器、步数、CFG、角色提示词、Vibe 与参考图），
  /// 而不是"上一张图"——否则每个分镜都会从同一张底图重绘，分镜之间失去独立性。
  static ImageParams _buildParams({
    required ImageParams base,
    required String prompt,
    required String negativePrompt,
    required List<CharacterPrompt>? characters,
    required StoryboardPanelGeneration generation,
    required bool freeOnly,
    required StoryboardPanelGenerationPlan plan,
    required int samples,
    required int? seed,
    StoryboardPromptAssembly? assembly,
  }) {
    // 分镜快照只覆盖它显式记录过的项，其余仍跟随生成页。
    final snapshot = generation;

    final overriding = characters != null;
    final usesCoords = overriding
        ? characters.any((character) => character.positionX != null)
        : base.useCoords;

    // 装配链与生成页一致：固定词、质量标签预设与 UC 预设套在最终提示词上，
    // 无论它来自分镜自己、页面还是生成页。
    final (finalPrompt, finalNegative) = assembly == null
        ? (prompt, negativePrompt)
        : assembly.apply(prompt, negativePrompt);

    return base.copyWith(
      prompt: finalPrompt,
      negativePrompt: finalNegative,
      width: plan.requestWidth,
      height: plan.requestHeight,
      nSamples: samples,
      seed: seed ?? -1,
      action: ImageGenerationAction.generate,
      sourceImage: null,
      maskImage: null,
      characters: characters ?? base.characters,
      // 只为分镜自己的角色启用坐标；继承生成页时沿用生成页的设置。
      useCoords: usesCoords,
      model: snapshot.model ?? base.model,
      sampler: snapshot.sampler ?? base.sampler,
      steps: freeOnly
          ? math.min(
              snapshot.steps ?? base.steps,
              StoryboardResolutionResolver.freeTierMaxSteps,
            )
          : (snapshot.steps ?? base.steps),
      scale: snapshot.scale ?? base.scale,
      smea: snapshot.smea ?? base.smea,
      smeaDyn: snapshot.smeaDyn ?? base.smeaDyn,
    );
  }

  /// 把分镜角色映射成生成用角色。
  static List<CharacterPrompt>? _mapCharacters({
    required List<StoryboardPanelCharacter> characters,
  }) {
    final usable = characters.where((character) => character.isUsable).toList();
    if (usable.isEmpty) return null;
    return [
      for (final character in usable)
        CharacterPrompt(
          prompt: character.prompt,
          negativePrompt: character.negativePrompt,
          positionX: character.x,
          positionY: character.y,
        ),
    ];
  }
}
