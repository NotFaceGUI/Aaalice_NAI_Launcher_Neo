import 'camera_angle_pose.dart';

/// 视角控制可叠加的镜头语言标签。
///
/// 全部使用 Danbooru 词表中的规范标签（NovelAI 图像模型即按该词表训练），
/// 因此统一写下划线形式，可被 `NaiPromptFormatter` 反复格式化而不改变。
enum CameraLensEffect {
  /// 视线看向镜头。
  lookingAtViewer('looking_at_viewer'),

  /// 景深虚化。
  depthOfField('depth_of_field'),

  /// 背景虚化。
  blurryBackground('blurry_background'),

  /// 鱼眼畸变。
  fisheye('fisheye'),

  /// 镜头光晕。
  lensFlare('lens_flare'),

  /// 色差。
  chromaticAberration('chromatic_aberration'),

  /// 动态模糊。
  motionBlur('motion_blur'),

  /// 变焦拉近。
  zoomLayer('zoom_layer'),

  /// 消失点透视。
  vanishingPoint('vanishing_point'),

  /// 透视缩短。
  foreshortening('foreshortening');

  const CameraLensEffect(this.tag);

  /// 输出的 Danbooru 标签。
  final String tag;

  static CameraLensEffect? fromName(String name) {
    for (final effect in values) {
      if (effect.name == name) return effect;
    }
    return null;
  }
}

/// 视角片段的输出形式。
///
/// 标签走 Danbooru 词表，稳定但只有分档；自然语言描述能表达八向方位、俯仰与
/// 倾斜度数，V4 及以上模型都能读懂（V5 尤其擅长），两者并存时准确度最高。
/// V3 只认标签，调用方需要按模型限制可选项。
enum CameraAngleOutputMode {
  /// 只输出分档标签。
  tags('tags'),

  /// 标签加一句机位描述（默认）。
  tagsWithDescription('tags_description'),

  /// 只输出机位描述。
  description('description');

  const CameraAngleOutputMode(this.id);

  /// 持久化用的稳定标识。
  final String id;

  static CameraAngleOutputMode fromId(String? id) {
    for (final mode in values) {
      if (mode.id == id) return mode;
    }
    return CameraAngleOutputMode.tagsWithDescription;
  }
}

/// 视角控制的完整预设：姿态 + 镜头语言 + 强度 + 输出形式 + 是否写入提示词。
///
/// 预设是纯数据，`buildPromptFragment()` 是唯一生成提示词文本的入口，
/// 保证工具栏按钮、预览和实际插入内容完全一致。
class CameraAnglePreset {
  const CameraAnglePreset({
    this.pose = CameraAnglePose.neutral,
    this.effects = const {},
    this.strength = defaultStrength,
    this.outputMode = CameraAngleOutputMode.tagsWithDescription,
    this.enabled = false,
  });

  /// 中性强度：输出不带数值强调的纯标签，对所有模型版本都有效。
  static const double defaultStrength = 1;

  static const double minStrength = 0.5;
  static const double maxStrength = 2;

  /// 强度低于该差值时不写数值强调，避免生成无意义的 `1.02::tag::`。
  static const double _strengthEpsilon = 0.05;

  final CameraAnglePose pose;
  final Set<CameraLensEffect> effects;

  /// 提示词强度，`1` 表示原样输出标签。
  final double strength;

  /// 输出形式：标签、标签加描述、或只输出描述。
  final CameraAngleOutputMode outputMode;

  /// 是否已写入提示词；关闭时提示词里不保留视角片段。
  final bool enabled;

  CameraAnglePreset copyWith({
    CameraAnglePose? pose,
    Set<CameraLensEffect>? effects,
    double? strength,
    CameraAngleOutputMode? outputMode,
    bool? enabled,
  }) => CameraAnglePreset(
    pose: pose ?? this.pose,
    effects: effects ?? this.effects,
    strength: strength ?? this.strength,
    outputMode: outputMode ?? this.outputMode,
    enabled: enabled ?? this.enabled,
  );

  /// 切换单个镜头语言标签。
  CameraAnglePreset toggleEffect(CameraLensEffect effect) {
    final next = {...effects};
    if (!next.remove(effect)) next.add(effect);
    return copyWith(effects: next);
  }

