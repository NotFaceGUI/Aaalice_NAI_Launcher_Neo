import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/services/storyboard/psd/psd_rle_encoder.dart';

import '../../../../helpers/psd_reader.dart';

void main() {
  group('图层通道编码', () {
    test('四个通道各自成块，行长度表与实际数据一致', () {
      const width = 3;
      const height = 2;
      final rgba = _rgbaFromPixels(
        pixels: [
          [1, 2, 3, 4],
          [5, 6, 7, 8],
          [9, 10, 11, 12],
          [13, 14, 15, 16],
          [17, 18, 19, 20],
          [21, 22, 23, 24],
        ],
      );

      final channels = PsdRleEncoder.encodeLayerChannels(
        rgba: rgba,
        width: width,
        height: height,
      );

      expect(channels, hasLength(PsdRleEncoder.channelCount));
      for (final channel in channels) {
        expect(channel.sublist(0, 2), orderedEquals(<int>[0, 1]));
      }
      expect(decodeRleChannel(channels[0], width, height), orderedEquals(<int>[1, 5, 9, 13, 17, 21]));
      expect(decodeRleChannel(channels[1], width, height), orderedEquals(<int>[2, 6, 10, 14, 18, 22]));
      expect(decodeRleChannel(channels[2], width, height), orderedEquals(<int>[3, 7, 11, 15, 19, 23]));
      expect(decodeRleChannel(channels[3], width, height), orderedEquals(<int>[4, 8, 12, 16, 20, 24]));
    });

    test('纯色掩码通道压缩到很小', () {
      const size = 64;
      final rgba = Uint8List(size * size * 4);
      final channels = PsdRleEncoder.encodeLayerChannels(
        rgba: rgba,
        width: size,
        height: size,
      );

      // 每行 64 个相同字节 = 1 个操作码 + 1 个数据字节；再加压缩方式与行长度表。
      for (final channel in channels) {
        expect(channel.length, 2 + size * 2 + size * 2);
        expect(decodeRleChannel(channel, size, size), Uint8List(size * size));
      }
    });

    test('尺寸或缓冲不合法时报错', () {
      final rgba = Uint8List(4 * 4 * 4);
      expect(
        () => PsdRleEncoder.encodeLayerChannels(rgba: rgba, width: 0, height: 4),
        throwsArgumentError,
      );
      expect(
        () => PsdRleEncoder.encodeLayerChannels(rgba: rgba, width: 8, height: 4),
        throwsArgumentError,
      );
      expect(
        () => PsdRleEncoder.encodeMergedImageData(rgba: Uint8List(10), width: 4, height: 4),
        throwsArgumentError,
      );
    });
  });

  group('合并预览编码', () {
    test('全部通道的行长度表集中在前，数据按通道顺序排在后面', () {
      const width = 2;
      const height = 3;
      final pixels = <List<int>>[
        for (var index = 0; index < width * height; index++)
          [index, index + 40, index + 80, index + 120],
      ];
      final rgba = _rgbaFromPixels(pixels: pixels);

      final merged = PsdRleEncoder.encodeMergedImageData(
        rgba: rgba,
        width: width,
        height: height,
      );

      expect(merged.sublist(0, 2), orderedEquals(<int>[0, 1]));
      final planes = _decodeMergedPlanes(merged, width: width, height: height);
      for (var channel = 0; channel < PsdRleEncoder.channelCount; channel++) {
        expect(
          planes[channel],
          orderedEquals(<int>[
            for (final pixel in pixels) pixel[channel],
          ]),
        );
      }
    });

    test('行长度表条目数等于高 × 通道数', () {
      const width = 5;
      const height = 4;
      final merged = PsdRleEncoder.encodeMergedImageData(
        rgba: Uint8List(width * height * 4),
        width: width,
        height: height,
      );

      // 2 字节压缩方式 + 2 字节/行 × 高 × 4 通道，之后才是数据。
      const tableBytes = height * PsdRleEncoder.channelCount * 2;
      expect(merged.length, greaterThan(2 + tableBytes));
      var counted = 0;
      for (var row = 0; row < height * PsdRleEncoder.channelCount; row++) {
        counted += (merged[2 + row * 2] << 8) | merged[3 + row * 2];
      }
      expect(counted, merged.length - 2 - tableBytes);
    });
  });
}

Uint8List _rgbaFromPixels({required List<List<int>> pixels}) {
  final rgba = Uint8List(pixels.length * 4);
  for (var index = 0; index < pixels.length; index++) {
    for (var channel = 0; channel < 4; channel++) {
      rgba[index * 4 + channel] = pixels[index][channel];
    }
  }
  return rgba;
}

/// 合并预览数据 → 每个通道的原始平面（行优先）。
List<Uint8List> _decodeMergedPlanes(
  Uint8List merged, {
  required int width,
  required int height,
}) {
  expect(merged[0], 0);
  expect(merged[1], 1);
  final counts = <int>[
    for (var row = 0; row < height * PsdRleEncoder.channelCount; row++)
      (merged[2 + row * 2] << 8) | merged[3 + row * 2],
  ];
  var offset = 2 + counts.length * 2;
  final planes = <Uint8List>[];
  for (var channel = 0; channel < PsdRleEncoder.channelCount; channel++) {
    final plane = Uint8List(width * height);
    for (var row = 0; row < height; row++) {
      final count = counts[channel * height + row];
      plane.setRange(
        row * width,
        (row + 1) * width,
        decodePackBitsReference(
          Uint8List.sublistView(merged, offset, offset + count),
          width,
        ),
      );
      offset += count;
    }
    planes.add(plane);
  }
  expect(offset, merged.length);
  return planes;
}
