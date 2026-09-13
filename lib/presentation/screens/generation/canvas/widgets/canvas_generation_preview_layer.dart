import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/localization_extension.dart';
import '../../../../../data/models/image/image_stream_chunk.dart';
import '../../../../providers/canvas/canvas_document_controller.dart';
import '../../../../providers/canvas/canvas_generation_preview.dart';
import '../../../../providers/canvas/canvas_view_controller.dart';
import '../../../../widgets/common/selectable_image_card.dart';

/// Live generation cards occupy canvas coordinates, not a viewport HUD.
class CanvasGenerationPreviewLayer extends ConsumerWidget {
  const CanvasGenerationPreviewLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final previews = ref.watch(canvasGenerationPreviewProvider);
    final viewport = ref.watch(canvasViewControllerProvider);
    final boardId = ref.watch(
      canvasDocumentControllerProvider.select(
        (value) => value.valueOrNull?.activeBoardId,
      ),
    );
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: Listenable.merge([previews, viewport]),
        builder: (context, _) => Stack(
          children: [
            for (final entry in previews.entries)
              if (entry.boardId == boardId)
                Positioned(
                  key: ValueKey('canvas-preview-${entry.id}'),
                  left: viewport.canvasToScreen(entry.rect.topLeft).dx,
                  top: viewport.canvasToScreen(entry.rect.topLeft).dy,
                  width: entry.rect.width * viewport.scale,
                  height: entry.rect.height * viewport.scale,
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: 0,
                    minHeight: 0,
                    maxWidth: double.infinity,
                    maxHeight: double.infinity,
                    child: Transform.scale(
                      scale: viewport.scale,
                      alignment: Alignment.topLeft,
                      child: SizedBox.fromSize(
                        size: entry.rect.size,
                        child: SelectableImageCard(
                          key: ValueKey('canvas-preview-card-${entry.id}'),
                          isGenerating: entry.image == null,
                          imageBytes: entry.image?.bytes,
                          imageIdentity: entry.image?.id,
                          imageWidth: entry.width,
                          imageHeight: entry.height,
                          currentImage: entry.slot.imageNumber,
                          totalImages: entry.slot.totalImages,
                          progress: entry.slot.progress,
                          postprocessPhase: entry.slot.postprocessPhase,
                          streamPreview: entry.slot.previewBytes,
                          focusedPreviewPlacement:
                              entry.slot.focusedPreviewPlacement,
                          completionPreview: entry.slot.previewBytes == null
                              ? null
                              : StreamPreviewFrame(
                                  bytes: entry.slot.previewBytes!,
                                  placement:
                                      entry.slot.focusedPreviewPlacement,
                                ),
                          enableSelection: false,
                          enableContextMenu: false,
                          enableHoverScale: false,
                          hoverEffectsEnabled: false,
                          enableSaveAction: false,
                          enableCopyAction: false,
                          shareWarmupEnabled: false,
                          statusBadgeLabel: entry.importFailed
                              ? context.l10n.infinite_canvas_addFailed
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
