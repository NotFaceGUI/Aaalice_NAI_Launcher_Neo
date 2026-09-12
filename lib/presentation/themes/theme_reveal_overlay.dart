/// 主题切换的圆形遮罩揭示动效。
///
/// 主题变化只能整体替换 `ThemeData`，想让新旧主题同屏就只能把旧画面冻结下来：
/// 在主题改写之前把整屏抓成一张图，主题生效后用它盖住屏幕，再从触发点挖一个
/// 不断扩大的圆洞。之所以不用"把 child 放进树里两次"的写法，是因为那会复制
/// Navigator、Provider 和全部页面状态，属于实打实的正确性问题。
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nai_launcher/presentation/providers/theme_provider.dart';

/// 包住整个应用，在任何主题切换时播放一次圆形揭示。
class ThemeRevealOverlay extends ConsumerStatefulWidget {
  const ThemeRevealOverlay({super.key, required this.child});

  /// 被揭示的应用内容。
  final Widget child;

  /// 揭示时长。比常规过渡略长，让圆的推进可被看清。
  static const Duration revealDuration = Duration(milliseconds: 450);

  /// 认为"刚刚点过"的时间窗。超出后从屏幕中心揭示。
  static const Duration pointerFreshness = Duration(milliseconds: 1500);

  /// 揭示遮罩层的 key，供测试与调试定位。
  static const Key maskKey = ValueKey('theme-reveal-mask');

  @override
  ConsumerState<ThemeRevealOverlay> createState() => _ThemeRevealOverlayState();
}

class _ThemeRevealOverlayState extends ConsumerState<ThemeRevealOverlay>
    with SingleTickerProviderStateMixin {
  final GlobalKey _boundaryKey = GlobalKey();

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: ThemeRevealOverlay.revealDuration,
  )..addStatusListener(_handleStatus);

  ui.Image? _frozen;
  Size _frozenSize = Size.zero;
  Offset _origin = Offset.zero;

  Offset? _lastPointerDown;
  DateTime? _lastPointerDownAt;

  @override
  void dispose() {
    _controller.dispose();
    _releaseFrozen();
    super.dispose();
  }

  void _releaseFrozen() {
    _frozen?.dispose();
    _frozen = null;
  }

  void _handleStatus(AnimationStatus status) {
    // 揭示结束就释放整屏抓图，不让它长期占着显存。
    if (status == AnimationStatus.completed && _frozen != null) {
      setState(_releaseFrozen);
    }
  }

  /// 在主题改写之前冻结当前画面。拿不到就退化为直接切换。
  ///
  /// 这里必须在 `setTheme` 生效、下一帧绘制之前调用，否则抓到的已经是新主题。
  void _freezeCurrentFrame() {
    _releaseFrozen();
    final boundary = _boundaryKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || !boundary.hasSize) return;
    try {
      // 只在不到半秒的过渡里展示，按逻辑像素抓图即可：DPR 3 的手机上按物理
      // 像素抓图会多出数倍显存，而这段画面是被遮挡后又迅速消失的中间态。
      _frozen = boundary.toImageSync(pixelRatio: 1);
      _frozenSize = boundary.size;
    } catch (_) {
      // toImageSync 在图层尚未绘制等情况下会失败，此时安静地跳过动效。
      _releaseFrozen();
    }
  }

  Offset _resolveOrigin(Size size) {
    final pointer = _lastPointerDown;
    final at = _lastPointerDownAt;
    final isFresh =
        pointer != null &&
        at != null &&
        DateTime.now().difference(at) < ThemeRevealOverlay.pointerFreshness;
    final origin = isFresh ? pointer : size.center(Offset.zero);
    return Offset(
      origin.dx.clamp(0.0, size.width),
      origin.dy.clamp(0.0, size.height),
    );
  }

  void _handleThemeChanged() {
    _freezeCurrentFrame();
    final frozen = _frozen;
    if (frozen == null) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _releaseFrozen();
      return;
    }
    _origin = _resolveOrigin(_frozenSize);
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(themeNotifierProvider, (previous, next) {
      if (previous == next) return;
      _handleThemeChanged();
    });

    final frozen = _frozen;
    return Listener(
      onPointerDown: (event) {
        _lastPointerDown = event.localPosition;
        _lastPointerDownAt = DateTime.now();
      },
      child: Stack(
        children: [
          // 抓图目标只包住应用内容：遮罩层是它的兄弟节点，不会被抓进去，
          // 否则连续切换主题会把上一次的遮罩叠进新画面。
          RepaintBoundary(key: _boundaryKey, child: widget.child),
          if (frozen != null)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => CustomPaint(
                    key: ThemeRevealOverlay.maskKey,
                    painter: _CircleRevealPainter(
                      image: frozen,
                      center: _origin,
                      progress: Curves.easeInOutCubic.transform(
                        _controller.value,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 把冻结的旧画面画出来，并在 [center] 处挖掉一个半径为 [progress] 比例的圆洞。
class _CircleRevealPainter extends CustomPainter {
  const _CircleRevealPainter({
    required this.image,
    required this.center,
    required this.progress,
  });

  final ui.Image image;
  final Offset center;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress >= 1) return;

    final hole = Path()
      ..addOval(
        Rect.fromCircle(
          center: center,
          radius: _farthestCornerDistance(center, size) * progress,
        ),
      );
    final screen = Path()..addRect(Offset.zero & size);
    final remaining = Path.combine(PathOperation.difference, screen, hole);
    if (remaining.getBounds().isEmpty) return;

    canvas.save();
    canvas.clipPath(remaining);
    canvas.drawImageRect(
      image,
      Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.low,
    );
    canvas.restore();
  }

  /// 圆心到最远屏幕角点的距离，保证 progress 到 1 时圆洞覆盖整屏。
  double _farthestCornerDistance(Offset center, Size size) {
    final corners = <Offset>[
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ];
    var farthest = 0.0;
    for (final corner in corners) {
      farthest = math.max(farthest, (corner - center).distance);
    }
    return farthest;
  }

  @override
  bool shouldRepaint(_CircleRevealPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.center != center ||
      oldDelegate.progress != progress;
}
