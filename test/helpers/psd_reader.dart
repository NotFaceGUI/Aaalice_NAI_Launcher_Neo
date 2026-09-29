import 'dart:typed_data';

/// 测试用的最小 PSD 解析器。
///
/// 写入器按 Adobe 规范排字节，这里按同一份规范把它们读回来，断言就能直接对照
/// 字段名而不是魔法下标。解析器只覆盖本项目写出的结构（版本 1、RGB/8-bit、
/// 无蒙版与图像资源），遇到别的排列会抛 [FormatException]。
class PsdTestFile {
  PsdTestFile._({
    required this.version,
    required this.channels,
    required this.width,
    required this.height,
    required this.depth,
    required this.colorMode,
    required this.colorModeDataLength,
    required this.imageResourcesLength,
    required this.layerAndMaskLength,
    required this.layerInfoLength,
    required this.layerCount,
    required this.layers,
    required this.globalLayerMaskLength,
    required this.mergedCompression,
    required this.mergedChannelData,
    required this.consumedBytes,
  });

  final int version;
  final int channels;
  final int width;
  final int height;
  final int depth;
  final int colorMode;
  final int colorModeDataLength;
  final int imageResourcesLength;
  final int layerAndMaskLength;
  final int layerInfoLength;
  final int layerCount;
  final List<PsdTestLayer> layers;
  final int globalLayerMaskLength;
  final int mergedCompression;

  /// 合并预览的通道数据，不含开头的 2 字节压缩方式。
  final Uint8List mergedChannelData;

  /// 解析结束时消费掉的字节数，应等于文件长度。
  final int consumedBytes;

  static PsdTestFile parse(Uint8List bytes) {
    final cursor = _Cursor(bytes);
    final signature = cursor.ascii(4);
    if (signature != '8BPS') {
      throw FormatException('不是 PSD 文件：$signature');
    }
    final version = cursor.uint16();
    if (!cursor.isZero(6)) {
      throw const FormatException('PSD 头部 Reserved 必须为零');
    }
    final channels = cursor.uint16();
    final height = cursor.uint32();
    final width = cursor.uint32();
    final depth = cursor.uint16();
    final colorMode = cursor.uint16();

    final colorModeDataLength = cursor.uint32();
    cursor.skip(colorModeDataLength);
    final imageResourcesLength = cursor.uint32();
    cursor.skip(imageResourcesLength);

    final layerAndMaskLength = cursor.uint32();
    final layerAndMaskEnd = cursor.offset + layerAndMaskLength;
    final layerInfoLength = cursor.uint32();
    final layerInfoEnd = cursor.offset + layerInfoLength;

    // 长度为 0 表示这份文档没有图层，此时连层计数字段都不存在。
    var layerCount = 0;
    final layers = <PsdTestLayer>[];
    if (layerInfoLength != 0) {
      layerCount = cursor.int16();
      for (var index = 0; index < layerCount; index++) {
        layers.add(PsdTestLayer._parseRecord(cursor));
      }
      // 通道数据紧跟全部层记录，顺序与记录里的通道顺序一致。
      for (final layer in layers) {
        layer.channelData = [
          for (final length in layer.channelLengths) cursor.take(length),
        ];
      }
      // 段长度按偶数上报，内容为奇数时只允许补一个零字节。这里必须严格对齐：
      // 放宽成「不足就往前跳」会掩盖写入器的长度错误，让整份文件后段错位。
      if (cursor.offset > layerInfoEnd) {
        throw const FormatException('图层信息段长度小于实际内容');
      }
      final padding = layerInfoEnd - cursor.offset;
      if (padding > 1 || (padding == 1 && cursor.uint8() != 0)) {
        throw const FormatException('图层信息段补齐字节不合法');
      }
    }

    final globalLayerMaskLength = cursor.uint32();
    cursor.skip(globalLayerMaskLength);
    if (cursor.offset != layerAndMaskEnd) {
      throw const FormatException('图层与蒙版段长度与实际内容不一致');
    }

    final mergedCompression = cursor.uint16();
    final mergedChannelData = cursor.take(cursor.remaining);

    return PsdTestFile._(
      version: version,
      channels: channels,
      width: width,
      height: height,
      depth: depth,
      colorMode: colorMode,
      colorModeDataLength: colorModeDataLength,
      imageResourcesLength: imageResourcesLength,
      layerAndMaskLength: layerAndMaskLength,
      layerInfoLength: layerInfoLength,
      layerCount: layerCount,
      layers: layers,
      globalLayerMaskLength: globalLayerMaskLength,
      mergedCompression: mergedCompression,
      mergedChannelData: mergedChannelData,
      consumedBytes: cursor.offset,
    );
  }