  /// 输出顺序：方位 → 俯仰 → 取景 → 倾斜 → 镜头语言。
  List<String> get plainTags => [
    ...pose.tags,
    for (final effect in CameraLensEffect.values)
      if (effects.contains(effect)) effect.tag,
  ];

  /// 按当前强度与角度输出的标签，必要时使用 NAI 数值强调 `weight::tag::`。
  ///
  /// 权重 = 角度系数 × 强度：角度越大权重越高，因此同一分档内也能区分"刚转
  /// 过去"和"几乎正侧对"。强度为 1 且角度在死区内时输出纯标签，对 V3 及更
  /// 低版本同样有效。
  List<String> get promptTags {
    final scale = strength.clamp(minStrength, maxStrength).toDouble();
    return [
      ?_weightedTag(pose.azimuthTag, 1 + 0.5 * pose.azimuthEmphasis, scale),
      ?_weightedTag(pose.elevationTag, 1 + 0.4 * pose.elevationEmphasis, scale),
      _weightedTag(pose.shotTag, 1, scale)!,
      ?_weightedTag(pose.rollTag, 1 + 0.5 * pose.rollEmphasis, scale),
      for (final effect in CameraLensEffect.values)
        if (effects.contains(effect)) _weightedTag(effect.tag, 1, scale)!,
    ];
  }

  String? _weightedTag(String? tag, double axisWeight, double scale) {
    if (tag == null) return null;
    final weight = axisWeight * scale;
    if ((weight - 1).abs() < _strengthEpsilon) return tag;
    return '${formatWeight(weight)}::$tag::';
  }

  /// 可直接写入提示词的片段，按 [outputMode] 组合标签与自然语言描述。
  ///
  /// [allowDescription] 为 false 时只用标签：V3 及更早的模型只认 Danbooru
  /// 标签，写入英文句子会白占 token。
  String promptFragment({bool allowDescription = true}) {
    final tags = promptTags.join(', ');
    if (!allowDescription || outputMode == CameraAngleOutputMode.tags) {
      return tags;
    }
    if (outputMode == CameraAngleOutputMode.description) {
      return pose.description;
    }
    return tags.isEmpty ? pose.description : '$tags, ${pose.description}';
  }

  /// NAI 数值强调的权重写法，与 `PromptTag.toSyntaxString()` 保持一致。
  static String formatWeight(double weight) {
    if (weight == weight.truncateToDouble()) return weight.toInt().toString();
    return weight
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  Map<String, Object?> toJson() => {
    'pose': pose.toJson(),
    'effects': [for (final effect in effects) effect.name],
    'strength': strength,
    'outputMode': outputMode.id,
    'enabled': enabled,
  };

  /// 从存储解析预设，非法字段逐项回落到默认值。
  factory CameraAnglePreset.fromJson(Map<String, Object?> json) {
    final effects = <CameraLensEffect>{};
    final rawEffects = json['effects'];
    if (rawEffects is List) {
      for (final entry in rawEffects) {
        final effect = entry is String
            ? CameraLensEffect.fromName(entry)
            : null;
        if (effect != null) effects.add(effect);
      }
    }

    final rawPose = json['pose'];
    final rawStrength = json['strength'];
    return CameraAnglePreset(
      pose: rawPose is Map<String, Object?>
          ? CameraAnglePose.fromJson(rawPose)
          : CameraAnglePose.neutral,
      effects: effects,
      strength: rawStrength is num
          ? rawStrength.toDouble().clamp(minStrength, maxStrength).toDouble()
          : defaultStrength,
      outputMode: CameraAngleOutputMode.fromId(
        json['outputMode'] is String ? json['outputMode'] as String : null,
      ),
      enabled: json['enabled'] == true,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CameraAnglePreset &&
        other.pose == pose &&
        other.strength == strength &&
        other.outputMode == outputMode &&
        other.enabled == enabled &&
        other.effects.length == effects.length &&
        other.effects.containsAll(effects);
  }

  @override
  int get hashCode => Object.hash(
    pose,
    strength,
    outputMode,
    enabled,
    Object.hashAllUnordered(effects),
  );

  @override
  String toString() =>
      'CameraAnglePreset(pose: $pose, effects: $effects, '
      'strength: $strength, enabled: $enabled)';
}
