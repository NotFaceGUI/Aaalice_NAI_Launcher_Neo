import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Color, Offset, Rect, Size;

import '../../../core/utils/storyboard/storyboard_fit_geometry.dart';
import '../../../core/utils/storyboard/storyboard_geometry.dart';
import '../../models/storyboard/storyboard_page.dart';
import '../../models/storyboard/storyboard_page_background.dart';
import '../../models/storyboard/storyboard_panel.dart';
import 'psd/psd_document.dart';
import 'psd/psd_rle_encoder.dart';
import 'psd/psd_writer.dart';
import 'storyboard_image_source.dart';
import 'storyboard_page_exporter.dart';

/// PSD 图层名称。由调用方按当前语言提供，导出器不读取 UI 上下文。
class StoryboardPsdLabels {
  const StoryboardPsdLabels({
    required this.background,
    required this.maskSuffix,
    required this.imageSuffix,
  });

  /// 背景图层名。
  final String background;

  /// 遮罩图层名后缀，与阅读序号拼成「03 遮罩」。
  final String maskSuffix;

  /// 原图图层名后缀，与阅读序号拼成「03 原图」。
  final String imageSuffix;

  String maskFor(int order) => _numbered(order, maskSuffix);

  String imageFor(int order) => _numbered(order, imageSuffix);

  /// 阅读序号统一补足两位：图层列表按名称排序时仍保持阅读顺序。
  static String _numbered(int order, String suffix) =>
      '${order.toString().padLeft(2, '0')} $suffix';
}

/// 分镜页 → 分层 PSD。
///
/// 一个分镜页对应一个 PSD，画布等于页面像素。图层自下而上为：背景、每个有图
/// 分镜的「遮罩 + 原图」。遮罩是按分镜形状填充的不透明白色剪贴基底，原图是
/// 未裁剪的整张原图并标记为被剪贴层——用户在 Photoshop 里移动或缩放原图即可
/// 重新取景，而画面上看到的结果与整页 PNG 合成一致。
///
/// 内存按「逐个分镜解码 → 绘制 → 压缩 → 释放」推进：任一时刻只驻留一个分镜
/// 的原图与一份未压缩像素，压缩结果直接进入 PSD 结构。
class StoryboardPsdExporter {
  StoryboardPsdExporter._();

  /// 单文件体积上限；超过即中止，避免把整页原图与中间缓冲一起撑进内存。
  static const int maxFileBytes = 512 * 1024 * 1024;

  /// 导出整页分层 PSD。
  ///
  /// 返回的字节可直接落盘；缩放越界（超过 PSD 的 30000 边长上限）或预计体积
  /// 超过 [maxFileBytes] 时抛 [StoryboardPsdCanvasTooLargeException] /
  /// [StoryboardPsdTooLargeException]，由调用方提示用户。
  static Future<Uint8List> exportPage({
    required StoryboardPage page,
    required String? galleryRoot,
    required StoryboardPsdLabels labels,
  }) async {
    if (page.width > PsdDocument.maxSide || page.height > PsdDocument.maxSide) {
      throw const StoryboardPsdCanvasTooLargeException();
    }
    final pageRect = Rect.fromLTWH(
      0,
      0,
      page.width.toDouble(),
      page.height.toDouble(),
    );

    // 合并预览沿用整页 PNG 的绘制结果：打开 PSD 时先看到的画面与 PNG 导出一致。
    final merged = PsdRleEncoder.encodeMergedImageData(
      rgba: await _decodeRgba(
        await StoryboardPageExporter.renderPage(
          page: page,
          galleryRoot: galleryRoot,
        ),
      ),
      width: page.width,
      height: page.height,
    );

    final layers = <PsdLayer>[];
    var estimatedBytes = merged.length;
    void spend(int bytes) {
      estimatedBytes += bytes;
      if (estimatedBytes > maxFileBytes) {
        throw const StoryboardPsdTooLargeException();
      }
    }

    final background = await _buildBackground(
      page: page,
      pageRect: pageRect,
      galleryRoot: galleryRoot,
      labels: labels,
    );
    if (background != null) {
      spend(background.channelBytes);
      layers.add(background);
    }

    for (final panel in page.panelsByZOrder) {
      if (!panel.hasImage) continue;
      // 原图读不到时整组跳过，与合成保持一致，也不会留下没有原图的空遮罩。
      final artwork = await _buildPanelArtwork(
        panel: panel,
        pageRect: pageRect,
        galleryRoot: galleryRoot,
        labels: labels,
      );
      if (artwork == null) continue;
      final mask = await _buildPanelMask(
        panel: panel,
        pageRect: pageRect,
        labels: labels,
      );
      if (mask == null) continue;

      spend(mask.channelBytes + artwork.channelBytes);
      layers.add(mask);
      layers.add(artwork);
    }

    return PsdWriter.write(
      PsdDocument(
        width: page.width,
        height: page.height,
        layers: layers,
        mergedImageData: merged,
      ),
    );
  }

