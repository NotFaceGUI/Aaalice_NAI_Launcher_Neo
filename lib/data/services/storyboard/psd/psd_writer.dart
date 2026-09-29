import 'dart:typed_data';

import 'psd_document.dart';

/// 极简 PSD 写入器：只写版本 1（PSD）、RGB/8-bit、正常混合、无 ICC 的文件。
///
/// 结构完全按 Adobe 的 PSD 规范排列：头部 → 颜色模式数据 → 图像资源 →
/// 图层与蒙版信息 → 图像数据。不支持的场景（非 RLE 通道、层数或边长越界）
/// 一律抛 [PsdFormatException]，不静默降级——写出一个 Photoshop 打不开或
/// 显示错误的文件，比导出失败更糟。
class PsdWriter {
  PsdWriter._();

  /// 写入文件的通道数：R、G、B、A。
  static const int channelCount = 4;

  /// 通道 ID：颜色通道 0/1/2，透明通道固定为 -1。
  static const List<int> _channelIds = [0, 1, 2, -1];

  static const int _version = 1;
  static const int _depth = 8;
  static const int _colorModeRgb = 3;
  static const int _opacity = 255;
  static const int _rleCompression = 1;

  /// Flags 的 bit 3：Photoshop 5.0 及以后的写入者都会置位。
  static const int _photoshopV5Flag = 0x08;

  /// Flags 的 bit 1 是**隐藏**标志，不是「可见」标志。
  ///
  /// 规范的字段说明写作「bit 1 = visible」，但实际约定相反：置位表示图层
  /// 被隐藏（psd-tools 读取时是 `visible = not (flags & 2)`，本机多份真实
  /// Photoshop 文件里可见图层的 flags 也都是 0x08）。写反会让导出的 PSD
  /// 在 Photoshop 里默认全部隐藏。
  static const int _hiddenFlag = 0x02;

  // 固定签名与混合模式关键字；PSD 里都是 4 字节 ASCII。
  static final Uint8List _signature = Uint8List.fromList(
    const [0x38, 0x42, 0x50, 0x53], // '8BPS'
  );
  static final Uint8List _blendModeSignature = Uint8List.fromList(
    const [0x38, 0x42, 0x49, 0x4D], // '8BIM'
  );
  static final Uint8List _blendModeNormal = Uint8List.fromList(
    const [0x6E, 0x6F, 0x72, 0x6D], // 'norm'
  );
  static final Uint8List _unicodeNameKey = Uint8List.fromList(
    const [0x6C, 0x75, 0x6E, 0x69], // 'luni'
  );

  /// 写入完整文件。
  static Uint8List write(PsdDocument document) {
    _validate(document);

    // 图层记录很小，先算好长度再顺序写入：图层与蒙版段和图层信息段都以长度
    // 开头，提前结算可以避免为「长度为前缀」把整段通道数据再缓存一遍。
    final records = [
      for (final layer in document.layers) _layerRecord(layer),
    ];
    // 没有图层时图层信息段长度为 0（Photoshop 对空文档的写法），有图层时为
    // 「层计数 + 层记录 + 通道数据」。RLE 通道数据长度可能是奇数，因此内容
    // 之后要补一个零字节并按补齐后的长度上报。
    var layerContentLength = 0;
    if (document.layers.isNotEmpty) {
      layerContentLength = 2;
      for (var index = 0; index < document.layers.length; index++) {
        layerContentLength += records[index].length;
        layerContentLength += document.layers[index].channelBytes;
      }
    }
    final layerInfoLength = layerContentLength.isOdd
        ? layerContentLength + 1
        : layerContentLength;
    final layerAndMaskLength = 4 + layerInfoLength + 4;

    final output = BytesBuilder(copy: false);
    _writeHeader(output, document);
    _writeUint32(output, 0); // 颜色模式数据：RGB 不需要附加数据
    _writeUint32(output, 0); // 图像资源：不写 ICC 等资源块

    _writeUint32(output, layerAndMaskLength);
    if (document.layers.isEmpty) {
      _writeUint32(output, 0);
    } else {
      _writeUint32(output, layerInfoLength);
      _writeInt16(output, document.layers.length);
      for (final record in records) {
        output.add(record);
      }
      for (final layer in document.layers) {
        for (final channel in layer.channelData) {
          output.add(channel);
        }
      }
      if (layerContentLength.isOdd) output.addByte(0);
    }
    _writeUint32(output, 0); // 全局图层蒙版信息：本写入器不生成

    // 图像数据段：合并预览已经自带压缩方式与行长度表，直接续在蒙版段之后。
    output.add(document.mergedImageData);
    return output.takeBytes();
  }

