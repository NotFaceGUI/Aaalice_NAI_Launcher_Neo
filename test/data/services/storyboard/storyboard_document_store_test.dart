import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/storyboard/storyboard_document.dart';
import 'package:nai_launcher/data/models/storyboard/storyboard_page.dart';
import 'package:nai_launcher/data/models/storyboard/storyboard_page_background.dart';
import 'package:nai_launcher/data/models/storyboard/storyboard_panel.dart';
import 'package:nai_launcher/data/models/storyboard/storyboard_panel_shape.dart';
import 'package:nai_launcher/data/services/storyboard/storyboard_document_store.dart';

void main() {
  late Directory root;
  final store = StoryboardDocumentStore();

  setUp(() async {
    root = await Directory.systemTemp.createTemp('storyboard-store-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  File documentFile() => File(
    '${root.path}${Platform.pathSeparator}${StoryboardDocumentStore.fileName}',
  );
  File backupFile() => File('${documentFile().path}.bak');
  File temporaryFile() => File('${documentFile().path}.tmp');

  StoryboardDocument buildDocument({String name = 'first', String prompt = 'a'}) {
    final now = DateTime.fromMillisecondsSinceEpoch(1700000000000);
    return StoryboardDocument.singlePage(
      StoryboardPage(
        id: 'page-1',
        name: name,
        width: 2480,
        height: 3508,
        background: const StoryboardPageBackground(),
        panels: [
          StoryboardPanel(
            id: 'panel-1',
            order: 1,
            shape: StoryboardPanelShape.rect,
            x: 96,
            y: 96,
            width: 1120,
            height: 1480,
            prompt: prompt,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  test('图库目录下没有分镜文档时返回 null', () async {
    expect(await store.load(root.path), isNull);
  });

  test('文档经 sidecar 文件完整往返', () async {
    expect(await store.save(root.path, buildDocument()), isTrue);

    final loaded = await store.load(root.path);
    expect(loaded, isNotNull);
    expect(loaded!.activePageId, 'page-1');
    final page = loaded.activePage!;
    expect(page.name, 'first');
    expect(page.width, 2480);
    expect(page.panels.single.prompt, 'a');
  });

  test('文件使用带缩进的版本化 JSON', () async {
    await store.save(root.path, buildDocument());
    final decoded = jsonDecode(await documentFile().readAsString()) as Map;

    expect(decoded['version'], StoryboardDocument.currentVersion);
    expect(decoded['activePageId'], 'page-1');
    expect(decoded['pages'], isA<List>());
  });

  test('写入后不遗留临时文件与备份', () async {
    await store.save(root.path, buildDocument());
    expect(await temporaryFile().exists(), isFalse);
    expect(await backupFile().exists(), isFalse);
  });

  test('重复写入以最后一次为准', () async {
    await store.save(root.path, buildDocument(name: 'first'));
    await store.save(root.path, buildDocument(name: 'second'));

    final loaded = await store.load(root.path);
    expect(loaded!.activePage!.name, 'second');
  });

  test('主文件损坏时从备份恢复', () async {
    await store.save(root.path, buildDocument(name: 'recoverable'));
    // 模拟"备份已落盘、主文件写入中断"的状态。
    await documentFile().copy(backupFile().path);
    await documentFile().writeAsString('{ 这不是合法 JSON');

    final loaded = await store.load(root.path);
    expect(loaded, isNotNull);
    expect(loaded!.activePage!.name, 'recoverable');
  });

  test('主文件损坏且没有备份时返回 null 而不是抛异常', () async {
    await documentFile().writeAsString('{ 坏文件');
    expect(await store.load(root.path), isNull);
  });

  test('不支持的版本返回 null', () async {
    final json = buildDocument().toJson();
    json['version'] = StoryboardDocument.currentVersion + 1;
    await documentFile().writeAsString(jsonEncode(json));

    expect(await store.load(root.path), isNull);
  });

  test('主文件缺失但备份存在时完成中断的提交', () async {
    await store.save(root.path, buildDocument(name: 'interrupted'));
    await documentFile().rename(backupFile().path);

    final loaded = await store.load(root.path);
    expect(loaded, isNotNull);
    expect(loaded!.activePage!.name, 'interrupted');
    // 恢复后应重新落成主文件。
    expect(await documentFile().exists(), isTrue);
    expect(await backupFile().exists(), isFalse);
  });

  test('内容为数组或标量时返回 null', () async {
    await documentFile().writeAsString('[1, 2, 3]');
    expect(await store.load(root.path), isNull);
  });
}
