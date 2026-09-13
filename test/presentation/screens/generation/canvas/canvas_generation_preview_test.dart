import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/data/models/canvas/canvas_document.dart';
import 'package:nai_launcher/data/models/image/image_params.dart';
import 'package:nai_launcher/data/models/image/image_postprocess_phase.dart';
import 'package:nai_launcher/data/services/canvas/canvas_repository.dart';
import 'package:nai_launcher/data/services/canvas/canvas_image_importer.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/providers/canvas/canvas_document_controller.dart';
import 'package:nai_launcher/presentation/providers/canvas/canvas_generation_preview.dart';
import 'package:nai_launcher/presentation/providers/canvas/canvas_repository_provider.dart';
import 'package:nai_launcher/presentation/providers/canvas/canvas_view_controller.dart';
import 'package:nai_launcher/presentation/providers/image_generation_provider.dart';
import 'package:nai_launcher/presentation/screens/generation/canvas/infinite_canvas_view.dart';
import 'package:nai_launcher/presentation/widgets/common/selectable_image_card.dart';

class _Repository extends CanvasRepository {
  final document = CanvasDocument.singleBoard();
  @override
  Future<String?> rootPath() async => null;
  @override
  Future<CanvasDocument?> load() async => document;
  @override
  Future<bool> save(CanvasDocument document) async => true;
}

class _Settings extends LocalStorageService {
  _Settings(this.autoImport);
  final bool autoImport;
  @override
  bool getInfiniteCanvasOpen() => true;
  @override
  bool getInfiniteCanvasAutoImport() => autoImport;
  @override
  ({double offsetX, double offsetY, double scale})?
  getInfiniteCanvasViewport() => null;
  @override
  Future<void> setInfiniteCanvasViewport({
    required double offsetX,
    required double offsetY,
    required double scale,
  }) async {}
}

class _Generation extends ImageGenerationNotifier {
  @override
  ImageGenerationState build() => const ImageGenerationState();
  void emit(ImageGenerationState value) => state = value;
}

class _Params extends GenerationParamsNotifier {
  @override
  ImageParams build() => const ImageParams(width: 512, height: 768);
}

class _Importer extends CanvasImageImporter {
  Completer<CanvasImageImportResult>? pending;
  int calls = 0;
  @override
  Future<CanvasImageImportResult> importImage({
    String? existingFilePath,
    Uint8List? bytes,
  }) async {
    calls++;
    return pending?.future ??
        const CanvasImageImportResult.success('test.png', savedToDisk: false);
  }
}

