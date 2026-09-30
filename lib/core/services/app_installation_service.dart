import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:win32_registry/win32_registry.dart';

part 'app_installation_service.g.dart';

enum AppInstallationType {
  windowsInstaller,
  windowsPortable,
  macosPortable,
  androidApk,
  unsupported,
}

/// 判断当前应用是安装版还是便携版。
class AppInstallationService {
  /// 当前卸载项名称。
  ///
  /// 不做旧名兼容：安装目录与卸载项会随品牌一起改名，跨名称查找只会在改名时
  /// 悄悄失配。安装版判定以应用目录里的卸载程序为主，注册表只做补充确认。
  static const String uninstallKeyName = 'NovelAI Launcher Neo';

  static const String uninstallRegistryRoot =
      r'Software\Microsoft\Windows\CurrentVersion\Uninstall';

  /// 安装器安装时放在应用目录里的卸载程序；便携包不含，因此这个判据与安装
  /// 目录名称、注册表键名都无关。
  static const String uninstallerFileName = 'Uninstall.exe';

  AppInstallationType getInstallationType() {
    if (Platform.isWindows) {
      return _isInstalledWindowsApp()
          ? AppInstallationType.windowsInstaller
          : AppInstallationType.windowsPortable;
    }
    if (Platform.isMacOS) {
      return AppInstallationType.macosPortable;
    }
    if (Platform.isAndroid) {
      return AppInstallationType.androidApk;
    }
    return AppInstallationType.unsupported;
  }

  String getReleaseAssetPreference() {
    return switch (getInstallationType()) {
      AppInstallationType.windowsInstaller => 'windows-installer',
      AppInstallationType.windowsPortable => 'windows-portable',
      AppInstallationType.macosPortable => 'macos',
      AppInstallationType.androidApk => 'android-apk',
      AppInstallationType.unsupported => 'unknown',
    };
  }

  /// Windows 由独立更新器替换应用；Android 下载并校验 APK 后交给
  /// 系统安装界面确认。macOS 涉及签名与隔离属性，暂不支持自动替换。
  bool get supportsInAppInstall {
    final type = getInstallationType();
    return type == AppInstallationType.windowsInstaller ||
        type == AppInstallationType.windowsPortable ||
        type == AppInstallationType.androidApk;
  }

  /// 安装版判定：先看应用目录里有没有卸载程序，再退回注册表核对。
  ///
  /// 注册表分支要求登记的安装位置真的包含当前可执行文件，这样品牌改名后
  /// 残留的旧键（指向旧目录）不会再把新目录误判成安装版。
  bool _isInstalledWindowsApp() {
    if (!Platform.isWindows) return false;
    return isInstalledWindowsApp(
      executablePath: Platform.resolvedExecutable,
    );
  }

  /// 与 [Platform.resolvedExecutable] 解耦的判定实现，便于用真实路径校验。
  static bool isInstalledWindowsApp({required String executablePath}) {
    final directory = _parentDirectory(executablePath);
    if (directory != null && hasUninstallerInDirectory(directory)) return true;
    final installLocation = readWindowsInstallLocationFor(executablePath);
    if (installLocation == null || installLocation.isEmpty) return false;
    return isExecutableInsideInstallDir(
      executablePath: executablePath,
      installLocation: installLocation,
    );
  }

  static const String _separator = r'\';

  /// [directory] 里是否存在卸载程序。
  static bool hasUninstallerInDirectory(String directory) {
    final normalized = directory.replaceAll('/', _separator);
    final base = normalized.endsWith(_separator)
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
    return File('$base$_separator$uninstallerFileName').existsSync();
  }

  static String? _parentDirectory(String path) {
    final normalized = path.replaceAll('/', _separator);
    final separator = normalized.lastIndexOf(_separator);
    if (separator <= 0) return null;
    return normalized.substring(0, separator);
  }

  /// 读取当前卸载项登记的安装位置。
  String? readWindowsInstallLocation() => readWindowsInstallLocationFor(
    Platform.resolvedExecutable,
  );

  /// 只有登记的目录确实包含 [executablePath] 时才采信，避免残留键或手工
  /// 搬动目录之后读到过期位置。
  static String? readWindowsInstallLocationFor(String executablePath) {
    if (!Platform.isWindows) return null;
    RegistryKey? key;
    try {
      key = Registry.openPath(
        RegistryHive.currentUser,
        path: '$uninstallRegistryRoot$_separator$uninstallKeyName',
      );
      final location = key.getValueAsString('InstallLocation');
      if (location == null || location.isEmpty) return null;
      return isExecutableInsideInstallDir(
        executablePath: executablePath,
        installLocation: location,
      )
          ? location
          : null;
    } catch (_) {
      return null;
    } finally {
      key?.close();
    }
  }

  static bool isExecutableInsideInstallDir({
    required String executablePath,
    required String installLocation,
  }) {
    final normalizedExe = _normalizePath(executablePath);
    final normalizedInstall = _normalizePath(installLocation);
    return normalizedExe == normalizedInstall ||
        normalizedExe.startsWith('$normalizedInstall\\');
  }

  static String _normalizePath(String value) {
    var normalized = value.replaceAll('/', r'\').trim();
    while (normalized.endsWith(r'\')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized.toLowerCase();
  }
}

@riverpod
AppInstallationService appInstallationService(Ref ref) {
  return AppInstallationService();
}
