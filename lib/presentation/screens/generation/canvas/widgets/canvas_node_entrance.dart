import 'package:flutter/material.dart';

/// 节点首次挂载时的入场动画；生成快照的原位替换不重新播放。
///
/// 只在挂载时播一次，不参与布局，也不影响命中区；Reduce Motion 直接到终态。
class CanvasNodeEntrance extends StatefulWidget {
  const CanvasNodeEntrance({
    super.key,
    required this.enabled,
    required this.child,
  });

  final bool enabled;
  final Widget child;

  @override
  State<CanvasNodeEntrance> createState() => _CanvasNodeEntranceState();
}

class _CanvasNodeEntranceState extends State<CanvasNodeEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: widget.enabled ? 0 : 1,
    );
    if (widget.enabled) _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_controller.value);
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.94 + 0.06 * t,
            alignment: Alignment.center,
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
