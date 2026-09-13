import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/canvas/canvas_board.dart';
import 'package:nai_launcher/data/models/canvas/canvas_document.dart';
import 'package:nai_launcher/data/models/canvas/canvas_edge.dart';
import 'package:nai_launcher/data/models/canvas/canvas_node.dart';
import 'package:nai_launcher/data/models/canvas/canvas_node_kind.dart';
import 'package:nai_launcher/data/models/canvas/canvas_node_params.dart';

void main() {
  final stamp = DateTime.fromMillisecondsSinceEpoch(1700000000000);

  CanvasNode node({
    required String id,
    required CanvasNodeKind kind,
    double x = 0,
    double y = 0,
    double width = 200,
    double height = 120,
    int zOrder = 0,
    String? imagePath,
    int? seed,
    CanvasNodeParams? params,
    String? note,
  }) {
    return CanvasNode(
      id: id,
      kind: kind,
      x: x,
      y: y,
      width: width,
      height: height,
      zOrder: zOrder,
      imageRelativePath: imagePath,
      seed: seed,
      params: params,
      noteText: note,
      createdAt: stamp,
      updatedAt: stamp,
    );
  }

  CanvasEdge edge({
    required String id,
    required String from,
    required String to,
    String? label,
  }) {
    return CanvasEdge(
      id: id,
      fromNodeId: from,
      toNodeId: to,
      label: label,
      createdAt: stamp,
      updatedAt: stamp,
    );
  }

  CanvasBoard board({
    required String id,
    required String name,
    List<CanvasNode> nodes = const [],
    List<CanvasEdge> edges = const [],
  }) {
    return CanvasBoard(
      id: id,
      name: name,
      nodes: nodes,
      edges: edges,
      createdAt: stamp,
      updatedAt: stamp,
    );
  }

  group('多画布文档', () {
    test('JSON 往返保留全部画布与当前画布', () {
      final document = CanvasDocument(
        boards: [
          board(
            id: 'board-1',
            name: '角色设定',
            nodes: [
              node(
                id: 'image-1',
                kind: CanvasNodeKind.image,
                imagePath: '2024-01-01/120000-1234.png',
                seed: 1234,
                params: const CanvasNodeParams(prompt: 'a cat'),
              ),
            ],
          ),
          board(
            id: 'board-2',
            name: '场景',
            nodes: [node(id: 'note-1', kind: CanvasNodeKind.note, note: '草稿')],
            edges: const [],
          ),
        ],
        activeBoardId: 'board-2',
      );

      final restored = CanvasDocument.fromJson(document.toJson());
      expect(restored, isNotNull);
      expect(restored!.boards, hasLength(2));
      expect(restored.activeBoardId, 'board-2');
      expect(restored.activeBoard!.name, '场景');
      expect(restored.nodes.single.noteText, '草稿');
    });

    test('当前画布 id 失效时退回第一块', () {
      final restored = CanvasDocument.fromJson({
        'version': 2,
        'activeBoardId': 'missing',
        'boards': [
          {'id': 'b1', 'name': 'A', 'nodes': <Object>[], 'edges': <Object>[]},
          {'id': 'b2', 'name': 'B', 'nodes': <Object>[], 'edges': <Object>[]},
        ],
      });
      expect(restored!.activeBoardId, 'b1');
    });

    test('丢弃重复 id 的画布，无有效画布时返回 null', () {
      expect(
        CanvasDocument.fromJson({
          'version': 2,
          'boards': [
            {'id': 'b1', 'name': 'A', 'nodes': <Object>[], 'edges': <Object>[]},
            {
              'id': 'b1',
              'name': 'A2',
              'nodes': <Object>[],
              'edges': <Object>[],
            },
          ],
        })!.boards,
        hasLength(1),
      );
      expect(
        CanvasDocument.fromJson({'version': 2, 'boards': <Object>[]}),
        isNull,
      );
    });

    test('节点与连线按画布隔离', () {
      final document = CanvasDocument(
        boards: [
          board(
            id: 'b1',
            name: 'A',
            nodes: [node(id: 'n1', kind: CanvasNodeKind.note)],
          ),
          board(
            id: 'b2',
            name: 'B',
            nodes: [node(id: 'n2', kind: CanvasNodeKind.note)],
          ),
        ],
        activeBoardId: 'b1',
      );

      expect(document.nodes.single.id, 'n1');
      expect(document.nodeById('n2'), isNull);

      final switched = document.copyWith(activeBoardId: 'b2');
      expect(switched.nodes.single.id, 'n2');
      expect(switched.nodeById('n1'), isNull);
    });

    test('withBoard 替换同 id 画布而不改变顺序', () {
      final document = CanvasDocument(
        boards: [
          board(id: 'b1', name: 'A'),
          board(id: 'b2', name: 'B'),
        ],
        activeBoardId: 'b2',
      );
      final updated = document.withBoard(board(id: 'b1', name: 'A2'));

      expect(updated.boards.map((item) => item.id), ['b1', 'b2']);
      expect(updated.boardById('b1')!.name, 'A2');
      expect(updated.activeBoardId, 'b2');
    });
  });

  group('v1 迁移', () {
    test('单画布文件迁移成一块未命名画布', () {
      final migrated = CanvasDocument.fromJson({
        'version': 1,
        'nodes': [
          {
            'id': 'legacy-node',
            'kind': 2,
            'x': 10,
            'y': 20,
            'width': 200,
            'height': 120,
            'note': '旧数据',
          },
        ],
        'edges': <Object>[],
      });

      expect(migrated, isNotNull);
      expect(migrated!.boards, hasLength(1));
      expect(migrated.activeBoard!.name, isEmpty);
      expect(migrated.nodes.single.noteText, '旧数据');
      expect(migrated.nodes.single.x, 10);
    });

    test('迁移后写出的版本号是当前版本', () {
      final migrated = CanvasDocument.fromJson({
        'version': 1,
        'nodes': <Object>[],
        'edges': <Object>[],
      })!;
      expect(migrated.toJson()['version'], CanvasDocument.currentVersion);
    });
  });

  group('容错解析', () {
    test('丢弃缺少 id 的条目与重复 id', () {
      final restored = CanvasDocument.fromJson({
        'version': 2,
        'boards': [
          {
            'id': 'b1',
            'name': 'A',
            'nodes': [
              {'kind': 2, 'x': 0, 'y': 0, 'width': 200, 'height': 120},
              {
                'id': 'dup',
                'kind': 2,
                'x': 0,
                'y': 0,
                'width': 200,
                'height': 120,
              },
              {
                'id': 'dup',
                'kind': 2,
                'x': 10,
                'y': 0,
                'width': 200,
                'height': 120,
              },
            ],
            'edges': <Object>[],
          },
        ],
      });
      expect(restored!.nodes, hasLength(1));
      expect(restored.nodes.single.x, 0);
    });

    test('丢弃引用缺失节点的连线与自连', () {
      final restored = CanvasDocument.fromJson({
        'version': 2,
        'boards': [
          {
            'id': 'b1',
            'name': 'A',
            'nodes': [
              {
                'id': 'a',
                'kind': 2,
                'x': 0,
                'y': 0,
                'width': 200,
                'height': 120,
              },
            ],
            'edges': [
              {'id': 'e1', 'from': 'a', 'to': 'missing'},
              {'id': 'e2', 'from': 'a', 'to': 'a'},
            ],
          },
        ],
      });
      expect(restored!.edges, isEmpty);
    });

    test('超出范围或非法的尺寸被夹到可用区间', () {
      final restored = CanvasDocument.fromJson({
        'version': 2,
        'boards': [
          {
            'id': 'b1',
            'name': 'A',
            'nodes': [
              {
                'id': 'a',
                'kind': 2,
                'x': 0,
                'y': 0,
                'width': -5,
                'height': 99999,
              },
            ],
            'edges': <Object>[],
          },
        ],
      });
      final parsed = restored!.nodes.single;
      expect(parsed.width, CanvasNode.minNodeWidth);
      expect(parsed.height, CanvasNode.maxNodeHeight);
    });

    test('未知版本返回 null，交给调用方决定是否覆盖', () {
      expect(
        CanvasDocument.fromJson({
          'version': CanvasDocument.currentVersion + 1,
          'boards': <Object>[],
        }),
        isNull,
      );
      expect(CanvasDocument.fromJson({'boards': <Object>[]}), isNull);
    });

    test('缺少字段的 v2 文档视为无有效画布', () {
      expect(CanvasDocument.fromJson({'version': 2}), isNull);
    });
  });

  group('落点计算', () {
    test('首选位置空闲时直接使用', () {
      final position = board(
        id: 'b',
        name: 'A',
      ).findFreePosition(width: 100, height: 100, nearX: 40, nearY: 50);
      expect(position.x, 40);
      expect(position.y, 50);
    });

    test('首选位置被占用时向外找到一个不重叠的位置', () {
      final target = board(
        id: 'b',
        name: 'A',
        nodes: [node(id: 'a', kind: CanvasNodeKind.note, x: 0, y: 0)],
      );
      final position = target.findFreePosition(
        width: 200,
        height: 120,
        nearX: 0,
        nearY: 0,
      );
      expect(
        _overlaps(
          left: position.x,
          top: position.y,
          width: 200,
          height: 120,
          otherLeft: 0,
          otherTop: 0,
          otherWidth: 200,
          otherHeight: 120,
        ),
        isFalse,
      );
    });

    test('同尺寸节点连续落位互不重叠', () {
      var target = board(id: 'b', name: 'A');
      final placed = <({double x, double y})>[];
      for (var i = 0; i < 6; i++) {
        final position = target.findFreePosition(
          width: 200,
          height: 120,
          nearX: 0,
          nearY: 0,
        );
        placed.add(position);
        target = target.copyWith(
          nodes: [
            ...target.nodes,
            node(
              id: 'n$i',
              kind: CanvasNodeKind.note,
              x: position.x,
              y: position.y,
            ),
          ],
        );
      }
      for (var i = 0; i < placed.length; i++) {
        for (var j = i + 1; j < placed.length; j++) {
          expect(
            _overlaps(
              left: placed[i].x,
              top: placed[i].y,
              width: 200,
              height: 120,
              otherLeft: placed[j].x,
              otherTop: placed[j].y,
              otherWidth: 200,
              otherHeight: 120,
            ),
            isFalse,
            reason: '第 $i 与第 $j 个落点重叠',
          );
        }
      }
    });
  });
}

bool _overlaps({
  required double left,
  required double top,
  required double width,
  required double height,
  required double otherLeft,
  required double otherTop,
  required double otherWidth,
  required double otherHeight,
}) {
  const gap = CanvasBoard.placementGap;
  return left < otherLeft + otherWidth + gap &&
      left + width > otherLeft - gap &&
      top < otherTop + otherHeight + gap &&
      top + height > otherTop - gap;
}
