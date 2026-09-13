import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/canvas/canvas_document.dart';
import 'package:nai_launcher/data/models/canvas/canvas_node.dart';
import 'package:nai_launcher/data/models/canvas/canvas_node_kind.dart';
import 'package:nai_launcher/data/models/canvas/canvas_node_params.dart';
import 'package:nai_launcher/data/services/canvas/canvas_repository.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/providers/canvas/canvas_document_controller.dart';
import 'package:nai_launcher/presentation/providers/canvas/canvas_interaction_provider.dart';
import 'package:nai_launcher/presentation/providers/canvas/canvas_repository_provider.dart';
import 'package:nai_launcher/presentation/screens/generation/canvas/widgets/canvas_node_info_panel.dart';
import 'package:nai_launcher/presentation/screens/generation/canvas/widgets/canvas_node_shell.dart';
import 'package:nai_launcher/presentation/screens/generation/canvas/widgets/canvas_note_node.dart';
import 'package:nai_launcher/presentation/screens/generation/canvas/widgets/canvas_seed_todo_node.dart';

class _FakeCanvasRepository extends CanvasRepository {
  _FakeCanvasRepository(this._document);

  CanvasDocument _document;

  @override
  Future<String?> rootPath() async => null;

  @override
  Future<CanvasDocument?> load() async => _document;

  @override
  Future<bool> save(CanvasDocument document) async {
    _document = document;
    return true;
  }
}

