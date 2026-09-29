import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/storyboard/storyboard_panel.dart';

/// 分镜编辑器当前的指针工具。
enum StoryboardTool {
  /// 选择、移动与缩放分镜。
  select,

  /// 在空白处拉框新建分镜。
  drawRect,

  /// 编辑选中分镜的多边形顶点。
  polygon;

  static StoryboardTool fromStorage(
    Object? value, {
    StoryboardTool fallback = StoryboardTool.select,
  }) {
    if (value is! String) return fallback;
    for (final tool in values) {
      if (tool.name == value) return tool;
    }
    return fallback;
  }
}

/// 分镜编辑器的选中与工具状态。
///
/// 选中对象有三种：某个分镜、页面背景、或者什么都不选。左侧提示词编辑器与
/// 右侧属性栏都跟着这里的选中对象切换。
class StoryboardInteractionState {
  const StoryboardInteractionState({
    this.selectedPanelId,
    this.backgroundSelected = false,
    this.tool = StoryboardTool.select,
    this.polygonEditing = false,
    this.gestureActive = false,
    this.placingFillLargest = false,
    this.previewMode = false,
  });

  final String? selectedPanelId;

  /// 页面背景是否被选中；与 [selectedPanelId] 互斥。
  final bool backgroundSelected;

  final StoryboardTool tool;

  /// 是否处于多边形顶点编辑：选中面板的顶点与边可以拖动、增删。
  final bool polygonEditing;

  /// 是否正在拖动/缩放分镜。
  ///
  /// 拖动期间不做参数快照切换：那次切换会连写多次文档，每次提交都整树重建，
  /// 整段拖动都在重建；而且写回分辨率还可能改掉正在拖的分镜尺寸。
  final bool gestureActive;

  /// 「填充最大空白」的放置模式：鼠标移入画布实时预览，点击落位。
  final bool placingFillLargest;

  /// 导出观感预览：画布只显示背景与分镜成图，不显示序号、描边与手柄。
  final bool previewMode;

  bool get hasSelection => selectedPanelId != null || backgroundSelected;

  bool isSelected(String panelId) => selectedPanelId == panelId;

  /// 只用于改工具与顶点编辑态；选中对象的变化由 [StoryboardInteractionController]
  /// 的具名方法直接构造，避免出现"面板与背景同时被选中"这种非法组合。
  StoryboardInteractionState copyWith({
    StoryboardTool? tool,
    bool? polygonEditing,
    bool? gestureActive,
    bool? placingFillLargest,
    bool? previewMode,
  }) {
    return StoryboardInteractionState(
      selectedPanelId: selectedPanelId,
      backgroundSelected: backgroundSelected,
      tool: tool ?? this.tool,
      polygonEditing: polygonEditing ?? this.polygonEditing,
      gestureActive: gestureActive ?? this.gestureActive,
      placingFillLargest: placingFillLargest ?? this.placingFillLargest,
      previewMode: previewMode ?? this.previewMode,
    );
  }
}

/// 选中与工具是纯会话状态；分镜文档本身由文档 controller 持有。
class StoryboardInteractionController
    extends Notifier<StoryboardInteractionState> {
  @override
  StoryboardInteractionState build() => const StoryboardInteractionState();

  String? get selectedPanelId => state.selectedPanelId;

  /// 选中一个分镜；传 null 等同于 [selectBackground]。
  void select(String? panelId) {
    if (panelId == null) {
      selectBackground();
      return;
    }
    if (state.selectedPanelId == panelId && !state.backgroundSelected) return;
    state = StoryboardInteractionState(
      selectedPanelId: panelId,
      tool: state.tool,
    );
  }

  /// 选中页面背景。
  void selectBackground() {
    if (state.backgroundSelected) return;
    state = StoryboardInteractionState(
      backgroundSelected: true,
      tool: state.tool,
    );
  }

  void setTool(StoryboardTool tool) {
    if (state.tool == tool &&
        !state.polygonEditing &&
        !state.previewMode) {
      return;
    }
    // 切换工具即退出预览：预览是纯查看态，不能带着编辑意图。
    state = state.copyWith(
      tool: tool,
      polygonEditing: false,
      previewMode: false,
    );
  }

  /// 进入/退出导出观感预览；进入时同时退出顶点编辑。
  void setPreviewMode(bool enabled) {
    if (state.previewMode == enabled) return;
    state = state.copyWith(
      previewMode: enabled,
      polygonEditing: enabled ? false : null,
    );
  }

  /// 标记拖动/缩放开始与结束。
  void setGestureActive(bool active) {
    if (state.gestureActive == active) return;
    state = state.copyWith(gestureActive: active);
  }

  /// 进入/退出「填充最大空白」的放置模式。
  void setPlacingFillLargest(bool placing) {
    if (state.placingFillLargest == placing) return;
    state = state.copyWith(placingFillLargest: placing);
  }

  void setPolygonEditing(bool editing) {
    if (state.polygonEditing == editing) return;
    state = state.copyWith(polygonEditing: editing);
  }

  void clear() => state = const StoryboardInteractionState();
}

/// 选中与工具状态。
///
/// 非 autoDispose：关掉分镜再回来时保留上次选中的面板。
final storyboardInteractionProvider =
    NotifierProvider<StoryboardInteractionController, StoryboardInteractionState>(
      StoryboardInteractionController.new,
    );

/// 分镜画布的指针认领表。
///
/// 与无限画布分开持有实例：两者可能同时挂着子树（只是其中一个不可见），
/// 共用一张表会让不可见的一侧误判指针归属。
final storyboardPointerRegistryProvider = Provider<StoryboardPointerRegistry>(
  (ref) => StoryboardPointerRegistry(),
);

/// 记录哪些指针已被分镜面板或工具条认领。
class StoryboardPointerRegistry {
  final Set<int> _ownedPointers = <int>{};

  void claim(int pointer) => _ownedPointers.add(pointer);

  void release(int pointer) => _ownedPointers.remove(pointer);

  bool isOwned(int pointer) => _ownedPointers.contains(pointer);

  void clear() => _ownedPointers.clear();
}

/// 当前选中的分镜；没有选中或该分镜已被删除时返回 null。
StoryboardPanel? selectedPanelOf(
  StoryboardInteractionState interaction,
  Iterable<StoryboardPanel> panels,
) {
  final id = interaction.selectedPanelId;
  if (id == null) return null;
  for (final panel in panels) {
    if (panel.id == id) return panel;
  }
  return null;
}
