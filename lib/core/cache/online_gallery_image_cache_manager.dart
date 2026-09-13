import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../network/online_gallery_browser_headers.dart';

final Set<String> _aiTagMediaHosts = {'ai-img.10118899.xyz'};

void registerAiTagImageBaseUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.isAbsolute || uri.host.isEmpty) return;
  _aiTagMediaHosts.add(uri.host.toLowerCase());
}

Map<String, String> onlineGalleryImageHeadersForUrl(String url) {
  final uri = Uri.tryParse(url);
  if (_isGelbooruMediaHost(uri)) return gelbooruImageHeaders;
  if (_isAiTagMediaHost(uri)) return aiTagImageHeaders;
  return const {};
}

String? onlineGalleryImageCacheKeyForUrl(String url) {
  final uri = Uri.tryParse(url);
  if (!_isGelbooruMediaHost(uri)) return null;
  return 'gelbooru-image-v2:$url';
}

bool _isGelbooruMediaHost(Uri? uri) {
  if (uri == null || uri.host.isEmpty) return false;
  final host = uri.host.toLowerCase();
  return host == 'gelbooru.com' || host.endsWith('.gelbooru.com');
}

bool _isAiTagMediaHost(Uri? uri) {
  if (uri == null || uri.host.isEmpty) return false;
  return _aiTagMediaHosts.contains(uri.host.toLowerCase());
}

/// 统一的在线画廊图片缓存管理器
///
/// 使用共享配置：
/// - 缓存键：沿用 danbooruImageCache，升级后继续复用现有磁盘池
/// - 过期时间：7天
/// - 最大缓存对象数：1000
/// - 共享磁盘缓存池，支持所有画廊来源
class OnlineGalleryImageCacheManager extends CacheManager
    with ImageCacheManager {
  static const key = 'danbooruImageCache';

  static final OnlineGalleryImageCacheManager _instance =
      OnlineGalleryImageCacheManager._internal();

  factory OnlineGalleryImageCacheManager() => _instance;

  OnlineGalleryImageCacheManager._internal()
    : super(
        Config(
          key,
          stalePeriod: const Duration(days: 7),
          maxNrOfCacheObjects: 1000,
        ),
      );

  /// 获取单例实例
  static OnlineGalleryImageCacheManager get instance => _instance;
}