void main() {
  final bytes = Uint8List.fromList(
    img.encodePng(img.Image(width: 8, height: 8)),
  );
  late ProviderContainer container;
  late _Importer importer;

  Future<void> pump(
    WidgetTester tester, {
    bool autoImport = true,
    double width = 900,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    importer = _Importer();
    container = ProviderContainer(
      overrides: [
        canvasRepositoryProvider.overrideWithValue(_Repository()),
        canvasImageImporterProvider.overrideWithValue(importer),
        localStorageServiceProvider.overrideWithValue(_Settings(autoImport)),
        imageGenerationNotifierProvider.overrideWith(_Generation.new),
        generationParamsNotifierProvider.overrideWith(_Params.new),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 400));
      container.dispose();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: InfiniteCanvasView()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  ImageGenerationState generating({
    List<StreamPreviewSlot> slots = const [],
    List<GeneratedImage> images = const [],
  }) => ImageGenerationState(
    status: GenerationStatus.generating,
    currentImage: 1,
    totalImages: 2,
    batchWidth: 512,
    batchHeight: 768,
    streamPreviewSlots: slots,
    currentImages: images,
  );

  void emit(ImageGenerationState state) =>
      (container.read(imageGenerationNotifierProvider.notifier) as _Generation)
          .emit(state);

  for (final width in [320.0, 600.0, 840.0, 1180.0, 1600.0]) {
    testWidgets(
      'live card at width $width reuses normal preview and keeps its canvas position',
      (tester) async {
        await pump(tester, width: width, autoImport: false);
        emit(generating());
        await tester.pump();
        final previews = container.read(canvasGenerationPreviewProvider);
        final initial = previews.entries.single;
        expect(find.byType(SelectableImageCard), findsOneWidget);
        final firstState = tester.state(find.byType(SelectableImageCard));
        emit(
          generating(
            slots: [
              StreamPreviewSlot(
                imageNumber: 1,
                totalImages: 2,
                progress: 0.6,
                previewBytes: bytes,
                postprocessPhase: ImagePostprocessPhase.enhancing,
              ),
            ],
          ),
        );
        await tester.pump();
        final card = tester.widget<SelectableImageCard>(
          find.byType(SelectableImageCard),
        );
        expect(card.streamPreview, same(bytes));
        expect(card.postprocessPhase, ImagePostprocessPhase.enhancing);
        expect(card.progress, 0.6);
        expect(card.imageWidth, 512);
        expect(card.imageHeight, 768);
        expect(
          tester.state(find.byType(SelectableImageCard)),
          same(firstState),
        );
        expect(previews.entries.single.rect, initial.rect);
        final viewport = container.read(canvasViewControllerProvider);
        viewport.setScale(0.5);
        await tester.pump();
        final rect = tester.getRect(
          find.byKey(ValueKey('canvas-preview-${initial.id}')),
        );
        expect(rect.topLeft, viewport.canvasToScreen(initial.rect.topLeft));
        expect(rect.width, initial.rect.width * 0.5);
        expect(
          container.read(canvasDocumentControllerProvider).value!.nodes,
          isEmpty,
        );
        emit(const ImageGenerationState(status: GenerationStatus.cancelled));
        await tester.pump(const Duration(milliseconds: 400));
        expect(previews.entries, isEmpty);
        expect(importer.calls, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'completed frame stays visible until a non-importing run settles',
    (tester) async {
      await pump(tester, autoImport: false);
      emit(generating());
      await tester.pump();
      final previews = container.read(canvasGenerationPreviewProvider);
      final result = GeneratedImage(
        id: 'result',
        bytes: bytes,
        width: 512,
        height: 768,
      );
      emit(generating(images: [result]));
      await tester.pump();
      expect(previews.entries.single.image, same(result));
      expect(
        tester
            .widget<SelectableImageCard>(find.byType(SelectableImageCard))
            .isGenerating,
        isFalse,
      );
      expect(importer.calls, 0);
      emit(const ImageGenerationState(status: GenerationStatus.completed));
      await tester.pump();
      expect(previews.entries, isEmpty);
    },
  );

  testWidgets(
    'multiple slots avoid overlap and completion keeps original board and position',
    (tester) async {
      await pump(tester);
      emit(
        generating(
          slots: const [
            StreamPreviewSlot(imageNumber: 1, totalImages: 2, progress: 0),
            StreamPreviewSlot(imageNumber: 2, totalImages: 2, progress: 0),
          ],
        ),
      );
      await tester.pump();
      final previews = container.read(canvasGenerationPreviewProvider);
      final entries = previews.entries;
      expect(entries, hasLength(2));
      expect(entries[0].rect.overlaps(entries[1].rect), isFalse);
      final documents = container.read(
        canvasDocumentControllerProvider.notifier,
      );
      final noteId = await documents.addNoteNode();
      final note = documents.document.nodeById(noteId)!;
      expect(
        entries.every(
          (entry) => !entry.rect.overlaps(
            Rect.fromLTWH(note.x, note.y, note.width, note.height),
          ),
        ),
        isTrue,
      );
      importer.pending = Completer<CanvasImageImportResult>();
      final result = GeneratedImage(
        id: 'result',
        bytes: bytes,
        width: 512,
        height: 768,
      );
      emit(generating(images: [result]));
      await tester.pump();
      final other = await documents.createBoard('Other');
      await tester.pump();
      importer.pending!.complete(
        const CanvasImageImportResult.success('test.png', savedToDisk: false),
      );
      await tester.pump();
      final saved = documents.document
          .boardById(entries.first.boardId)!
          .nodeById(entries.first.id)!;
      expect(
        Rect.fromLTWH(saved.x, saved.y, saved.width, saved.height),
        entries.first.rect,
      );
      expect(documents.document.activeBoardId, other);
      expect(documents.document.nodes, isEmpty);
      emit(const ImageGenerationState(status: GenerationStatus.completed));
      await tester.pump(const Duration(milliseconds: 400));
      expect(importer.calls, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
