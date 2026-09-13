import '../gallery/nai_image_metadata.dart';

/// 画布节点保存的可还原生成参数快照。
///
/// 只保存"把参数载回生成页"所需的字段，不保存模型能力位、参考图、角色
/// 等大对象；种子由所属节点单独持有，不在这里重复。
class CanvasNodeParams {
  final String prompt;
  final String negativePrompt;
  final String? model;
  final String? sampler;
  final int? steps;
  final double? scale;
  final int? width;
  final int? height;

  const CanvasNodeParams({
    this.prompt = '',
    this.negativePrompt = '',
    this.model,
    this.sampler,
    this.steps,
    this.scale,
    this.width,
    this.height,
  });

  /// 从图片自带的 NovelAI 元数据建立快照。
  factory CanvasNodeParams.fromImageMetadata(NaiImageMetadata metadata) {
    return CanvasNodeParams(
      prompt: metadata.prompt,
      negativePrompt: metadata.negativePrompt,
      model: metadata.model,
      sampler: metadata.sampler,
      steps: metadata.steps,
      scale: metadata.scale,
      width: metadata.width,
      height: metadata.height,
    );
  }

  bool get isEmpty =>
      prompt.isEmpty &&
      negativePrompt.isEmpty &&
      model == null &&
      sampler == null &&
      steps == null &&
      scale == null &&
      width == null &&
      height == null;

  Map<String, dynamic> toJson() => {
    'prompt': prompt,
    'negativePrompt': negativePrompt,
    if (model != null) 'model': model,
    if (sampler != null) 'sampler': sampler,
    if (steps != null) 'steps': steps,
    if (scale != null) 'scale': scale,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
  };

  static CanvasNodeParams fromJson(Map<String, dynamic> json) {
    double? readDouble(Object? value) => value is num ? value.toDouble() : null;
    int? readInt(Object? value) => value is num ? value.toInt() : null;
    String? readString(Object? value) =>
        value is String && value.isNotEmpty ? value : null;

    return CanvasNodeParams(
      prompt: json['prompt'] is String ? json['prompt'] as String : '',
      negativePrompt: json['negativePrompt'] is String
          ? json['negativePrompt'] as String
          : '',
      model: readString(json['model']),
      sampler: readString(json['sampler']),
      steps: readInt(json['steps']),
      scale: readDouble(json['scale']),
      width: readInt(json['width']),
      height: readInt(json['height']),
    );
  }
}
