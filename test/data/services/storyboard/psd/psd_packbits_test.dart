import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/services/storyboard/psd/psd_packbits.dart';

import '../../../../helpers/psd_reader.dart';

void main() {
  group('PackBits 编码', () {
    test('空区间产出空数据', () {
      expect(PsdPackBits.encode(Uint8List(0)), isEmpty);
      final data = Uint8List.fromList([1, 2, 3]);
      expect(PsdPackBits.encode(data, start: 1, end: 1), isEmpty);
    });

    test('重复串用重复码，长度上限 128', () {
      // 300 个相同字节 = 128 + 128 + 44 三段重复码。
      final encoded = PsdPackBits.encode(Uint8List(300)..fillRange(0, 300, 7));

      expect(encoded.length, 6);
      expect(encoded[0], 129); // -127，重复 128 次
      expect(encoded[1], 7);
      expect(encoded[2], 129);
      expect(encoded[3], 7);
      expect(encoded[4], 213); // 257-44，重复 44 次
      expect(encoded[5], 7);
      expect(decodePackBitsReference(encoded, 300), Uint8List(300)..fillRange(0, 300, 7));
    });

    test('两个相同字节也用重复码', () {
      expect(PsdPackBits.encode(Uint8List.fromList([9, 9])), orderedEquals(<int>[255, 9]));
    });

    test('互不相同的数据按字面串输出，超过 128 字节拆段', () {
      final source = Uint8List.fromList(
        List<int>.generate(200, (index) => (index * 7 + 3) % 256),
      );
      final encoded = PsdPackBits.encode(source);

      // 第一段字面串：1 个操作码 + 128 字节；第二段：1 + 72。
      expect(encoded[0], 127);
      expect(encoded.length, 2 + 200);
      expect(encoded[129], 71);
      expect(decodePackBitsReference(encoded, 200), source);
    });

    test('重复与字面混排可按区间编码', () {
      final source = Uint8List.fromList([
        ...List<int>.filled(5, 1),
        ...List<int>.generate(10, (index) => index + 20),
        ...List<int>.filled(3, 200),
      ]);
      final encoded = PsdPackBits.encode(source, start: 0, end: source.length);
      expect(decodePackBitsReference(encoded, source.length), source);

      // 只编码中间的字面段，起点与终点之外的数据不参与。
      final middle = PsdPackBits.encode(source, start: 5, end: 15);
      expect(decodePackBitsReference(middle, 10), source.sublist(5, 15));
    });

    test('越界区间被拒绝', () {
      final source = Uint8List.fromList([1, 2, 3]);
      expect(() => PsdPackBits.encode(source, start: 2, end: 5), throwsRangeError);
      expect(() => PsdPackBits.encode(source, start: 3, end: 1), throwsRangeError);
    });
  });

  group('PackBits 往返', () {
    test('纯色掩码行与照片行都能无损还原', () {
      final random = math.Random(20260929);
      final photo = Uint8List.fromList(
        List<int>.generate(4096, (_) => random.nextInt(256)),
      );
      final mask = Uint8List(4096)..fillRange(1024, 2048, 255);

      for (final source in [photo, mask, Uint8List(0), Uint8List.fromList([0])]) {
        final encoded = PsdPackBits.encode(source);
        expect(PsdPackBits.decode(encoded, source.length), source);
        expect(decodePackBitsReference(encoded, source.length), source);
      }
    });

    test('掩码行的压缩率远高于原图行', () {
      final mask = Uint8List(4096)..fillRange(1024, 2048, 255);
      expect(PsdPackBits.encode(mask).length, lessThan(mask.length ~/ 8));
    });

    test('内置解码器与参考解码器结果一致', () {
      final random = math.Random(7);
      final source = Uint8List.fromList(
        List<int>.generate(600, (index) {
          // 混入成段重复，覆盖两种操作码。
          if (index % 97 < 12) return 42;
          return random.nextInt(256);
        }),
      );
      final encoded = PsdPackBits.encode(source);
      expect(PsdPackBits.decode(encoded, source.length), decodePackBitsReference(encoded, source.length));
    });

    test('损坏数据被拒绝而不是静默截断', () {
      final encoded = PsdPackBits.encode(Uint8List.fromList([1, 2, 3, 4, 5]));

      expect(() => PsdPackBits.decode(encoded, 6), throwsFormatException);
      expect(
        () => PsdPackBits.decode(Uint8List.fromList([4, 1, 2]), 5),
        throwsFormatException,
      );
      expect(
        () => PsdPackBits.decode(Uint8List.fromList([255]), 2),
        throwsFormatException,
      );
      expect(() => decodePackBitsReference(encoded, 6), throwsFormatException);
    });
  });
}
