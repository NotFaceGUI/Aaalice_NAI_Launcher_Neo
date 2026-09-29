import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../gallery/gallery_path_utils.dart';

/// 分镜文档里的图片引用 → 已解码的 [ui.Image]。
///
/// 文档只保存相对图库根目录的路径，读取时必须校验路径、确认文件存在再解码。
/// 两个导出路径（整页合成与分层 PSD）都从这里取原图，避免各自实现一套路径
/// 校验与解码，也保证两条路径拿到的是同一张图。
class StoryboardImageSource {
  StoryboardImageSource._();

  /// 打开图库内的相对路径图片。
  ///
  /// 路径为空、越界或文件不存在时返回 null，由调用方当作「这个分镜还没有图」
  /// 处理；图片本身损坏时由解码器抛出的异常向上传递，导出以失败结束，
  /// 而不是静默产出一张缺图的成品。
  static Future<ui.Image?> open({
    required String? galleryRoot,
    required String? relativePath,
  }) async {
    if (galleryRoot == null || galleryRoot.isEmpty) return null;
    if (relativePath == null || relativePath.isEmpty) return null;
    if (!isValidGalleryRelativePath(relativePath)) return null;
    final file = File(toGalleryAbsolutePath(galleryRoot, relativePath));
    if (!await file.exists()) return null;
    return decode(await file.readAsBytes());
  }

  /// 解码图片字节；损坏的数据由 [ui.instantiateImageCodec] 抛错。
  static Future<ui.Image> decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  }
}
