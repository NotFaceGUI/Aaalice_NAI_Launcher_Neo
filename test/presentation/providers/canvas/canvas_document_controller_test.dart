import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/canvas/canvas_document.dart';
import 'package:nai_launcher/data/models/canvas/canvas_node.dart';
import 'package:nai_launcher/data/models/canvas/canvas_node_kind.dart';
import 'package:nai_launcher/data/models/canvas/canvas_node_params.dart';
import 'package:nai_launcher/data/services/canvas/canvas_repository.dart';
import 'package:nai_launcher/presentation/providers/canvas/canvas_document_controller.dart';
import 'package:nai_launcher/presentation/providers/canvas/canvas_repository_provider.dart';

/// 用内存文档替换磁盘 sidecar，测试只关心文档行为本身
class _FakeCanvasRepository extends CanvasRepository {
  _FakeCanvasRepository({CanvasDocument? initial})
    : _document = initial ?? CanvasDocument.singleBoard();

  CanvasDocument _document;
  int saveCount = 0;

  @override
  Future<String?> rootPath() async => null;

  @override
  Future<CanvasDocument?> load() async => _document;

  @override
  Future<bool> save(CanvasDocument document) async {
    _document = document;
    saveCount++;
    return true;
  }
}

void main() {
  late _FakeCanvasRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = _FakeCanvasRepository();
    container = ProviderContainer(
      overrides: [canvasRepositoryProvider.overrideWithValue(repository)],
    );
  });

  tearDown(() => container.dispose());

  Future<CanvasDocumentController> ready() async {
    await container.read(canvasDocumentControllerProvider.future);
    return container.read(canvasDocumentControllerProvider.notifier);
  }

  CanvasDocument currentDocument() =>
      container.read(canvasDocumentControllerProvider).value!;

  test('首次加载读取图库目录里已有的画布', () async {
    final seededRepository = _FakeCanvasRepository(
      initial: CanvasDocument.singleBoard(
        nodes: [
          CanvasNode(
            id: 'existing',
            kind: CanvasNodeKind.note,
            x: 1,
            y: 2,
            width: 200,
            height: 120,
            noteText: 'from disk',
            createdAt: DateTime.fromMillisecondsSinceEpoch(1),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(1),
          ),
        ],
        edges: const [],
      ),
    );
    final seededContainer = ProviderContainer(
      overrides: [canvasRepositoryProvider.overrideWithValue(seededRepository)],
    );
    addTearDown(seededContainer.dispose);

    await seededContainer.read(canvasDocumentControllerProvider.future);
    final document = seededContainer
        .read(canvasDocumentControllerProvider)
        .value!;
    expect(document.nodes.single.noteText, 'from disk');
    expect(document.nodes.single.x, 1);
  });

  test('新增节点按类型给出默认尺寸并落在空闲位置', () async {
    final controller = await ready();

    await controller.addNoteNode();
    await controller.addSeedTodoNode(seed: 42);
    final imageId = await controller.addImageNode(
      imageRelativePath: '2024-01-01/a.png',
      aspectRatio: 2,
      seed: 99,
      params: const CanvasNodeParams(prompt: 'a cat'),
    );

    final document = currentDocument();
    expect(document.nodes, hasLength(3));
    expect(
      document.nodes.map((node) => node.kind),
      containsAll([
        CanvasNodeKind.note,
        CanvasNodeKind.seedTodo,
        CanvasNodeKind.image,
      ]),
    );

    final image = document.nodeById(imageId)!;
    // 220 宽、宽高比 2 的图片节点高度是 110
    expect(image.height, 110);
    expect(image.seed, 99);
    expect(image.params!.prompt, 'a cat');

    // 三个节点互不重叠
    for (final a in document.nodes) {
      for (final b in document.nodes) {
        if (a.id == b.id) continue;
        final overlaps =
            a.x < b.x + b.width &&
            a.x + a.width > b.x &&
            a.y < b.y + b.height &&
            a.y + a.height > b.y;
        expect(overlaps, isFalse, reason: '${a.id} 与 ${b.id} 重叠');
      }
    }
  });

  test('图片宽高比非法时退回正方形高度', () async {
    final controller = await ready();
    final id = await controller.addImageNode(
      imageRelativePath: 'a.png',
      aspectRatio: 0,
    );
    expect(currentDocument().nodeById(id)!.height, 220);
  });

  test('删除节点同时移除相连的连线', () async {
    final controller = await ready();
    final first = await controller.addNoteNode();
    final second = await controller.addNoteNode();
    final third = await controller.addNoteNode();

    await controller.addEdge(fromNodeId: first, toNodeId: second);
    await controller.addEdge(fromNodeId: first, toNodeId: third);
    expect(currentDocument().edges, hasLength(2));

    await controller.removeNode(first);

    final document = currentDocument();
    expect(document.nodes, hasLength(2));
    expect(document.edges, isEmpty);
  });

  test('拒绝自连与重复连线', () async {
    final controller = await ready();
    final first = await controller.addNoteNode();
    final second = await controller.addNoteNode();

    expect(
      await controller.addEdge(fromNodeId: first, toNodeId: first),
      isNull,
    );
    final edgeId = await controller.addEdge(
      fromNodeId: first,
      toNodeId: second,
    );
    expect(edgeId, isNotNull);
    expect(
      await controller.addEdge(fromNodeId: first, toNodeId: second),
      isNull,
    );
    expect(currentDocument().edges, hasLength(1));
  });

  test('连线标注去除首尾空白，空串等于清除', () async {
    final controller = await ready();
    final first = await controller.addNoteNode();
    final second = await controller.addNoteNode();
    final edgeId = (await controller.addEdge(
      fromNodeId: first,
      toNodeId: second,
    ))!;

    await controller.setEdgeLabel(edgeId, '  参考  ');
    expect(currentDocument().edges.single.label, '参考');

    await controller.setEdgeLabel(edgeId, '   ');
    expect(currentDocument().edges.single.label, isNull);
  });

  test('节点移动到新位置后按 id 更新', () async {
    final controller = await ready();
    final id = await controller.addNoteNode();

    await controller.moveNode(id, x: 500, y: -120);
    final node = currentDocument().nodeById(id)!;
    expect(node.x, 500);
    expect(node.y, -120);
  });

  test('改尺寸被夹在允许区间', () async {
    final controller = await ready();
    final id = await controller.addNoteNode();

    await controller.resizeNode(id, width: 10, height: 99999);
    final node = currentDocument().nodeById(id)!;
    expect(node.width, 72);
    expect(node.height, 1600);
  });

  test('置顶后该节点拥有最大 z 序', () async {
    final controller = await ready();
    final first = await controller.addNoteNode();
    await controller.addNoteNode();

    await controller.bringNodeToFront(first);
    final document = currentDocument();
    expect(document.nodeById(first)!.zOrder, document.maxZOrder);
    expect(document.nodesByZOrder.last.id, first);
  });

  test('手动落盘会把当前文档写回仓库', () async {
    final controller = await ready();
    await controller.addNoteNode();
    expect(repository.saveCount, 0);

    await controller.flush();
    expect(repository.saveCount, 1);
    expect(repository._document.nodes, hasLength(1));
  });

  test('清空画布移除全部节点与连线', () async {
    final controller = await ready();
    final first = await controller.addNoteNode();
    final second = await controller.addNoteNode();
    await controller.addEdge(fromNodeId: first, toNodeId: second);

    await controller.clear();

    final document = currentDocument();
    expect(document.nodes, isEmpty);
    expect(document.edges, isEmpty);
  });

  test('空画布重复清空不产生多余写入', () async {
    final controller = await ready();
    await controller.clear();
    expect(currentDocument().isEmpty, isTrue);
    expect(repository.saveCount, 0);
  });

  test('图片节点比例优先取元数据里的真实像素尺寸', () {
    expect(
      CanvasNode.resolveAspectRatio(width: 832, height: 1216, fallback: 1),
      closeTo(832 / 1216, 1e-9),
    );
    // 失败快照常见：宽高为 0 或缺省，必须退回兜底比例而不是 0 或 NaN
    expect(
      CanvasNode.resolveAspectRatio(width: 0, height: 0, fallback: 1.5),
      1.5,
    );
    expect(CanvasNode.resolveAspectRatio(fallback: 2), 2);
    expect(CanvasNode.resolveAspectRatio(), 1);
    expect(CanvasNode.resolveAspectRatio(fallback: double.nan), 1);
  });

  group('多画布管理', () {
    test('新建画布后追加并切换过去', () async {
      final controller = await ready();
      final firstId = currentDocument().activeBoardId;

      final secondId = await controller.createBoard('场景');

      final document = currentDocument();
      expect(document.boards, hasLength(2));
      expect(document.activeBoardId, secondId);
      expect(document.boardById(firstId), isNotNull);
      expect(document.activeBoard!.name, '场景');
    });

    test('新画布是空的，节点不会带到其它画布', () async {
      final controller = await ready();
      await controller.addNoteNode();
      expect(currentDocument().nodes, hasLength(1));

      await controller.createBoard('场景');

      expect(currentDocument().nodes, isEmpty);
    });

    test('切回原画布后原有节点还在', () async {
      final controller = await ready();
      final firstId = currentDocument().activeBoardId;
      await controller.addNoteNode();
      await controller.createBoard('场景');
      await controller.selectBoard(firstId);

      expect(currentDocument().activeBoardId, firstId);
      expect(currentDocument().nodes, hasLength(1));
    });

    test('重命名只改名称，空白名称被忽略', () async {
      final controller = await ready();
      final id = currentDocument().activeBoardId;

      await controller.renameBoard(id, '  角色设定  ');
      expect(currentDocument().boardById(id)!.name, '角色设定');

      await controller.renameBoard(id, '   ');
      expect(currentDocument().boardById(id)!.name, '角色设定');
    });

    test('删除当前画布后切到剩下的第一块', () async {
      final controller = await ready();
      final firstId = currentDocument().activeBoardId;
      final secondId = await controller.createBoard('场景');

      await controller.deleteBoard(secondId);

      final document = currentDocument();
      expect(document.boards, hasLength(1));
      expect(document.activeBoardId, firstId);
    });

    test('最后一块画布不可删除', () async {
      final controller = await ready();
      final id = currentDocument().activeBoardId;

      await controller.deleteBoard(id);

      expect(currentDocument().boards, hasLength(1));
      expect(currentDocument().activeBoardId, id);
    });

    test('切换画布会写入文档并落盘', () async {
      final controller = await ready();
      final secondId = await controller.createBoard('场景');
      await controller.flush();
      expect(repository._document.activeBoardId, secondId);
      expect(repository._document.boards, hasLength(2));
    });
  });
}
