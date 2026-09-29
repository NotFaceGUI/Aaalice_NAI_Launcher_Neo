import 'dart:ui';

/// 分镜专属角色。
///
/// 分镜的角色与生成页的角色是两套：分镜要的是"这一格里有谁、站在哪"，
/// 生成页的角色是当前这一批生成的共用配置。分镜不填角色时继承生成页，
/// 填了就完全替换，不做合并——合并会让两边的增删互相干扰，难以预期。
class StoryboardPanelCharacter {
  /// 单个角色的提示词长度上限，避免异常数据把文档撑大。
  static const int maxPromptLength = 2000;

  const StoryboardPanelCharacter({
    required this.prompt,
    this.negativePrompt = '',
    this.x,
    this.y,
  });

  final String prompt;
  final String negativePrompt;

  /// 角色在画面内的相对位置（0..1）；两个都为空时交给模型自行安排。
  final double? x;
  final double? y;

  bool get hasPosition => x != null && y != null;

  bool get isUsable => prompt.trim().isNotEmpty;

  Offset? get position => hasPosition ? Offset(x!, y!) : null;

  StoryboardPanelCharacter copyWith({
    String? prompt,
    String? negativePrompt,
    double? x,
    double? y,
    bool clearPosition = false,
  }) {
    return StoryboardPanelCharacter(
      prompt: prompt ?? this.prompt,
      negativePrompt: negativePrompt ?? this.negativePrompt,
      x: clearPosition ? null : (x ?? this.x),
      y: clearPosition ? null : (y ?? this.y),
    );
  }

  Map<String, dynamic> toJson() => {
    'prompt': prompt,
    if (negativePrompt.isNotEmpty) 'negativePrompt': negativePrompt,
    if (x != null) 'x': x,
    if (y != null) 'y': y,
  };

  /// 解析角色；提示词为空或非法时返回 null，由调用方丢弃。
  static StoryboardPanelCharacter? fromJson(Object? value) {
    if (value is! Map) return null;
    final json = Map<String, dynamic>.from(value);
    final rawPrompt = json['prompt'];
    if (rawPrompt is! String) return null;
    final prompt = rawPrompt.length > maxPromptLength
        ? rawPrompt.substring(0, maxPromptLength)
        : rawPrompt;
    if (prompt.trim().isEmpty) return null;

    final rawNegative = json['negativePrompt'];
    final x = _readPosition(json['x']);
    final y = _readPosition(json['y']);

    return StoryboardPanelCharacter(
      prompt: prompt,
      negativePrompt: rawNegative is String
          ? (rawNegative.length > maxPromptLength
                ? rawNegative.substring(0, maxPromptLength)
                : rawNegative)
          : '',
      // 只给了一个轴的位置就视为未定位，避免出现半截坐标。
      x: x != null && y != null ? x : null,
      y: x != null && y != null ? y : null,
    );
  }

  static double? _readPosition(Object? value) {
    if (value is! num || !value.isFinite) return null;
    return value.toDouble().clamp(0.0, 1.0);
  }
}
