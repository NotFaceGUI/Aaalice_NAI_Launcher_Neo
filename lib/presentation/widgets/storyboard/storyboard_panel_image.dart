import 'dart:io';

import 'package:flutter/widgets.dart';

import '../../../data/models/storyboard/storyboard_fit_mode.dart';
import '../../../data/services/gallery/gallery_path_utils.dart';

/// 把分镜文档里的图库相对路径解析成可显示的图片源。
///
/// 显示路径统一走 [ResizeImage] 降采样：分镜页里一个面板在屏幕上通常只有
/// 几百逻辑像素，按原分辨率解码会白白占用大量内存（十几张 1088×1472 的
/// RGBA 就是几十 MB）。Flutter 的 ImageCache 负责 LRU 回收。
class StoryboardPanelImage {
  StoryboardPanelImage._();

  /// 解析相对路径；路径非法或根目录缺失时返回 null。
  static ImageProvider? providerFor({
    required String? galleryRoot,
    required String? relativePath,
    int? decodeWidth,
  }) {
    if (galleryRoot == null || galleryRoot.isEmpty) return null;
    if (relativePath == null || relativePath.isEmpty) return null;
    if (!isValidGalleryRelativePath(relativePath)) return null;

    final file = File(toGalleryAbsolutePath(galleryRoot, relativePath));
    final base = FileImage(file);
    if (decodeWidth == null || decodeWidth <= 0) return base;
    return ResizeImage(
      base,
      width: decodeWidth,
      policy: ResizeImagePolicy.fit,
    );
  }

  /// 分镜适配方式到 [BoxFit] 的映射。
  static BoxFit boxFitOf(StoryboardFitMode fit) {
    switch (fit) {
      case StoryboardFitMode.cover:
        return BoxFit.cover;
      case StoryboardFitMode.contain:
        return BoxFit.contain;
      case StoryboardFitMode.stretch:
        return BoxFit.fill;
    }
  }
}
