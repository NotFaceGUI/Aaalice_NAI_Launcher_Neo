import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/services/storyboard/psd/psd_document.dart';
import 'package:nai_launcher/data/services/storyboard/psd/psd_rle_encoder.dart';
import 'package:nai_launcher/data/services/storyboard/psd/psd_writer.dart';

import '../../../../helpers/psd_reader.dart';

void main() {
  group('PSD 头部与段落', () {
    test('签名、版本、通道、深宽与颜色模式按规范写入', () {
      final bytes = PsdWriter.write(_document(width: 8, height: 6));
      final parsed = PsdTestFile.parse(bytes);

      expect(bytes.sublist(0, 4), orderedEquals(<int>[0x38, 0x42, 0x50, 0x53]));
      expect(parsed.version, 1);
      expect(parsed.channels, 4);
      expect(parsed.width, 8);
      expect(parsed.height, 6);
      expect(parsed.depth, 8);
      expect(parsed.colorMode, 3); // RGB
      expect(parsed.colorModeDataLength, 0);
      expect(parsed.imageResourcesLength, 0);
      expect(parsed.globalLayerMaskLength, 0);
      expect(parsed.consumedBytes, bytes.length);
    });

    test('图层信息段长度为偶数，段落定位自洽', () {
      final bytes = PsdWriter.write(
        _document(
          width: 8,
          height: 6,
          layers: [
            _solidLayer(name: 'a', top: 0, left: 0, width: 8, height: 6),
            _solidLayer(name: 'chinese-name', top: 0, left: 0, width: 2, height: 2),
          ],
        ),
      );
      final parsed = PsdTestFile.parse(bytes);

      expect(parsed.layerInfoLength.isEven, isTrue);
      expect(parsed.layerAndMaskLength, 4 + parsed.layerInfoLength + 4);
      expect(parsed.layerCount, 2);
      expect(parsed.consumedBytes, bytes.length);
    });

    test('合并预览以 RLE 压缩方式收尾', () {
      final bytes = PsdWriter.write(_document(width: 8, height: 6));
      final parsed = PsdTestFile.parse(bytes);

      expect(parsed.mergedCompression, 1);
      expect(
        decodedMergedPlanes(parsed),
        hasLength(PsdRleEncoder.channelCount),
      );
    });
  });

  group('图层记录', () {
    test('边界、混合模式、透明度、剪贴与可见标志', () {
      final bytes = PsdWriter.write(
        _document(
          width: 8,
          height: 6,
          layers: [
            _solidLayer(name: 'base', top: 0, left: 0, width: 8, height: 6),
            _solidLayer(
              name: 'clipped',
              top: -2,
              left: 1,
              width: 5,
              height: 4,
              clipping: true,
              visible: false,
            ),
          ],
        ),
      );
      final parsed = PsdTestFile.parse(bytes);

      final base = parsed.layers[0];
      expect([base.top, base.left, base.bottom, base.right], [0, 0, 6, 8]);
      expect(base.clipping, 0);
      expect(base.visible, isTrue);
      expect(base.opacity, 255);
      expect(base.blendModeSignature, '8BIM');
      expect(base.blendModeKey, 'norm');
      expect(base.filler, 0);
      // 可见图层的 flags 只带 Photoshop 5.0 标记位；bit 1 一旦置位，
      // Photoshop 会把它读成「隐藏」，导出的文件打开后图层全是关的。
      expect(base.flags, 0x08);

      final clipped = parsed.layers[1];
      // 负坐标与越界矩形按原值写入，不额外钳制。
      expect([clipped.top, clipped.left], [-2, 1]);
      expect([clipped.width, clipped.height], [5, 4]);
      expect(clipped.clipping, 1);
      expect(clipped.visible, isFalse);
      expect(clipped.flags, 0x0A);
    });

    test('通道 ID 为 0/1/2/-1，数据长度与通道数据段一致', () {
      final layers = [
        _solidLayer(name: 'a', top: 0, left: 0, width: 8, height: 6),
        _solidLayer(name: 'b', top: 1, left: 1, width: 3, height: 2),
      ];
      final bytes = PsdWriter.write(
        _document(width: 8, height: 6, layers: layers),
      );
      final parsed = PsdTestFile.parse(bytes);

      for (var index = 0; index < parsed.layers.length; index++) {
        final layer = parsed.layers[index];
        expect(layer.channelIds, orderedEquals(<int>[0, 1, 2, -1]));
        expect(layer.channelData, hasLength(4));
        for (var channel = 0; channel < 4; channel++) {
          expect(layer.channelData[channel].length, layer.channelLengths[channel]);
          // 每段通道数据自带压缩方式与行长度表。
          expect(layer.channelData[channel].sublist(0, 2), orderedEquals(<int>[0, 1]));
        }
        expect(
          decodeRleChannel(layer.channelData[0], layer.width, layer.height).length,
          layer.width * layer.height,
        );
      }
    });

    test('蒙版与混合范围为空，额外数据按 2 字节对齐', () {
      final bytes = PsdWriter.write(
        _document(
          width: 8,
          height: 6,
          layers: [_solidLayer(name: 'x', top: 0, left: 0, width: 8, height: 6)],
        ),
      );
      final layer = PsdTestFile.parse(bytes).layers.single;

      expect(layer.maskDataLength, 0);
      expect(layer.blendingRangesLength, 0);
      expect(layer.extraDataLength.isEven, isTrue);
    });

    test('中文图层名写入 luni，Pascal 名保留可读回退', () {
      final bytes = PsdWriter.write(
        _document(
          width: 8,
          height: 6,
          layers: [
            _solidLayer(name: '03 原图', top: 0, left: 0, width: 8, height: 6),
          ],
        ),
      );
      final layer = PsdTestFile.parse(bytes).layers.single;

      expect(layer.name, '03 原图');
      expect(layer.pascalName, '03 ??');
    });

    test('图层顺序与传入顺序一致（自下而上）', () {
      final bytes = PsdWriter.write(
        _document(
          width: 8,
          height: 6,
          layers: [
            _solidLayer(name: '背景', top: 0, left: 0, width: 8, height: 6),
            _solidLayer(name: '01 遮罩', top: 0, left: 0, width: 4, height: 4),
            _solidLayer(
              name: '01 原图',
              top: 0,
              left: 0,
              width: 4,
              height: 4,
              clipping: true,
            ),
          ],
        ),
      );
      final parsed = PsdTestFile.parse(bytes);

      expect(
        parsed.layers.map((layer) => layer.name),
        orderedEquals(<String>['背景', '01 遮罩', '01 原图']),
      );
      expect(parsed.layers.map((layer) => layer.clipping), orderedEquals(<int>[0, 0, 1]));
    });
  });

  group('不支持的输入', () {
    test('画布边长超过 30000 或非正数时报错', () {
      final merged = _mergedData(width: 2, height: 2);
      for (final side in const [[0, 10], [10, 0], [30001, 10], [10, 30001]]) {
        expect(
          () => PsdWriter.write(
            PsdDocument(
              width: side[0],
              height: side[1],
              layers: const [],
              mergedImageData: merged,
            ),
          ),
          throwsA(isA<PsdFormatException>()),
          reason: '${side[0]}×${side[1]} 应被拒绝',
        );
      }
    });

    test('没有图层时按空文档写出图层信息段', () {
      final bytes = PsdWriter.write(
        PsdDocument(
          width: 4,
          height: 4,
          layers: const [],
          mergedImageData: _mergedData(width: 4, height: 4),
        ),
      );
      final parsed = PsdTestFile.parse(bytes);

      expect(parsed.layerInfoLength, 0);
      expect(parsed.layerCount, 0);
      expect(parsed.layers, isEmpty);
      expect(parsed.layerAndMaskLength, 8);
      expect(parsed.consumedBytes, bytes.length);
    });

    test('图层内容为奇数长度时补零字节并按偶数上报', () {
      // RLE 通道数据长度可以是奇数，图层信息段因此需要真的写一个补齐字节；
      // 只把上报长度加一、不写字节会让后面所有段落错位一个字节。
      final layer = PsdLayer(
        name: 'odd',
        top: 0,
        left: 0,
        width: 2,
        height: 1,
        channelData: [
          // 2 字节压缩方式 + 2 字节行长度表 + 3 字节数据 = 7 字节
          Uint8List.fromList(<int>[0, 1, 0, 3, 1, 0xAA, 0xBB]),
          // 2 + 2 + 2 字节重复码 = 6 字节
          for (var channel = 0; channel < 3; channel++)
            Uint8List.fromList(<int>[0, 1, 0, 2, 0xFF, 0xCC]),
        ],
      );
      final bytes = PsdWriter.write(
        PsdDocument(
          width: 4,
          height: 4,
          layers: [layer],
          mergedImageData: _mergedData(width: 4, height: 4),
        ),
      );
      final parsed = PsdTestFile.parse(bytes);

      expect(parsed.layerInfoLength.isEven, isTrue);
      expect(parsed.consumedBytes, bytes.length);
      expect(parsed.mergedCompression, 1);
      // 头部 26 字节 + 颜色模式数据 4 + 图像资源 4 + 段长度 4 之后才是图层信息段。
      expect(bytes[38 + parsed.layerInfoLength - 1], 0);
      expect(parsed.layers.single.channelLengths, orderedEquals(<int>[7, 6, 6, 6]));
    });

    test('通道数不是四个或通道数据非 RLE 时报错', () {
      final merged = _mergedData(width: 2, height: 2);
      expect(
        () => PsdWriter.write(
          PsdDocument(
            width: 2,
            height: 2,
            layers: [
              PsdLayer(
                name: 'bad',
                top: 0,
                left: 0,
                width: 2,
                height: 2,
                channelData: [Uint8List(2 + 4), Uint8List(2 + 4)],
              ),
            ],
            mergedImageData: merged,
          ),
        ),
        throwsA(isA<PsdFormatException>()),
      );
      expect(
        () => PsdWriter.write(
          PsdDocument(
            width: 2,
            height: 2,
            layers: [
              PsdLayer(
                name: 'raw',
                top: 0,
                left: 0,
                width: 2,
                height: 2,
                // 压缩方式 0（raw）在只支持 RLE 的写入器里必须被拒绝。
                channelData: [
                  for (var channel = 0; channel < 4; channel++)
                    Uint8List(2 + 2 * 2),
                ],
              ),
            ],
            mergedImageData: merged,
          ),
        ),
        throwsA(isA<PsdFormatException>()),
      );
    });
  });
}

