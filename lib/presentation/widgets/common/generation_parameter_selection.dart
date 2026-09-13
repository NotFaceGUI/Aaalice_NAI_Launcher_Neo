import 'package:flutter/material.dart';

import '../../../core/utils/localization_extension.dart';
import 'adaptive_dialog_frame.dart';

/// Shared parameter selection surface for gallery and canvas imports.
class GenerationParameterSelection<T> extends StatefulWidget {
  const GenerationParameterSelection({
    super.key,
    required this.scrollController,
    required this.options,
    required this.available,
    required this.label,
    required this.value,
    required this.leading,
    required this.heading,
    required this.description,
    required this.submitLabel,
    required this.optionKeyPrefix,
    required this.optionId,
    this.initialSelection = const {},
    this.submitKey,
    this.allowEmpty = true,
  });

  final ScrollController scrollController;
  final List<T> options;
  final Set<T> available;
  final Set<T> initialSelection;
  final String Function(T) label;
  final String Function(T) value;
  final String Function(T) optionId;
  final Widget Function(T, bool) leading;
  final String heading;
  final String description;
  final String submitLabel;
  final String optionKeyPrefix;
  final Key? submitKey;
  final bool allowEmpty;

  @override
  State<GenerationParameterSelection<T>> createState() =>
      _GenerationParameterSelectionState<T>();
}

class _GenerationParameterSelectionState<T>
    extends State<GenerationParameterSelection<T>> {
  late final Set<T> _selected = Set<T>.from(
    widget.initialSelection.where(widget.available.contains),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AdaptiveDialogFrame(
      maxWidth: 520,
      maxHeight: 640,
      reservedVerticalSpace: 0,
      horizontalMargin: 0,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              controller: widget.scrollController,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              children: [
                Text(
                  widget.heading,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: widget.available.isEmpty
                          ? null
                          : () => setState(() {
                              _selected
                                ..clear()
                                ..addAll(widget.available);
                            }),
                      icon: const Icon(Icons.done_all, size: 18),
                      label: Text(context.l10n.common_selectAll),
                    ),
                    TextButton.icon(
                      onPressed: _selected.isEmpty
                          ? null
                          : () => setState(_selected.clear),
                      icon: const Icon(Icons.clear_all, size: 18),
                      label: Text(context.l10n.common_clear),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Material(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.45,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < widget.options.length; i++) ...[
                        _tile(widget.options[i]),
                        if (i + 1 < widget.options.length)
                          const Divider(height: 1),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(20, 10, 20, 12),
            child: OverflowBar(
              alignment: MainAxisAlignment.end,
              overflowAlignment: OverflowBarAlignment.end,
              spacing: 8,
              overflowSpacing: 8,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.l10n.common_cancel),
                ),
                FilledButton.icon(
                  key: widget.submitKey,
                  onPressed: !widget.allowEmpty && _selected.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(Set<T>.from(_selected)),
                  icon: const Icon(Icons.send, size: 18),
                  label: Text(widget.submitLabel, textAlign: TextAlign.center),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(T option) {
    final theme = Theme.of(context);
    final enabled = widget.available.contains(option);
    return CheckboxListTile(
      key: ValueKey('${widget.optionKeyPrefix}${widget.optionId(option)}'),
      value: enabled && _selected.contains(option),
      onChanged: !enabled
          ? null
          : (checked) => setState(() {
              if (checked ?? false) {
                _selected.add(option);
              } else {
                _selected.remove(option);
              }
            }),
      controlAffinity: ListTileControlAffinity.trailing,
      secondary: widget.leading(option, enabled),
      title: Text(
        widget.label(option),
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        enabled ? widget.value(option) : context.l10n.metadataImport_noData,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
    );
  }
}
