import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_launcher/data/models/storyboard/storyboard_fit_mode.dart';
import 'package:nai_launcher/data/models/storyboard/storyboard_page.dart';
import 'package:nai_launcher/data/models/storyboard/storyboard_page_background.dart';
import 'package:nai_launcher/data/models/storyboard/storyboard_panel.dart';
import 'package:nai_launcher/data/models/storyboard/storyboard_panel_shape.dart';
import 'package:nai_launcher/data/services/storyboard/psd/psd_rle_encoder.dart';
import 'package:nai_launcher/data/services/storyboard/storyboard_page_exporter.dart';
import 'package:nai_launcher/data/services/storyboard/storyboard_psd_exporter.dart';
import 'package:path/path.dart' as p;

import '../../../helpers/psd_reader.dart';

const _labels = StoryboardPsdLabels(
  background: '背景',
  maskSuffix: '遮罩',
  imageSuffix: '原图',
);

const _backgroundPath = '2026-09-29/background.png';
const _panelPath = '2026-09-29/panel-cover.png';
const _polygonPath = '2026-09-29/panel-contain.png';

void main() {
  late Directory gallery;

  setUp(() async {
    gallery = await Directory.systemTemp.createTemp('storyboard-psd-test');
    final dated = Directory(p.join(gallery.path, '2026-09-29'));
    await dated.create(recursive: true);
    // 纯色图让分层结果可以逐像素断言：cover 与 contain 都能推出确定颜色。
    await _writePng(p.join(gallery.path, _backgroundPath), 64, 64, const [60, 60, 60]);
    await _writePng(p.join(gallery.path, _panelPath), 40, 60, const [200, 30, 40]);
    await _writePng(p.join(gallery.path, _polygonPath), 80, 40, const [10, 150, 220]);
  });

  tearDown(() async {
    if (await gallery.exists()) {
      await gallery.delete(recursive: true);
    }
  });

  test('整页导出为分层 PSD：背景独立、每个分镜遮罩与原图成对', () async {
    final page = _page();

    final bytes = await StoryboardPsdExporter.exportPage(
      page: page,
      galleryRoot: gallery.path,
      labels: _labels,
    );
    final parsed = PsdTestFile.parse(bytes);

    expect(bytes.sublist(0, 4), orderedEquals(<int>[0x38, 0x42, 0x50, 0x53]));
    expect(parsed.version, 1);
    expect(parsed.channels, 4);
    expect(parsed.depth, 8);
    expect(parsed.colorMode, 3);
    expect([parsed.width, parsed.height], [160, 120]);
    expect(parsed.consumedBytes, bytes.length);

    // 自下而上：背景、01 遮罩、01 原图、02 遮罩、02 原图。
    expect(
      parsed.layers.map((layer) => layer.name),
      orderedEquals(<String>['背景', '01 遮罩', '01 原图', '02 遮罩', '02 原图']),
    );
    expect(
      parsed.layers.map((layer) => layer.clipping),
      orderedEquals(<int>[0, 0, 1, 0, 1]),
    );
    // 所有图层默认可见：flags 置上 bit 1 会被 Photoshop 读成「隐藏」。
    expect(parsed.layers.every((layer) => layer.visible), isTrue);
    expect(
      parsed.layers.map((layer) => layer.flags),
      everyElement(0x08),
    );
    expect(parsed.mergedCompression, 1);
  });

  test('背景层覆盖整页并保留背景色；原图层按 fit 放置且可超出分镜矩形', () async {
    final parsed = PsdTestFile.parse(
      await StoryboardPsdExporter.exportPage(
        page: _page(),
        galleryRoot: gallery.path,
        labels: _labels,
      ),
    );

    final background = parsed.layerNamed('背景');
    expect([background.left, background.top, background.right, background.bottom], [0, 0, 160, 120]);
    expect(_pixel(background, 0, 0), orderedEquals(<int>[60, 60, 60, 255]));

    // 01 原图：40×60 的竖图以 cover 放进 60×60，放大 1.5 倍后居中，
    // 纵向溢出分镜矩形，被画布上边缘裁掉后仍高于分镜本身。
    final artwork = parsed.layerNamed('01 原图');
    expect([artwork.left, artwork.top, artwork.width, artwork.height], [8, 0, 60, 83]);
    expect(artwork.height, greaterThan(60));
    expect(_pixel(artwork, 30, 40), orderedEquals(<int>[200, 30, 40, 255]));

    // 01 遮罩：与分镜矩形同尺寸，中心不透明。
    final mask = parsed.layerNamed('01 遮罩');
    expect([mask.left, mask.top, mask.width, mask.height], [8, 8, 60, 60]);
    expect(_pixel(mask, 30, 30), orderedEquals(<int>[255, 255, 255, 255]));

    // 02 是 contain：原图完整放入并居中，边界小于分镜矩形。
    final contained = parsed.layerNamed('02 原图');
    expect([contained.left, contained.top, contained.width, contained.height], [80, 23, 60, 30]);
    expect(_pixel(contained, 30, 15), orderedEquals(<int>[10, 150, 220, 255]));
  });

  test('多边形分镜的遮罩按形状裁剪，原图仍是完整矩形', () async {
    final parsed = PsdTestFile.parse(
      await StoryboardPsdExporter.exportPage(
        page: _page(),
        galleryRoot: gallery.path,
        labels: _labels,
      ),
    );

    final mask = parsed.layerNamed('02 遮罩');
    // 三角形顶点是外接矩形右下角的一半：左上与左下透明、右下不透明。
    expect(_pixel(mask, 0, 0), orderedEquals(<int>[0, 0, 0, 0]));
    expect(_pixel(mask, 10, 10), orderedEquals(<int>[0, 0, 0, 0]));
    expect(_pixel(mask, 50, 50), orderedEquals(<int>[255, 255, 255, 255]));

    // 原图层不裁成三角形：多边形之外的像素仍在图层里。
    final artwork = parsed.layerNamed('02 原图');
    expect(_pixel(artwork, 0, 0), orderedEquals(<int>[10, 150, 220, 255]));
  });

  test('合并预览与整页 PNG 合成逐像素一致', () async {
    final page = _page();
    final png = await StoryboardPageExporter.renderPage(
      page: page,
      galleryRoot: gallery.path,
    );
    final expected = await _decodeStraightRgba(png);
    final parsed = PsdTestFile.parse(
      await StoryboardPsdExporter.exportPage(
        page: page,
        galleryRoot: gallery.path,
        labels: _labels,
      ),
    );
    final planes = decodedMergedPlanes(parsed);

    expect(planes, hasLength(PsdRleEncoder.channelCount));
    var mismatches = 0;
    var firstMismatch = -1;
    for (var index = 0; index < page.width * page.height; index++) {
      for (var channel = 0; channel < PsdRleEncoder.channelCount; channel++) {
        if (planes[channel][index] != expected[index * 4 + channel]) {
          mismatches++;
          if (firstMismatch < 0) firstMismatch = index * 4 + channel;
        }
      }
    }
    expect(
      mismatches,
      0,
      reason: '合并预览与 PNG 合成不一致，首个差异字节 $firstMismatch',
    );
  });

  test('背景为纯色或透明时只影响背景层', () async {
    final colored = PsdTestFile.parse(
      await StoryboardPsdExporter.exportPage(
        page: _page(background: const StoryboardPageBackground(kind: StoryboardBackgroundKind.color, colorArgb: 0xFF112233)),
        galleryRoot: gallery.path,
        labels: _labels,
      ),
    );
    expect(colored.layers.first.name, '背景');
    expect(_pixel(colored.layers.first, 0, 0), orderedEquals(<int>[0x11, 0x22, 0x33, 255]));

    final none = PsdTestFile.parse(
      await StoryboardPsdExporter.exportPage(
        page: _page(background: const StoryboardPageBackground()),
        galleryRoot: gallery.path,
        labels: _labels,
      ),
    );
    expect(none.layers.map((layer) => layer.name), isNot(contains('背景')));
    expect(none.layers, hasLength(4));
  });

  test('原图缺失的分镜整组跳过，不留下空遮罩', () async {
    final page = _page().withPanel(
      StoryboardPanel(
        id: 'p3',
        order: 3,
        x: 8,
        y: 80,
        width: 60,
        height: 30,
        fit: StoryboardFitMode.cover,
        images: const ['2026-09-29/missing.png'],
        selectedImage: '2026-09-29/missing.png',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    final parsed = PsdTestFile.parse(
      await StoryboardPsdExporter.exportPage(
        page: page,
        galleryRoot: gallery.path,
        labels: _labels,
      ),
    );

    expect(parsed.layers, hasLength(5));
    expect(parsed.layers.map((layer) => layer.name), isNot(contains('03 遮罩')));
  });

  test('页面边长超过 PSD 上限时报错', () async {
    final page = StoryboardPage(
      id: 'huge',
      name: '',
      width: 32000,
      height: 64,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    expect(
      () => StoryboardPsdExporter.exportPage(
        page: page,
        galleryRoot: gallery.path,
        labels: _labels,
      ),
      throwsA(isA<StoryboardPsdCanvasTooLargeException>()),
    );
  });
}

/// 背景图 cover 整页；01 是矩形 cover，02 是三角形 contain。
StoryboardPage _page({StoryboardPageBackground? background}) {
  final now = DateTime.now();
  return StoryboardPage(
    id: 'page-1',
    name: 'test',
    width: 160,
    height: 120,
    background:
        background ??
        const StoryboardPageBackground(
          kind: StoryboardBackgroundKind.image,
          imagePath: _backgroundPath,
          fit: StoryboardFitMode.cover,
        ),
    panels: [
      StoryboardPanel(
        id: 'p1',
        order: 1,
        x: 8,
        y: 8,
        width: 60,
        height: 60,
        fit: StoryboardFitMode.cover,
        images: const [_panelPath],
        selectedImage: _panelPath,
        createdAt: now,
        updatedAt: now,
      ),
      StoryboardPanel(
        id: 'p2',
        order: 2,
        shape: StoryboardPanelShape.polygon,
        x: 80,
        y: 8,
        width: 60,
        height: 60,
        points: const [Offset(1, 0), Offset(1, 1), Offset(0, 1)],
        fit: StoryboardFitMode.contain,
        images: const [_polygonPath],
        selectedImage: _polygonPath,
        createdAt: now,
        updatedAt: now,
      ),
    ],
    createdAt: now,
    updatedAt: now,
  );
}

/// 图层里某个像素的 RGBA（值为 0 表示该通道透明区域）。
List<int> _pixel(PsdTestLayer layer, int x, int y) {
  final offset = y * layer.width + x;
  return [
    for (var channel = 0; channel < PsdRleEncoder.channelCount; channel++)
      decodeRleChannel(
        layer.channelData[channel],
        layer.width,
        layer.height,
      )[offset],
  ];
}

Future<void> _writePng(
  String path,
  int width,
  int height,
  List<int> rgb,
) async {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(rgb[0], rgb[1], rgb[2]));
  await File(path).writeAsBytes(img.encodePng(image));
}

Future<Uint8List> _decodeStraightRgba(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  try {
    final data = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    frame.image.dispose();
    codec.dispose();
  }
}
