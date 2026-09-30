import 'dart:convert';
import 'dart:typed_data';

import 'package:dna/models/ta.dart';
import 'package:dna/services/image_storage.dart';
import 'package:dna/services/ta_export_import_service.dart';
import 'package:dna/state/app_controller.dart';
import 'package:dna/utils/id_utils.dart';

import 'island_api.dart';
import 'island_card.dart';
import 'island_session.dart';

/// 「导入到我家 / 发布到岛」的落地实现。
///
/// 这一层刻意做薄：**能用现有服务就不自己写**。
/// * 导入走主项目成熟的角色卡导入器 —— 溯源字段（protection / fx /
///   dataverification）与内嵌图片都由它处理，不重复实现；
/// * 发布只是把 TA 的字段换个键名（两边的 schema 本来就是同一套）。
class IslandBridge {
  IslandBridge._();

  /// 把岛上的卡片导入「我家」，返回落库后的 TA。
  ///
  /// 两条路：
  /// 1. **导出包（首选）**：岛导出的包带平台溯源字段与内嵌图片，交给主项目
  ///    现有的导入器，信息最全；
  /// 2. **卡片详情 + 下载立绘（兜底）**：导出包不可用时，用详情字段建 TA，
  ///    再把立绘逐张下下来。
  ///
  /// 与编辑器里的策略保持一致：**ID 冲突永不覆盖**，自动换新 ID 导入为新角色。
  static Future<TA> importCard({
    required AppController controller,
    required IslandApi api,
    required IslandCard card,
  }) async {
    String? content;
    try {
      final String pkg = await api.exportCard(card.id);
      if (pkg.isNotEmpty) {
        final dynamic decoded = jsonDecode(pkg);
        if (decoded is Map<String, dynamic>) {
          content = jsonEncode(normalizeIslandPackage(decoded));
        }
      }
    } catch (_) {
      content = null;
    }

    TA? ta;
    Map<String, String> images = <String, String>{};
    if (content != null) {
      final ExportImportResult<ImportResult> result =
          TaExportImportService.importCharacter(content);
      if (result.success && result.data != null) {
        ta = result.data!.ta;
        images = await _saveEmbeddedImages(ta.id, content);
      }
    }
    ta ??= card.toTa(id: newId());

    // ID 冲突：永不覆盖，换新 ID 当成新角色导入（图片路径按 TA id 命名，
    // 换 id 不影响已落盘的文件）。
    if (controller.getTaById(ta.id) != null) {
      ta = ta.copyWith(id: newId());
    }

    // 兜底：导出包没给图（或没内嵌图）的槽位，从卡片详情里下载。
    for (final MapEntry<String, String> entry in card.images.entries) {
      if (images.containsKey(entry.key)) {
        continue;
      }
      final Uint8List? bytes = await api.tryFetchImage(entry.value);
      if (bytes == null || bytes.isEmpty) {
        continue;
      }
      images[entry.key] = await ImageStorage.instance.saveBytes(
        taId: ta.id,
        slot: entry.key,
        bytes: bytes,
        ext: _extOf(entry.value),
      );
    }

    final TA toSave = images.isEmpty ? ta : ta.copyWith(images: images);
    await controller.upsertTa(toSave);
    return toSave;
  }

  /// 把本地 TA 发布到岛，返回 (卡片 id, 审核状态)。
  static Future<({String id, String status})> publishTa({
    required IslandApi api,
    required TA ta,
  }) async {
    final Map<String, String> dataUris = await imageDataUris(ta);
    return api.publishCard(
      islandPublishPayload(
        ta,
        imageDataUris: dataUris,
        authorUsername: IslandSession.username,
      ),
    );
  }

  /// 读取本地立绘并转成 `data:` URI（岛的后端收这个格式）。
  static Future<Map<String, String>> imageDataUris(TA ta) async {
    final Map<String, String> out = <String, String>{};
    for (final MapEntry<String, String> entry in ta.images.entries) {
      final Uint8List? bytes = await ImageStorage.instance.readBytes(
        entry.value,
      );
      if (bytes == null || bytes.isEmpty) {
        continue;
      }
      out[entry.key] =
          'data:${_mimeOf(entry.value)};base64,${base64Encode(bytes)}';
    }
    return out;
  }

  /// 把导出包里内嵌的图片（data URI）落到本地，返回槽位 → 本地路径。
  static Future<Map<String, String>> _saveEmbeddedImages(
    String taId,
    String content,
  ) async {
    final Map<String, String> saved = <String, String>{};
    try {
      final dynamic decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        return saved;
      }
      final ExportPackage package = ExportPackage.fromJson(decoded);
      for (final MapEntry<String, ExportedImageInfo> entry
          in package.character.images.entries) {
        final String? data = entry.value.data;
        if (data == null || data.isEmpty) {
          continue;
        }
        final int comma = data.indexOf(',');
        if (comma < 0) {
          continue;
        }
        final Uint8List bytes;
        try {
          bytes = base64Decode(data.substring(comma + 1));
        } catch (_) {
          continue;
        }
        if (bytes.isEmpty) {
          continue;
        }
        saved[entry.key] = await ImageStorage.instance.saveBytes(
          taId: taId,
          slot: entry.key,
          bytes: bytes,
          ext: _extOf(data),
        );
      }
    } catch (_) {
      // 包结构不认识就当作"没有内嵌图"，交给调用方去下载兜底。
    }
    return saved;
  }

  /// 从 `data:image/png;base64,...` 或文件路径里取扩展名。
  static String _extOf(String raw) {
    final String lower = raw.toLowerCase();
    if (lower.contains('image/png')) {
      return '.png';
    }
    if (lower.contains('image/webp')) {
      return '.webp';
    }
    if (lower.contains('image/gif')) {
      return '.gif';
    }
    if (lower.contains('image/jpeg') || lower.contains('image/jpg')) {
      return '.jpg';
    }
    final int dot = lower.lastIndexOf('.');
    if (dot > 0 && dot > lower.length - 6) {
      return lower.substring(dot);
    }
    return '.png';
  }

  static String _mimeOf(String path) {
    final String lower = path.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    if (lower.endsWith('.gif')) {
      return 'image/gif';
    }
    return 'image/png';
  }
}
