import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/world.dart';
import 'ta_export_import_models.dart';
export 'ta_export_import_models.dart';

/// 世界观导出导入服务（剪贴板文本格式，无图片，比角色卡简单）
class WorldExportImportService {
  static const int _currentVersion = 1;

  /// 将世界导出为带标识的 JSON 字符串，便于与角色卡等其他导出格式区分。
  static ExportImportResult<String> exportWorld(World world) {
    try {
      final Map<String, dynamic> package = <String, dynamic>{
        'version': _currentVersion,
        'exportType': 'world',
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'world': world.toJson(),
      };
      final String jsonString =
          const JsonEncoder.withIndent('  ').convert(package);
      return ExportImportResult(success: true, data: jsonString);
    } catch (e) {
      return ExportImportResult(success: false, message: '导出失败: $e');
    }
  }

  /// 从 JSON 字符串导入世界。
  ///
  /// 兼容两种格式：
  /// 1. 本应用导出的带标识格式（含 world/exportType 字段）
  /// 2. 直接是 World 的 JSON（含 name/entries 字段）
  static ExportImportResult<World> importWorld(String jsonString) {
    try {
      final dynamic decoded = jsonDecode(jsonString);
      if (decoded is! Map<String, dynamic>) {
        return const ExportImportResult(
          success: false,
          message: '无效的世界数据格式',
        );
      }

      final Map<String, dynamic>? worldJson = decoded['world'] is Map
          ? (decoded['world'] as Map).cast<String, dynamic>()
          : null;
      if (worldJson != null) {
        return ExportImportResult(
          success: true,
          data: World.fromJson(worldJson),
        );
      }

      // 兼容直接是 World JSON 的情况
      if (decoded.containsKey('name') || decoded.containsKey('entries')) {
        return ExportImportResult(
          success: true,
          data: World.fromJson(decoded.cast<String, dynamic>()),
        );
      }

      return const ExportImportResult(
        success: false,
        message: '未找到世界数据',
      );
    } catch (e) {
      return ExportImportResult(success: false, message: '导入失败: $e');
    }
  }

  /// 复制内容到剪贴板
  static Future<ExportImportResult<void>> copyToClipboard(String content) async {
    try {
      await Clipboard.setData(ClipboardData(text: content));
      return const ExportImportResult(success: true);
    } catch (e) {
      return ExportImportResult(
        success: false,
        message: '复制到剪贴板失败: $e',
      );
    }
  }

  /// 从剪贴板读取内容
  static Future<ExportImportResult<String>> pasteFromClipboard() async {
    try {
      final ClipboardData? data =
          await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text == null || data!.text!.isEmpty) {
        return const ExportImportResult(
          success: false,
          message: '剪贴板为空或没有文本内容',
        );
      }
      return ExportImportResult(success: true, data: data.text);
    } catch (e) {
      return ExportImportResult(
        success: false,
        message: '读取剪贴板失败: $e',
      );
    }
  }
}
