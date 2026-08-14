import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import '../models/conversation.dart';
import '../models/ta.dart';
import '../models/user_identity.dart';
import '../models/world.dart';
import 'image_storage.dart';
import 'ta_export_import_service.dart';
import 'data_backup_models.dart';
export 'data_backup_models.dart';

/// 数据备份服务（导出/导入 ZIP）
class DataBackupService {
  static const int _version = 1;
  static const String _app = 'dna-client';
  static const String _imageDir = 'images';

  static void _addJsonFile(Archive archive, String name, Object data) {
    final JsonEncoder encoder = const JsonEncoder.withIndent('  ');
    final List<int> bytes = utf8.encode(encoder.convert(data));
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  static ArchiveFile? _findFile(Archive archive, String name) {
    for (final ArchiveFile file in archive.files) {
      if (file.name == name) return file;
    }
    return null;
  }

  /// 将全部数据（角色 / 世界 / 对话 / 身份，不含设置）打包为 ZIP 字节
  static Future<ExportImportResult<Uint8List>> buildZip({
    required List<TA> tas,
    required List<World> worlds,
    required List<Conversation> conversations,
    List<UserIdentity> identities = const <UserIdentity>[],
  }) async {
    try {
      final Archive archive = Archive();

      _addJsonFile(
        archive,
        'manifest.json',
        DataBackupManifest(
          version: _version,
          exportedAt: DateTime.now().toUtc().toIso8601String(),
          app: _app,
          type: 'full',
        ).toJson(),
      );

      // 角色：把图片引用替换为相对文件名，并把图片字节写入 ZIP（读取走 ImageStorage，跨平台一致）
      final List<Map<String, dynamic>> tasJson = <Map<String, dynamic>>[];
      for (final TA ta in tas) {
        final Map<String, dynamic> map = ta.toJson();
        final Map<String, String> portableImages = <String, String>{};
        for (final MapEntry<String, String> entry in ta.images.entries) {
          final String slot = entry.key;
          final String imagePath = entry.value;
          if (imagePath.isNotEmpty) {
            final Uint8List? bytes =
                await ImageStorage.instance.readBytes(imagePath);
            if (bytes != null) {
              // 用 TA id + slot + 原文件名拼接，避免不同 TA 引用同名图片时互相覆盖
              final String name =
                  '${ta.id}_${slot}_${path.basename(imagePath)}';
              portableImages[slot] = name;
              archive.addFile(
                ArchiveFile('$_imageDir/$name', bytes.length, bytes),
              );
            } else {
              portableImages[slot] = '';
            }
          } else {
            portableImages[slot] = '';
          }
        }
        map['images'] = portableImages;
        tasJson.add(map);
      }
      _addJsonFile(archive, 'tas.json', tasJson);
      _addJsonFile(
        archive,
        'worlds.json',
        worlds.map((World w) => w.toJson()).toList(),
      );
      _addJsonFile(
        archive,
        'conversations.json',
        conversations.map((Conversation c) => c.toJson()).toList(),
      );
      _addJsonFile(
        archive,
        'identities.json',
        identities.map((UserIdentity i) => i.toJson()).toList(),
      );

      final List<int> encoded = ZipEncoder().encode(archive);
      return ExportImportResult(
        success: true,
        data: Uint8List.fromList(encoded),
      );
    } catch (e) {
      return ExportImportResult(success: false, message: '导出失败：$e');
    }
  }

  /// 将全部数据流式打包为 ZIP 文件（IO 平台，避免整体载入内存导致 OOM）。
  ///
  /// 图片以 [InputFileStream] 直接引用磁盘文件，[ZipEncoder].encodeStream 边压缩边
  /// 写盘，内存峰值仅为一个文件的大小，而非整个 ZIP。返回写入的 ZIP 路径。
  /// Web 无文件系统，请使用 [buildZip]。
  static Future<ExportImportResult<String>> buildZipToFile(
    String zipPath, {
    required List<TA> tas,
    required List<World> worlds,
    required List<Conversation> conversations,
    List<UserIdentity> identities = const <UserIdentity>[],
  }) async {
    try {
      final Archive archive = Archive();

      _addJsonFile(
        archive,
        'manifest.json',
        DataBackupManifest(
          version: _version,
          exportedAt: DateTime.now().toUtc().toIso8601String(),
          app: _app,
          type: 'full',
        ).toJson(),
      );

      // 角色：把图片引用替换为相对文件名，并以磁盘文件流引用图片字节
      final List<Map<String, dynamic>> tasJson = <Map<String, dynamic>>[];
      for (final TA ta in tas) {
        final Map<String, dynamic> map = ta.toJson();
        final Map<String, String> portableImages = <String, String>{};
        for (final MapEntry<String, String> entry in ta.images.entries) {
          final String slot = entry.key;
          final String imagePath = entry.value;
          if (imagePath.isNotEmpty) {
            final File f = File(imagePath);
            if (await f.exists()) {
              // 用 TA id + slot + 原文件名拼接，避免不同 TA 引用同名图片时互相覆盖
              final String name =
                  '${ta.id}_${slot}_${path.basename(imagePath)}';
              portableImages[slot] = name;
              archive.addFile(
                ArchiveFile.stream(
                  '$_imageDir/$name',
                  InputFileStream(imagePath),
                ),
              );
            } else {
              portableImages[slot] = '';
            }
          } else {
            portableImages[slot] = '';
          }
        }
        map['images'] = portableImages;
        tasJson.add(map);
      }
      _addJsonFile(archive, 'tas.json', tasJson);
      _addJsonFile(
        archive,
        'worlds.json',
        worlds.map((World w) => w.toJson()).toList(),
      );
      _addJsonFile(
        archive,
        'conversations.json',
        conversations.map((Conversation c) => c.toJson()).toList(),
      );
      _addJsonFile(
        archive,
        'identities.json',
        identities.map((UserIdentity i) => i.toJson()).toList(),
      );

      final OutputFileStream output = OutputFileStream(zipPath);
      try {
        // autoClose: 每个文件写完后自动关闭其输入流
        ZipEncoder().encodeStream(archive, output, autoClose: true);
      } finally {
        await output.close();
      }
      return ExportImportResult(success: true, data: zipPath);
    } catch (e) {
      return ExportImportResult(success: false, message: '导出失败：$e');
    }
  }

  /// 仅将对话流式打包为 ZIP 文件（IO 平台）。
  ///
  /// 内存峰值仅为单个文件大小，避免整体载入内存。Web 无文件系统，
  /// 请使用 [buildConversationsZip]。
  static Future<ExportImportResult<String>> buildConversationsZipToFile(
    String zipPath, {
    required List<Conversation> conversations,
  }) async {
    try {
      final Archive archive = Archive();

      _addJsonFile(
        archive,
        'manifest.json',
        DataBackupManifest(
          version: _version,
          exportedAt: DateTime.now().toUtc().toIso8601String(),
          app: _app,
          type: 'conversations',
        ).toJson(),
      );
      _addJsonFile(
        archive,
        'conversations.json',
        conversations.map((Conversation c) => c.toJson()).toList(),
      );

      final OutputFileStream output = OutputFileStream(zipPath);
      try {
        ZipEncoder().encodeStream(archive, output, autoClose: true);
      } finally {
        await output.close();
      }
      return ExportImportResult(success: true, data: zipPath);
    } catch (e) {
      return ExportImportResult(success: false, message: '导出失败：$e');
    }
  }

  /// 仅将对话打包为 ZIP 字节
  static Future<ExportImportResult<Uint8List>> buildConversationsZip({
    required List<Conversation> conversations,
  }) async {
    try {
      final Archive archive = Archive();

      _addJsonFile(
        archive,
        'manifest.json',
        DataBackupManifest(
          version: _version,
          exportedAt: DateTime.now().toUtc().toIso8601String(),
          app: _app,
          type: 'conversations',
        ).toJson(),
      );
      _addJsonFile(
        archive,
        'conversations.json',
        conversations.map((Conversation c) => c.toJson()).toList(),
      );

      final List<int> encoded = ZipEncoder().encode(archive);
      return ExportImportResult(
        success: true,
        data: Uint8List.fromList(encoded),
      );
    } catch (e) {
      return ExportImportResult(success: false, message: '导出失败：$e');
    }
  }

  /// 解析 ZIP 字节（Web 平台使用），返回结构化的备份数据。
  ///
  /// 内部用流式解码 [ZipDecoder].decodeStream，图片字节采用懒加载闭包，
  /// 只有访问时才解压单个文件，避免整包与所有图片同时驻留内存。
  static ExportImportResult<ParsedBackup> parseZip(Uint8List bytes) {
    return _parseArchive(
      ZipDecoder().decodeStream(InputMemoryStream(bytes)),
      dispose: null,
    );
  }

  /// 从文件路径流式解析 ZIP（IO 平台使用）。
  ///
  /// 基于 [InputFileStream] 按需读取文件内容，zip 与图片不会整体载入内存。
  /// 返回的 [ParsedBackup.dispose] 需在导入流程结束后调用以关闭文件流。
  static ExportImportResult<ParsedBackup> parseZipFile(String path) {
    final InputFileStream input = InputFileStream(path);
    try {
      final ExportImportResult<ParsedBackup> result = _parseArchive(
        ZipDecoder().decodeStream(input),
        dispose: () => input.close(),
      );
      if (!result.success) {
        input.close();
      }
      return result;
    } catch (e) {
      input.close();
      return ExportImportResult(success: false, message: '解析失败：$e');
    }
  }

  static ExportImportResult<ParsedBackup> _parseArchive(
    Archive archive, {
    Future<void> Function()? dispose,
  }) {
    try {
      Map<String, dynamic> readJson(String name) {
        final ArchiveFile? file = _findFile(archive, name);
        if (file == null) {
          throw Exception('缺少文件：$name');
        }
        final Object? decoded = jsonDecode(utf8.decode(file.content as List<int>));
        if (decoded is! Map<String, dynamic>) {
          throw Exception('文件格式错误：$name');
        }
        return decoded;
      }

      List<dynamic> readJsonList(String name) {
        final ArchiveFile? file = _findFile(archive, name);
        if (file == null) {
          return <dynamic>[];
        }
        final Object? decoded = jsonDecode(utf8.decode(file.content as List<int>));
        return decoded is List<dynamic> ? decoded : <dynamic>[];
      }

      final DataBackupManifest manifest =
          DataBackupManifest.fromJson(readJson('manifest.json'));
      if (manifest.version > _version) {
        return ExportImportResult(
          success: false,
          message: '不支持的备份版本：${manifest.version}（当前支持：$_version）',
        );
      }

      final List<TA> tas = readJsonList('tas.json')
          .whereType<Map<String, dynamic>>()
          .map(TA.fromJson)
          .toList();
      final List<World> worlds = readJsonList('worlds.json')
          .whereType<Map<String, dynamic>>()
          .map(World.fromJson)
          .toList();
      final List<Conversation> conversations = readJsonList('conversations.json')
          .whereType<Map<String, dynamic>>()
          .map(Conversation.fromJson)
          .toList();
      final List<UserIdentity> identities = readJsonList('identities.json')
          .whereType<Map<String, dynamic>>()
          .map(UserIdentity.fromJson)
          .toList();

      // 图片懒加载：仅在落盘时逐个解压，避免所有图片同时驻留内存。
      // 闭包捕获对应的 ArchiveFile，访问过一次后由调用方移除引用以便 GC。
      final Map<String, List<int> Function()> imageBytes =
          <String, List<int> Function()>{};
      for (final ArchiveFile file in archive.files) {
        if (file.isFile && file.name.startsWith('$_imageDir/')) {
          final String name = file.name.substring('$_imageDir/'.length);
          if (name.isNotEmpty) {
            imageBytes[name] = () => file.content as List<int>;
          }
        }
      }

      return ExportImportResult(
        success: true,
        data: ParsedBackup(
          manifest: manifest,
          tas: tas,
          worlds: worlds,
          conversations: conversations,
          identities: identities,
          imageBytes: imageBytes,
          dispose: dispose,
        ),
      );
    } catch (e) {
      return ExportImportResult(success: false, message: '解析失败：$e');
    }
  }

  /// 解析仅含对话的 ZIP（也兼容全量包，只提取其中的对话）。
  ///
  /// 使用流式解码 [ZipDecoder].decodeStream，避免整包一次性载入内存。
  static ExportImportResult<List<Conversation>> parseConversationsZip(
    Uint8List bytes,
  ) {
    try {
      final Archive archive =
          ZipDecoder().decodeStream(InputMemoryStream(bytes));
      final ArchiveFile? file = _findFile(archive, 'conversations.json');
      if (file == null) {
        return const ExportImportResult(
          success: false,
          message: '缺少文件：conversations.json',
        );
      }
      final Object? decoded = jsonDecode(utf8.decode(file.content as List<int>));
      if (decoded is! List<dynamic>) {
        return const ExportImportResult(
          success: false,
          message: '文件格式错误：conversations.json',
        );
      }
      final List<Conversation> conversations = decoded
          .whereType<Map<String, dynamic>>()
          .map(Conversation.fromJson)
          .toList();
      return ExportImportResult(success: true, data: conversations);
    } catch (e) {
      return ExportImportResult(success: false, message: '解析失败：$e');
    }
  }

  /// 将 ZIP 中的图片字节写入平台存储，返回补全 images 的 TA 列表。
  ///
  /// [imageBytes] 为懒加载闭包表，逐个解压写盘后即移除引用，让底层
  /// ArchiveFile 与解压缓存可被 GC，避免所有图片同时驻留内存。
  /// [taDirPath] 为历史参数（IO 平台旧实现用），已由 [ImageStorage] 统一管理目录，
  /// 传空串即可。
  static Future<List<TA>> resolveTasImages(
    List<TA> tas,
    Map<String, List<int> Function()> imageBytes,
    String taDirPath,
  ) async {
    final List<TA> result = <TA>[];
    for (final TA ta in tas) {
      final Map<String, String> resolved = <String, String>{};
      for (final MapEntry<String, String> entry in ta.images.entries) {
        final String slot = entry.key;
        final String rel = entry.value;
        if (rel.isEmpty) {
          resolved[slot] = '';
          continue;
        }
        final List<int> Function()? loader = imageBytes[rel];
        if (loader == null) {
          resolved[slot] = '';
          continue;
        }
        final List<int> bytes = loader();
        // 写盘后移除引用，使 ArchiveFile 及其解压缓存可被回收
        imageBytes.remove(rel);
        final String ext = path.extension(rel);
        final String ref = await ImageStorage.instance.saveBytes(
          taId: ta.id,
          slot: slot,
          bytes: Uint8List.fromList(bytes),
          ext: ext.isEmpty ? null : ext,
        );
        resolved[slot] = ref;
      }
      result.add(ta.copyWith(images: resolved));
    }
    return result;
  }
}
