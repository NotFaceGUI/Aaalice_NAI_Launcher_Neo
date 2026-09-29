import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/storyboard/storyboard_document.dart';
import 'package:nai_launcher/data/models/storyboard/storyboard_fit_mode.dart';
import 'package:nai_launcher/data/models/storyboard/storyboard_page_background.dart';
import 'package:nai_launcher/data/services/storyboard/storyboard_repository.dart';
import 'package:nai_launcher/presentation/agent_chat/services/storyboard_toolbox.dart';
import 'package:nai_launcher/presentation/providers/storyboard/storyboard_document_controller.dart';
import 'package:nai_launcher/presentation/providers/storyboard/storyboard_repository_provider.dart';

/// 测试用仓库：不落盘，永远当作"还没有文档"，由控制器建默认页。
class _MemoryRepository extends StoryboardRepository {
  StoryboardDocument? saved;

  @override
  Future<StoryboardDocument?> load() async => null;

  @override
  Future<bool> save(StoryboardDocument document) async {
    saved = document;
    return true;
  }
}

final _refProvider = Provider<Ref>((ref) => ref);

void main() {
  test('AI 能创建分镜并通过 update_storyboard_panel 写入角色提示词', () async {
    final container = ProviderContainer(
      overrides: [
        storyboardRepositoryProvider.overrideWithValue(_MemoryRepository()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(storyboardDocumentControllerProvider.future);
    final ref = container.read(_refProvider);
    final tools = {
      for (final tool in StoryboardToolbox(ref).tools()) tool.name: tool,
    };

    final added = await tools['add_storyboard_panels']!.execute('call-1', {
      'rows': 2,
      'columns': 2,
      'replace': true,
    });
    expect(added.isError, isFalse);

    final page = container
        .read(storyboardDocumentControllerProvider)
        .valueOrNull!
        .activePage!;
    expect(page.panels, hasLength(4));
    final panelId = page.panels.first.id;

    final updated = await tools['update_storyboard_panel']!.execute('call-2', {
      'panel_id': panelId,
      'prompt': 'rooftop at sunset',
      'characters': [
        {'prompt': 'alice, red hair'},
        {'prompt': 'bob', 'negative_prompt': 'hat', 'x': 0.2, 'y': 0.8},
        {'prompt': 'c'},
        {'prompt': 'd'},
        {'prompt': 'e'},
        {'prompt': 'f'},
        {'prompt': 'g'},
      ],
    });
    expect(updated.isError, isFalse);

    final panel = container
        .read(storyboardDocumentControllerProvider)
        .valueOrNull!
        .activePage!
        .panelById(panelId)!;
    expect(panel.prompt, 'rooftop at sunset');
    // 超过 6 个角色被截断到模型上限。
    expect(panel.characters, hasLength(6));
    expect(panel.characters.first.prompt, 'alice, red hair');
    expect(panel.characters[1].negativePrompt, 'hat');
    expect(panel.characters[1].x, 0.2);
    expect(panel.characters[1].y, 0.8);

    // 空数组清空角色，回落到页面角色。
    final cleared = await tools['update_storyboard_panel']!.execute('call-3', {
      'panel_id': panelId,
      'characters': <Object?>[],
    });
    expect(cleared.isError, isFalse);
    final afterClear = container
        .read(storyboardDocumentControllerProvider)
        .valueOrNull!
        .activePage!
        .panelById(panelId)!;
    expect(afterClear.characters, isEmpty);

    // 多边形：顶点是页面像素，写入后形状与外接矩形随顶点走。
    final polygon = await tools['update_storyboard_panel']!.execute('call-4', {
      'panel_id': panelId,
      'points': [
        [100.0, 100.0],
        [300.0, 120.0],
        [280.0, 320.0],
        [110.0, 300.0],
      ],
    });
    expect(polygon.isError, isFalse);
    var shapePanel = container
        .read(storyboardDocumentControllerProvider)
        .valueOrNull!
        .activePage!
        .panelById(panelId)!;
    expect(shapePanel.isPolygon, isTrue);
    expect(shapePanel.points, hasLength(4));
    expect(shapePanel.rect.left, closeTo(100, 0.001));
    expect(shapePanel.rect.right, closeTo(300, 0.001));
    expect(shapePanel.rect.top, closeTo(100, 0.001));
    expect(shapePanel.rect.bottom, closeTo(320, 0.001));

    // inspect 返回可直接回传的页面像素顶点。
    final inspected = await tools['inspect_storyboard_panel']!.execute('call-7', {
      'panel_id': panelId,
    });
    final inspectedPanel = inspected.details['panel']! as Map<String, dynamic>;
    final pixelPoints = inspectedPanel['pixel_points']! as List;
    expect(pixelPoints, hasLength(4));
    expect(pixelPoints.first, [100, 100]);

    // 顶点不足 3 个被拒绝，且不改已有形状。
    final badPoints = await tools['update_storyboard_panel']!.execute('call-5', {
      'panel_id': panelId,
      'points': [
        [10, 10],
        [20, 20],
      ],
    });
    expect(badPoints.isError, isTrue);
    expect(
      container
          .read(storyboardDocumentControllerProvider)
          .valueOrNull!
          .activePage!
          .panelById(panelId)!
          .isPolygon,
      isTrue,
    );

    // shape=rect 还原矩形。
    final reset = await tools['update_storyboard_panel']!.execute('call-6', {
      'panel_id': panelId,
      'shape': 'rect',
    });
    expect(reset.isError, isFalse);
    shapePanel = container
        .read(storyboardDocumentControllerProvider)
        .valueOrNull!
        .activePage!
        .panelById(panelId)!;
    expect(shapePanel.isPolygon, isFalse);
    expect(shapePanel.points, isEmpty);
  });

  test('AI 能直接创建多边形分镜（points 入口，外接框随顶点）', () async {
    final container = ProviderContainer(
      overrides: [
        storyboardRepositoryProvider.overrideWithValue(_MemoryRepository()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(storyboardDocumentControllerProvider.future);
    final ref = container.read(_refProvider);
    final tools = {
      for (final tool in StoryboardToolbox(ref).tools()) tool.name: tool,
    };

    final added = await tools['add_storyboard_panels']!.execute('call-1', {
      'replace': true,
      'rects': [
        {'x': 40.0, 'y': 60.0, 'width': 300.0, 'height': 300.0},
        {
          'points': [
            [400.0, 80.0],
            [700.0, 120.0],
            [660.0, 380.0],
            [420.0, 340.0],
          ],
        },
      ],
    });
    expect(added.isError, isFalse);
    expect(added.details['created'], 2);

    final page = container
        .read(storyboardDocumentControllerProvider)
        .valueOrNull!
        .activePage!;
    expect(page.panels, hasLength(2));
    final polygon = page.panels.firstWhere((panel) => panel.isPolygon);
    expect(polygon.points, hasLength(4));
    expect(polygon.rect.left, closeTo(400, 0.001));
    expect(polygon.rect.top, closeTo(80, 0.001));
    expect(polygon.rect.width, closeTo(300, 0.001));
    expect(polygon.rect.height, closeTo(300, 0.001));

    // 只有 2 个顶点且没有矩形字段 → 明确报错，不静默建矩形。
    final bad = await tools['add_storyboard_panels']!.execute('call-2', {
      'rects': [
        {
          'points': [
            [10, 10],
            [20, 20],
          ],
        },
      ],
    });
    expect(bad.isError, isTrue);
  });

  test('AI 能配置整页背景（纯色/提示词/种子/适配）', () async {
    final container = ProviderContainer(
      overrides: [
        storyboardRepositoryProvider.overrideWithValue(_MemoryRepository()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(storyboardDocumentControllerProvider.future);
    final ref = container.read(_refProvider);
    final tools = {
      for (final tool in StoryboardToolbox(ref).tools()) tool.name: tool,
    };

    final updated = await tools['update_storyboard_background']!.execute(
      'call-1',
      {
        'kind': 'color',
        'color': '#112233',
        'prompt': 'rainy school gate',
        'seed': 42,
        'fit': 'contain',
      },
    );
    expect(updated.isError, isFalse);

    final background = container
        .read(storyboardDocumentControllerProvider)
        .valueOrNull!
        .activePage!
        .background;
    expect(background.kind, StoryboardBackgroundKind.color);
    expect(background.colorArgb, 0xFF112233);
    expect(background.prompt, 'rainy school gate');
    expect(background.seed, 42);
    expect(background.fit, StoryboardFitMode.contain);

    // 状态工具里能看到背景设置，AI 不用猜。
    final state = await tools['get_storyboard_state']!.execute('call-2', {});
    final page = state.details['page']! as Map<String, dynamic>;
    final reported = page['background']! as Map<String, dynamic>;
    expect(reported['kind'], 'color');
    expect(reported['color'], '#FF112233');
    expect(reported['seed'], 42);

    // 非法颜色被拒绝，且不改文档。
    final bad = await tools['update_storyboard_background']!.execute('call-3', {
      'color': 'red',
    });
    expect(bad.isError, isTrue);
    expect(
      container
          .read(storyboardDocumentControllerProvider)
          .valueOrNull!
          .activePage!
          .background
          .kind,
      StoryboardBackgroundKind.color,
    );
  });
}
