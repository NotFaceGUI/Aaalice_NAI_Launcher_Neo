/// NovelAI Shapes - NovelAI 图像页圆角
///
/// NovelAI 的面板与浮层用小圆角（约 8px），按钮和输入框更接近 4px，
/// 提示气泡与菜单同级别为 4px。整体克制，不出现胶囊形大圆角。
library;

import 'package:flutter/material.dart';
import 'package:nai_launcher/presentation/themes/modules/shape/shape_module.dart';

class NovelAiShapes extends BaseShapeModule {
  const NovelAiShapes();

  @override
  double get smallRadius => 4.0;

  @override
  double get mediumRadius => 6.0;

  @override
  double get largeRadius => 8.0;

  @override
  double get menuRadius => 4.0;

  @override
  ShapeBorder get cardShape => RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(largeRadius),
      );

  @override
  ShapeBorder get buttonShape => RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(smallRadius),
      );

  @override
  ShapeBorder get inputShape => RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(smallRadius),
      );

  @override
  ShapeBorder get menuShape => RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(menuRadius),
      );
}