  /// 背景层：整页范围的纯色，或「颜色铺底 + 按 fit 放置的背景图」。
  ///
  /// 与合成一致：kind=image 时先铺 [StoryboardPageBackground.colorArgb]，
  /// contain 留下的空隙就是这层颜色；cover 放大的部分落在画布外，由画布裁掉。
  static Future<PsdLayer?> _buildBackground({
    required StoryboardPage page,
    required Rect pageRect,
    required String? galleryRoot,
    required StoryboardPsdLabels labels,
  }) async {
    final background = page.background;
    if (background.kind == StoryboardBackgroundKind.none) return null;

    final image = background.hasImage
        ? await StoryboardImageSource.open(
            galleryRoot: galleryRoot,
            relativePath: background.imagePath,
          )
        : null;
    try {
      return await _buildLayer(
        name: labels.background,
        bounds: pageRect,
        draw: (canvas) {
          canvas.drawRect(
            pageRect,
            ui.Paint()..color = Color(background.colorArgb),
          );
          if (image == null) return;
          final imageSize = Size(
            image.width.toDouble(),
            image.height.toDouble(),
          );
          canvas.drawImageRect(
            image,
            Offset.zero & imageSize,
            StoryboardFitGeometry.placementRect(
              imageSize: imageSize,
              dest: pageRect,
              fit: background.fit,
            ),
            StoryboardPageExporter.imagePaint(),
          );
        },
      );
    } finally {
      image?.dispose();
    }
  }

  /// 分镜遮罩层：按分镜形状填充不透明白色，其余透明，作为剪贴基底。
  static Future<PsdLayer?> _buildPanelMask({
    required StoryboardPanel panel,
    required Rect pageRect,
    required StoryboardPsdLabels labels,
  }) {
    return _buildLayer(
      name: labels.maskFor(panel.order),
      bounds: _layerBounds(panel.rect, pageRect),
      draw: (canvas) {
        canvas.drawPath(
          StoryboardGeometry.buildPanelPath(
            rect: panel.rect,
            points: panel.points,
            polygon: panel.isPolygon,
          ),
          ui.Paint()..color = const Color(0xFFFFFFFF),
        );
      },
    );
  }

  /// 分镜原图层：未裁剪的整张原图，按 fit 决定放置位置与缩放。
  ///
  /// cover 会放大到覆盖分镜矩形并居中，图层因此大于分镜矩形——被遮罩裁掉的
  /// 部分仍留在图层里，用户移动或缩放即可重新取景。
  static Future<PsdLayer?> _buildPanelArtwork({
    required StoryboardPanel panel,
    required Rect pageRect,
    required String? galleryRoot,
    required StoryboardPsdLabels labels,
  }) async {
    final image = await StoryboardImageSource.open(
      galleryRoot: galleryRoot,
      relativePath: panel.selectedImage,
    );
    if (image == null) return null;
    try {
      final imageSize = Size(image.width.toDouble(), image.height.toDouble());
      final placement = StoryboardFitGeometry.placementRect(
        imageSize: imageSize,
        dest: panel.rect,
        fit: panel.fit,
      );
      return await _buildLayer(
        name: labels.imageFor(panel.order),
        bounds: _layerBounds(placement, pageRect),
        clipping: true,
        draw: (canvas) {
          canvas.drawImageRect(
            image,
            Offset.zero & imageSize,
            placement,
            StoryboardPageExporter.imagePaint(),
          );
        },
      );
    } finally {
      image.dispose();
    }
  }

