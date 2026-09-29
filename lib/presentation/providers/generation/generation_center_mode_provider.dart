import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/local_storage_service.dart';
import '../character_position_canvas_provider.dart';

/// 生成页中央工作区正在呈现的内容。
///
/// 三种模式互斥地占据同一块区域：图像预览、无限画布、分镜。它们各自的子树
/// 在首次进入后保持存活，切换只改变可见性与水平位移。
enum GenerationCenterMode {
  /// 常规图像预览与流式生成过程。
  preview,

  /// 无限画布工作台。
  canvas,

  /// 漫画分镜页编辑器。
  storyboard;

  static GenerationCenterMode fromStorage(Object? value) {
    if (value is! String) return GenerationCenterMode.preview;
    for (final mode in values) {
      if (mode.name == value) return mode;
    }
    return GenerationCenterMode.preview;
  }
}

/// 中央工作区模式。
///
/// 状态存本地设置：重启后回到上次的工作视图，但这是设备专属状态，
/// 不进入任何 sidecar 与云同步。
///
/// 与"角色位置画布"互斥：两者都占用同一块中央区域，而角色位置画布是短暂
/// 的专注操作，进入画布或分镜时先让它退出。反向不需要处理——角色位置画布的
/// 入口只在图像预览区可见，其它模式打开时预览区并不呈现。
class GenerationCenterModeController extends Notifier<GenerationCenterMode> {
  @override
  GenerationCenterMode build() {
    final storage = ref.watch(localStorageServiceProvider);
    final stored = storage.getGenerationCenterMode();
    if (stored != null) return GenerationCenterMode.fromStorage(stored);
    // 首次读取新键：按升级前的开关键还原当时的工作视图，之后只认新键。
    return storage.getInfiniteCanvasOpen()
        ? GenerationCenterMode.canvas
        : GenerationCenterMode.preview;
  }

  void show(GenerationCenterMode mode) {
    if (state == mode) return;
    if (mode != GenerationCenterMode.preview) {
      final characterCanvas = ref.read(
        characterPositionCanvasProvider.notifier,
      );
      if (ref.read(characterPositionCanvasProvider)) {
        characterCanvas.close();
      }
    }
    state = mode;
    unawaited(
      ref.read(localStorageServiceProvider).setGenerationCenterMode(mode.name),
    );
  }

  void showPreview() => show(GenerationCenterMode.preview);
}

/// 中央工作区当前模式。
///
/// keepAlive（非 autoDispose）：应用生命周期内保持同一个实例，切换视图或
/// 窗口最小化都不会重置。
final generationCenterModeControllerProvider =
    NotifierProvider<GenerationCenterModeController, GenerationCenterMode>(
      GenerationCenterModeController.new,
    );
