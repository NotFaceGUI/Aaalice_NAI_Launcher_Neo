import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/utils/storyboard/storyboard_geometry.dart';
import '../../../data/models/storyboard/storyboard_document.dart';
import '../../../data/models/storyboard/storyboard_fit_mode.dart';
import '../../../data/models/storyboard/storyboard_page.dart';
import '../../../data/models/storyboard/storyboard_page_background.dart';
import '../../../data/models/storyboard/storyboard_panel.dart';
import '../../../data/models/storyboard/storyboard_panel_character.dart';
import '../../../data/models/storyboard/storyboard_panel_generation.dart';
import '../../../data/models/storyboard/storyboard_panel_shape.dart';
import '../../../data/models/storyboard/storyboard_panel_status.dart';
import '../../../data/models/storyboard/storyboard_resolution.dart';
import '../../../data/services/gallery/gallery_path_utils.dart';
import '../../../data/services/storyboard/storyboard_repository.dart';
import 'storyboard_history_provider.dart';
import 'storyboard_repository_provider.dart';

/// 批量排版的一个格子：矩形 + 可选多边形顶点（页面像素）。
///
/// [points] 不少于 3 个时创建多边形分镜，[rect] 由顶点的外接框取代；
/// 矩形格子只需要 [rect]。
class StoryboardLayoutCell {
  const StoryboardLayoutCell({required this.rect, this.points = const []});

  final Rect rect;
  final List<Offset> points;
}

/// 分镜文档状态：全部页面与当前页。
///
/// 全部修改先在内存里乐观生效再异步落盘；拖动等高频操作由调用方在手势结束
/// 时才提交，因此这里用一个短防抖把连续修改合并成一次写入。
///
/// 所有修改方法都会先等待首次加载完成，避免文档还没读回来就把内存里的
/// 空文档写回磁盘。
///
/// keepAlive：分镜关闭后仍要保持文档（生成结果回填、Agent 工具都可能在
/// 分镜未打开时写入），生命周期与应用一致。
class StoryboardDocumentController extends AsyncNotifier<StoryboardDocument> {
  /// 连续修改合并成一次写入的等待时间
  static const Duration persistDebounce = Duration(milliseconds: 300);

  late final StoryboardRepository _repository;
  Timer? _persistTimer;

  @override
  Future<StoryboardDocument> build() async {
    _repository = ref.watch(storyboardRepositoryProvider);
    ref.onDispose(() {
      _persistTimer?.cancel();
      _persistTimer = null;
    });
    final loaded = await _repository.load();
    // 首次使用时落下一张空白页：文档始终至少有一页，调用方不必到处判空。
    if (loaded != null) return loaded;
    final page = StoryboardPage.create(id: _newId());
    final document = StoryboardDocument.singlePage(page);
    unawaited(_repository.save(document));
    return document;
  }

  /// 当前文档；首次加载完成前为 null，视图此时显示加载态。
  StoryboardDocument? get document => state.valueOrNull;

  bool get isReady => state.hasValue;

  /// 当前正在编辑的页；未就绪时为 null。
  StoryboardPage? get activePage => document?.activePage;

  /// 立即落盘；关闭分镜或离开页面前调用，避免丢掉防抖窗口内的修改。
  Future<void> flush() async {
    final doc = document;
    if (doc == null) return;
    _persistTimer?.cancel();
    _persistTimer = null;
    await _repository.save(doc);
  }

  // ==================== 撤销与重做 ====================

  /// 在一次手势（拖动、缩放、顶点编辑、拉框）开始前记录快照。
  ///
  /// 拖动过程中会逐帧写入内存文档以获得即时反馈，因此快照必须在手势开始前
  /// 一次性记录，而不是每次写入都记录。
  void beginGesture() {
    final doc = document;
    if (doc == null) return;
    ref.read(storyboardHistoryProvider.notifier).push(doc);
  }

  Future<void> undo() async {
    await future;
    final doc = document;
    if (doc == null) return;
    final previous = ref.read(storyboardHistoryProvider.notifier).undo(doc);
    if (previous == null) return;
    _commit(previous);
  }

  Future<void> redo() async {
    await future;
    final doc = document;
    if (doc == null) return;
    final next = ref.read(storyboardHistoryProvider.notifier).redo(doc);
    if (next == null) return;
    _commit(next);
  }

  // ==================== 页面管理 ====================

