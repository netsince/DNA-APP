import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import '../models/ta.dart';
import '../models/dialogue_style.dart';

String _obfuscate(String str) {
  final hex = str.codeUnits.map((c) => c.toRadixString(16).padLeft(2, '0')).join();
  String result = '';
  for (int i = 0; i < hex.length; i += 2) {
    result = hex.substring(i, i + 2) + result;
  }
  return result;
}

String _deobfuscate(dynamic raw) {
  if (raw == null || raw.toString().trim().isEmpty) return '';
  final str = raw.toString();
  String reversed = '';
  for (int i = 0; i < str.length; i += 2) {
    reversed = str.substring(i, i + 2) + reversed;
  }
  try {
    return String.fromCharCodes(
      RegExp(r'.{1,2}').allMatches(reversed).map((m) => int.parse(m.group(0)!, radix: 16))
    );
  } catch (_) {
    return str;
  }
}

/// 导出导入结果
class ExportImportResult<T> {
  const ExportImportResult({
    required this.success,
    this.data,
    this.message,
  });

  final bool success;
  final T? data;
  final String? message;
}

/// 图片导出信息
class ExportedImageInfo {
  const ExportedImageInfo({
    required this.data,
    this.width,
    this.height,
    this.fx,
    this.dataverification,
  });

  final String? data;
  final int? width;
  final int? height;
  final String? fx;
  final String? dataverification;

  Map<String, dynamic> toJson() => {
        'data': data,
        'width': width,
        'height': height,
        if (fx != null) 'fx': fx,
        if (dataverification != null) 'dataverification': dataverification,
      };

  static ExportedImageInfo fromJson(Map<String, dynamic> json) {
    return ExportedImageInfo(
      data: json['data'] as String?,
      width: json['width'] as int?,
      height: json['height'] as int?,
      fx: json['fx'] as String?,
      dataverification: json['dataverification'] as String?,
    );
  }
}

/// 导出角色数据
class ExportedCharacter {
  const ExportedCharacter({
    required this.id,
    required this.name,
    required this.gender,
    required this.persona,
    required this.intro,
    required this.opening,
    required this.tags,
    required this.dialogueStyle,
    required this.images,
  });

  final String id;
  final String name;
  final String gender;
  final String persona;
  final String intro;
  final String opening;
  final List<String> tags;
  final List<Map<String, String>> dialogueStyle;
  final Map<String, ExportedImageInfo> images;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'gender': gender,
        'persona': persona,
        'intro': intro,
        'opening': opening,
        'tags': tags,
        'dialogueStyle': dialogueStyle,
        'images': images.map((key, value) => MapEntry(key, value.toJson())),
      };

  static ExportedCharacter fromJson(Map<String, dynamic> json) {
    final Map<String, ExportedImageInfo> images = {};
    final imagesRaw = json['images'];
    if (imagesRaw is Map<String, dynamic>) {
      for (final entry in imagesRaw.entries) {
        if (entry.value is Map<String, dynamic>) {
          images[entry.key] = ExportedImageInfo.fromJson(
            entry.value as Map<String, dynamic>,
          );
        }
      }
    }

    final dialogueRaw = json['dialogueStyle'] as List<dynamic>?;
    final List<Map<String, String>> dialogueStyle = [];
    if (dialogueRaw != null) {
      for (final item in dialogueRaw) {
        if (item is Map<String, dynamic>) {
          dialogueStyle.add({
            'user': (item['user'] as String?) ?? '',
            'assistant': (item['assistant'] as String?) ?? '',
          });
        }
      }
    }

    return ExportedCharacter(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',
      gender: (json['gender'] as String?) ?? '无性',
      persona: (json['persona'] as String?) ?? '',
      intro: (json['intro'] as String?) ?? '',
      opening: (json['opening'] as String?) ?? '',
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      dialogueStyle: dialogueStyle,
      images: images,
    );
  }

  TA toTA() {
    return TA(
      id: id,
      name: name,
      gender: gender,
      persona: persona,
      intro: intro,
      opening: opening,
      tags: tags,
      images: {},
      dialogueStyle: dialogueStyle
          .map((d) => DialogueTurn(
                user: d['user'] ?? '',
                assistant: d['assistant'] ?? '',
              ))
          .toList(),
    );
  }
}

/// 导出包数据
class ExportPackage {
  const ExportPackage({
    required this.version,
    required this.exportType,
    required this.exportedAt,
    required this.compressed,
    required this.character,
    this.originalLink,
  });

  final int version;
  final String exportType;
  final String exportedAt;
  final bool compressed;
  final ExportedCharacter character;
  final String? originalLink;