  /// 绘制 → 取像素 → 编码为 RLE 通道；未压缩的像素缓冲随调用结束释放。
  static Future<PsdLayer?> _buildLayer({
    required String name,
    required Rect? bounds,
    required void Function(ui.Canvas canvas) draw,
    bool clipping = false,
  }) async {
    if (bounds == null) return null;
    final width = bounds.width.round();
    final height = bounds.height.round();
    final rgba = await _renderRgba(bounds: bounds, draw: draw);
    return PsdLayer(
      name: name,
      top: bounds.top.round(),
      left: bounds.left.round(),
      width: width,
      height: height,
      channelData: PsdRleEncoder.encodeLayerChannels(
        rgba: rgba,
        width: width,
        height: height,
      ),
      clipping: clipping,
    );
  }

  /// 在图层边界内绘制并取回像素。
  ///
  /// 用 `rawStraightRgba` 而不是 `rawRgba`：后者是预乘 alpha，而 PSD 通道保存
  /// 的是直通 alpha，直接写预乘值会让半透明像素在 Photoshop 里变暗。
  static Future<Uint8List> _renderRgba({
    required Rect bounds,
    required void Function(ui.Canvas canvas) draw,
  }) async {
    final width = bounds.width.round();
    final height = bounds.height.round();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );
    canvas.translate(-bounds.left, -bounds.top);
    draw(canvas);
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(width, height);
      try {
        final data = await image.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        );
        if (data == null) {
          throw StateError('分层导出时读取像素失败');
        }
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  /// PNG 合成图 → 直通 RGBA，作为 PSD 的合并预览。
  static Future<Uint8List> _decodeRgba(Uint8List png) async {
    final image = await StoryboardImageSource.decode(png);
    try {
      final data = await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      if (data == null) {
        throw StateError('读取整页合成图像素失败');
      }
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  }

  /// 图层边界：放置结果向外取整后收进画布。
  ///
  /// PSD 允许图层矩形超出画布，但越界像素在 Photoshop 里既不可见也无从取回；
  /// 而极端比例的原图在 cover 下会放大到远超画布，不收敛就可能把内存撑爆。
  /// 收边后单层像素量不超过画布，可见结果完全不变。
  static Rect? _layerBounds(Rect placement, Rect pageRect) {
    if (placement.isEmpty) return null;
    final snapped = Rect.fromLTRB(
      placement.left.floorToDouble(),
      placement.top.floorToDouble(),
      placement.right.ceilToDouble(),
      placement.bottom.ceilToDouble(),
    );
    final bounds = snapped.intersect(pageRect);
    if (bounds.width < 1 || bounds.height < 1) return null;
    return bounds;
  }
}

/// 页面边长超过 PSD（版本 1）的 30000 像素上限。
class StoryboardPsdCanvasTooLargeException implements Exception {
  const StoryboardPsdCanvasTooLargeException();

  @override
  String toString() => 'Storyboard PSD canvas exceeds ${PsdDocument.maxSide}px';
}

/// 预计导出的 PSD 超过 [StoryboardPsdExporter.maxFileBytes]。
class StoryboardPsdTooLargeException implements Exception {
  const StoryboardPsdTooLargeException();

  @override
  String toString() => 'Storyboard PSD exceeds the file size limit';
}
