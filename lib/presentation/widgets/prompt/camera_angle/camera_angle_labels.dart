import 'package:flutter/widgets.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/camera_angle/camera_angle_pose.dart';
import '../../../../data/models/camera_angle/camera_angle_preset.dart';

/// 视角控制的本地化标签。
///
/// 控件标签与输出的 Danbooru 标签分开维护：界面显示中文/英文描述，提示词里
/// 始终写入词表标签本身，避免本地化文案被当成提示词内容。

/// 方位分档名称。
String cameraAzimuthLabel(BuildContext context, CameraAzimuth azimuth) =>
    switch (azimuth) {
      CameraAzimuth.front => context.l10n.cameraAngle_azimuthFront,
      CameraAzimuth.left => context.l10n.cameraAngle_azimuthLeft,
      CameraAzimuth.right => context.l10n.cameraAngle_azimuthRight,
      CameraAzimuth.back => context.l10n.cameraAngle_azimuthBack,
    };

/// 俯仰分档名称。
String cameraElevationLabel(BuildContext context, CameraElevation elevation) =>
    switch (elevation) {
      CameraElevation.above => context.l10n.cameraAngle_elevationAbove,
      CameraElevation.eye => context.l10n.cameraAngle_elevationEye,
      CameraElevation.below => context.l10n.cameraAngle_elevationBelow,
    };

/// 取景分档名称。
String cameraShotLabel(BuildContext context, CameraShot shot) =>
    switch (shot) {
      CameraShot.closeUp => context.l10n.cameraAngle_shotCloseUp,
      CameraShot.portrait => context.l10n.cameraAngle_shotPortrait,
      CameraShot.upperBody => context.l10n.cameraAngle_shotUpperBody,
      CameraShot.cowboyShot => context.l10n.cameraAngle_shotCowboyShot,
      CameraShot.fullBody => context.l10n.cameraAngle_shotFullBody,
      CameraShot.wideShot => context.l10n.cameraAngle_shotWideShot,
    };

/// 镜头语言标签名称。
String cameraEffectLabel(BuildContext context, CameraLensEffect effect) =>
    switch (effect) {
      CameraLensEffect.lookingAtViewer =>
        context.l10n.cameraAngle_effectLookingAtViewer,
      CameraLensEffect.depthOfField =>
        context.l10n.cameraAngle_effectDepthOfField,
      CameraLensEffect.blurryBackground =>
        context.l10n.cameraAngle_effectBlurryBackground,
      CameraLensEffect.fisheye => context.l10n.cameraAngle_effectFisheye,
      CameraLensEffect.lensFlare => context.l10n.cameraAngle_effectLensFlare,
      CameraLensEffect.chromaticAberration =>
        context.l10n.cameraAngle_effectChromaticAberration,
      CameraLensEffect.motionBlur => context.l10n.cameraAngle_effectMotionBlur,
      CameraLensEffect.zoomLayer => context.l10n.cameraAngle_effectZoomLayer,
      CameraLensEffect.vanishingPoint =>
        context.l10n.cameraAngle_effectVanishingPoint,
      CameraLensEffect.foreshortening =>
        context.l10n.cameraAngle_effectForeshortening,
    };
