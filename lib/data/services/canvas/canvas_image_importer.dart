import 'dart:io';
import 'dart:typed_data';

import '../../../core/utils/app_logger.dart';
import '../../../core/utils/image_save_utils.dart';
import '../../repositories/gallery_folder_repository.dart';
import 'canvas_repository.dart';

/// 图片无法进入画布的原因。
enum CanvasImageImportFailure {
  /// 图库根目录不可用
  rootUnavailable,

  /// 图片来源文件已不存在（被移动或删除）
  sourceMissing,

  /// 图片不在图库根目录内，无法用相对路径引用
  outsideGalleryRoot,

  /// 落盘失败
  saveFailed,
}

/// 把图片准备成画布可以长期引用的图库相对路径。
class CanvasImageImportResult {
  const CanvasImageImportResult._({
    this.relativePath,
    this.failure,
    this.savedToDisk = false,
  });

  const CanvasImageImportResult.success(
    String relativePath, {
    required bool savedToDisk,
  }) : this._(relativePath: relativePath, savedToDisk: savedToDisk);

  const CanvasImageImportResult.failure(CanvasImageImportFailure failure)
    : this._(failure: failure);

  final String? relativePath;
  final CanvasImageImportFailure? failure;

  /// 本次是否新写入图库（用于区分"已保存并加入"与"已加入"提示）
  final bool savedToDisk;

  bool get isSuccess => relativePath != null;
}

/// 画布图片引用准备器。
///
/// 画布节点只保存相对图库根目录的路径，不复制图片字节：图片已经在图库里
/// 就直接引用，尚未落盘的生成结果先走既有保存链路写入图库再引用。这样画布
/// 重启后仍可恢复、不产生第二份图片副本，后续云同步也只需同步这份轻量引用。
class CanvasImageImporter {
  CanvasImageImporter({
    CanvasRepository? repository,
    Future<String?> Function()? resolveRootPath,
  }) : _repository = repository ?? CanvasRepository(),
       _resolveRootPath =
           resolveRootPath ?? GalleryFolderRepository.instance.getRootPath;

  final CanvasRepository _repository;
  final Future<String?> Function() _resolveRootPath;

  /// [existingFilePath] 已知的磁盘路径；为空时用 [bytes] 新写入图库。
  Future<CanvasImageImportResult> importImage({
    String? existingFilePath,
    Uint8List? bytes,
  }) async {
    final rootPath = await _resolveRootPath();
    if (rootPath == null || rootPath.isEmpty) {
      return const CanvasImageImportResult.failure(
        CanvasImageImportFailure.rootUnavailable,
      );
    }

    var filePath = existingFilePath;
    var savedToDisk = false;
    if (filePath == null || filePath.isEmpty) {
      if (bytes == null || bytes.isEmpty) {
        return const CanvasImageImportResult.failure(
          CanvasImageImportFailure.sourceMissing,
        );
      }
      try {
        filePath = await ImageSaveUtils.saveBytesToDatedPath(
          rootPath: rootPath,
          bytes: bytes,
          seed: await ImageSaveUtils.resolveSeed(bytes: bytes),
        );
        savedToDisk = true;
      } catch (error, stackTrace) {
        AppLogger.e('画布保存图片失败', error, stackTrace, 'CanvasImport');
        return const CanvasImageImportResult.failure(
          CanvasImageImportFailure.saveFailed,
        );
      }
    } else if (!await File(filePath).exists()) {
      return const CanvasImageImportResult.failure(
        CanvasImageImportFailure.sourceMissing,
      );
    }

    final relativePath = await _repository.toCanvasRelativePath(filePath);
    if (relativePath == null) {
      return const CanvasImageImportResult.failure(
        CanvasImageImportFailure.outsideGalleryRoot,
      );
    }
    return CanvasImageImportResult.success(
      relativePath,
      savedToDisk: savedToDisk,
    );
  }
}
