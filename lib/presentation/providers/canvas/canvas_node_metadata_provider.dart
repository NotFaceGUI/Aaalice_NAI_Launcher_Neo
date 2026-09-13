import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../data/models/gallery/nai_image_metadata.dart';
import '../../../data/services/image_metadata_service.dart';

part 'canvas_node_metadata_provider.g.dart';

/// 按磁盘路径解析画布图片节点的元数据。
///
/// 节点自带参数快照时优先用快照；快照缺失（例如从图库拖入、或加入画布时
/// 字节里没有可解析的元数据）时回退到这里，让节点仍然能显示提示词与参数。
/// [ImageMetadataService] 自身有内存与 Hive 两级缓存，重复读取不会反复解析。
@riverpod
Future<NaiImageMetadata?> canvasNodeMetadata(Ref ref, String absolutePath) =>
    ImageMetadataService().getMetadata(absolutePath);
