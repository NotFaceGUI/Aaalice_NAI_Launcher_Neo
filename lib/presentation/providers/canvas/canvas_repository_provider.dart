import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../data/services/canvas/canvas_image_importer.dart';
import '../../../data/services/canvas/canvas_repository.dart';

part 'canvas_repository_provider.g.dart';

/// 无限画布文档与图库根目录的读写入口。
@Riverpod(keepAlive: true)
CanvasRepository canvasRepository(Ref ref) => CanvasRepository();

/// 把图片准备成画布可引用的图库相对路径。
@Riverpod(keepAlive: true)
CanvasImageImporter canvasImageImporter(Ref ref) =>
    CanvasImageImporter(repository: ref.watch(canvasRepositoryProvider));

/// 图库根目录；画布节点的相对路径以此为基准解析。
@Riverpod(keepAlive: true)
Future<String?> canvasGalleryRootPath(Ref ref) =>
    ref.watch(canvasRepositoryProvider).rootPath();
