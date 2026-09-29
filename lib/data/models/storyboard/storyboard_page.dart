import 'storyboard_page_background.dart';
import 'storyboard_panel.dart';

/// 一张漫画分镜页。
///
/// [width]/[height] 是用户指定的最终输出分辨率，页面坐标与它同一空间：
/// 分镜矩形直接用输出像素表达，导出时不需要额外的换算层。
/// 但页面本身不是生成物——单张生成的上限（3,145,728 像素）远小于常见
/// 漫画页，所以页面由逐分镜生成的结果合成而来。
///
/// [margin]/[gutter] 是排版间距：前者是页边留白，后者是分镜之间的空隙。
/// 它们属于页面而不是某次网格操作，换页或重开都保持同一套间距。
class StoryboardPage {
  /// 页面边长下限，低于此值排版与合成都没有意义。
  static const int minSide = 64;

  /// 页面边长上限。
  static const int maxSide = 16384;

  /// 页面总像素上限，与合成分辨率守卫保持一致。
  static const int maxPixels = 64000000;

  /// 单页分镜数量上限。
  static const int maxPanels = 256;

  /// 新建页面的默认尺寸：A4 比例的数字漫画画布。
  static const int defaultWidth = 2048;
  static const int defaultHeight = 2896;

  /// 间距按页面短边取比例，换页面尺寸时观感一致。
  static const double defaultMarginRatio = 0.04;
  static const double defaultGutterRatio = 0.02;

  /// 间距上限比例，避免一次手滑把页面挤空。
  static const double maxSpacingRatio = 0.2;

  /// 按页面短边比例算出的默认页边距。
  static double defaultMarginFor(int width, int height) =>
      _ratioOf(width, height, defaultMarginRatio);

  /// 按页面短边比例算出的默认分镜间距。
  static double defaultGutterFor(int width, int height) =>
      _ratioOf(width, height, defaultGutterRatio);

  static double _ratioOf(int width, int height, double ratio) {
    final shortSide = (width < height ? width : height).toDouble();
    return shortSide * ratio;
  }

  final String id;
  final String name;
  final int width;
  final int height;

  /// 页面外边距（页面像素）。
  final double margin;

  /// 分镜之间的空隙（页面像素）。
  final double gutter;

  /// 禁止收费：所有分镜都限制在 Opus 免费档内出图，超出的画幅自动缩小。
  ///
  /// 自定义画幅经常落在免费档之外，一次排版实验就烧掉 Anlas 不可接受；
  /// 打开后在免费范围内生成，再由分镜自己的适配方式缩放贴合。
  final bool freeOnly;

  final StoryboardPageBackground background;
  final List<StoryboardPanel> panels;
  final DateTime createdAt;
  final DateTime updatedAt;

