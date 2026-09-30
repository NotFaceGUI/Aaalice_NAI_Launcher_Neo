import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/camera_angle/camera_angle_pose.dart';

void main() {
  group('CameraAnglePose', () {
    test('方位分档覆盖正面、左右侧面与背面', () {
      expect(CameraAnglePose.neutral.azimuthBucket, CameraAzimuth.front);
      expect(
        const CameraAnglePose(azimuth: 0.2).azimuthBucket,
        CameraAzimuth.front,
      );
      expect(
        const CameraAnglePose(azimuth: -0.45).azimuthBucket,
        CameraAzimuth.left,
      );
      expect(
        const CameraAnglePose(azimuth: 0.45).azimuthBucket,
        CameraAzimuth.right,
      );
      expect(
        const CameraAnglePose(azimuth: -1).azimuthBucket,
        CameraAzimuth.back,
      );
      expect(
        const CameraAnglePose(azimuth: 0.9).azimuthBucket,
        CameraAzimuth.back,
      );
    });

    test('俯仰分档覆盖俯视、平视与仰视', () {
      expect(
        const CameraAnglePose(elevation: 0.5).elevationBucket,
        CameraElevation.above,
      );
      expect(
        const CameraAnglePose(elevation: 0.1).elevationBucket,
        CameraElevation.eye,
      );
      expect(
        const CameraAnglePose(elevation: -0.5).elevationBucket,
        CameraElevation.below,
      );
    });

    test('取景六档依次覆盖特写到远景', () {
      const expectations = <(double, CameraShot)>[
        (1.0, CameraShot.closeUp),
        (0.4, CameraShot.portrait),
        (0.0, CameraShot.upperBody),
        (-0.25, CameraShot.cowboyShot),
        (-0.5, CameraShot.fullBody),
        (-1.0, CameraShot.wideShot),
      ];
      for (final (distance, shot) in expectations) {
        expect(
          CameraAnglePose(distance: distance).shotBucket,
          shot,
          reason: 'distance=$distance',
        );
      }
    });

    test('正面平视的中性姿态只输出取景标签', () {
      expect(CameraAnglePose.neutral.tags, ['upper_body']);
    });

    test('侧面与俯视组合输出方位和俯仰标签', () {
      const pose = CameraAnglePose(
        azimuth: -0.45,
        elevation: 0.6,
        distance: -0.5,
      );

      expect(pose.tags, ['from_side', 'from_above', 'full_body']);
    });

    test('背面机位使用 from_behind，左右共用 from_side', () {
      expect(const CameraAnglePose(azimuth: 1).azimuthTag, 'from_behind');
      expect(
        const CameraAnglePose(azimuth: 0.45).azimuthTag,
        const CameraAnglePose(azimuth: -0.45).azimuthTag,
      );
    });

    test('倾斜超过死区才输出 dutch_angle', () {
      expect(const CameraAnglePose(roll: 0.1).rollTag, isNull);
      expect(const CameraAnglePose(roll: -0.1).rollTag, isNull);
      expect(const CameraAnglePose(roll: 0.3).rollTag, 'dutch_angle');
      expect(const CameraAnglePose(roll: -0.3).rollTag, 'dutch_angle');
    });

    test('copyWith 把越界分量夹在 -1 到 1 之间', () {
      final pose = CameraAnglePose.neutral.copyWith(
        azimuth: 4,
        elevation: -9,
        distance: 2,
        roll: -3,
      );

      expect(pose.azimuth, 1);
      expect(pose.elevation, -1);
      expect(pose.distance, 1);
      expect(pose.roll, -1);
      expect(pose.copyWith(azimuth: 12).azimuth, 1);
      expect(pose.copyWith(azimuth: -0.4).azimuth, -0.4);
    });

    test('角度换算与可视化范围一致', () {
      expect(CameraAnglePose.neutral.azimuthAngle, 0);
      expect(
        const CameraAnglePose(azimuth: 1).azimuthAngle,
        closeTo(3.1415926535, 1e-6),
      );
      // 俯仰限制在 ±72°，避免相机与极点重合
      expect(
        const CameraAnglePose(elevation: 1).elevationAngle,
        closeTo(1.2566370614, 1e-6),
      );
    });

    test('JSON 往返保持相等', () {
      const pose = CameraAnglePose(
        azimuth: 0.35,
        elevation: -0.55,
        distance: 0.75,
        roll: 0.25,
      );

      expect(CameraAnglePose.fromJson(pose.toJson()), pose);
    });

    test('缺失或非法字段回落到中性值并夹取范围', () {
      final pose = CameraAnglePose.fromJson({
        'azimuth': 5,
        'elevation': 'bogus',
        'distance': null,
      });

      expect(pose.azimuth, 1);
      expect(pose.elevation, 0);
      expect(pose.distance, 0);
      expect(pose.roll, 0);
    });

    test('isNeutral 只认同默认姿态', () {
      expect(CameraAnglePose.neutral.isNeutral, isTrue);
      expect(const CameraAnglePose(roll: 0.2).isNeutral, isFalse);
    });
  });
}
