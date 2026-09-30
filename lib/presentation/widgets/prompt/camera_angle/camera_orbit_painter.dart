import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../data/models/camera_angle/camera_angle_pose.dart';

/// 视角控制的可视化场景绘制。
///
/// 场景由一个静止的剪影主体、地面网格和围绕主体移动的机位组成。相机位置由
/// [CameraAnglePose] 的方位/俯仰/距离决定，画面倾斜作为屏幕空间旋转施加，
/// 因此拖动时的视觉反馈与最终插入的提示词标签一一对应。
/// [_painterCamera] 的近平面矩形按 [frameAspect] 绘制成当前生成画幅，
/// 让取景范围和真实出图比例一致。
class CameraOrbitPainter extends CustomPainter {
  const CameraOrbitPainter({
    required this.pose,
    required this.frameAspect,
    required this.subjectOutline,
    required this.gridColor,
    required this.cameraColor,
    required this.detailColor,
  });

  final CameraAnglePose pose;

  /// 当前生成画幅（宽 / 高），用于机位取景框的比例。
  final double frameAspect;


  final Color subjectOutline;
  final Color gridColor;
  final Color cameraColor;
  final Color detailColor;

  /// 俯视/仰视时相机的注视高度，取主体中段。
  static const double _focusHeight = 0.95;

  /// 相机距离范围，从远景到特写。
  static const double _nearDistance = 1.15;
  static const double _farDistance = 5.2;

