/// 分镜的生成状态。
///
/// 只描述"这个分镜有没有可用的图"，不描述队列细节；队列状态由队列本身
/// 持有，这里保存的是回填后的事实。
enum StoryboardPanelStatus {
  /// 还没有图。
  empty,

  /// 已入队，等待生成。
  queued,

  /// 正在生成。
  generating,

  /// 已有至少一张图。
  done,

  /// 最近一次生成失败。
  failed;

  bool get isBusy =>
      this == StoryboardPanelStatus.queued || this == StoryboardPanelStatus.generating;

  static StoryboardPanelStatus fromStorage(
    Object? value, {
    StoryboardPanelStatus fallback = StoryboardPanelStatus.empty,
  }) {
    if (value is! String) return fallback;
    for (final status in values) {
      if (status.name == value) return status;
    }
    return fallback;
  }
}