  /// 新建一页并切换过去，返回页面 id。
  Future<String> createPage({
    String name = '',
    int width = StoryboardPage.defaultWidth,
    int height = StoryboardPage.defaultHeight,
  }) async {
    await future;
    final doc = document;
    if (doc == null) return '';
    final page = StoryboardPage.create(
      id: _newId(),
      name: name.trim(),
      width: width,
      height: height,
    );
    _commit(doc.copyWith(pages: [...doc.pages, page], activePageId: page.id));
    return page.id;
  }

  Future<void> selectPage(String id) async {
    await future;
    final doc = document;
    if (doc == null || doc.activePageId == id || doc.pageById(id) == null) {
      return;
    }
    _commit(doc.copyWith(activePageId: id));
  }

  Future<void> renamePage(String id, String name) async {
    await future;
    final doc = document;
    final page = doc?.pageById(id);
    final trimmed = name.trim();
    if (doc == null || page == null || trimmed.isEmpty || trimmed == page.name) {
      return;
    }
    _commit(doc.withPage(page.copyWith(name: trimmed)));
  }

  /// 删除一页；至少保留一页，删掉当前页时切到剩下第一页。
  Future<void> deletePage(String id) async {
    await future;
    final doc = document;
    if (doc == null || doc.pages.length <= 1) return;
    final next = [
      for (final page in doc.pages)
        if (page.id != id) page,
    ];
    if (next.length == doc.pages.length) return;
    _commit(
      doc.copyWith(
        pages: next,
        activePageId: doc.activePageId == id ? next.first.id : doc.activePageId,
      ),
    );
  }

  /// 修改当前页的输出分辨率。
  ///
  /// 页面坐标就等于输出像素，改尺寸不会缩放已有分镜，只把落在新范围之外的
  /// 分镜收回页面内——否则导出时它们会被静默裁掉。
  Future<void> setPageSize({required int width, required int height}) async {
    await future;
    final page = activePage;
    if (page == null) return;
    final nextWidth = width.clamp(StoryboardPage.minSide, StoryboardPage.maxSide);
    final nextHeight = height.clamp(
      StoryboardPage.minSide,
      StoryboardPage.maxSide,
    );
    if (nextWidth == page.width && nextHeight == page.height) return;

    final size = Size(nextWidth.toDouble(), nextHeight.toDouble());
    final panels = [
      for (final panel in page.panels)
        _withRect(
          panel,
          StoryboardGeometry.normalizeRect(panel.rect, pageSize: size),
        ),
    ];
    _commit(
      _withActivePage(
        page.copyWith(
          width: nextWidth,
          height: nextHeight,
          panels: panels,
          updatedAt: DateTime.now(),
        ),
      ),
    );
  }

  Future<void> setBackground(StoryboardPageBackground background) async {
    await future;
    final page = activePage;
    if (page == null) return;
    _commit(
      _withActivePage(
        page.copyWith(background: background, updatedAt: DateTime.now()),
      ),
    );
  }

  Future<void> setBackgroundPrompt(String prompt) async {
    await future;
    final page = activePage;
    if (page == null) return;
    final trimmed = prompt.trim();
    if (page.background.prompt == trimmed) return;
    _commit(
      _withActivePage(
        page.copyWith(
          background: page.background.copyWith(prompt: trimmed),
          updatedAt: DateTime.now(),
        ),
      ),
    );
  }

  Future<void> setBackgroundSeed(int? seed) async {
    await future;
    final page = activePage;
    if (page == null) return;
    _commit(
      _withActivePage(
        page.copyWith(
          background: seed == null
              ? page.background.copyWith(clearSeed: true)
              : page.background.copyWith(seed: seed),
          updatedAt: DateTime.now(),
        ),
      ),
    );
  }

  /// 记录一张背景图并切换为图片背景。
  Future<void> addBackgroundImage(String relativePath) async {
    await future;
    final page = activePage;
    if (page == null) return;
    if (!isValidGalleryRelativePath(relativePath)) return;
    final background = page.background;
    final next = <String>[
      ...background.images.where((path) => path != relativePath),
      relativePath,
    ];
    _commit(
      _withActivePage(
        page.copyWith(
          background: background.copyWith(
            kind: StoryboardBackgroundKind.image,
            imagePath: relativePath,
            images: next,
          ),
          updatedAt: DateTime.now(),
        ),
      ),
    );
  }

  // ==================== 分镜增删改 ====================

