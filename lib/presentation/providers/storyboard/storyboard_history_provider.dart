import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/storyboard/storyboard_document.dart';

/// 撤销/重做的可用性；用作状态是为了让工具条按需启用按钮。
typedef StoryboardHistoryState = ({int undoDepth, int redoDepth});

/// 分镜文档的撤销栈。
///
/// 快照式：在每次手势开始前压入当时整篇文档。分镜文档很轻（只有版面与引用，
/// 不含图片字节），因此整套文档快照比逐字段记录更简单也更不容易出错。
///
/// 上限 [maxDepth] 条；超出后丢弃最旧的一条。分镜是工作台，不是版本管理，
/// 长时间编辑只保留最近若干步即可。
class StoryboardHistoryController extends Notifier<StoryboardHistoryState> {
  static const int maxDepth = 60;

  final List<StoryboardDocument> _undo = <StoryboardDocument>[];
  final List<StoryboardDocument> _redo = <StoryboardDocument>[];

  @override
  StoryboardHistoryState build() => (undoDepth: 0, redoDepth: 0);

  bool get canUndo => _undo.isNotEmpty;

  bool get canRedo => _redo.isNotEmpty;

  /// 记录一次手势前的文档快照。连续调用（例如一个手势内多次）只在第一次生效。
  void push(StoryboardDocument document) {
    _undo.add(document);
    while (_undo.length > maxDepth) {
      _undo.removeAt(0);
    }
    // 新的修改会让原来的重做分支失效。
    _redo.clear();
    _publish();
  }

  /// 回退一步；返回需要恢复的文档，已经在最底部时返回 null。
  StoryboardDocument? undo(StoryboardDocument current) {
    if (_undo.isEmpty) return null;
    final previous = _undo.removeLast();
    _redo.add(current);
    while (_redo.length > maxDepth) {
      _redo.removeAt(0);
    }
    _publish();
    return previous;
  }

  /// 重做一步；没有可重做的内容时返回 null。
  StoryboardDocument? redo(StoryboardDocument current) {
    if (_redo.isEmpty) return null;
    final next = _redo.removeLast();
    _undo.add(current);
    while (_undo.length > maxDepth) {
      _undo.removeAt(0);
    }
    _publish();
    return next;
  }

  void clear() {
    _undo.clear();
    _redo.clear();
    _publish();
  }

  void _publish() {
    state = (undoDepth: _undo.length, redoDepth: _redo.length);
  }
}

final storyboardHistoryProvider =
    NotifierProvider<StoryboardHistoryController, StoryboardHistoryState>(
      StoryboardHistoryController.new,
    );
