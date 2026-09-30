import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/utils/camera_angle_prompt_inserter.dart';
import 'package:nai_launcher/core/utils/nai_prompt_formatter.dart';
import 'package:nai_launcher/data/models/camera_angle/camera_angle_pose.dart';
import 'package:nai_launcher/data/models/camera_angle/camera_angle_preset.dart';

void main() {
  group('CameraAnglePromptInserter.insert', () {
    test('插入到已有提示词的开头', () {
      expect(
        CameraAnglePromptInserter.insert('1girl, black_hair', 'upper_body'),
        'upper_body, 1girl, black_hair',
      );
    });

    test('空提示词直接得到片段', () {
      expect(CameraAnglePromptInserter.insert('', 'upper_body'), 'upper_body');
      expect(
        CameraAnglePromptInserter.insert('   \n ', 'upper_body'),
        'upper_body',
      );
    });

    test('保留首行缩进与空行', () {
      expect(
        CameraAnglePromptInserter.insert('\n\n  location, 1girl', 'from_above'),
        '\n\n  from_above, location, 1girl',
      );
    });

    test('片段已完整存在时不重复插入', () {
      const prompt = 'from_above, 1girl';
      expect(
        CameraAnglePromptInserter.insert(prompt, 'from_above'),
        prompt,
      );
    });

    test('空片段不改变提示词', () {
      expect(CameraAnglePromptInserter.insert('1girl', '  '), '1girl');
    });
  });

  group('CameraAnglePromptInserter.remove', () {
    test('移除前置片段并清理逗号', () {
      expect(
        CameraAnglePromptInserter.remove(
          'from_above, 1girl, black_hair',
          'from_above',
        ),
        '1girl, black_hair',
      );
    });

    test('片段在末尾时清理前一个逗号', () {
      expect(
        CameraAnglePromptInserter.remove('1girl, from_above', 'from_above'),
        '1girl',
      );
    });

    test('多标签片段在中间时保持两侧内容', () {
      expect(
        CameraAnglePromptInserter.remove(
          '1girl, from_above, upper_body, location',
          'from_above, upper_body',
        ),
        '1girl, location',
      );
    });

    test('用户改写过的片段不会被模糊删除', () {
      const prompt = '1girl, from side, black_hair';
      expect(
        CameraAnglePromptInserter.remove(prompt, 'from_above'),
        prompt,
      );
    });

    test('空片段不改变提示词', () {
      expect(CameraAnglePromptInserter.remove('1girl', ''), '1girl');
    });

    test('插入后移除可以往返回到原文', () {
      const prompt = '\n\n  location, 1girl(black_hair), absurdres';
      const fragment = 'from_side, from_below, cowboy_shot';

      final inserted = CameraAnglePromptInserter.insert(prompt, fragment);
      expect(inserted.startsWith('\n\n  '), isTrue);
      expect(CameraAnglePromptInserter.remove(inserted, fragment), prompt);
    });
  });

  group('与 NAI 格式化配合', () {
    test('带权重的片段原文在自动格式化后保持不变，仍可被精确移除', () {
      const prompt = '1girl, black hair, looking at viewer';
      const preset = CameraAnglePreset(
        pose: CameraAnglePose(azimuth: 0.45, elevation: -0.5, distance: -0.5),
        strength: 1.3,
      );

      final inserted = CameraAnglePromptInserter.insert(
        prompt,
        preset.promptFragment,
      );
      final formatted = NaiPromptFormatter.format(inserted);

      expect(formatted.contains(preset.promptFragment), isTrue);
      expect(
        CameraAnglePromptInserter.remove(formatted, preset.promptFragment),
        '1girl, black_hair, looking_at_viewer',
      );
    });

    test('纯标签片段经过格式化后依然可被精确移除', () {
      const preset = CameraAnglePreset(
        pose: CameraAnglePose(azimuth: -0.45, distance: 1),
      );

      final inserted = CameraAnglePromptInserter.insert(
        '1girl, black hair',
        preset.promptFragment,
      );
      final formatted = NaiPromptFormatter.format(inserted);

      expect(
        CameraAnglePromptInserter.remove(formatted, preset.promptFragment),
        '1girl, black_hair',
      );
    });
  });
}
