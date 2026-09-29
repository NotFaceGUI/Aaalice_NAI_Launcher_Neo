import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Color, Rect, Size;

import '../../../core/utils/storyboard/storyboard_fit_geometry.dart';
import '../../../core/utils/storyboard/storyboard_geometry.dart';
import '../../models/storyboard/storyboard_page.dart';
import '../../models/storyboard/storyboard_page_background.dart';
import '../../models/storyboard/storyboard_panel.dart';
import 'storyboard_image_source.dart';

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
    final image = await StoryboardImageSource.open(
      galleryRoot: galleryRoot,
      relativePath: background.imagePath,
    );
    if (image == null) return;
    try {
      final (src, dest) = StoryboardFitGeometry.fitRects(
        imageSize: Size(image.width.toDouble(), image.height.toDouble()),
        dest: rect,
        fit: background.fit,
      );
      canvas.drawImageRect(image, src, dest, imagePaint());
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
    final image = await StoryboardImageSource.open(
      galleryRoot: galleryRoot,
      relativePath: panel.selectedImage,
    );
    if (image == null) return;
    try {
      final path = StoryboardGeometry.buildPanelPath(
        rect: panel.rect,
        points: panel.points,
        polygon: panel.isPolygon,
      );
      canvas.save();
      canvas.clipPath(path, doAntiAlias: true);
      final (src, dest) = StoryboardFitGeometry.fitRects(
        imageSize: Size(image.width.toDouble(), image.height.toDouble()),
        dest: panel.rect,
        fit: panel.fit,
      );
      canvas.drawImageRect(image, src, dest, imagePaint());
      canvas.restore();
    } finally {
      image.dispose();
    }
  }

  /// 绘制用画笔：`Paint()` 默认是最近邻插值（FilterQuality.none），成图缩放
  /// 到分镜尺寸时会产生明显锯齿与摩尔纹；整页合成与分层导出共用高质量重采样。
  static ui.Paint imagePaint() =>
      ui.Paint()..filterQuality = ui.FilterQuality.high;
}

/// 用户取消导出；调用方据此静默结束，不当作错误提示。
class StoryboardExportCancelledException implements Exception {
  const StoryboardExportCancelledException();

  @override
  String toString() => 'Storyboard export cancelled';
}
