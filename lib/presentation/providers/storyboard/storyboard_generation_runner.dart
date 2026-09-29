import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/platform/platform_capabilities.dart';
import '../../../../core/services/anlas_calculator.dart';
import '../../../../core/services/android_media_store_service.dart';
import '../../../../core/services/character_conversion_service.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../../core/utils/character_prompt_block_parser.dart';
import '../../../../core/utils/prompt_edit_document.dart';
import '../../../../core/utils/prompt_preset_resolution.dart';
import '../../../../data/datasources/remote/nai_image_generation_api_service.dart';
import '../../../../data/models/image/image_params.dart';
import '../../../../data/models/storyboard/storyboard_page.dart';
import '../../../../data/models/storyboard/storyboard_panel_status.dart';
import '../../../../data/repositories/gallery_folder_repository.dart';
import '../../../../data/services/alias_resolver_service.dart';
import '../../../../data/services/gallery/gallery_path_utils.dart';
import '../../../../data/services/statistics_cache_service.dart';
import '../../../../data/services/storyboard/storyboard_generation_planner.dart';
import '../../services/generation_history_storage_service.dart';
import '../character_prompt_provider.dart';
import '../fixed_tags_provider.dart';
import '../generation/generation_models.dart';
import '../generation/generation_params_notifier.dart';
import '../generation/generation_result_lifecycle_service.dart';
import '../generation/image_generation_service.dart';
import '../local_gallery_provider.dart';
import '../quality_preset_provider.dart';
import '../uc_preset_provider.dart';
import 'storyboard_document_controller.dart';
import 'storyboard_preview_provider.dart';

/// 分镜批量生成的状态。
class StoryboardGenerationState {
  const StoryboardGenerationState({
    this.isRunning = false,
    this.totalRequests = 0,
    this.completedRequests = 0,
    this.currentPanelOrder,
    this.generatedImages = 0,
    this.failedRequests = 0,
    this.errorCode,
  });

  final bool isRunning;
  final int totalRequests;
  final int completedRequests;

  /// 正在生成的分镜阅读序号，用于界面提示"第几个"。
  final int? currentPanelOrder;

  final int generatedImages;
  final int failedRequests;

  /// 机器可读的失败原因；界面负责本地化。
  final String? errorCode;

  bool get hasWork => totalRequests > 0;

  double get progress =>
      totalRequests == 0 ? 0 : completedRequests / totalRequests;

  StoryboardGenerationState copyWith({
    bool? isRunning,
    int? totalRequests,
    int? completedRequests,
    int? currentPanelOrder,
    bool clearCurrentPanel = false,
    int? generatedImages,
    int? failedRequests,
    String? errorCode,
    bool clearError = false,
  }) {
    return StoryboardGenerationState(
      isRunning: isRunning ?? this.isRunning,
      totalRequests: totalRequests ?? this.totalRequests,
      completedRequests: completedRequests ?? this.completedRequests,
      currentPanelOrder: clearCurrentPanel
          ? null
          : (currentPanelOrder ?? this.currentPanelOrder),
      generatedImages: generatedImages ?? this.generatedImages,
      failedRequests: failedRequests ?? this.failedRequests,
      errorCode: clearError ? null : (errorCode ?? this.errorCode),
    );
  }
}

/// 分镜批量生成的执行器。
///
/// 逐条发送 [StoryboardGenerationPlanner] 规划出的请求：同一个分镜的多张变体
/// 会在请求内部合并成 n_samples，不同分镜之间则严格顺序执行——批量分镜很容易
/// 撞上并发限制，顺序执行换来的是可预期的进度与失败定位。
///
/// 生成走的是生成页同一套 [ImageGenerationService]（含重试、429 退避与取消），
/// 不另写一份请求逻辑；结果与生成页一样经 [GenerationResultLifecycleService]
/// 落盘并进入图库索引。
class StoryboardGenerationRunner extends Notifier<StoryboardGenerationState> {
  ImageGenerationService? _service;
  bool _cancelRequested = false;

  /// 预览帧节流：流式回调可能远高于界面刷新率，按时间窗丢弃多余帧。
  DateTime _lastPreviewAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  StoryboardGenerationState build() => const StoryboardGenerationState();

  bool get isRunning => state.isRunning;

  /// 取消当前批次；当前请求会在网络层被中断，已完成的分镜保留。
  void cancel() {
    _cancelRequested = true;
    _service?.cancel();
  }

