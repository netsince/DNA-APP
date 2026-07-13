import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;

import '../models/conversation.dart';
import '../models/ta.dart';
import '../models/world.dart';
import 'ta_export_import_service.dart';

/// 备份清单
class DataBackupManifest {
  const DataBackupManifest({
    required this.version,
    required this.exportedAt,
    required this.app,
    this.type = 'full',
  });

  final int version;
  final String exportedAt;
  final String app;

  /// 备份类型：'full'（全量：角色/世界/对话）或 'conversations'（仅对话）
  final String type;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': version,
        'exportedAt': exportedAt,
        'app': app,
        'type': type,
      };

  factory DataBackupManifest.fromJson(Map<String, dynamic> json) {
    return DataBackupManifest(
      version: (json['version'] as int?) ?? 1,
      exportedAt: (json['exportedAt'] as String?) ?? '',
      app: (json['app'] as String?) ?? '',
      type: (json['type'] as String?) ?? 'full',
    );
  }
}

/// 解析后的备份数据（图片尚未写入磁盘，仅保留在内存中）
class ParsedBackup {
  const ParsedBackup({
    required this.manifest,
    required this.tas,
    required this.worlds,
    required this.conversations,
    required this.imageBytes,
  });

  final DataBackupManifest manifest;
  final List<TA> tas; // 其中的 images 为相对文件名
  final List<World> worlds;
  final List<Conversation> conversations;
  final Map<String, List<int>> imageBytes;
}

/// 导入结果报告
class DataImportReport {
  const DataImportReport({
    required this.replaced,
    required this.tasCount,
    required this.worldsCount,
    required this.conversationsCount,
    this.backupPath,
    this.backupError,
  });

  final bool replaced;
  final int tasCount;
  final int worldsCount;
  final int conversationsCount;
  final String? backupPath;
  final String? backupError;
}

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

  /// 将全部数据（角色 / 世界 / 对话，不含设置）打包为 ZIP 字节
  static Future<ExportImportResult<Uint8List>> buildZip({
    required List<TA> tas,
    required List<World> worlds,
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
          type: 'full',
        ).toJson(),
      );

      // 角色：把图片的绝对路径替换为相对文件名，并把图片字节写入 ZIP
      final List<Map<String, dynamic>> tasJson = <Map<String, dynamic>>[];
      for (final TA ta in tas) {
        final Map<String, dynamic> map = ta.toJson();
        final Map<String, String> portableImages = <String, String>{};
        ta.images.forEach((String slot, String imagePath) {
          if (imagePath.isNotEmpty) {
            final File file = File(imagePath);
            if (file.existsSync()) {
              final String name = path.basename(imagePath);
              portableImages[slot] = name;
              final List<int> bytes = file.readAsBytesSync();
              archive.addFile(ArchiveFile('$_imageDir/$name', bytes.length, bytes));
            } else {
              portableImages[slot] = '';
            }
          } else {
            portableImages[slot] = '';
          }
        });
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

      final List<int> encoded = ZipEncoder().encode(archive);
      return ExportImportResult(
        success: true,
        data: Uint8List.fromList(encoded),
      );
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

  /// 解析 ZIP，返回结构化的备份数据（图片尚未落盘）
  static ExportImportResult<ParsedBackup> parseZip(Uint8List bytes) {
    try {
      final Archive archive = ZipDecoder().decodeBytes(bytes);

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

      final Map<String, List<int>> imageBytes = <String, List<int>>{};
      for (final ArchiveFile file in archive.files) {
        if (file.isFile && file.name.startsWith('$_imageDir/')) {
          final String name = file.name.substring('$_imageDir/'.length);
          if (name.isNotEmpty) {
            imageBytes[name] = file.content as List<int>;
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
          imageBytes: imageBytes,
        ),
      );
    } catch (e) {
      return ExportImportResult(success: false, message: '解析失败：$e');
    }
  }

  /// 解析仅含对话的 ZIP（也兼容全量包，只提取其中的对话）
  static ExportImportResult<List<Conversation>> parseConversationsZip(
    Uint8List bytes,
  ) {
    try {
      final Archive archive = ZipDecoder().decodeBytes(bytes);
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

  /// 将相对文件名解析为磁盘路径，并把图片写入 tas 目录
  static List<TA> resolveTasImages(
    List<TA> tas,
    Map<String, List<int>> imageBytes,
    String taDirPath,
  ) {
    return tas.map((TA ta) {
      final Map<String, String> resolved = <String, String>{};
      ta.images.forEach((String slot, String rel) {
        if (rel.isEmpty) {
          resolved[slot] = '';
          return;
        }
        final List<int>? bytes = imageBytes[rel];
        if (bytes == null) {
          resolved[slot] = '';
          return;
        }
        final String outPath = path.join(taDirPath, rel);
        File(outPath).writeAsBytesSync(bytes);
        resolved[slot] = outPath;
      });
      return ta.copyWith(images: resolved);
    }).toList();
  }
}
