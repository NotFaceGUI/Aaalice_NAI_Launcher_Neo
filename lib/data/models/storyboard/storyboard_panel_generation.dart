/// 分镜的生成配置快照。
///
/// 分镜之间互相独立：切换分镜时左侧参数面板要整体切过去，而不只是提示词。
/// 提示词、负面词、种子、画幅与角色已经是分镜自身字段，这里补齐其余部分——
/// 模型与采样参数、以及图生图/风格迁移/精准参考的**引用**。
///
/// 只存引用不存图像字节：图生图源图、Vibe 编码、精准参考图都可能是几百 KB 的
/// base64，写进分镜 sidecar 会让文档和云备份急剧膨胀，而它们本来就属于图库或
/// 资源库。快照记录"指向谁"，恢复时按引用回读；引用失效时该字段留空，
/// 由界面提示，而不是让整份文档带着幽灵字节。
class StoryboardPanelGeneration {
  const StoryboardPanelGeneration({
    this.model,
    this.sampler,
    this.steps,
    this.scale,
    this.smea,
    this.smeaDyn,
    this.sourceImagePath,
    this.strength,
    this.noise,
    this.vibeLibraryIds = const [],
    this.preciseReferenceLibraryIds = const [],
  });

  /// 未指定时返回空快照，表示"这一项跟随生成页当前值"。
  static const StoryboardPanelGeneration empty = StoryboardPanelGeneration();

  final String? model;
  final String? sampler;
  final int? steps;
  final double? scale;
  final bool? smea;
  final bool? smeaDyn;

  /// 图生图源图，相对图库根目录的 '/' 分隔路径。
  final String? sourceImagePath;
  final double? strength;
  final double? noise;

  /// 风格迁移（Vibe）在资源库里的条目 id。
  final List<String> vibeLibraryIds;

  /// 精准参考在资源库里的条目 id。
  final List<String> preciseReferenceLibraryIds;

  /// 除提示词类字段外是否为空：为空时说明这个分镜没有自己的生成配置。
  bool get isEmpty =>
      model == null &&
      sampler == null &&
      steps == null &&
      scale == null &&
      smea == null &&
      smeaDyn == null &&
      sourceImagePath == null &&
      strength == null &&
      noise == null &&
      vibeLibraryIds.isEmpty &&
      preciseReferenceLibraryIds.isEmpty;

  StoryboardPanelGeneration copyWith({
    String? model,
    String? sampler,
    int? steps,
    double? scale,
    bool? smea,
    bool? smeaDyn,
    String? sourceImagePath,
    bool clearSourceImage = false,
    double? strength,
    double? noise,
    List<String>? vibeLibraryIds,
    List<String>? preciseReferenceLibraryIds,
  }) {
    return StoryboardPanelGeneration(
      model: model ?? this.model,
      sampler: sampler ?? this.sampler,
      steps: steps ?? this.steps,
      scale: scale ?? this.scale,
      smea: smea ?? this.smea,
      smeaDyn: smeaDyn ?? this.smeaDyn,
      sourceImagePath: clearSourceImage
          ? null
          : (sourceImagePath ?? this.sourceImagePath),
      strength: strength ?? this.strength,
      noise: noise ?? this.noise,
      vibeLibraryIds: vibeLibraryIds ?? this.vibeLibraryIds,
      preciseReferenceLibraryIds:
          preciseReferenceLibraryIds ?? this.preciseReferenceLibraryIds,
    );
  }

  Map<String, dynamic> toJson() => {
    if (model != null) 'model': model,
    if (sampler != null) 'sampler': sampler,
    if (steps != null) 'steps': steps,
    if (scale != null) 'scale': scale,
    if (smea != null) 'smea': smea,
    if (smeaDyn != null) 'smeaDyn': smeaDyn,
    if (sourceImagePath != null) 'sourceImagePath': sourceImagePath,
    if (strength != null) 'strength': strength,
    if (noise != null) 'noise': noise,
    if (vibeLibraryIds.isNotEmpty) 'vibeLibraryIds': vibeLibraryIds,
    if (preciseReferenceLibraryIds.isNotEmpty)
      'preciseReferenceLibraryIds': preciseReferenceLibraryIds,
  };

  /// 解析快照；字段缺失或非法时退回"跟随生成页"，不抛异常。
  static StoryboardPanelGeneration fromJson(Object? value) {
    if (value is! Map) return empty;
    final json = Map<String, dynamic>.from(value);

    return StoryboardPanelGeneration(
      model: _readString(json['model']),
      sampler: _readString(json['sampler']),
      steps: _readInt(json['steps']),
      scale: _readDouble(json['scale']),
      smea: json['smea'] is bool ? json['smea'] as bool : null,
      smeaDyn: json['smeaDyn'] is bool ? json['smeaDyn'] as bool : null,
      sourceImagePath: _readString(json['sourceImagePath']),
      strength: _readDouble(json['strength']),
      noise: _readDouble(json['noise']),
      vibeLibraryIds: _readIds(json['vibeLibraryIds']),
      preciseReferenceLibraryIds: _readIds(
        json['preciseReferenceLibraryIds'],
      ),
    );
  }

  static String? _readString(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static int? _readInt(Object? value) {
    if (value is! num || !value.isFinite) return null;
    return value.toInt();
  }

  static double? _readDouble(Object? value) {
    if (value is! num || !value.isFinite) return null;
    return value.toDouble();
  }

  static List<String> _readIds(Object? value) {
    if (value is! List) return const [];
    final ids = <String>[];
    for (final item in value) {
      final id = _readString(item);
      if (id == null || ids.contains(id)) continue;
      ids.add(id);
      if (ids.length >= maxEntries) break;
    }
    return ids;
  }

  /// 单个快照里每类引用的数量上限，与资源库的常见规模匹配。
  static const int maxEntries = 16;
}
