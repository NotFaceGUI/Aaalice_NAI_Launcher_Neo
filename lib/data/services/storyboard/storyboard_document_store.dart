import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:synchronized/synchronized.dart';

import '../../../core/utils/app_logger.dart';
import '../../models/storyboard/storyboard_document.dart';

/// 读写图库根目录下的分镜文档（`.gallery_storyboard.json`）。
///
/// 与相册、分类、画布 sidecar 一致：跟随图库根目录存储，整个图库文件夹
/// 拷贝到其他设备时分镜内容随之带走。分镜只保存相对图库根的图片路径引用，
/// 不保存图片字节，因此这份文件天然是轻量、可检查、可移植的。
///
/// 页面背景图与生成图本体同样不进文档，只有引用参与云同步。
class StoryboardDocumentStore {
  StoryboardDocumentStore({Lock? saveLock}) : _saveLock = saveLock ?? Lock();

  static const String fileName = '.gallery_storyboard.json';

  final Lock _saveLock;

  File _documentFile(String rootPath) => File(p.join(rootPath, fileName));
  File _backupFile(String rootPath) =>
      File('${_documentFile(rootPath).path}.bak');
  File _temporaryFile(String rootPath) =>
      File('${_documentFile(rootPath).path}.tmp');

  /// 读取分镜文档。
  ///
  /// 返回 null 表示该图库目录下还没有分镜文档，调用方应视为新建；
  /// 主文件损坏时从 `.bak` 恢复，恢复不了则返回 null 而不是让启动失败。
  Future<StoryboardDocument?> load(String rootPath) async {
    final file = _documentFile(rootPath);
    final backup = _backupFile(rootPath);
    try {
      if (await file.exists()) {
        try {
          final document = await _readDocument(file);
          if (document != null) {
            await _deleteIfPresent(backup);
            return document;
          }
          AppLogger.w('分镜文档版本不受支持，已忽略: ${file.path}', 'StoryboardStore');
        } catch (primaryError) {
          if (!await backup.exists()) {
            AppLogger.e('读取分镜文档失败', primaryError, null, 'StoryboardStore');
            return null;
          }
          final document = await _readDocument(backup);
          if (document != null) {
            await backup.copy(file.path);
            await _deleteIfPresent(backup);
            AppLogger.w('分镜文档损坏，已从备份恢复: $primaryError', 'StoryboardStore');
            return document;
          }
        }
        return null;
      }

      if (!await backup.exists()) return null;

      final document = await _readDocument(backup);
      if (document == null) return null;
      await backup.copy(file.path);
      await _deleteIfPresent(backup);
      AppLogger.w('分镜文档提交中断，已从备份恢复', 'StoryboardStore');
      return document;
    } catch (e) {
      AppLogger.e('加载分镜文档失败', e, null, 'StoryboardStore');
      return null;
    }
  }

  /// 原子写入分镜文档：先写临时文件，再把现有文件转成备份后替换。
  Future<bool> save(String rootPath, StoryboardDocument document) {
    return _saveLock.synchronized(() async {
      final file = _documentFile(rootPath);
      final temporary = _temporaryFile(rootPath);
      final backup = _backupFile(rootPath);
      var committed = false;
      try {
        if (!await file.parent.exists()) {
          await file.parent.create(recursive: true);
        }
        await temporary.writeAsString(
          const JsonEncoder.withIndent('  ').convert(document.toJson()),
          flush: true,
        );
        if (await file.exists()) {
          await file.copy(backup.path);
        }
        await temporary.rename(file.path);
        committed = true;
        await _deleteIfPresent(backup);
        return true;
      } catch (e) {
        if (!committed && await backup.exists() && !await file.exists()) {
          try {
            await backup.rename(file.path);
          } catch (restoreError) {
            AppLogger.e('恢复分镜文档备份失败', restoreError, null, 'StoryboardStore');
          }
        }
        AppLogger.e('保存分镜文档失败', e, null, 'StoryboardStore');
        return false;
      } finally {
        await _deleteIfPresent(temporary);
      }
    });
  }

  Future<StoryboardDocument?> _readDocument(File file) async {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) return null;
    return StoryboardDocument.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<void> _deleteIfPresent(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (e) {
      AppLogger.w('清理分镜文档临时文件失败: ${file.path}: $e', 'StoryboardStore');
    }
  }
}
