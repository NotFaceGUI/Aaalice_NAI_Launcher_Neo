import 'dart:math' as math;

/// 相机相对主体的方位。
///
/// 左/右是可视化控制里的真实机位差异；Danbooru 没有区分左右机位的标签，
/// 因此两者都落到 `from_side`，见 [CameraAnglePose.azimuthTag]。
enum CameraAzimuth { front, left, right, back }

/// 相机相对主体的俯仰高度。
enum CameraElevation { above, eye, below }

/// 取景距离档位，由近到远。
enum CameraShot { closeUp, portrait, upperBody, cowboyShot, fullBody, wideShot }

/// 视角姿态：相机围绕主体的球面坐标加上画面倾斜。
///
/// 四个分量都归一化到 `-1..1`，与可视化编辑器的手势、滑条一一对应。
/// [copyWith] 和 [fromJson] 会夹取越界值，可视化与分档因此始终有定义；
/// 常量构造只接受已经归一化的字面量，供默认值和档位按钮使用。
/// 姿态本身不携带权重和文案，标签生成只由该值决定，便于单测覆盖。
class CameraAnglePose {
  const CameraAnglePose({
    this.azimuth = 0,
    this.elevation = 0,
    this.distance = 0,
    this.roll = 0,
  });

  /// 与主体正面视图相同的默认姿态：正面平视中景，无倾斜。
  static const CameraAnglePose neutral = CameraAnglePose();

  static const double _min = -1;
  static const double _max = 1;

  /// 水平方位，`0` 为正前方，正值向右环绕（从主体看向相机），`±1` 为后方。
  final double azimuth;

  /// 俯仰，`0` 为平视，正值表示相机高于主体（俯视），负值为仰视。
  final double elevation;

  /// 距离，`-1` 最远（远景），`1` 最近（特写）。
  final double distance;

  /// 画面倾斜，`0` 为水平，非零表示 dutch angle。
  final double roll;

  static double _clampUnit(double value) => value.clamp(_min, _max).toDouble();

  CameraAnglePose copyWith({
    double? azimuth,
    double? elevation,
    double? distance,
    double? roll,
  }) => CameraAnglePose(
    azimuth: _clampUnit(azimuth ?? this.azimuth),
    elevation: _clampUnit(elevation ?? this.elevation),
    distance: _clampUnit(distance ?? this.distance),
    roll: _clampUnit(roll ?? this.roll),
  );

  /// 方位角（弧度），用于投影可视化。
  double get azimuthAngle => azimuth * math.pi;

  /// 俯仰角（弧度），限制在 ±72° 内，避免相机与极点重合时视图退化。
  double get elevationAngle => elevation * (math.pi * 0.4);

  /// 画面倾斜角（弧度）。
  double get rollAngle => roll * (math.pi / 9);

  bool get isNeutral =>
      azimuth == 0 && elevation == 0 && distance == 0 && roll == 0;

  /// 方位分档：正面 / 左侧 / 右侧 / 后方。
  CameraAzimuth get azimuthBucket {
    if (azimuth.abs() <= 0.22) return CameraAzimuth.front;
    if (azimuth.abs() > 0.68) return CameraAzimuth.back;
    return azimuth.isNegative ? CameraAzimuth.left : CameraAzimuth.right;
  }

  /// 俯仰分档：俯视 / 平视 / 仰视。
  CameraElevation get elevationBucket {
    if (elevation >= 0.2) return CameraElevation.above;
    if (elevation <= -0.2) return CameraElevation.below;
    return CameraElevation.eye;
  }

  /// 取景分档，六档与滑条停靠点一一对应。
  CameraShot get shotBucket {
    if (distance <= -0.72) return CameraShot.wideShot;
    if (distance <= -0.4) return CameraShot.fullBody;
    if (distance <= -0.1) return CameraShot.cowboyShot;
    if (distance <= 0.2) return CameraShot.upperBody;
    if (distance <= 0.52) return CameraShot.portrait;
    return CameraShot.closeUp;
  }

  /// 是否构成倾斜构图。
  bool get tilts => roll.abs() > 0.12;

  /// 方位对应的 NAI/Danbooru 标签，正面视图不额外施加机位约束。
  String? get azimuthTag => switch (azimuthBucket) {
    CameraAzimuth.front => null,
    CameraAzimuth.left || CameraAzimuth.right => 'from_side',
    CameraAzimuth.back => 'from_behind',
  };

  /// 俯仰对应的 NAI/Danbooru 标签，平视不需要额外约束。
  String? get elevationTag => switch (elevationBucket) {
    CameraElevation.above => 'from_above',
    CameraElevation.eye => null,
    CameraElevation.below => 'from_below',
  };

  /// 取景对应的 NAI/Danbooru 标签。
  String get shotTag => switch (shotBucket) {
    CameraShot.closeUp => 'close-up',
    CameraShot.portrait => 'portrait',
    CameraShot.upperBody => 'upper_body',
    CameraShot.cowboyShot => 'cowboy_shot',
    CameraShot.fullBody => 'full_body',
    CameraShot.wideShot => 'wide_shot',
  };

  /// 倾斜对应的 NAI/Danbooru 标签。
  String? get rollTag => tilts ? 'dutch_angle' : null;

  /// 按 NAI 提示词习惯排序的机位标签：方位 → 俯仰 → 取景 → 倾斜。
  List<String> get tags {
    final azimuthTag = this.azimuthTag;
    final elevationTag = this.elevationTag;
    final rollTag = this.rollTag;
    return [
      if (azimuthTag != null) azimuthTag,
      if (elevationTag != null) elevationTag,
      shotTag,
      if (rollTag != null) rollTag,
    ];
  }

  Map<String, Object?> toJson() => {
    'azimuth': azimuth,
    'elevation': elevation,
    'distance': distance,
    'roll': roll,
  };

  /// 从存储读取姿态，缺失或非数值字段回落到默认姿态。
  factory CameraAnglePose.fromJson(Map<String, Object?> json) {
    double read(String key) {
      final value = json[key];
      if (value is num) return _clampUnit(value.toDouble());
      return 0;
    }

    return CameraAnglePose(
      azimuth: read('azimuth'),
      elevation: read('elevation'),
      distance: read('distance'),
      roll: read('roll'),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameraAnglePose &&
          other.azimuth == azimuth &&
          other.elevation == elevation &&
          other.distance == distance &&
          other.roll == roll;

  @override
  int get hashCode => Object.hash(azimuth, elevation, distance, roll);

  @override
  String toString() =>
      'CameraAnglePose(azimuth: $azimuth, elevation: $elevation, '
      'distance: $distance, roll: $roll)';
}
