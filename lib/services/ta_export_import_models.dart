import '../models/ta.dart';
import '../models/dialogue_style.dart';

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

  TA toTA({Map<String, dynamic>? protection}) {
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
      originalLink: protection?['originalLink'] as String?,
      protection: protection,
    );
  }
}

/// 导出包数据
///
/// 溯源字段（originalLink / _lk / 图片槽 fx、dataverification / Tips）由平台注入，
/// 客户端只做「完整存储 + 原样透传」，绝不自行生成或改写，避免溯源信息失真。
class ExportPackage {
  const ExportPackage({
    required this.version,
    required this.exportType,
    required this.exportedAt,
    required this.compressed,
    required this.character,
    this.protection,
  });

  final int version;
  final String exportType;
  final String exportedAt;
  final bool compressed;
  final ExportedCharacter character;
  /// 平台注入的溯源包原样存储（originalLink / _lk / Tips / images[slot].fx、dataverification）
  final Map<String, dynamic>? protection;

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> result = {
      'version': version,
      'exportType': exportType,
      'exportedAt': exportedAt,
      'compressed': compressed,
      'character': character.toJson(),
    };

    // 原样放回平台注入的溯源字段（不重新生成、不改写）
    final p = protection;
    if (p != null && p.isNotEmpty) {
      if (p['originalLink'] != null) result['originalLink'] = p['originalLink'];
      if (p['_lk'] != null) result['_lk'] = p['_lk'];
      if (p['Tips'] != null) result['Tips'] = p['Tips'];
      final imgs = p['images'];
      if (imgs is Map) {
        final charImages = (result['character'] as Map<String, dynamic>)['images'];
        if (charImages is Map) {
          for (final slot in ['square', 'landscape', 'portrait']) {
            final slotP = imgs[slot];
            final img = charImages[slot];
            if (slotP is Map && img is Map) {
              final target = img as Map<String, dynamic>;
              if (slotP['fx'] != null) target['fx'] = slotP['fx'];
              if (slotP['dataverification'] != null) {
                target['dataverification'] = slotP['dataverification'];
              }
            }
          }
        }
      }
    }
    return result;
  }

  static ExportPackage fromJson(Map<String, dynamic> json) {
    // 完整保留溯源字段到 protection，原样透传，不解码、不丢弃
    final Map<String, dynamic> p = {};
    if (json['originalLink'] != null) p['originalLink'] = json['originalLink'];
    if (json['_lk'] != null) p['_lk'] = json['_lk'];
    if (json['Tips'] != null) p['Tips'] = json['Tips'];

    final charData = json['character'];
    if (charData is Map<String, dynamic> && charData['images'] is Map) {
      final imgs = <String, dynamic>{};
      final rawImgs = charData['images'] as Map;
      for (final slot in ['square', 'landscape', 'portrait']) {
        final img = rawImgs[slot];
        if (img is Map) {
          final slotP = <String, dynamic>{};
          if (img['fx'] != null) slotP['fx'] = img['fx'];
          if (img['dataverification'] != null) {
            slotP['dataverification'] = img['dataverification'];
          }
          if (slotP.isNotEmpty) imgs[slot] = slotP;
        }
      }
      if (imgs.isNotEmpty) p['images'] = imgs;
    }

    return ExportPackage(
      version: json['version'] as int? ?? 1,
      exportType: json['exportType'] as String? ?? 'single',
      exportedAt: json['exportedAt'] as String? ?? '',
      compressed: json['compressed'] as bool? ?? false,
      character: ExportedCharacter.fromJson(
        json['character'] as Map<String, dynamic>,
      ),
      protection: p.isNotEmpty ? p : null,
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
