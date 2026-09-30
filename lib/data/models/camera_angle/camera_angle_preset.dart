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

/// 视角控制的完整预设：姿态 + 镜头语言 + 强度 + 是否写入提示词。
///
/// 预设是纯数据，`buildPromptFragment()` 是唯一生成提示词文本的入口，
/// 保证工具栏按钮、预览和实际插入内容完全一致。
class CameraAnglePreset {
  const CameraAnglePreset({
    this.pose = CameraAnglePose.neutral,
    this.effects = const {},
    this.strength = defaultStrength,
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

  /// 是否已写入提示词；关闭时提示词里不保留视角片段。
  final bool enabled;

  CameraAnglePreset copyWith({
    CameraAnglePose? pose,
    Set<CameraLensEffect>? effects,
    double? strength,
    bool? enabled,
  }) => CameraAnglePreset(
    pose: pose ?? this.pose,
    effects: effects ?? this.effects,
    strength: strength ?? this.strength,
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

  /// 按当前强度输出的标签，必要时使用 NAI 数值强调 `weight::tag::`。
  ///
  /// 强度为 1 时不加任何权重语法；数值强调自 V4 起可用，默认输出因此对
  /// V3 及更低版本同样有效。
  List<String> get promptTags {
    final weight = strength.clamp(minStrength, maxStrength).toDouble();
    final weighted = (weight - 1).abs() >= _strengthEpsilon;
    final prefix = weighted ? '${formatWeight(weight)}::' : '';
    return [
      for (final tag in plainTags) weighted ? '$prefix$tag::' : tag,
    ];
  }

  /// 可直接写入提示词的片段；无标签时返回空串。
  String get promptFragment => promptTags.join(', ');

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
      enabled: json['enabled'] == true,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CameraAnglePreset &&
        other.pose == pose &&
        other.strength == strength &&
        other.enabled == enabled &&
        other.effects.length == effects.length &&
        other.effects.containsAll(effects);
  }

  @override
  int get hashCode => Object.hash(
    pose,
    strength,
    enabled,
    Object.hashAllUnordered(effects),
  );

  @override
  String toString() =>
      'CameraAnglePreset(pose: $pose, effects: $effects, '
      'strength: $strength, enabled: $enabled)';
}
