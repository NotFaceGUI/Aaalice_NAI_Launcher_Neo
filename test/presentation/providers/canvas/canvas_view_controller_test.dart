import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/providers/canvas/canvas_view_controller.dart';

void main() {
  CanvasViewController build({
    double offsetX = 0,
    double offsetY = 0,
    double scale = 1,
    void Function(double, double, double)? onSettled,
  }) {
    return CanvasViewController(
      offsetX: offsetX,
      offsetY: offsetY,
      scale: scale,
      onViewportSettled: onSettled,
    );
  }

  test('屏幕坐标与画布坐标互为逆变换', () {
    final controller = build(offsetX: 120, offsetY: -40, scale: 2);
    addTearDown(controller.dispose);

    const canvasPoint = Offset(35, -12.5);
    final screen = controller.canvasToScreen(canvasPoint);
    final roundTrip = controller.screenToCanvas(screen);
    expect(roundTrip.dx, closeTo(canvasPoint.dx, 1e-9));
    expect(roundTrip.dy, closeTo(canvasPoint.dy, 1e-9));
  });

  test('以焦点缩放时焦点下的画布点保持不动', () {
    final controller = build(offsetX: 30, offsetY: 10, scale: 1);
    addTearDown(controller.dispose);

    const focal = Offset(240, 180);
    final before = controller.screenToCanvas(focal);
    controller.zoomBy(1.8, focalScreen: focal);
    final after = controller.screenToCanvas(focal);

    expect(after.dx, closeTo(before.dx, 1e-9));
    expect(after.dy, closeTo(before.dy, 1e-9));
    expect(controller.scale, closeTo(1.8, 1e-9));
  });

  test('缩放被夹在允许区间内', () {
    final controller = build();
    addTearDown(controller.dispose);

    controller.setScale(1000, focalScreen: Offset.zero);
    expect(controller.scale, CanvasViewController.maxScale);

    controller.setScale(0.0001, focalScreen: Offset.zero);
    expect(controller.scale, CanvasViewController.minScale);
  });

  test('平移按屏幕增量移动偏移', () {
    final controller = build(offsetX: 10, offsetY: 20, scale: 2);
    addTearDown(controller.dispose);

    controller.panBy(const Offset(15, -5));
    expect(controller.offsetX, 25);
    expect(controller.offsetY, 15);
  });

  test('可见矩形与视口中心随变换更新', () {
    final controller = build(offsetX: -100, offsetY: -50, scale: 2);
    addTearDown(controller.dispose);
    controller.setViewportSize(const Size(400, 300));

    final visible = controller.visibleCanvasRect;
    expect(visible.left, closeTo(50, 1e-9));
    expect(visible.top, closeTo(25, 1e-9));
    expect(visible.width, closeTo(200, 1e-9));
    expect(visible.height, closeTo(150, 1e-9));

    final center = controller.viewportCenterInCanvas;
    expect(center.dx, closeTo(150, 1e-9));
    expect(center.dy, closeTo(100, 1e-9));
  });

  test('聚焦矩形时把内容居中且不放大超过上限', () {
    final controller = build();
    addTearDown(controller.dispose);
    controller.setViewportSize(const Size(600, 400));

    controller.focusOnCanvasRect(
      const Rect.fromLTWH(1000, 500, 100, 80),
      animate: false,
    );

    expect(controller.scale, CanvasViewController.maxFocusScale);
    final center = controller.canvasToScreen(const Offset(1050, 540));
    expect(center.dx, closeTo(300, 1e-6));
    expect(center.dy, closeTo(200, 1e-6));
  });

  test('适应内容时合并全部矩形', () {
    final controller = build();
    addTearDown(controller.dispose);
    controller.setViewportSize(const Size(600, 400));

    controller.fitToContent(const [
      Rect.fromLTWH(0, 0, 100, 100),
      Rect.fromLTWH(300, 200, 100, 100),
    ], animate: false);

    final unionCenter = controller.canvasToScreen(const Offset(200, 150));
    expect(unionCenter.dx, closeTo(300, 1e-6));
    expect(unionCenter.dy, closeTo(200, 1e-6));
  });

  test('没有内容时把画布原点放到视口中心', () {
    final controller = build(offsetX: 999, offsetY: 999, scale: 3);
    addTearDown(controller.dispose);
    controller.setViewportSize(const Size(500, 300));

    controller.fitToContent(const [], animate: false);

    expect(controller.scale, 1);
    final origin = controller.canvasToScreen(Offset.zero);
    expect(origin.dx, closeTo(250, 1e-9));
    expect(origin.dy, closeTo(150, 1e-9));
  });

  test('提交视口时上报当前偏移与缩放', () {
    final settled = <({double x, double y, double scale})>[];
    final controller = build(
      offsetX: 5,
      offsetY: 6,
      scale: 1.5,
      onSettled: (x, y, scale) => settled.add((x: x, y: y, scale: scale)),
    );
    addTearDown(controller.dispose);

    controller.commitViewport();
    expect(settled, hasLength(1));
    expect(settled.single.x, 5);
    expect(settled.single.y, 6);
    expect(settled.single.scale, 1.5);
  });

  test('未绑定 Ticker 时聚焦直接到达终态并提交视口', () {
    final committed = <double>[];
    final controller = build(onSettled: (_, __, scale) => committed.add(scale));
    addTearDown(controller.dispose);
    controller.setViewportSize(const Size(400, 300));

    controller.resetZoom();
    expect(controller.scale, 1);
    expect(committed, isNotEmpty);
  });

  test('视口尺寸不变时不重复通知', () {
    final controller = build();
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.setViewportSize(const Size(300, 200));
    controller.setViewportSize(const Size(300, 200));
    expect(notifications, 1);
  });
}