  /// 开始批量生成。
  ///
  /// [base] 通常来自生成页当前参数，提供模型、采样器、步数、CFG、角色与参考。
  Future<void> start({
    required StoryboardPage page,
    required ImageParams base,
    Iterable<String>? onlyPanelIds,
    bool selectedImageOnly = false,
    bool background = false,
  }) async {
    if (state.isRunning) return;

    // 与生成页同一套装配：固定词、质量/UC 预设套到每个分镜的最终提示词，
    // 角色快照与 Vibe 编码进入 base。改动这些设置的后果与生成页一致。
    final assembly = _buildPromptAssembly(base);
    final preparedBase = await _prepareBase(base);

    final requests = background
        ? StoryboardGenerationPlanner.planBackground(
            page: page,
            base: preparedBase,
            assembly: assembly,
          )
        : StoryboardGenerationPlanner.planPage(
            page: page,
            base: preparedBase,
            onlyPanelIds: onlyPanelIds,
            selectedImageOnly: selectedImageOnly,
            assembly: assembly,
          );
    if (requests.isEmpty) {
      state = state.copyWith(
        errorCode: background
            ? 'storyboard_generate_background_no_prompt'
            : onlyPanelIds == null
            ? 'storyboard_generate_no_prompt'
            : 'storyboard_generate_nothing_to_do',
      );
      return;
    }

    final document = ref.read(storyboardDocumentControllerProvider.notifier);
    final service = ImageGenerationService(
      apiService: ref.read(naiImageGenerationApiServiceProvider),
      // 分镜批量不做后处理：一次几十张的自动增强会让等待时间与内存都失控。
      // 流式预览保持开启：生成中的分镜格内实时显示当前画面。
      streamPreviewEnabled: true,
    );
    _service = service;
    _cancelRequested = false;
    _lastPreviewAt = DateTime.fromMillisecondsSinceEpoch(0);
    ref.read(storyboardPreviewProvider.notifier).clear();

    state = StoryboardGenerationState(
      isRunning: true,
      totalRequests: requests.length,
    );

    final panelIds = requests
        .map((request) => request.panelId)
        .where((id) => id != StoryboardGenerationPlanner.backgroundRequestId)
        .toSet();
    for (final panelId in panelIds) {
      await document.setPanelStatus(panelId, StoryboardPanelStatus.queued);
    }

    var completed = 0;
    var generated = 0;
    var failed = 0;

    for (final request in requests) {
      if (_cancelRequested) break;
      final isBackground =
          request.panelId == StoryboardGenerationPlanner.backgroundRequestId;
      state = state.copyWith(currentPanelOrder: request.panelOrder);
      if (!isBackground) {
        await document.setPanelStatus(
          request.panelId,
          StoryboardPanelStatus.generating,
        );
      }

      var panelDone = false;
      try {
        final result = await service.generateSingle(
          request.params,
          onProgress: (current, total, progress, {previewImage}) {
            if (previewImage == null || _cancelRequested) return;
            final now = DateTime.now();
            if (now.difference(_lastPreviewAt).inMilliseconds < 120) return;
            _lastPreviewAt = now;
            ref.read(storyboardPreviewProvider.notifier).update(
                  panelId: request.panelId,
                  bytes: previewImage,
                  progress: progress,
                );
          },
        );
        if (!_cancelRequested && result.isSuccess) {
          final saved = await _saveImages(result.images, request.params);
          for (final relativePath in saved) {
            if (isBackground) {
              await document.addBackgroundImage(relativePath);
            } else {
              await document.addGeneratedImage(request.panelId, relativePath);
            }
          }
          generated += saved.length;
          panelDone = saved.isNotEmpty;
          if (!panelDone) failed++;
        } else if (!_cancelRequested) {
          failed++;
        }
      } catch (error, stackTrace) {
        AppLogger.e('分镜生成失败', error, stackTrace, 'StoryboardGeneration');
        failed++;
      }

      if (!panelDone && !_cancelRequested && !isBackground) {
        await document.setPanelFailed(request.panelId);
      }
      // 本条请求的流式预览随完成/失败一并清掉，分镜格回到图库图或占位。
      ref.read(storyboardPreviewProvider.notifier).clear();
      completed++;
      state = state.copyWith(completedRequests: completed);
    }

    _service = null;
    ref.read(storyboardPreviewProvider.notifier).clear();
    state = state.copyWith(
      isRunning: false,
      generatedImages: generated,
      failedRequests: failed,
      clearCurrentPanel: true,
      errorCode: _cancelRequested ? 'cancelled' : null,
      clearError: !_cancelRequested,
    );
  }