  /// 按名称查图层；缺失时抛错，避免断言悄悄放过。
  PsdTestLayer layerNamed(String name) {
    for (final layer in layers) {
      if (layer.name == name) return layer;
    }
    throw StateError('没有名为「$name」的图层：${layers.map((l) => l.name)}');
  }
}

/// 一个解析出来的图层记录。
class PsdTestLayer {
  PsdTestLayer._({
    required this.top,
    required this.left,
    required this.bottom,
    required this.right,
    required this.channelIds,
    required this.channelLengths,
    required this.blendModeSignature,
    required this.blendModeKey,
    required this.opacity,
    required this.clipping,
    required this.flags,
    required this.filler,
    required this.extraDataLength,
    required this.maskDataLength,
    required this.blendingRangesLength,
    required this.pascalName,
    required this.name,
  });

  final int top;
  final int left;
  final int bottom;
  final int right;
  final List<int> channelIds;
  final List<int> channelLengths;
  final String blendModeSignature;
  final String blendModeKey;
  final int opacity;
  final int clipping;
  final int flags;
  final int filler;
  final int extraDataLength;
  final int maskDataLength;
  final int blendingRangesLength;

  /// Pascal 名称（非 ASCII 会被写入器替换为 '?'）。
  final String pascalName;

  /// `luni` 块里的 UTF-16 名称，也是 Photoshop 显示的名称。
  final String name;

  /// 每个通道的数据：压缩方式 + 行长度表 + PackBits 数据。
  List<Uint8List> channelData = const [];

  int get width => right - left;
  int get height => bottom - top;
  /// Flags 的 bit 1 是隐藏标志（置位表示隐藏），与规范文字说明相反。
  bool get visible => flags & 0x02 == 0;

  static PsdTestLayer _parseRecord(_Cursor cursor) {
    final top = cursor.int32();
    final left = cursor.int32();
    final bottom = cursor.int32();
    final right = cursor.int32();
    final channelCount = cursor.uint16();
    final channelIds = <int>[];
    final channelLengths = <int>[];
    for (var index = 0; index < channelCount; index++) {
      channelIds.add(cursor.int16());
      channelLengths.add(cursor.uint32());
    }
    final blendModeSignature = cursor.ascii(4);
    final blendModeKey = cursor.ascii(4);
    final opacity = cursor.uint8();
    final clipping = cursor.uint8();
    final flags = cursor.uint8();
    final filler = cursor.uint8();
    final extraDataLength = cursor.uint32();
    final extraEnd = cursor.offset + extraDataLength;

    final maskDataLength = cursor.uint32();
    cursor.skip(maskDataLength);
    final blendingRangesLength = cursor.uint32();
    cursor.skip(blendingRangesLength);

    final pascalLength = cursor.uint8();
    final pascalName = cursor.ascii(pascalLength);
    cursor.skipTo(cursor.offset + _padding(pascalLength + 1, 4));

    var name = pascalName;
    while (cursor.offset < extraEnd) {
      final signature = cursor.ascii(4);
      final key = cursor.ascii(4);
      final length = cursor.uint32();
      if (signature != '8BIM') {
        throw FormatException('附加信息块签名错误：$signature');
      }
      if (key == 'luni') {
        final units = cursor.uint32();
        final raw = cursor.take(units * 2);
        final codeUnits = <int>[
          for (var index = 0; index < units; index++)
            (raw[index * 2] << 8) | raw[index * 2 + 1],
        ];
        name = String.fromCharCodes(codeUnits);
        cursor.skipTo(cursor.offset + _padding(4 + units * 2, 4));
      } else {
        cursor.skip(length);
      }
    }
    cursor.skipTo(extraEnd);

    return PsdTestLayer._(
      top: top,
      left: left,
      bottom: bottom,
      right: right,
      channelIds: channelIds,
      channelLengths: channelLengths,
      blendModeSignature: blendModeSignature,
      blendModeKey: blendModeKey,
      opacity: opacity,
      clipping: clipping,
      flags: flags,
      filler: filler,
      extraDataLength: extraDataLength,
      maskDataLength: maskDataLength,
      blendingRangesLength: blendingRangesLength,
      pascalName: pascalName,
      name: name,
    );
  }
}

