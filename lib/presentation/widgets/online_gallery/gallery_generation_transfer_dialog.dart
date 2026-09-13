import 'package:flutter/material.dart';
import '../common/model_family_icon.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/utils/localization_extension.dart';
import '../../adaptive/adaptive_presenter.dart';
import '../../services/generation_prompt_transfer_service.dart';
import '../common/generation_parameter_selection.dart';

/// Lets users choose which recognized NovelAI settings accompany a prompt
/// sent from AI TAG to the native text-to-image form.
class GalleryGenerationTransferDialog extends StatefulWidget {
  const GalleryGenerationTransferDialog._({
    required this.configuration,
    required this.scrollController,
  });

  final GenerationTransferConfiguration? configuration;
  final ScrollController scrollController;

  static Future<Set<GenerationTransferSetting>?> show(
    BuildContext context, {
    required GenerationTransferConfiguration? configuration,
  }) => AdaptivePresenter.showForm<Set<GenerationTransferSetting>>(
    context: context,
    dialogWidth: 520,
    maxCenteredHeight: 720,
    titleBuilder: (panelContext) => Row(
      children: [
        Icon(
          Icons.send_outlined,
          size: 22,
          color: Theme.of(panelContext).colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            panelContext.l10n.onlineGallery_sendToTextToImage,
            style: Theme.of(panelContext).textTheme.titleLarge,
          ),
        ),
      ],
    ),
    builder: (_, scrollController) => GalleryGenerationTransferDialog._(
      configuration: configuration,
      scrollController: scrollController,
    ),
  );

  @override
  State<GalleryGenerationTransferDialog> createState() =>
      _GalleryGenerationTransferDialogState();
}

class _GalleryGenerationTransferDialogState
    extends State<GalleryGenerationTransferDialog> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GenerationParameterSelection<GenerationTransferSetting>(
      key: const ValueKey('gallery-generation-transfer-dialog'),
      scrollController: widget.scrollController,
      options: GenerationTransferSetting.values,
      available: widget.configuration?.availableSettings ?? const {},
      label: _label,
      value: _value,
      optionId: (setting) => setting.name,
      optionKeyPrefix: 'gallery-generation-setting-',
      submitKey: const ValueKey('gallery-generation-transfer-submit'),
      heading: context.l10n.onlineGallery_replaceConfig,
      description: widget.configuration == null
          ? context.l10n.onlineGallery_replaceConfigNaiOnly
          : context.l10n.onlineGallery_replaceConfigDescription,
      submitLabel: context.l10n.onlineGallery_sendToTextToImage,
      leading: (setting, enabled) =>
          setting == GenerationTransferSetting.model && enabled
          ? ModelFamilyIcon(modelId: widget.configuration!.model!, size: 20)
          : Icon(
              _icon(setting),
              size: 20,
              color: enabled
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
    );
  }

  String _label(GenerationTransferSetting setting) => switch (setting) {
    GenerationTransferSetting.model => context.l10n.generation_model,
    GenerationTransferSetting.size => context.l10n.generation_imageSize,
    GenerationTransferSetting.sampler => context.l10n.generation_sampler,
    GenerationTransferSetting.seed => context.l10n.generation_seed,
    GenerationTransferSetting.steps => context.l10n.queue_steps,
    GenerationTransferSetting.scale => context.l10n.queue_cfg,
    GenerationTransferSetting.cfgRescale => _labelBeforeColon(
      context.l10n.generation_cfgRescale(''),
    ),
    GenerationTransferSetting.noiseSchedule =>
      context.l10n.generation_noiseSchedule,
    GenerationTransferSetting.smea => context.l10n.generation_smea,
    GenerationTransferSetting.smeaDyn => context.l10n.generation_smeaDyn,
  };

  String _value(GenerationTransferSetting setting) {
    final configuration = widget.configuration!;
    return switch (setting) {
      GenerationTransferSetting.model =>
        ImageModels.modelDisplayNames[configuration.model] ??
            configuration.model!,
      GenerationTransferSetting.size =>
        '${configuration.width} x ${configuration.height}',
      GenerationTransferSetting.sampler =>
        Samplers.samplerDisplayNames[configuration.sampler] ??
            configuration.sampler!,
      GenerationTransferSetting.seed => '${configuration.seed}',
      GenerationTransferSetting.steps => '${configuration.steps}',
      GenerationTransferSetting.scale => _formatNumber(configuration.scale!),
      GenerationTransferSetting.cfgRescale => _formatNumber(
        configuration.cfgRescale!,
      ),
      GenerationTransferSetting.noiseSchedule =>
        NoiseSchedules.displayNames[configuration.noiseSchedule] ??
            configuration.noiseSchedule!,
      GenerationTransferSetting.smea =>
        configuration.smea!
            ? context.l10n.common_enabled
            : context.l10n.common_disabled,
      GenerationTransferSetting.smeaDyn =>
        configuration.smeaDyn!
            ? context.l10n.common_enabled
            : context.l10n.common_disabled,
    };
  }

  IconData _icon(GenerationTransferSetting setting) => switch (setting) {
    GenerationTransferSetting.model => Icons.memory_outlined,
    GenerationTransferSetting.size => Icons.aspect_ratio_outlined,
    GenerationTransferSetting.sampler => Icons.timeline_outlined,
    GenerationTransferSetting.seed => Icons.casino_outlined,
    GenerationTransferSetting.steps => Icons.stairs_outlined,
    GenerationTransferSetting.scale => Icons.tune_outlined,
    GenerationTransferSetting.cfgRescale => Icons.balance_outlined,
    GenerationTransferSetting.noiseSchedule => Icons.multiline_chart_outlined,
    GenerationTransferSetting.smea => Icons.hd_outlined,
    GenerationTransferSetting.smeaDyn => Icons.auto_fix_high_outlined,
  };

  String _formatNumber(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');

  String _labelBeforeColon(String value) =>
      value.replaceFirst(RegExp(r'[:：]\s*$'), '').trim();
}
