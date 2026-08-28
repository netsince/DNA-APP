import 'dialogue_style.dart';

class TA {
  const TA({
    required this.id,
    required this.name,
    required this.gender,
    required this.persona,
    required this.intro,
    required this.opening,
    required this.tags,
    required this.images,
    required this.dialogueStyle,
    this.archived = false,
    this.originalLink,
    this.protection,
    this.voiceSeed,
    this.authorNote,
    this.authorNoteInterval = 0,
    this.musicPath,
  });

  final String id;
  final String name;
  final String gender;
  final String persona;
  final String intro;
  final String opening;
  final List<String> tags;
  final Map<String, String> images;
  final List<DialogueTurn> dialogueStyle;
  final bool archived;
  final String? originalLink;

  /// 该角色固定的语音合成 seed（未设置时用全局 seed）。
  final int? voiceSeed;
  /// 隐蔽列：完整存平台注入的溯源包（originalLink / _lk / 图片槽 fx、dataverification / Tips）。
  /// 客户端只存不编，导出时原样透传，UI 不展示，避免溯源信息失真。
  final Map<String, dynamic>? protection;

  /// 该角色绑定的作者注释（Author's Note）。选填：留空则不注入。
  final String? authorNote;

  /// 该角色作者注释的注入间隔（每多少条历史消息注入一次），0 表示禁用。
  final int authorNoteInterval;

  /// 该角色绑定的背景音乐文件路径（应用私有目录内）。
  ///
  /// ⚠️ 故意设计：此字段**只**用于本地持久化（Hive）与「全量 ZIP 备份/恢复」，
  /// **绝不**写入角色卡导出 JSON（`TaExportImportService.exportCharacter`），
  /// 导入角色卡时也**不识别**该字段。原因：音乐文件体积大，若塞进导出 JSON
  /// 走 Base64 会把导出包/备份撑爆。因此背景音乐只在本地随角色存在，
  /// 导出/分享角色卡到其它端时不会带上音乐。
  final String? musicPath;

  TA copyWith({
    String? id,
    String? name,
    String? gender,
    String? persona,
    String? intro,
    String? opening,
    List<String>? tags,
    Map<String, String>? images,
    List<DialogueTurn>? dialogueStyle,
    bool? archived,
    String? originalLink,
    Map<String, dynamic>? protection,
    int? voiceSeed,
    String? authorNote,
    int? authorNoteInterval,
    String? musicPath,
  }) {
    return TA(
      id: id ?? this.id,
      name: name ?? this.name,
      gender: gender ?? this.gender,
      persona: persona ?? this.persona,
      intro: intro ?? this.intro,
      opening: opening ?? this.opening,
      tags: tags ?? this.tags,
      images: images ?? this.images,
      dialogueStyle: dialogueStyle ?? this.dialogueStyle,
      archived: archived ?? this.archived,
      originalLink: originalLink ?? this.originalLink,
      protection: protection ?? this.protection,
      voiceSeed: voiceSeed ?? this.voiceSeed,
      musicPath: musicPath ?? this.musicPath,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'gender': gender,
      'persona': persona,
      'intro': intro,
      'opening': opening,
      'tags': tags,
      'images': images,
      'dialogueStyle': dialogueStyle.map((DialogueTurn t) => t.toJson()).toList(),
      'archived': archived,
      'originalLink': originalLink,
      'protection': protection,
      'voiceSeed': voiceSeed,
      'authorNote': authorNote,
      'authorNoteInterval': authorNoteInterval,
      // musicPath 用于本地持久化（Hive）与全量 ZIP 备份。角色卡导出（exportCharacter）
      // 不经过本方法，因此不会把音乐塞进导出 JSON。
      'musicPath': musicPath,
    };
  }

  static TA fromJson(Map<String, dynamic> json) {
    final List<dynamic>? raw = json['dialogueStyle'] as List<dynamic>?;
    return TA(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',
      gender: (json['gender'] as String?) ?? '无性',
      persona: (json['persona'] as String?) ?? '',
      intro: (json['intro'] as String?) ?? '',
      opening: (json['opening'] as String?) ?? '',
      tags: (json['tags'] as List?)?.whereType<String>().toList() ?? <String>[],
      images: switch (json['images']) {
        Map m => m.map((key, value) => MapEntry('$key', '$value')),
        _ => <String, String>{},
      },
      dialogueStyle: raw == null
          ? <DialogueTurn>[]
          : raw.whereType<Map<String, dynamic>>().map(DialogueTurn.fromJson).toList(),
      archived: (json['archived'] as bool?) ?? false,
      originalLink: json['originalLink'] as String?,
      protection: json['protection'] as Map<String, dynamic>?,
      voiceSeed: json['voiceSeed'] as int?,
      authorNote: json['authorNote'] as String?,
      authorNoteInterval: (json['authorNoteInterval'] as int?) ?? 0,
      // 本地持久化 / 全量备份恢复时读回 musicPath；角色卡导入（importCharacter）
      // 不经过本方法，因此不会从外部导入包中识别音乐字段。
      musicPath: json['musicPath'] as String?,
    );
  }
}