/// 一个最小可用的文档：可选图层（默认一层纯色）+ 合并预览。
PsdDocument _document({
  required int width,
  required int height,
  List<PsdLayer>? layers,
}) {
  return PsdDocument(
    width: width,
    height: height,
    layers: layers ?? [_solidLayer(name: 'bg', top: 0, left: 0, width: width, height: height)],
    mergedImageData: _mergedData(width: width, height: height),
  );
}

/// 纯色图层：R/G/B 取不同值，A 满不透明。
PsdLayer _solidLayer({
  required String name,
  required int top,
  required int left,
  required int width,
  required int height,
  bool clipping = false,
  bool visible = true,
}) {
  final rgba = Uint8List(width * height * 4);
  for (var index = 0; index < width * height; index++) {
    rgba[index * 4] = 12;
    rgba[index * 4 + 1] = 34;
    rgba[index * 4 + 2] = 56;
    rgba[index * 4 + 3] = 255;
  }
  return PsdLayer(
    name: name,
    top: top,
    left: left,
    width: width,
    height: height,
    channelData: PsdRleEncoder.encodeLayerChannels(
      rgba: rgba,
      width: width,
      height: height,
    ),
    clipping: clipping,
    visible: visible,
  );
}

Uint8List _mergedData({required int width, required int height}) =>
    PsdRleEncoder.encodeMergedImageData(
      rgba: Uint8List(width * height * 4),
      width: width,
      height: height,
    );
