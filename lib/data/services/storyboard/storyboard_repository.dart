import '../../models/storyboard/storyboard_document.dart';
import '../../repositories/gallery_folder_repository.dart';
import '../gallery/gallery_path_utils.dart';
import 'storyboard_document_store.dart';

/// 分镜文档的读写入口。
///
/// 把"图库根目录解析 + 相对路径引用 + 文档存取"组合在一起，
/// 让上层 provider 只关心分镜状态本身。
class StoryboardRepository {
  StoryboardRepository({StoryboardDocumentStore? store})
    : _store = store ?? StoryboardDocumentStore();

  final StoryboardDocumentStore _store;

  /// 分镜跟随图库根目录存储；未配置时用默认目录。
  Future<String?> rootPath() => GalleryFolderRepository.instance.getRootPath();

  /// 读取分镜文档；null 表示该图库目录下还没有分镜文档。
  Future<StoryboardDocument?> load() async {
    final root = await rootPath();
    if (root == null || root.isEmpty) return null;
    return _store.load(root);
  }

  Future<bool> save(StoryboardDocument document) async {
    final root = await rootPath();
    if (root == null || root.isEmpty) return false;
    return _store.save(root, document);
  }

  /// 把已落盘图片的绝对路径转成分镜可保存的相对引用。
  ///
  /// 不在图库根目录内（用户把图片存到了别处）或路径非法时返回 null，
  /// 由调用方决定拒绝引用并提示。
  Future<String?> toStoryboardRelativePath(String absolutePath) async {
    final root = await rootPath();
    if (root == null || root.isEmpty) return null;
    final relative = toGalleryRelativePath(root, absolutePath);
    if (relative == null || !isValidGalleryRelativePath(relative)) return null;
    return relative;
  }

  static String resolveAbsolutePath(String rootPath, String relativePath) =>
      toGalleryAbsolutePath(rootPath, relativePath);

  static bool isValidReference(String relativePath) =>
      isValidGalleryRelativePath(relativePath);
}
