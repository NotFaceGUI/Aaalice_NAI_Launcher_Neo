/// NovelAI 官网的 Model Mode（Anime / Furry）。
///
/// 该选项不进入 API 请求体：官网只在客户端把 `fur dataset, ` 数据集标签加到
/// 正向提示词最前面，Anime 模式不加任何内容。因此提示词文本本身就携带了模式
/// 信息，导入官网图片时可以据此还原。
///
/// 只有 V4、V4.5 与 V5 家族支持它（网页端能力位 `hasFurryMode`），更早的
/// 模型没有这个选项。
enum ModelMode {
  anime,
  furry;

  /// 官网 Furry 模式注入的数据集标签。
  static const String furryDatasetTag = 'fur dataset';

  /// 官网同样视为已带数据集标签、不再重复注入的标签。
  static const String backgroundDatasetTag = 'background dataset';

  /// 官网注入的完整前缀（含分隔符）。
  static const String furryDatasetPrefix = '$furryDatasetTag, ';

  /// 从持久化字段或元数据还原，未知值按 Anime 处理。
  static ModelMode fromName(String? value) =>
      value == furry.name ? furry : anime;

  /// 提示词是否带官网的 Furry 数据集前缀。
  static bool hasDatasetTag(String prompt) =>
      prompt.startsWith(furryDatasetPrefix);

  /// 去掉 Furry 数据集前缀，用于还原用户原始提示词。
  static String stripDatasetTag(String prompt) => hasDatasetTag(prompt)
      ? prompt.substring(furryDatasetPrefix.length)
      : prompt;

  /// 按官网规则追加数据集标签。
  ///
  /// 非 Furry 模式不加；提示词已经以 `fur dataset` 或 `background dataset`
  /// 开头时不重复添加——官网对这两个前缀的判定不含逗号。
  String applyDatasetTag(String prompt) {
    if (this != ModelMode.furry) return prompt;
    if (prompt.startsWith(furryDatasetTag) ||
        prompt.startsWith(backgroundDatasetTag)) {
      return prompt;
    }
    return '$furryDatasetPrefix$prompt';
  }
}
