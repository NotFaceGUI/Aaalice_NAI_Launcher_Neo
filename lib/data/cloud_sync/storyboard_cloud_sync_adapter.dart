import '../models/storyboard/storyboard_document.dart';
import 'cloud_sync_data_adapter.dart';
import 'portable_sync_record.dart';

/// 分镜文档的云同步。
///
/// 只同步图库根目录下的 sidecar JSON（版面、提示词与相对路径引用），
/// 不读取也不上传任何图片本体。文档按整篇读写，恢复时覆盖本地文档。
Map<String, dynamic> _portableMap(Object? value) {
  if (value is! Map) {
    throw const CloudSyncPreflightException('Expected a JSON object');
  }
  return value.map((key, item) {
    if (key is! String) {
      throw const CloudSyncPreflightException(
        'Portable object keys must be strings',
      );
    }
    return MapEntry(key, item);
  });
}

class StoryboardDocumentCloudSyncAdapter
    extends ValidatingCloudSyncDataAdapter {
  StoryboardDocumentCloudSyncAdapter({
    required Future<StoryboardDocument?> Function() loadDocument,
    required Future<bool> Function(StoryboardDocument document) saveDocument,
    required bool include,
  }) : _loadDocument = loadDocument,
       _saveDocument = saveDocument,
       _include = include;

  final Future<StoryboardDocument?> Function() _loadDocument;
  final Future<bool> Function(StoryboardDocument document) _saveDocument;
  final bool _include;

  /// 单篇文档的页数上限；分镜文档是轻量引用集合，正常远小于此值。
  static const int maxPages = 128;

  @override
  String get id => 'storyboard-document';

  @override
  Set<String> get allowedKinds => const {'document'};

  @override
  Stream<PortableSyncRecord> exportRecords() async* {
    if (!_include) return;
    final document = await _loadDocument();
    if (document == null) return;
    if (document.pages.length > maxPages) {
      throw const CloudSyncPreflightException(
        'Storyboard document has too many pages',
      );
    }
    yield PortableSyncRecord(
      adapterId: id,
      id: 'document',
      kind: 'document',
      data: document.toJson(),
    );
  }

  @override
  void validateRecord(PortableSyncRecord record) {
    if (record.deleted) {
      if (record.id != 'document' ||
          record.resource != null ||
          record.data.isNotEmpty) {
        throw const CloudSyncPreflightException(
          'Invalid storyboard tombstone',
        );
      }
      return;
    }
    final pages = record.data['pages'];
    if (record.id != 'document' ||
        record.data['version'] is! num ||
        pages is! List ||
        pages.isEmpty ||
        pages.length > maxPages) {
      throw const CloudSyncPreflightException('Invalid storyboard document');
    }
    // 结构必须真的可解析；fromJson 拒绝未知新版本，防止旧客户端
    // 把看不懂的新文档覆盖到本地。
    if (StoryboardDocument.fromJson(_portableMap(record.data)) == null) {
      throw const CloudSyncPreflightException(
        'Storyboard document is not parseable',
      );
    }
  }

  @override
  Future<void> apply(List<PortableSyncRecord> records) async {
    for (final record in records) {
      // 删除墓碑不清空本地排版：分镜文档没有"删掉"的用户入口，
      // 静默清空用户手排的版面比不同步更糟。
      if (record.deleted || !_include) continue;
      final document = StoryboardDocument.fromJson(_portableMap(record.data));
      if (document == null) continue;
      await _saveDocument(document);
    }
  }
}
