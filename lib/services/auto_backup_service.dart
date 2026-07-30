import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../state/app_controller.dart';
import 'settings_service.dart';

/// 每日自动备份服务。
///
/// 行为：
/// - 默认开启；每天「首次进入应用」时生成一次全量备份（角色 / 世界 / 对话，不含设置）。
/// - 备份写入软件外部目录（优先公共下载目录，卸载不丢失），保留最近 5 天。
/// - 全程静默，无任何提示；任何失败都被吞掉，不影响正常使用。
/// - 设置中可关闭，关闭后不再自动备份。
class AutoBackupService {
  static const String _dirName = 'dna_auto_backups';
  static const int _keepDays = 5;
  static const String _filePrefix = 'auto_backup_';

  /// 解析「软件外部」目录：优先公共下载目录（卸载后保留），失败回退到应用文档目录。
  static Future<Directory> _resolveDir() async {
    Directory pick(Directory base) =>
        Directory(path.join(base.path, _dirName));
    try {
      final Directory? downloads = await getDownloadsDirectory();
      if (downloads != null) {
        return pick(downloads);
      }
    } catch (_) {
      // 忽略，走回退
    }
    return pick(await getApplicationDocumentsDirectory());
  }

  static String _dayKey(DateTime d) {
    String p(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)}';
  }

  /// 每天首次进入应用时调用。若当天已备份（或已关闭）则直接返回。
  /// 设计为 fire-and-forget：调用方无需 await，失败也静默。
  static Future<void> maybeBackup(AppController controller) async {
    try {
      if (!controller.settings.autoBackup) return;

      final SettingsService service = controller.settingsService;
      final String today = _dayKey(DateTime.now());
      if (await service.getLastAutoBackupDate() == today) return;

      final result = await controller.exportAllData();
      if (!result.success || result.data == null) return;

      // 写入外部目录；公共下载目录受限于作用域存储时回退到应用文档目录。
      Directory dir = await _resolveDir();
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final String fileName = '$_filePrefix$today.zip';
      try {
        await File(path.join(dir.path, fileName)).writeAsBytes(result.data!);
      } catch (_) {
        dir = Directory(path.join(
          (await getApplicationDocumentsDirectory()).path,
          _dirName,
        ));
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        await File(path.join(dir.path, fileName)).writeAsBytes(result.data!);
      }

      await service.saveLastAutoBackupDate(today);
      await _prune(dir);
    } catch (_) {
      // 全程无感：任何异常都不提示、不阻断使用
    }
  }

  /// 仅保留最近 [_keepDays] 天的备份（文件名含 YYYY-MM-DD，字典序即时间序）。
  static Future<void> _prune(Directory dir) async {
    try {
      if (!await dir.exists()) return;
      final List<File> files = <File>[];
      await for (final FileSystemEntity e in dir.list()) {
        if (e is File &&
            path.basename(e.path).startsWith(_filePrefix) &&
            path.basename(e.path).endsWith('.zip')) {
          files.add(e);
        }
      }
      files.sort((File a, File b) =>
          path.basename(a.path).compareTo(path.basename(b.path)));
      if (files.length > _keepDays) {
        final List<File> toDelete = files.sublist(0, files.length - _keepDays);
        for (final File f in toDelete) {
          try {
            await f.delete();
          } catch (_) {
            // 删除失败忽略
          }
        }
      }
    } catch (_) {
      // 忽略
    }
  }
}
