import 'dart:async';
import 'dart:ui';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/utils/app_logger.dart';
import '../../../data/models/canvas/canvas_node_params.dart';
import '../generation/generated_image_metadata_provider.dart';
import '../image_generation_provider.dart';
import 'canvas_document_controller.dart';
import 'canvas_generation_preview.dart';
import 'canvas_repository_provider.dart';
import 'canvas_view_controller.dart';
import 'canvas_visibility_provider.dart';

part 'canvas_generation_bridge.g.dart';

/// Reserves live preview positions, then replaces them with saved image nodes.
@Riverpod(keepAlive: true)
class CanvasGenerationBridge extends _$CanvasGenerationBridge {
  final Set<String> _knownImageIds = {};
  final Map<int, String> _slots = {};
  late CanvasGenerationPreview _previews;
  late ImageGenerationState _latest;
  bool _ready = false;
  bool _disposed = false;
  bool _generating = false;
  String? _boardId;

  @override
  void build() {
    _previews = ref.read(canvasGenerationPreviewProvider);
    _latest = ref.read(imageGenerationNotifierProvider);
    _knownImageIds.addAll(_latest.currentImages.map((image) => image.id));
    ref.onDispose(() => _disposed = true);
    ref.listen(imageGenerationNotifierProvider, (_, next) {
      _latest = next;
      if (_ready) _sync(next);
    });
    ref.listen(infiniteCanvasVisibilityProvider, (_, visible) {
      if (_ready && visible) _sync(_latest);
    });
    ref.listen(canvasDocumentControllerProvider, (_, value) {
      final document = value.valueOrNull;
      if (document == null) return;
      for (final entry in _previews.entries) {
        if (document.boardById(entry.boardId) == null) {
          _previews.remove(entry.id);
        }
      }
    });
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await ref.read(canvasDocumentControllerProvider.future);
    if (_disposed) return;
    _ready = true;
    _sync(_latest);
  }

  void _sync(ImageGenerationState state) {
    if (_disposed) return;
    final documents = ref.read(canvasDocumentControllerProvider.notifier);
    final visible = ref.read(infiniteCanvasVisibilityProvider);
    if (state.isGenerating && !_generating) {
      for (final entry in _previews.entries) {
        if (entry.importFailed) _previews.remove(entry.id);
      }
      _slots.clear();
      _boardId = visible ? documents.document.activeBoardId : null;
    }
    _generating = state.isGenerating;
    if (_generating && visible) _boardId ??= documents.document.activeBoardId;

    final board = documents.document.boardById(_boardId ?? '');
    final fallback = ref.read(generationParamsNotifierProvider);
    final width = state.batchWidth ?? fallback.width;
    final height = state.batchHeight ?? fallback.height;
    if (state.isGenerating && visible && board != null) {
      final inserted = <Rect>[];
      final slots = state.streamPreviewSlots.isNotEmpty
          ? state.streamPreviewSlots
          : [
              StreamPreviewSlot(
                imageNumber: state.currentImage > 0 ? state.currentImage : 1,
                totalImages: state.totalImages,
                progress: state.progress,
                previewBytes: state.streamPreview,
                focusedPreviewPlacement: state.focusedPreviewPlacement,
              ),
            ];
      for (final slot in slots) {
        if (slot.imageNumber <= state.currentImages.length) continue;
        final id = _slots.putIfAbsent(
          slot.imageNumber,
          () => const Uuid().v4(),
        );
        final isNew = _previews.entry(id) == null;
        final entry = _previews.reserve(
          id: id,
          board: board,
          center: ref.read(canvasViewControllerProvider).viewportCenterInCanvas,
          width: width,
          height: height,
          slot: slot,
        );
        _previews.put(entry.copyWith(slot: slot));
        if (isNew) inserted.add(entry.rect);
      }
      final viewport = ref.read(canvasViewControllerProvider);
      if (inserted.isNotEmpty &&
          documents.document.activeBoardId == board.id &&
          !viewport.viewportSize.isEmpty &&
          inserted.any(
            (rect) =>
                !viewport.visibleCanvasRect.contains(rect.topLeft) ||
                !viewport.visibleCanvasRect.contains(rect.bottomRight),
          )) {
        viewport.fitToContent(inserted, animate: false);
      }
    }

    final autoImport = visible && ref.read(canvasAutoImportProvider);
    for (final (index, image) in state.currentImages.indexed) {
      if (!_knownImageIds.add(image.id)) continue;
      final id = _slots[index + 1];
      var entry = id == null ? null : _previews.entry(id);
      if (image.isFailedStreamSnapshot) {
        if (entry != null) _previews.remove(entry.id);
        continue;
      }
      if (!autoImport) {
        if (entry != null) _previews.put(entry.copyWith(image: image));
        continue;
      }
      final targetBoard = entry == null
          ? (board ?? documents.activeBoard)
          : documents.document.boardById(entry.boardId);
      if (targetBoard == null) continue;
      entry ??= _previews.reserve(
        id: const Uuid().v4(),
        board: targetBoard,
        center: ref.read(canvasViewControllerProvider).viewportCenterInCanvas,
        width: image.width,
        height: image.height,
        slot: StreamPreviewSlot(
          imageNumber: index + 1,
          totalImages: state.totalImages,
          progress: 1,
        ),
      );
      final completed = entry.copyWith(image: image);
      _previews.put(completed);
      unawaited(_importImage(completed));
    }
    if (!state.isGenerating) {
      for (final id in _slots.values) {
        final entry = _previews.entry(id);
        if (entry != null && (entry.image == null || !autoImport)) {
          _previews.remove(id);
        }
      }
    }
  }

  Future<void> _importImage(CanvasGenerationPreviewEntry entry) async {
    final image = entry.image!;
    final importer = ref.read(canvasImageImporterProvider);
    final documents = ref.read(canvasDocumentControllerProvider.notifier);
    try {
      final metadata = await ref.read(
        generatedImageMetadataProvider(image).future,
      );
      if (_disposed || documents.document.boardById(entry.boardId) == null) {
        _previews.remove(entry.id);
        return;
      }
      final result = await importer.importImage(
        existingFilePath: image.filePath,
        bytes: image.bytes,
      );
      if (_disposed) return;
      if (!result.isSuccess) {
        _previews.put(entry.copyWith(importFailed: true));
        return;
      }
      final added = await documents.addGeneratedImageNode(
        boardId: entry.boardId,
        id: entry.id,
        rect: entry.rect,
        imageRelativePath: result.relativePath!,
        seed: metadata?.seed,
        params: metadata == null
            ? null
            : CanvasNodeParams.fromImageMetadata(metadata),
      );
      // Keep the last frame until the file-backed node has painted its first frame.
      if (!added) _previews.remove(entry.id);
    } catch (error, stackTrace) {
      AppLogger.e('生成结果加入画布失败', error, stackTrace, 'CanvasBridge');
      if (!_disposed) _previews.put(entry.copyWith(importFailed: true));
    }
  }
}
