import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Color, Offset, Rect, Size;

import '../../../core/utils/storyboard/storyboard_geometry.dart';
import '../../models/storyboard/storyboard_fit_mode.dart';
import '../../models/storyboard/storyboard_page.dart';
import '../../models/storyboard/storyboard_page_background.dart';
import '../../models/storyboard/storyboard_panel.dart';
import '../gallery/gallery_path_utils.dart';

/// 分镜页导出器：把整页（背景 + 全部分镜）或单个分镜合成为一张 PNG。
///
/// 页面坐标就是最终输出像素，导出结果即用户排版的成品。dart:ui 渲染只能在
/// 根 isolate 执行（与 mosaic 渲染相同的约定）；面板原图逐张「解码 → 绘制 →
/// 释放」，不把整页原图同时常驻内存。
class StoryboardPageExporter {
  StoryboardPageExporter._();

  /// 渲染整页。没有出图的面板留空（背景透出），与画布表现一致。
  static Future<Uint8List> renderPage({
    required StoryboardPage page,
    required String? galleryRoot,
    void Function(int completed, int total)? onPanelDone,
    bool Function()? isCancelled,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      Rect.fromLTWH(0, 0, page.width.toDouble(), page.height.toDouble()),
    );
    await _drawBackground(canvas, page.background, _pageRect(page), galleryRoot);

    final panels = page.panelsByZOrder;
    var completed = 0;
    var cancelled = false;
    for (final panel in panels) {
      if (isCancelled?.call() ?? false) {
        cancelled = true;
        break;
      }
      await _drawPanel(canvas, panel, galleryRoot);
      completed++;
      onPanelDone?.call(completed, panels.length);
    }
    final picture = recorder.endRecording();
    try {
      if (cancelled) {
        throw const StoryboardExportCancelledException();
      }
      final image = await picture.toImage(page.width, page.height);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) {
          throw StateError('导出整页分镜时 PNG 编码失败');
        }
        return data.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  /// 渲染单个分镜：按外接矩形出图，多边形外的区域保持透明。
  ///
  /// 面板自己的背景就是页面背景在该区域的透出，所以同样绘制一遍背景。
  static Future<Uint8List> renderPanel({
    required StoryboardPage page,
    required StoryboardPanel panel,
    required String? galleryRoot,
  }) async {
    final width = panel.width.round().clamp(1, 1 << 14);
    final height = panel.height.round().clamp(1, 1 << 14);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );
    canvas.translate(-panel.x, -panel.y);
    await _drawBackground(canvas, page.background, _pageRect(page), galleryRoot);
    await _drawPanel(canvas, panel, galleryRoot);
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(width, height);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) {
          throw StateError('导出分镜时 PNG 编码失败');
        }
        return data.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  static Rect _pageRect(StoryboardPage page) =>
      Rect.fromLTWH(0, 0, page.width.toDouble(), page.height.toDouble());

  static Future<void> _drawBackground(
    ui.Canvas canvas,
    StoryboardPageBackground background,
    Rect rect,
    String? galleryRoot,
  ) async {
    if (background.kind != StoryboardBackgroundKind.none) {
      canvas.drawRect(rect, ui.Paint()..color = Color(background.colorArgb));
    }
    if (!background.hasImage) return;
    final bytes = await _readImageBytes(galleryRoot, background.imagePath);
    final image = bytes == null ? null : await _decode(bytes);
    if (image == null) return;
    try {
      final (src, dest) = _fitRects(
        imageSize: Size(image.width.toDouble(), image.height.toDouble()),
        dest: rect,
        fit: background.fit,
      );
      canvas.drawImageRect(image, src, dest, _imagePaint());
    } finally {
      image.dispose();
    }
  }

  static Future<void> _drawPanel(
    ui.Canvas canvas,
    StoryboardPanel panel,
    String? galleryRoot,
  ) async {
    if (panel.selectedImage == null || panel.selectedImage!.isEmpty) return;
    final bytes = await _readImageBytes(galleryRoot, panel.selectedImage);
    final image = bytes == null ? null : await _decode(bytes);
    if (image == null) return;
    try {
      final path = StoryboardGeometry.buildPanelPath(
        rect: panel.rect,
        points: panel.points,
        polygon: panel.isPolygon,
      );
      canvas.save();
      canvas.clipPath(path, doAntiAlias: true);
      final (src, dest) = _fitRects(
        imageSize: Size(image.width.toDouble(), image.height.toDouble()),
        dest: panel.rect,
        fit: panel.fit,
      );
      canvas.drawImageRect(image, src, dest, _imagePaint());
      canvas.restore();
    } finally {
      image.dispose();
    }
  }

  /// fit 语义与画布一致：cover 居中裁满（裁源图）、contain 完整放入、
  /// stretch 拉伸。返回（源图裁切区, 目标区）。
  static (Rect, Rect) _fitRects({
    required Size imageSize,
    required Rect dest,
    required StoryboardFitMode fit,
  }) {
    final full = Rect.fromLTWH(
      0,
      0,
      imageSize.width,
      imageSize.height,
    );
    switch (fit) {
      case StoryboardFitMode.stretch:
        return (full, dest);
      case StoryboardFitMode.contain:
        final scale = (dest.width / imageSize.width).clamp(
          0.0,
          dest.height / imageSize.height,
        );
        final scaled = imageSize * scale;
        final fitted = Offset(
              dest.left + (dest.width - scaled.width) / 2,
              dest.top + (dest.height - scaled.height) / 2,
            ) &
            scaled;
        return (full, fitted);
      case StoryboardFitMode.cover:
        final destAspect = dest.width / dest.height;
        var cropWidth = imageSize.width;
        var cropHeight = cropWidth / destAspect;
        if (cropHeight > imageSize.height) {
          cropHeight = imageSize.height;
          cropWidth = cropHeight * destAspect;
        }
        final src = Rect.fromCenter(
          center: Offset(imageSize.width / 2, imageSize.height / 2),
          width: cropWidth,
          height: cropHeight,
        );
        return (src, dest);
    }
  }

  /// 绘制用画笔：`Paint()` 默认是最近邻插值（FilterQuality.none），成图缩放
  /// 到分镜尺寸时会产生明显锯齿与摩尔纹；导出统一用高质量重采样。
  static ui.Paint _imagePaint() => ui.Paint()
    ..filterQuality = ui.FilterQuality.high;

  static Future<Uint8List?> _readImageBytes(
    String? galleryRoot,
    String? relativePath,
  ) async {
    if (galleryRoot == null || galleryRoot.isEmpty) return null;
    if (relativePath == null || relativePath.isEmpty) return null;
    if (!isValidGalleryRelativePath(relativePath)) return null;
    final file = File(toGalleryAbsolutePath(galleryRoot, relativePath));
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  static Future<ui.Image?> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  }
}

/// 用户取消导出；调用方据此静默结束，不当作错误提示。
class StoryboardExportCancelledException implements Exception {
  const StoryboardExportCancelledException();

  @override
  String toString() => 'Storyboard export cancelled';
}
