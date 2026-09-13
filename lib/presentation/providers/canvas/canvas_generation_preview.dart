import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/canvas/canvas_board.dart';
import '../../../data/models/canvas/canvas_node.dart';
import '../../../data/models/canvas/canvas_node_kind.dart';
import '../generation/generation_models.dart';

final canvasGenerationPreviewProvider = Provider<CanvasGenerationPreview>((
  ref,
) {
  final preview = CanvasGenerationPreview();
  ref.onDispose(preview.dispose);
  return preview;
});

class CanvasGenerationPreviewEntry {
  const CanvasGenerationPreviewEntry({
    required this.id,
    required this.boardId,
    required this.rect,
    required this.width,
    required this.height,
    required this.slot,
    this.image,
    this.importFailed = false,
  });

  final String id;
  final String boardId;
  final Rect rect;
  final int width;
  final int height;
  final StreamPreviewSlot slot;
  final GeneratedImage? image;
  final bool importFailed;

  CanvasGenerationPreviewEntry copyWith({
    StreamPreviewSlot? slot,
    GeneratedImage? image,
    bool? importFailed,
  }) => CanvasGenerationPreviewEntry(
    id: id,
    boardId: boardId,
    rect: rect,
    width: width,
    height: height,
    slot: slot ?? this.slot,
    image: image ?? this.image,
    importFailed: importFailed ?? this.importFailed,
  );

  CanvasNode get placeholder => CanvasNode(
    id: id,
    kind: CanvasNodeKind.image,
    x: rect.left,
    y: rect.top,
    width: rect.width,
    height: rect.height,
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );
}

/// Runtime-only frames and reserved positions; never serialized or synced.
class CanvasGenerationPreview extends ChangeNotifier {
  final Map<String, CanvasGenerationPreviewEntry> _entries = {};
  bool _disposed = false;

  List<CanvasGenerationPreviewEntry> get entries =>
      List.unmodifiable(_entries.values);
  CanvasGenerationPreviewEntry? entry(String id) => _entries[id];

  CanvasGenerationPreviewEntry reserve({
    required String id,
    required CanvasBoard board,
    required Offset center,
    required int width,
    required int height,
    required StreamPreviewSlot slot,
  }) {
    final existing = _entries[id];
    if (existing != null) return existing;
    const nodeWidth = CanvasNode.defaultImageWidth;
    final nodeHeight = (nodeWidth * height / width)
        .clamp(CanvasNode.minNodeHeight, CanvasNode.maxNodeHeight)
        .toDouble();
    final occupied = board.copyWith(
      nodes: [
        ...board.nodes,
        for (final item in _entries.values)
          if (item.boardId == board.id) item.placeholder,
      ],
    );
    final position = occupied.findFreePosition(
      width: nodeWidth,
      height: nodeHeight,
      nearX: center.dx - nodeWidth / 2,
      nearY: center.dy - nodeHeight / 2,
    );
    final entry = CanvasGenerationPreviewEntry(
      id: id,
      boardId: board.id,
      rect: Rect.fromLTWH(position.x, position.y, nodeWidth, nodeHeight),
      width: width,
      height: height,
      slot: slot,
    );
    put(entry);
    return entry;
  }

  void put(CanvasGenerationPreviewEntry entry) {
    if (_disposed) return;
    _entries[entry.id] = entry;
    notifyListeners();
  }

  void remove(String id) {
    if (_disposed || _entries.remove(id) == null) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _entries.clear();
    super.dispose();
  }
}