  /// 与生成页同一套提示词装配：别名 → 角色块解析 → 固定词 → 质量/UC 预设。
  ///
  /// 装配套在每个分镜最终使用的提示词上（分镜自己的、页面的或生成页的），
  /// 固定词因此对逐格生成同样生效。质量/UC 内容按 base 的模型解析；带模型
  /// 快照覆盖的分镜沿用 base 的预设内容，与预设按页生效的语义一致。
  StoryboardPromptAssembly _buildPromptAssembly(ImageParams base) {
    final aliases = ref
        .read(aliasResolverServiceProvider.notifier)
        .resolveAliases;
    final fixedTags = ref.read(fixedTagsNotifierProvider);
    return StoryboardPromptAssembly(apply: (prompt, negative) {
      final resolvedPositive = CharacterPromptBlockParser.parse(
        PromptEditDocument.effectiveText(aliases(prompt)),
      ).positivePrompt;
      final presets = resolvePromptPresetSettings(
        prompt: fixedTags.applyToPrompt(resolvedPositive),
        negativePrompt: fixedTags.applyToNegativePrompt(aliases(negative)),
        qualityMode: ref.read(qualityPresetNotifierProvider).mode,
        qualityContent: ref
            .read(qualityPresetNotifierProvider.notifier)
            .getEffectiveContent(base.model),
        ucPresetType: ref.read(ucPresetNotifierProvider).presetType,
        ucPresetContent: ref
            .read(ucPresetNotifierProvider.notifier)
            .getEffectiveContent(base.model),
        useCustomUcPreset: ref.read(ucPresetNotifierProvider).isCustom,
      );
      return (presets.prompt, presets.negativePrompt);
    });
  }

  /// base 的角色快照与 Vibe 编码，与生成页的装配保持一致。
  ///
  /// 分镜自带角色时由规划器整体覆盖；没有时回落到编辑器当前角色。
  Future<ImageParams> _prepareBase(ImageParams base) async {
    var effective = base;
    final config = ref.read(characterPromptNotifierProvider);
    final characters = CharacterConversionService(
      aliasResolver: ref
          .read(aliasResolverServiceProvider.notifier)
          .resolveAliases,
    ).convert(config).characters;
    effective = effective.copyWith(
      characters: characters,
      useCoords: characters.isNotEmpty && !config.globalAiChoice,
    );
    if (AnlasCalculator.usesVibeReferences(effective) &&
        effective.capabilities.supportsEncodedVibeTransfer) {
      final encoded = await ref
          .read(generationParamsNotifierProvider.notifier)
          .ensureVibeReferencesEncoded(
            effective.vibeReferencesV4,
            model: effective.model,
            syncCurrentState: true,
          );
      if (!identical(encoded, effective.vibeReferencesV4)) {
        effective = effective.copyWith(vibeReferencesV4: encoded);
      }
    }
    return effective;
  }

  /// 落盘并进入图库索引，返回相对图库根的路径。
  ///
  /// 与生成页共用同一套生命周期服务：元数据嵌入、图库索引与统计口径都一致，
  /// 不会因为换了入口就产生两种"已保存"的含义。
  Future<List<String>> _saveImages(
    List<GeneratedImage> images,
    ImageParams params,
  ) async {
    if (images.isEmpty) return const [];
    final gallery = ref.read(localGalleryNotifierProvider.notifier);
    final statistics = ref.read(statisticsCacheServiceProvider);
    final lifecycle = GenerationResultLifecycleService(
      GenerationResultLifecycleDependencies(
        historyStorage: ref.read(generationHistoryStorageServiceProvider),
        resolveGalleryRootPath: GalleryFolderRepository.instance.getRootPath,
        addGalleryImages: gallery.addNewlySavedImages,
        refreshGallery: gallery.refresh,
        incrementStatistics: statistics.incrementImageCount,
        publishToSystemGallery:
            PlatformCapabilities.operatingSystem.supportsSystemGalleryExport
            ? (sourcePath, fileName) async {
                await AndroidMediaStoreService.saveImageFromPath(
                  sourcePath: sourcePath,
                  fileName: fileName,
                  mimeType: 'image/png',
                );
              }
            : null,
      ),
    );
    final result = await lifecycle.saveImages(
      images,
      params,
      snapshot: const GenerationSaveSnapshot(),
    );
    final rootPath = await GalleryFolderRepository.instance.getRootPath();
    if (rootPath == null || rootPath.isEmpty) return const [];

    final relative = <String>[];
    for (final path in result.savedPaths) {
      final value = toGalleryRelativePath(rootPath, path);
      if (value != null && isValidGalleryRelativePath(value)) {
        relative.add(value);
      }
    }
    return relative;
  }
}

/// 分镜批量生成的执行器实例。
final storyboardGenerationRunnerProvider =
    NotifierProvider<StoryboardGenerationRunner, StoryboardGenerationState>(
      StoryboardGenerationRunner.new,
    );
