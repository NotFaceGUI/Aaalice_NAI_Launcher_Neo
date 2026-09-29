import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/cloud_sync/content_selection.dart';
import 'package:nai_launcher/data/cloud_sync/cloud_sync_data_adapter.dart';
import 'package:nai_launcher/data/cloud_sync/portable_sync_record.dart';
import 'package:nai_launcher/data/cloud_sync/storyboard_cloud_sync_adapter.dart';
import 'package:nai_launcher/data/models/storyboard/storyboard_document.dart';
import 'package:nai_launcher/data/models/storyboard/storyboard_page.dart';

void main() {
  group('CloudSyncContentSelection v3', () {
    test('encode 与 decode 往返一致', () {
      const selection = CloudSyncContentSelection(
        includeVibes: true,
        selectedSkillIds: {'workspace:skill-a'},
      );
      final decoded = CloudSyncContentSelection.decode(selection.encode());
      expect(decoded.includeStoryboard, selection.includeStoryboard);
      expect(decoded.includeVibes, true);
      expect(decoded.selectedSkillIds, {'workspace:skill-a'});
    });

    test('v2 快照可以解码，includeStoryboard 跟随新默认', () {
      const v2 = '''
      {
        "version": 2,
        "includeSettings": true,
        "includePromptsAndTags": true,
        "includeTagThumbnails": false,
        "includeOnlineGallerySettings": true,
        "includeOnlineGalleryFavorites": false,
        "includeGalleryAlbums": true,
        "includeAgentSystemPrompt": true,
        "includeSkills": true,
        "includeVibes": false,
        "includePreciseReferences": false,
        "selectedSkillIds": []
      }
      ''';
      final decoded = CloudSyncContentSelection.decode(v2);
      expect(decoded.includeSettings, true);
      expect(decoded.includeTagThumbnails, false);
      expect(decoded.includeOnlineGalleryFavorites, false);
      expect(
        decoded.includeStoryboard,
        const CloudSyncContentSelection().includeStoryboard,
      );
    });

    test('v1 快照仍可解码', () {
      const v1 = '''
      {
        "version": 1,
        "includeAgentSystemPrompt": true,
        "includeSkills": false,
        "selectedSkillIds": []
      }
      ''';
      final decoded = CloudSyncContentSelection.decode(v1);
      expect(decoded.includeAgentSystemPrompt, true);
      expect(decoded.includeSkills, false);
    });

    test('未知字段被拒绝', () {
      const bad = '''
      {
        "version": 3,
        "includeSettings": true,
        "includePromptsAndTags": true,
        "includeTagThumbnails": true,
        "includeOnlineGallerySettings": true,
        "includeOnlineGalleryFavorites": true,
        "includeGalleryAlbums": true,
        "includeStoryboard": true,
        "includeAgentSystemPrompt": true,
        "includeSkills": true,
        "includeVibes": false,
        "includePreciseReferences": false,
        "selectedSkillIds": [],
        "surprise": true
      }
      ''';
      expect(
        () => CloudSyncContentSelection.decode(bad),
        throwsFormatException,
      );
    });
  });

  group('StoryboardDocumentCloudSyncAdapter', () {
    StoryboardDocument document() => StoryboardDocument.singlePage(
      StoryboardPage.create(id: 'page-1', width: 1024, height: 1536),
    );

    test('export 产出单条 document 记录并通过 preflight', () async {
      final adapter = StoryboardDocumentCloudSyncAdapter(
        loadDocument: () async => document(),
        saveDocument: (_) async => true,
        include: true,
      );
      final records = await adapter.exportRecords().toList();
      expect(records, hasLength(1));
      expect(records.single.id, 'document');
      expect(records.single.kind, 'document');
      await adapter.preflight(records);
    });

    test('未勾选时不出记录', () async {
      final adapter = StoryboardDocumentCloudSyncAdapter(
        loadDocument: () async => document(),
        saveDocument: (_) async => true,
        include: false,
      );
      expect(await adapter.exportRecords().toList(), isEmpty);
    });

    test('被篡改的记录被 preflight 拒绝', () async {
      final adapter = StoryboardDocumentCloudSyncAdapter(
        loadDocument: () async => null,
        saveDocument: (_) async => true,
        include: true,
      );
      void expectRejected(PortableSyncRecord record) {
        expect(
          () => adapter.validateRecord(record),
          throwsA(isA<CloudSyncPreflightException>()),
        );
      }

      expectRejected(
        PortableSyncRecord(
          adapterId: 'storyboard-document',
          id: 'document',
          kind: 'document',
          data: {'version': 99, 'pages': <Object?>[], 'activePageId': 'x'},
        ),
      );
      expectRejected(
        PortableSyncRecord(
          adapterId: 'storyboard-document',
          id: 'document',
          kind: 'document',
          data: {'version': 1, 'pages': 'not-a-list'},
        ),
      );
      expectRejected(
        PortableSyncRecord(
          adapterId: 'storyboard-document',
          id: 'document',
          kind: 'document',
          data: {
            'version': 1,
            'pages': [
              {'id': 'p'},
            ],
          },
        ),
      );
    });

    test('apply 把文档写回，删除墓碑不清空本地', () async {
      StoryboardDocument? saved;
      final adapter = StoryboardDocumentCloudSyncAdapter(
        loadDocument: () async => null,
        saveDocument: (document) async {
          saved = document;
          return true;
        },
        include: true,
      );
      await adapter.apply([
        PortableSyncRecord(
          adapterId: 'storyboard-document',
          id: 'document',
          kind: 'document',
          data: document().toJson(),
        ),
      ]);
      expect(saved?.activePage?.id, 'page-1');

      await adapter.apply([
        PortableSyncRecord(
          adapterId: 'storyboard-document',
          id: 'document',
          kind: 'document',
          deleted: true,
        ),
      ]);
      expect(saved?.activePage?.id, 'page-1');
    });
  });
}
