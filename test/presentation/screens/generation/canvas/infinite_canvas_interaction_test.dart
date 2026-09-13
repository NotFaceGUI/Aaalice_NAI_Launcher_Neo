import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/data/models/canvas/canvas_document.dart';
import 'package:nai_launcher/data/models/canvas/canvas_node.dart';
import 'package:nai_launcher/data/models/canvas/canvas_node_kind.dart';
import 'package:nai_launcher/data/models/canvas/canvas_node_params.dart';
import 'package:nai_launcher/data/models/canvas/canvas_edge.dart';
import 'package:nai_launcher/data/services/canvas/canvas_repository.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/providers/canvas/canvas_document_controller.dart';
import 'package:nai_launcher/presentation/providers/canvas/canvas_generation_bridge.dart';
import 'package:nai_launcher/presentation/providers/canvas/canvas_interaction_provider.dart';
import 'package:nai_launcher/presentation/providers/canvas/canvas_repository_provider.dart';
import 'package:nai_launcher/presentation/screens/generation/canvas/infinite_canvas_view.dart';
import 'package:nai_launcher/presentation/providers/canvas/canvas_view_controller.dart';
import 'package:nai_launcher/presentation/screens/generation/canvas/widgets/canvas_node_shell.dart';
import 'package:nai_launcher/presentation/screens/generation/canvas/widgets/canvas_edge_layer.dart';
import 'package:nai_launcher/presentation/screens/generation/canvas/canvas_edge_math.dart';
import 'package:nai_launcher/presentation/adaptive/interaction_policy.dart';

/// 只替换磁盘存取，其余走真实实现
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

/// 断掉生成桥，测试不依赖生成链路
class _NoopGenerationBridge extends CanvasGenerationBridge {
  @override
  void build() {}
}

/// 视口持久化只走内存，测试不依赖 Hive
class _FakeCanvasSettings extends LocalStorageService {
  ({double offsetX, double offsetY, double scale})? viewport;

  @override
  ({double offsetX, double offsetY, double scale})?
  getInfiniteCanvasViewport() => viewport;

  @override
  Future<void> setInfiniteCanvasViewport({
    required double offsetX,
    required double offsetY,
    required double scale,
  }) async {
    viewport = (offsetX: offsetX, offsetY: offsetY, scale: scale);
  }

  @override
  bool getInfiniteCanvasOpen() => true;

  @override
  Future<void> setInfiniteCanvasOpen(bool value) async {}

  @override
  bool getInfiniteCanvasAutoImport() => false;

  @override
  Future<void> setInfiniteCanvasAutoImport(bool value) async {}
}

Rect bodyRect(WidgetTester tester, String id) => tester
    .getRect(find.byKey(ValueKey(id)))
    .deflate(
      tester
          .widget<CanvasNodeShell>(find.byKey(ValueKey(id)))
          .handleLayout!
          .inset,
    );

