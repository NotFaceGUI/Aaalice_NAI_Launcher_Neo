import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/services/storyboard/storyboard_image_importer.dart';
import '../../../data/services/storyboard/storyboard_repository.dart';

/// 分镜文档与图库根目录的读写入口。
final storyboardRepositoryProvider = Provider<StoryboardRepository>(
  (ref) => StoryboardRepository(),
);

/// 把图库外的图片准备成分镜可引用的相对路径（目前只有页面背景图需要）。
final storyboardImageImporterProvider = Provider<StoryboardImageImporter>(
  (ref) => StoryboardImageImporter(
    repository: ref.watch(storyboardRepositoryProvider),
  ),
);

/// 图库根目录；分镜面板引用与背景图以此为基准解析。
final storyboardGalleryRootPathProvider = FutureProvider<String?>(
  (ref) => ref.watch(storyboardRepositoryProvider).rootPath(),
);
