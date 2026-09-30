import 'package:dna/models/dialogue_style.dart';
import 'package:dna/models/ta.dart';

/// 岛上的角色卡。
///
/// 字段与主项目的 [TA] **本来就是同一套**（同一个生态、同一批人做的），
/// 差异只在命名风格：岛用 snake_case（`dialogue_style` / `author_note` /
/// `seed`），主项目用 camelCase（`dialogueStyle` / `authorNote` /
/// `voiceSeed`）。所以「导入到我家 / 发布到岛」本质上是**换键名**，
/// 不是数据转换 —— 这是合并后能立刻兑现的最大红利。
class IslandCard {
  const IslandCard({
    required this.id,
    required this.name,
    this.gender = '',
    this.persona = '',
    this.intro = '',
    this.opening = '',
    this.originalLink = '',
    this.coverFocus = '',
    this.status = '',
    this.tags = const <String>[],
    this.dialogue = const <DialogueTurn>[],
    this.images = const <String, String>{},
    this.authorName = '',
    this.authorUsername = '',
    this.authorNote,
    this.authorNoteInterval = 0,
    this.seed,
  });

  final String id;
  final String name;
  final String gender;
  final String persona;
  final String intro;
  final String opening;

  /// 卡片的原始出处（平台注入的溯源）。
  final String originalLink;

  /// 封面焦点（岛独有；发布时用）。
  final String coverFocus;
  final String status;
  final List<String> tags;
  final List<DialogueTurn> dialogue;

  /// 槽位 → 服务端图片路径或完整 URL。
  final Map<String, String> images;

  final String authorName;
  final String authorUsername;
  final String? authorNote;
  final int authorNoteInterval;

  /// 音色种子（主项目里叫 voiceSeed）。
  final int? seed;

  factory IslandCard.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> author = _asMap(json['author']);
    final List<DialogueTurn> dialogue = <DialogueTurn>[
      for (final dynamic turn in _asList(json['dialogue'] ?? json['dialogue_style']))
        if (turn is Map)
          DialogueTurn(
            user: _str(_asMap(turn)['user']),
            assistant: _str(_asMap(turn)['assistant']),
          ),
    ];
    return IslandCard(
      id: _str(json['id']),
      name: _str(json['name']),
      gender: _str(json['gender']),
      persona: _str(json['persona']),
      intro: _str(json['intro']),
      opening: _str(json['opening']),
      originalLink: _str(json['original_link'] ?? json['originalLink']),
      coverFocus: _str(json['cover_focus'] ?? json['coverFocus']),
      status: _str(json['status']),
      tags: <String>[
        for (final dynamic tag in _asList(json['tags']))
          if (tag != null) tag.toString(),
      ],
      dialogue: dialogue,
      images: <String, String>{
        for (final MapEntry<String, dynamic> e in _asMap(json['images']).entries)
          if (e.value is String && (e.value as String).isNotEmpty)
            e.key: e.value as String,
      },
      authorName: _str(author['nickname'] ?? author['display_name']),
      authorUsername: _str(author['username']),
      authorNote: json['author_note'] == null
          ? (json['authorNote'] as String?)
          : _str(json['author_note']),
      authorNoteInterval:
          int.tryParse(
            _str(json['author_note_interval'] ?? json['authorNoteInterval']),
          ) ??
          0,
      seed: int.tryParse(_str(json['seed'] ?? json['voiceSeed'])),
    );
  }

  /// 映射成主项目的 [TA]。
  ///
  /// [localImages] 是已经落到本地的图片槽位（下载/内嵌恢复之后的）。
  /// 没有图片也能成 TA —— 试聊不需要图，导入时再补。
  TA toTa({required String id, Map<String, String> localImages = const {}}) => TA(
    id: id,
    name: name,
    gender: gender.isEmpty ? '无性' : gender,
    persona: persona,
    intro: intro,
    opening: opening,
    tags: tags,
    images: localImages,
    dialogueStyle: dialogue,
    archived: false,
    originalLink: originalLink.isEmpty ? null : originalLink,
    voiceSeed: seed,
    authorNote: authorNote,
    authorNoteInterval: authorNoteInterval,
  );
}