  Map<String, dynamic> toJson() {
    final encoded = originalLink != null && originalLink!.isNotEmpty
        ? _obfuscate(originalLink!)
        : null;

    final Map<String, dynamic> trackingData = {
      'pd': 'dna-client',
      'up': originalLink,
      'ct': DateTime.now().toUtc().toIso8601String(),
    };
    final dataverificationValue = _obfuscate(jsonEncode(trackingData));

    final Map<String, dynamic> result = {
      'version': version,
      'exportType': exportType,
      '_lk': encoded,
      'exportedAt': exportedAt,
      'compressed': compressed,
      'character': character.toJson(),
      'originalLink': originalLink,
    };

    // Embed hidden fx and dataverification fields in all images as triple backup
    if (encoded != null) {
      final charMap = result['character'] as Map<String, dynamic>;
      final imagesMap = charMap['images'] as Map<String, dynamic>?;
      if (imagesMap != null) {
        for (final targetKey in ['square', 'landscape', 'portrait']) {
          if (imagesMap[targetKey] is Map<String, dynamic>) {
            final img = imagesMap[targetKey] as Map<String, dynamic>;
            img['fx'] = encoded;
            img['dataverification'] = dataverificationValue;
          } else {
            imagesMap[targetKey] = {'fx': encoded, 'dataverification': dataverificationValue};
          }
        }
      }
    }

    return result;
  }

  static ExportPackage fromJson(Map<String, dynamic> json) {
    String? originalLink;

    // Priority 1: Check fx field inside images (most hidden)
    final charData = json['character'] as Map<String, dynamic>?;
    if (charData != null) {
      final imagesData = charData['images'] as Map<String, dynamic>?;
      if (imagesData != null) {
        for (final key in ['square', 'landscape', 'portrait']) {
          final img = imagesData[key] as Map<String, dynamic>?;
          if (img != null && img.containsKey('fx')) {
            String rawFx = img['fx'] as String? ?? '';
            // Strip the [random10] checksum suffix if present
            final bracketIdx = rawFx.indexOf('[');
            if (bracketIdx > 0) {
              rawFx = rawFx.substring(0, bracketIdx);
            }
            final decoded = _deobfuscate(rawFx);
            if (decoded.isNotEmpty) {
              originalLink = decoded;
              break;
            }
          }
        }
      }
    }

    // Priority 2: Check _lk field (obfuscated)
    if (originalLink == null && json.containsKey('_lk')) {
      final decoded = _deobfuscate(json['_lk']);
      if (decoded.isNotEmpty) originalLink = decoded;
    }

    // Priority 3: Check originalLink field (plaintext decoy)
    if (originalLink == null && json.containsKey('originalLink')) {
      final raw = json['originalLink'] as String?;
      if (raw != null && raw.isNotEmpty) originalLink = raw;
    }

    return ExportPackage(
      version: json['version'] as int? ?? 1,
      exportType: json['exportType'] as String? ?? 'single',
      exportedAt: json['exportedAt'] as String? ?? '',
      compressed: json['compressed'] as bool? ?? false,
      character: ExportedCharacter.fromJson(
        json['character'] as Map<String, dynamic>,
      ),
      originalLink: originalLink,
    );
  }
}

/// 导入结果
class ImportResult {
  const ImportResult({
    required this.ta,
    required this.idConflict,
    required this.existingId,
  });

  final TA ta;
  final bool idConflict;
  final String? existingId;
}

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
      );

      final jsonString = const JsonEncoder.withIndent('  ').convert(package.toJson());
      return ExportImportResult(success: true, data: jsonString);
    } catch (e) {
      return ExportImportResult(success: false, message: '导出失败: $e');
    }
  }

  /// 从JSON字符串导入角色
  static ExportImportResult<ImportResult> importCharacter(String jsonString) {
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is! Map<String, dynamic>) {
        return const ExportImportResult(
          success: false,
          message: '无效的导出文件格式',
        );
      }

      final version = decoded['version'] as int?;
      if (version == null || version > _currentVersion) {
        return ExportImportResult(
          success: false,
          message: '不支持的版本: $version (当前支持: $_currentVersion)',
        );
      }

      final package = ExportPackage.fromJson(decoded);
      final exported = package.character;

      // 构建TA对象
      final ta = exported.toTA();

      return ExportImportResult(
        success: true,
        data: ImportResult(
          ta: ta,
          idConflict: false, // 由调用方检查
          existingId: null,
        ),
      );
    } catch (e) {
      return ExportImportResult(success: false, message: '导入失败: $e');
    }
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
