import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/storage/local_storage_service.dart';
import '../generation/generation_center_mode_provider.dart';

part 'canvas_visibility_provider.g.dart';

/// 无限画布是否占据生成页的中央工作区。
///
/// 这是 [generationCenterModeControllerProvider] 的派生视图：中央工作区现在有
/// 预览、画布、分镜三种模式，但画布侧的调用方（生成桥、画布工具条、把种子
/// 固定到画布的动作）只关心"画布是不是当前视图"，保持这个 bool 门面可以让
/// 它们不需要知道分镜的存在。
///
/// 开关状态由模式 provider 统一持久化，这里不再单独写存储。
@Riverpod(keepAlive: true)
class InfiniteCanvasVisibility extends _$InfiniteCanvasVisibility {
  @override
  bool build() {
    return ref.watch(generationCenterModeControllerProvider) ==
        GenerationCenterMode.canvas;
  }

  void open() => ref
      .read(generationCenterModeControllerProvider.notifier)
      .show(GenerationCenterMode.canvas);

  void close() => ref
      .read(generationCenterModeControllerProvider.notifier)
      .showPreview();

  void toggle() => state ? close() : open();
}

/// 画布打开时，生成完成的结果是否自动成为画布节点。
@Riverpod(keepAlive: true)
class CanvasAutoImport extends _$CanvasAutoImport {
  @override
  bool build() =>
      ref.watch(localStorageServiceProvider).getInfiniteCanvasAutoImport();

  Future<void> set(bool value) async {
    if (state == value) return;
    state = value;
    await ref
        .read(localStorageServiceProvider)
        .setInfiniteCanvasAutoImport(value);
  }

  void toggle() => unawaited(set(!state));
}
