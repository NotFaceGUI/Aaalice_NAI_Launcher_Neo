/// 分镜生成分辨率的来源。
enum StoryboardResolutionMode {
  /// 按分镜在页面上的版面尺寸智能推导，并吸附到 64 网格。
  auto,

  /// 用户显式指定；非法值在请求前吸附到最近的合法分辨率。
  explicit;

  static StoryboardResolutionMode fromStorage(
    Object? value, {
    StoryboardResolutionMode fallback = StoryboardResolutionMode.auto,
  }) {
    if (value is! String) return fallback;
    for (final mode in values) {
      if (mode.name == value) return mode;
    }
    return fallback;
  }
}

/// 单个分镜的生成分辨率设置。
///
/// 这里保存的是"意图"而不是最终请求值：explicit 允许保存非法尺寸（例如
/// 用户从别处粘贴的值），请求前统一由 `StoryboardResolutionResolver` 吸附。
/// 这样做的好处是用户切回自己的输入时不必重新键入。
class StoryboardResolution {
  /// 显式尺寸的取值上限；只用于挡住明显异常的输入，合法性由解析器判定。
  static const int maxExplicitSide = 8192;

  const StoryboardResolution({required this.mode, this.width, this.height});

  const StoryboardResolution.auto()
    : mode = StoryboardResolutionMode.auto,
      width = null,
      height = null;

  const StoryboardResolution.explicit({required int this.width, required int this.height})
    : mode = StoryboardResolutionMode.explicit;

  final StoryboardResolutionMode mode;

  /// 显式宽度；auto 模式为 null。
  final int? width;

  /// 显式高度；auto 模式为 null。
  final int? height;

  bool get isAuto => mode == StoryboardResolutionMode.auto;

  /// 显式模式且两个尺寸都可用。
  bool get hasExplicitSize =>
      !isAuto && (width ?? 0) > 0 && (height ?? 0) > 0;

  StoryboardResolution copyWith({
    StoryboardResolutionMode? mode,
    int? width,
    int? height,
    bool clearSize = false,
  }) {
    final nextMode = mode ?? this.mode;
    if (nextMode == StoryboardResolutionMode.auto) {
      return const StoryboardResolution.auto();
    }
    return StoryboardResolution(
      mode: nextMode,
      width: clearSize ? null : (width ?? this.width),
      height: clearSize ? null : (height ?? this.height),
    );
  }

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    if (!isAuto && width != null) 'width': width,
    if (!isAuto && height != null) 'height': height,
  };

  /// 解析分辨率设置；无法识别时退回 auto，不抛异常。
  static StoryboardResolution fromJson(Object? value) {
    if (value is! Map) return const StoryboardResolution.auto();
    final json = Map<String, dynamic>.from(value);
    final mode = StoryboardResolutionMode.fromStorage(json['mode']);
    if (mode == StoryboardResolutionMode.auto) {
      return const StoryboardResolution.auto();
    }

    final width = _readSide(json['width']);
    final height = _readSide(json['height']);
    return StoryboardResolution(mode: mode, width: width, height: height);
  }

  /// 只接受正整数并在上限内钳制；其余视为未设置。
  static int? _readSide(Object? value) {
    if (value is! num) return null;
    final side = value.toInt();
    if (side <= 0) return null;
    return side > maxExplicitSide ? maxExplicitSide : side;
  }
}
