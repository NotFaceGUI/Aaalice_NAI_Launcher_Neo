import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/canvas/canvas_node.dart';
import 'package:nai_launcher/data/models/canvas/canvas_node_kind.dart';
import 'package:nai_launcher/data/models/canvas/canvas_node_params.dart';
import 'package:nai_launcher/data/models/image/image_params.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/providers/generation/generation_params_notifier.dart';
import 'package:nai_launcher/presentation/screens/generation/canvas/canvas_actions.dart';
import 'package:nai_launcher/presentation/widgets/common/generation_parameter_selection.dart';

class _Params extends GenerationParamsNotifier {
  @override
  ImageParams build() => const ImageParams(seed: 12, prompt: 'unchanged');
  @override
  void updateSeed(int seed) => state = state.copyWith(seed: seed);
}

void main() {
  final stamp = DateTime.fromMillisecondsSinceEpoch(0);
  final node = CanvasNode(
    id: 'note',
    kind: CanvasNodeKind.seedTodo,
    x: 0,
    y: 0,
    width: 200,
    height: 120,
    seed: 42,
    params: const CanvasNodeParams(
      prompt: 'portrait',
      model: 'nai-diffusion-4-5-full',
      width: 832,
      height: 1216,
      steps: 28,
      scale: 5,
    ),
    createdAt: stamp,
    updatedAt: stamp,
  );

  Future<ProviderContainer> open(
    WidgetTester tester, {
    double width = 900,
    double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(
      overrides: [generationParamsNotifierProvider.overrideWith(_Params.new)],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 400));
      container.dispose();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => showCanvasLoadParamsDialog(
                  context: context,
                  ref: ref,
                  node: node,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return container;
  }

  for (final width in [320.0, 600.0, 840.0, 1180.0, 1600.0]) {
    testWidgets('canvas shares AI TAG picker at $width and 3x text', (
      tester,
    ) async {
      await open(tester, width: width, textScale: 3);
      expect(
        find.byType(GenerationParameterSelection<CanvasParamField>),
        findsOneWidget,
      );
      final sampler = find.byKey(const ValueKey('canvas-parameter-sampler'));
      await tester.scrollUntilVisible(
        sampler,
        180,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(sampler).onChanged, isNull);
      final size = find.byKey(const ValueKey('canvas-parameter-size'));
      await tester.ensureVisible(size);
      await tester.pumpAndSettle();
      expect(find.text('832 x 1216'), findsOneWidget);
      expect(size.hitTestable(), findsOneWidget);
      expect(
        find.byKey(const ValueKey('canvas-parameter-submit')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    });
  }

  testWidgets(
    'selecting only seed preserves prompt and clear disables submit',
    (tester) async {
      final container = await open(tester);
      await tester.tap(find.byIcon(Icons.clear_all));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('canvas-parameter-submit')),
            )
            .onPressed,
        isNull,
      );
      final seed = find.byKey(const ValueKey('canvas-parameter-seed'));
      await tester.ensureVisible(seed);
      await tester.tap(seed);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('canvas-parameter-submit')));
      await tester.pumpAndSettle();
      final params = container.read(generationParamsNotifierProvider);
      expect(params.seed, 42);
      expect(params.prompt, 'unchanged');
    },
  );
}
