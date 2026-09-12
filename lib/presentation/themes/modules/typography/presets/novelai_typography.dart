/// NovelAI Typography - NovelAI 图像页字体
///
/// NovelAI 应用的 `fonts.headings` 是 Eczar，`fonts.default` 是 Source Sans Pro。
/// Source Sans Pro 已改名 Source Sans 3 并保留在 Google Fonts，因此这里用
/// Source Sans 3，与线上观感一致。
library;

import 'package:flutter/material.dart';
import 'package:nai_launcher/presentation/themes/modules/typography/typography_module.dart';

class NovelAiTypography extends BaseTypographyModule {
  const NovelAiTypography();

  @override
  String get displayFontFamily => 'Eczar';

  @override
  String get bodyFontFamily => 'Source Sans 3';

  @override
  TextTheme get textTheme => BaseTypographyModule.createTextTheme(
        displayFamily: displayFontFamily,
        bodyFamily: bodyFontFamily,
      );
}
