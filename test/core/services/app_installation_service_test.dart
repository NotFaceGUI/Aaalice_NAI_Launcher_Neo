import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/services/app_installation_service.dart';

void main() {
  group('AppInstallationService', () {
    test('detects executable inside install directory', () {
      expect(
        AppInstallationService.isExecutableInsideInstallDir(
          executablePath:
              r'C:\Users\alice\AppData\Local\Programs\Aaalice NAI Launcher Neo\nai_launcher.exe',
          installLocation:
              r'C:\Users\alice\AppData\Local\Programs\Aaalice NAI Launcher Neo',
        ),
        isTrue,
      );
    });

    test('does not match similar path prefixes', () {
      expect(
        AppInstallationService.isExecutableInsideInstallDir(
          executablePath:
              r'C:\Users\alice\AppData\Local\Programs\Aaalice NAI Launcher Neo Portable\nai_launcher.exe',
          installLocation:
              r'C:\Users\alice\AppData\Local\Programs\Aaalice NAI Launcher Neo',
        ),
        isFalse,
      );
    });

    test('normalizes slash and trailing separator differences', () {
      expect(
        AppInstallationService.isExecutableInsideInstallDir(
          executablePath:
              'C:/Users/alice/AppData/Local/Programs/Aaalice NAI Launcher Neo/nai_launcher.exe',
          installLocation:
              r'C:\Users\alice\AppData\Local\Programs\Aaalice NAI Launcher Neo\',
        ),
        isTrue,
      );
    });
  });

  group('安装版判定依据', () {
    test('应用目录里有卸载程序就判为安装版（与目录名、注册表无关）', () async {
      final root = await Directory.systemTemp.createTemp('launcher-');
      addTearDown(() => root.delete(recursive: true));
      final installDir = Directory(
        '${root.path}${Platform.pathSeparator}Renamed Launcher',
      );
      await installDir.create(recursive: true);
      final executablePath =
          '${installDir.path}${Platform.pathSeparator}nai_launcher.exe';
      await File(executablePath).writeAsString('stub');
      await File(
        '${installDir.path}${Platform.pathSeparator}'
        '${AppInstallationService.uninstallerFileName}',
      ).writeAsString('stub');

      expect(
        AppInstallationService.isInstalledWindowsApp(
          executablePath: executablePath,
        ),
        isTrue,
      );
    });

    test('没有卸载程序且注册表没有对应登记时判为便携版', () async {
      final root = await Directory.systemTemp.createTemp('portable-');
      addTearDown(() => root.delete(recursive: true));
      final portableDir = Directory(
        '${root.path}${Platform.pathSeparator}Portable',
      );
      await portableDir.create(recursive: true);
      final executablePath =
          '${portableDir.path}${Platform.pathSeparator}nai_launcher.exe';
      await File(executablePath).writeAsString('stub');

      expect(
        AppInstallationService.isInstalledWindowsApp(
          executablePath: executablePath,
        ),
        isFalse,
      );
    });

    test('指向旧目录的登记不算当前安装位置', () {
      // 真实数据：品牌改名后，运行中的 exe 在「NovelAI Launcher Neo」，
      // 而注册表里也可能留着指向旧目录的条目。旧条目若被采信，安装版会被
      // 判成便携版，更新时就会去下载便携包。
      const executablePath = r'E:\Software\NovelAI Launcher Neo\nai_launcher.exe';

      expect(
        AppInstallationService.isExecutableInsideInstallDir(
          executablePath: executablePath,
          installLocation: r'E:\Software\Aaalice NAI Launcher Neo',
        ),
        isFalse,
      );
      expect(
        AppInstallationService.isExecutableInsideInstallDir(
          executablePath: executablePath,
          installLocation: r'E:\Software\NovelAI Launcher Neo',
        ),
        isTrue,
      );
    });

    test('卸载程序是安装版与便携版的可靠分界', () async {
      final installerDir = await Directory.systemTemp.createTemp('installer-');
      final portableDir = await Directory.systemTemp.createTemp('portable-');
      addTearDown(() => installerDir.delete(recursive: true));
      addTearDown(() => portableDir.delete(recursive: true));
      await File(
        '${installerDir.path}${Platform.pathSeparator}'
        '${AppInstallationService.uninstallerFileName}',
      ).writeAsString('stub');

      expect(
        AppInstallationService.hasUninstallerInDirectory(installerDir.path),
        isTrue,
      );
      // 便携包只解压应用文件，不含卸载程序
      expect(
        AppInstallationService.hasUninstallerInDirectory(portableDir.path),
        isFalse,
      );
    });
  });
}
