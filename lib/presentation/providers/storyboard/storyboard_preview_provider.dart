import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 正在生成的分镜的流式预览。
///
/// 生成 runner 每收到一帧预览就更新这里；画布上对应分镜（或背景）用
/// `matches` 判定后直接渲染字节。批量生成严格顺序执行，同一时刻最多只有
/// 一个对象在生成，所以不需要多份预览状态。
class StoryboardPreviewState {
  const StoryboardPreviewState({this.panelId, this.bytes, this.progress = 0});

  /// 正在生成的分镜 id；页面背景用
  /// [StoryboardGenerationPlanner.backgroundRequestId] 标记。
  final String? panelId;

  /// 当前预览帧；PNG/JPEG 字节，直接交给 `Image.memory`。
  final Uint8List? bytes;

  final double progress;

  bool matches(String id) => panelId == id && bytes != null && bytes!.isNotEmpty;
}

class StoryboardPreviewController extends Notifier<StoryboardPreviewState> {
  @override
  StoryboardPreviewState build() => const StoryboardPreviewState();

  void update({
    required String panelId,
    required Uint8List bytes,
    required double progress,
  }) {
    state = StoryboardPreviewState(
      panelId: panelId,
      bytes: bytes,
      progress: progress,
    );
  }

  void clear() {
    if (state.panelId == null && state.bytes == null) return;
    state = const StoryboardPreviewState();
  }
}

/// 分镜生成中的流式预览；非 autoDispose，无预览时状态为空。
final storyboardPreviewProvider =
    NotifierProvider<StoryboardPreviewController, StoryboardPreviewState>(
      StoryboardPreviewController.new,
    );