  /// 在给定矩形处新增一个分镜，返回它的 id。
  Future<String> addPanel(Rect rect, {String prompt = ''}) async {
    await future;
    final page = activePage;
    if (page == null) return '';
    final normalized = StoryboardGeometry.normalizeRect(
      rect,
      pageSize: Size(page.width.toDouble(), page.height.toDouble()),
    );
    final now = DateTime.now();
    final panel = StoryboardPanel(
      id: _newId(),
      order: page.nextOrder,
      zOrder: page.maxZOrder + 1,
      x: normalized.left,
      y: normalized.top,
      width: normalized.width,
      height: normalized.height,
      prompt: prompt,
      createdAt: now,
      updatedAt: now,
    );
    _commit(_withActivePage(page.withPanel(panel, now: now)));
    return panel.id;
  }

  /// 修改页面的排版间距。
  ///
  /// 间距只改"以后怎么排"，不会自动重排已有分镜——已有的版面是用户手工调过的，
  /// 静默改动它比不生效更糟。需要重排时用网格生成器的"替换现有分镜"。
  Future<void> setPageSpacing({
    required double margin,
    required double gutter,
  }) async {
    await future;
    final page = activePage;
    if (page == null) return;
    final limit =
        (page.width < page.height ? page.width : page.height).toDouble() *
        StoryboardPage.maxSpacingRatio;
    final nextMargin = margin.isFinite ? margin.clamp(0.0, limit) : page.margin;
    final nextGutter = gutter.isFinite ? gutter.clamp(0.0, limit) : page.gutter;
    if (nextMargin == page.margin && nextGutter == page.gutter) return;
    _commit(
      _withActivePage(
        page.copyWith(
          margin: nextMargin,
          gutter: nextGutter,
          updatedAt: DateTime.now(),
        ),
      ),
    );
  }

