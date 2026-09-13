import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../widgets/common/generation_parameter_selection.dart';
import '../../../widgets/common/model_family_icon.dart';
import '../../../../data/models/canvas/canvas_node.dart';
import '../../../../data/models/canvas/canvas_node_kind.dart';
import '../../../../data/models/canvas/canvas_node_params.dart';
import '../../../../data/services/canvas/canvas_image_importer.dart';
import '../../../adaptive/adaptive_presenter.dart';
import '../../../adaptive/content_sized_adaptive_form.dart';
import '../../../providers/canvas/canvas_document_controller.dart';
import '../../../providers/canvas/canvas_node_metadata_provider.dart';
import '../../../providers/canvas/canvas_repository_provider.dart';
import '../../../providers/canvas/canvas_visibility_provider.dart';
import '../../../providers/generation/generation_params_notifier.dart';
import '../../../widgets/common/app_toast.dart';

/// 画布节点可以载回生成页的参数项。
enum CanvasParamField {
  prompt,
  negativePrompt,
  seed,
  model,
  sampler,
  steps,
  scale,
  size,
}

/// 把画布节点保存的种子与参数载回生成页。
///
/// 先让用户勾选要替换哪些字段：画布上通常是"拿这张的参数再调一版"，
/// 全量覆盖会连带改掉用户正在调的其它参数。
Future<void> showCanvasLoadParamsDialog({
  required BuildContext context,
  required WidgetRef ref,
  required CanvasNode node,
  String? absolutePath,
}) async {
  final l10n = context.l10n;
  var params = node.params;
  var seed = node.seed;

  // 节点没有快照时按文件解析一次，尽量给出可选项
  if ((params == null || params.isEmpty) &&
      absolutePath != null &&
      absolutePath.isNotEmpty) {
    final metadata = await ref.read(
      canvasNodeMetadataProvider(absolutePath).future,
    );
    if (metadata != null) {
      params = CanvasNodeParams.fromImageMetadata(metadata);
      seed ??= metadata.seed;
    }
  }
  if (!context.mounted) return;

  final available = canvasAvailableParamFields(params: params, seed: seed);
  if (available.isEmpty) {
    AppToast.warning(context, l10n.infinite_canvas_paramsEmpty);
    return;
  }

  final selected = await AdaptivePresenter.showForm<Set<CanvasParamField>>(
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
            l10n.infinite_canvas_todoLoadParams,
            style: Theme.of(panelContext).textTheme.titleLarge,
          ),
        ),
      ],
    ),
    builder: (formContext, scrollController) => _CanvasParamPicker(
      scrollController: scrollController,
      available: available,
      params: params,
      seed: seed,
    ),
  );
  if (!context.mounted || selected == null || selected.isEmpty) return;

  applyCanvasNodeParams(ref: ref, params: params, seed: seed, fields: selected);

  if (!context.mounted) return;
  AppToast.success(context, l10n.infinite_canvas_paramsLoaded);
}

/// 节点快照里实际有值、可以载入的字段。
List<CanvasParamField> canvasAvailableParamFields({
  required CanvasNodeParams? params,
  required int? seed,
}) {
  return [
    if (params != null && params.prompt.isNotEmpty) CanvasParamField.prompt,
    if (params != null && params.negativePrompt.isNotEmpty)
      CanvasParamField.negativePrompt,
    if (seed != null && seed >= 0) CanvasParamField.seed,
    if (params?.model != null) CanvasParamField.model,
    if (params?.sampler != null) CanvasParamField.sampler,
    if (params?.steps != null) CanvasParamField.steps,
    if (params?.scale != null) CanvasParamField.scale,
    if (params?.width != null && params?.height != null) CanvasParamField.size,
  ];
}

