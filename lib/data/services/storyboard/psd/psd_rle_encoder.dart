import 'dart:typed_data';

import 'psd_packbits.dart';

/// 把 RGBA 像素编码成 PSD 的 RLE 通道数据。
///
/// PSD 的通道是平面的：先按通道、再按行。图层通道与合并预览的排版不同——
/// 图层是每个通道独立成块，合并预览则把所有通道的行长度表集中在前、数据
/// 集中在后——所以这里提供两个入口，调用方不必自己拆平面或摆长度表。
///
/// 所有入口都要求 [width] 与 [height] 为正且缓冲长度足够；像素按
/// `ImageByteFormat.rawStraightRgba` 的顺序（直通 alpha，行优先）排列。
class PsdRleEncoder {
  PsdRleEncoder._();

  /// PSD 的通道个数：R、G、B、A。
  static const int channelCount = 4;

  /// RLE 压缩方式编号，写在每段通道数据的开头。
  static const int rleCompression = 1;

  /// 图层通道：返回 R、G、B、A 四段数据，每段为
  /// 「压缩方式(2) + 行长度表(2×高) + PackBits 数据」。
  ///
  /// 一次只处理一个通道的一行，中间缓冲随行释放；调用方拿到的是压缩后的
  /// 结果，未压缩的 RGBA 缓冲可以在调用后立即丢弃。
  static List<Uint8List> encodeLayerChannels({
    required Uint8List rgba,
    required int width,
    required int height,
  }) {
    _validate(rgba, width, height);
    return [
      for (var channel = 0; channel < channelCount; channel++)
        _assembleChannel(rgba, width, height, channel),
    ];
  }

  /// 合并预览：整页像素编码为
  /// 「压缩方式(2) + 全部通道的行长度表(2×高×4) + 全部通道数据」。
  static Uint8List encodeMergedImageData({
    required Uint8List rgba,
    required int width,
    required int height,
  }) {
    _validate(rgba, width, height);
    final rowLengths = Uint8List(height * channelCount * 2);
    final rows = BytesBuilder(copy: false);
    for (var channel = 0; channel < channelCount; channel++) {
      for (var row = 0; row < height; row++) {
        final packed = _packedRow(rgba, width, row, channel);
        _writeRowLength(
          rowLengths,
          (channel * height + row) * 2,
          packed.length,
        );
        rows.add(packed);
      }
    }
    return _join(rowLengths, rows.takeBytes());
  }

  /// 单通道独立成块（图层通道的排版）。
  static Uint8List _assembleChannel(
    Uint8List rgba,
    int width,
    int height,
    int channel,
  ) {
    final rowLengths = Uint8List(height * 2);
    final rows = BytesBuilder(copy: false);
    for (var row = 0; row < height; row++) {
      final packed = _packedRow(rgba, width, row, channel);
      _writeRowLength(rowLengths, row * 2, packed.length);
      rows.add(packed);
    }
    return _join(rowLengths, rows.takeBytes());
  }

  /// 把 RGBA 中某个通道的一行取出来压缩；跨行取值必须逐像素拷贝。
  static Uint8List _packedRow(
    Uint8List rgba,
    int width,
    int row,
    int channel,
  ) {
    final rowBytes = Uint8List(width);
    var source = (row * width) * channelCount + channel;
    for (var column = 0; column < width; column++) {
      rowBytes[column] = rgba[source];
      source += channelCount;
    }
    return PsdPackBits.encode(rowBytes);
  }

  /// 行长度表用大端 2 字节；单行编码结果不会超过 65535（画布边长上限 30000，
  /// 最坏情况每 128 字节多 1 个操作码字节）。
  static void _writeRowLength(Uint8List target, int offset, int length) {
    target[offset] = (length >> 8) & 0xFF;
    target[offset + 1] = length & 0xFF;
  }

  static Uint8List _join(Uint8List rowLengths, Uint8List rows) {
    final output = Uint8List(2 + rowLengths.length + rows.length);
    // 压缩方式是大端 2 字节，RLE 即 0x0001。
    output[0] = 0;
    output[1] = rleCompression;
    output.setRange(2, 2 + rowLengths.length, rowLengths);
    output.setRange(2 + rowLengths.length, output.length, rows);
    return output;
  }

  static void _validate(Uint8List rgba, int width, int height) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('PSD 通道编码要求宽高为正数：$width×$height');
    }
    if (rgba.length < width * height * channelCount) {
      throw ArgumentError(
        'RGBA 缓冲长度不足：${rgba.length} < ${width * height * channelCount}',
      );
    }
  }
}
