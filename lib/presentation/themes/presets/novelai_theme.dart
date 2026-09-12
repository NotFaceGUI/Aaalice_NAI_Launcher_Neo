/// NovelAI Theme Preset
///
/// 复刻 novelai.net 图像生成页（/image）的应用内主题 `NovelAI Dark`：
/// 深蓝画布 #0E0F21、面板 #191B31、冷蓝灰细边框 #22253F、米色强调 #F5F3C2。
/// 配色来源与映射说明见 [NovelAiPalette]。
library;

import 'package:flutter/material.dart';
import 'package:nai_launcher/presentation/themes/core/theme_composer.dart';
import 'package:nai_launcher/presentation/themes/modules/color/palettes/novelai_palette.dart';
import 'package:nai_launcher/presentation/themes/modules/typography/presets/novelai_typography.dart';
import 'package:nai_launcher/presentation/themes/modules/shape/presets/novelai_shapes.dart';
import 'package:nai_launcher/presentation/themes/modules/motion/presets/snappy_motion.dart';

/// NovelAI theme configuration.
class NovelAiTheme {
  const NovelAiTheme._();

  static const _composer = ThemeComposer(
    color: NovelAiPalette(),
    typography: NovelAiTypography(),
    shape: NovelAiShapes(),
    motion: SnappyMotion(),
  );

  static ThemeData get light => _composer.buildTheme(Brightness.light);
  static ThemeData get dark => _composer.buildTheme(Brightness.dark);
  static bool get supportsDarkMode => true;
  static String get displayName => 'NovelAI';
  static String get description => 'NovelAI 图像生成页配色，深蓝底、米色强调与冷灰细边框';
}
