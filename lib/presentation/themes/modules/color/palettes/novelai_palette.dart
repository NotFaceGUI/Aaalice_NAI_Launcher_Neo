/// NovelAI Palette - NovelAI 图像生成页配色
///
/// 取自 novelai.net 前端的 `NovelAI Dark` 主题对象（应用内实际生效的那一套，
/// 不是营销首页那套紫色渐变）：
///
/// - 背景四级阶梯 `bg0`~`bg3`：#0E0F21 / #13152C / #191B31 / #22253F
/// - 标题与强调色 `textHeadings`：#F5F3C2（淡米色，不是紫色；NovelAI 实心按钮
///   就是米底深字）
/// - 正文 `textMain`：#FFFFFF，次级文字 `textPlaceholder`：#FFFFFF77
/// - 警告/错误 `warning`：#FF7878（NovelAI 错误与警告同色）
/// - 交互语义色：用户文本 #9CDCFF、编辑文本 #F4C7FF
///
/// 边界色沿用 `bg3` #22253F。NovelAI 的面板确实带 1px 描边，而本项目
/// [ThemeComposer] 对普通卡片有全局"无常驻描边"不变量（对比度守卫会逐一断言），
/// 因此这里的边框通过 [ColorScheme.outline] / [ColorScheme.outlineVariant] 表达：
/// 输入框静息边框、`InputSurfaceContainer` 描边、分隔线都会据此渲染出
/// NovelAI 那种冷蓝灰细线，聚焦态则换成米色描边。
///
/// 次级文字没有直接照抄 47% 白：#FFFFFF77 叠在 #0E0F21 上只有约 4.8:1，
/// 勉强压线；这里改用同色温的 #9BA0B8，达到约 7.3:1，观感仍是那块灰蓝次级色。
library;

import 'package:flutter/material.dart';
import 'package:nai_launcher/presentation/themes/modules/color/color_module.dart';

/// NovelAI 图像生成页配色 - 深蓝底 + 米色强调。
class NovelAiPalette extends BaseColorModule {
  const NovelAiPalette();

  // 背景阶梯（NovelAI 前端 bg0~bg3）
  static const Color _bg0 = Color(0xFF0E0F21);
  static const Color _bg1 = Color(0xFF13152C);
  static const Color _bg2 = Color(0xFF191B31);
  static const Color _bg3 = Color(0xFF22253F);
  // bg3 之上补一级：NovelAI 只有四级背景，而 Material 需要到 Highest。
  // 仅做同族中性提亮，不引入任何强调色。
  static const Color _bg4 = Color(0xFF262A4A);

  // 强调色（textHeadings / textUser / textEdit）
  static const Color _cream = Color(0xFFF5F3C2);
  static const Color _userText = Color(0xFF9CDCFF);
  static const Color _editText = Color(0xFFF4C7FF);
  static const Color _warning = Color(0xFFFF7878);

  @override
  ColorScheme get lightScheme => darkScheme; // NovelAI 图像页只有深色

  @override
  ColorScheme get darkScheme => const ColorScheme.dark(
    primary: _cream,
    onPrimary: _bg0,
    primaryContainer: Color(0xFF333542), // 米色 12% 叠在 bg2 上的容器面
    onPrimaryContainer: _cream,
    secondary: _userText,
    onSecondary: _bg0,
    secondaryContainer: Color(0xFF2E3A52), // 用户文本蓝的暗容器
    onSecondaryContainer: Color(0xFFBFE6FF),
    tertiary: _editText,
    onTertiary: _bg0,
    tertiaryContainer: Color(0xFF38334E),
    onTertiaryContainer: _editText,
    error: _warning,
    onError: _bg0,
    errorContainer: Color(0xFF3D1F26),
    onErrorContainer: Color(0xFFFFB4B4),
    // 画布 bg0，区块 bg1，控件 bg2，浮层 bg3 —— 与 NovelAI 的层叠顺序一致。
    surface: _bg0,
    onSurface: Colors.white,
    onSurfaceVariant: Color(0xFF9BA0B8),
    surfaceContainerLowest: _bg0,
    surfaceContainerLow: _bg1,
    surfaceContainer: _bg2,
    surfaceContainerHigh: _bg3,
    surfaceContainerHighest: _bg4,
    outline: Color(0xFF7C85A8),
    outlineVariant: Color(0xFF565D80),
  );

  @override
  bool get supportsDarkMode => true;
}