  const StoryboardPage({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
    this.margin = 0,
    this.gutter = 0,
    this.freeOnly = false,
    this.background = const StoryboardPageBackground(),
    this.panels = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  /// 新建一张空白页，间距按页面尺寸取默认比例。
  factory StoryboardPage.create({
    required String id,
    String name = '',
    int width = defaultWidth,
    int height = defaultHeight,
    DateTime? now,
  }) {
    final stamp = now ?? DateTime.now();
    final sideClampedWidth = width.clamp(minSide, maxSide);
    final sideClampedHeight = height.clamp(minSide, maxSide);
    return StoryboardPage(
      id: id,
      name: name,
      width: sideClampedWidth,
      height: sideClampedHeight,
      margin: defaultMarginFor(sideClampedWidth, sideClampedHeight),
      gutter: defaultGutterFor(sideClampedWidth, sideClampedHeight),
      createdAt: stamp,
      updatedAt: stamp,
    );
  }

  double get aspectRatio => height > 0 ? width / height : 1.0;

  bool get isEmpty => panels.isEmpty;

  /// 按叠放顺序排列，用于绘制与倒序命中测试。
  List<StoryboardPanel> get panelsByZOrder {
    final sorted = List<StoryboardPanel>.of(panels);
    sorted.sort((a, b) {
      final byZ = a.zOrder.compareTo(b.zOrder);
      return byZ != 0 ? byZ : a.order.compareTo(b.order);
    });
    return sorted;
  }

  /// 按阅读顺序排列，用于批量生成与列表展示。
  List<StoryboardPanel> get panelsByReadingOrder {
    final sorted = List<StoryboardPanel>.of(panels);
    sorted.sort((a, b) => a.order.compareTo(b.order));
    return sorted;
  }

  int get maxZOrder => panels.isEmpty
      ? 0
      : panels.map((panel) => panel.zOrder).reduce((a, b) => a > b ? a : b);

  /// 下一个可用的阅读序号。
  int get nextOrder => panels.isEmpty
      ? 1
      : panels.map((panel) => panel.order).reduce((a, b) => a > b ? a : b) + 1;

  StoryboardPanel? panelById(String id) {
    for (final panel in panels) {
      if (panel.id == id) return panel;
    }
    return null;
  }

  /// 用同 id 的分镜替换已有项，未找到时追加。
  StoryboardPage withPanel(StoryboardPanel panel, {DateTime? now}) {
    final next = <StoryboardPanel>[];
    var replaced = false;
    for (final existing in panels) {
      if (existing.id == panel.id) {
        next.add(panel);
        replaced = true;
      } else {
        next.add(existing);
      }
    }
    if (!replaced) {
      if (next.length >= maxPanels) return this;
      next.add(panel);
    }
    return copyWith(panels: next, updatedAt: now ?? DateTime.now());
  }

  StoryboardPage withoutPanel(String id, {DateTime? now}) {
    final next = panels.where((panel) => panel.id != id).toList(growable: false);
    if (next.length == panels.length) return this;
    return copyWith(panels: next, updatedAt: now ?? DateTime.now());
  }

  StoryboardPage copyWith({
    String? name,
    int? width,
    int? height,
    double? margin,
    double? gutter,
    bool? freeOnly,
    StoryboardPageBackground? background,
    List<StoryboardPanel>? panels,
    DateTime? updatedAt,
  }) {
    return StoryboardPage(
      id: id,
      name: name ?? this.name,
      width: width ?? this.width,
      height: height ?? this.height,
      margin: margin ?? this.margin,
      gutter: gutter ?? this.gutter,
      freeOnly: freeOnly ?? this.freeOnly,
      background: background ?? this.background,
      panels: panels ?? this.panels,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'width': width,
    'height': height,
    'margin': margin,
    'gutter': gutter,
    'freeOnly': freeOnly,
    'background': background.toJson(),
    'panels': [for (final panel in panels) panel.toJson()],
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };

  /// 解析页面；id 或尺寸不可用时返回 null。
  ///
  /// 丢弃缺少 id 的分镜（无法被选中或回填），并补齐重复的 id——
  /// 保证内存里的页面始终自洽，与画布文档的处理方式一致。
  ///
  /// 旧文档没有间距字段：缺失时按当前页面尺寸取默认比例补齐，
  /// 而不是留 0 让所有分镜贴着页边。
  static StoryboardPage? fromJson(Object? value) {
    if (value is! Map) return null;
    final json = Map<String, dynamic>.from(value);

    final id = json['id'];
    if (id is! String || id.isEmpty) return null;

    final width = _readSide(json['width']);
    final height = _readSide(json['height']);
    if (width == null || height == null) return null;

    final rawName = json['name'];
    final createdAt = json['createdAt'] is num
        ? (json['createdAt'] as num).toInt()
        : 0;

    final panels = <StoryboardPanel>[];
    final seenIds = <String>{};
    final rawPanels = json['panels'];
    if (rawPanels is List) {
      for (final item in rawPanels) {
        if (panels.length >= maxPanels) break;
        final panel = StoryboardPanel.fromJson(
          item,
          fallbackOrder: panels.length + 1,
        );
        if (panel == null || !seenIds.add(panel.id)) continue;
        panels.add(panel);
      }
    }

    return StoryboardPage(
      id: id,
      name: rawName is String ? rawName : '',
      width: width,
      height: height,
      margin: _readSpacing(
        json['margin'],
        defaultMarginFor(width, height),
        width,
        height,
      ),
      gutter: _readSpacing(
        json['gutter'],
        defaultGutterFor(width, height),
        width,
        height,
      ),
      freeOnly: json['freeOnly'] == true,
      background: StoryboardPageBackground.fromJson(json['background']),
      panels: panels,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        json['updatedAt'] is num ? (json['updatedAt'] as num).toInt() : createdAt,
      ),
    );
  }

  /// 读取页面边长：必须是正整数，并在边长与总像素上限内收敛。
  static int? _readSide(Object? value) {
    if (value is! num || !value.isFinite) return null;
    final side = value.toInt();
    if (side < minSide) return null;
    if (side > maxSide) return maxSide;
    return side;
  }

  /// 读取间距：缺失用默认值，非法值归零，并钳在页面的合理比例内。
  static double _readSpacing(
    Object? value,
    double fallback,
    int width,
    int height,
  ) {
    final shortSide = (width < height ? width : height).toDouble();
    final limit = shortSide * maxSpacingRatio;
    if (value is! num || !value.isFinite) return fallback.clamp(0.0, limit);
    final spacing = value.toDouble();
    if (spacing < 0) return 0;
    return spacing > limit ? limit : spacing;
  }
}