/// 按勾选结果把参数写回生成页。
void applyCanvasNodeParams({
  required WidgetRef ref,
  required CanvasNodeParams? params,
  required int? seed,
  required Set<CanvasParamField> fields,
}) {
  final notifier = ref.read(generationParamsNotifierProvider.notifier);

  // 模型先切：followDefaults 会按新模型重置步数与 CFG，
  // 而快照要还原的是当时的实际值，所以随后显式写回。
  if (fields.contains(CanvasParamField.model)) {
    final model = params?.model;
    if (model != null && model.isNotEmpty) {
      notifier.updateModel(model, followDefaults: false);
    }
  }
  if (fields.contains(CanvasParamField.sampler)) {
    final sampler = params?.sampler;
    if (sampler != null && sampler.isNotEmpty) notifier.updateSampler(sampler);
  }
  if (fields.contains(CanvasParamField.steps) && params?.steps != null) {
    notifier.updateSteps(params!.steps!);
  }
  if (fields.contains(CanvasParamField.scale) && params?.scale != null) {
    notifier.updateScale(params!.scale!);
  }
  if (fields.contains(CanvasParamField.size) &&
      params?.width != null &&
      params?.height != null) {
    notifier.updateSize(params!.width!, params.height!);
  }
  if (fields.contains(CanvasParamField.prompt) && params != null) {
    if (params.prompt.isNotEmpty) notifier.updatePrompt(params.prompt);
  }
  if (fields.contains(CanvasParamField.negativePrompt) && params != null) {
    if (params.negativePrompt.isNotEmpty) {
      notifier.updateNegativePrompt(params.negativePrompt);
    }
  }
  if (fields.contains(CanvasParamField.seed) && seed != null && seed >= 0) {
    notifier.updateSeed(seed);
  }
}

/// Canvas and AI TAG share the same field/value selection surface.
class _CanvasParamPicker extends StatelessWidget {
  const _CanvasParamPicker({
    required this.scrollController,
    required this.available,
    required this.params,
    required this.seed,
  });

  final ScrollController scrollController;
  final List<CanvasParamField> available;
  final CanvasNodeParams? params;
  final int? seed;

  @override
  Widget build(BuildContext context) =>
      GenerationParameterSelection<CanvasParamField>(
        key: const ValueKey('canvas-parameter-selection'),
        scrollController: scrollController,
        options: CanvasParamField.values,
        available: available.toSet(),
        initialSelection: available.toSet(),
        allowEmpty: false,
        label: (field) => canvasParamFieldLabel(context, field),
        value: _value,
        optionId: (field) => field.name,
        optionKeyPrefix: 'canvas-parameter-',
        submitKey: const ValueKey('canvas-parameter-submit'),
        heading: context.l10n.onlineGallery_replaceConfig,
        description: context.l10n.onlineGallery_replaceConfigDescription,
        submitLabel: context.l10n.infinite_canvas_todoLoadParams,
        leading: (field, enabled) => field == CanvasParamField.model && enabled
            ? ModelFamilyIcon(modelId: params!.model!, size: 20)
            : Icon(
                switch (field) {
                  CanvasParamField.prompt => Icons.subject,
                  CanvasParamField.negativePrompt => Icons.block,
                  CanvasParamField.seed => Icons.casino_outlined,
                  CanvasParamField.model => Icons.memory_outlined,
                  CanvasParamField.sampler => Icons.timeline_outlined,
                  CanvasParamField.steps => Icons.stairs_outlined,
                  CanvasParamField.scale => Icons.tune_outlined,
                  CanvasParamField.size => Icons.aspect_ratio_outlined,
                },
                size: 20,
                color: enabled
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.3),
              ),
      );

  String _value(CanvasParamField field) => switch (field) {
    CanvasParamField.prompt => params?.prompt ?? '',
    CanvasParamField.negativePrompt => params?.negativePrompt ?? '',
    CanvasParamField.seed => '$seed',
    CanvasParamField.model =>
      ImageModels.modelDisplayNames[params?.model] ?? params?.model ?? '',
    CanvasParamField.sampler =>
      Samplers.samplerDisplayNames[params?.sampler] ?? params?.sampler ?? '',
    CanvasParamField.steps => '${params?.steps}',
    CanvasParamField.scale => '${params?.scale}',
    CanvasParamField.size => '${params?.width} x ${params?.height}',
  };
}

/// 参数项名称，与节点信息浮层共用同一批文案。
String canvasParamFieldLabel(BuildContext context, CanvasParamField field) {
  final l10n = context.l10n;
  return switch (field) {
    CanvasParamField.prompt => l10n.infinite_canvas_infoPrompt,
    CanvasParamField.negativePrompt => l10n.infinite_canvas_infoNegativePrompt,
    CanvasParamField.seed => l10n.infinite_canvas_infoSeed,
    CanvasParamField.model => l10n.infinite_canvas_infoModel,
    CanvasParamField.sampler => l10n.infinite_canvas_infoSampler,
    CanvasParamField.steps => l10n.infinite_canvas_infoSteps,
    CanvasParamField.scale => l10n.infinite_canvas_infoCfg,
    CanvasParamField.size => l10n.infinite_canvas_infoSize,
  };
}

