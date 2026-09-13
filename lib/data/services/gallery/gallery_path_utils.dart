import 'dart:io';

import 'package:path/path.dart' as p;

String normalizeGalleryFilePath(String filePath) {
  final trimmed = filePath.trim();
  if (!Platform.isWindows) return trimmed;

  var normalized = trimmed.replaceAll('/', r'\');
  if (normalized.startsWith(r'\\?\UNC\')) {
    normalized = r'\\' + normalized.substring(r'\\?\UNC\'.length);
  } else if (normalized.startsWith(r'\\?\')) {
    normalized = normalized.substring(r'\\?\'.length);
  }
  return normalized;
}

String galleryFilePathKey(String filePath) {
  final normalized = normalizeGalleryFilePath(filePath);
  return Platform.isWindows ? normalized.toLowerCase() : normalized;
}

bool galleryFilePathsEqual(String left, String right) =>
    galleryFilePathKey(left) == galleryFilePathKey(right);

/// 绝对路径 -> 相对图库根目录的 '/' 分隔路径；不在根目录下时返回 null。
String? toGalleryRelativePath(String rootPath, String absolutePath) {
  final normalizedRoot = p.normalize(rootPath);
  final normalized = p.normalize(absolutePath);
  if (!p.isWithin(normalizedRoot, normalized)) return null;
  return p.relative(normalized, from: normalizedRoot).replaceAll('\\', '/');
}

/// 相对路径 -> 绝对路径
String toGalleryAbsolutePath(String rootPath, String relativePath) {
  return p.joinAll([p.normalize(rootPath), ...relativePath.split('/')]);
}

/// 校验引用是否为图库根目录内的规范化相对路径。
///
/// 拒绝绝对路径（POSIX 前导 / 或 Windows 盘符）、反斜杠与 .. 上跳段，
/// 防止越界引用或设备绝对路径（含盘符、用户名）进入 sidecar 与云同步。
bool isValidGalleryRelativePath(String path) {
  if (path.isEmpty || path.length > 1024) return false;
  if (path.contains('\\')) return false;
  if (path.startsWith('/')) return false;
  if (RegExp(r'^[A-Za-z]:').hasMatch(path)) return false;
  final segments = path.split('/');
  for (final segment in segments) {
    if (segment.isEmpty || segment == '.' || segment == '..') return false;
  }
  return true;
}