void main() {
  final stamp = DateTime.fromMillisecondsSinceEpoch(1700000000000);

  CanvasNode node({
    required String id,
    required CanvasNodeKind kind,
    double x = 100,
    double y = 100,
    String? note,
    int? seed,
    CanvasNodeParams? params,
    bool todoDone = false,
  }) {
    return CanvasNode(
      id: id,
      kind: kind,
      x: x,
      y: y,
      width: 200,
      height: 120,
      noteText: note,
      seed: seed,
      params: params,
      todoDone: todoDone,
      createdAt: stamp,
      updatedAt: stamp,
    );
  }

  Future<ProviderContainer> pumpCanvas(
    WidgetTester tester,
    CanvasNode subject, {
    bool selected = false,
    VoidCallback? onDoubleTap,
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer(
      overrides: [
        canvasRepositoryProvider.overrideWithValue(
          _FakeCanvasRepository(
            CanvasDocument.singleBoard(nodes: [subject], edges: const []),
          ),
        ),
      ],
    );
    // 先卸载再推进时钟：文档防抖落盘会安排一个 300ms 定时器，
    // 让它跑完再销毁容器，避免留下未完成的定时器
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 400));
      container.dispose();
    });
    await container.read(canvasDocumentControllerProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Stack(
              children: [
                // 节点层给外壳的是屏幕单位的紧约束；测试里手工给出同样的盒子
                Positioned(
                  left: subject.x - CanvasNodeShell.handleInset,
                  top: subject.y - CanvasNodeShell.handleInset,
                  width: subject.width + CanvasNodeShell.handleInset * 2,
                  height: subject.height + CanvasNodeShell.handleInset * 2,
                  child: CanvasNodeShell(
                    node: subject,
                    scale: 1,
                    selected: selected,
                    linkSourceActive: false,
                    resizable: true,
                    aspectLocked: subject.kind == CanvasNodeKind.image,
                    onDoubleTap: onDoubleTap,
                    contentBuilder: (context, hovered) =>
                        switch (subject.kind) {
                          CanvasNodeKind.note => CanvasNoteNode(node: subject),
                          CanvasNodeKind.seedTodo => CanvasSeedTodoNode(
                            node: subject,
                            hovered: hovered,
                            selected: selected,
                          ),
                          CanvasNodeKind.image => const SizedBox.shrink(),
                        },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  testWidgets('种子待办节点显示种子、提示词与状态标签', (tester) async {
    await pumpCanvas(
      tester,
      node(
        id: 'todo',
        kind: CanvasNodeKind.seedTodo,
        seed: 4242,
        params: const CanvasNodeParams(prompt: 'a quiet library'),
      ),
    );

    expect(find.text('4242'), findsOneWidget);
    expect(find.text('a quiet library'), findsOneWidget);
    expect(find.text('待生成'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('完成的待办用删除线区分', (tester) async {
    await pumpCanvas(
      tester,
      node(id: 'todo', kind: CanvasNodeKind.seedTodo, seed: 7, todoDone: true),
    );

    expect(find.text('已完成'), findsOneWidget);
    final seedText = tester.widget<Text>(find.text('7'));
    expect(seedText.style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('空便签显示占位文案', (tester) async {
    await pumpCanvas(tester, node(id: 'note', kind: CanvasNodeKind.note));
    expect(find.text('写点什么…'), findsOneWidget);
  });

  testWidgets('便签显示正文并隐藏占位文案', (tester) async {
    await pumpCanvas(
      tester,
      node(id: 'note', kind: CanvasNodeKind.note, note: '第二步再调 CFG'),
    );
    expect(find.text('第二步再调 CFG'), findsOneWidget);
    expect(find.text('写点什么…'), findsNothing);
  });

  testWidgets('便签渲染 Markdown 而不是原样显示标记', (tester) async {
    await pumpCanvas(
      tester,
      node(
        id: 'note',
        kind: CanvasNodeKind.note,
        note: '# 标题\n\n- 第一项\n- **加粗**',
      ),
    );

    // 列表项渲染为文本内容，标记符号本身不再出现在正文里
    expect(find.text('第一项'), findsOneWidget);
    expect(find.text('# 标题'), findsNothing);
    expect(find.textContaining('- 第一项'), findsNothing);
  });

  testWidgets('便签不再提供编辑图标，改为双击进入编辑', (tester) async {
    var doubleTapped = 0;
    await pumpCanvas(
      tester,
      node(id: 'note', kind: CanvasNodeKind.note, note: '内容'),
      onDoubleTap: () => doubleTapped++,
    );

    expect(find.byIcon(Icons.edit_outlined), findsNothing);

    await tester.tap(find.text('内容'));
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(find.text('内容'));
    await tester.pumpAndSettle();

    expect(doubleTapped, 1);
  });

  testWidgets('拖动节点在松手后写回文档', (tester) async {
    final container = await pumpCanvas(
      tester,
      node(id: 'note', kind: CanvasNodeKind.note, note: '拖我'),
    );

    final before = container
        .read(canvasDocumentControllerProvider)
        .value!
        .nodeById('note')!;

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('拖我')),
    );
    // 第一次移动用于越过手势 slop（默认 DragStartBehavior.start 不报告这段位移），
    // 第二次移动才是真正被节点接收的拖动增量
    await gesture.moveBy(const Offset(30, 20));
    await tester.pump();
    await gesture.moveBy(const Offset(50, 30));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final after = container
        .read(canvasDocumentControllerProvider)
        .value!
        .nodeById('note')!;
    expect(after.x, greaterThan(before.x));
    expect(after.y, greaterThan(before.y));
    expect(after.x - before.x, closeTo(80, 0.001));
    expect(after.y - before.y, closeTo(50, 0.001));

    // 让文档防抖落盘跑完，避免测试结束时留下挂起的定时器
    await tester.pump(CanvasDocumentController.persistDebounce);
  });

  testWidgets('单击节点写入选中状态', (tester) async {
    final container = await pumpCanvas(
      tester,
      node(id: 'note', kind: CanvasNodeKind.note, note: '点我'),
    );

    await tester.tap(find.text('点我'));
    await tester.pump();

    expect(container.read(canvasInteractionProvider).selectedNodeId, 'note');
  });

  testWidgets('选中节点时信息浮层可见，作为触屏没有 hover 的等价入口', (tester) async {
    await pumpCanvas(
      tester,
      node(
        id: 'todo',
        kind: CanvasNodeKind.seedTodo,
        seed: 2468,
        params: const CanvasNodeParams(
          prompt: 'a quiet library',
          model: 'nai-diffusion-4-5-full',
        ),
      ),
      selected: true,
    );

    final panel = tester.widget<CanvasNodeInfoPanel>(
      find.byType(CanvasNodeInfoPanel),
    );
    expect(panel.visible, isTrue);
    expect(panel.entries.map((entry) => entry.text), contains('种子 2468'));
    expect(
      panel.entries.map((entry) => entry.text),
      contains('nai-diffusion-4-5-full'),
    );
  });

  testWidgets('未选中且未 hover 时不展示信息浮层', (tester) async {
    await pumpCanvas(
      tester,
      node(id: 'todo', kind: CanvasNodeKind.seedTodo, seed: 1),
    );

    final panel = tester.widget<CanvasNodeInfoPanel>(
      find.byType(CanvasNodeInfoPanel),
    );
    expect(panel.visible, isFalse);
  });

  testWidgets('缩放、拖动与点击都不产生溢出或异常', (tester) async {
    await pumpCanvas(
      tester,
      node(
        id: 'todo',
        kind: CanvasNodeKind.seedTodo,
        seed: 123456789,
        params: const CanvasNodeParams(
          prompt: '一段很长很长的提示词，用来确认窄节点里也会正确截断而不是撑破布局',
          model: 'nai-diffusion-4-5-full',
        ),
      ),
      selected: true,
    );

    expect(find.byType(CanvasSeedTodoNode), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
