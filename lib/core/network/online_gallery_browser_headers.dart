/// 第三方画廊站点的浏览器化请求头。
///
/// AI TAG 的边缘防护会拒绝不像本站前端发出的请求：缺少浏览器 User-Agent 或
/// 同源 Referer 时直接返回 403 HTML 拦截页，客户端表现为“无法获取来源配置”。
/// JSON 接口与媒体主机都需要这些请求头，Gelbooru 的图片还额外要求 Cookie。
library;

const onlineGalleryBrowserUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/126.0.0.0 Safari/537.36';

const aiTagReferer = 'https://aitag.win/';
const gelbooruReferer = 'https://gelbooru.com/';
const gelbooruContentCookie = 'fringeBenefits=yup';

const _browserAcceptLanguage = 'zh-CN,zh;q=0.9,en;q=0.8';
const _imageAcceptHeader =
    'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8';

/// AI TAG JSON 接口（`/api/config`、搜索、榜单、详情）的请求头。
Map<String, String> aiTagApiHeaders({bool noCache = false}) => {
  'User-Agent': onlineGalleryBrowserUserAgent,
  'Referer': aiTagReferer,
  'Accept': 'application/json',
  'Accept-Language': _browserAcceptLanguage,
  if (noCache) 'Cache-Control': 'no-cache',
};

/// AI TAG 媒体主机的请求头。
const aiTagImageHeaders = <String, String>{
  'User-Agent': onlineGalleryBrowserUserAgent,
  'Referer': aiTagReferer,
  'Accept': _imageAcceptHeader,
};

const gelbooruImageHeaders = <String, String>{
  'User-Agent': onlineGalleryBrowserUserAgent,
  'Referer': gelbooruReferer,
  'Cookie': gelbooruContentCookie,
  'Accept': _imageAcceptHeader,
};
