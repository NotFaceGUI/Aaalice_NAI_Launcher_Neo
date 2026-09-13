import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/presentation/providers/canvas/canvas_visibility_provider.dart';
import 'package:nai_launcher/presentation/providers/character_position_canvas_provider.dart';

/// 只覆盖画布相关的本地设置，其余设置不参与测试
class _FakeCanvasSettings extends LocalStorageService {
  _FakeCanvasSettings({this.open = false});

  bool open;
  bool autoImport = true;
  int openWrites = 0;

  @override
  bool getInfiniteCanvasOpen() => open;

  @override
  Future<void> setInfiniteCanvasOpen(bool value) async {
    open = value;
    openWrites++;
  }

  @override
  bool getInfiniteCanvasAutoImport() => autoImport;

  @override
  Future<void> setInfiniteCanvasAutoImport(bool value) async {
    autoImport = value;
  }

  @override
  ({double offsetX, double offsetY, double scale})?
  getInfiniteCanvasViewport() => null;

  @override
  Future<void> setInfiniteCanvasViewport({
    required double offsetX,
    required double offsetY,
    required double scale,
  }) async {}
}

void main() {
  late _FakeCanvasSettings settings;
  late ProviderContainer container;

  setUp(() {
    settings = _FakeCanvasSettings();
    container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(settings),
        // 位置画布的可用性依赖生成参数与生成状态，这里只关心互斥行为
        characterPositionCanvasAvailableProvider.overrideWithValue(true),
      ],
    );
  });

  tearDown(() => container.dispose());

  test('默认关闭，开关状态来自本地设置', () {
    expect(container.read(infiniteCanvasVisibilityProvider), isFalse);

    container.dispose();
    settings = _FakeCanvasSettings(open: true);
    container = ProviderContainer(
      overrides: [localStorageServiceProvider.overrideWithValue(settings)],
    );
    expect(container.read(infiniteCanvasVisibilityProvider), isTrue);
  });

  test('打开与关闭都会写回本地设置', () {
    final notifier = container.read(infiniteCanvasVisibilityProvider.notifier);

    notifier.open();
    expect(container.read(infiniteCanvasVisibilityProvider), isTrue);
    expect(settings.open, isTrue);
    expect(settings.openWrites, 1);

    notifier.close();
    expect(container.read(infiniteCanvasVisibilityProvider), isFalse);
    expect(settings.open, isFalse);
    expect(settings.openWrites, 2);
  });

  test('重复设置同一状态不会重复写入', () {
    final notifier = container.read(infiniteCanvasVisibilityProvider.notifier);
    notifier.open();
    notifier.open();
    expect(settings.openWrites, 1);

    notifier.close();
    notifier.close();
    expect(settings.openWrites, 2);
  });

  test('切换在两种状态之间往返', () {
    final notifier = container.read(infiniteCanvasVisibilityProvider.notifier);
    notifier.toggle();
    expect(container.read(infiniteCanvasVisibilityProvider), isTrue);
    notifier.toggle();
    expect(container.read(infiniteCanvasVisibilityProvider), isFalse);
  });

  test('打开画布会先让角色位置画布退出', () {
    container.read(characterPositionCanvasProvider.notifier).open();
    expect(container.read(characterPositionCanvasProvider), isTrue);

    container.read(infiniteCanvasVisibilityProvider.notifier).open();
    expect(container.read(characterPositionCanvasProvider), isFalse);
    expect(container.read(infiniteCanvasVisibilityProvider), isTrue);
  });

  test('自动加入开关默认开启并可写回设置', () async {
    expect(container.read(canvasAutoImportProvider), isTrue);

    await container.read(canvasAutoImportProvider.notifier).set(false);
    expect(container.read(canvasAutoImportProvider), isFalse);
    expect(settings.autoImport, isFalse);

    container.read(canvasAutoImportProvider.notifier).toggle();
    expect(container.read(canvasAutoImportProvider), isTrue);
    expect(settings.autoImport, isTrue);
  });
}
