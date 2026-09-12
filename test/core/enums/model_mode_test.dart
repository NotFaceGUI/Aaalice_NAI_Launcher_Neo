import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/enums/model_mode.dart';

void main() {
  group('ModelMode.applyDatasetTag', () {
    test('prepends the official dataset tag in furry mode', () {
      expect(ModelMode.furry.applyDatasetTag('1girl'), 'fur dataset, 1girl');
    });

    test('leaves the prompt untouched in anime mode', () {
      expect(ModelMode.anime.applyDatasetTag('1girl'), '1girl');
    });

    test('does not duplicate an existing dataset tag', () {
      // 官网按不含逗号的裸标签判重，两种写法都不再注入。
      for (final prompt in [
        'fur dataset, 1girl',
        'fur dataset,1girl',
        'background dataset, scenery',
      ]) {
        expect(ModelMode.furry.applyDatasetTag(prompt), prompt, reason: prompt);
      }
    });
  });

  group('ModelMode dataset tag helpers', () {
    test('detects and strips only the official furry prefix', () {
      expect(ModelMode.hasDatasetTag('fur dataset, 1girl'), isTrue);
      expect(ModelMode.stripDatasetTag('fur dataset, 1girl'), '1girl');
      // 官网的剥离正则要求逗号加空格，裸标签不构成前缀。
      expect(ModelMode.hasDatasetTag('fur dataset,1girl'), isFalse);
      expect(ModelMode.stripDatasetTag('fur dataset,1girl'), 'fur dataset,1girl');
      expect(ModelMode.hasDatasetTag('background dataset, scenery'), isFalse);
      expect(ModelMode.stripDatasetTag('1girl'), '1girl');
    });

    test('resolves stored names with anime as the fallback', () {
      expect(ModelMode.fromName('furry'), ModelMode.furry);
      expect(ModelMode.fromName('anime'), ModelMode.anime);
      expect(ModelMode.fromName(null), ModelMode.anime);
      expect(ModelMode.fromName('nonsense'), ModelMode.anime);
    });
  });
}
