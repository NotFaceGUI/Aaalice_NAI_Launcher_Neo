import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/data/models/camera_angle/camera_angle_pose.dart';
import 'package:nai_launcher/data/models/camera_angle/camera_angle_preset.dart';
import 'package:nai_launcher/presentation/providers/camera_angle_provider.dart';

void main() {
  group('CameraAnglePresetNotifier', () {
    ProviderContainer containerWith(_FakeStorage storage) {
      final container = ProviderContainer(
        overrides: [localStorageServiceProvider.overrideWith((ref) => storage)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('未设置时为中性姿态、未启用且没有已写入片段', () {
      final container = containerWith(_FakeStorage());
      final state = container.read(cameraAnglePresetNotifierProvider);

      expect(state.preset.pose, CameraAnglePose.neutral);
      expect(state.preset.enabled, isFalse);
      expect(state.preset.promptFragment, 'upper_body');
      expect(state.appliedFragment, isEmpty);
    });

    test('读取已保存的预设', () {
      final container = containerWith(
        _FakeStorage()
          ..json = jsonEncode(
            const CameraAnglePreset(
              pose: CameraAnglePose(azimuth: 0.45, roll: 0.4),
              effects: {CameraLensEffect.fisheye},
              strength: 1.2,
            ).toJson(),
          ),
      );
      final preset = container.read(cameraAnglePresetNotifierProvider).preset;

      expect(preset.pose.azimuth, 0.45);
      expect(preset.effects, {CameraLensEffect.fisheye});
      expect(preset.strength, 1.2);
    });

    test('已启用的预设视为已写入，启动时不会重复插入', () {
      final container = containerWith(
        _FakeStorage()
          ..json = jsonEncode(
            const CameraAnglePreset(
              pose: CameraAnglePose(distance: 1),
              enabled: true,
            ).toJson(),
          ),
      );
      final state = container.read(cameraAnglePresetNotifierProvider);

      expect(state.appliedFragment, state.preset.promptFragment);
    });

    test('损坏的 JSON 回落到默认预设', () {
      final container = containerWith(_FakeStorage()..json = '{not json');

      final state = container.read(cameraAnglePresetNotifierProvider);

      expect(state.preset, const CameraAnglePreset());
      expect(state.appliedFragment, isEmpty);
    });

    test('姿态、镜头语言与强度都会写回存储', () async {
      final storage = _FakeStorage();
      final container = containerWith(storage);
      final notifier = container.read(
        cameraAnglePresetNotifierProvider.notifier,
      );

      await notifier.setPose(const CameraAnglePose(azimuth: -0.45));
      await notifier.toggleEffect(CameraLensEffect.motionBlur);
      await notifier.setStrength(1.4);

      final saved = CameraAnglePreset.fromJson(
        Map<String, Object?>.from(jsonDecode(storage.json!) as Map),
      );
      expect(saved.pose.azimuth, -0.45);
      expect(saved.effects, {CameraLensEffect.motionBlur});
      expect(saved.strength, 1.4);
      expect(storage.writeCount, 3);
    });

    test('重复设置同一姿态不写盘', () async {
      final storage = _FakeStorage();
      final container = containerWith(storage);
      final notifier = container.read(
        cameraAnglePresetNotifierProvider.notifier,
      );

      await notifier.setPose(CameraAnglePose.neutral);

      expect(storage.writeCount, 0);
    });

    test('markApplied 只更新运行时账本，不写盘', () {
      final storage = _FakeStorage();
      final container = containerWith(storage);
      final notifier = container.read(
        cameraAnglePresetNotifierProvider.notifier,
      );

      notifier.markApplied('from_above, close-up');

      expect(
        container.read(cameraAnglePresetNotifierProvider).appliedFragment,
        'from_above, close-up',
      );
      expect(storage.writeCount, 0);
    });

    test('关闭开关时保留已写入片段，等待提示词同步移除', () async {
      final container = containerWith(
        _FakeStorage()
          ..json = jsonEncode(
            const CameraAnglePreset(
              pose: CameraAnglePose(distance: 1),
              enabled: true,
            ).toJson(),
          ),
      );
      final notifier = container.read(
        cameraAnglePresetNotifierProvider.notifier,
      );

      await notifier.setEnabled(false);

      final state = container.read(cameraAnglePresetNotifierProvider);
      expect(state.preset.enabled, isFalse);
      expect(state.appliedFragment, 'close-up');
    });
  });
}

class _FakeStorage extends LocalStorageService {
  String? json;
  int writeCount = 0;

  @override
  String? getCameraAnglePresetJson() => json;

  @override
  Future<void> setCameraAnglePresetJson(String value) async {
    json = value;
    writeCount++;
  }
}
