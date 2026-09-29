import 'dart:ui';

import '../../services/gallery/gallery_path_utils.dart';
import 'storyboard_fit_mode.dart';
import 'storyboard_panel_character.dart';
import 'storyboard_panel_generation.dart';
import 'storyboard_panel_shape.dart';
import 'storyboard_panel_status.dart';
import 'storyboard_resolution.dart';

/// 漫画分镜页上的一个分镜。
///
/// 坐标是页面像素（等于用户指定的最终输出分辨率坐标），尺寸是版面尺寸；
/// [points] 是归一化到本分镜矩形内的多边形顶点，因此移动或缩放矩形时
/// 多边形自动跟随，画布交互只需要修改矩形。
///
/// 生成分辨率与版面尺寸是两个独立的量：[resolution] 决定请求什么样尺寸的
/// 图，[fit] 决定这张图如何落进版面矩形。
class StoryboardPanel {
  /// 分镜在页面上的最小边长（页面像素）。
  static const double minSide = 8.0;

  /// 多边形顶点数量范围。
  static const int minPolygonPoints = 3;
  static const int maxPolygonPoints = 64;

  /// 单个分镜可保留的变体（生成图）数量上限。
  static const int maxImages = 16;

  /// 单个分镜一次生成的张数上限。
  static const int maxVariants = 16;

  /// 单个分镜可携带的角色数量上限，与生成页的角色上限保持同一量级。
  static const int maxCharacters = 6;

  /// 矩形分镜在归一化空间下的四个角，顺序与多边形顶点一致。
  static const List<Offset> rectCorners = [
    Offset(0, 0),
    Offset(1, 0),
    Offset(1, 1),
    Offset(0, 1),
  ];

  final String id;

  /// 阅读顺序，从 1 开始。
  final int order;

  /// 叠放顺序，越大越靠上。
  final int zOrder;

  final StoryboardPanelShape shape;

  final double x;
  final double y;
  final double width;
  final double height;

  /// 归一化到本分镜矩形（0..1）的多边形顶点；矩形分镜为空。
  final List<Offset> points;

  final StoryboardResolution resolution;
  final StoryboardFitMode fit;

  final String prompt;
  final String? negativePrompt;

  /// 本分镜专属的角色；为空时继承生成页当前角色。
  final List<StoryboardPanelCharacter> characters;

  final int? seed;

  /// 本次为这个分镜生成几张图。
  final int variants;

  /// 已生成的图，相对图库根目录的 '/' 分隔路径，按生成顺序排列。
  final List<String> images;

  /// 当前选中的那张图；必须存在于 [images] 中。
  final String? selectedImage;

  final StoryboardPanelStatus status;

  /// 锁定后画布交互不再改动版面几何。
  final bool locked;

  /// 拖拽时跳过页边距与分镜间距约束，用于刻意让分镜出血或压边的情况。
  final bool ignoreSpacing;

  /// 是否参与生成；停用的分镜在画面上保留但会被跳过，用作暂不处理的占位。
  final bool enabled;

  /// 生成配置快照（模型、采样参数、图生图与参考库引用）。
  ///
  /// 切换分镜时左侧参数面板整体切到这份快照；空快照表示跟随生成页当前值。
  final StoryboardPanelGeneration generation;

  final String? note;

  final DateTime createdAt;
  final DateTime updatedAt;