/// 只读展示一个节点的完整提示词（无快照时按文件解析）。
Future<void> showCanvasPromptDialog({
  required BuildContext context,
  required WidgetRef ref,
  required CanvasNode node,
  String? absolutePath,
}) async {
  final l10n = context.l10n;
  var params = node.params;
  if ((params == null || params.prompt.isEmpty) &&
      absolutePath != null &&
      absolutePath.isNotEmpty) {
    final metadata = await ref.read(
      canvasNodeMetadataProvider(absolutePath).future,
    );
    if (metadata != null) params = CanvasNodeParams.fromImageMetadata(metadata);
  }
  final prompt = params?.prompt ?? '';
  if (!context.mounted) return;

  await AdaptivePresenter.showForm<void>(
    context: context,
    title: l10n.infinite_canvas_infoPrompt,
    builder: (formContext, scrollController) => ContentSizedAdaptiveForm(
      scrollController: scrollController,
      content: [
        SelectableText(
          prompt.isEmpty ? l10n.infinite_canvas_paramsEmpty : prompt,
          style: Theme.of(formContext).textTheme.bodyMedium,
        ),
      ],
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: prompt.isEmpty
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: prompt));
                      AppToast.success(formContext, l10n.common_copied);
                    },
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: Text(l10n.common_copy),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => Navigator.of(formContext).pop(),
              child: Text(l10n.common_confirm),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 画布节点宽高比；见 [CanvasNode.resolveAspectRatio]。
double resolveCanvasAspectRatio({int? width, int? height, double? fallback}) =>
    CanvasNode.resolveAspectRatio(
      width: width,
      height: height,
      fallback: fallback,
    );

/// 把当前种子固定成画布上的待办节点。
///
/// 随机种子（-1）没有可固定的值，直接提示而不创建节点。
Future<void> pinCurrentSeedToCanvas({
  required BuildContext context,
  required WidgetRef ref,
}) async {
  final l10n = context.l10n;
  final params = ref.read(generationParamsNotifierProvider);
  if (params.seed < 0) {
    AppToast.warning(context, l10n.infinite_canvas_pinSeedNeedsValue);
    return;
  }

  await ref
      .read(canvasDocumentControllerProvider.notifier)
      .addSeedTodoNode(
        seed: params.seed,
        params: CanvasNodeParams(
          prompt: params.prompt,
          negativePrompt: params.negativePrompt,
          model: params.model,
          sampler: params.sampler,
          steps: params.steps,
          scale: params.scale,
          width: params.width,
          height: params.height,
        ),
      );
  ref.read(infiniteCanvasVisibilityProvider.notifier).open();

  if (!context.mounted) return;
  AppToast.success(context, l10n.infinite_canvas_seedPinned);
}

/// 把一张图片加入画布（图片未落盘时先保存到图库再引用）。
Future<void> addImageToCanvas({
  required BuildContext context,
  required WidgetRef ref,
  required double aspectRatio,
  String? filePath,
  Uint8List? bytes,
  int? seed,
  CanvasNodeParams? params,
}) async {
  final l10n = context.l10n;
  final result = await ref
      .read(canvasImageImporterProvider)
      .importImage(existingFilePath: filePath, bytes: bytes);

  if (!result.isSuccess) {
    if (!context.mounted) return;
    AppToast.error(context, _importFailureMessage(l10n, result.failure));
    return;
  }

  await ref
      .read(canvasDocumentControllerProvider.notifier)
      .addImageNode(
        imageRelativePath: result.relativePath!,
        aspectRatio: aspectRatio,
        seed: seed,
        params: params,
      );

  if (!context.mounted) return;
  AppToast.success(
    context,
    result.savedToDisk
        ? l10n.infinite_canvas_addedAndSaved
        : l10n.infinite_canvas_addedToCanvas,
  );
}

/// 画布节点的默认标题，用于菜单与空状态。
String canvasNodeTitle(BuildContext context, CanvasNodeKind kind) {
  final l10n = context.l10n;
  return switch (kind) {
    CanvasNodeKind.image => l10n.infinite_canvas_nodeImage,
    CanvasNodeKind.seedTodo => l10n.infinite_canvas_nodeSeedTodo,
    CanvasNodeKind.note => l10n.infinite_canvas_nodeNote,
  };
}

String _importFailureMessage(
  AppLocalizations l10n,
  CanvasImageImportFailure? failure,
) {
  return switch (failure) {
    CanvasImageImportFailure.outsideGalleryRoot =>
      l10n.infinite_canvas_addOutsideRoot,
    CanvasImageImportFailure.rootUnavailable ||
    CanvasImageImportFailure.sourceMissing ||
    CanvasImageImportFailure.saveFailed ||
    null => l10n.infinite_canvas_addFailed,
  };
}
