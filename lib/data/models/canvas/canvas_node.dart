import 'canvas_node_kind.dart';
import 'canvas_node_params.dart';

/// 无限画布上的一个节点。
///
/// 坐标与尺寸都是画布空间（未缩放）的值；视口变换由画布控制器负责。
/// 图片节点只持有相对图库根目录的路径引用，不持有图片字节。
class CanvasNode {
  /// 图片节点在 100% 缩放下的默认宽度
  static const double defaultImageWidth = 220.0;

  /// 便签节点的默认尺寸
  static const double defaultNoteWidth = 220.0;
  static const double defaultNoteHeight = 140.0;

  /// 种子待办节点的默认尺寸
  static const double defaultSeedTodoWidth = 240.0;
  static const double defaultSeedTodoHeight = 132.0;

  /// 节点缩放下限/上限（画布空间尺寸，不含视口缩放）
  static const double minNodeWidth = 72.0;
  static const double maxNodeWidth = 1600.0;
  static const double minNodeHeight = 48.0;
  static const double maxNodeHeight = 1600.0;

  final String id;
  final CanvasNodeKind kind;
  final double x;
  final double y;
  final double width;
  final double height;
  final int zOrder;

  /// 相对图库根目录的 '/' 分隔图片路径；非图片节点为 null
  final String? imageRelativePath;

  /// 种子：图片节点来自生成参数，种子待办节点来自固定时的输入框
  final int? seed;

  /// 可还原的生成参数快照
  final CanvasNodeParams? params;

  /// 便签文本
  final String? noteText;

  /// 种子待办是否已完成
  final bool todoDone;

  final DateTime createdAt;
  final DateTime updatedAt;

  const CanvasNode({
    required this.id,
    required this.kind,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.zOrder = 0,
    this.imageRelativePath,
    this.seed,
    this.params,
    this.noteText,
    this.todoDone = false,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 由像素尺寸与兜底比例推导节点宽高比。
  ///
  /// 失败快照与部分图源的 width/height 不可靠（0 或缺失），直接相除会得到
  /// 0、NaN 或无穷，节点盒就会用错误比例落位，所以要显式兜底。
  static double resolveAspectRatio({
    int? width,
    int? height,
    double? fallback,
  }) {
    if (width != null && height != null && width > 0 && height > 0) {
      return width / height;
    }
    if (fallback != null && fallback.isFinite && fallback > 0) return fallback;
    return 1;
  }

  /// 节点在画布空间占据的右边界/下边界
  double get right => x + width;
  double get bottom => y + height;

  /// 是否与给定画布空间矩形相交（视口裁剪用）
  bool intersects(double left, double top, double right_, double bottom_) =>
      x < right_ && right > left && y < bottom_ && bottom > top;

  CanvasNode copyWith({
    CanvasNodeKind? kind,
    double? x,
    double? y,
    double? width,
    double? height,
    int? zOrder,
    String? imageRelativePath,
    bool clearImageRelativePath = false,
    int? seed,
    CanvasNodeParams? params,
    String? noteText,
    bool? todoDone,
    DateTime? updatedAt,
  }) {
    return CanvasNode(
      id: id,
      kind: kind ?? this.kind,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      zOrder: zOrder ?? this.zOrder,
      imageRelativePath: clearImageRelativePath
          ? null
          : (imageRelativePath ?? this.imageRelativePath),
      seed: seed ?? this.seed,
      params: params ?? this.params,
      noteText: noteText ?? this.noteText,
      todoDone: todoDone ?? this.todoDone,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.storageValue,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'zOrder': zOrder,
    if (imageRelativePath != null) 'imagePath': imageRelativePath,
    if (seed != null) 'seed': seed,
    if (params != null && !params!.isEmpty) 'params': params!.toJson(),
    if (noteText != null && noteText!.isNotEmpty) 'note': noteText,
    if (todoDone) 'todoDone': true,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };

  /// 解析单个节点；字段缺失或非法时退回安全默认值，不抛异常。
  static CanvasNode fromJson(
    Map<String, dynamic> json, {
    required int fallbackZ,
  }) {
    double readDouble(Object? value, double fallback) =>
        value is num && value.isFinite ? value.toDouble() : fallback;
    int readInt(Object? value, int fallback) =>
        value is num ? value.toInt() : fallback;

    final kind = CanvasNodeKind.fromStorage(json['kind']);
    final rawNote = json['note'];
    final rawPath = json['imagePath'];
    final rawParams = json['params'];
    final createdAt = readInt(json['createdAt'], 0);

    return CanvasNode(
      id: json['id'] is String ? json['id'] as String : '',
      kind: kind,
      x: readDouble(json['x'], 0),
      y: readDouble(json['y'], 0),
      width: readDouble(
        json['width'],
        0,
      ).clamp(minNodeWidth, maxNodeWidth).toDouble(),
      height: readDouble(
        json['height'],
        0,
      ).clamp(minNodeHeight, maxNodeHeight).toDouble(),
      zOrder: readInt(json['zOrder'], fallbackZ),
      imageRelativePath:
          kind.hasImage && rawPath is String && rawPath.isNotEmpty
          ? rawPath
          : null,
      seed: json['seed'] is num ? (json['seed'] as num).toInt() : null,
      params: rawParams is Map
          ? CanvasNodeParams.fromJson(Map<String, dynamic>.from(rawParams))
          : null,
      noteText: rawNote is String ? rawNote : null,
      todoDone: json['todoDone'] == true,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        readInt(json['updatedAt'], createdAt),
      ),
    );
  }
}
