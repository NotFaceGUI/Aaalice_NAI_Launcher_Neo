import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/storage/local_storage_service.dart';
import '../../core/utils/app_logger.dart';
import '../../data/models/camera_angle/camera_angle_pose.dart';
import '../../data/models/camera_angle/camera_angle_preset.dart';

part 'camera_angle_provider.g.dart';

/// 视角控制状态：预设本身，以及当前已经写进提示词的片段。
///
/// [appliedFragment] 是运行时账本，用来在姿态变化或关闭时精确移除上一次插入
/// 的内容；它不参与持久化，避免用户在提示词里手改后仍被自动回滚。
typedef CameraAngleState = ({CameraAnglePreset preset, String appliedFragment});

/// 视角控制预设
///
/// 全局偏好并跨会话保留，同时跟随“提示词与标签”云同步分类；
/// 预设只描述要写进提示词的标签，不直接持有提示词文本。
@Riverpod(keepAlive: true)
class CameraAnglePresetNotifier extends _$CameraAnglePresetNotifier {
  @override
  CameraAngleState build() {
    final preset = _loadPreset();
    return (
      preset: preset,
      // 已启用的预设视为已经写进提示词：启动时不再重复插入，
      // 也不因为提示词被其他入口改写而擅自删除用户内容。
      appliedFragment: preset.enabled ? preset.promptFragment : '',
    );
  }

  CameraAnglePreset _loadPreset() {
    final storage = ref.read(localStorageServiceProvider);
    final raw = storage.getCameraAnglePresetJson();
    if (raw == null || raw.isEmpty) return const CameraAnglePreset();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const CameraAnglePreset();
      return CameraAnglePreset.fromJson(Map<String, Object?>.from(decoded));
    } catch (error, stack) {
      AppLogger.e(
        'Failed to load camera angle preset: $error',
        error,
        stack,
        'CameraAngleProvider',
      );
      return const CameraAnglePreset();
    }
  }

  /// 更新姿态；姿态不变时不写入存储。
  Future<void> setPose(CameraAnglePose pose) =>
      _update(state.preset.copyWith(pose: pose));

  /// 切换单个镜头语言标签。
  Future<void> toggleEffect(CameraLensEffect effect) =>
      _update(state.preset.toggleEffect(effect));

  /// 设置提示词强度。
  Future<void> setStrength(double strength) =>
      _update(state.preset.copyWith(strength: strength));

  /// 开启或关闭视角提示词。
  Future<void> setEnabled(bool enabled) =>
      _update(state.preset.copyWith(enabled: enabled));

  /// 回到默认姿态，保留镜头语言、强度与开关状态。
  Future<void> resetPose() =>
      _update(state.preset.copyWith(pose: CameraAnglePose.neutral));

  /// 记录已经写入提示词的片段。
  ///
  /// 由提示词同步流程在真正写入后调用，让下一次变更能精确移除旧内容。
  void markApplied(String fragment) {
    if (state.appliedFragment == fragment) return;
    state = (preset: state.preset, appliedFragment: fragment);
  }

  Future<void> _update(CameraAnglePreset next) async {
    if (next == state.preset) return;
    state = (preset: next, appliedFragment: state.appliedFragment);
    try {
      await ref
          .read(localStorageServiceProvider)
          .setCameraAnglePresetJson(jsonEncode(next.toJson()));
    } catch (error, stack) {
      AppLogger.e(
        'Failed to save camera angle preset: $error',
        error,
        stack,
        'CameraAngleProvider',
      );
    }
  }
}
