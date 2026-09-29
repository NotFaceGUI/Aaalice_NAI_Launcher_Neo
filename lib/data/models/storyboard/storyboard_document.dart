import 'storyboard_page.dart';

/// 分镜文档：全部分镜页与当前正在编辑的页。
///
/// 与无限画布文档同构：按整篇文档读写、只保存相对图库根的轻量引用、
/// 由 `StoryboardDocumentStore` 原子提交到图库根目录下的 sidecar 文件。
class StoryboardDocument {
  /// 文档格式版本。
  static const int currentVersion = 1;

  final List<StoryboardPage> pages;
  final String activePageId;

  const StoryboardDocument({
    required this.pages,
    required this.activePageId,
  });

  /// 由单页构成的文档；新建与测试用。
  factory StoryboardDocument.singlePage(StoryboardPage page) =>
      StoryboardDocument(pages: [page], activePageId: page.id);

  StoryboardPage? get activePage {
    for (final page in pages) {
      if (page.id == activePageId) return page;
    }
    return pages.isEmpty ? null : pages.first;
  }

  StoryboardPage? pageById(String id) {
    for (final page in pages) {
      if (page.id == id) return page;
    }
    return null;
  }

  // ==================== 当前页的便捷读取 ====================

  bool get isEmpty => activePage?.isEmpty ?? true;

  /// 以某一页替换同 id 的页；未找到时追加。
  StoryboardDocument withPage(StoryboardPage page) {
    final next = <StoryboardPage>[];
    var replaced = false;
    for (final existing in pages) {
      if (existing.id == page.id) {
        next.add(page);
        replaced = true;
      } else {
        next.add(existing);
      }
    }
    if (!replaced) next.add(page);
    return StoryboardDocument(pages: next, activePageId: activePageId);
  }

  StoryboardDocument copyWith({
    List<StoryboardPage>? pages,
    String? activePageId,
  }) => StoryboardDocument(
    pages: pages ?? this.pages,
    activePageId: activePageId ?? this.activePageId,
  );

  Map<String, dynamic> toJson() => {
    'version': currentVersion,
    'activePageId': activePageId,
    'pages': [for (final page in pages) page.toJson()],
  };

  /// 解析文档。
  ///
  /// 未知版本或没有任何可用页面时返回 null，由调用方决定是否新建；
  /// 这样调用方不会把"文件损坏"误当成"用户删光了页面"而覆盖原文件。
  static StoryboardDocument? fromJson(Object? value) {
    if (value is! Map) return null;
    final json = Map<String, dynamic>.from(value);

    final version = json['version'];
    if (version is! num || version > currentVersion) return null;

    final pages = <StoryboardPage>[];
    final seenIds = <String>{};
    final rawPages = json['pages'];
    if (rawPages is List) {
      for (final item in rawPages) {
        final page = StoryboardPage.fromJson(item);
        if (page == null || !seenIds.add(page.id)) continue;
        pages.add(page);
      }
    }
    if (pages.isEmpty) return null;

    final rawActive = json['activePageId'];
    final activePageId = rawActive is String && seenIds.contains(rawActive)
        ? rawActive
        : pages.first.id;

    return StoryboardDocument(pages: pages, activePageId: activePageId);
  }
}