  /// 头部半径（世界单位），脚底 y=0，面朝 +Z。
  static const double _headRadius = 0.115;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final center = Offset(size.width / 2, size.height * 0.54);
    final focal = size.shortestSide * 1.15;
    final projection = _CameraProjection(
      rawEye: _eyePosition(),
      target: const _Vec3(0, _focusHeight, 0),
      focal: focal,
      center: center,
      worldUp: const _Vec3(0, 1, 0),
      roll: pose.rollAngle,
    );

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    _paintGround(canvas, projection);
    _paintSubject(canvas, projection);
    _paintCamera(canvas, projection);
    canvas.restore();
  }

  _Vec3 _eyePosition() {
    final azimuth = pose.azimuthAngle;
    final elevation = pose.elevationAngle;
    final distance = _distanceForPose(pose.distance);
    final horizontal = distance * math.cos(elevation);
    return _Vec3(
      horizontal * math.sin(azimuth),
      _focusHeight + distance * math.sin(elevation),
      horizontal * math.cos(azimuth),
    );
  }

  static double _distanceForPose(double distance) {
    final normalized = ((distance + 1) / 2).clamp(0.0, 1.0);
    // 近距离段更灵敏：特写与中景之间保留更多可分辨的位移。
    final eased = math.pow(normalized, 1.6).toDouble();
    return _farDistance + (_nearDistance - _farDistance) * eased;
  }

  void _paintGround(Canvas canvas, _CameraProjection projection) {
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = gridColor;

    const ringCount = 3;
    const segments = 48;
    for (var ring = 1; ring <= ringCount; ring++) {
      final radius = ring * 0.85;
      final path = Path();
      var started = false;
      for (var i = 0; i <= segments; i++) {
        final angle = i * 2 * math.pi / segments;
        final point = projection.project(
          _Vec3(radius * math.sin(angle), 0, radius * math.cos(angle)),
        );
        if (point == null) continue;
        if (!started) {
          path.moveTo(point.dx, point.dy);
          started = true;
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(path, grid);
    }

    const spokes = 8;
    final origin = projection.project(const _Vec3(0, 0, 0));
    if (origin != null) {
      for (var i = 0; i < spokes; i++) {
        final angle = i * 2 * math.pi / spokes;
        final end = projection.project(
          _Vec3(
            _farDistance * math.sin(angle),
            0,
            _farDistance * math.cos(angle),
          ),
        );
        if (end != null) canvas.drawLine(origin, end, grid);
      }
    }
  }

  /// 主体：立方体素体人偶（躯干/胯/四肢）加球状头部，保持技术示意图的直观。
  void _paintSubject(Canvas canvas, _CameraProjection projection) {
    final body = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..color = subjectOutline;

    _paintBox(
      canvas,
      projection,
      body,
      center: const _Vec3(0, 1.32, 0),
      half: const _Vec3(0.19, 0.24, 0.12),
    );
    _paintBox(
      canvas,
      projection,
      body,
      center: const _Vec3(0, 0.94, 0),
      half: const _Vec3(0.15, 0.11, 0.11),
    );
    for (final side in const [-1.0, 1.0]) {
      _paintBox(
        canvas,
        projection,
        body,
        center: _Vec3(side * 0.095, 0.42, 0),
        half: const _Vec3(0.065, 0.41, 0.08),
      );
      _paintBox(
        canvas,
        projection,
        body,
        center: _Vec3(side * 0.245, 1.3, 0),
        half: const _Vec3(0.05, 0.24, 0.06),
      );
    }

    final head = _projectCircle(
      projection,
      const _Vec3(0, 1.68, 0),
      _headRadius,
    );
    if (head != null) canvas.drawPath(head, body);

    // 鼻尖短线标出面部朝向，一眼分辨正面与背面。
    final headCenter = projection.project(const _Vec3(0, 1.68, 0));
    const nosePoint = _Vec3(0, 1.68, 0.19);
    final nose = projection.project(nosePoint);
    if (headCenter != null && nose != null) {
      canvas.drawLine(headCenter, nose, body);
      canvas.drawCircle(
        nose,
        math.max(1.6, projection.scaleAt(nosePoint) * 0.022),
        Paint()..color = detailColor,
      );
    }
  }

  /// 画一个立方体线框，8 个顶点按 x/y/z 的位序生成。
  void _paintBox(
    Canvas canvas,
    _CameraProjection projection,
    Paint paint, {
    required _Vec3 center,
    required _Vec3 half,
  }) {
    final corners = <Offset?>[];
    for (var i = 0; i < 8; i++) {
      corners.add(
        projection.project(
          _Vec3(
            center.x + ((i & 1) == 0 ? -half.x : half.x),
            center.y + ((i & 2) == 0 ? -half.y : half.y),
            center.z + ((i & 4) == 0 ? -half.z : half.z),
          ),
        ),
      );
    }
    for (final edge in _boxEdges) {
      final from = corners[edge.$1];
      final to = corners[edge.$2];
      if (from == null || to == null) continue;
      canvas.drawLine(from, to, paint);
    }
  }

  /// 立方体的 12 条棱，索引对应 [_paintBox] 的顶点顺序。
  static const List<(int, int)> _boxEdges = [
    (0, 1),
    (1, 3),
    (3, 2),
    (2, 0),
    (4, 5),
    (5, 7),
    (7, 6),
    (6, 4),
    (0, 4),
    (1, 5),
    (2, 6),
    (3, 7),
  ];

  void _paintCamera(Canvas canvas, _CameraProjection projection) {
    final apex = projection.rawEye;
    final nearCenter = apex + projection.forward * (pose.distance * 0.12 + 0.5);
    // 取景框按真实生成画幅绘制，宽度由高度和画幅推导。
    const halfHeight = 0.105;
    final halfWidth = halfHeight * frameAspect.clamp(0.4, 2.6);
    final corners = [
      nearCenter + projection.right * -halfWidth + projection.up * -halfHeight,
      nearCenter + projection.right * halfWidth + projection.up * -halfHeight,
      nearCenter + projection.right * halfWidth + projection.up * halfHeight,
      nearCenter + projection.right * -halfWidth + projection.up * halfHeight,
    ];

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeJoin = StrokeJoin.round
      ..color = cameraColor;

    final projectedApex = projection.project(apex);
    final projectedCorners = [
      for (final corner in corners) projection.project(corner),
    ];
    if (projectedApex != null) {
      for (final corner in projectedCorners) {
        if (corner != null) canvas.drawLine(projectedApex, corner, paint);
      }
      canvas.drawCircle(
        projectedApex,
        math.max(2.2, projection.scaleAt(apex) * 0.045),
        Paint()..color = cameraColor,
      );
    }
    final frame = Path();
    var started = false;
    for (final corner in [...projectedCorners, projectedCorners.first]) {
      if (corner == null) continue;
      if (!started) {
        frame.moveTo(corner.dx, corner.dy);
        started = true;
      } else {
        frame.lineTo(corner.dx, corner.dy);
      }
    }
    if (started) {
      canvas.drawPath(
        frame,
        Paint()
          ..style = PaintingStyle.fill
          ..color = cameraColor.withValues(alpha: 0.12),
      );
      canvas.drawPath(frame, paint);
    }
  }

  /// 投影一个与视线正对的世界圆，用于头部与朝向标记。
  Path? _projectCircle(
    _CameraProjection projection,
    _Vec3 center,
    double radius,
  ) {
    final screenCenter = projection.project(center);
    if (screenCenter == null) return null;
    final screenRadius = projection.scaleAt(center) * radius;
    if (!screenRadius.isFinite || screenRadius <= 0) return null;
    return Path()..addOval(
      Rect.fromCircle(center: screenCenter, radius: screenRadius),
    );
  }

  @override
  bool shouldRepaint(CameraOrbitPainter oldDelegate) =>
      oldDelegate.pose != pose ||
      oldDelegate.frameAspect != frameAspect ||

      oldDelegate.subjectOutline != subjectOutline ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.cameraColor != cameraColor ||
      oldDelegate.detailColor != detailColor;
}

/// 世界坐标到画布坐标的透视投影。
class _CameraProjection {
  _CameraProjection({
    required this.rawEye,
    required _Vec3 target,
    required this.focal,
    required this.center,
    required _Vec3 worldUp,
    required double roll,
  }) : _forward = (target - rawEye).normalized() {
    var right = worldUp.cross(_forward);
    if (right.length < 1e-6) {
      right = const _Vec3(1, 0, 0);
    }
    _right = right.normalized();
    _up = _forward.cross(_right).normalized();
    _rollCos = math.cos(roll);
    _rollSin = math.sin(roll);
  }

  final _Vec3 rawEye;
  final double focal;
  final Offset center;
  final _Vec3 _forward;
  late final _Vec3 _right;
  late final _Vec3 _up;
  late final double _rollCos;
  late final double _rollSin;

  /// 相机朝向，供视锥绘制使用。
  _Vec3 get forward => _forward;

  /// 相机的屏幕右方向。
  _Vec3 get right => _right;

  /// 相机的屏幕上方方向。
  _Vec3 get up => _up;

  /// 投影一点；位于相机后方或过近时返回 null。
  Offset? project(_Vec3 point) {
    final relative = point - rawEye;
    final depth = relative.dot(_forward);
    if (depth < 0.05) return null;
    final scale = focal / depth;
    return _applyRoll(
      Offset(
        center.dx + relative.dot(_right) * scale,
        center.dy - relative.dot(_up) * scale,
      ),
    );
  }

  /// 该点处一个世界单位对应的屏幕长度。
  double scaleAt(_Vec3 point) {
    final depth = (point - rawEye).dot(_forward);
    return focal / math.max(depth, 0.05);
  }

  Offset _applyRoll(Offset point) {
    final dx = point.dx - center.dx;
    final dy = point.dy - center.dy;
    return Offset(
      center.dx + dx * _rollCos - dy * _rollSin,
      center.dy + dx * _rollSin + dy * _rollCos,
    );
  }
}

class _Vec3 {
  const _Vec3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  _Vec3 operator +(_Vec3 other) => _Vec3(x + other.x, y + other.y, z + other.z);
  _Vec3 operator -(_Vec3 other) => _Vec3(x - other.x, y - other.y, z - other.z);
  _Vec3 operator *(double k) => _Vec3(x * k, y * k, z * k);

  double dot(_Vec3 other) => x * other.x + y * other.y + z * other.z;

  _Vec3 cross(_Vec3 other) => _Vec3(
    y * other.z - z * other.y,
    z * other.x - x * other.z,
    x * other.y - y * other.x,
  );

  double get length => math.sqrt(x * x + y * y + z * z);

  _Vec3 normalized() {
    final magnitude = length;
    if (magnitude < 1e-9) return const _Vec3(0, 0, 0);
    return _Vec3(x / magnitude, y / magnitude, z / magnitude);
  }
}
