/// NovelAI 预设回归守卫。
///
/// 两个真实风险：
///
/// 1. 配色漂移。这套主题的价值全在"和 novelai.net 一致"，色值一旦被顺手
///    微调就失去意义，且对比度守卫发现不了（改完仍然达标）。
/// 2. 枚举下标错位。主题选择按下标存进本地存储，往枚举中间插一个成员会让
///    老用户的选择整体偏移。这里把顺序钉死。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nai_launcher/presentation/themes/app_theme.dart';
import 'package:nai_launcher/presentation/themes/core/input_surface_style.dart';
import 'package:nai_launcher/presentation/themes/core/layered_surface_style.dart';
import 'package:nai_launcher/presentation/themes/theme_extension.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('NovelAI 预设', () {
    testWidgets('必须还原 NovelAI 图像页的背景阶梯与强调色', (tester) async {
      final colors = AppTheme.getTheme(
        AppStyle.novelAi,
        Brightness.dark,
      ).colorScheme;

      // 画布 bg0、区块 bg1、控件 bg2、浮层 bg3。
      expect(colors.surface, const Color(0xFF0E0F21));
      expect(colors.surfaceContainerLow, const Color(0xFF13152C));
      expect(colors.surfaceContainer, const Color(0xFF191B31));
      expect(colors.surfaceContainerHigh, const Color(0xFF22253F));
      expect(colors.onSurface, Colors.white);
      // textHeadings 的淡米色是 NovelAI 的强调色，不是紫色。
      expect(colors.primary, const Color(0xFFF5F3C2));
      expect(colors.onPrimary, colors.surface);
      // 错误与警告在 NovelAI 里同色。
      expect(colors.error, const Color(0xFFFF7878));
    });

    testWidgets('色面阶梯必须保持单调递增且可辨', (tester) async {
      final colors = AppTheme.getTheme(
        AppStyle.novelAi,
        Brightness.dark,
      ).colorScheme;

      final ladder = [
        colors.surface,
        sectionSurfaceColor(colors),
        controlSurfaceColor(colors),
        overlaySurfaceColor(colors),
      ];
      for (var i = 1; i < ladder.length; i++) {
        expect(
          ladder[i].computeLuminance(),
          greaterThan(ladder[i - 1].computeLuminance()),
          reason: '第 $i 级色面没有比上一级更亮',
        );
      }
    });

    // 本项目对普通卡片有全局"无常驻描边"不变量，NovelAI 的 1px 边框只能走
    // outline/outlineVariant。这两条是那套映射的实际落点，断了边框就没了。
    testWidgets('NovelAI 的边框色必须落到输入框与语义 token 上', (tester) async {
      final theme = AppTheme.getTheme(AppStyle.novelAi, Brightness.dark);
      final colors = theme.colorScheme;

      expect(colors.outlineVariant, const Color(0xFF565D80));
      expect(theme.appTheme.borderColor, colors.outlineVariant);

      final expectedResting = inputSurfaceBorder(
        colors,
        BorderRadius.circular(4),
      ).borderSide;
      final resting = theme.inputDecorationTheme.enabledBorder;
      expect(resting, isA<OutlineInputBorder>());
      expect(
        (resting! as OutlineInputBorder).borderSide.color,
        expectedResting.color,
      );
      expect(expectedResting.style, BorderStyle.solid);
      expect(expectedResting.width, 1);

      // 聚焦态换成米色描边，和 NovelAI 的高亮一致。
      final focused =
          (theme.inputDecorationTheme.focusedBorder! as OutlineInputBorder)
              .borderSide
              .color;
      expect(focused, colors.primary.withValues(alpha: 0.68));
    });

    test('新预设必须追加在枚举末尾，不得移动已有下标', () {
      expect(AppStyle.novelAi.index, AppStyle.values.length - 1);
      expect(AppStyle.grungeCollage.index, 0);
      expect(AppStyle.system.index, 15);
    });
  });
}
