import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../../core/utils/localization_extension.dart';
import '../../../../../data/models/canvas/canvas_node.dart';
import '../../../../../data/models/canvas/canvas_node_params.dart';
import '../../../../providers/canvas/canvas_node_metadata_provider.dart';
import '../../../../widgets/common/delayed_rich_tooltip.dart';
import '../../../../widgets/common/rich_tooltip_surface.dart';
import 'canvas_node_info_panel.dart';

/// 图片节点内容：缩略图、缺失占位与信息浮层。
///
/// 缩略图按节点宽度分桶解码（而不是整图解码后再缩），画布上同时出现几十个
/// 节点时内存占用保持可控；解码结果由 Flutter 的 ImageCache 按 LRU 复用。
/// 用 [BoxFit.contain] 而不是 cover：画布上不能擅自裁掉用户作品的内容；
/// 同时解码出的真实宽高比会通过 [onAspectResolved] 回报给文档，让节点盒
/// 自己贴合图片比例。
class CanvasImageNode extends ConsumerStatefulWidget {
  const CanvasImageNode({
    super.key,
    required this.node,
    required this.absolutePath,
    required this.hovered,
    required this.selected,
    required this.onAspectResolved,
    this.onImageReady,
  });

  /// 相对路径解析后的绝对路径；图库根目录不可用时为空
  final String? absolutePath;

  final CanvasNode node;
  final bool hovered;

  /// 选中时也展示信息，作为触屏没有 hover 的等价入口
  final bool selected;

  /// 解码得到真实宽高比后的回报，用于修正节点盒比例
  final void Function(double aspectRatio) onAspectResolved;
  final VoidCallback? onImageReady;

  /// 宽高比偏差超过该比例才回报，避免无意义的重复写入
  static const double _aspectTolerance = 0.01;

  @override
  ConsumerState<CanvasImageNode> createState() => _CanvasImageNodeState();
}

class _CanvasImageNodeState extends ConsumerState<CanvasImageNode> {
  bool _readyReported = false;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveAspect();
  }

  @override
  void didUpdateWidget(covariant CanvasImageNode oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.absolutePath != widget.absolutePath) _resolveAspect();
  }

  @override
  void dispose() {
    _detachListener();
    super.dispose();
  }

  void _detachListener() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    _listener = null;
    _stream = null;
  }

  /// 解析一次真实尺寸，把宽高比回报给文档。
  void _resolveAspect() {
    final path = widget.absolutePath;
    if (path == null || path.isEmpty) return;
    _detachListener();

    final provider = FileImage(File(path));
    final stream = provider.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener((info, _) {
      final width = info.image.width;
      final height = info.image.height;
      if (width > 0 && height > 0) _reportAspect(width / height);
      _detachListener();
    }, onError: (_, _) => _detachListener());
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  void _reportAspect(double aspect) {
    if (!aspect.isFinite || aspect <= 0) return;
    final node = widget.node;
    if (node.height <= 0) return;
    final currentAspect = node.width / node.height;
    if ((currentAspect - aspect).abs() / aspect <=
        CanvasImageNode._aspectTolerance) {
      return;
    }
    widget.onAspectResolved(aspect);
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.absolutePath;
    if (path == null || path.isEmpty) {
      return _MissingImage(node: widget.node);
    }

    final image = Image.file(
      File(path),
      fit: BoxFit.contain,
      // 按原始分辨率解码：画布上放大查看是常态，任何预缩放都会让作品发虚。
      // 内存由 Flutter 的 ImageCache（main.dart 已设上限）按 LRU 兜底。
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, synchronous) {
        if (frame != null || synchronous) _reportImageReady();
        return child;
      },
      errorBuilder: (context, error, stackTrace) {
        _reportImageReady();
        return _MissingImage(node: widget.node);
      },
    );

    final effectiveParams = _effectiveParams(path);
    final prompt = effectiveParams?.prompt ?? '';

    return Stack(
      fit: StackFit.expand,
      children: [
        if (prompt.isEmpty)
          image
        else
          DelayedRichTooltip(
            content: RichTooltipSurface(
              maxWidth: 340,
              child: CanvasPromptPreview(prompt: prompt),
            ),
            child: image,
          ),
        CanvasNodeInfoPanel(
          visible: widget.hovered || widget.selected,
          entries: buildCanvasImageInfoEntries(
            context: context,
            node: widget.node,
            params: effectiveParams,
          ),
        ),
      ],
    );
  }

  void _reportImageReady() {
    if (_readyReported || widget.onImageReady == null) return;
    _readyReported = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onImageReady?.call();
    });
  }

  /// 节点自带快照优先；缺失时按文件解析并补齐展示用参数。
  CanvasNodeParams? _effectiveParams(String path) {
    final snapshot = widget.node.params;
    if (snapshot != null && !snapshot.isEmpty) return snapshot;
    if (!widget.hovered && !widget.selected) return snapshot;
    final metadata = ref.watch(canvasNodeMetadataProvider(path)).valueOrNull;
    return metadata == null
        ? snapshot
        : CanvasNodeParams.fromImageMetadata(metadata);
  }
}

/// 由节点与元数据组装信息条目，图片节点与菜单共用同一份事实来源。
List<({IconData icon, String text})> buildCanvasImageInfoEntries({
  required BuildContext context,
  required CanvasNode node,
  required CanvasNodeParams? params,
}) {
  final l10n = context.l10n;
  final seed = node.seed;
  final entries = <({IconData icon, String text})>[];
  if (seed != null && seed >= 0) {
    entries.add((
      icon: Icons.tag_rounded,
      text: '${l10n.infinite_canvas_infoSeed} $seed',
    ));
  }
  final width = params?.width;
  final height = params?.height;
  if (width != null && height != null) {
    entries.add((
      icon: Icons.aspect_ratio_rounded,
      text: '${l10n.infinite_canvas_infoSize} $width × $height',
    ));
  }
  final model = params?.model;
  if (model != null && model.isNotEmpty) {
    entries.add((icon: Icons.memory_rounded, text: model));
  }
  final sampler = params?.sampler;
  if (sampler != null && sampler.isNotEmpty) {
    entries.add((
      icon: Icons.tune_rounded,
      text: [
        sampler,
        if (params?.steps != null)
          '${l10n.infinite_canvas_infoSteps} '
              '${params!.steps}',
        if (params?.scale != null) 'CFG ${params!.scale!.toStringAsFixed(1)}',
      ].join(' · '),
    ));
  }
  entries.add((
    icon: Icons.schedule_rounded,
    text: canvasFormatCreatedAt(context, node.createdAt),
  ));
  return entries;
}

/// 节点创建时间；按当前语言的短日期 + 小时分钟展示。
String canvasFormatCreatedAt(BuildContext context, DateTime time) {
  final locale = Localizations.localeOf(context).toString();
  return DateFormat.yMd(locale).add_Hm().format(time.toLocal());
}

/// 完整提示词的只读展示，供悬浮预览与提示词弹窗共用。
class CanvasPromptPreview extends StatelessWidget {
  const CanvasPromptPreview({super.key, required this.prompt});

  final String prompt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.infinite_canvas_infoPrompt,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(prompt, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _MissingImage extends StatelessWidget {
  const _MissingImage({required this.node});

  final CanvasNode node;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.image_not_supported_outlined,
                size: 28,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.infinite_canvas_nodeMissingImage,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                l10n.infinite_canvas_nodeMissingImageHint,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.8,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