/// 解出一个 RLE 通道（含 2 字节压缩方式）的原始平面：行优先，每行 [width] 字节。
Uint8List decodeRleChannel(Uint8List data, int width, int height) {
  final compression = (data[0] << 8) | data[1];
  if (compression != 1) {
    throw FormatException('期望 RLE 压缩，实际压缩方式 $compression');
  }
  var offset = 2;
  final counts = <int>[];
  for (var row = 0; row < height; row++) {
    counts.add((data[offset] << 8) | data[offset + 1]);
    offset += 2;
  }
  final output = Uint8List(width * height);
  for (var row = 0; row < height; row++) {
    final count = counts[row];
    output.setRange(
      row * width,
      (row + 1) * width,
      decodePackBitsReference(
        Uint8List.sublistView(data, offset, offset + count),
        width,
      ),
    );
    offset += count;
  }
  if (offset != data.length) {
    throw const FormatException('通道数据长度与行长度表不一致');
  }
  return output;
}

/// 解出合并预览的全部通道平面；行长度表集中在文件开头，每个通道一个平面。
List<Uint8List> decodedMergedPlanes(PsdTestFile file) {
  final data = file.mergedChannelData;
  final rows = file.height * file.channels;
  final counts = <int>[
    for (var row = 0; row < rows; row++)
      (data[row * 2] << 8) | data[row * 2 + 1],
  ];
  var offset = rows * 2;
  final planes = <Uint8List>[];
  for (var channel = 0; channel < file.channels; channel++) {
    final plane = Uint8List(file.width * file.height);
    for (var row = 0; row < file.height; row++) {
      final count = counts[channel * file.height + row];
      plane.setRange(
        row * file.width,
        (row + 1) * file.width,
        decodePackBitsReference(
          Uint8List.sublistView(data, offset, offset + count),
          file.width,
        ),
      );
      offset += count;
    }
    planes.add(plane);
  }
  if (offset != data.length) {
    throw const FormatException('合并预览数据长度与行长度表不一致');
  }
  return planes;
}

/// 独立的 PackBits 解码参考实现。
///
/// 刻意与 `PsdPackBits.decode` 分开写：编码器与解码器同源时往返测试可能一起
/// 出错，参考实现只按规范字面解释操作码，用来互相印证。
Uint8List decodePackBitsReference(Uint8List data, int expectedLength) {
  final output = <int>[];
  var index = 0;
  while (index < data.length && output.length < expectedLength) {
    final header = data[index++];
    if (header < 128) {
      for (var count = 0; count <= header; count++) {
        if (index >= data.length) break;
        output.add(data[index++]);
      }
    } else if (header > 128) {
      final value = data[index++];
      for (var count = 0; count < 257 - header; count++) {
        output.add(value);
      }
    }
  }
  if (output.length != expectedLength) {
    throw FormatException(
      'PackBits 参考解码得到 ${output.length} 字节，期望 $expectedLength',
    );
  }
  return Uint8List.fromList(output);
}

int _padding(int written, int divisor) =>
    written % divisor == 0 ? 0 : divisor - written % divisor;

class _Cursor {
  _Cursor(this.bytes);

  final Uint8List bytes;
  int offset = 0;

  int get remaining => bytes.length - offset;

  int uint8() => bytes[offset++];

  int uint16() {
    final value = (bytes[offset] << 8) | bytes[offset + 1];
    offset += 2;
    return value;
  }

  int int16() {
    final value = uint16();
    return value >= 0x8000 ? value - 0x10000 : value;
  }

  int uint32() {
    final value =
        (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
    offset += 4;
    return value;
  }

  int int32() {
    final value = uint32();
    return value >= 0x80000000 ? value - 0x100000000 : value;
  }

  String ascii(int length) => String.fromCharCodes(take(length));

  Uint8List take(int length) {
    if (length < 0 || offset + length > bytes.length) {
      throw StateError('读取越界：需要 $length 字节，剩余 $remaining');
    }
    final value = Uint8List.sublistView(bytes, offset, offset + length);
    offset += length;
    return value;
  }

  void skip(int length) {
    take(length);
  }

  void skipTo(int target) {
    if (target < offset || target > bytes.length) {
      throw StateError('无法定位到偏移 $target');
    }
    offset = target;
  }

  bool isZero(int length) => take(length).every((byte) => byte == 0);
}
