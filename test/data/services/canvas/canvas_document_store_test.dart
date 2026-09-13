import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/canvas/canvas_board.dart';
import 'package:nai_launcher/data/models/canvas/canvas_document.dart';
import 'package:nai_launcher/data/models/canvas/canvas_node.dart';
import 'package:nai_launcher/data/models/canvas/canvas_node_kind.dart';
import 'package:nai_launcher/data/services/canvas/canvas_document_store.dart';

void main() {
  late Directory root;
  final store = CanvasDocumentStore();

  setUp(() async {
    root = await Directory.systemTemp.createTemp('canvas-store-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  File documentFile() => File(
    '${root.path}${Platform.pathSeparator}${CanvasDocumentStore.fileName}',
  );
  File backupFile() => File('${documentFile().path}.bak');

  CanvasDocument buildDocument({String note = 'first'}) {
    final now = DateTime.fromMillisecondsSinceEpoch(1700000000000);
    final node = CanvasNode(
      id: 'node-1',
      kind: CanvasNodeKind.note,
      x: 12,
      y: 34,
      width: 200,
      height: 120,
      noteText: note,
      createdAt: now,
      updatedAt: now,
    );
    return CanvasDocument.singleBoard(nodes: [node], edges: const []);
  }

  test('returns null when the gallery folder has no canvas yet', () async {
    expect(await store.load(root.path), isNull);
  });

  test('round-trips the document through the sidecar file', () async {
    expect(await store.save(root.path, buildDocument()), isTrue);

    final loaded = await store.load(root.path);
    expect(loaded, isNotNull);
    expect(loaded!.nodes, hasLength(1));
    expect(loaded.nodes.single.noteText, 'first');
    expect(loaded.nodes.single.x, 12);
    expect(loaded.nodes.single.kind, CanvasNodeKind.note);
  });

  test('overwrites the previous canvas on the next save', () async {
    await store.save(root.path, buildDocument(note: 'first'));
    await store.save(root.path, buildDocument(note: 'second'));

    final loaded = await store.load(root.path);
    expect(loaded!.nodes.single.noteText, 'second');
    // 成功提交后不留下备份
    expect(await backupFile().exists(), isFalse);
  });

  test('recovers from the backup when the primary file is corrupt', () async {
    await store.save(root.path, buildDocument(note: 'recovered'));
    await backupFile().writeAsString(
      await documentFile().readAsString(),
      flush: true,
    );
    await documentFile().writeAsString('{ this is not json', flush: true);

    final loaded = await store.load(root.path);
    expect(loaded, isNotNull);
    expect(loaded!.nodes.single.noteText, 'recovered');
    // 恢复后主文件被修复，备份被清理
    expect(await backupFile().exists(), isFalse);
    expect(await store.load(root.path), isNotNull);
  });

  test('ignores a document written by a newer app version', () async {
    await documentFile().writeAsString(
      jsonEncode({'version': CanvasDocument.currentVersion + 1, 'nodes': []}),
      flush: true,
    );
    expect(await store.load(root.path), isNull);
  });

  test('keeps an empty canvas as a valid document', () async {
    await store.save(root.path, CanvasDocument.singleBoard());
    final loaded = await store.load(root.path);
    expect(loaded, isNotNull);
    expect(loaded!.isEmpty, isTrue);
  });
}
