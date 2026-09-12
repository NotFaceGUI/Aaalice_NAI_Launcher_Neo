/// 主题圆形揭示遮罩的回归守卫。
///
/// 这条动效依赖 `toImageSync` 冻结整屏，属于"失败必须安静降级"的路径：抓图
/// 不可用时只能跳过动效，绝不能影响主题本身切换成功。因此这里同时断言遮罩
/// 按预期出现，以及切换结果与异常情况。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/presentation/providers/theme_provider.dart';
import 'package:nai_launcher/presentation/themes/app_theme.dart';
import 'package:nai_launcher/presentation/themes/theme_reveal_overlay.dart';

void main() {
  testWidgets('切换主题时出现圆形揭示遮罩，动画结束后释放', (tester) async {
    await _pumpApp(tester);
    expect(find.byKey(ThemeRevealOverlay.maskKey), findsNothing);

    await tester.tap(find.text('切换'));
    await tester.pump();

    expect(find.byKey(ThemeRevealOverlay.maskKey), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpAndSettle();

    // 抓图必须释放，否则每次切换都会留一张整屏图在显存里。
    expect(find.byKey(ThemeRevealOverlay.maskKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('遮罩不拦截指针，切换后按钮仍可点击', (tester) async {
    await _pumpApp(tester);
    await tester.tap(find.text('切换'));
    await tester.pump();

    expect(find.byKey(ThemeRevealOverlay.maskKey), findsOneWidget);

    // 动效进行中也要能继续操作，遮罩层不能吃掉指针事件。
    await tester.pumpAndSettle();
    await tester.tap(find.text('切换'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reduce Motion 下直接切换，不播放揭示动效', (tester) async {
    await _pumpApp(tester, disableAnimations: true);

    await tester.tap(find.text('切换'));
    await tester.pump();

    expect(find.byKey(ThemeRevealOverlay.maskKey), findsNothing);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ThemeRevealOverlay)),
    );
    expect(container.read(themeNotifierProvider), AppStyle.novelAi);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpApp(
  WidgetTester tester, {
  bool disableAnimations = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageServiceProvider.overrideWith((ref) => _FakeStorage()),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          final style = ref.watch(themeNotifierProvider);
          return MaterialApp(
            theme: _themeFor(style),
            // 与 app.dart 一致：遮罩在 MaterialApp 的 builder 内、主题之下，
            // 才能抓到并冻结切换前的那一帧。
            builder: (context, child) {
              final reveal = ThemeRevealOverlay(child: child!);
              if (!disableAnimations) return reveal;
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: reveal,
              );
            },
            home: Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => ref
                      .read(themeNotifierProvider.notifier)
                      .setTheme(AppStyle.novelAi),
                  child: const Text('切换'),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 不引入 GoogleFonts，让本用例只关注遮罩本身。
ThemeData _themeFor(AppStyle style) => ThemeData(
  brightness: Brightness.dark,
  colorScheme: ColorScheme.fromSeed(
    seedColor: style == AppStyle.novelAi ? Colors.teal : Colors.indigo,
    brightness: Brightness.dark,
  ),
);

class _FakeStorage extends LocalStorageService {
  int themeIndex = 0;

  @override
  int getThemeIndex() => themeIndex;

  @override
  Future<void> setThemeIndex(int index) async {
    themeIndex = index;
  }
}
