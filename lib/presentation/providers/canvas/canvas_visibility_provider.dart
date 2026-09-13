import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/storage/local_storage_service.dart';
import '../character_position_canvas_provider.dart';

part 'canvas_visibility_provider.g.dart';

/// 无限画布是否占据生成页的中央工作区。
///
/// 与"角色位置画布"互斥：两者都占用同一块中央区域，而角色位置画布是短暂
/// 的专注操作，打开无限画布时先让它退出。反向不需要处理——角色位置画布的
/// 入口只在图像预览区可见，无限画布打开时预览区并不呈现。
///
/// 开关状态存本地设置：重启后回到上次的工作视图，但这是设备专属状态，
/// 不进入画布 sidecar 与云同步。
@Riverpod(keepAlive: true)
class InfiniteCanvasVisibility extends _$InfiniteCanvasVisibility {
  @override
  bool build() {
    return ref.watch(localStorageServiceProvider).getInfiniteCanvasOpen();
  }

  void open() => _apply(true);

  void close() => _apply(false);

  void toggle() => _apply(!state);

  void _apply(bool value) {
    if (state == value) return;
    if (value) {
      final characterCanvas = ref.read(
        characterPositionCanvasProvider.notifier,
      );
      if (ref.read(characterPositionCanvasProvider)) {
        characterCanvas.close();
      }
    }
    state = value;
    unawaited(
      ref.read(localStorageServiceProvider).setInfiniteCanvasOpen(value),
    );
  }
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
