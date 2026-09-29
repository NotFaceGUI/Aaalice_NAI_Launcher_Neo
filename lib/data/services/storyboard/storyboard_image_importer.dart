import 'dart:io';

import 'package:path/path.dart' as p;

import '../gallery/gallery_path_utils.dart';
import 'storyboard_repository.dart';

/// 把本地图片准备成分镜文档可以引用的图库相对路径。
///
/// 分镜只保存相对图库根的引用，不复制图片字节（见 `docs/storyboard.md`）。
/// 图片已经在图库内时直接引用；来自图库之外（用户从桌面挑的背景图）时才复制
/// 一份到图库的 `storyboard/backgrounds/`，之后它就跟着图库一起迁移。
class StoryboardImageImporter {
  StoryboardImageImporter({StoryboardRepository? repository})
    : _repository = repository ?? StoryboardRepository();

  /// 导入内容的落地目录（相对图库根）。
  static const String backgroundsDirectory = 'storyboard/backgrounds';

  /// 单个背景文件的体积上限；背景图会随页面一起解码，过大的文件不值得。
  static const int maxImportBytes = 32 * 1024 * 1024;

  final StoryboardRepository _repository;

  /// 返回可写入分镜文档的相对路径；无法导入时返回 null。
  Future<String?> importFromPath(String absolutePath) async {
    final root = await _repository.rootPath();
    if (root == null || root.isEmpty) return null;

    final alreadyInside = toGalleryRelativePath(root, absolutePath);
    if (alreadyInside != null && isValidGalleryRelativePath(alreadyInside)) {
      return alreadyInside;
    }

    final source = File(absolutePath);
    if (!await source.exists()) return null;
    final size = await source.length();
    if (size <= 0 || size > maxImportBytes) return null;

    final directory = Directory(
      p.joinAll([p.normalize(root), ...backgroundsDirectory.split('/')]),
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final target = await _resolveTargetFile(directory, p.basename(absolutePath));
    await source.copy(target.path);
    final relative = toGalleryRelativePath(root, target.path);
    if (relative == null || !isValidGalleryRelativePath(relative)) return null;
    return relative;
  }

  /// 同名文件已存在时追加序号，不覆盖用户已有的背景。
  Future<File> _resolveTargetFile(Directory directory, String fileName) async {
    final sanitized = _sanitize(fileName);
    final stem = p.basenameWithoutExtension(sanitized);
    final extension = p.extension(sanitized);
    var candidate = File(p.join(directory.path, '$stem$extension'));
    var index = 2;
    while (await candidate.exists()) {
      candidate = File(p.join(directory.path, '$stem-$index$extension'));
      index++;
    }
    return candidate;
  }

  /// 只保留文件名本身：分隔符、控制字符与保留字符都不能进入图库路径。
  static String _sanitize(String fileName) {
    final base = p.basename(fileName);
    final cleaned = base.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_').trim();
    if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') {
      return 'background.png';
    }
    return cleaned.length > 120 ? cleaned.substring(0, 120) : cleaned;
  }

  /// 解析相对引用到绝对路径，供预览与导出使用。
  Future<String?> resolveAbsolute(String relativePath) async {
    final root = await _repository.rootPath();
    if (root == null || root.isEmpty) return null;
    if (!isValidGalleryRelativePath(relativePath)) return null;
    return StoryboardRepository.resolveAbsolutePath(root, relativePath);
  }
}
