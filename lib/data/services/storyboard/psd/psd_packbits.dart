import 'dart:typed_data';

/// Photoshop 的 PackBits 行压缩（PSD compression = 1）。
///
/// PSD 的每个扫描行独立压缩，行与行之间不共享状态，所以这里处理的是任意
/// 字节区间而不是「整行」。编码器只产出规范允许的两种操作码，解码器留给
/// 测试与自检做往返验证：纯色掩码行与照片行都必须是可逆的无损压缩。
class PsdPackBits {
  PsdPackBits._();

  /// 单个操作码最多覆盖的字节数，规范固定为 128。
  static const int maxRunLength = 128;

  /// 把 [source] 的 `[start, end)` 区间编码为 PackBits 数据。
  ///
  /// 重复串（≥2 字节）用重复码；其余按字面串输出，遇到下一个重复串开头或
  /// 128 字节上限时收尾。
  static Uint8List encode(Uint8List source, {int start = 0, int? end}) {
    final stop = end ?? source.length;
    if (start < 0 || stop > source.length || start > stop) {
      throw RangeError.range(stop, start, source.length, 'end');
    }
    final output = BytesBuilder(copy: false);
    var index = start;
    while (index < stop) {
      var runEnd = index;
      while (runEnd + 1 < stop &&
          source[runEnd + 1] == source[index] &&
          runEnd - index + 1 < maxRunLength) {
        runEnd++;
      }
      final runLength = runEnd - index + 1;
      if (runLength >= 2) {
        // 长度 n（2..128）编码为有符号字节 1-n，即无符号的 257-n。
        output.addByte(257 - runLength);
        output.addByte(source[index]);
        index = runEnd + 1;
        continue;
      }

      var literalEnd = index + 1;
      while (literalEnd < stop && literalEnd - index < maxRunLength) {
        if (literalEnd + 1 < stop &&
            source[literalEnd] == source[literalEnd + 1]) {
          break;
        }
        literalEnd++;
      }
      output.addByte(literalEnd - index - 1);
      output.add(Uint8List.sublistView(source, index, literalEnd));
      index = literalEnd;
    }
    return output.takeBytes();
  }

  /// 解码 PackBits 数据，要求恰好还原出 [expectedLength] 个字节。
  ///
  /// 仅用于测试与自检：数据不完整或长度不符时抛 [FormatException]，
  /// 避免往返验证在「少解一段」时误判通过。
  static Uint8List decode(Uint8List data, int expectedLength) {
    final output = Uint8List(expectedLength);
    var read = 0;
    var write = 0;
    while (read < data.length) {
      final header = data[read++];
      // 0x80 是规范里的空操作码，跳过。
      if (header == 128) continue;

      if (header < 128) {
        final count = header + 1;
        if (read + count > data.length) {
          throw const FormatException('PackBits 字面串数据不足');
        }
        if (write + count > expectedLength) {
          throw const FormatException('PackBits 输出超出预期长度');
        }
        output.setRange(write, write + count, data, read);
        read += count;
        write += count;
        continue;
      }

      final count = 257 - header;
      if (read >= data.length) {
        throw const FormatException('PackBits 重复串缺少数据字节');
      }
      if (write + count > expectedLength) {
        throw const FormatException('PackBits 输出超出预期长度');
      }
      output.fillRange(write, write + count, data[read]);
      read++;
      write += count;
    }

    if (write != expectedLength) {
      throw const FormatException('PackBits 数据长度与预期不符');
    }
    return output;
  }
}
