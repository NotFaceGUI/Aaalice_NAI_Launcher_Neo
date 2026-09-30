import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/camera_angle/camera_angle_pose.dart';
import 'package:nai_launcher/data/models/camera_angle/camera_angle_preset.dart';

void main() {
  group('CameraAnglePreset', () {
    test('中性姿态且强度为 1 时输出纯标签', () {
      const preset = CameraAnglePreset(
        pose: CameraAnglePose.neutral,
        outputMode: CameraAngleOutputMode.tags,
      );

      expect(preset.promptFragment(), 'upper_body');
    });

    test('同一分档内角度越大权重越高', () {
      const slight = CameraAnglePreset(
        pose: CameraAnglePose(azimuth: 0.3),
        outputMode: CameraAngleOutputMode.tags,
      );
      const strong = CameraAnglePreset(
        pose: CameraAnglePose(azimuth: 0.62),
        outputMode: CameraAngleOutputMode.tags,
      );

      expect(slight.promptFragment(), '1.05::from_side::, upper_body');
      expect(strong.promptFragment(), '1.26::from_side::, upper_body');
    });

    test('俯仰与倾斜同样随幅度加权', () {
      const mild = CameraAnglePreset(
        pose: CameraAnglePose(elevation: -0.3, roll: 0.2),
        outputMode: CameraAngleOutputMode.tags,
      );
      const strong = CameraAnglePreset(
        pose: CameraAnglePose(elevation: -0.9, roll: 0.9),
        outputMode: CameraAngleOutputMode.tags,
      );

      // 轻微倾斜落在权重死区内，保持纯标签，避免无意义的 1.04::dutch_angle::
      expect(mild.promptFragment(), '1.05::from_below::, upper_body, dutch_angle');
      expect(strong.promptFragment(), '1.35::from_below::, upper_body, 1.44::dutch_angle::');
    });

    test('自然语言描述给出标签表达不了的细节', () {
      const preset = CameraAnglePreset(
        pose: CameraAnglePose(
          azimuth: -0.45,
          elevation: 0.6,
          distance: 0.4,
          roll: 0.75,
        ),
        outputMode: CameraAngleOutputMode.description,
      );

      expect(
        preset.promptFragment(),
        'viewed from the left and from a slightly high angle, '
        'a close portrait, tilted about 15° to the right (dutch angle)',
      );
    });

    test('输出形式决定标签与描述的组合', () {
      const pose = CameraAnglePose(distance: 1);
      const tags = CameraAnglePreset(
        pose: pose,
        outputMode: CameraAngleOutputMode.tags,
      );
      const both = CameraAnglePreset(pose: pose);
      const description = CameraAnglePreset(
        pose: pose,
        outputMode: CameraAngleOutputMode.description,
      );

      expect(tags.promptFragment(), 'close-up');
      expect(
        both.promptFragment(),
        'close-up, viewed from the front, a tight close-up',
      );
      expect(
        description.promptFragment(),
        'viewed from the front, a tight close-up',
      );
    });

    test('V3 降级时只输出标签', () {
      const preset = CameraAnglePreset(pose: CameraAnglePose(distance: 1));

      expect(preset.promptFragment(allowDescription: false), 'close-up');
    });

    test('强度不等于 1 时使用 V4 数值强调语法', () {
      const preset = CameraAnglePreset(
        pose: CameraAnglePose(azimuth: 0.45, distance: 0),
        strength: 1.3,
      );

      expect(
        preset.promptFragment(),
        '1.49::from_side::, 1.3::upper_body::, '
        'viewed from the right, an upper-body framing',
      );
    });

    test('低于 1 的强度同样输出小数权重', () {
      const preset = CameraAnglePreset(
        pose: CameraAnglePose(distance: 1),
        strength: 0.7,
      );

      expect(
        preset.promptFragment(),
        '0.7::close-up::, viewed from the front, a tight close-up',
      );
    });

    test('强度接近 1 时不写权重语法', () {
      const preset = CameraAnglePreset(
        pose: CameraAnglePose(distance: 1),
        strength: 1.04,
      );

      expect(
        preset.promptFragment(),
        'close-up, viewed from the front, a tight close-up',
      );
    });

    test('formatWeight 去掉多余小数位', () {
      expect(CameraAnglePreset.formatWeight(2), '2');
      expect(CameraAnglePreset.formatWeight(1.5), '1.5');
      expect(CameraAnglePreset.formatWeight(1.25), '1.25');
      expect(CameraAnglePreset.formatWeight(0.7), '0.7');
    });

    test('镜头语言按固定顺序追加在机位标签之后', () {
      const preset = CameraAnglePreset(
        pose: CameraAnglePose(distance: 0),
        effects: {
          CameraLensEffect.fisheye,
          CameraLensEffect.lookingAtViewer,
        },
      );

      expect(preset.plainTags, ['upper_body', 'looking_at_viewer', 'fisheye']);
    });

    test('标出的镜头语言都在 Danbooru 词表里，且不含空格', () {
      for (final effect in CameraLensEffect.values) {
        expect(effect.tag, isNotEmpty);
        expect(effect.tag.contains(' '), isFalse, reason: effect.tag);
        expect(effect.tag.contains('-') && effect.tag != 'close-up', isFalse);
      }
    });

    test('toggleEffect 可以来回切换', () {
      const preset = CameraAnglePreset();
      final enabled = preset.toggleEffect(CameraLensEffect.depthOfField);

      expect(enabled.effects, {CameraLensEffect.depthOfField});
      expect(
        enabled.toggleEffect(CameraLensEffect.depthOfField).effects,
        <CameraLensEffect>{},
      );
    });

    test('JSON 往返保持姿态、镜头语言、强度与开关', () {
      const preset = CameraAnglePreset(
        pose: CameraAnglePose(azimuth: -0.5, elevation: 0.4, roll: 0.3),
        effects: {CameraLensEffect.motionBlur, CameraLensEffect.lensFlare},
        strength: 1.2,
        enabled: true,
      );

      expect(CameraAnglePreset.fromJson(preset.toJson()), preset);
    });

    test('未知镜头语言与越界强度被丢弃或夹取', () {
      final preset = CameraAnglePreset.fromJson({
        'effects': ['fisheye', 'not_a_tag', 42],
        'strength': 9.0,
        'enabled': 'yes',
      });

      expect(preset.effects, {CameraLensEffect.fisheye});
      expect(preset.strength, CameraAnglePreset.maxStrength);
      expect(preset.enabled, isFalse);
      expect(preset.pose, CameraAnglePose.neutral);
    });
  });
}