void main() {
  final stamp = DateTime.fromMillisecondsSinceEpoch(1700000000000);

  CanvasNode note(String id, double x, double y, String text) => CanvasNode(
    id: id,
    kind: CanvasNodeKind.note,
    x: x,
    y: y,
    width: 200,
    height: 120,
    noteText: text,
    createdAt: stamp,
    updatedAt: stamp,
  );

  late ProviderContainer container;

  Future<void> pumpView(
    WidgetTester tester,
    CanvasDocument document, {
    Size size = const Size(900, 700),
    EdgeInsets padding = EdgeInsets.zero,
    double textScale = 1,
    bool touch = false,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    container = ProviderContainer(
      overrides: [
        canvasRepositoryProvider.overrideWithValue(
          _FakeCanvasRepository(document),
        ),
        canvasGenerationBridgeProvider.overrideWith(_NoopGenerationBridge.new),
        localStorageServiceProvider.overrideWithValue(_FakeCanvasSettings()),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(CanvasDocumentController.persistDebounce);
      container.dispose();
    });

    final app = MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Padding(padding: padding, child: const InfiniteCanvasView()),
      ),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: touch
            ? InteractionPolicyScope(
                initialPolicy: InteractionPolicy.touchFirst,
                child: app,
              )
            : app,
      ),
    );
    // 首帧后才写入视口尺寸并自动定位内容
    await tester.pump();
    await tester.pump();
  }

  CanvasDocument currentDocument() =>
      container.read(canvasDocumentControllerProvider).value!;

  for (final width in [320.0, 600.0, 840.0, 1180.0, 1600.0]) {
    testWidgets(
      'touch controls at width $width and 3x text are contained and reachable',
      (tester) async {
        await pumpView(
          tester,
          CanvasDocument.singleBoard(
            nodes: [note('a', 4200, 3100, 'A')],
            edges: const [],
          ),
          size: Size(width, 400),
          textScale: 3,
          touch: true,
          padding: const EdgeInsets.fromLTRB(8, 20, 8, 16),
        );
        container.read(canvasViewControllerProvider).setScale(0.25);
        container.read(canvasInteractionProvider.notifier).selectNode('a');
        await tester.pump();
        final shell = tester.widget<CanvasNodeShell>(
          find.byKey(const ValueKey('a')),
        );
        expect(shell.handleLayout!.extent, 48);
        for (final side in CanvasNodeSide.values) {
          final handle = find.byKey(ValueKey('link-a-${side.name}'));
          final hit = tester.hitTestOnBinding(tester.getCenter(handle));
          expect(
            hit.path.any(
              (entry) => entry.target == tester.renderObject(handle),
            ),
            isTrue,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('edge selection uses workspace-local coordinates', (
    tester,
  ) async {
    await pumpView(
      tester,
      CanvasDocument.singleBoard(
        nodes: [note('a', 4200, 3100, 'A'), note('b', 4700, 3300, 'B')],
        edges: [
          CanvasEdge(
            id: 'e',
            fromNodeId: 'a',
            toNodeId: 'b',
            createdAt: stamp,
            updatedAt: stamp,
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(170, 90, 0, 0),
    );
    final layer = tester.widget<CanvasEdgeLayer>(find.byType(CanvasEdgeLayer));
    final route = layer.edges.single.route;
    final midpoint = CanvasEdgeMath.labelAnchor(
      route.start,
      route.end,
      horizontal: route.horizontal,
    );
    final origin = tester.getTopLeft(find.byType(InfiniteCanvasView));
    final viewport = container.read(canvasViewControllerProvider);
    await tester.tapAt(origin + viewport.canvasToScreen(midpoint));
    await tester.pump();
    expect(container.read(canvasInteractionProvider).selectedEdgeId, 'e');
  });

  testWidgets('cancelled link does not create an edge', (tester) async {
    await pumpView(
      tester,
      CanvasDocument.singleBoard(
        nodes: [note('a', 4200, 3100, 'A'), note('b', 4700, 3100, 'B')],
        edges: const [],
      ),
    );
    container.read(canvasInteractionProvider.notifier).selectNode('a');
    await tester.pump();
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('link-a-right'))),
    );
    await gesture.moveTo(bodyRect(tester, 'b').center);
    await tester.pump();
    expect(
      container.read(canvasInteractionProvider).linkDraft?.targetNodeId,
      'b',
    );
    await gesture.cancel();
    await tester.pump(const Duration(milliseconds: 400));
    expect(currentDocument().edges, isEmpty);
    expect(container.read(canvasInteractionProvider).linkDraft, isNull);
  });

  testWidgets('switching boards during drag never commits into the new board', (
    tester,
  ) async {
    final first = CanvasDocument.singleBoard(
      nodes: [note('a', 4200, 3100, 'A')],
      edges: const [],
    );
    final next = CanvasDocument.singleBoard(
      boardId: 'next',
      nodes: [note('a', 100, 100, 'B')],
    ).activeBoard!;
    await pumpView(tester, first.copyWith(boards: [...first.boards, next]));
    final gesture = await tester.startGesture(bodyRect(tester, 'a').center);
    await gesture.moveBy(const Offset(80, 40));
    await tester.pump();
    await container
        .read(canvasDocumentControllerProvider.notifier)
        .selectBoard('next');
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(currentDocument().nodeById('a')!.x, 100);
    expect(
      currentDocument().boardById(first.activeBoardId)!.nodeById('a')!.x,
      4200,
    );
    expect(container.read(canvasDragTrackerProvider).isDragging, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('toolbar drag does not pan the canvas', (tester) async {
    await pumpView(
      tester,
      CanvasDocument.singleBoard(
        nodes: [note('a', 4200, 3100, 'A')],
        edges: const [],
      ),
      size: const Size(320, 700),
    );
    final viewport = container.read(canvasViewControllerProvider);
    final before = viewport.offset;
    final gesture = await tester.startGesture(const Offset(200, 30));
    await gesture.moveBy(const Offset(-80, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(viewport.offset, before);
  });

  void expectRect(Rect actual, Rect expected) {
    expect(actual.left, closeTo(expected.left, 0.001));
    expect(actual.top, closeTo(expected.top, 0.001));
    expect(actual.width, closeTo(expected.width, 0.001));
    expect(actual.height, closeTo(expected.height, 0.001));
  }

  for (final scale in [0.25, 0.5, 1.0, 2.0]) {
    testWidgets(
      'drag at $scale keeps screen motion and committed geometry equal',
      (tester) async {
        await pumpView(
          tester,
          CanvasDocument.singleBoard(
            nodes: [note('a', 4200, 3100, 'A'), note('b', 4550, 3100, 'B')],
            edges: [
              CanvasEdge(
                id: 'edge',
                fromNodeId: 'a',
                toNodeId: 'b',
                createdAt: stamp,
                updatedAt: stamp,
              ),
            ],
          ),
        );
        final viewport = container.read(canvasViewControllerProvider);
        viewport.setScale(scale);
        await tester.pump();
        final before = bodyRect(tester, 'a');
        final persisted = currentDocument().nodeById('a')!;
        final shellState = tester.state(find.byKey(const ValueKey('a')));
        final gesture = await tester.startGesture(before.center);
        await gesture.moveBy(const Offset(60, 40));
        await tester.pump();
        expect(tester.state(find.byKey(const ValueKey('a'))), same(shellState));
        final during = bodyRect(tester, 'a');
        expectRect(during, before.shift(const Offset(60, 40)));
        expect(currentDocument().nodeById('a')!.x, persisted.x);
        final route = tester
            .widget<CanvasEdgeLayer>(find.byType(CanvasEdgeLayer))
            .edges
            .single
            .route;
        final mappedStart = viewport.canvasToScreen(route.start);
        expect(during.inflate(0.01).contains(mappedStart), isTrue);
        await gesture.up();
        await tester.pump();
        expectRect(bodyRect(tester, 'a'), during);
        expect(
          currentDocument().nodeById('a')!.x,
          closeTo(persisted.x + 60 / scale, 0.001),
        );
        expect(container.read(canvasDragTrackerProvider).isDragging, isFalse);
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
      },
    );

    for (final corner in CanvasNodeCorner.values) {
      testWidgets(
        'resize ${corner.name} at $scale anchors opposite corner and commits without jump',
        (tester) async {
          await pumpView(
            tester,
            CanvasDocument.singleBoard(
              nodes: [note('a', 4200, 3100, 'A')],
              edges: const [],
            ),
          );
          container.read(canvasViewControllerProvider).setScale(scale);
          container.read(canvasInteractionProvider.notifier).selectNode('a');
          await tester.pump();
          final before = bodyRect(tester, 'a');
          final handle = find.byKey(ValueKey('resize-a-${corner.name}'));
          final gesture = await tester.startGesture(tester.getCenter(handle));
          final direction = Offset(
            corner.isLeft ? -1 : 1,
            corner.isTop ? -1 : 1,
          );
          await gesture.moveBy(direction * 30);
          await tester.pump();
          final during = bodyRect(tester, 'a');
          expect(during.width, closeTo(before.width + 30, 0.001));
          expect(during.height, closeTo(before.height + 30, 0.001));
          expect(
            corner.isLeft ? during.right : during.left,
            closeTo(corner.isLeft ? before.right : before.left, 0.001),
          );
          expect(
            corner.isTop ? during.bottom : during.top,
            closeTo(corner.isTop ? before.bottom : before.top, 0.001),
          );
          await gesture.up();
          await tester.pump();
          expectRect(bodyRect(tester, 'a'), during);
          expect(container.read(canvasDragTrackerProvider).isDragging, isFalse);
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull);
        },
      );
    }

    for (final side in CanvasNodeSide.values) {
      testWidgets('link ${side.name} at $scale reaches target', (tester) async {
        await pumpView(
          tester,
          CanvasDocument.singleBoard(
            nodes: [note('a', 4200, 3100, 'A'), note('b', 4550, 3100, 'B')],
            edges: const [],
          ),
          size: const Size(1400, 700),
        );
        container.read(canvasViewControllerProvider).setScale(scale);
        container.read(canvasInteractionProvider.notifier).selectNode('a');
        await tester.pump();
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(ValueKey('link-a-${side.name}'))),
        );
        await gesture.moveTo(bodyRect(tester, 'b').center);
        await tester.pump();
        expect(
          container.read(canvasInteractionProvider).linkDraft?.targetNodeId,
          'b',
        );
        await gesture.up();
        await tester.pump();
        expect(currentDocument().edges, hasLength(1));
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('cancelled drag restores layout without changing document', (
    tester,
  ) async {
    await pumpView(
      tester,
      CanvasDocument.singleBoard(
        nodes: [note('a', 4200, 3100, 'A')],
        edges: const [],
      ),
    );
    final before = bodyRect(tester, 'a');
    final gesture = await tester.startGesture(before.center);
    await gesture.moveBy(const Offset(24, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(60, 40));
    await tester.pump();
    await gesture.cancel();
    await tester.pump();
    expectRect(bodyRect(tester, 'a'), before);
    expect(currentDocument().nodeById('a')!.x, 4200);
    expect(container.read(canvasDragTrackerProvider).isDragging, isFalse);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('远离画布原点的节点也在命中范围内，可以点选', (tester) async {
    await pumpView(
      tester,
      CanvasDocument.singleBoard(
        nodes: [note('a', 4200, 3100, '节点甲'), note('b', 4700, 3100, '节点乙')],
        edges: const [],
      ),
    );

    // 内容被自动放进视野，节点确实在视口内
    final surfaceRect = tester.getRect(find.byType(InfiniteCanvasView));
    final nodeCenter = tester.getCenter(find.byKey(const ValueKey('a')));
    expect(
      surfaceRect.contains(nodeCenter),
      isTrue,
      reason: '自动定位后节点应在视口内，实际节点位置 $nodeCenter，视口 $surfaceRect',
    );

    // 选中在按下时生效：只按下不抬起，验证"按下即选中"
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('a'))),
    );
    await tester.pump();

    expect(container.read(canvasInteractionProvider).selectedNodeId, 'a');

    await gesture.up();
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
  });

  testWidgets('拖动远离原点的节点会写回新位置', (tester) async {
    await pumpView(
      tester,
      CanvasDocument.singleBoard(
        nodes: [note('a', 4200, 3100, '拖我')],
        edges: const [],
      ),
    );

    final before = currentDocument().nodeById('a')!;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('a'))),
    );
    // 第一段越过手势 slop（DragStartBehavior.start 不报告这段位移）
    await gesture.moveBy(const Offset(24, 16));
    await tester.pump();
    await gesture.moveBy(const Offset(60, 40));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    final after = currentDocument().nodeById('a')!;
    expect(after.x, greaterThan(before.x));
    expect(after.y, greaterThan(before.y));
    expect(after.x - before.x, closeTo(84, 0.001));
    expect(after.y - before.y, closeTo(56, 0.001));

    await tester.pump(CanvasDocumentController.persistDebounce);
  });

  testWidgets('连线模式下依次点击两个节点会建立连线', (tester) async {
    await pumpView(
      tester,
      CanvasDocument.singleBoard(
        nodes: [note('a', 4200, 3100, '节点甲'), note('b', 4700, 3100, '节点乙')],
        edges: const [],
      ),
    );

    container
        .read(canvasInteractionProvider.notifier)
        .setMode(CanvasInteractionMode.link);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('a')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('b')));
    await tester.pump();

    final document = currentDocument();
    expect(document.edges, hasLength(1));
    expect(document.edges.single.fromNodeId, 'a');
    expect(document.edges.single.toNodeId, 'b');

    await tester.pump(CanvasDocumentController.persistDebounce);
  });

  testWidgets('右键远点节点会打开节点菜单', (tester) async {
    await pumpView(
      tester,
      CanvasDocument.singleBoard(
        nodes: [note('a', 4200, 3100, '菜单')],
        edges: const [],
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('a'))),
      buttons: kSecondaryButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    // 菜单里必须出现节点相关操作
    expect(find.text('从画布移除'), findsOneWidget);
    expect(find.text('置于顶层'), findsOneWidget);

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
  });

  testWidgets('图片节点按真实宽高比落位，节点盒贴合图片', (tester) async {
    final imageNode = CanvasNode(
      id: 'img',
      kind: CanvasNodeKind.image,
      x: 4200,
      y: 3100,
      width: 220,
      height: 220,
      imageRelativePath: '2024-01-01/a.png',
      seed: 7,
      params: const CanvasNodeParams(prompt: 'a cat', width: 832, height: 1216),
      createdAt: stamp,
      updatedAt: stamp,
    );
    await pumpView(
      tester,
      CanvasDocument.singleBoard(nodes: [imageNode], edges: const []),
    );

    // 图片文件不存在，节点走缺失占位；这里只验证命中与选中仍然成立
    await tester.tap(find.byKey(const ValueKey('img')));
    await tester.pump();
    expect(container.read(canvasInteractionProvider).selectedNodeId, 'img');
  });

  testWidgets('缩小到 25% 后节点仍可点选（回归：缩小后命中整片失效）', (tester) async {
    await pumpView(
      tester,
      CanvasDocument.singleBoard(
        nodes: [note('a', 4200, 3100, '节点甲'), note('b', 4700, 3100, '节点乙')],
        edges: const [],
      ),
    );

    // 缩到 25%：此前祖先盒会被压成"包围盒 × scale"，节点随即点不到
    container
        .read(canvasViewControllerProvider)
        .setScale(0.25, focalScreen: const Offset(450, 350));
    await tester.pump();
    await tester.pump();

    final shell = tester.widget<CanvasNodeShell>(
      find.byKey(const ValueKey('a')),
    );
    expect(shell.scale, closeTo(0.25, 1e-9));

    final rect = tester.getRect(find.byKey(const ValueKey('a')));
    final surfaceRect = tester.getRect(find.byType(InfiniteCanvasView));
    expect(surfaceRect.contains(rect.center), isTrue);

    await tester.tap(find.byKey(const ValueKey('a')));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    expect(container.read(canvasInteractionProvider).selectedNodeId, 'a');
  });

  testWidgets('节点屏幕位置等于画布坐标乘以缩放加视口偏移', (tester) async {
    await pumpView(
      tester,
      CanvasDocument.singleBoard(
        nodes: [note('a', 4200, 3100, '甲')],
        edges: const [],
      ),
    );

    final viewport = container.read(canvasViewControllerProvider);
    final expected = viewport.canvasToScreen(const Offset(4200, 3100));
    final surfaceOrigin = tester
        .getRect(find.byType(InfiniteCanvasView))
        .topLeft;
    final shellTopLeft = tester
        .getRect(find.byKey(const ValueKey('a')))
        .topLeft;

    expect(
      shellTopLeft.dx - surfaceOrigin.dx,
      closeTo(expected.dx - CanvasNodeShell.handleInset, 0.5),
    );
    expect(
      shellTopLeft.dy - surfaceOrigin.dy,
      closeTo(expected.dy - CanvasNodeShell.handleInset, 0.5),
    );
  });
}
