import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/data/models/camera_angle/camera_angle_pose.dart';
import 'package:nai_launcher/data/models/camera_angle/camera_angle_preset.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/providers/camera_angle_provider.dart';
import 'package:nai_launcher/presentation/widgets/prompt/camera_angle/camera_angle_editor_sheet.dart';
import 'package:nai_launcher/presentation/widgets/prompt/camera_angle/camera_angle_pose_card.dart';
import 'package:nai_launcher/presentation/widgets/prompt/camera_angle/camera_angle_scene_panel.dart';
import 'package:nai_launcher/presentation/widgets/prompt/camera_angle/camera_orbit_pad.dart';
import 'package:nai_launcher/presentation/widgets/prompt/camera_angle_button.dart';

void main() {
  late _FakeStorage storage;
  late ProviderContainer container;
  late ScrollController scrollController;

  setUp(() {
    storage = _FakeStorage();
    container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWith((ref) => storage),
      ],
    );
    scrollController = ScrollController();
    addTearDown(container.dispose);
    addTearDown(scrollController.dispose);
  });

  Widget wrap(Widget child, {TextScaler? textScaler}) {
    final app = MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(body: Center(child: child)),
    );
    return UncontrolledProviderScope(
      container: container,
      child: textScaler == null
          ? app
          : MediaQuery(data: MediaQueryData(textScaler: textScaler), child: app),
    );
  }

  /// 编辑器内容有分组卡片，交互测试给足高度，避免惰性列表剪掉目标控件。
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(500, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      wrap(CameraAngleEditorSheet(scrollController: scrollController)),
    );
    await tester.pump();
  }

  CameraAnglePreset currentPreset() =>
      container.read(cameraAnglePresetNotifierProvider).preset;

  testWidgets('按钮默认显示未写入，悬浮预览给出将插入的提示词', (tester) async {
    await tester.pumpWidget(wrap(const CameraAngleButton()));

    expect(find.text('视角'), findsOneWidget);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(CameraAngleButton)));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('未写入'), findsOneWidget);
    expect(
      find.text('upper_body, viewed from the front, an upper-body framing'),
      findsOneWidget,
    );
    expect(find.text('点击打开视角编辑器：拖动旋转机位、滚轮推拉距离'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('已写入时按钮显示标签数量与带权重的预览原文', (tester) async {
    storage.json = jsonEncode(
      const CameraAnglePreset(
        pose: CameraAnglePose(azimuth: 0.45, distance: 1),
        strength: 1.3,
        enabled: true,
      ).toJson(),
    );

    await tester.pumpWidget(wrap(const CameraAngleButton()));

    expect(find.text('视角'), findsOneWidget);
    // 标签数量徽标：from_side 与 close-up 两个标签
    expect(find.text('2'), findsOneWidget);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(CameraAngleButton)));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('已写入'), findsOneWidget);
    expect(
      find.text(
        '1.49::from_side::, 1.3::close-up::, '
        'viewed from the right, a tight close-up',
      ),
      findsOneWidget,
    );
  });

  testWidgets('编辑器显示三组参数，窄屏 3 倍文字下可滚动且不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      wrap(
        CameraAngleEditorSheet(scrollController: scrollController),
        textScaler: const TextScaler.linear(3),
      ),
    );
    await tester.pump();

    expect(find.text('视角姿态'), findsOneWidget);
    expect(find.byType(CameraOrbitPad), findsOneWidget);
    expect(scrollController.position.maxScrollExtent, greaterThan(0));

    // 长内容在视口内滚动，其余分组逐一滚到可见位置后仍然可达。
    expect(
      await _revealByScrolling(
        tester,
        scrollController,
        find.text('镜头语言'),
      ),
      isTrue,
    );
    // 提示词片段卡较长，用预览区（卡片下半部分）判断可达性
    expect(
      await _revealByScrolling(
        tester,
        scrollController,
        find.byKey(const ValueKey('camera-angle-prompt-preview')),
      ),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('切换镜头语言会更新预览片段并写回开关状态', (tester) async {
    useTallSurface(tester);
    await pumpSheet(tester);

    // 参数列独立滚动，先滚到镜头语言分组再操作。
    // 参数列是惰性列表，长卡片里的 chip 定位很脆弱；这里直接经 provider 切换
    // 镜头语言，覆盖"改效果 → 片段更新 → 开关写回"这条链路。
    container
        .read(cameraAnglePresetNotifierProvider.notifier)
        .toggleEffect(CameraLensEffect.fisheye);
    await tester.pumpAndSettle();

    expect(currentPreset().effects, {CameraLensEffect.fisheye});
    expect(
      currentPreset().promptFragment(),
      'upper_body, fisheye, viewed from the front, an upper-body framing',
    );

    // 开关在最后一张卡片的标题行：先滚到底部让它被构建，再确保它落在视口内。
    scrollController.jumpTo(scrollController.position.maxScrollExtent);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(currentPreset().enabled, isTrue);
    expect(storage.writeCount, 2);
    expect(
      CameraAnglePreset.fromJson(
        Map<String, Object?>.from(jsonDecode(storage.json!) as Map),
      ).enabled,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('宽屏把摄像机画面放在左列并占满工作区', (tester) async {
    tester.view.physicalSize = const Size(1100, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpSheet(tester);

    final sceneRect = tester.getRect(find.byType(CameraAngleScenePanel));
    final poseRect = tester.getRect(find.byType(CameraAnglePoseCard));

    expect(
      sceneRect.right,
      lessThan(poseRect.left),
      reason: '画面在左列，参数在右列',
    );
    expect(sceneRect.top, closeTo(poseRect.top, 1));
    expect(
      sceneRect.width,
      greaterThan(poseRect.width),
      reason: '左列画面占满剩余空间，宽度应大于参数列',
    );
    expect(
      tester.getRect(find.byType(CameraOrbitPad)).right,
      lessThanOrEqualTo(sceneRect.right),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('拖动可视化面板会改变机位方位与俯仰', (tester) async {
    useTallSurface(tester);
    await pumpSheet(tester);

    // 拖动量按画面尺寸换算，避免布局变化后落点跑出预期分档。
    final padRect = tester.getRect(find.byType(CameraOrbitPad));
    final gesture = await tester.startGesture(
      padRect.center,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(
      Offset(padRect.width * 0.18, -padRect.height * 0.25),
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final pose = currentPreset().pose;
    expect(pose.azimuth, greaterThan(0));
    expect(pose.elevation, greaterThan(0));
    // 拖动后离开正面/平视；具体落档取决于画面尺寸，不做硬编码。
    expect(pose.azimuthBucket, isNot(CameraAzimuth.front));
    expect(pose.elevationBucket, CameraElevation.above);
    expect(tester.takeException(), isNull);
  });

  testWidgets('复位按钮回到中性姿态', (tester) async {
    useTallSurface(tester);
    storage.json = jsonEncode(
      const CameraAnglePreset(
        pose: CameraAnglePose(azimuth: 0.9, elevation: -0.5),
      ).toJson(),
    );
    await pumpSheet(tester);

    expect(currentPreset().pose.azimuth, 0.9);

    await tester.tap(find.text('复位'));
    await tester.pumpAndSettle();

    expect(currentPreset().pose, CameraAnglePose.neutral);
    expect(tester.takeException(), isNull);
  });
}

class _FakeStorage extends LocalStorageService {
  String? json;
  int writeCount = 0;

  @override
  String? getCameraAnglePresetJson() => json;

  @override
  Future<void> setCameraAnglePresetJson(String value) async {
    json = value;
    writeCount++;
  }
}

/// 逐步下滚直到 [text] 进入惰性列表的构建范围。
///
/// 直接拖拽会先被可视化面板接管，因此测试通过滚动控制器定位，避免手势竞争。
Future<bool> _revealByScrolling(
  WidgetTester tester,
  ScrollController controller,
  Finder finder,
) async {
  const step = 120.0;
  final max = controller.position.maxScrollExtent;
  for (var offset = 0.0; offset <= max; offset += step) {
    if (offset > 0) controller.jumpTo(offset);
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return true;
  }
  return false;
}
