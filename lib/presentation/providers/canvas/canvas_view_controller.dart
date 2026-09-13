import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/storage/local_storage_service.dart';

part 'canvas_view_controller.g.dart';

/// 无限画布的视口状态：画布空间偏移与缩放。
///
/// 平移与缩放是逐帧变化的高频状态，因此这里用 [ChangeNotifier] 而不是
/// Riverpod 状态：只有画布视图自己重建，不会波及整棵 provider 依赖树。
/// 视口活在 widget 树之外，Windows 最小化导致的零尺寸重建、断点切换或
/// 关闭画布都不会丢失位置。
///
/// 坐标约定：画布空间点 `p` 与屏幕点 `s` 的关系为 `s = p * scale + offset`。
class CanvasViewController extends ChangeNotifier {
  CanvasViewController({
    required double offsetX,
    required double offsetY,
    required double scale,
    this.restoredFromStorage = false,
    this.onViewportSettled,
  }) : _offsetX = offsetX,
       _offsetY = offsetY,
       _scale = scale.clamp(minScale, maxScale).toDouble();

  static const double minScale = 0.1;
  static const double maxScale = 4.0;

  /// 聚焦内容时的缩放上限，避免把少量内容放大到失真
  static const double maxFocusScale = 1.0;

  static const Duration animationDuration = Duration(milliseconds: 280);

  /// 是否来自上次会话保存的视口；为 false 时视图会在首次布局后自动定位内容
  final bool restoredFromStorage;

  /// 视口稳定（手势结束、动画结束）后回调，用于持久化设备专属视口
  final void Function(double offsetX, double offsetY, double scale)?
  onViewportSettled;

  double _offsetX;
  double _offsetY;
  double _scale;
  Size _viewportSize = Size.zero;
  AnimationController? _animation;
  _ViewportAnimationTarget? _animationTarget;

  double get offsetX => _offsetX;
  double get offsetY => _offsetY;
  double get scale => _scale;
  Size get viewportSize => _viewportSize;
  Offset get offset => Offset(_offsetX, _offsetY);

  bool get isAnimating => _animation?.isAnimating ?? false;

  /// 视图在布局后把自身尺寸告知控制器，用于计算可见区域与聚焦目标。
  void setViewportSize(Size size) {
    if (size == _viewportSize) return;
    _viewportSize = size;
    notifyListeners();
  }

  /// 绑定 Ticker；未绑定时聚焦与适应内容直接跳到终态（Reduce Motion 同理）。
  void attachTicker(TickerProvider vsync) {
    if (_animation != null) return;
    final animation = AnimationController(
      vsync: vsync,
      duration: animationDuration,
    )..addListener(_onAnimationTick);
    _animation = animation;
  }

  void detachTicker() {
    final animation = _animation;
    if (animation == null) return;
    animation.removeListener(_onAnimationTick);
    animation.dispose();
    _animation = null;
    _animationTarget = null;
  }

  Offset screenToCanvas(Offset screen) =>
      Offset((screen.dx - _offsetX) / _scale, (screen.dy - _offsetY) / _scale);

  Offset canvasToScreen(Offset canvas) =>
      Offset(canvas.dx * _scale + _offsetX, canvas.dy * _scale + _offsetY);

  /// 当前可见的画布空间矩形
  Rect get visibleCanvasRect {
    if (_viewportSize.isEmpty) return Rect.zero;
    return Rect.fromPoints(
      screenToCanvas(Offset.zero),
      screenToCanvas(Offset(_viewportSize.width, _viewportSize.height)),
    );
  }

  /// 视口中心的画布空间坐标；新节点默认落在这附近。
  Offset get viewportCenterInCanvas {
    if (_viewportSize.isEmpty) return Offset.zero;
    return screenToCanvas(_viewportCenter);
  }

  /// 屏幕空间平移（拖动画布）
  void panBy(Offset deltaScreen) {
    if (deltaScreen == Offset.zero) return;
    _stopAnimation();
    _offsetX += deltaScreen.dx;
    _offsetY += deltaScreen.dy;
    notifyListeners();
  }

  /// 以屏幕焦点为中心缩放；焦点下的画布点在缩放前后保持不动。
  void zoomBy(double factor, {Offset? focalScreen}) {
    if (!factor.isFinite || factor <= 0) return;
    _zoomTo(_scale * factor, focalScreen: focalScreen);
  }

  void setScale(double scale, {Offset? focalScreen}) {
    if (!scale.isFinite || scale <= 0) return;
    _zoomTo(scale, focalScreen: focalScreen);
  }

  /// 恢复 100% 缩放，保持当前视口中心对应的画布点不动。
  void resetZoom({bool animate = true}) {
    final focal = _viewportCenter;
    final canvasPoint = screenToCanvas(focal);
    _moveTo(
      offsetX: focal.dx - canvasPoint.dx,
      offsetY: focal.dy - canvasPoint.dy,
      scale: 1,
      animate: animate,
    );
  }

