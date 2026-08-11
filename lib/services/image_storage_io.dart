import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/ta.dart';

/// TA 图片存储（IO 平台实现）。
///
/// 与旧实现保持一致：图片落盘到应用文档目录 `tas/` 下，
/// TA.images 中保存绝对路径，存量数据无需迁移。
class ImageStorage {
  ImageStorage._();

  static final ImageStorage instance = ImageStorage._();

  /// 从引用（绝对路径）读取图片字节；引用为空或文件不存在返回 null。
  Future<Uint8List?> readBytes(String ref) async {
    if (ref.isEmpty) return null;
    final File f = File(ref);
    if (!await f.exists()) return null;
    return f.readAsBytes();
  }

  /// 保存图片字节到 `<doc>/tas/<taId>_<slot>.<ext>`，返回绝对路径。
  Future<String> saveBytes({
    required String taId,
    required String slot,
    required Uint8List bytes,
    String? ext,
  }) async {
    final Directory dir = await _ensureTaDir();
    final String e = _normalizeExt(ext);
    final String targetPath = path.join(dir.path, '${taId}_$slot$e');
    final File targetFile = File(targetPath);
    if (await targetFile.exists()) {
      await targetFile.delete();
    }
    await targetFile.writeAsBytes(bytes, flush: true);
    return targetPath;
  }

  /// 删除引用对应的图片文件（幂等）。
  Future<void> delete(String ref) async {
    if (ref.isEmpty) return;
    final File f = File(ref);
    if (await f.exists()) {
      await f.delete();
    }
  }

  /// 清空全部 TA 图片（删除整个 tas 目录）。
  Future<void> clearAll() async {
    final Directory dir = await _ensureTaDir();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// 返回 TA 指定槽位的可显示 ImageProvider；无图返回 null。
  ImageProvider? providerFor(TA ta, String slot) {
    final String? ref = ta.images[slot];
    if (ref == null || ref.isEmpty) return null;
    return providerForRef(ref);
  }

  /// 根据引用（绝对路径）返回可显示 ImageProvider；引用为空返回 null。
  ImageProvider? providerForRef(String? ref) {
    if (ref == null || ref.isEmpty) return null;
    final File f = File(ref);
    if (!f.existsSync()) return null;
    return FileImage(f);
  }

  String _normalizeExt(String? ext) {
    final String e = (ext == null || ext.isEmpty) ? '.jpg' : ext;
    return e.startsWith('.') ? e : '.$e';
  }

  Future<Directory> _ensureTaDir() async {
    final Directory doc = await getApplicationDocumentsDirectory();
    final Directory dir = Directory(path.join(doc.path, 'tas'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
