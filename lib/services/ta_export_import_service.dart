import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../models/ta.dart';
import '../models/dialogue_style.dart';
import '../utils/id_utils.dart';
import 'ta_export_import_models.dart';
export 'ta_export_import_models.dart';

/// 角色导出导入服务
class TaExportImportService {
  static const int _currentVersion = 1;
  static const String _exportTypeSingle = 'single';

  /// 导出角色为JSON字符串
  static Future<ExportImportResult<String>> exportCharacter(
    TA character, {
    bool compressImages = true,
    int maxImageDimension = 1024,
  }) async {
    try {
      final Map<String, ExportedImageInfo> exportedImages = {};

      // 处理图片
      for (final entry in character.images.entries) {
        final slot = entry.key;
        final path = entry.value;

        if (path.isEmpty) {
          exportedImages[slot] = const ExportedImageInfo(data: null);
          continue;
        }

        final file = File(path);
        if (!await file.exists()) {
          exportedImages[slot] = const ExportedImageInfo(data: null);
          continue;
        }

        Uint8List imageBytes;
        int width;
        int height;

        if (compressImages) {
          // 压缩图片
          final compressed = await FlutterImageCompress.compressWithFile(
            path,
            minWidth: maxImageDimension,
            minHeight: maxImageDimension,
            quality: 85,
          );
          imageBytes = compressed ?? await file.readAsBytes();

          // 获取压缩后的尺寸
          final decoded = img.decodeImage(imageBytes);
          width = decoded?.width ?? 0;
          height = decoded?.height ?? 0;
        } else {
          imageBytes = await file.readAsBytes();
          final decoded = img.decodeImage(imageBytes);
          width = decoded?.width ?? 0;
          height = decoded?.height ?? 0;
        }

        final base64String = base64Encode(imageBytes);
        final mimeType = _getMimeType(path);
        exportedImages[slot] = ExportedImageInfo(
          data: 'data:$mimeType;base64,$base64String',
          width: width,
          height: height,
        );
      }

      // 确保所有图片槽位都有值
      for (final slot in ['square', 'landscape', 'portrait']) {
        if (!exportedImages.containsKey(slot)) {
          exportedImages[slot] = const ExportedImageInfo(data: null);
        }
      }

      // 构建导出数据
      final exportedCharacter = ExportedCharacter(
        id: character.id,
        name: character.name,
        gender: character.gender,
        persona: character.persona,
        intro: character.intro,
        opening: character.opening,
        tags: character.tags,
        dialogueStyle: character.dialogueStyle
            .map((d) => {'user': d.user, 'assistant': d.assistant})
            .toList(),
        images: exportedImages,
      );

      final package = ExportPackage(
        version: _currentVersion,
        exportType: _exportTypeSingle,
        exportedAt: DateTime.now().toUtc().toIso8601String(),
        compressed: compressImages,
        character: exportedCharacter,
        protection: character.protection,
      );

      final jsonString = const JsonEncoder.withIndent('  ').convert(package.toJson());
      return ExportImportResult(success: true, data: jsonString);
    } catch (e) {
      return ExportImportResult(success: false, message: '导出失败: $e');
    }
  }

  /// 从JSON字符串导入角色。
  ///
  /// 兼容两种格式：
  /// 1. 本应用导出的格式（含 character/exportType 字段）
  /// 2. 酒馆（SillyTavern）角色卡 JSON（chara_card_v1/v2/v3）
  static ExportImportResult<ImportResult> importCharacter(String jsonString) {
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is! Map<String, dynamic>) {
        return const ExportImportResult(
          success: false,
          message: '无效的导出文件格式',
        );
      }

      // 优先尝试本应用格式
      if (decoded.containsKey('character') || decoded.containsKey('exportType')) {
        return _importOwnFormat(decoded);
      }

      // 酒馆（SillyTavern）角色卡
      if (_looksLikeSillyTavern(decoded)) {
        return _importSillyTavern(decoded);
      }

