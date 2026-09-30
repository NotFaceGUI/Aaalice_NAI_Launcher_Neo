import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/character/character_interaction.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/widgets/character/character_interaction_bar.dart';

void main() {
  Future<List<CharacterInteraction?>> pumpBar(
    WidgetTester tester, {
    CharacterInteraction? interaction,
    bool compact = false,
  }) async {
    final changes = <CharacterInteraction?>[];
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: SingleChildScrollView(
            child: CharacterInteractionBar(
              interaction: interaction,
              onChanged: changes.add,
              compact: compact,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return changes;
  }

  Future<void> expand(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pump();
  }

  testWidgets('默认收起，只显示一行摘要', (tester) async {
    await pumpBar(tester);

    expect(find.text('互动'), findsOneWidget);
    expect(find.text('未设置'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, '拥抱'), findsNothing);

    await expand(tester);

    expect(find.widgetWithText(FilterChip, '拥抱'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('摘要显示当前身份与动作，自定义动作显示原文', (tester) async {
    await pumpBar(
      tester,
      interaction: const CharacterInteraction(
        role: CharacterInteractionRole.target,
        action: 'hug',
      ),
    );
    expect(find.text('承受（target#） · 拥抱'), findsOneWidget);

    await pumpBar(
      tester,
      interaction: const CharacterInteraction(
        role: CharacterInteractionRole.source,
        action: 'pointing at another',
      ),
    );
    expect(find.text('主动（source#） · pointing at another'), findsOneWidget);
  });

  testWidgets('未设置时默认按主动方写入标签', (tester) async {
    final changes = await pumpBar(tester);
    await expand(tester);

    await tester.tap(find.widgetWithText(FilterChip, '拥抱'));
    await tester.pump();

    expect(changes, [
      const CharacterInteraction(
        role: CharacterInteractionRole.source,
        action: 'hug',
      ),
    ]);
  });

  testWidgets('先选承受方再点动作，写入的是 target#', (tester) async {
    final changes = await pumpBar(tester);
    await expand(tester);

    await tester.tap(find.text('承受（target#）'));
    await tester.pump();
    // 只切换身份不应改动提示词
    expect(changes, isEmpty);

    await tester.tap(find.widgetWithText(FilterChip, '接吻'));
    await tester.pump();

    expect(changes, [
      const CharacterInteraction(
        role: CharacterInteractionRole.target,
        action: 'kiss',
      ),
    ]);
  });

  testWidgets('已有标签时切换身份保留动作', (tester) async {
    final changes = await pumpBar(
      tester,
      interaction: const CharacterInteraction(
        role: CharacterInteractionRole.source,
        action: 'hug',
      ),
    );
    await expand(tester);

    await tester.tap(find.text('互相（mutual#）'));
    await tester.pump();

    expect(changes, [
      const CharacterInteraction(
        role: CharacterInteractionRole.mutual,
        action: 'hug',
      ),
    ]);
  });

  testWidgets('再次点击已选动作会清除标签', (tester) async {
    final changes = await pumpBar(
      tester,
      interaction: const CharacterInteraction(
        role: CharacterInteractionRole.source,
        action: 'hug',
      ),
    );
    await expand(tester);

    await tester.tap(find.widgetWithText(FilterChip, '拥抱'));
    await tester.pump();

    expect(changes, [null]);
  });

  testWidgets('清除按钮只在已有标签时出现', (tester) async {
    final withoutTag = await pumpBar(tester);
    expect(find.byTooltip('清除'), findsNothing);
    expect(withoutTag, isEmpty);

    final changes = await pumpBar(
      tester,
      interaction: const CharacterInteraction(
        role: CharacterInteractionRole.target,
        action: 'holding_hands',
      ),
    );
    expect(find.byTooltip('清除'), findsOneWidget);

    await tester.tap(find.byTooltip('清除'));
    await tester.pump();

    expect(changes, [null]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('可以输入自定义动作并写入', (tester) async {
    final changes = await pumpBar(tester);
    await expand(tester);

    await tester.enterText(
      find.byKey(const ValueKey('character-interaction-custom-action')),
      'pointing at another',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, '写入'));
    await tester.pump();

    expect(changes, [
      const CharacterInteraction(
        role: CharacterInteractionRole.source,
        action: 'pointing at another',
      ),
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('自定义动作回填输入框，且空输入不可提交', (tester) async {
    await pumpBar(
      tester,
      interaction: const CharacterInteraction(
        role: CharacterInteractionRole.target,
        action: 'pointing at another',
      ),
    );
    await expand(tester);

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('character-interaction-custom-action')),
    );
    expect(field.controller!.text, 'pointing at another');

    await tester.enterText(
      find.byKey(const ValueKey('character-interaction-custom-action')),
      '   ',
    );
    await tester.pump();

    expect(
      tester.widget<TextButton>(find.widgetWithText(TextButton, '写入')).onPressed,
      isNull,
    );
  });

  testWidgets('窄卡内收起一行、展开后单行动作条不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(3)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: CharacterInteractionBar(
                interaction: null,
                onChanged: (_) {},
                compact: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await expand(tester);

    expect(find.widgetWithText(FilterChip, '拥抱'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
