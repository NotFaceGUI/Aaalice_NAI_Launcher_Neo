import 'dart:typed_data';

/// 一个待写入的 PSD：版本 1（PSD）、RGB、8-bit、无 ICC 的最小结构。
///
/// 这里只描述文件内容，不含任何分镜或图库语义：图层按自下而上的顺序给出，
/// 通道数据已经是 RLE 编码结果（见 `PsdRleEncoder`）。写入由 `PsdWriter`
/// 完成，两者都不依赖 `dart:ui`，可以在纯 Dart 单测里逐字节验证。
class PsdDocument {
  const PsdDocument({
    required this.width,
    required this.height,
    required this.layers,
    required this.mergedImageData,
  });

  /// PSD（版本 1）允许的最大边长，超出只能改用 PSB（本写入器不支持）。
  static const int maxSide = 30000;

  /// 图层数量上限：层计数字段是 16 位有符号数。
  static const int maxLayers = 32767;

  /// 画布边长（像素）。
  final int width;
  final int height;

  /// 自下而上的图层顺序，与 Photoshop 图层面板自下而上一致。
  final List<PsdLayer> layers;

  /// 合并预览，即图像数据段的全部内容：
  /// 「压缩方式(2) + 全部通道的行长度表 + 全部通道数据」。
  ///
  /// Photoshop 打开文件时先显示这份像素，它必须与编辑器里的合成结果一致。
  final Uint8List mergedImageData;
}

/// 一个 PSD 图层：边界、四个通道的 RLE 数据与剪贴标志。
///
/// 边界可以超出画布（Photoshop 支持负坐标与越界矩形），但超出画布的部分
/// 既不显示也无从取回，调用方通常会把边界收进画布以限制内存。
class PsdLayer {
  const PsdLayer({
    required this.name,
    required this.top,
    required this.left,
    required this.width,
    required this.height,
    required this.channelData,
    this.clipping = false,
    this.visible = true,
  });

  /// 图层名；写入 `luni` 块，中文名也能在 Photoshop 与 Krita 里正确显示。
  final String name;

  /// 图层左上角在画布坐标系中的位置。
  final int top;
  final int left;

  /// 图层像素尺寸。
  final int width;
  final int height;

  /// R、G、B、A 四个通道的数据，每项为「压缩方式 + 行长度表 + PackBits 数据」。
  final List<Uint8List> channelData;

  /// 是否为被剪贴层（Clipping = 1）：可见区域由紧邻下方的剪贴基底决定。
  final bool clipping;

  /// 图层是否可见（Flags 的 bit 1）。
  final bool visible;

  int get right => left + width;
  int get bottom => top + height;

  /// 四个通道数据的字节总数，用于导出过程中的体积预估。
  int get channelBytes =>
      channelData.fold(0, (total, channel) => total + channel.length);
}
