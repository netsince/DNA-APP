import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/user_identity.dart';
import 'ta_export_import_models.dart';
export 'ta_export_import_models.dart';

/// 身份导出导入服务（剪贴板文本格式，与世界观类似）
class IdentityExportImportService {
  static const int _currentVersion = 1;

  /// 将身份导出为带标识的 JSON 字符串，便于与角色卡等其他导出格式区分。
  static ExportImportResult<String> exportIdentity(UserIdentity identity) {
    try {
      final Map<String, dynamic> package = <String, dynamic>{
        'version': _currentVersion,
        'exportType': 'identity',
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'identity': identity.toJson(),
      };
      final String jsonString =
          const JsonEncoder.withIndent('  ').convert(package);
      return ExportImportResult(success: true, data: jsonString);
    } catch (e) {
      return ExportImportResult(success: false, message: '导出失败: $e');
    }
  }

  /// 从 JSON 字符串导入身份。
  ///
  /// 兼容两种格式：
  /// 1. 本应用导出的带标识格式（含 identity/exportType 字段）
  /// 2. 直接是身份 JSON（含 name/persona 字段）
  static ExportImportResult<UserIdentity> importIdentity(String jsonString) {
    try {
      final dynamic decoded = jsonDecode(jsonString);
      if (decoded is! Map<String, dynamic>) {
        return const ExportImportResult(
          success: false,
          message: '无效的身份数据格式',
        );
      }

      final Map<String, dynamic>? identityJson = decoded['identity'] is Map
          ? (decoded['identity'] as Map).cast<String, dynamic>()
          : null;
      if (identityJson != null) {
        return ExportImportResult(
          success: true,
          data: UserIdentity.fromJson(identityJson),
        );
      }

      // 兼容直接是身份 JSON 的情况
      if (decoded.containsKey('name') || decoded.containsKey('persona')) {
        return ExportImportResult(
          success: true,
          data: UserIdentity.fromJson(decoded.cast<String, dynamic>()),
        );
      }

      return const ExportImportResult(
        success: false,
        message: '未找到身份数据',
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
      final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
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
