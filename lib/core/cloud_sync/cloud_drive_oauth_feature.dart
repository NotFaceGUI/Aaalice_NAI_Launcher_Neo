import 'package:flutter/foundation.dart';

/// 云盘 OAuth 备份（Google Drive / OneDrive）的编译期开关。
///
/// 本分支默认不提供云盘 OAuth 同步：这两个后端不会出现在可选连接目标中，
/// 应用也不会发起授权请求。WebDAV 与 GitHub 备份不受影响。
///
/// 需要恢复时传入 `--dart-define=ENABLE_CLOUD_DRIVE_OAUTH=true`，并同时配置
/// 各平台的 OAuth 客户端，恢复发布流程中被跳过的授权校验步骤。
abstract final class CloudDriveOAuthFeature {
  static bool _enabled = const bool.fromEnvironment(
    'ENABLE_CLOUD_DRIVE_OAUTH',
  );

  /// 是否允许创建新的云盘 OAuth 连接。
  static bool get enabled => _enabled;

  @visibleForTesting
  static set enabledForTesting(bool value) => _enabled = value;
}
