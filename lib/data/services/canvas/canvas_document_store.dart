import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:synchronized/synchronized.dart';

import '../../../core/utils/app_logger.dart';
import '../../models/canvas/canvas_document.dart';

/// 读写图片库根目录下的无限画布文档（`.gallery_canvas.json`）。
///
/// 与相簿、分类 sidecar 一致：跟随图库根目录存储，整个图库文件夹拷贝到
/// 其他设备时画布内容随之带走。节点只保存相对图库根的图片路径引用，
/// 不保存图片字节，因此这份文件天然是轻量、可检查、可移植的。
class CanvasDocumentStore {
  CanvasDocumentStore({Lock? saveLock}) : _saveLock = saveLock ?? Lock();

  static const String fileName = '.gallery_canvas.json';

  final Lock _saveLock;

  File _documentFile(String rootPath) => File(p.join(rootPath, fileName));
  File _backupFile(String rootPath) =>
      File('${_documentFile(rootPath).path}.bak');
  File _temporaryFile(String rootPath) =>
      File('${_documentFile(rootPath).path}.tmp');

  /// 读取画布文档。
  ///
  /// 返回 null 表示该图库目录下还没有画布，调用方应视为空画布；
  /// 主文件损坏时从 `.bak` 恢复，恢复不了则返回 null 而不是让启动失败。
  Future<CanvasDocument?> load(String rootPath) async {
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
          AppLogger.w('画布文档版本不受支持，已忽略: ${file.path}', 'CanvasStore');
        } catch (primaryError) {
          if (!await backup.exists()) {
            AppLogger.e('读取画布文档失败', primaryError, null, 'CanvasStore');
            return null;
          }
          final document = await _readDocument(backup);
          if (document != null) {
            await backup.copy(file.path);
            await _deleteIfPresent(backup);
            AppLogger.w('画布文档损坏，已从备份恢复: $primaryError', 'CanvasStore');
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
      AppLogger.w('画布文档提交中断，已从备份恢复', 'CanvasStore');
      return document;
    } catch (e) {
      AppLogger.e('加载画布文档失败', e, null, 'CanvasStore');
      return null;
    }
  }

  /// 原子写入画布文档：先写临时文件，再把现有文件转成备份后替换。
  Future<bool> save(String rootPath, CanvasDocument document) {
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
            AppLogger.e('恢复画布文档备份失败', restoreError, null, 'CanvasStore');
          }
        }
        AppLogger.e('保存画布文档失败', e, null, 'CanvasStore');
        return false;
      } finally {
        await _deleteIfPresent(temporary);
      }
    });
  }

  Future<CanvasDocument?> _readDocument(File file) async {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) return null;
    return CanvasDocument.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<void> _deleteIfPresent(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (e) {
      AppLogger.w('清理画布文档临时文件失败: ${file.path}: $e', 'CanvasStore');
    }
  }
}