  static void _validate(PsdDocument document) {
    if (document.width <= 0 || document.height <= 0) {
      throw const PsdFormatException('PSD 画布尺寸必须为正数');
    }
    if (document.width > PsdDocument.maxSide ||
        document.height > PsdDocument.maxSide) {
      throw PsdFormatException(
        'PSD 画布边长不能超过 ${PsdDocument.maxSide} 像素：'
        '${document.width}×${document.height}',
      );
    }
    if (document.layers.length > PsdDocument.maxLayers) {
      throw const PsdFormatException(
        'PSD 图层数不能超过 ${PsdDocument.maxLayers}',
      );
    }

    for (final layer in document.layers) {
      if (layer.channelData.length != channelCount) {
        throw PsdFormatException(
          '图层「${layer.name}」必须有 $channelCount 个通道，'
          '实际 ${layer.channelData.length} 个',
        );
      }
      if (layer.width <= 0 || layer.height <= 0) {
        throw PsdFormatException('图层「${layer.name}」的尺寸必须为正数');
      }
      for (final channel in layer.channelData) {
        if (channel.length < 2 + layer.height * 2 ||
            channel[0] != 0 ||
            channel[1] != _rleCompression) {
          throw PsdFormatException(
            '图层「${layer.name}」的通道数据必须是带行长度表的 RLE 数据',
          );
        }
      }
    }

    if (document.mergedImageData.length < 2 + document.height * channelCount * 2 ||
        document.mergedImageData[0] != 0 ||
        document.mergedImageData[1] != _rleCompression) {
      throw const PsdFormatException('合并预览必须是带行长度表的 RLE 数据');
    }
  }
  static void _writeHeader(BytesBuilder output, PsdDocument document) {
    output.add(_signature);
    _writeUint16(output, _version);
    for (var index = 0; index < 6; index++) {
      output.addByte(0); // Reserved，规范要求为零
    }
    _writeUint16(output, channelCount);
    _writeUint32(output, document.height);
    _writeUint32(output, document.width);
    _writeUint16(output, _depth);
    _writeUint16(output, _colorModeRgb);
  }

  /// 一条图层记录；总长度为偶数（额外数据里的补齐字节计入额外数据长度）。
  static Uint8List _layerRecord(PsdLayer layer) {
    final extra = BytesBuilder(copy: false);
    _writeUint32(extra, 0); // 图层蒙版数据：本写入器不生成
    _writeUint32(extra, 0); // 混合范围：无
    _writePascalName(extra, layer.name);
    _writeUnicodeName(extra, layer.name);
    if (extra.length.isOdd) extra.addByte(0);

    final extraBytes = extra.takeBytes();
    final record = BytesBuilder(copy: false);
    _writeInt32(record, layer.top);
    _writeInt32(record, layer.left);
    _writeInt32(record, layer.bottom);
    _writeInt32(record, layer.right);
    _writeUint16(record, layer.channelData.length);
    for (var index = 0; index < layer.channelData.length; index++) {
      _writeInt16(record, _channelIds[index]);
      _writeUint32(record, layer.channelData[index].length);
    }
    record.add(_blendModeSignature);
    record.add(_blendModeNormal);
    record.addByte(_opacity);
    record.addByte(layer.clipping ? 1 : 0);
    record.addByte(layer.visible ? _photoshopV5Flag : _photoshopV5Flag | _hiddenFlag);
    record.addByte(0); // Filler，规范要求为零
    _writeUint32(record, extraBytes.length);
    record.add(extraBytes);
    return record.takeBytes();
  }

  /// 图层名（Pascal 字符串，按 4 字节补齐）。
  ///
  /// 只保留 ASCII，其余字符写 '?'：真实名称由 `luni` 块承载，这里只是给
  /// 不读 `luni` 的老实现一个可读的回退。
  static void _writePascalName(BytesBuilder output, String name) {
    final bytes = <int>[];
    for (final unit in name.codeUnits) {
      if (bytes.length >= 255) break;
      bytes.add(unit >= 0x20 && unit < 0x7F ? unit : 0x3F);
    }
    output.addByte(bytes.length);
    output.add(bytes);
    var written = bytes.length + 1;
    while (written % 4 != 0) {
      output.addByte(0);
      written++;
    }
  }

  /// `luni` 附加信息块：`8BIM` + `luni` + 4 字节长度 + 码元数 + UTF-16BE 名称。
  ///
  /// 中文字层名必须写在这里；名称区按 4 字节补齐，补零计入块长度。
  static void _writeUnicodeName(BytesBuilder output, String name) {
    final units = name.codeUnits;
    var blockLength = 4 + units.length * 2;
    while (blockLength % 4 != 0) {
      blockLength++;
    }

    output.add(_blendModeSignature);
    output.add(_unicodeNameKey);
    _writeUint32(output, blockLength);
    _writeUint32(output, units.length);
    for (final unit in units) {
      output.addByte((unit >> 8) & 0xFF);
      output.addByte(unit & 0xFF);
    }
    for (var written = 4 + units.length * 2; written < blockLength; written++) {
      output.addByte(0);
    }
  }

  static void _writeUint16(BytesBuilder output, int value) {
    output.addByte((value >> 8) & 0xFF);
    output.addByte(value & 0xFF);
  }

  static void _writeInt16(BytesBuilder output, int value) =>
      _writeUint16(output, value.toUnsigned(16));

  static void _writeUint32(BytesBuilder output, int value) {
    output.addByte((value >> 24) & 0xFF);
    output.addByte((value >> 16) & 0xFF);
    output.addByte((value >> 8) & 0xFF);
    output.addByte(value & 0xFF);
  }

  static void _writeInt32(BytesBuilder output, int value) =>
      _writeUint32(output, value.toUnsigned(32));
}

/// PSD 结构不合法：越界尺寸、层数、通道数或通道数据格式。
///
/// 这些情况不做降级处理，由调用方提示用户而不是写出损坏的文件。
class PsdFormatException implements Exception {
  const PsdFormatException(this.message);

  final String message;

  @override
  String toString() => 'PsdFormatException: $message';
}
