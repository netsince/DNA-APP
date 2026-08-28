import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ta.dart';

class TaService {
  static const String _tasKey = 'tas_v1';

  /// 背景音乐默认大小上限：10MB。
  /// 未在设置中解锁时，超过该大小的音乐文件会被拒绝。
  static const int kMusicSizeLimitBytes = 10 * 1024 * 1024;

  /// 允许的背景音乐扩展名（小写）。
  static const List<String> kMusicAllowedExts = <String>['.mp3', '.m4a', '.aac', '.ogg', '.wav'];

  Future<List<TA>> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_tasKey);
    if (raw == null || raw.isEmpty) {
      return <TA>[];
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(TA.fromJson)
            .toList();
      }
    } catch (_) {}
    return <TA>[];
  }

  Future<void> save(List<TA> tas) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String raw = jsonEncode(tas.map((TA ta) => ta.toJson()).toList());
    await prefs.setString(_tasKey, raw);
  }

  Future<String> storeImage({
    required String sourcePath,
    required String taId,
    required String slot,
  }) async {
    final Directory dir = await _ensureTaDir();
    final String ext = path.extension(sourcePath).isEmpty ? '.jpg' : path.extension(sourcePath);
    final String fileName = '${taId}_$slot$ext';
    final String targetPath = path.join(dir.path, fileName);
    
    // 如果目标文件已存在，先删除
    final File targetFile = File(targetPath);
    if (await targetFile.exists()) {
      await targetFile.delete();
    }
    
    final File sourceFile = File(sourcePath);
    await sourceFile.copy(targetPath);
    return targetPath;
  }

  Future<Directory> _ensureTaDir() async {
    final Directory doc = await getApplicationDocumentsDirectory();
    final Directory dir = Directory(path.join(doc.path, 'tas'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 保存背景音乐文件到 `<文档>/tas/music_<taId><ext>`（每个 TA 固定一个音乐）。
  ///
  /// - 校验扩展名必须在 [kMusicAllowedExts] 内；
  /// - 默认限制大小 ≤ [kMusicSizeLimitBytes]（10MB），除非 [sizeLimitUnlocked] 为 true；
  /// - 若该 TA 已有旧音乐文件，先删除旧文件再拷贝新文件（避免磁盘堆积）。
  ///
  /// 返回新音乐文件的绝对路径；校验不通过或拷贝失败返回 null。
  Future<String?> storeMusic({
    required String sourcePath,
    required String taId,
    String? oldMusicPath,
    required bool sizeLimitUnlocked,
  }) async {
    try {
      final File source = File(sourcePath);
      if (!await source.exists()) return null;

      final String ext = path.extension(sourcePath).toLowerCase();
      if (!kMusicAllowedExts.contains(ext)) return null;

      final int length = await source.length();
      if (!sizeLimitUnlocked && length > kMusicSizeLimitBytes) return null;

      final Directory dir = await _ensureTaDir();
      final String targetPath = path.join(dir.path, 'music_$taId$ext');

      // 先删除旧音乐文件，避免多个扩展名残留
      if (oldMusicPath != null &&
          oldMusicPath.isNotEmpty &&
          oldMusicPath != targetPath) {
        final File oldFile = File(oldMusicPath);
        if (await oldFile.exists()) {
          await oldFile.delete();
        }
      }
      final File target = File(targetPath);
      if (await target.exists()) {
        await target.delete();
      }
      await source.copy(targetPath);
      return targetPath;
    } catch (_) {
      return null;
    }
  }

  /// 删除背景音乐文件（幂等）。空路径或文件不存在时直接返回。
  Future<void> deleteMusic(String? musicPath) async {
    if (musicPath == null || musicPath.isEmpty) return;
    try {
      final File f = File(musicPath);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {}
  }

  /// 保存背景音乐字节到 `<文档>/tas/music_<taId><ext>`（供全量备份恢复）。
  ///
  /// 直接写入字节，不做大小/扩展名校验（恢复的是本应用导出的备份，
  /// 已在备份时校验过）。返回新音乐文件的绝对路径。
  Future<String?> saveMusicBytes({
    required String taId,
    required Uint8List bytes,
    String? ext,
  }) async {
    try {
      final Directory dir = await _ensureTaDir();
      final String e = (ext == null || ext.isEmpty)
          ? '.mp3'
          : (ext.startsWith('.') ? ext : '.$ext');
      final String targetPath = path.join(dir.path, 'music_$taId$e');
      final File target = File(targetPath);
      if (await target.exists()) {
        await target.delete();
      }
      await target.writeAsBytes(bytes, flush: true);
      return targetPath;
    } catch (_) {
      return null;
    }
  }
}