  /// 按行列批量生成等分分镜，顺序为阅读顺序。
  ///
  /// [replace] 为真时先清空现有分镜再排——版面已调乱、想用新间距重来一遍时用。
  /// 返回新增数量；页面容不下所要求的边距与间隔时返回 0，由调用方提示。
  Future<int> applyGrid({
    required int rows,
    required int columns,
    required double margin,
    required double gutter,
    bool replace = false,
  }) async {
    await future;
    final page = activePage;
    if (page == null) return 0;
    final rects = StoryboardGeometry.buildGridRects(
      pageSize: Size(page.width.toDouble(), page.height.toDouble()),
      rows: rows,
      columns: columns,
      margin: margin,
      gutter: gutter,
    );
    if (rects.isEmpty) return 0;

    final now = DateTime.now();
    // 替换模式重新编号，追加模式接在现有分镜之后。
    var order = replace ? 1 : page.nextOrder;
    var zOrder = replace ? 0 : page.maxZOrder + 1;
    final created = <StoryboardPanel>[];
    for (final rect in rects) {
      if (created.length >= StoryboardPage.maxPanels) break;
      created.add(
        StoryboardPanel(
          id: _newId(),
          order: order++,
          zOrder: zOrder++,
          x: rect.left,
          y: rect.top,
          width: rect.width,
          height: rect.height,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    if (created.isEmpty) return 0;

    // 一次提交同时更新间距与分镜，账号里不留"间距已改但还按旧间距排"的中间态。
    _commit(
      _withActivePage(
        page.copyWith(
          margin: margin,
          gutter: gutter,
          panels: replace ? created : [...page.panels, ...created],
          updatedAt: now,
        ),
      ),
    );
    return created.length;
  }

  /// 按显式矩形批量生成分镜；预设版式（含通栏混排等不规则排布）走这里。
  ///
  /// [rects] 是页面像素矩形，调用方负责间距与阅读顺序，这里只做归一化、
  /// 最小尺寸过滤、编号与一次提交。[replace] 为真时先清空现有分镜。
  /// 返回新增数量。
  /// 按格子批量生成分镜；预设版式与 Agent 建格都走这里。
  ///
  /// 矩形格子按页面归一化并过滤过小尺寸；带顶点（≥3）的格子创建多边形，
  /// 外接框取顶点包围盒。返回新增数量；[replace] 为真时先清空现有分镜。
  Future<int> applyPanelLayout(
    List<StoryboardLayoutCell> cells, {
    bool replace = false,
  }) async {
    await future;
    final page = activePage;
    if (page == null) return 0;
    final pageSize = Size(page.width.toDouble(), page.height.toDouble());
    final maxX = page.width.toDouble();
    final maxY = page.height.toDouble();
    final now = DateTime.now();
    var order = replace ? 1 : page.nextOrder;
    var zOrder = replace ? 0 : page.maxZOrder + 1;
    final created = <StoryboardPanel>[];
    for (final cell in cells) {
      if (created.length >= StoryboardPage.maxPanels) break;
      if (cell.points.length >= StoryboardPanel.minPolygonPoints) {
        final clamped = [
          for (final point in cell.points)
            Offset(point.dx.clamp(0.0, maxX), point.dy.clamp(0.0, maxY)),
        ];
        final fitted = StoryboardGeometry.fitPolygonToPixelBounds(clamped);
        if (fitted.rect.width < StoryboardPanel.minSide ||
            fitted.rect.height < StoryboardPanel.minSide) {
          continue;
        }
        created.add(
          StoryboardPanel(
            id: _newId(),
            order: order++,
            zOrder: zOrder++,
            x: fitted.rect.left,
            y: fitted.rect.top,
            width: fitted.rect.width,
            height: fitted.rect.height,
            shape: StoryboardPanelShape.polygon,
            points: fitted.points,
            createdAt: now,
            updatedAt: now,
          ),
        );
        continue;
      }
      final normalized = StoryboardGeometry.normalizeRect(
        cell.rect,
        pageSize: pageSize,
      );
      if (normalized.width < StoryboardPanel.minSide ||
          normalized.height < StoryboardPanel.minSide) {
        continue;
      }
      created.add(
        StoryboardPanel(
          id: _newId(),
          order: order++,
          zOrder: zOrder++,
          x: normalized.left,
          y: normalized.top,
          width: normalized.width,
          height: normalized.height,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    if (created.isEmpty) return 0;
    _commit(
      _withActivePage(
        page.copyWith(
          panels: replace ? created : [...page.panels, ...created],
          updatedAt: now,
        ),
      ),
    );
    return created.length;
  }

  /// 只改版面矩形；多边形顶点按归一化存储，因此形状自动跟随。
  Future<void> setPanelRect(String id, Rect rect) async {
    await _updatePanel(id, (panel, page) {
      final normalized = StoryboardGeometry.normalizeRect(
        rect,
        pageSize: Size(page.width.toDouble(), page.height.toDouble()),
      );
      if (StoryboardGeometry.rectsNearlyEqual(normalized, panel.rect)) {
        return panel;
      }
      return _withRect(panel, normalized);
    });
  }

  /// 替换分镜的多边形顶点；顶点不足三个时退回矩形。
  ///
  /// 顶点先钳制到页面内再反推外接矩形：矩形是被归一化顶点的参照系，若矩形
  /// 被页面边界二次收敛而顶点没跟着收敛，形状就会和矩形脱节。
  Future<void> setPanelPolygon(String id, List<Offset> pixelPoints) async {
    await _updatePanel(id, (panel, page) {
      if (pixelPoints.length < StoryboardPanel.minPolygonPoints) {
        return panel.copyWith(
          shape: StoryboardPanelShape.rect,
          points: const [],
        );
      }
      final maxX = page.width.toDouble();
      final maxY = page.height.toDouble();
      final clamped = [
        for (final point in pixelPoints)
          Offset(point.dx.clamp(0.0, maxX), point.dy.clamp(0.0, maxY)),
      ];
      final fitted = StoryboardGeometry.fitPolygonToPixelBounds(clamped);
      return _withRect(
        panel.copyWith(
          shape: StoryboardPanelShape.polygon,
          points: fitted.points,
        ),
        fitted.rect,
      );
    });
  }

  /// 把分镜改回矩形。
  Future<void> resetPanelShape(String id) async {
    await _updatePanel(
      id,
      (panel, page) => panel.copyWith(
        shape: StoryboardPanelShape.rect,
        points: const [],
      ),
    );
  }

  /// 在多边形的第 [index] 个顶点之前插入一个新顶点。
  Future<void> insertPanelVertex(
    String id,
    int index,
    Offset pixelPoint,
  ) async {
    await future;
    final page = activePage;
    final panel = page?.panelById(id);
    if (page == null || panel == null) return;

    final points = List<Offset>.of(panel.effectivePoints);
    if (points.length >= StoryboardPanel.maxPolygonPoints) return;
    final insertAt = index.clamp(0, points.length);
    points.insert(insertAt, Offset.zero);
    await setPanelPolygon(
      id,
      _withReplacedPoint(panel, points, insertAt, pixelPoint),
    );
  }

  /// 删除多边形的第 [index] 个顶点；少于三个顶点时保持不变。
  Future<void> removePanelVertex(String id, int index) async {
    await future;
    final page = activePage;
    final panel = page?.panelById(id);
    if (page == null || panel == null) return;

    final points = List<Offset>.of(panel.effectivePoints);
    if (points.length <= StoryboardPanel.minPolygonPoints) return;
    if (index < 0 || index >= points.length) return;
    points.removeAt(index);
    await setPanelPolygon(
      id,
      StoryboardGeometry.toPixelPoints(points, panel.rect),
    );
  }

  /// 把列表里第 [index] 项换成给定的页面像素点，其余项按当前矩形还原。
  List<Offset> _withReplacedPoint(
    StoryboardPanel panel,
    List<Offset> normalizedPoints,
    int index,
    Offset pixelPoint,
  ) {
    final pixels = StoryboardGeometry.toPixelPoints(
      normalizedPoints,
      panel.rect,
    );
    pixels[index] = pixelPoint;
    return pixels;
  }

  Future<void> setPanelResolution(
    String id,
    StoryboardResolution resolution,
  ) async {
    await _updatePanel(
      id,
      (panel, page) => panel.copyWith(resolution: resolution),
    );
  }

  Future<void> setPanelFit(String id, StoryboardFitMode fit) async {
    await _updatePanel(id, (panel, page) => panel.copyWith(fit: fit));
  }

  Future<void> setPanelPrompt(String id, String prompt) async {
    await _updatePanel(
      id,
      (panel, page) => panel.copyWith(prompt: prompt.trim()),
    );
  }

  Future<void> setPanelNegativePrompt(String id, String negativePrompt) async {
    final trimmed = negativePrompt.trim();
    await _updatePanel(
      id,
      (panel, page) => trimmed.isEmpty
          ? panel.copyWith(clearNegativePrompt: true)
          : panel.copyWith(negativePrompt: trimmed),
    );
  }

  /// 切换「禁止收费」。
  Future<void> setPageFreeOnly(bool freeOnly) async {
    await future;
    final page = activePage;
    if (page == null || page.freeOnly == freeOnly) return;
    _commit(
      _withActivePage(
        page.copyWith(freeOnly: freeOnly, updatedAt: DateTime.now()),
      ),
    );
  }

  /// 写入分镜的生成配置快照；空快照表示跟随生成页。
  Future<void> setPanelGeneration(
    String id,
    StoryboardPanelGeneration generation,
  ) async {
    await _updatePanel(
      id,
      (panel, page) => panel.copyWith(generation: generation),
    );
  }

  /// 设置分镜专属角色；传空列表即回到"继承生成页角色"。
  Future<void> setPanelCharacters(
    String id,
    List<StoryboardPanelCharacter> characters,
  ) async {
    final limited = characters.length > StoryboardPanel.maxCharacters
        ? characters.sublist(0, StoryboardPanel.maxCharacters)
        : characters;
    await _updatePanel(
      id,
      (panel, page) => panel.copyWith(characters: limited),
    );
  }

  Future<void> setPanelSeed(String id, int? seed) async {
    await _updatePanel(
      id,
      (panel, page) => seed == null
          ? panel.copyWith(clearSeed: true)
          : panel.copyWith(seed: seed),
    );
  }

  Future<void> setPanelVariants(String id, int variants) async {
    await _updatePanel(
      id,
      (panel, page) => panel.copyWith(
        variants: variants.clamp(1, StoryboardPanel.maxVariants),
      ),
    );
  }

  Future<void> setPanelLocked(String id, bool locked) async {
    await _updatePanel(id, (panel, page) => panel.copyWith(locked: locked));
  }

  /// 切换分镜是否参与生成；停用只影响生成，不改版面。
  Future<void> setPanelEnabled(String id, bool enabled) async {
    await _updatePanel(id, (panel, page) => panel.copyWith(enabled: enabled));
  }

  /// 切换"不受间距约束"：刻意压边或出血时用。
  Future<void> setPanelIgnoreSpacing(String id, bool ignore) async {
    await _updatePanel(
      id,
      (panel, page) => panel.copyWith(ignoreSpacing: ignore),
    );
  }

  Future<void> removePanel(String id) async {
    await future;
    final page = activePage;
    if (page == null) return;
    final next = page.withoutPanel(id);
    if (identical(next, page)) return;
    _commit(_withActivePage(next));
  }

  /// 复制一个分镜，偏移一点位置后置顶。
  Future<String> duplicatePanel(String id) async {
    await future;
    final page = activePage;
    final source = page?.panelById(id);
    if (page == null || source == null) return '';
    final now = DateTime.now();
    final size = Size(page.width.toDouble(), page.height.toDouble());
    final target = StoryboardGeometry.normalizeRect(
      source.rect.translate(24, 24),
      pageSize: size,
    );
    final copy = StoryboardPanel(
      id: _newId(),
      order: page.nextOrder,
      zOrder: page.maxZOrder + 1,
      shape: source.shape,
      x: target.left,
      y: target.top,
      width: target.width,
      height: target.height,
      points: source.points,
      resolution: source.resolution,
      fit: source.fit,
      prompt: source.prompt,
      negativePrompt: source.negativePrompt,
      seed: source.seed,
      variants: source.variants,
      note: source.note,
      createdAt: now,
      updatedAt: now,
    );
    _commit(_withActivePage(page.withPanel(copy, now: now)));
    return copy.id;
  }

  Future<void> bringPanelToFront(String id) async {
    await _updatePanel(
      id,
      (panel, page) => panel.copyWith(zOrder: page.maxZOrder + 1),
    );
  }

  Future<void> sendPanelToBack(String id) async {
    await _updatePanel(id, (panel, page) {
      final lowest = page.panels.isEmpty
          ? 0
          : page.panels
                .map((item) => item.zOrder)
                .reduce((a, b) => a < b ? a : b);
      return panel.copyWith(zOrder: lowest - 1);
    });
  }

  // ==================== 生成结果回填 ====================

  /// 记录一张已落盘的生成图并选中它。
  Future<void> addGeneratedImage(String panelId, String relativePath) async {
    await _updatePanel(
      panelId,
      (panel, page) => panel.withGeneratedImage(relativePath),
    );
  }

  Future<void> selectPanelImage(String panelId, String relativePath) async {
    await _updatePanel(panelId, (panel, page) {
      if (!panel.images.contains(relativePath)) return panel;
      return panel.copyWith(
        selectedImage: relativePath,
        status: StoryboardPanelStatus.done,
        updatedAt: DateTime.now(),
      );
    });
  }

  Future<void> setPanelStatus(String panelId, StoryboardPanelStatus status) async {
    await _updatePanel(
      panelId,
      (panel, page) => panel.status == status
          ? panel
          : panel.copyWith(status: status, updatedAt: DateTime.now()),
    );
  }

  Future<void> setPanelFailed(String panelId) =>
      setPanelStatus(panelId, StoryboardPanelStatus.failed);

  // ==================== 内部 ====================

  /// 读取分镜、替换、写回；分镜不存在或未就绪时静默跳过。
  Future<void> _updatePanel(
    String id,
    StoryboardPanel Function(StoryboardPanel panel, StoryboardPage page) update,
  ) async {
    await future;
    final page = activePage;
    final panel = page?.panelById(id);
    if (page == null || panel == null) return;
    final next = update(panel, page).copyWith(updatedAt: DateTime.now());
    if (identical(next, panel)) return;
    _commit(_withActivePage(page.withPanel(next)));
  }

  StoryboardDocument _withActivePage(StoryboardPage page) {
    final doc = document;
    if (doc == null) return StoryboardDocument.singlePage(page);
    return doc.withPage(page);
  }

  void _commit(StoryboardDocument next) {
    state = AsyncData(next);
    _persistTimer?.cancel();
    _persistTimer = Timer(persistDebounce, () {
      _persistTimer = null;
      unawaited(_repository.save(document ?? next));
    });
  }

  static String _newId() => const Uuid().v4();

  /// 版面矩形在模型里是 x/y/width/height 四个字段，这里统一换算。
  static StoryboardPanel _withRect(StoryboardPanel panel, Rect rect) =>
      panel.copyWith(
        x: rect.left,
        y: rect.top,
        width: rect.width,
        height: rect.height,
      );
}

/// 分镜文档状态。
///
/// 非 autoDispose：应用生命周期内保持同一个实例，关闭分镜不卸载文档。
final storyboardDocumentControllerProvider =
    AsyncNotifierProvider<StoryboardDocumentController, StoryboardDocument>(
      StoryboardDocumentController.new,
    );
