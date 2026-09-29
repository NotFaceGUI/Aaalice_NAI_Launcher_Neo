import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/storyboard/storyboard_page.dart';
import '../../../../data/models/storyboard/storyboard_page_background.dart';
import '../../../adaptive/adaptive_presenter.dart';
import '../../../adaptive/content_sized_adaptive_form.dart';
import '../../../providers/storyboard/storyboard_document_controller.dart';
import '../../../providers/storyboard/storyboard_repository_provider.dart';
import 'storyboard_grid_dialog.dart' show StoryboardDialogActions;

/// 打开页面设置。
///
/// 这里设置的是**整张页面**：输出分辨率、排版间距与背景。分镜自己的属性在
/// 左侧「分镜设置」分组里，两者不混。
///
/// 走项目统一的 [AdaptivePresenter.showForm]，头部、关闭与响应式呈现都由
/// 共用壳层负责。
Future<void> showStoryboardPageSettingsDialog(
  BuildContext context,
  StoryboardPage page,
) {
  return AdaptivePresenter.showForm<void>(
    context: context,
    title: context.l10n.storyboard_pageSettings,
    builder: (formContext, scrollController) => _PageSettingsContent(
      page: page,
      scrollController: scrollController,
    ),
  );
}

class _PageSettingsContent extends ConsumerStatefulWidget {
  const _PageSettingsContent({
    required this.page,
    required this.scrollController,
  });

  final StoryboardPage page;
  final ScrollController? scrollController;

  @override
  ConsumerState<_PageSettingsContent> createState() =>
      _PageSettingsContentState();
}

class _PageSettingsContentState extends ConsumerState<_PageSettingsContent> {
  late final TextEditingController _width;
  late final TextEditingController _height;
  late final TextEditingController _margin;
  late final TextEditingController _gutter;
  late StoryboardPageBackground _background;
  late bool _freeOnly;
  bool _busy = false;

  /// 常用页面底色；自定义取色需要额外的取色器，这里先给出够用的档位。
  static const List<int> _presetColors = [
    0xFFFFFFFF,
    0xFFF5F2EC,
    0xFFE8E4DC,
    0xFF121212,
    0xFF1E1E1E,
    0xFF000000,
  ];

  @override
  void initState() {
    super.initState();
    _width = TextEditingController(text: '${widget.page.width}');
    _height = TextEditingController(text: '${widget.page.height}');
    _margin = TextEditingController(
      text: widget.page.margin.round().toString(),
    );
    _gutter = TextEditingController(
      text: widget.page.gutter.round().toString(),
    );
    _background = widget.page.background;
    _freeOnly = widget.page.freeOnly;
  }

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    _margin.dispose();
    _gutter.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final controller = ref.read(storyboardDocumentControllerProvider.notifier);
    final width = int.tryParse(_width.text);
    final height = int.tryParse(_height.text);
    if (width != null && height != null) {
      await controller.setPageSize(width: width, height: height);
    }
    await controller.setPageSpacing(
      margin: double.tryParse(_margin.text) ?? widget.page.margin,
      gutter: double.tryParse(_gutter.text) ?? widget.page.gutter,
    );
    await controller.setPageFreeOnly(_freeOnly);
    await controller.setBackground(_background);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _pickBackgroundImage() async {
    setState(() => _busy = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'bmp'],
      );
      final path = picked?.files.single.path;
      if (path == null || !mounted) return;
      final relative = await ref
          .read(storyboardImageImporterProvider)
          .importFromPath(path);
      if (!mounted) return;
      if (relative == null) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(context.l10n.common_error)),
        );
        return;
      }
      setState(() {
        _background = _background.copyWith(
          kind: StoryboardBackgroundKind.image,
          imagePath: relative,
        );
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final kind = _background.kind;

    return ContentSizedAdaptiveForm(
      scrollController: widget.scrollController,
      content: [
        Row(
          children: [
            Expanded(
              child: _NumberField(
                controller: _width,
                label: l10n.storyboard_pageWidth,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _NumberField(
                controller: _height,
                label: l10n.storyboard_pageHeight,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          l10n.storyboard_pageSizeHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 18),
        Text(l10n.storyboard_spacing, style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _NumberField(
                controller: _margin,
                label: l10n.storyboard_gridMargin,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _NumberField(
                controller: _gutter,
                label: l10n.storyboard_gridGutter,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          l10n.storyboard_spacingHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 18),
        SwitchListTile(
          value: _freeOnly,
          onChanged: (value) => setState(() => _freeOnly = value),
          title: Text(l10n.storyboard_freeOnly),
          subtitle: Text(
            l10n.storyboard_freeOnlyHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 8),
        Text(l10n.storyboard_background, style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        SegmentedButton<StoryboardBackgroundKind>(
          segments: [
            ButtonSegment(
              value: StoryboardBackgroundKind.none,
              label: Text(l10n.storyboard_backgroundNone),
            ),
            ButtonSegment(
              value: StoryboardBackgroundKind.color,
              label: Text(l10n.storyboard_backgroundColor),
            ),
            ButtonSegment(
              value: StoryboardBackgroundKind.image,
              label: Text(l10n.storyboard_backgroundImage),
            ),
          ],
          selected: {kind},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => setState(
            () => _background = _background.copyWith(kind: selection.first),
          ),
        ),
        if (kind == StoryboardBackgroundKind.color) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final argb in _presetColors)
                _ColorSwatch(
                  color: Color(argb),
                  selected: _background.colorArgb == argb,
                  onTap: () => setState(
                    () => _background = _background.copyWith(colorArgb: argb),
                  ),
                ),
            ],
          ),
        ],
        if (kind == StoryboardBackgroundKind.image) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  _background.imagePath ?? l10n.common_emptyValue,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: _busy ? null : _pickBackgroundImage,
                child: Text(l10n.storyboard_chooseImage),
              ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Text(
          l10n.storyboard_backgroundPromptHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
      footer: StoryboardDialogActions(
        onCancel: () => Navigator.of(context).pop(),
        onConfirm: _busy ? null : _apply,
        confirmLabel: l10n.common_apply,
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label, isDense: true),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 40,
        height: 30,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: selected
            ? Icon(
                Icons.check,
                size: 15,
                color: color.computeLuminance() > 0.5
                    ? Colors.black
                    : Colors.white,
              )
            : null,
      ),
    );
  }
}