  /// 把视口动画移到一个画布空间矩形上。
  void focusOnCanvasRect(
    Rect rect, {
    double padding = 48,
    double? maxScaleOverride,
    bool animate = true,
  }) {
    if (rect.isEmpty || _viewportSize.isEmpty) return;
    final limit = math.max(minScale, maxScaleOverride ?? maxFocusScale);
    final availableWidth = math.max(1.0, _viewportSize.width - padding * 2);
    final availableHeight = math.max(1.0, _viewportSize.height - padding * 2);
    final nextScale = math
        .min(availableWidth / rect.width, availableHeight / rect.height)
        .clamp(minScale, limit)
        .toDouble();
    final center = rect.center;
    _moveTo(
      offsetX: _viewportSize.width / 2 - center.dx * nextScale,
      offsetY: _viewportSize.height / 2 - center.dy * nextScale,
      scale: nextScale,
      animate: animate,
    );
  }

  /// 让全部内容可见；没有内容时把画布原点放到视口中心。
  void fitToContent(Iterable<Rect> rects, {bool animate = true}) {
    Rect? union;
    for (final rect in rects) {
      if (rect.isEmpty) continue;
      union = union == null ? rect : union.expandToInclude(rect);
    }
    if (union == null) {
      if (_viewportSize.isEmpty) return;
      _moveTo(
        offsetX: _viewportSize.width / 2,
        offsetY: _viewportSize.height / 2,
        scale: 1,
        animate: animate,
      );
      return;
    }
    focusOnCanvasRect(union, maxScaleOverride: maxFocusScale, animate: animate);
  }

  /// 手势结束时提交视口，交给上层持久化。
  void commitViewport() {
    onViewportSettled?.call(_offsetX, _offsetY, _scale);
  }

  Offset get _viewportCenter =>
      Offset(_viewportSize.width / 2, _viewportSize.height / 2);

  void _zoomTo(double scale, {Offset? focalScreen}) {
    if (_viewportSize.isEmpty && focalScreen == null) {
      _zoomToAt(scale, Offset.zero);
      return;
    }
    _zoomToAt(scale, focalScreen ?? _viewportCenter);
  }

  void _zoomToAt(double scale, Offset focal) {
    final canvasPoint = screenToCanvas(focal);
    _stopAnimation();
    _scale = scale.clamp(minScale, maxScale).toDouble();
    _offsetX = focal.dx - canvasPoint.dx * _scale;
    _offsetY = focal.dy - canvasPoint.dy * _scale;
    notifyListeners();
  }

  void _moveTo({
    required double offsetX,
    required double offsetY,
    required double scale,
    required bool animate,
  }) {
    _stopAnimation();
    final targetScale = scale.clamp(minScale, maxScale).toDouble();
    final animation = _animation;
    if (!animate || animation == null) {
      _offsetX = offsetX;
      _offsetY = offsetY;
      _scale = targetScale;
      notifyListeners();
      commitViewport();
      return;
    }

    _animationTarget = _ViewportAnimationTarget(
      offsetX: offsetX,
      offsetY: offsetY,
      scale: targetScale,
      startOffsetX: _offsetX,
      startOffsetY: _offsetY,
      startScale: _scale,
    );
    animation.forward(from: 0);
  }

  void _onAnimationTick() {
    final target = _animationTarget;
    final animation = _animation;
    if (target == null || animation == null) return;
    // 单向减速，不做回弹/过冲
    final t = Curves.easeOutCubic.transform(animation.value);
    _offsetX = _lerp(target.startOffsetX, target.offsetX, t);
    _offsetY = _lerp(target.startOffsetY, target.offsetY, t);
    _scale = _lerp(target.startScale, target.scale, t);
    if (animation.isCompleted) {
      _offsetX = target.offsetX;
      _offsetY = target.offsetY;
      _scale = target.scale;
      _animationTarget = null;
      notifyListeners();
      commitViewport();
      return;
    }
    notifyListeners();
  }

  void _stopAnimation() {
    _animation?.stop();
    _animationTarget = null;
  }

  static double _lerp(double from, double to, double t) =>
      from + (to - from) * t;

  @override
  void dispose() {
    _animation?.removeListener(_onAnimationTick);
    _animation?.dispose();
    _animation = null;
    _animationTarget = null;
    super.dispose();
  }
}

class _ViewportAnimationTarget {
  const _ViewportAnimationTarget({
    required this.offsetX,
    required this.offsetY,
    required this.scale,
    required this.startOffsetX,
    required this.startOffsetY,
    required this.startScale,
  });

  final double offsetX;
  final double offsetY;
  final double scale;
  final double startOffsetX;
  final double startOffsetY;
  final double startScale;
}

/// 画布视口控制器。
///
/// keepAlive：视口与画布文档同生命周期，关闭画布或窗口最小化都不重置。
@Riverpod(keepAlive: true)
CanvasViewController canvasViewController(Ref ref) {
  final storage = ref.watch(localStorageServiceProvider);
  final saved = storage.getInfiniteCanvasViewport();
  final controller = CanvasViewController(
    offsetX: saved?.offsetX ?? 0,
    offsetY: saved?.offsetY ?? 0,
    scale: saved?.scale ?? 1,
    restoredFromStorage: saved != null,
    onViewportSettled: (offsetX, offsetY, scale) {
      unawaited(
        storage.setInfiniteCanvasViewport(
          offsetX: offsetX,
          offsetY: offsetY,
          scale: scale,
        ),
      );
    },
  );
  ref.onDispose(controller.dispose);
  return controller;
}
