import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/utils/nai_resolution_adapter.dart';
import 'package:nai_launcher/core/utils/storyboard/storyboard_resolution_resolver.dart';
import 'package:nai_launcher/data/models/image/image_params.dart';
import 'package:nai_launcher/data/models/storyboard/storyboard_page.dart';
import 'package:nai_launcher/data/models/storyboard/storyboard_page_background.dart';
import 'package:nai_launcher/data/models/storyboard/storyboard_panel.dart';
import 'package:nai_launcher/data/models/storyboard/storyboard_panel_status.dart';
import 'package:nai_launcher/data/models/storyboard/storyboard_resolution.dart';
import 'package:nai_launcher/data/services/storyboard/storyboard_generation_planner.dart';

void main() {
  final stamp = DateTime.fromMillisecondsSinceEpoch(1700000000000);

  StoryboardPanel panel({
    String id = 'p1',
    int order = 1,
    double x = 0,
    double y = 0,
    double width = 832,
    double height = 1216,
    String prompt = 'panel prompt',
    String? negativePrompt,
    int? seed,
    int variants = 1,
    StoryboardResolution resolution = const StoryboardResolution.auto(),
    List<String> images = const [],
  }) {
    return StoryboardPanel(
      id: id,
      order: order,
      x: x,
      y: y,
      width: width,
      height: height,
      prompt: prompt,
      negativePrompt: negativePrompt,
      seed: seed,
      variants: variants,
      resolution: resolution,
      images: images,
      selectedImage: images.isEmpty ? null : images.last,
      status: images.isEmpty
          ? StoryboardPanelStatus.empty
          : StoryboardPanelStatus.done,
      createdAt: stamp,
      updatedAt: stamp,
    );
  }

  StoryboardPage page(List<StoryboardPanel> panels) => StoryboardPage(
    id: 'page',
    name: '',
    width: 2048,
    height: 2896,
    panels: panels,
    createdAt: stamp,
    updatedAt: stamp,
  );

  group('提示词解析', () {
    test('分镜没有提示词时继承生成页提示词', () {
      final requests = StoryboardGenerationPlanner.planPage(
        page: page([panel(prompt: '')]),
        base: const ImageParams(prompt: 'base prompt'),
      );
      expect(requests.single.params.prompt, 'base prompt');
    });

    test('分镜自己的提示词优先', () {
      final requests = StoryboardGenerationPlanner.planPage(
        page: page([panel(prompt: 'panel prompt')]),
        base: const ImageParams(prompt: 'base prompt'),
      );
      expect(requests.single.params.prompt, 'panel prompt');
    });

    test('分镜与生成页都没有提示词时跳过该分镜', () {
      final requests = StoryboardGenerationPlanner.planPage(
        page: page([panel(prompt: '   ')]),
        base: const ImageParams(),
      );
      expect(requests, isEmpty);
    });

    test('负面提示词按 分镜 > 页面 > 生成页 取值', () {
      const base = ImageParams(negativePrompt: 'base negative');

      final fromPanel = StoryboardGenerationPlanner.planPage(
        page: page([panel(negativePrompt: 'panel negative')]),
        base: base,
        pageNegativePrompt: 'page negative',
      );
      expect(fromPanel.single.params.negativePrompt, 'panel negative');

      final fromPage = StoryboardGenerationPlanner.planPage(
        page: page([panel()]),
        base: base,
        pageNegativePrompt: 'page negative',
      );
      expect(fromPage.single.params.negativePrompt, 'page negative');

      final fromBase = StoryboardGenerationPlanner.planPage(
        page: page([panel()]),
        base: base,
      );
      expect(fromBase.single.params.negativePrompt, 'base negative');
    });
  });

  group('分辨率', () {
    test('自动模式使用吸附后的合法请求尺寸', () {
      final requests = StoryboardGenerationPlanner.planPage(
        page: page([panel(width: 1000, height: 1400)]),
        base: const ImageParams(),
      );
      final params = requests.single.params;
      expect(params.width, requests.single.plan.requestWidth);
      expect(params.height, requests.single.plan.requestHeight);
      expect(
        NaiResolutionAdapter.isGenerationCompatible(params.width, params.height),
        isTrue,
      );
      // 版面尺寸不是 64 倍数，必须被吸附而不是原样发出。
      expect(params.width % 64, 0);
      expect(params.height % 64, 0);
      expect(requests.single.plan.layoutWidth, 1000);
      expect(requests.single.plan.layoutHeight, 1400);
    });

    test('显式模式覆盖版面推导', () {
      final requests = StoryboardGenerationPlanner.planPage(
        page: page([
          panel(
            width: 1000,
            height: 1400,
            resolution: const StoryboardResolution.explicit(
              width: 832,
              height: 1216,
            ),
          ),
        ]),
        base: const ImageParams(),
      );
      expect(requests.single.params.width, 832);
      expect(requests.single.params.height, 1216);
    });
  });

  test('装配回调把固定词与预设套到分镜提示词上', () {
    final requests = StoryboardGenerationPlanner.planPage(
      page: page([panel(prompt: '1girl')]),
      base: const ImageParams(),
      assembly: StoryboardPromptAssembly(
        apply: (prompt, negative) => ('[fx] $prompt', '[uc] $negative'),
      ),
    );
    expect(requests.single.params.prompt, '[fx] 1girl');
    expect(requests.single.params.negativePrompt, '[uc] ');
  });

  test('背景提示词同样经过装配', () {
    final backgroundPage = StoryboardPage(
      id: 'page',
      name: '',
      width: 1024,
      height: 1024,
      background: const StoryboardPageBackground(prompt: 'city skyline'),
      createdAt: stamp,
      updatedAt: stamp,
    );
    final requests = StoryboardGenerationPlanner.planBackground(
      page: backgroundPage,
      base: const ImageParams(),
      assembly: StoryboardPromptAssembly(
        apply: (prompt, negative) => ('[fx] $prompt', negative),
      ),
    );
    expect(requests.single.params.prompt, '[fx] city skyline');
  });

  group('变体拆分', () {
    test('不超过单次上限时只发一次请求', () {
      final requests = StoryboardGenerationPlanner.planPage(
        page: page([panel(variants: 3)]),
        base: const ImageParams(),
      );
      expect(requests.length, 1);
      expect(requests.single.params.nSamples, 3);
    });

    test('超过单次上限时拆成多条请求并补齐余数', () {
      final requests = StoryboardGenerationPlanner.planPage(
        page: page([
          panel(variants: StoryboardGenerationPlanner.maxSamplesPerRequest + 2),
        ]),
        base: const ImageParams(),
      );
      expect(requests.length, 2);
      expect(requests[0].params.nSamples, StoryboardGenerationPlanner.maxSamplesPerRequest);
      expect(requests[1].params.nSamples, 2);
      expect(requests.every((r) => r.panelId == 'p1'), isTrue);
    });

    test('变体数量被钳制在分镜允许范围内', () {
      final requests = StoryboardGenerationPlanner.planPage(
        page: page([panel(variants: 999)]),
        base: const ImageParams(),
      );
      final total = requests.fold<int>(0, (sum, r) => sum + r.params.nSamples);
      // 构造时未走 JSON，variants 仍是原值，规划器负责钳制。
      expect(total, StoryboardPanel.maxVariants);
    });
  });

  group('种子', () {
    test('未设种子时交给服务端随机', () {
      final requests = StoryboardGenerationPlanner.planPage(
        page: page([panel()]),
        base: const ImageParams(),
      );
      expect(requests.single.params.seed, -1);
    });

    test('设了种子时按批次递增，保证同一分镜的变体不重复', () {
      final requests = StoryboardGenerationPlanner.planPage(
        page: page([panel(seed: 1000, variants: 6)]),
        base: const ImageParams(),
      );
      expect(requests[0].params.seed, 1000);
      expect(requests[1].params.seed, 1004);
    });
  });

  test('分镜一律从零生成，不继承生成页的图生图源图与蒙版', () {
    final base = ImageParams(
      action: ImageGenerationAction.img2img,
      sourceImage: Uint8List.fromList([1, 2, 3]),
      maskImage: Uint8List.fromList([4, 5, 6]),
      model: 'custom-model',
      steps: 42,
    );
    final requests = StoryboardGenerationPlanner.planPage(
      page: page([panel()]),
      base: base,
    );
    final params = requests.single.params;
    expect(params.action, ImageGenerationAction.generate);
    expect(params.sourceImage, isNull);
    expect(params.maskImage, isNull);
    // 模型与采样参数仍然继承，分镜之间共享风格。
    expect(params.model, 'custom-model');
    expect(params.steps, 42);
  });

  group('范围过滤', () {
    test('onlyPanelIds 只保留指定分镜', () {
      final requests = StoryboardGenerationPlanner.planPage(
        page: page([panel(id: 'a'), panel(id: 'b', order: 2)]),
        base: const ImageParams(),
        onlyPanelIds: ['b'],
      );
      expect(requests.single.panelId, 'b');
    });

    test('selectedImageOnly 跳过已有图的分镜', () {
      final requests = StoryboardGenerationPlanner.planPage(
        page: page([
          panel(id: 'a', images: const ['2026-09-29/a.png']),
          panel(id: 'b', order: 2),
        ]),
        base: const ImageParams(),
        selectedImageOnly: true,
      );
      expect(requests.single.panelId, 'b');
    });

    test('按阅读顺序而不是列表顺序展开', () {
      final requests = StoryboardGenerationPlanner.planPage(
        page: page([
          panel(id: 'second', order: 2),
          panel(id: 'first', order: 1),
        ]),
        base: const ImageParams(),
      );
      expect(requests.map((r) => r.panelId), ['first', 'second']);
    });

    test('空页面返回空列表', () {
      expect(
        StoryboardGenerationPlanner.planPage(
          page: page(const []),
          base: const ImageParams(prompt: 'x'),
        ),
        isEmpty,
      );
    });
  });

  test('planPanel 与 planPage 对单个分镜的结果一致', () {
    final target = panel(seed: 7, variants: 2);
    final viaPage = StoryboardGenerationPlanner.planPage(
      page: page([target]),
      base: const ImageParams(),
    );
    final viaPanel = StoryboardGenerationPlanner.planPanel(
      panel: target,
      base: const ImageParams(),
    );
    expect(viaPanel.length, viaPage.length);
    expect(viaPanel.first.params.width, viaPage.first.params.width);
    expect(viaPanel.first.params.seed, viaPage.first.params.seed);
  });

  group('背景生成', () {
    StoryboardPage pageWithBackground({
      String prompt = 'city skyline',
      int? seed,
    }) {
      return StoryboardPage(
        id: 'page',
        name: '',
        width: 2048,
        height: 2896,
        background: StoryboardPageBackground(prompt: prompt, seed: seed),
        createdAt: stamp,
        updatedAt: stamp,
      );
    }

    test('提示词为空时不产生请求', () {
      expect(
        StoryboardGenerationPlanner.planBackground(
          page: pageWithBackground(prompt: '   '),
          base: const ImageParams(),
        ),
        isEmpty,
      );
    });

    test('用保留 id 标记背景请求，尺寸收敛到单张上限', () {
      final requests = StoryboardGenerationPlanner.planBackground(
        page: pageWithBackground(),
        base: const ImageParams(),
      );
      final request = requests.single;
      expect(
        request.panelId,
        StoryboardGenerationPlanner.backgroundRequestId,
      );
      expect(request.params.prompt, 'city skyline');
      expect(request.params.nSamples, 1);
      // 整页 2048×2896 超过 3MP，必须被收敛而不是原样发出。
      expect(
        NaiResolutionAdapter.isGenerationCompatible(
          request.params.width,
          request.params.height,
        ),
        isTrue,
      );
      expect(request.plan.notice, StoryboardResolutionNotice.clampedToMaxArea);
    });

    test('背景种子与从零生成的约定一致', () {
      final withSeed = StoryboardGenerationPlanner.planBackground(
        page: pageWithBackground(seed: 99),
        base: const ImageParams(),
      );
      expect(withSeed.single.params.seed, 99);

      final withoutSeed = StoryboardGenerationPlanner.planBackground(
        page: pageWithBackground(),
        base: const ImageParams(),
      );
      expect(withoutSeed.single.params.seed, -1);
    });

    test('背景不继承生成页的图生图源图', () {
      final requests = StoryboardGenerationPlanner.planBackground(
        page: pageWithBackground(),
        base: ImageParams(
          action: ImageGenerationAction.img2img,
          sourceImage: Uint8List.fromList([1, 2, 3]),
        ),
      );
      expect(requests.single.params.action, ImageGenerationAction.generate);
      expect(requests.single.params.sourceImage, isNull);
    });

    test('禁止收费页面：背景尺寸与步数都收敛到免费档', () {
      final page = StoryboardPage(
        id: 'page',
        name: '',
        width: 2048,
        height: 2896,
        freeOnly: true,
        background: const StoryboardPageBackground(prompt: 'city skyline'),
        createdAt: stamp,
        updatedAt: stamp,
      );
      final requests = StoryboardGenerationPlanner.planBackground(
        page: page,
        base: const ImageParams(steps: 50),
      );
      final request = requests.single;
      expect(
        request.params.width * request.params.height,
        lessThanOrEqualTo(StoryboardResolutionResolver.freeTierMaxPixels),
        reason:
            '背景 ${request.params.width}x${request.params.height} 仍会产生 Anlas 消耗',
      );
      expect(
        NaiResolutionAdapter.isGenerationCompatible(
          request.params.width,
          request.params.height,
        ),
        isTrue,
      );
      expect(
        request.params.steps,
        lessThanOrEqualTo(StoryboardResolutionResolver.freeTierMaxSteps),
      );
    });
  });
}
