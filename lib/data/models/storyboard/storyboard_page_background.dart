import '../../services/gallery/gallery_path_utils.dart';
import 'storyboard_fit_mode.dart';

/// 分镜页背景的呈现方式。
enum StoryboardBackgroundKind {
  /// 不绘制背景，页面在编辑器里显示为透明棋盘格。
  none,

  /// 纯色背景。
  color,

  /// 以一张图库内的图片作为背景。
  image;

  static StoryboardBackgroundKind fromStorage(
    Object? value, {
    StoryboardBackgroundKind fallback = StoryboardBackgroundKind.none,
  }) {
    if (value is! String) return fallback;
    for (final kind in values) {
      if (kind.name == value) return kind;
    }
    return fallback;
  }
}

/// 分镜页的背景设置。
///
/// 背景图只保存相对图库根目录的路径引用，不复制图片字节——与画布节点、
/// 相册成员保持一致，整个图库文件夹拷贝到其他设备时背景随之可用。
class StoryboardPageBackground {
  /// 默认背景色：不透明白色，对应漫画页的纸面。
  static const int defaultColorArgb = 0xFFFFFFFF;

  const StoryboardPageBackground({
    this.kind = StoryboardBackgroundKind.none,
    this.colorArgb = defaultColorArgb,
    this.imagePath,
    this.fit = StoryboardFitMode.cover,
    this.prompt = '',
    this.seed,
    this.images = const [],
  });

  final StoryboardBackgroundKind kind;
  final int colorArgb;

  /// 相对图库根目录的 '/' 分隔路径；仅 [StoryboardBackgroundKind.image] 使用。
  final String? imagePath;

  final StoryboardFitMode fit;

  /// 背景图的生成提示词；选中背景后与分镜共用生成流程。
  final String prompt;

  /// 背景生成的固定种子；null 表示每次随机。
  final int? seed;

  /// 背景已生成的图，相对图库根目录，按生成顺序排列。
  final List<String> images;

  bool get hasImage =>
      kind == StoryboardBackgroundKind.image && (imagePath?.isNotEmpty ?? false);

  StoryboardPageBackground copyWith({
    StoryboardBackgroundKind? kind,
    int? colorArgb,
    String? imagePath,
    bool clearImagePath = false,
    StoryboardFitMode? fit,
    String? prompt,
    int? seed,
    bool clearSeed = false,
    List<String>? images,
  }) {
    return StoryboardPageBackground(
      kind: kind ?? this.kind,
      colorArgb: colorArgb ?? this.colorArgb,
      imagePath: clearImagePath ? null : (imagePath ?? this.imagePath),
      fit: fit ?? this.fit,
      prompt: prompt ?? this.prompt,
      seed: clearSeed ? null : (seed ?? this.seed),
      images: images ?? this.images,
    );
  }

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    if (kind == StoryboardBackgroundKind.color) 'colorArgb': colorArgb,
    if (hasImage) 'imagePath': imagePath,
    if (kind == StoryboardBackgroundKind.image) 'fit': fit.name,
    if (prompt.isNotEmpty) 'prompt': prompt,
    if (seed != null) 'seed': seed,
    if (images.isNotEmpty) 'images': images,
  };

  /// 解析背景设置；非法路径与缺失字段退回安全默认值，不抛异常。
  static StoryboardPageBackground fromJson(Object? value) {
    if (value is! Map) return const StoryboardPageBackground();
    final json = Map<String, dynamic>.from(value);
    final kind = StoryboardBackgroundKind.fromStorage(json['kind']);

    final rawColor = json['colorArgb'];
    final colorArgb = rawColor is num
        ? rawColor.toInt().toUnsigned(32)
        : defaultColorArgb;

    final rawPath = json['imagePath'];
    // 越界或设备绝对路径不得进入文档，否则会被云同步带到其他设备。
    final imagePath = rawPath is String && isValidGalleryRelativePath(rawPath)
        ? rawPath
        : null;

    if (kind == StoryboardBackgroundKind.image && imagePath == null) {
      return const StoryboardPageBackground();
    }

    final rawPrompt = json['prompt'];
    final images = <String>[];
    final rawImages = json['images'];
    if (rawImages is List) {
      for (final item in rawImages) {
        if (item is! String || !isValidGalleryRelativePath(item)) continue;
        if (images.contains(item)) continue;
        images.add(item);
      }
    }

    return StoryboardPageBackground(
      kind: kind,
      colorArgb: colorArgb,
      imagePath: imagePath,
      fit: StoryboardFitMode.fromStorage(json['fit']),
      prompt: rawPrompt is String ? rawPrompt : '',
      seed: json['seed'] is num ? (json['seed'] as num).toInt() : null,
      images: images,
    );
  }
}