      return const ExportImportResult(
        success: false,
        message: '不支持的文件格式：既不是本应用导出文件，也不是酒馆角色卡',
      );
    } catch (e) {
      return ExportImportResult(success: false, message: '导入失败: $e');
    }
  }

  /// 解析本应用导出的格式
  static ExportImportResult<ImportResult> _importOwnFormat(Map<String, dynamic> decoded) {
    final version = decoded['version'] as int?;
    if (version == null || version > _currentVersion) {
      return ExportImportResult(
        success: false,
        message: '不支持的版本: $version (当前支持: $_currentVersion)',
      );
    }

    final package = ExportPackage.fromJson(decoded);
    final exported = package.character;

    // 构建TA对象（protection 含完整溯源包，原样保留，不编不改）
    final ta = exported.toTA(protection: package.protection);

    return ExportImportResult(
      success: true,
      data: ImportResult(
        ta: ta,
        idConflict: false, // 由调用方检查
        existingId: null,
      ),
    );
  }

  /// 判断是否为酒馆（SillyTavern）角色卡
  static bool _looksLikeSillyTavern(Map<String, dynamic> json) {
    final String spec = json['spec']?.toString() ?? '';
    if (spec.startsWith('chara_card')) return true;

    final dynamic data = json['data'];
    if (data is Map<String, dynamic> &&
        data.containsKey('name') &&
        (data.containsKey('description') || data.containsKey('first_mes'))) {
      return true;
    }

    // v1 扁平结构（无 spec 时）
    if (json.containsKey('name') &&
        !json.containsKey('exportType') &&
        !json.containsKey('character') &&
        (json.containsKey('description') || json.containsKey('first_mes'))) {
      return true;
    }

    return false;
  }

  /// 解析酒馆（SillyTavern）角色卡为 TA
  static ExportImportResult<ImportResult> _importSillyTavern(Map<String, dynamic> json) {
    // 定位数据节点：v2/v3 嵌套在 data 中，v1 为扁平结构
    final Map<String, dynamic> data;
    final dynamic rawData = json['data'];
    if (rawData is Map<String, dynamic>) {
      data = rawData;
    } else {
      data = json;
    }

    final String name = (data['name'] as String?) ?? '';
    final String description = (data['description'] as String?) ?? '';
    final String personality = (data['personality'] as String?) ?? '';
    final String scenario = (data['scenario'] as String?) ?? '';
    final String firstMes = (data['first_mes'] as String?) ?? '';
    final String mesExample = (data['mes_example'] as String?) ?? '';
    final List<String> tags = (data['tags'] as List?)
            ?.whereType<dynamic>()
            .map((dynamic e) => e.toString())
            .toList() ??
        <String>[];

    // 简介：将性格与情境合并，便于在本应用中保留信息
    final List<String> introParts = <String>[];
    if (personality.trim().isNotEmpty) introParts.add(personality.trim());
    if (scenario.trim().isNotEmpty) introParts.add(scenario.trim());
    final String intro = introParts.join('\n\n');

    // 示例对话：尽力解析为对话风格
    final List<DialogueTurn> dialogueStyle = _parseExampleDialogue(mesExample);

    final TA ta = TA(
      id: newId(),
      name: name,
      gender: '无性',
      persona: description,
      intro: intro,
      opening: firstMes,
      tags: tags,
      images: {},
      dialogueStyle: dialogueStyle,
    );

    return ExportImportResult(
      success: true,
      data: ImportResult(
        ta: ta,
        idConflict: false, // 由调用方检查
        existingId: null,
      ),
    );
  }

  /// 尽力解析酒馆示例对话（mes_example）为对话风格列表。
  ///
  /// 支持 {{user}}: / {{char}}: 标记格式，忽略多行续写与未知行。
  static List<DialogueTurn> _parseExampleDialogue(String raw) {
    if (raw.trim().isEmpty) return <DialogueTurn>[];
    final List<DialogueTurn> turns = <DialogueTurn>[];
    String? userText;
    for (final String rawLine in raw.split('\n')) {
      final String line = rawLine.trim();
      if (line.isEmpty || line == '<START>' || line == '<start>') continue;
      final RegExpMatch? userM =
          RegExp(r'^\{\{user\}\}\s*:?\s*(.*)$', caseSensitive: false).firstMatch(line);
      final RegExpMatch? charM =
          RegExp(r'^\{\{char\}\}\s*:?\s*(.*)$', caseSensitive: false).firstMatch(line);
      if (userM != null) {
        if (userText != null) {
          turns.add(DialogueTurn(user: userText, assistant: ''));
        }
        userText = userM.group(1)!.trim();
      } else if (charM != null) {
        final String assistant = charM.group(1)!.trim();
        turns.add(DialogueTurn(user: userText ?? '', assistant: assistant));
        userText = null;
      }
    }
    if (userText != null) {
      turns.add(DialogueTurn(user: userText, assistant: ''));
    }
    return turns;
  }

  /// 复制导出内容到剪贴板
  static Future<ExportImportResult<void>> copyToClipboard(String content) async {
    try {
      await Clipboard.setData(ClipboardData(text: content));
      return const ExportImportResult(success: true);
    } catch (e) {
      return ExportImportResult(success: false, message: '复制到剪贴板失败: $e');
    }
  }

  /// 从剪贴板读取导入内容
  static Future<ExportImportResult<String>> pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text == null || data!.text!.isEmpty) {
        return const ExportImportResult(
          success: false,
          message: '剪贴板为空或没有文本内容',
        );
      }
      return ExportImportResult(success: true, data: data.text);
    } catch (e) {
      return ExportImportResult(success: false, message: '读取剪贴板失败: $e');
    }
  }

  /// 从Base64数据保存图片到指定路径
  static Future<ExportImportResult<String>> saveBase64Image(
    String base64Data,
    String targetPath,
  ) async {
    try {
      // 解析 data URI
      String pureBase64 = base64Data;
      if (base64Data.contains(',')) {
        pureBase64 = base64Data.split(',')[1];
      }

      final bytes = base64Decode(pureBase64);
      final file = File(targetPath);
      await file.writeAsBytes(bytes);
      return ExportImportResult(success: true, data: targetPath);
    } catch (e) {
      return ExportImportResult(success: false, message: '保存图片失败: $e');
    }
  }

  /// 从 data URI 推断文件扩展名
  static String _getExtensionFromMimeType(String dataUri) {
    final String mime = dataUri.split(';').first.replaceFirst('data:', '');
    switch (mime) {
      case 'image/png':
        return '.png';
      case 'image/jpeg':
        return '.jpg';
      case 'image/webp':
        return '.webp';
      case 'image/gif':
        return '.gif';
      default:
        return '.jpg';
    }
  }

  /// 将导出包中的内嵌图片落盘到 ta 目录，返回补全 images 的 TA。
  ///
  /// [packageJson] 为本应用导出包（ExportPackage）结构。无内嵌图片时直接返回原 TA。
  static Future<ExportImportResult<TA>> restoreTaImages(
    TA ta,
    Map<String, dynamic> packageJson,
  ) async {
    try {
      final ExportPackage package = ExportPackage.fromJson(packageJson);

      final Directory docDir = await getApplicationDocumentsDirectory();
      final Directory taDir = Directory(path.join(docDir.path, 'tas'));
      if (!await taDir.exists()) {
        await taDir.create(recursive: true);
      }

      final Map<String, String> newImages = <String, String>{};
      for (final MapEntry<String, ExportedImageInfo> entry
          in package.character.images.entries) {
        final String slot = entry.key;
        final ExportedImageInfo imageInfo = entry.value;
        if (imageInfo.data != null && imageInfo.data!.isNotEmpty) {
          final String ext = _getExtensionFromMimeType(imageInfo.data!);
          final String fileName = '${ta.id}_$slot$ext';
          final String targetPath = path.join(taDir.path, fileName);
          final ExportImportResult<String> save =
              await saveBase64Image(imageInfo.data!, targetPath);
          if (save.success) {
            newImages[slot] = targetPath;
          }
        }
      }

      return ExportImportResult(
        success: true,
        data: ta.copyWith(images: newImages),
      );
    } catch (e) {
      return ExportImportResult(success: false, message: '恢复角色图片失败：$e');
    }
  }

  /// 获取MIME类型
  static String _getMimeType(String path) {
    final ext = path.toLowerCase();
    if (ext.endsWith('.png')) return 'image/png';
    if (ext.endsWith('.jpg') || ext.endsWith('.jpeg')) return 'image/jpeg';
    if (ext.endsWith('.webp')) return 'image/webp';
    if (ext.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }
}