/// 主项目的 [TA] → 岛的发卡 payload。
///
/// [imageDataUris] 是槽位 → `data:image/png;base64,...`（岛的后端就是收
/// 这个格式）；主项目导出角色卡时本来也产出同样的 data URI，所以这一步
/// 不需要重新编码，直接复用。
Map<String, dynamic> islandPublishPayload(
  TA ta, {
  required Map<String, String> imageDataUris,
  String authorUsername = '',
}) => <String, dynamic>{
  'name': ta.name,
  'gender': ta.gender,
  'persona': ta.persona,
  'intro': ta.intro,
  'opening': ta.opening,
  'tags': ta.tags,
  'dialogue_style': <Map<String, String>>[
    for (final DialogueTurn turn in ta.dialogueStyle)
      <String, String>{'user': turn.user, 'assistant': turn.assistant},
  ],
  'author_note': ta.authorNote ?? '',
  'author_note_interval': ta.authorNoteInterval,
  'seed': ta.voiceSeed,
  'original_link': ta.originalLink ?? '',
  'cover_focus': '',
  'user': authorUsername,
  'images': imageDataUris,
};

/// 岛导出的角色卡包 → 主项目导入器认识的形状。
///
/// 主项目的 `importCharacter` 只认两种：本应用格式（带 `character` /
/// `exportType` 外壳）与酒馆卡。岛的包是 snake_case 的扁平卡片，所以这里
/// **补一层外壳 + 把键名转成 camelCase**，之后就能直接交给现有的导入器
/// —— 溯源字段（protection / fx / dataverification）由它原样保留，
/// 不在这里重复实现。
///
/// 只改键名，**不动值**。
Map<String, dynamic> normalizeIslandPackage(Map<String, dynamic> raw) {
  final Map<String, dynamic> inner = _asMap(raw['character']);
  final Map<String, dynamic> card = inner.isNotEmpty ? inner : raw;
  // 溯源字段在主项目包里是**顶层**的：ExportPackage.fromJson 从顶层读
  // originalLink / _lk / Tips（ExportedCharacter 本身没有这个字段），
  // 所以必须从卡片里提上来，否则导入后 originalLink 会丢。
  final String originalLink = _str(
    card['originalLink'] ?? card['original_link'] ?? raw['originalLink'],
  );
  return <String, dynamic>{
    'exportType': _str(raw['exportType']).isEmpty
        ? 'character'
        : raw['exportType'],
    'version': raw['version'] ?? 1,
    if (originalLink.isNotEmpty) 'originalLink': originalLink,
    if (raw['_lk'] != null) '_lk': raw['_lk'],
    if (raw['Tips'] != null) 'Tips': raw['Tips'],
    'character': <String, dynamic>{
      for (final MapEntry<String, dynamic> e in card.entries)
        _camelKey(e.key): _normalizeImageSlot(e.key, e.value),
    },
  };
}

/// snake_case → camelCase（`dialogue_style` → `dialogueStyle`）。
///
/// 只对已知的例外做别名（岛的 `seed` 在主项目里叫 `voiceSeed`）。
String _camelKey(String key) {
  if (key == 'seed') {
    return 'voiceSeed';
  }
  if (key == 'dialogue') {
    return 'dialogueStyle';
  }
  if (!key.contains('_')) {
    return key;
  }
  final List<String> parts = key.split('_');
  final StringBuffer out = StringBuffer(parts.first);
  for (final String part in parts.skip(1)) {
    if (part.isEmpty) {
      continue;
    }
    out.write(part[0].toUpperCase());
    out.write(part.substring(1));
  }
  return out.toString();
}

/// 图片槽位：岛的详情里是「槽位 → 路径字符串」，主项目要的是
/// 「槽位 → {data, width, height, ...}」。字符串包一层 `data`，
/// 数据 URI 能解出图，普通 URL 会被跳过（调用方再退回下载）。
dynamic _normalizeImageSlot(String key, dynamic value) {
  if (key != 'images' || value is! Map) {
    return value;
  }
  return <String, dynamic>{
    for (final MapEntry<dynamic, dynamic> e in value.entries)
      e.key.toString(): e.value is String
          ? <String, dynamic>{'data': e.value}
          : e.value,
  };
}

Map<String, dynamic> _asMap(dynamic value) => value is Map
    ? value.map((dynamic k, dynamic v) => MapEntry(k.toString(), v))
    : <String, dynamic>{};

List<dynamic> _asList(dynamic value) => value is List ? value : <dynamic>[];

String _str(dynamic value) => value == null ? '' : value.toString();