  const StoryboardPanel({
    required this.id,
    required this.order,
    this.zOrder = 0,
    this.shape = StoryboardPanelShape.rect,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.points = const [],
    this.resolution = const StoryboardResolution.auto(),
    this.fit = StoryboardFitMode.cover,
    this.prompt = '',
    this.negativePrompt,
    this.characters = const [],
    this.seed,
    this.variants = 1,
    this.images = const [],
    this.selectedImage,
    this.status = StoryboardPanelStatus.empty,
    this.locked = false,
    this.ignoreSpacing = false,
    this.enabled = true,
    this.generation = StoryboardPanelGeneration.empty,
    this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  Rect get rect => Rect.fromLTWH(x, y, width, height);

  bool get isPolygon => shape.isPolygon;

  bool get hasImage => selectedImage != null && selectedImage!.isNotEmpty;

  bool get hasPrompt => prompt.trim().isNotEmpty;

  double get aspectRatio => height > 0 ? width / height : 1.0;

  /// 实际参与合成与命中测试的顶点；矩形分镜返回四个角。
  List<Offset> get effectivePoints => isPolygon && points.length >= minPolygonPoints
      ? points
      : rectCorners;

  StoryboardPanel copyWith({
    int? order,
    int? zOrder,
    StoryboardPanelShape? shape,
    double? x,
    double? y,
    double? width,
    double? height,
    List<Offset>? points,
    StoryboardResolution? resolution,
    StoryboardFitMode? fit,
    String? prompt,
    String? negativePrompt,
    bool clearNegativePrompt = false,
    List<StoryboardPanelCharacter>? characters,
    int? seed,
    bool clearSeed = false,
    int? variants,
    List<String>? images,
    String? selectedImage,
    bool clearSelectedImage = false,
    StoryboardPanelStatus? status,
    bool? locked,
    bool? ignoreSpacing,
    bool? enabled,
    StoryboardPanelGeneration? generation,
    String? note,
    bool clearNote = false,
    DateTime? updatedAt,
  }) {
    return StoryboardPanel(
      id: id,
      order: order ?? this.order,
      zOrder: zOrder ?? this.zOrder,
      shape: shape ?? this.shape,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      points: points ?? this.points,
      resolution: resolution ?? this.resolution,
      fit: fit ?? this.fit,
      prompt: prompt ?? this.prompt,
      negativePrompt: clearNegativePrompt
          ? null
          : (negativePrompt ?? this.negativePrompt),
      characters: characters ?? this.characters,
      seed: clearSeed ? null : (seed ?? this.seed),
      variants: variants ?? this.variants,
      images: images ?? this.images,
      selectedImage: clearSelectedImage
          ? null
          : (selectedImage ?? this.selectedImage),
      status: status ?? this.status,
      locked: locked ?? this.locked,
      ignoreSpacing: ignoreSpacing ?? this.ignoreSpacing,
      enabled: enabled ?? this.enabled,
      generation: generation ?? this.generation,
      note: clearNote ? null : (note ?? this.note),
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// 记录一张新生成的图并选中它，超出上限时丢弃最旧的一张。
  StoryboardPanel withGeneratedImage(String relativePath, {DateTime? now}) {
    if (!isValidGalleryRelativePath(relativePath)) return this;
    final next = <String>[
      ...images.where((path) => path != relativePath),
      relativePath,
    ];
    while (next.length > maxImages) {
      next.removeAt(0);
    }
    return copyWith(
      images: next,
      selectedImage: relativePath,
      status: StoryboardPanelStatus.done,
      updatedAt: now ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'order': order,
    'zOrder': zOrder,
    'shape': shape.name,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    if (isPolygon && points.isNotEmpty)
      'points': [
        for (final point in points) [point.dx, point.dy],
      ],
    'resolution': resolution.toJson(),
    'fit': fit.name,
    if (prompt.isNotEmpty) 'prompt': prompt,
    if (negativePrompt != null && negativePrompt!.isNotEmpty)
      'negativePrompt': negativePrompt,
    if (characters.isNotEmpty)
      'characters': [for (final character in characters) character.toJson()],
    if (seed != null) 'seed': seed,
    'variants': variants,
    if (images.isNotEmpty) 'images': images,
    if (hasImage) 'selectedImage': selectedImage,
    'status': status.name,
    if (locked) 'locked': true,
    if (ignoreSpacing) 'ignoreSpacing': true,
    if (!enabled) 'enabled': false,
    if (!generation.isEmpty) 'generation': generation.toJson(),
    if (note != null && note!.isNotEmpty) 'note': note,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };

  /// 解析单个分镜；字段缺失或非法时退回安全默认值，不抛异常。
  ///
  /// 返回 null 只发生在 id 不可用时——没有 id 的分镜无法被选中、生成或
  /// 回填，由调用方丢弃。
  static StoryboardPanel? fromJson(Object? value, {int fallbackOrder = 1}) {
    if (value is! Map) return null;
    final json = Map<String, dynamic>.from(value);

    final id = json['id'];
    if (id is! String || id.isEmpty) return null;

    final rawPoints = _readPoints(json['points']);
    var shape = StoryboardPanelShape.fromStorage(json['shape']);
    // 顶点不足以构成多边形时按矩形处理，避免文档里存在无法渲染的分镜。
    if (shape.isPolygon && rawPoints.length < minPolygonPoints) {
      shape = StoryboardPanelShape.rect;
    }

    final images = _readImages(json['images']);
    final rawSelected = json['selectedImage'];
    final selectedImage = rawSelected is String && images.contains(rawSelected)
        ? rawSelected
        : (images.isEmpty ? null : images.last);

    final createdAt = _readInt(json['createdAt'], 0);
    final width = _readSide(json['width'], minSide);
    final height = _readSide(json['height'], minSide);

    final prompt = json['prompt'];
    final negativePrompt = json['negativePrompt'];
    final note = json['note'];

    return StoryboardPanel(
      id: id,
      order: _readInt(json['order'], fallbackOrder),
      zOrder: _readInt(json['zOrder'], 0),
      shape: shape,
      x: _readFinite(json['x'], 0),
      y: _readFinite(json['y'], 0),
      width: width,
      height: height,
      points: shape.isPolygon ? rawPoints : const [],
      resolution: StoryboardResolution.fromJson(json['resolution']),
      fit: StoryboardFitMode.fromStorage(json['fit']),
      prompt: prompt is String ? prompt : '',
      negativePrompt: negativePrompt is String && negativePrompt.isNotEmpty
          ? negativePrompt
          : null,
      characters: _readCharacters(json['characters']),
      seed: json['seed'] is num ? (json['seed'] as num).toInt() : null,
      variants: _readInt(json['variants'], 1).clamp(1, maxVariants),
      images: images,
      selectedImage: selectedImage,
      status: StoryboardPanelStatus.fromStorage(json['status']),
      locked: json['locked'] == true,
      ignoreSpacing: json['ignoreSpacing'] == true,
      enabled: json['enabled'] != false,
      generation: StoryboardPanelGeneration.fromJson(json['generation']),
      note: note is String && note.isNotEmpty ? note : null,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        _readInt(json['updatedAt'], createdAt),
      ),
    );
  }

  static double _readFinite(Object? value, double fallback) =>
      value is num && value.isFinite ? value.toDouble() : fallback;

  static double _readSide(Object? value, double fallback) {
    final side = _readFinite(value, fallback);
    return side < minSide ? fallback : side;
  }

  static int _readInt(Object? value, int fallback) =>
      value is num && value.isFinite ? value.toInt() : fallback;

  /// 读取多边形顶点并钳制到归一化范围，顺带丢弃非数值项。
  static List<Offset> _readPoints(Object? value) {
    if (value is! List) return const [];
    final points = <Offset>[];
    for (final item in value) {
      if (item is! List || item.length < 2) continue;
      final dx = item[0];
      final dy = item[1];
      if (dx is! num || dy is! num) continue;
      if (!dx.isFinite || !dy.isFinite) continue;
      points.add(
        Offset(dx.toDouble().clamp(0.0, 1.0), dy.toDouble().clamp(0.0, 1.0)),
      );
      if (points.length > maxPolygonPoints) break;
    }
    return points;
  }

  /// 只接受可用的角色条目，并限制数量。
  static List<StoryboardPanelCharacter> _readCharacters(Object? value) {
    if (value is! List) return const [];
    final characters = <StoryboardPanelCharacter>[];
    for (final item in value) {
      if (characters.length >= maxCharacters) break;
      final character = StoryboardPanelCharacter.fromJson(item);
      if (character == null) continue;
      characters.add(character);
    }
    return characters;
  }

  /// 只接受图库内的规范化相对路径，越界或设备绝对路径直接丢弃。
  static List<String> _readImages(Object? value) {
    if (value is! List) return const [];
    final images = <String>[];
    for (final item in value) {
      if (item is! String || !isValidGalleryRelativePath(item)) continue;
      if (images.contains(item)) continue;
      images.add(item);
      if (images.length >= maxImages) break;
    }
    return images;
  }
}
