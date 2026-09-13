import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../../core/utils/localization_extension.dart';
import '../canvas_node_geometry.dart';

/// 四角缩放手柄：拖动改变节点尺寸，光标提示可缩放。
class CanvasResizeCornerHandle extends StatefulWidget {
  const CanvasResizeCornerHandle({
    super.key,
    required this.corner,
    required this.faded,
    required this.onHoverChanged,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
  });

  final CanvasNodeCorner corner;
  final bool faded;
  final ValueChanged<bool> onHoverChanged;
  final ValueChanged<Offset> onStart;
  final ValueChanged<Offset> onUpdate;
  final VoidCallback onEnd;
  final VoidCallback onCancel;

  @override
  State<CanvasResizeCornerHandle> createState() =>
      _CanvasResizeCornerHandleState();
}

class _CanvasResizeCornerHandleState extends State<CanvasResizeCornerHandle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: context.l10n.infinite_canvas_resize,
      child: MouseRegion(
        // 左上/右下用一条对角光标，右上/左下用另一条
        cursor: widget.corner.isLeft == widget.corner.isTop
            ? SystemMouseCursors.resizeUpLeftDownRight
            : SystemMouseCursors.resizeUpRightDownLeft,
        onEnter: (_) {
          setState(() => _hovered = true);
          widget.onHoverChanged(true);
        },
        onExit: (_) {
          setState(() => _hovered = false);
          widget.onHoverChanged(false);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onPanStart: (details) => widget.onStart(details.globalPosition),
          onPanUpdate: (details) => widget.onUpdate(details.globalPosition),
          onPanEnd: (_) => widget.onEnd(),
          onPanCancel: widget.onCancel,
          child: Center(
            child: AnimatedOpacity(
              opacity: widget.faded && !_hovered ? 0.35 : 1,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 120),
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _hovered
                      ? scheme.primary
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: scheme.primary, width: 1.5),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 四边连线手柄：从任一边拖到另一个节点即建立标注连线。
class CanvasLinkEdgeHandle extends StatefulWidget {
  const CanvasLinkEdgeHandle({
    super.key,
    required this.side,
    required this.faded,
    required this.onHoverChanged,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
  });

  final CanvasNodeSide side;
  final bool faded;
  final ValueChanged<bool> onHoverChanged;
  final void Function(Offset globalPosition) onStart;
  final void Function(Offset globalPosition) onUpdate;
  final VoidCallback onEnd;
  final VoidCallback onCancel;

  @override
  State<CanvasLinkEdgeHandle> createState() => _CanvasLinkEdgeHandleState();
}

class _CanvasLinkEdgeHandleState extends State<CanvasLinkEdgeHandle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: context.l10n.infinite_canvas_linkStart,
      child: MouseRegion(
        cursor: SystemMouseCursors.precise,
        onEnter: (_) {
          setState(() => _hovered = true);
          widget.onHoverChanged(true);
        },
        onExit: (_) {
          setState(() => _hovered = false);
          widget.onHoverChanged(false);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onPanStart: (details) => widget.onStart(details.globalPosition),
          onPanUpdate: (details) => widget.onUpdate(details.globalPosition),
          onPanEnd: (_) => widget.onEnd(),
          onPanCancel: widget.onCancel,
          child: AnimatedOpacity(
            opacity: widget.faded && !_hovered ? 0.5 : 1,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 120),
            child: Center(
              child: Icon(
                Icons.add_link_rounded,
                size: 16,
                color: scheme.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
